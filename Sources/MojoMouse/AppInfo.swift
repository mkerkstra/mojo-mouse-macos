import Foundation

enum AppInfo {
  static var name: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Mojo Mouse"
  }
  static var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "Development"
  }
  static var build: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
  }
  static let website = URL(string: "https://github.com/mkerkstra/mojo-mouse-macos")!
  static let guide = website.appendingPathComponent("blob/main/docs/profiles-and-rules.md")
  static let support = website.appendingPathComponent("issues")
  static let privacy = website.appendingPathComponent("blob/main/PRIVACY.md")
  static let license = website.appendingPathComponent("blob/main/LICENSE")
  #if APP_STORE
    static let appStore = true
  #else
    static let appStore = false
  #endif
  static var allowsExperimental: Bool { !appStore }
}
