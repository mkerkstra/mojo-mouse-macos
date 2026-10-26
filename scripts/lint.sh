#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun swift-format lint --strict --recursive Sources Tests Distribution/RenderIcon.swift
npm run format:check
for file in Sources/MojoMouse/Resources/*.js Tests/*.js; do
  node --check "$file"
done
for file in scripts/*.sh; do
  bash -n "$file"
done
plutil -lint Sources/MojoMouse/Info.plist Distribution/Store-Info.plist Distribution/Store.entitlements Sources/MojoMouse/Resources/PrivacyInfo.xcprivacy
