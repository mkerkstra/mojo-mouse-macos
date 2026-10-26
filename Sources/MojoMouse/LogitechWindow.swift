import AppKit

// Separate capability-based controls: MJ-189 profiles/rules cannot target these devices.
final class LogitechWindow: NSWindowController {
  private let worker = DispatchQueue(label: "io.github.mkerkstra.mojomouse.logitech")
  private let picker = NSPopUpButton()
  private let scanButton = NSButton(title: "Scan USB", target: nil, action: nil)
  private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
  private let optIn = NSButton(
    checkboxWithTitle: "Enable experimental controls for this session", target: nil, action: nil)
  private let liveButton = NSButton(title: "Use live controls", target: nil, action: nil)
  private let onboardButton = NSButton(title: "Use onboard settings", target: nil, action: nil)
  private let modeLabel = NSTextField(labelWithString: "No mouse selected")
  private let dpiField = NSTextField(string: "")
  private let dpiHelp = NSTextField(wrappingLabelWithString: "DPI capability has not been read.")
  private let dpiButton = NSButton(title: "Set DPI", target: nil, action: nil)
  private let ratePicker = NSPopUpButton()
  private let rateButton = NSButton(title: "Set rate", target: nil, action: nil)
  private let status = NSTextField(wrappingLabelWithString: "")
  private var devices: [LogitechDevice] = []
  private var state: LogitechState?
  private var busy = false

