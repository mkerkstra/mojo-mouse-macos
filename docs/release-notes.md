## Mojo Mouse 0.3.0

- Adds a separate, opt-in **Logitech mice (Preview)…** window for live DPI and polling-rate controls on exact wired G502 Core/Spectrum/HERO, G403/HERO and G102/G203 family USB IDs.
- Discovers HID++ capabilities, validates device-advertised ranges, compares settings before each action, and requires actual setting readback after changes.
- Handles composite USB usage collections and checks existing Input Monitoring access before opening interfaces that include keyboard/pointer controls; it never requests permission automatically.
- Provides explicit live/onboard mode switching and a read-only `--diagnose-logitech` report with no serial numbers or profile contents.
- Keeps MOJO profiles and automation isolated from Logitech. No Logitech button maps, LED settings, onboard profile storage, or firmware are written.
- Preserves MIT protocol-reference notices inside executable distributions. Adds no runtime dependencies.

**Logitech support has simulated protocol tests but no physical hardware testing.** Lighting, buttons, saved profiles and app/time automation remain MJ-189-only. Receivers, Bluetooth, G502 X and other brands are not enabled. See [Logitech preview and recovery](https://github.com/mkerkstra/mojo-mouse-macos/blob/main/docs/logitech.md).

The Mac App Store edition remains MJ-189-only; its pending submission is separate from this release. The download supports Intel and Apple Silicon on macOS 13 or later. It is ad-hoc signed and not Apple notarized. Checksums accompany the DMG and ZIP.
