# Contributing

Start with an issue describing the model, USB vendor/product IDs, firmware revision, and behavior. Do not assume two MOJO models share a protocol. A matching USB ID alone is not enough evidence for a new support claim.

Run `npm ci --ignore-scripts`, `npm run check`, `shellcheck scripts/*.sh`, and `./scripts/build.sh`. Keep hardware-independent tests deterministic and never add device writes to CI. Changes to the protocol need packet fixtures, validation, preservation checks, and explicit limits on what was physically tested.

New automatic actions should be idempotent, off by default, and recoverable where the device supports readback. Keep unverified commands behind the experimental setting. Never flash firmware or add broad USB matching to work around an unknown device.

Use small changes and explain the before/after behavior, tests, and hardware evidence. Avoid publishing private profiles, side text, app lists, serial numbers, backups, signing credentials, or the vendor’s proprietary software.

The source uses Swift/AppKit/IOKit and a bundled local HTML interface. There is no server and no frontend package runtime. Frontend scripts must work with the bundled content security policy and the native library store. No network requests or analytics should be added without an explicit design discussion.

## Code and dependency hygiene

Use Xcode 16 or newer (including its bundled `swift-format`), Node.js 24, npm 11, and ShellCheck. `.node-version`, package engines, `.editorconfig`, `.swift-format`, and Prettier define the shared environment and style. Run `npm run format` and `xcrun swift-format format --in-place --recursive Sources Tests` to format edits. `npm run check` runs strict Swift lint, frontend formatting and syntax, shell syntax, plist validation, native tests, and control-encoding tests. Build and test compilation treat warnings as errors. ShellCheck runs in the shared CI validation workflow.

The app has no third-party runtime packages. Prettier is the only npm dependency, is development-only, is pinned exactly, and has its registry integrity recorded in `package-lock.json`. Keep dependency additions justified and small; review ownership, license, maintenance, install scripts, and transitive dependencies. Commit the manifest and lockfile together. Use `npm ci --ignore-scripts` for clean installs; repository npm settings also disable lifecycle scripts. Never replace version pins with floating ranges merely to silence an audit.

CI audits all npm dependencies, including development tools, and fails on reported vulnerabilities of any severity. An unavailable audit service also fails the job so a missing result cannot appear clean. Dependabot proposes weekly npm and GitHub Actions updates and security fixes. Review and test those pull requests; no automatic merging is configured. An audit with no findings describes known advisories, not proof that all code is safe.

CI and release validation share one workflow and exercise Intel and Apple Silicon. Remote Actions use full commit hashes, checkout credentials are not persisted, and repository policy requires action pinning. Tokens default to read-only; only the release publishing job can write contents. Published releases are not overwritten by a workflow rerun. Build output is assembled in a temporary directory and replaces the previous app only after successful signing and verification, so removed resources cannot leak into a new package.
