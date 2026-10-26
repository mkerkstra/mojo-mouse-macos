# Profiles and switching rules

## Named profiles

A profile captures readable mouse settings and an optional display policy. **Complete readable settings** includes the sensor profile, button map, and polling rate. **Lighting only** merges body and wheel lighting into the current profile, preserving buttons, DPI, X/Y scaling, polling, and other bytes.

Display policies are **Leave unchanged**, **Blank display**, **MOJO logo**, or **Custom text**. Leave unchanged is deliberate: there is no reliable way to retrieve and restore the mouse’s existing display content. Blank display uses an empty text image and never assumes the picture slot is blank.

Profiles can be saved, renamed, duplicated, updated from the draft, exported, and imported. Importing changes the draft only. Apply now writes the selected profile and pauses automatic switching for an hour. A profile used by a rule or fallback cannot be deleted until those references are removed.

Profiles and rules stay on the Mac, not as multiple independently addressable hardware profiles. One selected setup is sent to the connected mouse.

## Rules

Create a profile for your usual setup and select it as the fallback. Add rules in priority order. Automatic switching is off until explicitly enabled and saved. Both a fallback and an enabled rule are required.

Examples:

| Rule           | App                   | Time                 | Result                                       |
| -------------- | --------------------- | -------------------- | -------------------------------------------- |
| Editor         | `com.example.Editor`  | None                 | Work profile whenever that app is foreground |
| Quiet evenings | Any                   | 22:00–07:00, daily   | Lights-off profile overnight                 |
| Game evenings  | Your game’s bundle ID | 18:00–23:00, Fri/Sat | Gaming profile only when both match          |

The first enabled rule that matches wins. Reorder with Move up/down. If none matches, the fallback applies. Choose a running app from the form or enter its bundle identifier. Only its identifier is used; no document titles, window contents, or input events are read.

Times use the Mac’s current time zone. Start is inclusive, end is exclusive. An overnight window belongs to its starting day: Friday 22:00–07:00 includes Saturday morning. Daylight-saving transitions are evaluated by local weekday/hour/minute, rather than adding a fixed 24-hour duration.

App changes are debounced by half a second. Time rules are evaluated every 15 seconds, so an idle time boundary may take up to about 15 seconds plus USB work to apply. The same profile is not repeatedly sent. Reconnection resets that suppression.

## Manual override and lifecycle

Manual profile applications and settings changes pause automatic switching for an hour. Resume from the rules page or menu bar. Changing/saving rules clears the pause so the new rules can run. Switching waits while Mojo Mouse itself is foreground to protect draft editing.

Keep the app open. With automatic switching enabled, closing its windows leaves the menu-bar app running. Quit stops all switching. The app installs no login item and does not automatically reopen after login.

The engine waits through disconnects and sleep, then reevaluates after reconnect/wake. USB failures are reported locally and retried with a backoff from 30 seconds up to five minutes. Do not run two different mouse configuration utilities at the same time.

## Recovery

Before changing readable settings, the app stores a backup. The newest 50 generated snapshots are retained alongside the immutable original. A failed multi-part application attempts rollback using the same connection and verifies the original sensor profile, button map, and rate. If disconnected, rollback may be impossible; the app says so rather than claiming success.

A side-display failure can happen after readable settings were successfully saved. That case is reported separately. The original display cannot be recovered from hardware. Macros and rapid-fire recipes are not uploaded by automatic rules.

Automatic switching always uses the stable native write policy, even when experimental editing is enabled. Existing unverified button bindings can be preserved unchanged, but importing or switching to changed experimental bindings or unknown vendor bytes requires a manual experimental application. Such changes are rejected by rules.
