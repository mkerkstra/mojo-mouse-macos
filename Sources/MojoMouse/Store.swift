import Foundation

final class LibraryStore {
  static let shared = LibraryStore()
  let directory: URL
  private let lock = NSLock()
  init(directory: URL? = nil) {
    self.directory =
      directory
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Mojo Mouse", isDirectory: true)
  }
  private var libraryURL: URL { directory.appendingPathComponent("library.json") }
  private func readUnlocked() throws -> AppLibrary {
    guard FileManager.default.fileExists(atPath: libraryURL.path) else { return AppLibrary() }
    let data = try Data(contentsOf: libraryURL)
    guard data.count <= 4_000_000 else {
      throw MouseFailure(message: "The profile library is too large to read.")
    }
    let library = try JSONDecoder().decode(AppLibrary.self, from: data)
    try library.validate()
    return library
  }
  func read() throws -> AppLibrary {
    lock.lock()
    defer { lock.unlock() }
    return try readUnlocked()
  }
  @discardableResult func update(_ edit: (inout AppLibrary) throws -> Void) throws -> AppLibrary {
    lock.lock()
    defer { lock.unlock() }
    var library = try readUnlocked()
    try edit(&library)
    try library.validate()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(library)
    guard data.count <= 4_000_000 else {
      throw MouseFailure(message: "The profile library exceeds its size limit.")
    }
    try data.write(to: libraryURL, options: .atomic)
    return library
  }
  func setPreference(_ key: String, _ value: String) throws {
    let allowed = ["sideText", "rapid", "experimental", "lastPage"]
    guard allowed.contains(key) || (1...16).contains(where: { key == "macro\($0)" }) else {
      throw MouseFailure(message: "Unknown preference.")
    }
    _ = try update { $0.preferences[key] = value }
  }
  func captureOriginal(_ snapshot: FullSnapshot) throws {
    try snapshot.validate()
    lock.lock()
    defer { lock.unlock() }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("original-profile-backup.json")
    if !FileManager.default.fileExists(atPath: file.path) {
      try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
    }
  }
  func original() throws -> FullSnapshot {
    let snapshot = try JSONDecoder().decode(
      FullSnapshot.self,
      from: Data(contentsOf: directory.appendingPathComponent("original-profile-backup.json")))
    try snapshot.validate()
    return snapshot
  }
  func backup(_ snapshot: FullSnapshot) throws {
    try captureOriginal(snapshot)
    let folder = directory.appendingPathComponent("Backups", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(snapshot).write(
      to: folder.appendingPathComponent("snapshot-\(UUID().uuidString).json"), options: .atomic)
    // Retain the original separately and the newest 50 generated snapshots.
    let files = try FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: [.contentModificationDateKey]
    )
    .filter { $0.lastPathComponent.hasPrefix("snapshot-") && $0.pathExtension == "json" }
    .sorted { left, right in
      let l =
        (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        ?? .distantPast
      let r =
        (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        ?? .distantPast
      return l == r ? left.lastPathComponent > right.lastPathComponent : l > r
    }
    for old in files.dropFirst(50) { try? FileManager.default.removeItem(at: old) }

  }
  func appendEvent(_ message: String) {
    lock.lock()
    defer { lock.unlock() }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let path = directory.appendingPathComponent("recent-events.json")
      var events = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: path))) ?? []
      let stamp = ISO8601DateFormatter().string(from: Date())
      events.append("\(stamp) \(message)")
      // This is a fixed-size status history, separate from profile backups.
      if events.count > 100 { events = Array(events.suffix(100)) }
      try JSONEncoder().encode(events).write(to: path, options: .atomic)
    } catch {
      // Logging must not turn a successful hardware operation into a failure.
    }
  }
  func events() -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return
      (try? JSONDecoder().decode(
        [String].self,
        from: Data(contentsOf: directory.appendingPathComponent("recent-events.json")))) ?? []
  }
}

final class LightingStore {
  let directory = LibraryStore.shared.directory
  func baseline(for state: MouseState) throws -> Lighting {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let path = directory.appendingPathComponent("profile-\(state.profile)-lighting.json")
    if FileManager.default.fileExists(atPath: path.path) {
      let lighting = try JSONDecoder().decode(Lighting.self, from: Data(contentsOf: path))
      guard lighting.body.count == 6, lighting.wheel.count == 24 else {
        throw MouseFailure(message: "The saved lighting backup is invalid.")
      }
      return lighting
    }
    let lighting = state.lighting
    try JSONEncoder().encode(lighting).write(to: path, options: .atomic)
    return lighting
  }
}
