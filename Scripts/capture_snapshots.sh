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
DATA_CONTAINER="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)"
mkdir -p "$DATA_CONTAINER/Documents"

capture_surface() {
  local scenario="$1"
  local surface="$2"
  local output="$3"
  local ready="$DATA_CONTAINER/Documents/observer-snapshot-ready-${scenario}-${surface}"

  local launch_attempt ready_attempt
  local ready_ok=0

  for launch_attempt in 1 2 3; do
    echo "Capture scenario=$scenario surface=$surface attempt=$launch_attempt"
    rm -f "$ready"
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
    sleep 0.4

    if ! xcrun simctl launch "$UDID" "$BUNDLE_ID" --scenario "$scenario" --surface "$surface" --snapshot-ci-ready; then
      echo "Launch failed: scenario=$scenario surface=$surface attempt=$launch_attempt" >&2
      sleep 1
      continue
    fi

    for ready_attempt in $(seq 1 75); do
      if [[ -f "$ready" ]]; then
        ready_ok=1
        break
      fi
      sleep 0.2
    done

    if [[ "$ready_ok" -eq 1 ]]; then
      break
    fi

    echo "Readiness timeout: scenario=$scenario surface=$surface attempt=$launch_attempt" >&2
    xcrun simctl spawn "$UDID" log show --style compact --last 30s --predicate 'process == "Observer"' 2>/dev/null | tail -n 80 || true
    sleep 1
  done

  if [[ "$ready_ok" -ne 1 ]]; then
    echo "Snapshot readiness failed after 3 attempts: scenario=$scenario surface=$surface" >&2
    exit 1
  fi

  sleep 0.6
  xcrun simctl io "$UDID" screenshot "$output"
  test -s "$output"

  local width height
  width="$(sips -g pixelWidth "$output" | awk '/pixelWidth/ {print $2}')"
  height="$(sips -g pixelHeight "$output" | awk '/pixelHeight/ {print $2}')"
  if [[ -z "$width" || -z "$height" || "$width" -lt 500 || "$height" -lt 1000 ]]; then
    echo "Invalid screenshot dimensions: $output width=$width height=$height" >&2
    exit 1
  fi
}

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
  capture_surface "$s" "overview" "Artifacts/Snapshots/Overview/${s}.png"
done

for surface in runs detail settings; do
  capture_surface "runningActiveOnline" "$surface" "Artifacts/Snapshots/Core3/${surface}.png"
done

xcrun simctl status_bar "$UDID" clear || true
find Artifacts/Snapshots -type f -name '*.png' | sort > Artifacts/Snapshot-Manifest.txt
COUNT="$(find Artifacts/Snapshots -type f -name '*.png' | wc -l | tr -d ' ')"
printf 'SNAPSHOT_COUNT=%s\n' "$COUNT" >> Artifacts/Snapshot-Manifest.txt
if [[ "$COUNT" -ne 21 ]]; then
  echo "Expected 21 snapshots, found $COUNT" >&2
  exit 1
fi
