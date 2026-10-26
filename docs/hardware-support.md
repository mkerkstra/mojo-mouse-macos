# Hardware support and evidence

The initial implementation was tested with one wired **MOJO Pro Performance Silent Gaming Mouse, model MJ-189**. It identifies as `HOLTEK USB-HID MOUSE`, USB vendor `260d`, product `1027`, with HID version `0316`.

The controller opens only its vendor-specific HID interface, usage page/usage `ff01:ff01`. It does not seize normal mouse input, request global input monitoring, or flash firmware. Zero matching devices and multiple matching devices block writes.

## Logitech preview

The direct download has an opt-in [wired Logitech DPI/rate preview](logitech.md). It has **no physical acceptance evidence**. Its exact IDs, mode changes, limitations and read-only diagnostics are documented separately. The MOJO observations below do not apply to Logitech. The store target disables this preview.

## What was tested

- Reading a 128-byte sensor/lighting profile, a 128-byte button map, and polling rate.
- Turning body and wheel lights off and restoring their previous values; complete byte-for-byte readback matched. Non-lighting bytes remained unchanged.
- Sending an unchanged button map and reading it back without alteration.
- Changing polling rate and restoring it; readback matched.
- Rendering and sending custom static side text, visually confirmed on the mouse.
- Selecting a blank side picture, visually confirmed on that particular device. The public app instead sends an empty text image so other users’ picture contents are irrelevant.
- Hardware-independent tests for profile validation, lighting-only merges, app/time rule selection, overnight/DST behavior, native persistence, rollback, and disconnect handling.

Readback verifies stored bytes, not every possible physical button action. Intel CI verifies builds and code execution, not USB behavior on an Intel-connected physical mouse. Other firmware revisions and other models remain untested.

## Not established

Macro playback, every shortcut/media action, rapid fire, lift-off behavior, every display information mode, and long-term firmware endurance are not fully acceptance-tested. These limitations must not be turned into broad compatibility claims.

The vendor API does not reliably return existing macro contents, display contents/mode, rapid-fire configuration, or lift-off height. The app distinguishes commands sent from values verified. Experimental controls are hidden by default. No native marquee command was established, and continuous bitmap streaming is not included.

## Reporting another device

Use the compatibility issue template and the app’s read-only `--diagnose` command. Include model, USB ID, firmware/HID revision if known, architecture, macOS version, feature tested, and observed result. Omit serial numbers and private profiles. Do not change the USB allowlist just to force a test on an unrelated model.
