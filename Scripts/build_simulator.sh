#!/bin/bash
set -euo pipefail
UDID="${1:-$(python3 Scripts/find_simulator.py)}"
xcodebuild \
  -project Observer.xcodeproj \
  -scheme Observer \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath build/DerivedData \
  -skipPackagePluginValidation \
  build | tee Artifacts/Observer-Simulator-Build.log
