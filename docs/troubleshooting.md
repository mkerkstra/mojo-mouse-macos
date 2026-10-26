# Troubleshooting

## macOS blocks the downloaded app

The initial public binary is ad-hoc signed, not Developer ID signed or Apple notarized. If you trust the release, first try opening it, then use System Settings → Privacy & Security → Open Anyway. Follow [Apple’s official instructions](https://support.apple.com/en-us/102445). Do not disable Gatekeeper globally or run blanket quarantine-removal scripts. You can instead build the source locally.

## Mouse not found

Connect exactly one wired MJ-189 by USB. Other MOJO models are unsupported. Try a direct port rather than a hub, reconnect, and click Reload mouse. Normal pointing should continue even when the configuration interface is unavailable. Close other configuration utilities.

For a read-only report:

```bash
"/Applications/Mojo Mouse.app/Contents/MacOS/MojoMouse" --diagnose
```

The report omits serial numbers, profile contents, app lists, usernames, and local paths. Inspect it before sharing. A device with matching IDs but another firmware revision may still be incompatible.

## Rules do not switch

Save the rules, choose a fallback, and enable at least one rule. Return to another app; Mojo Mouse intentionally pauses evaluation while its own editor is foreground. Check for a manual one-hour pause, weekday mismatch, rule priority, or an overnight window assigned to the previous starting day. Resume from the menu bar. Keep the app running.

After a USB failure, switching retries with backoff. Check Advanced → Show recent status events. Disconnect/reconnect may take until the next schedule evaluation.

## Applying a profile failed

Reload before retrying. Readable settings are checked before and after writes. If another utility changed them, the draft is rejected rather than overwriting a stale snapshot. A failed application attempts verified rollback; a disconnect can prevent recovery. Backups are under `~/Library/Application Support/Mojo Mouse/Backups/`; use Saved profiles → Import profile to review one, then apply it.

Display changes are separate and cannot be verified by readback. A display failure after profile success is reported as a partial result.

## Library cannot be read

Quit the app and copy `~/Library/Application Support/Mojo Mouse/library.json` somewhere safe. The app preserves corrupt or unsupported data instead of resetting it. Check recent exports/backups. If you choose to start fresh, rename the library file while the app is closed; keep the original for recovery. Do not post private side text, app identifiers, or profiles in a public issue.

## Text is too long

The panel is only 96 × 39 pixels. Short messages are easiest to read. The exact pixel preview shows wrapping and shrinking. Reduce the text if it cannot fit. Marquee is intentionally omitted.

## Logitech preview

Use **Logitech mice (Preview)…** from the app menu for a listed wired Logitech device. The MOJO settings editor intentionally remains MJ-189-only. See [exact IDs and recovery](logitech.md). If live controls fail, **Use onboard settings** remains available independently of DPI/rate reads. Refresh after an error: a failed command may still have taken effect. `--diagnose-logitech` is the read-only compatibility report; `--diagnose` remains the MOJO report. No Logitech lighting or profile automation is enabled yet.
