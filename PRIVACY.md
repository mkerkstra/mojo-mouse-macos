# Privacy policy

Effective October 25, 2026. Applies to Mojo Mouse and the Pointer Profiles Mac App Store edition, by Matthew Kerkstra.

## Data stays on your Mac

The app does not collect, sell, or transmit personal information to the developer. It has no developer-operated account, analytics, advertising, tracking, or server. No third-party runtime SDKs are included.

Profiles, button settings, side text, schedules, preferences, backups, and recent status events are stored locally. A rule may contain an application identifier you choose. Automatic switching observes the foreground application's identifier through macOS; it does not capture keystrokes, window contents, screenshots, or documents. USB commands go to the supported connected mouse.

Generated backups are limited to the newest 50 snapshots, alongside the original readable settings. Recent status history is limited to 100 events. These files are not automatically sent anywhere. The app cannot retrieve existing display content or macro memory from the mouse.

## Files, permissions, and external links

The App Store edition uses App Sandbox, USB access, and user-selected file access for profile import/export. Its settings renderer also requires WebKit's outgoing-network entitlement; the app loads only its bundled settings document, blocks remote navigation and script connections, and makes no developer-server requests.

The GitHub-only Logitech preview may encounter a composite USB interface with keyboard or pointer collections. macOS may require Input Monitoring for that interface. The app checks existing permission and blocks opening that composite interface if access is not granted; it does not request the permission automatically. It retains only HID++ configuration replies and ignores normal keyboard/pointer reports. It does not install a global event tap or record keystrokes. A monotonic system clock is used locally to bound USB reply timeouts; its values are not saved or transmitted. The broader macOS permission is optional and can be revoked in System Settings. The MJ-189 controls and App Store edition do not require it. See [Logitech compatibility and permissions](docs/logitech.md).

Opening User Guide, Support, Privacy, or Source links opens your browser. GitHub, Apple, and your browser apply their own privacy policies to those visits. If you choose to export or share a profile or post a support issue, review it first: it may contain custom side text, application identifiers, or other settings you entered. Support messages are handled by the service you choose to use.

Apple may process App Store purchases, downloads, diagnostics, or platform analytics under its own policies and your system preferences. That is separate from data collection by this app.

## Your control

Automatic switching is off until you enable it. Quit stops switching. No login item is installed. You can remove profiles and rules in the app. Local data can be removed through Finder after quitting. The direct-download edition stores it in `~/Library/Application Support/Mojo Mouse/`. The sandboxed edition stores it under its macOS app container's Application Support folder; it does not silently import another app's files. Export/import is available if you want to transfer profiles.

For privacy questions, use the repository's [support page](https://github.com/mkerkstra/mojo-mouse-macos/issues). Do not include private profiles or contact information in a public issue.
