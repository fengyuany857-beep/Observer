#!/bin/bash
set -euo pipefail
python3 Scripts/signing_report.py
[[ -f Artifacts/Observer-Signing-Report.txt ]]
[[ -f Artifacts/Observer-Signing-Report.json ]]
(
  cd Artifacts
  /usr/bin/zip -qry Observer-Simulator-Snapshots.zip Snapshots Snapshot-Manifest.txt
)
{
  echo "Observer CI Build Manifest"
  echo "generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "runner_os=${RUNNER_OS:-local}"
  echo "runner_arch=${RUNNER_ARCH:-$(uname -m)}"
  echo "xcode=$(xcodebuild -version | tr '\n' ' ')"
  echo "iphoneos_sdk=$(xcrun --sdk iphoneos --show-sdk-version)"
  echo "iphonesimulator_sdk=$(xcrun --sdk iphonesimulator --show-sdk-version)"
  echo "xcodegen=$(xcodegen --version 2>/dev/null || echo unavailable)"
  echo "unsigned_ipa_sha256=$(shasum -a 256 Artifacts/Observer-unsigned.ipa | awk '{print $1}')"
  echo "snapshot_zip_sha256=$(shasum -a 256 Artifacts/Observer-Simulator-Snapshots.zip | awk '{print $1}')"
} > Artifacts/Observer-Build-Manifest.txt
