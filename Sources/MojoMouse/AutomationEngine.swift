import AppKit

final class AutomationEngine {
  static let shared = AutomationEngine()
  private let store: LibraryStore
  private let now: () -> Date
  private let frontmost: () -> String?
  private let discovery: () -> (identity: UInt64?, count: Int)
  private let makeSession: () throws -> MouseSession
  private let renderText: (String) throws -> [UInt8]
  let ownBundleID: String
  private let worker = DispatchQueue(label: "io.github.mkerkstra.mojomouse.rules")
  private var timer: Timer?
  private var observers: [NSObjectProtocol] = []
  private var debounce: DispatchWorkItem?
  private var busy = false
  private var needsReevaluation = false
  private(set) var policy = SwitchingState()
  private(set) var statusText = "Automatic switching is off."
  var onChange: (() -> Void)?

  init(
    store: LibraryStore = .shared, now: @escaping () -> Date = Date.init,
    frontmost: @escaping () -> String? = {
      NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    },
    discovery: @escaping () -> (identity: UInt64?, count: Int) = MouseConnection.discovery,
    makeSession: @escaping () throws -> MouseSession = { try MouseConnection() },
    renderText: @escaping (String) throws -> [UInt8] = { try DisplayPixels.render($0).bytes },
    ownBundleID: String = Bundle.main.bundleIdentifier ?? "io.github.mkerkstra.MojoMouse"
  ) {
    self.store = store
    self.now = now
    self.frontmost = frontmost
    self.discovery = discovery
    self.makeSession = makeSession
    self.renderText = renderText
    self.ownBundleID = ownBundleID
  }
  deinit {
    timer?.invalidate()
    debounce?.cancel()
    for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
  }
  func start() {
    let center = NSWorkspace.shared.notificationCenter
    observers.append(
      center.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
      ) { [weak self] _ in self?.schedule() })
    observers.append(
      center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
        [weak self] _ in self?.handleSleep()
      })
    observers.append(
      center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
        [weak self] _ in self?.handleWake()
      })
    timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
      self?.evaluate()
    }
    schedule()
  }
  func handleSleep() {
    policy.sleep()
    debounce?.cancel()
  }
  func handleWake() {
    policy.wake(at: now())
    schedule()
  }
  func settingsChanged(clearPause: Bool = false) {
    policy.changed(clearPause: clearPause)
    if policy.pausedUntil.map({ $0 > now() }) == true {
      statusText = pauseMessage()
    } else {
      statusText =
        ((try? store.read().automationEnabled) ?? false)
        ? "Rules enabled; return to another app to switch profiles." : "Automatic switching is off."
    }
    schedule()
    onChange?()
  }
  private func pauseMessage() -> String {
    guard let until = policy.pausedUntil else { return "Automatic switching is off." }
    return
      "Automatic switching paused until \(DateFormatter.localizedString(from:until,dateStyle:.none,timeStyle:.short))."
  }
  func pause(minutes: Int = 60) {
    guard (try? store.read().automationEnabled) == true else { return }
    policy.pause(at: now(), minutes: minutes)
    debounce?.cancel()
    statusText = pauseMessage()
    onChange?()
  }
  func resume() {
    policy.resume()
    schedule()
    onChange?()
  }
  func status() -> [String: Any] {
    [
      "enabled": (try? store.read().automationEnabled) ?? false,
      "paused": policy.pausedUntil.map { $0 > now() } ?? false, "message": statusText,
      "pausedUntil": policy.pausedUntil.map { ISO8601DateFormatter().string(from: $0) } as Any?
        ?? NSNull(),
    ]
  }
  private func schedule() {
    debounce?.cancel()
    policy.generation += 1
    let item = DispatchWorkItem { [weak self] in self?.evaluate() }
    debounce = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
  }
  private func finished() {
    busy = false
    if needsReevaluation {
      needsReevaluation = false
      schedule()
    }
  }
  func evaluate() {
    if busy {
      needsReevaluation = true
      return
    }
    guard !policy.suspended else { return }
    do {
      let library = try store.read()
      guard library.automationEnabled else {
        statusText = "Automatic switching is off."
        onChange?()
        return
      }
      if let until = policy.pausedUntil, until > now() { return }
      policy.pausedUntil = nil
      guard now() >= policy.retryAfter else { return }
      let app = frontmost()
      guard app != ownBundleID else { return }
      guard let (profile, ruleName) = library.selection(app: app, at: now()) else { return }
      let device = discovery()
      guard device.count == 1, let identity = device.identity else {
        policy.lastKey = nil
        statusText =
          device.count > 1
          ? "Connect only one supported mouse for automatic switching."
          : "Waiting for an MJ-189 over USB."
        onChange?()
        return
      }
      let key = try profile.activationKey(identity: identity)
      guard key != policy.lastKey else { return }
      let pixels = profile.display.mode == "text" ? try renderText(profile.display.text) : nil
      let token = policy.generation
      busy = true
      statusText = "Applying \(profile.name)…"
      onChange?()
      worker.async {
        do {
          guard self.discovery().identity == identity else {
            throw MouseFailure(message: "The mouse connection changed.")
          }
          let mouse = try self.makeSession()
          // A connection can wait behind a manual write. Recheck cancellation
          // only after acquiring that connection's process-wide USB lock.
          var valid = false
          DispatchQueue.main.sync { valid = self.policy.accepts(token: token, at: self.now()) }
          guard valid else {
            DispatchQueue.main.async {
              self.needsReevaluation = true
              self.finished()
            }
            return
          }
          _ = try ProfileController(store: self.store).apply(profile, to: mouse, textPixels: pixels)
          DispatchQueue.main.async {
            if token == self.policy.generation {
              self.policy.succeeded(key: key)
              self.statusText = "\(profile.name) · \(ruleName)"
              self.store.appendEvent("Automatic profile: \(profile.name) (\(ruleName))")
            } else {
              self.needsReevaluation = true
            }
            self.finished()
            self.onChange?()
          }
        } catch {
          DispatchQueue.main.async {
            if token == self.policy.generation {
              self.policy.failed(at: self.now())
              self.statusText = "Automatic switch failed: \(error.localizedDescription)"
              self.store.appendEvent(self.statusText)
            } else {
              self.needsReevaluation = true
            }
            self.finished()
            self.onChange?()
          }
        }
      }
    } catch {
      statusText = "Automatic switching stopped: \(error.localizedDescription)"
      onChange?()
    }
  }
}
