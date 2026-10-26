import Foundation

var assertions = 0
func check(_ condition: Bool, _ message: String) {
  assertions += 1
  if !condition {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
  }
}
@discardableResult func expectFailure(_ name: String, _ operation: () throws -> Void) -> String {
  do {
    try operation()
    check(false, name)
    return ""
  } catch {
    assertions += 1
    return error.localizedDescription
  }
}
let profileID = "00000000-0000-4000-8000-000000000001"
let fallbackID = "00000000-0000-4000-8000-000000000002"
func snapshot() -> FullSnapshot {
  var data = [UInt8](repeating: 0, count: 128)
  data[35] = 100
  data[36] = 100
  data[71] = 255
  data[73] = 1
  data[74] = 10
  data[76] = 255
  data[100] = 255
  var buttons = [UInt8](repeating: 0, count: 128)
  buttons.replaceSubrange(0..<4, with: [1, 0, 240, 0])
  buttons.replaceSubrange(4..<8, with: [1, 0, 241, 0])
  return FullSnapshot(profile: 0, data: data, buttons: buttons, rate: 1)
}
func named(_ id: String = profileID, _ name: String = "Work") -> NamedProfile {
  NamedProfile(id: id, name: name, scope: "all", snapshot: snapshot(), display: SideDisplay())
}
func rule(app: String? = nil, start: Int? = nil, end: Int? = nil, days: [Int] = [])
  -> ActivationRule
{
  ActivationRule(
    id: UUID().uuidString, name: "Test rule", enabled: true, profileID: profileID, bundleID: app,
    startMinute: start, endMinute: end, weekdays: days)
}
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "America/Chicago")!
func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ minute: Int = 0) -> Date {
  calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: minute))!
}
func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date { date(2026, 10, day, hour, minute) }

check(
  try Packet.command(0x86, parameters: [0]) == [0x86, 0, 0, 0, 0, 0, 0, 0x79],
  "captured profile-read command")
check(
  try Packet.command(6, parameters: [0, 128]) == [6, 0, 128, 0, 0, 0, 0, 0x79],
  "captured profile-write command")
check(
  try Packet.command(10, parameters: [5]) == [10, 5, 0, 0, 0, 0, 0, 0xf0], "text display command")
expectFailure("reject oversized packets") {
  _ = try Packet.command(1, parameters: Array(repeating: 0, count: 7))
}

let keyProfile = named()
let activationKey = try keyProfile.activationKey(identity: 42)
for _ in 0..<20 {
  check(
    try keyProfile.activationKey(identity: 42) == activationKey,
    "same selection does not cause repeated device writes")
}
check(
  try keyProfile.activationKey(identity: 43) != activationKey, "reconnection changes activation key"
)
var changedKeyProfile = keyProfile
changedKeyProfile.snapshot.data[73] = 0
check(
  try changedKeyProfile.activationKey(identity: 42) != activationKey,
  "editing a selected profile causes reevaluation")

let appOnly = rule(app: "com.example.Editor")
check(
  appOnly.matches(app: "com.example.Editor", at: at(26, 12), calendar: calendar),
  "app matches without schedule")
check(
  !appOnly.matches(app: "com.example.Other", at: at(26, 12), calendar: calendar), "app mismatch")
check(
  !appOnly.matches(app: nil, at: at(26, 12), calendar: calendar),
  "unknown app cannot match app-only rule")
var disabled = appOnly
disabled.enabled = false
check(
  !disabled.matches(app: "com.example.Editor", at: at(26, 12), calendar: calendar),
  "disabled rule never matches")
let day = rule(start: 9 * 60, end: 17 * 60, days: [1])
check(day.matches(app: nil, at: at(26, 9), calendar: calendar), "start inclusive")
check(!day.matches(app: nil, at: at(26, 17), calendar: calendar), "end exclusive")
check(!day.matches(app: nil, at: at(27, 10), calendar: calendar), "weekday filter")
let overnight = rule(start: 22 * 60, end: 7 * 60, days: [1])
check(overnight.matches(app: nil, at: at(26, 22), calendar: calendar), "overnight starts Monday")
check(
  overnight.matches(app: nil, at: at(27, 6, 59), calendar: calendar),
  "overnight Tuesday morning belongs to Monday")
