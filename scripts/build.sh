#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/bin 'build/Mojo Mouse.app/Contents/MacOS' 'build/Mojo Mouse.app/Contents/Resources'
app='build/Mojo Mouse.app'
sources=(Sources/MojoMouse/*.swift)
for arch in arm64 x86_64; do
  xcrun swiftc -O -target "${arch}-apple-macos13.0" "${sources[@]}" -o "build/bin/MojoMouse-${arch}" -framework AppKit -framework IOKit -framework WebKit
done
xcrun lipo -create build/bin/MojoMouse-arm64 build/bin/MojoMouse-x86_64 -output "$app/Contents/MacOS/MojoMouse"
cp Sources/MojoMouse/Info.plist "$app/Contents/Info.plist"
cp Sources/MojoMouse/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp Sources/MojoMouse/Resources/* "$app/Contents/Resources/"
codesign --force --sign "${CODE_SIGN_IDENTITY:--}" "$app"
codesign --verify --deep --strict "$app"
architectures=$(xcrun lipo -archs "$app/Contents/MacOS/MojoMouse")
[[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]]
printf '%s\n' "Built universal app: $app"
