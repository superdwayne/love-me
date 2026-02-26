#!/bin/bash
set -e
cd "$(dirname "$0")"
echo "=== Generating Xcode project ==="
xcodegen generate
echo "=== Building ==="
xcodebuild -project LoveMeApp.xcodeproj -scheme LoveMeApp -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -80
echo "=== Done ==="