  init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 660, height: 720),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "Logitech mice · Preview"
    window.isReleasedWhenClosed = false
    window.center()
    super.init(window: window)
    build()
    scan()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  private func row(_ views: [NSView]) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .horizontal
    stack.spacing = 12
    stack.alignment = .centerY
    return stack
  }
  private func note(_ text: String) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: text)
    field.font = .systemFont(ofSize: 12)
    field.textColor = .secondaryLabelColor
    return field
  }
  private func bind(_ button: NSButton, _ action: Selector) {
    button.target = self
    button.action = action
    button.bezelStyle = .rounded
  }
  private func build() {
    bind(scanButton, #selector(scan))
    bind(refreshButton, #selector(refresh))
    bind(liveButton, #selector(live))
    bind(onboardButton, #selector(onboard))
    bind(dpiButton, #selector(setDPI))
    bind(rateButton, #selector(setRate))
    optIn.target = self
    optIn.action = #selector(updateControls)
    picker.target = self
    picker.action = #selector(refresh)
    picker.setAccessibilityLabel("Logitech mouse")
    dpiField.setAccessibilityLabel("Logitech DPI")
    dpiField.placeholderString = "DPI"
    ratePicker.setAccessibilityLabel("Logitech polling rate")
    dpiField.widthAnchor.constraint(equalToConstant: 130).isActive = true
    let heading = NSTextField(labelWithString: "A lighter setup for Logitech mice")
    heading.font = .systemFont(ofSize: 23, weight: .semibold)
    let devicesRow = row([picker, scanButton, refreshButton])
    picker.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let info = note(
      "Wired G502 Core, Spectrum and HERO; G403 and G102/G203 family. USB only. This preview has protocol tests but has not been tested on a physical Logitech mouse."
    )
    let modeInfo = note(
      "Live mode may change how DPI buttons work. Use onboard settings to return to your saved hardware profiles. Live values may remain until power cycling. The app never overwrites onboard profiles."
    )
    let permissionInfo = note(
      "Some Logitech interfaces need macOS Input Monitoring access. The app checks existing permission and does not request it automatically. See the guide for details."
    )
    let controlsInfo = note(
      "Only capabilities reported by your firmware are enabled. Lighting, button remapping, macros, saved profiles and app/time rules are currently available only for the MOJO MJ-189."
    )
    let buttons = row([liveButton, onboardButton])
    let dpiRow = row([NSTextField(labelWithString: "Pointer speed"), dpiField, dpiButton])
    let rateRow = row([NSTextField(labelWithString: "Polling rate"), ratePicker, rateButton])
    let guide = NSButton(
      title: "Compatibility & testing guide…", target: self, action: #selector(guide))
    guide.bezelStyle = .rounded
    status.font = .systemFont(ofSize: 12)
    status.textColor = .secondaryLabelColor
    status.maximumNumberOfLines = 4
    status.setAccessibilityRole(.staticText)
    let stack = NSStackView(views: [
      heading, info, devicesRow, optIn, modeLabel, buttons, modeInfo, permissionInfo,
      dpiRow, dpiHelp, rateRow, controlsInfo, guide, status,
    ])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 16
    stack.translatesAutoresizingMaskIntoConstraints = false
    window!.contentView!.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: window!.contentView!.leadingAnchor, constant: 28),
      stack.trailingAnchor.constraint(equalTo: window!.contentView!.trailingAnchor, constant: -28),
      stack.topAnchor.constraint(equalTo: window!.contentView!.topAnchor, constant: 24),
      stack.bottomAnchor.constraint(
        lessThanOrEqualTo: window!.contentView!.bottomAnchor, constant: -24),
    ])
    for view in [info, devicesRow, modeInfo, permissionInfo, dpiHelp, controlsInfo, status] {
      view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    updateControls()
  }
  @objc private func updateControls() {
    let enabled = !busy && AppInfo.allowsExperimental
    picker.isEnabled = enabled && !devices.isEmpty
    scanButton.isEnabled = enabled
    refreshButton.isEnabled = enabled && !devices.isEmpty
    optIn.isEnabled = enabled
    let writing = enabled && optIn.state == .on && state != nil
    liveButton.isEnabled = writing && state?.mode == 1
    // Recovery remains available after failed DPI/rate reads and without opt-in.
    onboardButton.isEnabled = enabled && !devices.isEmpty
    dpiField.isEnabled = writing && state?.hostControls == true && state?.dpi != nil
    dpiButton.isEnabled = dpiField.isEnabled
    ratePicker.isEnabled = writing && state?.hostControls == true && state?.rate != nil
    rateButton.isEnabled = ratePicker.isEnabled
  }
  private func show(_ value: LogitechState) {
    state = value
    modeLabel.stringValue =
      value.mode.map { $0 == 1 ? "Using onboard settings" : "Using live controls" }
      ?? "Live controls · no onboard mode feature"
    dpiField.stringValue = value.dpi.map(String.init) ?? ""
    dpiHelp.stringValue =
      value.dpiRange.map { "Supported DPI: \($0.label)" }
      ?? "Your firmware does not expose the supported DPI control."
    ratePicker.removeAllItems()
    for rate in value.rates {
      ratePicker.addItem(withTitle: "\(1000 / rate) Hz (\(rate) ms)")
      ratePicker.lastItem?.tag = rate
    }
    if let rate = value.rate { ratePicker.selectItem(withTag: rate) }
    updateControls()
  }
  @objc private func scan() {
    guard !busy, AppInfo.allowsExperimental else { return }
    busy = true
    state = nil
    updateControls()
    status.stringValue = "Looking for an allowlisted wired Logitech configuration interface…"
    worker.async {
      let devices = LogitechHID.discover()
      DispatchQueue.main.async {
        self.devices = devices
        self.picker.removeAllItems()
        for device in devices {
          self.picker.addItem(withTitle: "\(device.name) · \(device.usbID)")
        }
        self.busy = false
        if devices.isEmpty {
          self.modeLabel.stringValue = "No compatible wired Logitech interface found"
          self.dpiField.stringValue = ""
          self.ratePicker.removeAllItems()
          self.dpiHelp.stringValue = "Connect a listed mouse by USB, then scan again."
          self.status.stringValue =
            "Receivers, Bluetooth, G502 X and other models are not enabled in this preview."
          self.updateControls()
        } else {
          self.refresh()
        }
      }
    }
  }
  private func operate(
    _ message: String,
    _ action: @escaping (LogitechController) throws -> LogitechState?
  ) {
    guard !busy, AppInfo.allowsExperimental,
      devices.indices.contains(picker.indexOfSelectedItem)
    else { return }
    let identity = devices[picker.indexOfSelectedItem].identity
    busy = true
    updateControls()
    status.stringValue = message
    worker.async {
      let result = Result {
        let connection = try LogitechHID(identity: identity)
        return try action(LogitechController(connection))
      }
      DispatchQueue.main.async {
        self.busy = false
        switch result {
        case .success(let value):
          if let value {
            self.show(value)
            self.status.stringValue =
              "Settings read back from the mouse. Physical behavior still needs hardware testing."
          } else {
            self.state = nil
            self.optIn.state = .off
            self.modeLabel.stringValue = "Onboard mode confirmed"
            self.status.stringValue =
              "Returned to saved hardware settings. Refresh to read current DPI and rate."
            self.updateControls()
          }
        case .failure(let error):
          self.state = nil
          self.modeLabel.stringValue = "Refresh required"
          self.status.stringValue = error.localizedDescription
          self.updateControls()
        }
      }
    }
  }
  @objc private func refresh() {
    state = nil
    operate("Reading Logitech capabilities…") { try $0.read() }
  }
  @objc private func live() {
    guard optIn.state == .on, let expected = state else { return }
    operate("Switching to live controls…") { try $0.setMode(2, expected: expected) }
  }
  @objc private func onboard() {
    operate("Returning to onboard settings…") {
      try $0.restoreOnboard()
      return nil
    }
  }
  @objc private func setDPI() {
    guard optIn.state == .on, let expected = state, let dpi = Int(dpiField.stringValue) else {
      status.stringValue = "Enter a whole DPI value from the supported range."
      return
    }
    operate("Setting DPI…") { try $0.setDPI(dpi, expected: expected) }
  }
  @objc private func setRate() {
    guard optIn.state == .on, let expected = state, let rate = ratePicker.selectedItem?.tag else {
      return
    }
    operate("Setting polling rate…") { try $0.setRate(rate, expected: expected) }
  }
  @objc private func guide() {
    NSWorkspace.shared.open(AppInfo.website.appendingPathComponent("blob/main/docs/logitech.md"))
  }
}
