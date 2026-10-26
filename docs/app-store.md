# Mac App Store edition

Pointer Profiles is the independently branded store edition of Mojo Mouse. It uses the same Swift/AppKit/IOKit controller and bundled local settings UI, with a native SwiftUI information window. Its bundle ID is `io.github.mkerkstra.PointerProfiles`. The current store version is 1.0, build 1. The developer team is the same team used for Glasswright.

The store target uses App Sandbox, hardened runtime, USB access, user-selected file import/export, and the outgoing-network entitlement required to start WebKit's local settings renderer. Remote navigation and connections are blocked by the bundled page's content security policy and native navigation policy. No private APIs, temporary sandbox exceptions, input monitoring, driver extensions, root helper, cloud service, or tracking SDKs are used.

Experimental macro, rapid-fire, lift-off, and raw-byte changes are disabled by the native `APP_STORE` build policy as well as the UI. Standard profile changes are read back and verified. Hardware support remains limited to the wired MJ-189 (`260d:1027`), with one physical HID revision tested. Apple approval is separate from a successful local build or upload.

## Build

Open `PointerProfiles.xcodeproj` and select the PointerProfiles scheme. The project is committed, so building it does not require XcodeGen. `project.yml` is the optional source for regenerating the project with XcodeGen 2.46.0. Keep generated project changes and the specification together. Signing requires a matching Apple developer account; do not commit profiles, keys, archives, or account files.

Run `./scripts/check-store.sh` to compile, ad-hoc sign, and inspect a sandboxed build without developer-account credentials. CI performs this check on Apple Silicon and Intel. Physical hardware checks must still be performed separately. Local data lives inside the app's container. Export/import provides an explicit path from the direct-download edition.

Before submitting a new version, archive with Xcode, export through App Store Connect distribution using the correct team, verify entitlements, icons, privacy manifest, executable name, version/build, and complete listing metadata. Review requires a physical MJ-189 for hardware behavior; state that clearly and provide any resources requested by App Review. Do not claim a simulator or preview validates USB writes.
