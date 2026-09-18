#!/usr/bin/env bash
# Build, install and launch on a visionOS simulator, then save a screenshot.
#
#   scripts/run-simulator.sh [device-udid]
#
# With no argument it uses the first booted visionOS device, or creates one.
set -euo pipefail

cd "$(dirname "$0")/.."

# One xcodebuild at a time on this machine — two at once is what brings it down.
if pgrep -x xcodebuild > /dev/null; then
  echo "another xcodebuild is running; waiting for it to finish"
  while pgrep -x xcodebuild > /dev/null; do sleep 10; done
fi

udid="${1:-}"
if [ -z "$udid" ]; then
  udid=$(xcrun simctl list devices booted -j | python3 -c "
import json,sys
devices = json.load(sys.stdin)['devices']
booted = [d['udid'] for rt, ds in devices.items() if 'xrOS' in rt for d in ds]
print(booted[0] if booted else '')")
fi
if [ -z "$udid" ]; then
  device=$(xcrun simctl list devicetypes -j | python3 -c "
import json,sys
print([d['identifier'] for d in json.load(sys.stdin)['devicetypes'] if 'Vision-Pro' in d['identifier']][0])")
  runtime=$(xcrun simctl list runtimes -j | python3 -c "
import json,sys
print([r['identifier'] for r in json.load(sys.stdin)['runtimes'] if r['platform']=='xrOS' and r['isAvailable']][0])")
  udid=$(xcrun simctl create "Parallax Vision" "$device" "$runtime")
  xcrun simctl boot "$udid"
fi
xcrun simctl bootstatus "$udid" -b > /dev/null

xcodegen generate
xcodebuild -project Parallax.xcodeproj -scheme Parallax \
  -destination "platform=visionOS Simulator,id=$udid" \
  -configuration Debug -derivedDataPath build build

xcrun simctl install "$udid" build/Build/Products/Debug-xrsimulator/Parallax.app
xcrun simctl launch "$udid" com.parallax.app
sleep 8
xcrun simctl io "$udid" screenshot --type=png build/screenshot.png
echo "screenshot: build/screenshot.png"

# The simulator is the heaviest thing this Mac runs; leave it shut when done.
echo "when finished: xcrun simctl shutdown $udid"
