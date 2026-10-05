#!/bin/bash
set -euo pipefail
BUNDLE_ID="com.fnauy.observer"
UDID="${1:-$(python3 Scripts/find_simulator.py)}"
mkdir -p Artifacts/Snapshots/Overview Artifacts/Snapshots/Core3

echo "Using simulator: $UDID"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl ui "$UDID" appearance dark
xcrun simctl status_bar "$UDID" override --time "09:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 || true

APP_PATH="build/DerivedData/Build/Products/Debug-iphonesimulator/Observer.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing simulator app at $APP_PATH" >&2
  exit 1
fi
xcrun simctl install "$UDID" "$APP_PATH"

scenarios=(
  runningActiveOnline
  startingActiveOnline
  verifyingActiveOnline
  finalizingActiveOnline
  completedVerifiedPresentationUnknown
  completedPresentationConfirmed
  failedOnline
  aborted
  resumable
  waitingApproval
  runningSlow
  runningStale
  runningSuspectedStuck
  runningLastKnownOffline
  runningReconnecting
  authFailedCached
  multipleActiveAggregate
  noRunEmpty
)

for s in "${scenarios[@]}"; do
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" --scenario "$s" --surface overview >/dev/null
  sleep 1
  xcrun simctl io "$UDID" screenshot "Artifacts/Snapshots/Overview/${s}.png"
done

for surface in runs detail settings; do
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" --scenario runningActiveOnline --surface "$surface" >/dev/null
  sleep 1
  xcrun simctl io "$UDID" screenshot "Artifacts/Snapshots/Core3/${surface}.png"
done

xcrun simctl status_bar "$UDID" clear || true
find Artifacts/Snapshots -type f -name '*.png' | sort > Artifacts/Snapshot-Manifest.txt
printf 'SNAPSHOT_COUNT=%s\n' "$(find Artifacts/Snapshots -type f -name '*.png' | wc -l | tr -d ' ')" >> Artifacts/Snapshot-Manifest.txt
