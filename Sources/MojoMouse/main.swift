import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var window: NSWindow!
  private let worker = DispatchQueue(label: "io.github.mkerkstra.mojomouse.manual")
  private let store = LightingStore()
  private var state: MouseState?
  private var baseline: Lighting?
  private var busy = false
  private var controls: [NSControl] = []
  private let connection = NSTextField(labelWithString: "Looking for your mouse…")
  private let summary = NSTextField(labelWithString: "Connecting")
  private let status = NSTextField(wrappingLabelWithString: "")
  private let wheelValue = NSTextField(labelWithString: "—")
  private let bodySwitch = NSSwitch()
  private let wheel = NSSlider(value: 0, minValue: 0, maxValue: 100, target: nil, action: nil)
  private var indicator: NSView!
  private var offButton: NSButton!
  private var settingsWindow: SettingsWindow?
  private var informationWindow: AppInformationWindow?
  private var menuItem: NSStatusItem!
  private var libraryObserver: NSObjectProtocol?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let appMenu = NSMenu()
    let top = NSMenuItem()
    let submenu = NSMenu()
    submenu.addItem(withTitle: "About \(AppInfo.name)", action: #selector(about), keyEquivalent: "")
    submenu.addItem(.separator())
    submenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
    submenu.addItem(.separator())
    submenu.addItem(
      withTitle: "Quit \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    top.submenu = submenu
    appMenu.addItem(top)
    let edit = NSMenuItem()
    let editMenu = NSMenu(title: "Edit")
    for (title, action, key) in [
      ("Undo", "undo:", "z"), ("Redo", "redo:", "Z"),
      ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
      ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a"),
    ] {
      editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
    }
    edit.submenu = editMenu
    appMenu.addItem(edit)
    let help = NSMenuItem()
    let helpMenu = NSMenu(title: "Help")
    helpMenu.addItem(withTitle: "User Guide", action: #selector(openGuide), keyEquivalent: "?")
    helpMenu.addItem(
      withTitle: "Support & Compatibility", action: #selector(openSupport), keyEquivalent: "")
    helpMenu.addItem(withTitle: "Privacy Policy", action: #selector(openPrivacy), keyEquivalent: "")
    help.submenu = helpMenu
    appMenu.addItem(help)
    NSApp.helpMenu = helpMenu
    NSApplication.shared.mainMenu = appMenu
    buildWindow()
    menuItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    menuItem.button?.image = NSImage(
      systemSymbolName: "computermouse", accessibilityDescription: AppInfo.name)
    menuItem.button?.toolTip = AppInfo.name
    rebuildMenu()
    AutomationEngine.shared.onChange = { [weak self] in self?.rebuildMenu() }
    libraryObserver = NotificationCenter.default.addObserver(
      forName: Notification.Name("MojoLibraryChanged"), object: nil, queue: .main
    ) { [weak self] _ in self?.rebuildMenu() }
    AutomationEngine.shared.start()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    refresh()
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    !((try? LibraryStore.shared.read().automationEnabled) ?? false)
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    window.makeKeyAndOrderFront(nil)
    return true
  }
  private func rebuildMenu() {
    guard menuItem != nil else { return }
    let menu = NSMenu()
    let open = NSMenuItem(
      title: "Open \(AppInfo.name)", action: #selector(openWindow), keyEquivalent: "")
    open.target = self
    menu.addItem(open)
    let settings = NSMenuItem(
      title: "Profiles & rules…", action: #selector(openSettings), keyEquivalent: "")
    settings.target = self
    menu.addItem(settings)
    if let library = try? LibraryStore.shared.read() {
      if !library.profiles.isEmpty {
        menu.addItem(.separator())
        for profile in library.profiles {
          let item = NSMenuItem(
            title: profile.name, action: #selector(activateSaved(_:)), keyEquivalent: "")
          item.target = self
          item.representedObject = profile.id
          menu.addItem(item)
        }
      }
      if library.automationEnabled {
        menu.addItem(.separator())
        let status = NSMenuItem(
          title: AutomationEngine.shared.statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        let pause = NSMenuItem(
          title: "Pause switching for 1 hour", action: #selector(pauseRules), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        let resume = NSMenuItem(
          title: "Resume switching", action: #selector(resumeRules), keyEquivalent: "")
        resume.target = self
        menu.addItem(resume)
      }
    }
    menu.addItem(.separator())
    let quit = NSMenuItem(
      title: "Quit \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    menu.addItem(quit)
    menuItem.menu = menu
  }
  @objc private func openWindow() {
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  @objc private func pauseRules() { AutomationEngine.shared.pause() }
  @objc private func resumeRules() { AutomationEngine.shared.resume() }
  @objc private func activateSaved(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    do {
      guard let profile = try LibraryStore.shared.read().profiles.first(where: { $0.id == id })
      else { return }
      let pixels =
        profile.display.mode == "text" ? try DisplayPixels.render(profile.display.text).bytes : nil
      perform("Applying \(profile.name)…", pauseRules: true) { mouse, _, _ in
        let applied = try ProfileController().apply(
          profile, to: mouse, textPixels: pixels,
          experimental: AppInfo.allowsExperimental
            && (try LibraryStore.shared.read().preferences["experimental"]) == "true")
        return MouseState(profile: applied.profile, data: applied.data)
      }
    } catch { status.stringValue = error.localizedDescription }
  }

  private func text(
    _ title: String, size: CGFloat = 13, weight: NSFont.Weight = .regular,
    color: NSColor = .labelColor
  ) -> NSTextField {
    let field = NSTextField(labelWithString: title)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    return field
  }
  private func button(_ title: String, _ action: Selector) -> NSButton {
    let button = NSButton(title: title, target: self, action: action)
    button.bezelStyle = .rounded
    button.controlSize = .large
    controls.append(button)
    return button
  }
  private func row(_ items: [NSView], spacing: CGFloat = 12) -> NSStackView {
    let stack = NSStackView(views: items)
    stack.orientation = .horizontal
    stack.spacing = spacing
    stack.alignment = .centerY
    return stack
  }
  private func vertical(_ items: [NSView], spacing: CGFloat = 4) -> NSStackView {
    let stack = NSStackView(views: items)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = spacing
    return stack
  }
  private func spacer() -> NSView {
    let view = NSView()
    view.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return view
  }
  private func line() -> NSBox {
    let line = NSBox()
    line.boxType = .separator
    return line
  }
  private func buildWindow() {
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 500, height: 570),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = AppInfo.name
    window.titlebarAppearsTransparent = true
    window.center()
    window.isReleasedWhenClosed = false
    let content = window.contentView!

    let moon = NSImageView(
      image: NSImage(systemSymbolName: "moon.stars.fill", accessibilityDescription: AppInfo.name)!)
    moon.contentTintColor = .systemIndigo
    moon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 32, weight: .medium)
    moon.widthAnchor.constraint(equalToConstant: 48).isActive = true
    moon.heightAnchor.constraint(equalToConstant: 48).isActive = true
    summary.font = .systemFont(ofSize: 25, weight: .semibold)
    connection.font = .systemFont(ofSize: 12)
    connection.textColor = .secondaryLabelColor
    indicator = NSView()
    indicator.wantsLayer = true
    indicator.layer?.cornerRadius = 4
    indicator.layer?.backgroundColor = NSColor.systemOrange.cgColor
    indicator.widthAnchor.constraint(equalToConstant: 8).isActive = true
    indicator.heightAnchor.constraint(equalToConstant: 8).isActive = true
    let heading = row([
      moon, vertical([summary, row([indicator, connection], spacing: 6)]), spacer(),
    ])
    let caption = text("A quieter desk, with one click.", color: .secondaryLabelColor)
    offButton = button("All lights off", #selector(allOff))
    offButton.bezelColor = .systemIndigo
    offButton.contentTintColor = .white
    offButton.font = .systemFont(ofSize: 15, weight: .semibold)
    offButton.heightAnchor.constraint(equalToConstant: 40).isActive = true
    offButton.setAccessibilityLabel("Turn off body lights, scroll wheel, and side display")

    bodySwitch.target = self
    bodySwitch.action = #selector(changeBody)
    bodySwitch.setAccessibilityLabel("Body lighting")
    controls.append(bodySwitch)
    let bodyRow = row([
      vertical([
        text("Body lighting", weight: .medium),
        text("Use your saved color and effect", size: 11, color: .secondaryLabelColor),
      ]), spacer(), bodySwitch,
    ])

    wheel.target = self
    wheel.action = #selector(changeWheel)
    wheel.isContinuous = false
    wheel.setAccessibilityLabel("Scroll wheel brightness")
    controls.append(wheel)
    wheelValue.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    wheelValue.alignment = .right
    wheelValue.widthAnchor.constraint(equalToConstant: 42).isActive = true
    let wheelHead = row([text("Scroll wheel", weight: .medium), spacer(), wheelValue])
    let wheelRow = vertical([wheelHead, wheel], spacing: 8)
    wheel.widthAnchor.constraint(equalTo: wheelRow.widthAnchor).isActive = true
    wheelHead.widthAnchor.constraint(equalTo: wheelRow.widthAnchor).isActive = true

    let hide = button("Hide", #selector(hideSide))
    let show = button("Show MOJO", #selector(showSide))
    let sideRow = row(
      [
        vertical([
          text("Side display", weight: .medium),
          text("MOJO logo or a blank display", size: 11, color: .secondaryLabelColor),
        ]), spacer(), hide, show,
      ], spacing: 8)
    let refresh = button("Refresh", #selector(refresh))
    refresh.setAccessibilityLabel("Refresh mouse connection and lighting settings")
    let restore = button("Restore saved lights", #selector(restore))
    let footer = row([restore, spacer(), refresh])
    let settings = button("Profiles, rules & side text…", #selector(openSettings))
    status.font = .systemFont(ofSize: 11)
    status.textColor = .secondaryLabelColor
    status.maximumNumberOfLines = 3
    status.setAccessibilityRole(.staticText)
    status.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true

    let stack = vertical(
      [
        heading, caption, offButton, line(), bodyRow, wheelRow, sideRow, line(), footer, settings,
        status,
      ], spacing: 14)
    stack.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
      stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
      stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
    ])
    for view in [heading, offButton!, bodyRow, wheelRow, sideRow, footer, settings, status] {
      view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    for view in stack.arrangedSubviews where view is NSBox {
      view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    setEnabled(false)
  }
  private func setEnabled(_ enabled: Bool) {
    for control in controls { control.isEnabled = enabled }
    // Reconnecting must remain available after a missing-device error.
    controls.first(where: { $0.action == #selector(openSettings) })?.isEnabled = true
    if !busy { controls.first(where: { $0.action == #selector(refresh) })?.isEnabled = true }
  }
  private func update(_ result: MouseState, baseline saved: Lighting, message: String) {
    state = result
    baseline = saved
    let lighting = result.lighting
    summary.stringValue =
      !lighting.bodyOn && !lighting.wheelOn ? "RGB lights off" : "Your lights, your way."
    connection.stringValue = "MJ-189 connected · Profile \(result.profile + 1)"
    indicator.layer?.backgroundColor = NSColor.systemGreen.cgColor
    bodySwitch.state = lighting.bodyOn ? .on : .off
    let maxSaved = saved.wheel.map(Int.init).max() ?? 255
    let maxCurrent = lighting.wheel.map(Int.init).max() ?? 0
    let percent =
      maxSaved > 0
      ? min(100, Int((Double(maxCurrent) / Double(maxSaved) * 100).rounded()))
      : (lighting.wheelOn ? 100 : 0)
    wheel.doubleValue = Double(percent)
    wheelValue.stringValue = "\(percent)%"
    status.stringValue = message
    status.textColor = .secondaryLabelColor
    setEnabled(true)
  }
  private func perform(
    _ label: String, pauseRules: Bool = true,
    operation: @escaping (MouseConnection, MouseState, Lighting) throws -> MouseState
  ) {
    guard !busy else {
      status.stringValue = "A mouse operation is already running. Try again when it finishes."
      return
    }
    if pauseRules { AutomationEngine.shared.pause() }
    busy = true
    setEnabled(false)
    status.stringValue = label
    worker.async {
      do {
        let mouse = try MouseConnection()
        let current = try mouse.state()
        let saved = try self.store.baseline(for: current)
        let result = try operation(mouse, current, saved)
        DispatchQueue.main.async {
          self.busy = false
          self.update(
            result, baseline: saved, message: "Body and wheel settings checked on your mouse.")
        }
      } catch {
        DispatchQueue.main.async {
          self.busy = false
          self.status.stringValue = error.localizedDescription
          self.status.textColor = .systemRed
          self.connection.stringValue = "Mouse needs attention"
          self.indicator.layer?.backgroundColor = NSColor.systemOrange.cgColor
          self.setEnabled(false)
        }
      }
    }
  }
  @objc private func refresh() {
    perform("Reading your mouse…", pauseRules: false) { _, current, _ in current }
  }
  @objc private func allOff() {
    perform("Turning the lights off…") { mouse, current, _ in
      var lighting = current.lighting
      lighting.body[0] = 0
      lighting.body[1] = 0
      lighting.body[2] = 0
      lighting.wheel = [UInt8](repeating: 0, count: 24)
      let result = try mouse.apply(lighting, to: current)
      try mouse.showSideLogo(false)
      return result
    }
  }
  @objc private func changeBody() {
    let on = bodySwitch.state == .on
    perform("Updating body lighting…") { mouse, current, saved in
      var lighting = current.lighting
      if on {
        lighting.body = saved.body
        if !lighting.bodyOn { lighting.body = [1, 10, 0, 255, 128, 0] }
      } else {
        lighting.body[0] = 0
        lighting.body[1] = 0
        lighting.body[2] = 0
      }
      return try mouse.apply(lighting, to: current)
    }
  }
  @objc private func changeWheel() {
    let fraction = wheel.doubleValue / 100
    perform("Updating wheel brightness…") { mouse, current, saved in
      var lighting = current.lighting
      let colors = saved.wheelOn ? saved.wheel : Array(repeating: UInt8(255), count: 24)
      lighting.wheel = colors.map { UInt8((Double($0) * fraction).rounded()) }
      return try mouse.apply(lighting, to: current)
    }
  }
  @objc private func hideSide() {
    perform("Hiding the side logo…") { mouse, current, _ in
      try mouse.showSideLogo(false)
      return current
    }
  }
  @objc private func showSide() {
    perform("Showing the MOJO logo…") { mouse, current, _ in
      try mouse.showSideLogo(true)
      return current
    }
  }
  @objc private func restore() {
    perform("Restoring your saved lights…") { mouse, current, saved in
      let result = try mouse.apply(saved, to: current)
      try mouse.showSideLogo(true)
      return result
    }
  }
  @objc private func openSettings() {
    if settingsWindow == nil { settingsWindow = SettingsWindow() }
    settingsWindow?.showWindow(nil)
    settingsWindow?.window?.makeKeyAndOrderFront(nil)
  }
  @objc private func about() {
    if informationWindow == nil { informationWindow = AppInformationWindow() }
    informationWindow?.showWindow(nil)
    informationWindow?.window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  @objc private func openGuide() { NSWorkspace.shared.open(AppInfo.guide) }
  @objc private func openSupport() { NSWorkspace.shared.open(AppInfo.support) }
  @objc private func openPrivacy() { NSWorkspace.shared.open(AppInfo.privacy) }

}
if CommandLine.arguments.contains("--version") {
  print("\(AppInfo.name) \(AppInfo.version)")
  exit(0)
}
if CommandLine.arguments.contains("--diagnose") {
  let discovery = MouseConnection.discovery()
  var report: [String: Any] = [
    "app": AppInfo.name, "version": AppInfo.version, "supportedModel": "MJ-189",
    "usbID": "260d:1027",
    "connectedCount": discovery.count,
    "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
  ]
  if discovery.count == 1 {
    do {
      let mouse = try MouseConnection()
      let snapshot = try ProfileController().snapshot(mouse)
      report["profileBytes"] = snapshot.data.count
      report["buttonMapBytes"] = snapshot.buttons.count
      report["pollingHz"] = 1000 / snapshot.rate
    } catch { report["error"] = error.localizedDescription }
  }
  let data = try JSONSerialization.data(
    withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
  print(String(data: data, encoding: .utf8)!)
  exit(report["error"] == nil ? 0 : 1)
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
