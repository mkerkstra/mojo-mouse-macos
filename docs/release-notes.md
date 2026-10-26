First public release of **Mojo Mouse for macOS**, an independent controller for the wired **MOJO MJ-189 (`260d:1027`)**.

### Download the app

Choose **Mojo-Mouse-macOS-universal.dmg** for drag-to-Applications installation, or **Mojo-Mouse-macOS-universal.zip**. Both contain the executable app for **Intel and Apple Silicon**, macOS 13 or later. GitHub’s “Source code” archives are for developers.

This initial build is **ad-hoc signed, not Developer ID signed or Apple notarized**. Follow the repository’s first-launch instructions if macOS blocks it. `SHA256SUMS.txt` covers both app downloads.

### Included

- Body/wheel lighting controls and blank side display without overwriting picture storage.
- Static custom text with a 96 × 39 pixel preview.
- DPI stages, pointer scaling, polling, and button assignments.
- Named full or lighting-only profiles, import/export, and backups.
- App-specific and weekday/time switching rules, ordered priority, fallback, one-hour manual pause, and menu-bar access.
- Native local storage, no telemetry/account/network service, and read-only diagnostics.
- Experimental controls hidden by default.

### Limits

Only one physical MJ-189/HID revision `0x0316` was tested. Other models and firmware revisions are not established as compatible. Profile/button/polling writes use readback verification; that does not validate every physical action. Display changes lack readback. Macro playback, rapid fire, and lift-off behavior remain unverified experimental features. No native marquee support was established, and bitmap-streaming marquee is omitted.

The app must remain running for automatic switching. It installs no login item. See the README for exact rule, backup, recovery, and security behavior.
