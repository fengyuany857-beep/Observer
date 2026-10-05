#!/bin/bash
set -euo pipefail
rm -rf build/DerivedDataDevice build/Payload Artifacts/Observer-unsigned.ipa
xcodebuild \
  -project Observer.xcodeproj \
  -scheme Observer \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedDataDevice \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build | tee Artifacts/Observer-Device-Unsigned-Build.log
APP_PATH="build/DerivedDataDevice/Build/Products/Release-iphoneos/Observer.app"
[[ -d "$APP_PATH" ]] || { echo "Observer.app not found" >&2; exit 1; }
mkdir -p build/Payload
cp -R "$APP_PATH" build/Payload/Observer.app
(
  cd build
  /usr/bin/zip -qry ../Artifacts/Observer-unsigned.ipa Payload
)
