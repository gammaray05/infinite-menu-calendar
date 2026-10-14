#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/native-test
cp scripts/NativeIntegration.swift build/native-test/main.swift
xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 \
  Sources/CalendarCore/CalendarEngine.swift \
  Sources/InfiniteCalendar/Preferences.swift \
  Sources/InfiniteCalendar/CalendarScrollView.swift \
  Sources/InfiniteCalendar/Views.swift \
  build/native-test/main.swift -o build/native-test/NativeIntegration
build/native-test/NativeIntegration 2>&1 | tee build/native-tests.log
