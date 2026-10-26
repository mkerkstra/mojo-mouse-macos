# Contributing

Start with an issue describing the model, USB vendor/product IDs, firmware revision, and behavior. Do not assume two MOJO models share a protocol. A matching USB ID alone is not enough evidence for a new support claim.

Run `./scripts/test.sh` and `./scripts/build.sh`. Keep hardware-independent tests deterministic and never add device writes to CI. Changes to the protocol need packet fixtures, validation, preservation checks, and explicit limits on what was physically tested.

New automatic actions should be idempotent, off by default, and recoverable where the device supports readback. Keep unverified commands behind the experimental setting. Never flash firmware or add broad USB matching to work around an unknown device.

Use small changes and explain the before/after behavior, tests, and hardware evidence. Avoid publishing private profiles, side text, app lists, serial numbers, backups, signing credentials, or the vendor’s proprietary software.

The source uses Swift/AppKit/IOKit and a bundled local HTML interface. There is no server and no frontend package runtime. Frontend scripts must work with the bundled content security policy and the native library store. No network requests or analytics should be added without an explicit design discussion.