check(!overnight.matches(app: nil, at: at(27, 7), calendar: calendar), "overnight end exclusive")
check(
  !overnight.matches(app: nil, at: at(26, 6), calendar: calendar),
  "Monday morning belongs to Sunday")
let weekend = rule(start: 22 * 60, end: 7 * 60, days: [6])
check(
  weekend.matches(app: nil, at: date(2026, 11, 1, 3), calendar: calendar), "DST fallback overnight")
check(
  weekend.matches(app: nil, at: date(2026, 3, 8, 3), calendar: calendar), "DST spring overnight")
let both = rule(app: "com.example.Editor", start: 9 * 60, end: 17 * 60, days: [1])
check(
  !both.matches(app: "com.example.Other", at: at(26, 10), calendar: calendar),
  "app and time use AND")
check(
  !both.matches(app: "com.example.Editor", at: at(26, 20), calendar: calendar),
  "app alone cannot satisfy combined rule")
var library = AppLibrary()
library.profiles = [named(), named(fallbackID, "Fallback")]
library.rules = [appOnly, day]
library.automationEnabled = true
library.fallbackProfileID = fallbackID
try library.validate()
check(
  library.selection(app: "com.example.Editor", at: at(26, 10), calendar: calendar)?.1
    == appOnly.name, "first matching rule wins")
check(
  library.selection(app: "other", at: at(27, 20), calendar: calendar)?.0.id == fallbackID,
  "fallback when no match")
var offLibrary = library
offLibrary.automationEnabled = false
check(
  offLibrary.selection(app: "com.example.Editor", at: at(26, 10), calendar: calendar) == nil,
  "disabled automation cannot select a profile")
expectFailure("enabling requires fallback") {
  var value = library
  value.fallbackProfileID = nil
  try value.validate()
}
expectFailure("rules must reference existing profile") {
  var value = appOnly
  value.profileID = UUID().uuidString
  try value.validate(profiles: library.profiles)
}
expectFailure("empty trigger rejected") { try rule().validate(profiles: library.profiles) }
expectFailure("equal time rejected") {
  try rule(start: 10, end: 10, days: [1]).validate(profiles: library.profiles)
}
expectFailure("invalid weekday rejected") {
  try rule(start: 10, end: 20, days: [8]).validate(profiles: library.profiles)
}
expectFailure("duplicate weekdays rejected") {
  try rule(start: 10, end: 20, days: [1, 1]).validate(profiles: library.profiles)
}
expectFailure("duplicate profile IDs rejected") {
  var value = library
  value.profiles.append(value.profiles[0])
  try value.validate()
}
expectFailure("profile without left click rejected") {
  var value = snapshot()
  value.buttons[2] = 241
  try value.validate()
}
expectFailure("profile without DPI stages rejected") {
  var value = snapshot()
  value.data[71] = 0
  try value.validate()
}
expectFailure("wrong device rejected") {
  var value = snapshot()
  value.device = "other"
  try value.validate()
}
expectFailure("unsupported rate rejected") {
  var value = snapshot()
  value.rate = 3
  try value.validate()
}

let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
  "mojo-tests-\(UUID().uuidString)")
let store = LibraryStore(directory: folder)
defer { try? FileManager.default.removeItem(at: folder) }
check(try store.read().automationEnabled == false, "fresh install automation off")
_ = try store.update { $0 = library }
check(try store.read() == library, "library persistence round trip")
expectFailure("invalid library update rejected atomically") {
  _ = try store.update { $0.profiles = [] }
}
check(try store.read() == library, "failed update preserved previous file")
try store.captureOriginal(snapshot())
try store.captureOriginal(snapshot())
check(try store.original() == snapshot(), "original backup preserved")
expectFailure("unknown preferences rejected") { try store.setPreference("arbitrary", "value") }
try store.setPreference("sideText", "HELLO")
check(try store.read().preferences["sideText"] == "HELLO", "native preference persistence")

