#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
mkdir -p dist
app='build/Mojo Mouse.app'
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
ditto -c -k --sequesterRsrc --keepParent "$app" dist/Mojo-Mouse-macOS-universal.zip
stage=$(mktemp -d "${TMPDIR:-/tmp}/mojo-mouse-release.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Mojo Mouse.app"
ln -s /Applications "$stage/Applications"
cp LICENSE "$stage/LICENSE.txt"
cat > "$stage/Read me first.txt" <<TXT
Mojo Mouse $version for macOS

Drag Mojo Mouse into Applications, connect one wired MOJO MJ-189, and open it.
Requires macOS 13 or later. Supports Apple Silicon and Intel.
Supported USB ID: 260d:1027. Other MOJO models are not supported.

This initial release is ad-hoc signed, not Developer ID signed or Apple notarized.
If macOS blocks it and you trust the release, first try opening it, then use:
System Settings > Privacy & Security > Open Anyway.
Do not disable Gatekeeper globally.

Profiles, app/time switching rules, lighting, DPI, buttons, and static side text.
Automatic switching is off by default. It requires a fallback and an enabled rule.
Keep the app open for rules. No login item is installed.

Source, compatibility limits, checksums, support, and documentation:
https://github.com/mkerkstra/mojo-mouse-macos
TXT
hdiutil create -volname "Mojo Mouse $version" -srcfolder "$stage" -format UDZO -ov dist/Mojo-Mouse-macOS-universal.dmg
(cd dist && shasum -a 256 Mojo-Mouse-macOS-universal.zip Mojo-Mouse-macOS-universal.dmg > SHA256SUMS.txt)
printf '%s\n' 'Release assets ready in dist/'
