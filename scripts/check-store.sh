#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project PointerProfiles.xcodeproj -scheme PointerProfiles -configuration Release \
  -derivedDataPath build/store CODE_SIGNING_ALLOWED=NO build
app='build/store/Build/Products/Release/PointerProfiles.app'
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist")" = io.github.mkerkstra.PointerProfiles
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundlePackageType' "$app/Contents/Info.plist")" = APPL
test "$(/usr/libexec/PlistBuddy -c 'Print LSApplicationCategoryType' "$app/Contents/Info.plist")" = public.app-category.utilities
test -f "$app/Contents/Resources/PrivacyInfo.xcprivacy"
test -f "$app/Contents/Resources/settings.html"
test -f "$app/Contents/Resources/THIRD_PARTY_NOTICES.md"
if "$app/Contents/MacOS/PointerProfiles" --diagnose-logitech; then
  echo "Logitech preview must be disabled in the store target"
  exit 1
fi
codesign --force --sign - --entitlements Distribution/Store.entitlements "$app"
codesign --verify --deep --strict "$app"
"$app/Contents/MacOS/PointerProfiles" --version
"$app/Contents/MacOS/PointerProfiles" --diagnose