final class FakeMouse: MouseSession {
  var value = snapshot()
  var failButtonsOnce = false
  var failNextReadOnButtonFailure = false
  var invalidateOnButtonFailure = false
  var switchProfileAfterWrite = false
  var transientReads = 0
  var disconnected = false
  var disconnectAfterWrite = false
  var writes = 0
  var pixels: [UInt8]?
  var mode: Int?
  func state() throws -> MouseState {
    if transientReads > 0 {
      transientReads -= 1
      throw MouseFailure(message: "Transient read timeout")
    }
    if disconnected { throw MouseFailure(message: "Disconnected") }
    return MouseState(profile: value.profile, data: value.data)
  }
  func readButtons() throws -> [UInt8] {
    if disconnected { throw MouseFailure(message: "Disconnected") }
    return value.buttons
  }
  func rawPollingRate() throws -> Int { try pollingRate() }
  func pollingRate() throws -> Int {
    if disconnected { throw MouseFailure(message: "Disconnected") }
    return value.rate
  }
  func writeProfile(_ data: [UInt8], expected: MouseState) throws -> MouseState {
    guard !disconnected, value.profile == expected.profile, value.data == expected.data else {
      throw MouseFailure(message: "Stale profile")
    }
    if value.data != data { writes += 1 }
    value.data = data
    if switchProfileAfterWrite {
      value.profile += 1
      value.data[35] = 77
    }
    if disconnectAfterWrite { disconnected = true }
    return MouseState(profile: value.profile, data: data)
  }
  func writeButtons(_ data: [UInt8], expected: [UInt8]) throws {
    guard !disconnected, value.buttons == expected else {
      throw MouseFailure(message: "Stale buttons")
    }
    if failButtonsOnce {
      failButtonsOnce = false
      if failNextReadOnButtonFailure { transientReads = 1 }
      if invalidateOnButtonFailure {
        value.data[71] = 0
        value.buttons[2] = 0
        value.rate = 3
      }
      throw MouseFailure(message: "Injected button write failure")
    }
    if value.buttons != data { writes += 1 }
    value.buttons = data
  }
  func setPollingRate(_ rate: Int) throws {
    if disconnected { throw MouseFailure(message: "Disconnected") }
    value.rate = rate
    writes += 1
  }
  func setSideMode(_ mode: Int) throws { self.mode = mode }
  func sendTextPixels(_ bytes: [UInt8]) throws { pixels = bytes }
}
let controller = ProfileController(store: store)
let mouse = FakeMouse()
let unchanged = try controller.apply(named(), to: mouse)
check(unchanged == snapshot() && mouse.writes == 0, "identical profile avoids writes")
var quiet = named()
quiet.scope = "lighting"
quiet.snapshot.data[73] = 0
quiet.snapshot.data[100] = 0
quiet.snapshot.data[35] = 2
quiet.snapshot.buttons[6] = 244
quiet.snapshot.rate = 8
quiet.display.mode = "blank"
_ = try controller.apply(quiet, to: mouse)
check(
  mouse.value.data[35] == 100 && mouse.value.buttons == snapshot().buttons && mouse.value.rate == 1,
  "lighting-only scope preserves pointer/buttons/rate")
check(
  mouse.value.data[73] == 0 && mouse.pixels == Array(repeating: 0, count: 512),
  "lighting-only blanks RGB and side text without picture assumptions")
let failing = FakeMouse()
failing.failButtonsOnce = true
var changed = named()
changed.snapshot.data[35] = 120
let restored = expectFailure("partial failure rolls back") {
  _ = try controller.apply(changed, to: failing)
}
check(
  restored.contains("restored and verified") && failing.value == snapshot(),
  "partial failure restores prior complete settings")
let disconnected = FakeMouse()
disconnected.disconnectAfterWrite = true
let interrupted = expectFailure("disconnect reports unverifiable rollback") {
  _ = try controller.apply(changed, to: disconnected)
}
check(
  interrupted.contains("Some settings may have changed"),
  "disconnect does not claim successful rollback")
