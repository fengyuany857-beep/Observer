#!/bin/bash
set -euo pipefail
PREFERRED="/Applications/Xcode_26.5.app/Contents/Developer"
if [[ -d "$PREFERRED" ]]; then
  sudo xcode-select -s "$PREFERRED"
fi
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
xcrun --sdk iphonesimulator --show-sdk-version
