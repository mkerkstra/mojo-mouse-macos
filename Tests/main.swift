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
// Native experimental policy is enforced on imported/saved/automatic writes.
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
print(
  "Passed \(assertions) native checks: packet fixtures, validation, scopes, rule priority, overnight/DST windows, persistence, rollback, and disconnect handling."
)