let switched = FakeMouse()
switched.switchProfileAfterWrite = true
let switchedFailure = expectFailure("hardware profile change stops rollback") {
  _ = try controller.apply(changed, to: switched)
}
check(
  switchedFailure.contains("active hardware profile changed")
    && switchedFailure.contains("Profile 1 may have changed"), "changed slot is reported accurately"
)
check(
  switched.writes == 1 && switched.value.profile == 1 && switched.value.data[35] == 77,
  "rollback never writes original bytes into a different hardware profile")
let textMouse = FakeMouse()
var text = named()
text.display = SideDisplay(mode: "text", text: "HELLO")
expectFailure("unrendered text rejected before writes") {
  _ = try controller.apply(text, to: textMouse)
}
check(textMouse.writes == 0, "text validation precedes device changes")
_ = try controller.apply(text, to: textMouse, textPixels: Array(repeating: 1, count: 512))
check(textMouse.pixels == Array(repeating: 1, count: 512), "prepared text passed through")
// Native experimental policy is enforced whenever a profile is applied.
var rawCandidate = snapshot()
rawCandidate.data[0] = 1
expectFailure("stable mode rejects vendor-byte edits") {
  try WritePolicy.validate(rawCandidate, comparedTo: snapshot(), experimental: false)
}
try WritePolicy.validate(rawCandidate, comparedTo: snapshot(), experimental: true)
var macroCandidate = snapshot()
macroCandidate.buttons.replaceSubrange(12..<16, with: [9, 0, 1, 0])
expectFailure("stable mode rejects new macro bindings") {
  try WritePolicy.validate(macroCandidate, comparedTo: snapshot(), experimental: false)
}
try WritePolicy.validate(macroCandidate, comparedTo: macroCandidate, experimental: false)
var rapidCandidate = snapshot()
rapidCandidate.buttons.replaceSubrange(12..<16, with: [11, 240, 64, 0])
expectFailure("stable mode rejects new rapid bindings") {
  try WritePolicy.validate(rapidCandidate, comparedTo: snapshot(), experimental: false)
}
check(WritePolicy.knownButton([0, 0, 227, 6]), "known single-modifier shortcut")
check(!WritePolicy.knownButton([15, 0, 46, 0]), "unknown special action is experimental")
let transient = FakeMouse()
transient.failButtonsOnce = true
transient.failNextReadOnButtonFailure = true
transient.invalidateOnButtonFailure = true
let recovered = expectFailure("rollback retries raw reads of invalid partial settings") {
  _ = try controller.apply(changed, to: transient)
}
check(
  recovered.contains("restored and verified") && transient.value == snapshot(),
  "invalid partial state and transient timeout are recovered")
for i in 0..<55 {
  var backup = snapshot()
  backup.data[35] = UInt8(i + 1)
  try store.backup(backup)
}
let retained = try FileManager.default.contentsOfDirectory(
  at: folder.appendingPathComponent("Backups"), includingPropertiesForKeys: nil)
check(retained.count == 50, "generated backups are bounded to 50")
check(try store.original() == snapshot(), "retention never removes original backup")

var policy = SwitchingState()
let fixed = Date(timeIntervalSince1970: 1000)
policy.pause(at: fixed)
let until = policy.pausedUntil
policy.changed(clearPause: false)
check(policy.pausedUntil == until, "profile saves preserve manual pause")
check(!policy.accepts(token: policy.generation, at: fixed), "paused queued work rejected")
check(policy.accepts(token: policy.generation, at: fixed.addingTimeInterval(3601)), "pause expiry")
policy.changed(clearPause: true)
check(policy.pausedUntil == nil, "saving rules explicitly clears pause")
let staleToken = policy.generation
policy.pause(at: fixed)
check(
  !policy.accepts(token: staleToken, at: fixed.addingTimeInterval(7200)),
  "old token remains invalid even after pause expires")
policy.resume()
policy.sleep()
check(!policy.accepts(token: policy.generation, at: fixed), "sleep rejects work")
policy.wake(at: fixed)
check(
  !policy.suspended && policy.retryAfter == fixed.addingTimeInterval(3),
  "wake waits for USB recovery")
