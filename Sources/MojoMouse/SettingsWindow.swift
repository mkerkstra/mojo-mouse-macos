import AppKit
import WebKit

final class SettingsWindow: NSWindowController, WKScriptMessageHandler, WKNavigationDelegate,
  WKUIDelegate
{
  private var web: WKWebView!
  private var documentURL: URL!
  private let queue = DispatchQueue(label: "io.github.mkerkstra.mojomouse.editor")
  private let store = LibraryStore.shared
  private var pending = false
  override init(window: NSWindow?) { super.init(window: window) }
  required init?(coder: NSCoder) { fatalError() }
  convenience init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1050, height: 760),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    window.title = "\(AppInfo.name) · Profiles & rules"
    window.minSize = NSSize(width: 850, height: 620)
    if AppInfo.appStore {
      window.setFrame(NSRect(x: 100, y: 100, width: 1280, height: 800), display: false)
    }
    window.center()
    self.init(window: window)
    let config = WKWebViewConfiguration()
    config.userContentController.add(self, name: "mojo")
    let preferences = (try? store.read().preferences) ?? [:]
    let data = try! JSONSerialization.data(withJSONObject: preferences)
    let configuration: [String: Any] = [
      "name": AppInfo.name, "experimental": AppInfo.allowsExperimental,
    ]
    let configData = try! JSONSerialization.data(withJSONObject: configuration)
    let script =
      "window.mojoPreferences = \(String(data:data,encoding:.utf8)!); window.mojoApp = \(String(data:configData,encoding:.utf8)!);"
    config.userContentController.addUserScript(
      WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    web = WKWebView(frame: .zero, configuration: config)
    web.navigationDelegate = self
    web.uiDelegate = self
    window.contentView = web
    documentURL = Bundle.main.url(forResource: "settings", withExtension: "html")!
    web.loadFileURL(documentURL, allowingReadAccessTo: documentURL.deletingLastPathComponent())
  }
  func webView(
    _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    decisionHandler(
      navigationAction.request.url?.standardizedFileURL == documentURL.standardizedFileURL
        ? .allow : .cancel)
  }
  func webView(
    _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void
  ) {
    let alert = NSAlert()
    alert.messageText = message
    alert.addButton(withTitle: "Continue")
    alert.addButton(withTitle: "Cancel")
    alert.beginSheetModal(for: window!) { completionHandler($0 == .alertFirstButtonReturn) }
  }
  func webView(
    _ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
    defaultText: String?, initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping (String?) -> Void
  ) {
    let alert = NSAlert()
    alert.messageText = prompt
    let field = NSTextField(string: defaultText ?? "")
    field.frame = NSRect(x: 0, y: 0, width: 400, height: 26)
    alert.accessoryView = field
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = field
    alert.beginSheetModal(for: window!) {
      completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil)
    }
  }
  private func result(_ id: Int, data: Any? = nil, error: String? = nil) {
    var response: [String: Any] = ["id": id, "ok": error == nil]
    if let data { response["data"] = data }
    if let error { response["error"] = error }
    guard let data = try? JSONSerialization.data(withJSONObject: response),
      let json = String(data: data, encoding: .utf8)
    else { return }
    web.evaluateJavaScript("window.receive(\(json))", completionHandler: nil)
  }
  private func object<T: Encodable>(_ value: T) throws -> Any {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
  }
  private func decode<T: Decodable>(_ type: T.Type, _ payload: Any) throws -> T {
    try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: payload))
  }
  private func bytes(_ value: Any?, count: Int) throws -> [UInt8] {
    guard let values = value as? [NSNumber], values.count == count,
      values.allSatisfy({
        $0.doubleValue.isFinite && $0.doubleValue.rounded() == $0.doubleValue
          && (0...255).contains($0.intValue)
      })
    else { throw MouseFailure(message: "Invalid mouse settings data.") }
    return values.map { UInt8($0.intValue) }
  }
  private func changed(clearPause: Bool = false) {
    NotificationCenter.default.post(name: Notification.Name("MojoLibraryChanged"), object: nil)
    AutomationEngine.shared.settingsChanged(clearPause: clearPause)
  }
  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    guard message.frameInfo.isMainFrame, message.webView === web,
      message.frameInfo.request.url?.standardizedFileURL == documentURL.standardizedFileURL,
      let body = message.body as? [String: Any], let id = body["id"] as? Int,
      let action = body["action"] as? String
    else { return }
    let payload = body["payload"] as? [String: Any] ?? [:]
    do {
      switch action {
      case "render":
        result(
          id, data: try DisplayPixels.render(payload["text"] as? String ?? "").bytes.map(Int.init))
        return
      case "library":
        result(id, data: try object(store.read()))
        return
      case "preference":
        guard let key = payload["key"] as? String, let value = payload["value"] as? String else {
          throw MouseFailure(message: "Invalid preference.")
        }
        guard key != "experimental" || value != "true" || AppInfo.allowsExperimental else {
          throw MouseFailure(message: "Experimental controls are unavailable in this build.")
        }
        try store.setPreference(key, value)
        result(id, data: true)
        return
      case "apps":
        let apps = NSWorkspace.shared.runningApplications.filter {
          $0.activationPolicy == .regular && $0.bundleIdentifier != nil
            && $0.bundleIdentifier != Bundle.main.bundleIdentifier
        }.map {
          ["name": $0.localizedName ?? $0.bundleIdentifier!, "bundleID": $0.bundleIdentifier!]
        }.sorted { ($0["name"] ?? "") < ($1["name"] ?? "") }
        result(id, data: apps)
        return
      case "automationStatus":
        result(id, data: AutomationEngine.shared.status())
        return
      case "pauseRules":
        AutomationEngine.shared.pause()
        result(id, data: AutomationEngine.shared.status())
        return
      case "resumeRules":
        AutomationEngine.shared.resume()
        result(id, data: AutomationEngine.shared.status())
        return
      case "events":
        result(id, data: store.events())
        return
      case "original":
        result(id, data: try object(store.original()))
        return
      case "saveProfile":
        let profile = try decode(NamedProfile.self, payload)
        try profile.validate()
        // Saving/importing is inert. Every device apply validates the requested
        // changes against the live mouse, including lighting-only scope merges.
        let library = try store.update { library in
          if let index = library.profiles.firstIndex(where: { $0.id == profile.id }) {
            library.profiles[index] = profile
          } else {
            library.profiles.append(profile)
          }
        }
        changed()
        result(id, data: try object(library))
        return
      case "deleteProfile":
        guard let profileID = payload["id"] as? String else {
          throw MouseFailure(message: "Choose a profile.")
        }
        let library = try store.update { library in
          guard library.fallbackProfileID != profileID,
            !library.rules.contains(where: { $0.profileID == profileID })
          else {
            throw MouseFailure(
              message: "Remove this profile from rules and fallback selection before deleting it.")
          }
          library.profiles.removeAll { $0.id == profileID }
        }
        changed()
        result(id, data: try object(library))
        return
      case "saveRules":
        let rules = try decode([ActivationRule].self, payload["rules"] ?? [])
        let enabled = payload["enabled"] as? Bool ?? false
        let fallback = payload["fallbackProfileID"] as? String
        let library = try store.update {
          $0.rules = rules
          $0.automationEnabled = enabled
          $0.fallbackProfileID = fallback
        }
        changed(clearPause: true)
        result(id, data: try object(library))
        return
      case "export":
        let data = try JSONSerialization.data(
          withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        guard data.count <= 1_000_000 else {
          throw MouseFailure(message: "The export is too large.")
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(AppInfo.name) profile.json"
        panel.beginSheetModal(for: window!) { response in
          do {
            if response == .OK, let url = panel.url {
              try data.write(to: url, options: .atomic)
              self.result(id, data: true)
            } else {
              self.result(id, data: false)
            }
          } catch { self.result(id, error: error.localizedDescription) }
        }
        return
      case "import":
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window!) { response in
          do {
            if response == .OK, let url = panel.url {
              let data = try Data(contentsOf: url)
              guard data.count <= 1_000_000 else {
                throw MouseFailure(message: "The profile file is too large.")
              }
              self.result(id, data: try JSONSerialization.jsonObject(with: data))
            } else {
              self.result(id, data: NSNull())
            }
          } catch { self.result(id, error: error.localizedDescription) }
        }
        return
      default: break
      }
    } catch {
      result(id, error: error.localizedDescription)
      return
    }
    guard !pending else {
      result(id, error: "A mouse operation is already running.")
      return
    }
    if ["macro", "rapidFire"].contains(action) || ((payload["liftOff"] as? Int) ?? 0) != 0 {
      guard AppInfo.allowsExperimental && (try? store.read().preferences["experimental"]) == "true"
      else {
        result(id, error: "Enable experimental controls in Advanced first.")
        return
      }
    }
    var rendered: [UInt8]?
    if action == "applySaved" {
      do {
        guard
          let profile = try store.read().profiles.first(where: { $0.id == payload["id"] as? String }
          )
        else { throw MouseFailure(message: "The saved profile no longer exists.") }
        if profile.display.mode == "text" {
          rendered = try DisplayPixels.render(profile.display.text).bytes
        }
      } catch {
        result(id, error: error.localizedDescription)
        return
      }
    }
    if action != "load" { AutomationEngine.shared.pause() }
    pending = true
    let textPixels = rendered
    queue.async {
      do {
        let mouse = try MouseConnection()
        let controller = ProfileController()
        var output: Any = true
        switch action {
        case "load":
          let snapshot = try controller.snapshot(mouse)
          try self.store.captureOriginal(snapshot)
          output = try self.object(snapshot)
        case "applySaved":
          guard
            let profile = try self.store.read().profiles.first(where: {
              $0.id == payload["id"] as? String
            })
          else { throw MouseFailure(message: "The saved profile no longer exists.") }
          output = try self.object(
            controller.apply(
              profile, to: mouse, textPixels: textPixels,
              experimental: AppInfo.allowsExperimental
                && (try self.store.read().preferences["experimental"]) == "true"))
        case "apply":
          let current = try controller.snapshot(mouse)
          guard current.data == (try self.bytes(payload["baseData"], count: 128)),
            current.buttons == (try self.bytes(payload["baseButtons"], count: 128)),
            current.rate == payload["baseRate"] as? Int
          else {
            throw MouseFailure(message: "The mouse changed. Reload before applying this draft.")
          }
          var snapshot = current
          snapshot.data = try self.bytes(payload["data"], count: 128)
          snapshot.buttons = try self.bytes(payload["buttons"], count: 128)
          guard let rate = payload["rate"] as? Int else {
            throw MouseFailure(message: "Choose a polling rate.")
          }
          snapshot.rate = rate
          let draft = NamedProfile(
            id: UUID().uuidString, name: "Manual draft", scope: "all", snapshot: snapshot,
            display: SideDisplay())
          let applied = try controller.apply(
            draft, to: mouse,
            experimental: AppInfo.allowsExperimental
              && (try self.store.read().preferences["experimental"]) == "true")
          if let height = payload["liftOff"] as? Int, height != 0 { try mouse.setLiftOff(height) }
          output = try self.object(applied)
        case "text": try mouse.sendTextPixels(self.bytes(payload["pixels"], count: 512))
        case "display":
          guard let mode = payload["mode"] as? Int else {
            throw MouseFailure(message: "Choose a display mode.")
          }
          if mode == -1 {
            try mouse.sendTextPixels([UInt8](repeating: 0, count: 512))
          } else {
            try mouse.setSideMode(mode)
          }
        case "macro":
          guard let slot = payload["slot"] as? Int else {
            throw MouseFailure(message: "Choose a macro slot.")
          }
          try mouse.sendMacro(slot: slot, data: try self.bytes(payload["data"], count: 128))
        case "rapidFire":
          guard let key = payload["key"] as? Int, let count = payload["count"] as? Int,
            let x = payload["x"] as? Int, let y = payload["y"] as? Int
          else { throw MouseFailure(message: "Enter valid rapid-fire settings.") }
          try mouse.setRapidFire(key: key, count: count, x: x, y: y)
        case "original": output = try self.object(self.store.original())
        default: throw MouseFailure(message: "Unknown app action.")
        }
        let response = output
        DispatchQueue.main.async {
          self.pending = false
          self.result(id, data: response)
        }
      } catch {
        DispatchQueue.main.async {
          self.pending = false
          self.result(id, error: error.localizedDescription)
        }
      }
    }
  }
}
