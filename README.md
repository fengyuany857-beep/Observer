# Observer CI + Self-Sign Pipeline V1

Purpose: develop and visually validate Observer without owning a Mac.

Pipeline:

`SwiftUI sources -> GitHub Actions macOS 26 -> Xcode 26.5 -> iPhone Simulator -> screenshots -> unsigned iphoneos build -> unsigned IPA -> user-side self-signing`

## What CI produces

- `Observer-Simulator-Snapshots.zip`
  - 18 Overview truth-state screenshots
  - Runs / Run Detail / Settings core surface screenshots
- `Observer-unsigned.ipa`
- `Observer-Signing-Report.txt` and `.json`
- core test report and build logs

## Important V1 signing boundary

V1 deliberately avoids App Groups and Push Notifications. The embedded Widget extension and local Live Activity UI are scaffolds. Remote Live Activity push updates are out of scope.

The unsigned IPA contains a main app and a nested Widget extension. Any self-signing tool must sign both the main executable and every nested `PlugIns/*.appex` executable using entitlements allowed by the chosen provisioning profile.

An IPA installing successfully is not evidence that Widget or Live Activity functionality is valid. Verify those surfaces independently after signing.

## GitHub setup

1. Put this folder at the root of a GitHub repository.
2. Push to `main`, or open Actions and run **Observer CI + Self-Sign** manually.
3. When the run finishes, download the three artifacts from the workflow run.
4. Inspect screenshots first.
5. Download `Observer-Unsigned-IPA` only when you want a phone build.
6. Re-sign the IPA on your own device/tooling, then test launch and extension discovery.

No certificate, private key, provisioning profile, Apple ID, or signing secret belongs in this repository or workflow.

## Current evidence boundary

The source/domain layer can be tested outside macOS. Actual iOS SDK compilation, Simulator launch, screenshot capture, device build, extension embedding, and unsigned IPA packaging only become verified when this workflow executes successfully on GitHub-hosted macOS.