var retry = SwitchingState()
for delay in [30.0, 60, 120, 240, 300, 300] {
  retry.failed(at: fixed)
  check(retry.retryAfter.timeIntervalSince(fixed) == delay, "bounded backoff schedule")
}

final class Counter {
  private let lock = NSLock()
  private var count = 0
  func increment() {
    lock.lock()
    count += 1
    lock.unlock()
  }
  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return count
  }
}
func pumpUntil(_ message: String, timeout: Double = 3, _ predicate: () -> Bool) {
  let deadline = Date().addingTimeInterval(timeout)
  while !predicate() && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
  }
  check(predicate(), message)
}
var automationLibrary = library
automationLibrary.profiles[0].snapshot.data[35] = 111
_ = try store.update { $0 = automationLibrary }
let automaticMouse = FakeMouse()
let attempts = Counter()
var connectionIdentity: UInt64 = 1
let engine = AutomationEngine(
  store: store, now: { fixed }, frontmost: { "com.example.Editor" },
  discovery: { (connectionIdentity, 1) },
  makeSession: {
    attempts.increment()
    return automaticMouse
  }, renderText: { _ in Array(repeating: 0, count: 512) }, ownBundleID: "com.example.Mojo")
engine.evaluate()
pumpUntil("automation executes selected profile") { engine.policy.lastKey != nil }
check(
  automaticMouse.value.data[35] == 111 && attempts.value == 1,
  "real engine applies expected settings")
engine.evaluate()
RunLoop.current.run(until: Date().addingTimeInterval(0.1))
check(attempts.value == 1, "real engine suppresses repeat connection/write")
connectionIdentity = 2
engine.evaluate()
pumpUntil("reconnection reevaluates selected profile") {
  attempts.value == 2 && engine.policy.lastKey?.hasPrefix("2:") == true
}
engine.pause()
let enginePause = engine.policy.pausedUntil
engine.settingsChanged(clearPause: false)
check(engine.policy.pausedUntil == enginePause, "real engine preserves pause on profile edits")
engine.settingsChanged(clearPause: true)
check(engine.policy.pausedUntil == nil, "real engine clears pause for rule changes")
let ownAttempts = Counter()
let ownEngine = AutomationEngine(
  store: store, now: { fixed }, frontmost: { "com.example.Mojo" }, discovery: { (1, 1) },
  makeSession: {
    ownAttempts.increment()
    return FakeMouse()
  }, ownBundleID: "com.example.Mojo")
ownEngine.evaluate()
check(ownAttempts.value == 0, "own-app editing guard")
ownEngine.handleSleep()
ownEngine.evaluate()
check(ownAttempts.value == 0, "suspended engine cannot start work")

let waiting = DispatchSemaphore(value: 0)
let permit = DispatchSemaphore(value: 0)
let cancelMouse = FakeMouse()
let cancelEngine = AutomationEngine(
  store: store, now: { fixed }, frontmost: { "com.example.Editor" }, discovery: { (1, 1) },
  makeSession: {
    waiting.signal()
    _ = permit.wait(timeout: .now() + 3)
    return cancelMouse
  }, ownBundleID: "com.example.Mojo")
cancelEngine.evaluate()
check(
  waiting.wait(timeout: .now() + 3) == .success, "automatic operation is waiting for its connection"
)
cancelEngine.pause()
permit.signal()
pumpUntil("post-connection token check drops queued automatic work") {
  cancelEngine.policy.pausedUntil != nil && cancelEngine.statusText.contains("paused")
}
RunLoop.current.run(until: Date().addingTimeInterval(0.1))
check(
  cancelMouse.writes == 0 && cancelMouse.value == snapshot(),
  "queued automation cannot overwrite later manual override")

var fakeNow = fixed
let failedAttempts = Counter()
let failedEngine = AutomationEngine(
  store: store, now: { fakeNow }, frontmost: { "com.example.Editor" }, discovery: { (1, 1) },
  makeSession: {
    failedAttempts.increment()
    throw MouseFailure(message: "Injected unavailable mouse")
  }, ownBundleID: "com.example.Mojo")
