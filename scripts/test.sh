#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
sources=()
for file in Sources/MojoMouse/*.swift; do
  case "$file" in */main.swift|*/SettingsWindow.swift) ;; *) sources+=("$file");; esac
done
xcrun swiftc -warnings-as-errors "${sources[@]}" Tests/main.swift -o build/tests/core -framework AppKit -framework IOKit
build/tests/core
node Tests/encoding.test.js
