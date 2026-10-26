import AppKit
import SwiftUI

final class AppInformationWindow: NSWindowController {
  convenience init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 610),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
      defer: false)
    window.title = "About \(AppInfo.name)"
    window.minSize = NSSize(width: 470, height: 500)
    window.isReleasedWhenClosed = false
    window.center()
    window.contentViewController = NSHostingController(rootView: AppInformationView())
    self.init(window: window)
  }
}

private struct AppInformationView: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        HStack(spacing: 16) {
          Image(nsImage: NSApp.applicationIconImage)
            .resizable().frame(width: 76, height: 76).accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 5) {
            Text(AppInfo.name).font(.largeTitle.bold())
            Text("A mouse setup for every moment.").foregroundStyle(.secondary)
            Text("Version \(AppInfo.version) (\(AppInfo.build))")
              .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
          }
        }
        Divider()
        section("Made for your MJ-189", icon: "computermouse") {
          Text(
            "Control lighting, DPI, buttons, and static side text. Save profiles for work, games, or a quieter desk."
          )
          Text(
            "Requires one wired MOJO MJ-189, USB 260d:1027. Other mouse models are not supported."
          )
          .foregroundStyle(.secondary)
        }
        section("Your settings stay here", icon: "lock.shield") {
          Text(
            "No account, analytics, advertising, or developer-operated server. Profiles, rules, and backups stay on this Mac."
          )
          Text(
            "App rules use the foreground app’s identifier. They do not read keystrokes or window contents. Switching is off until you enable it and stops when you quit."
          )
          .foregroundStyle(.secondary)
        }
        section("A few useful details", icon: "info.circle") {
          Text(
            "The app must remain open for app and time rules. Manual changes pause switching for one hour. Readable settings are backed up before changes and checked afterward."
          )
          Text(
            "Existing side-display content cannot be retrieved or backed up. Display uploads cannot be read back. No native marquee support is established."
          )
          .foregroundStyle(.secondary)
          if AppInfo.appStore {
            Text(
              "This build includes the standard controls. Experimental macro, rapid-fire, lift-off, and raw-byte editing are unavailable."
            )
            .foregroundStyle(.secondary)
          }
        }
        HStack(spacing: 18) {
          Link("User guide", destination: AppInfo.guide)
          Link("Support", destination: AppInfo.support)
          Link("Privacy", destination: AppInfo.privacy)
          Link("Source & license", destination: AppInfo.website)
        }
        .font(.callout)
        Text(
          "© 2026 Matthew Kerkstra · MIT License\nIndependent software. Not affiliated with or endorsed by MOJO. Product names belong to their owners."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      .textSelection(.enabled)
      .padding(28)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
  private func section<Content: View>(
    _ title: String, icon: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(title, systemImage: icon).font(.headline)
      content().font(.callout).fixedSize(horizontal: false, vertical: true)
    }
  }
}