failedEngine.evaluate()
pumpUntil("engine records first retry") { failedEngine.policy.failureCount == 1 }
failedEngine.evaluate()
check(failedAttempts.value == 1, "engine respects backoff")
fakeNow = fixed.addingTimeInterval(31)
failedEngine.evaluate()
pumpUntil("engine retries after deadline") { failedEngine.policy.failureCount == 2 }
check(
  failedEngine.policy.retryAfter == fakeNow.addingTimeInterval(60), "second retry waits 60 seconds")

let corrupt = folder.appendingPathComponent("library.json")
try Data("broken".utf8).write(to: corrupt)
expectFailure("corrupt library is not silently reset") { _ = try store.read() }
check(
  try String(contentsOf: corrupt, encoding: .utf8) == "broken",
  "corrupt file preserved for recovery")

// HID++ fixtures come from documented protocol layouts, not a connected Logitech.
check(LogitechCatalog.models.count == 8, "explicit Logitech product allowlist")
for product in LogitechCatalog.models.keys {
  check(
    LogitechCatalog.accepts(
      vendor: 0x046d, product: product, usagePages: [0xff00], transport: "USB"),
    "allow wired vendor interface")
}
for (vendor, product, usage, transport) in [
  (0x046d, 0xc08b, 1, "USB"), (0x046d, 0xc08b, 0xff00, "Bluetooth"),
  (0x046d, 0xc539, 0xff00, "USB"), (0x260d, 0xc08b, 0xff00, "USB"),
  (0x046d, 0xc095, 0xff00, "USB"), (0x046d, 0xc08b, -1, "USB"),
] {
  check(
    !LogitechCatalog.accepts(
      vendor: vendor, product: product, usagePages: [usage], transport: transport),
    "reject unrelated interface or transport")
}
let hidpp = try HIDPPPacket(feature: 5, function: 3, softwareID: 8, parameters: [0, 3, 32])
check(
  hidpp.bytes == [0x11, 0xff, 5, 0x38, 0, 3, 32] + Array(repeating: 0, count: 13),
  "HID++ long DPI packet fixture")
check(try hidpp.response(hidpp.bytes) == Array(hidpp.bytes.dropFirst(4)), "match long reply")
check(
  try hidpp.response([0x10, 0xff, 5, 0x38, 0, 3, 32]) == [0, 3, 32],
  "match short reply to long request")
for reply: [UInt8] in [
  [], [0x11], [0x10, 0xff, 5, 0x38], [0x10, 1, 5, 0x38, 0, 0, 0], [0x10, 0xff, 5, 0x39, 0, 0, 0],
  [0x10, 0xff, 6, 0x38, 0, 0, 0],
] {
  check(try hidpp.response(reply) == nil, "ignore truncated, foreign device or unrelated reply")
}
expectFailure("HID++ 2 error cannot become success") {
  _ = try hidpp.response([0x10, 0xff, 0xff, 5, 0x38, 2, 0])
}
expectFailure("HID++ 1 error cannot become success") {
  _ = try hidpp.response([0x10, 0xff, 0x8f, 5, 0x38, 2, 0])
}
expectFailure("reject oversized HID++ payload") {
  _ = try HIDPPPacket(
    feature: 1, function: 0, softwareID: 8, parameters: Array(repeating: 0, count: 17))
}
expectFailure("reject reserved software ID") {
  _ = try HIDPPPacket(feature: 1, function: 0, softwareID: 1)
}

func dpiList(_ words: [Int]) -> [UInt8] {
  let bytes: [UInt8] = [0] + words.flatMap { [UInt8($0 >> 8), UInt8($0 & 255)] }
  return bytes + Array(repeating: 0, count: 16 - bytes.count)
}
let dpiRange = try LogitechDPIRange(reply: dpiList([100, 0xe032, 25600]))
check(
  dpiRange.contains(100) && dpiRange.contains(800) && dpiRange.contains(25600),
  "DPI range endpoints and step")
check(
  !dpiRange.contains(99) && !dpiRange.contains(125) && !dpiRange.contains(25650),
  "reject off-grid DPI")
