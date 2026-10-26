import Foundation

struct FullSnapshot: Codable, Equatable {
  var formatVersion = 1
  var device = "MOJO MJ-189 (260d:1027)"
  var profile: Int
  var data: [UInt8]
  var buttons: [UInt8]
  var rate: Int

  func validate() throws {
    guard formatVersion == 1, device == "MOJO MJ-189 (260d:1027)", (0..<6).contains(profile),
      data.count == 128, buttons.count == 128, [1, 2, 4, 8].contains(rate), data[71] != 0
    else {
      throw MouseFailure(message: "This is not a supported MJ-189 profile.")
    }
    guard
      stride(from: 0, to: 36, by: 4).contains(where: {
        Array(buttons[$0..<$0 + 4]) == [1, 0, 240, 0]
      })
    else {
      throw MouseFailure(message: "Keep at least one primary button assigned to Left click.")
    }
  }
  func mergingLighting(into current: FullSnapshot) -> FullSnapshot {
    var merged = current
    merged.data.replaceSubrange(73..<79, with: data[73..<79])
    merged.data.replaceSubrange(100..<124, with: data[100..<124])
    return merged
  }
}

struct SideDisplay: Codable, Equatable {
  var mode: String = "unchanged"
  var text: String = ""
  func validate() throws {
    guard ["unchanged", "blank", "logo", "text"].contains(mode), text.count <= 120 else {
      throw MouseFailure(
        message: "Choose a supported side-display mode and at most 120 characters.")
    }
  }
}

struct NamedProfile: Codable, Equatable, Identifiable {
  var id: String
  var name: String
  var scope: String
  var snapshot: FullSnapshot
  var display: SideDisplay
  func activationKey(identity: UInt64) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return String(identity) + ":" + (try encoder.encode(self)).base64EncodedString()
  }
  func validate() throws {
    guard UUID(uuidString: id) != nil,
      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      name.count <= 64, ["all", "lighting"].contains(scope)
    else { throw MouseFailure(message: "Invalid profile name, identifier, or scope.") }
    try snapshot.validate()
    try display.validate()
  }
}

struct ActivationRule: Codable, Equatable, Identifiable {
  var id: String
  var name: String
  var enabled: Bool
  var profileID: String
  var bundleID: String?
  var startMinute: Int?
  var endMinute: Int?
  var weekdays: [Int]
  var hasSchedule: Bool { startMinute != nil || endMinute != nil }
  func validate(profiles: [NamedProfile]) throws {
    guard UUID(uuidString: id) != nil,
      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80,
      profiles.contains(where: { $0.id == profileID })
    else { throw MouseFailure(message: "Every rule needs a name and an existing profile.") }
    if let app = bundleID {
      guard app.count <= 255, app.contains("."), !app.contains(where: { $0.isWhitespace }),
        !app.contains("/")
      else {
        throw MouseFailure(message: "Use an app bundle identifier such as com.apple.Safari.")
      }
    }
    guard bundleID != nil || hasSchedule else {
      throw MouseFailure(message: "Give each rule an app, a schedule, or both.")
    }
    if hasSchedule {
      guard let start = startMinute, let end = endMinute, (0..<1440).contains(start),
        (0..<1440).contains(end),
        start != end, !weekdays.isEmpty, Set(weekdays).count == weekdays.count,
        weekdays.allSatisfy({ (1...7).contains($0) })
      else { throw MouseFailure(message: "Choose different start/end times and at least one day.") }
    } else if !weekdays.isEmpty {
      throw MouseFailure(message: "Weekdays require a time window.")
    }
  }
  func matches(app: String?, at date: Date, calendar: Calendar) -> Bool {
    guard enabled else { return false }
    if let bundleID, bundleID != app { return false }
    guard hasSchedule else { return true }
    guard let start = startMinute, let end = endMinute else { return false }
    let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
    guard let day = parts.weekday, let hour = parts.hour, let minute = parts.minute else {
      return false
    }
    let isoDay = (day + 5) % 7 + 1
    let now = hour * 60 + minute
    if start < end { return weekdays.contains(isoDay) && now >= start && now < end }
    // An overnight window belongs to its starting day, including across DST.
    if now >= start { return weekdays.contains(isoDay) }
    return now < end && weekdays.contains((isoDay + 5) % 7 + 1)
  }
}

struct AppLibrary: Codable, Equatable {
  var formatVersion = 1
  var profiles: [NamedProfile] = []
  var rules: [ActivationRule] = []
  var automationEnabled = false
  var fallbackProfileID: String?
  var preferences: [String: String] = [:]
  func validate() throws {
    guard formatVersion == 1, profiles.count <= 200, rules.count <= 200,
      Set(profiles.map(\.id)).count == profiles.count, Set(rules.map(\.id)).count == rules.count
    else {
      throw MouseFailure(
        message: "The profile library has an invalid format or duplicate identifiers.")
    }
    for profile in profiles { try profile.validate() }
    for rule in rules { try rule.validate(profiles: profiles) }
    if let fallbackProfileID, !profiles.contains(where: { $0.id == fallbackProfileID }) {
      throw MouseFailure(message: "Choose an existing fallback profile.")
    }
    if automationEnabled {
      guard fallbackProfileID != nil, rules.contains(where: { $0.enabled }) else {
        throw MouseFailure(
          message:
            "Choose a fallback profile and enable at least one rule before turning on automatic switching."
        )
      }
    }
    guard preferences.count <= 80,
      preferences.allSatisfy({ $0.key.count <= 80 && $0.value.utf8.count <= 32768 })
    else {
      throw MouseFailure(message: "The saved preferences are too large.")
    }
  }
  func selection(app: String?, at date: Date, calendar: Calendar = .autoupdatingCurrent) -> (
    NamedProfile, String
  )? {
    guard automationEnabled else { return nil }
    if let rule = rules.first(where: { $0.matches(app: app, at: date, calendar: calendar) }),
      let profile = profiles.first(where: { $0.id == rule.profileID })
    {
      return (profile, rule.name)
    }
    if let fallbackProfileID, let profile = profiles.first(where: { $0.id == fallbackProfileID }) {
      return (profile, "Fallback profile")
    }
    return nil
  }
}
