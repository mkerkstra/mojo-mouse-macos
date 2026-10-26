#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
stage=$(mktemp -d build/.mojo-build.XXXXXX)
trap 'rm -rf "$stage"' EXIT
app="$stage/Mojo Mouse.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
sources=(Sources/MojoMouse/*.swift)
for arch in arm64 x86_64; do
  xcrun swiftc -warnings-as-errors -O -target "${arch}-apple-macos13.0" "${sources[@]}" -o "$stage/MojoMouse-${arch}" -framework AppKit -framework IOKit -framework WebKit
done
xcrun lipo -create "$stage/MojoMouse-arm64" "$stage/MojoMouse-x86_64" -output "$app/Contents/MacOS/MojoMouse"
cp Sources/MojoMouse/Info.plist "$app/Contents/Info.plist"
cp Sources/MojoMouse/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp Sources/MojoMouse/Resources/* "$app/Contents/Resources/"
codesign --force --sign "${CODE_SIGN_IDENTITY:--}" "$app"
codesign --verify --deep --strict "$app"
architectures=$(xcrun lipo -archs "$app/Contents/MacOS/MojoMouse")
[[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]]
# Replace only after a complete, verified build; removed resources cannot linger.
rm -rf 'build/Mojo Mouse.app'
mv "$app" 'build/Mojo Mouse.app'
printf '%s\n' 'Built universal app: build/Mojo Mouse.app'