let discreteDPI = try LogitechDPIRange(reply: dpiList([400, 800, 1600]))
check(discreteDPI.contains(800) && !discreteDPI.contains(600), "discrete DPI list")
for list in [
  dpiList([]), dpiList([800, 400]), dpiList([400, 400]), dpiList([100, 0xe000, 1000]),
  dpiList([100, 0xe032, 0xe064, 1000]), [0, 1, 2],
] {
  expectFailure("malformed DPI list fails closed") { _ = try LogitechDPIRange(reply: list) }
}

final class FakeHIDPP: HIDPPTransport {
  var mode: UInt8 = 1
  var dpi = 800
  var rate: UInt8 = 1
  var features: [UInt16: UInt8] = [0x2201: 5, 0x8060: 7, 0x8100: 9, 0x8071: 10]
  var writes: [(UInt8, UInt8, [UInt8])] = []
  var ignoreDPIWrite = false
  var failWrites = false
  var invalidVersion = false
  var wrongToken = false
  var truncateDPI = false
  var sensorCount: UInt8 = 1
  func request(feature: UInt8, function: UInt8, parameters: [UInt8]) throws -> [UInt8] {
    func padded(_ bytes: [UInt8]) -> [UInt8] {
      bytes + Array(repeating: 0, count: 16 - bytes.count)
    }
    if feature == 0 {
      if function == 1 { return [invalidVersion ? 1 : 2, 0, wrongToken ? 0 : parameters[2]] }
      let id = UInt16(parameters[0]) << 8 | UInt16(parameters[1])
      return [features[id] ?? 0, 0, 0]
    }
    let key = features.first(where: { $0.value == feature })?.key
    switch (key, function) {
    case (0x8100, 2): return padded([mode])
    case (0x2201, 0): return padded([sensorCount])
    case (0x2201, 1): return dpiList([100, 0xe032, 25600])
    case (0x2201, 2):
      return truncateDPI ? [0, 3] : padded([0, UInt8(dpi >> 8), UInt8(dpi & 255), 3, 32])
    case (0x8060, 0): return padded([0x8b])  // 1, 2, 4, 8ms, not 1, 2, 8, 128ms
    case (0x8060, 1): return padded([rate])
    case (0x8100, 1), (0x2201, 3), (0x8060, 2):
      writes.append((feature, function, parameters))
      if failWrites { throw MouseFailure(message: "Injected transport failure") }
      if key == 0x8100 { mode = parameters[0] }
      if key == 0x2201 && !ignoreDPIWrite { dpi = Int(parameters[1]) << 8 | Int(parameters[2]) }
      if key == 0x8060 { rate = parameters[0] }
      return padded(parameters)
    default: throw MouseFailure(message: "Unexpected command in Logitech fixture")
    }
  }
}
let logitech = FakeHIDPP()
let logitechController = try LogitechController(logitech)
let onboardState = try logitechController.read()
check(
  logitech.writes.isEmpty && onboardState.mode == 1 && onboardState.dpi == 800,
  "discovery only reads settings")
check(onboardState.rates == [1, 2, 4, 8], "polling capability bit positions are milliseconds")
expectFailure("block DPI change in onboard mode") {
  _ = try logitechController.setDPI(1600, expected: onboardState)
}
check(logitech.writes.isEmpty, "blocked action sends no setting command")
var liveState = try logitechController.setMode(2, expected: onboardState)
check(liveState.mode == 2 && logitech.writes.count == 1, "explicit mode change verified")
liveState = try logitechController.setDPI(1600, expected: liveState)
check(
  liveState.dpi == 1600 && logitech.writes.last?.2 == [0, 6, 64],
  "DPI writes big-endian sensor zero and verifies")
liveState = try logitechController.setRate(4, expected: liveState)
check(
  liveState.rate == 4 && logitech.writes.last?.2 == [4], "polling writes milliseconds and verifies")
