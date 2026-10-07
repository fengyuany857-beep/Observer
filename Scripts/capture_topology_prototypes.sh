#!/bin/bash
set -euo pipefail

BUNDLE_ID="com.fnauy.observer"
UDID="${1:-$(python3 Scripts/find_simulator.py)}"
OUT_DIR="Artifacts/TopologyPrototypes"
mkdir -p "$OUT_DIR"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl ui "$UDID" appearance dark
xcrun simctl status_bar "$UDID" override --time "09:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 || true

APP_PATH="build/DerivedData/Build/Products/Debug-iphonesimulator/Observer.app"
test -d "$APP_PATH"
xcrun simctl install "$UDID" "$APP_PATH"

DATA_CONTAINER="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)"
mkdir -p "$DATA_CONTAINER/Documents"

capture() {
  local preset="$1"
  local filename="$2"

  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  sleep 0.5
  xcrun simctl launch "$UDID" "$BUNDLE_ID" --topology-preset "$preset" --snapshot-ci-ready
  sleep 3

  xcrun simctl io "$UDID" screenshot "$OUT_DIR/$filename"
  test -s "$OUT_DIR/$filename"
}

capture A "A-barely-there.png"
capture B "B-balanced.png"
capture C "C-upper-bound.png"

xcrun simctl status_bar "$UDID" clear || true
cd Artifacts
zip -qry Observer-Topology-Prototypes.zip TopologyPrototypes
