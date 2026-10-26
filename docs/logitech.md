# Logitech USB preview

The GitHub download includes a separate **Logitech mice (Preview)…** window, available from the app menu, menu bar, and main window. It implements live DPI and polling-rate controls using native Swift and macOS IOKit. It does not require G Hub, an account, an online service, Python, a driver, or Accessibility permission.

**No physical Logitech mouse was available for testing this release.** Protocol fixtures and simulated-device tests are evidence about the implementation, not hardware compatibility. The App Store edition keeps this preview disabled and remains MJ-189-only.

## Exact candidate devices

| Wired mouse                  | USB ID      |
| ---------------------------- | ----------- |
| G502 Proteus Core            | `046d:c07d` |
| G502 Proteus Spectrum        | `046d:c332` |
| G502 HERO                    | `046d:c08b` |
| G403                         | `046d:c083` |
| G403 HERO                    | `046d:c08f` |
| G102 / G203 family           | `046d:c084` |
| G102 / G203 LIGHTSYNC family | `046d:c092` |
| G102 / G103 / G203 family    | `046d:c09d` |

IDs come from the pinned MIT-licensed [libratbag device definitions](https://github.com/libratbag/libratbag/tree/8235b5bb6032dea15901ab58a8218956f4494d08/data/devices). Marketing names alone are insufficient: firmware revisions can expose different capabilities. Only USB interfaces with a vendor collection and both input and output HID++ long reports are candidates. Discovery checks all top-level usage pairs, rather than only the primary usage: Logitech can share its configuration interface with a keyboard collection. Standalone normal pointer/keyboard interfaces without HID++ vendor reports are excluded; the selected configuration interface is opened with shared access and never seized. Only HID++ reports are retained or processed; keyboard and normal pointer reports are ignored. The selected interface must keep the same connection identity; reconnecting requires scanning again.

Receivers, Bluetooth, G502 LIGHTSPEED, G502 X variants, MX-series mice, Razer, Corsair, SteelSeries, and arbitrary USB devices are **not enabled**. A supported upstream driver is a research lead, not proof of macOS behavior. New backends need a license/protocol review, an exact device/interface boundary, meaningful tests, and physical acceptance evidence before becoming verified support. Never change a VID/PID just to force another device through this backend.

## macOS permissions

A composite Logitech configuration interface can include keyboard or pointer controls. macOS may require **Input Monitoring** to open that interface. Before opening a composite interface the app checks existing access with Apple's `IOHIDCheckAccess`; it does not call `IOHIDRequestAccess`, prompt for the permission, open System Settings, or attempt to bypass macOS protections. Without granted access it reports the limitation and sends no commands. Vendor-only interfaces are attempted without that permission; macOS can still reject access.

If you choose to use the preview on a composite device, review what this broad macOS permission permits. In System Settings → Privacy & Security → Input Monitoring, use **+** to add **`/Applications/Mojo Mouse.app`**, then enable its toggle and restart the app. Because the app never requests access itself, it may not already appear in the list. With an ad-hoc-signed download, an update can invalidate a previous grant: remove the old entry, add the updated app again, and restart it. A diagnostic launched from Terminal can have different permission attribution; use the GUI to investigate access rather than granting Terminal broad access solely for this utility. You can leave it denied and use the MOJO controls. The app ignores key and normal pointer reports and contains no global event tap, key logger, or remote telemetry, but the system permission itself is broader than mouse settings. This requirement still needs verification on each hardware/macOS combination.

## Controls and recovery

1. Connect a listed wired mouse and choose **Logitech mice (Preview)… → Scan USB**. Selecting a device only reads capabilities and current values. Quit other mouse configuration utilities if reads time out.
2. Check **Enable experimental controls for this session**. It resets when the app restarts; merely checking it sends no settings.
3. If the device is in onboard mode, choose **Use live controls**. This explicitly selects HID++ host mode. It may change DPI-button behavior; the app does not emulate buttons or macros.
4. Set DPI or polling rate individually. Only firmware-advertised DPI values/ranges and rates are accepted. Each action compares freshly read settings with those shown and reads settings again afterward. A protocol acknowledgement alone never counts as verification.
5. Choose **Use onboard settings** to return to saved hardware profiles. This remains available when the preview checkbox is off, including after failed DPI/rate reads. You can reopen the preview after relaunching to do this. Power cycling may also reset live values; do not rely on persistence.

This preview does not overwrite onboard profile storage or flash firmware, change button maps, or send RGB commands. It does not save Logitech backups or provide automatic rollback. If a write or readback fails, further DPI/rate changes are blocked until a successful refresh; onboard recovery remains available. A failed write can still have taken effect: inspect the refreshed values and return to onboard mode if necessary. The app does not switch modes on exit or silently configure devices in the background.

Lighting, side text, button remapping, macros, saved profiles and app/time rules remain **MJ-189-only**. G502 variants expose different LED features (`0x8070` / `0x8071`) and onboard memory formats. Those feature IDs are reported for diagnostics, but neither LED feature is written. Support for these should wait for hardware testing, rather than extrapolating MOJO packets or rewriting unverified Logitech memory sectors.

## Useful compatibility reports

The read-only command below reports candidate model/USB ID and, when exactly one interface is found, HID++ feature IDs, current mode, DPI, and polling interval. It never selects host mode or changes a setting. It omits serial numbers, connection identifiers, app lists, and saved profile contents.

```bash
"/Applications/Mojo Mouse.app/Contents/MacOS/MojoMouse" --diagnose-logitech
```

Attach its output to a [compatibility issue](https://github.com/mkerkstra/mojo-mouse-macos/issues/new?template=compatibility.yml) with macOS version, Intel/Apple Silicon, whether connected directly or through a hub, and the behavior tested. Verify normal movement and buttons, DPI/rate readback, mode recovery, disconnect/reconnect, and sleep/wake. Avoid private profile contents or serial numbers. Do not call support hardware-verified based only on a successful build or simulated test.

## Licensing

Protocol layouts are informed by MIT-licensed libratbag, with the pinned source and full notices in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md), also included in the executable bundle. No GPL application or proprietary vendor code is incorporated. No additional runtime dependencies are introduced. This is an independent utility and is not affiliated with Logitech or MOJO.