let writeCount = logitech.writes.count
_ = try logitechController.setDPI(1600, expected: liveState)
_ = try logitechController.setRate(4, expected: liveState)
check(logitech.writes.count == writeCount, "unchanged values are never written")
expectFailure("invalid DPI blocked before sending") {
  _ = try logitechController.setDPI(Int.max, expected: liveState)
}
expectFailure("negative DPI blocked before sending") {
  _ = try logitechController.setDPI(-1, expected: liveState)
}
expectFailure("invalid polling rate blocked before sending") {
  _ = try logitechController.setRate(3, expected: liveState)
}
expectFailure("invalid mode blocked before sending") {
  _ = try logitechController.setMode(255, expected: liveState)
}
check(logitech.writes.count == writeCount, "all invalid values send no write")
logitech.dpi = 2000
expectFailure("physical DPI changes require refresh") {
  _ = try logitechController.setRate(8, expected: liveState)
}
check(logitech.writes.count == writeCount, "stale state sends no write")
liveState = try logitechController.read()
logitech.ignoreDPIWrite = true
expectFailure("ACK without DPI readback is failure") {
  _ = try logitechController.setDPI(1600, expected: liveState)
}
logitech.ignoreDPIWrite = false
logitech.failWrites = true
expectFailure("disconnect propagates without false success") {
  _ = try logitechController.setRate(8, expected: liveState)
}
logitech.failWrites = false
let restoredLogitech = try logitechController.setMode(1, expected: liveState)
check(restoredLogitech.mode == 1, "can return to onboard settings")
check(
  logitech.writes.allSatisfy { [5, 7, 9].contains($0.0) },
  "no lighting, memory or button commands sent")
for invalid in ["version", "token", "sensor", "truncated", "mode", "duplicate"] {
  let transport = FakeHIDPP()
  transport.invalidVersion = invalid == "version"
  transport.wrongToken = invalid == "token"
  transport.sensorCount = invalid == "sensor" ? 2 : 1
  transport.truncateDPI = invalid == "truncated"
  transport.mode = invalid == "mode" ? 7 : 1
  if invalid == "duplicate" { transport.features[0x8060] = 5 }
  expectFailure("reject unsupported device response \(invalid)") {
    _ = try LogitechController(transport).read()
  }
  check(transport.writes.isEmpty, "unsupported reply sends no writes")
}
let minimalLogitech = FakeHIDPP()
minimalLogitech.features = [:]
let minimalState = try LogitechController(minimalLogitech).read()
check(
  minimalState.dpi == nil && minimalState.rate == nil && minimalState.mode == nil,
  "absent capabilities remain unavailable")
expectFailure("missing capability cannot be forced") {
  _ = try LogitechController(minimalLogitech).setDPI(800, expected: minimalState)
}

let recoveryLogitech = FakeHIDPP()
recoveryLogitech.mode = 2
recoveryLogitech.truncateDPI = true
let recoveryController = try LogitechController(recoveryLogitech)
expectFailure("broken live reads require recovery") { _ = try recoveryController.read() }
try recoveryController.restoreOnboard()
check(
  recoveryLogitech.mode == 1 && recoveryLogitech.writes.count == 1,
  "onboard recovery does not depend on DPI/rate reads")
try recoveryController.restoreOnboard()
check(recoveryLogitech.writes.count == 1, "recovery avoids unnecessary mode writes")
expectFailure("missing onboard feature cannot be forced") {
  try LogitechController(minimalLogitech).restoreOnboard()
}

check(
  LogitechCatalog.accepts(
    vendor: 0x046d, product: 0xc08b, usagePages: [1, 12, 0xff00], transport: "USB"),
  "composite Logitech interface matches secondary vendor usage")
check(
  LogitechCatalog.requiresInputPermission([
    HIDUsagePair(page: 1, usage: 6), HIDUsagePair(page: 0xff00, usage: 1),
  ]), "keyboard collection requires prior input permission")
check(
  !LogitechCatalog.requiresInputPermission([HIDUsagePair(page: 0xff00, usage: 1)]),
  "vendor-only configuration does not require input permission")
recoveryLogitech.mode = 7
try recoveryController.restoreOnboard()
check(
  recoveryLogitech.mode == 1 && recoveryLogitech.writes.count == 2,
  "explicit recovery handles unknown modes")

print(
  "Passed \(assertions) native checks: packet fixtures, validation, scopes, rule priority, overnight/DST windows, persistence, rollback, disconnect handling, and Logitech HID++ preview."
)
