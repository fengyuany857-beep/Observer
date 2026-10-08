#!/bin/bash
set -euo pipefail
mkdir -p build/r4-bg
swiftc -swift-version 6 -warnings-as-errors \
  Sources/Domain/ObserverApprovalAttemptJournal.swift \
  Sources/Domain/ObserverBGApprovalActionEngine.swift \
  Tests/ObserverBGIsolatedTests.swift \
  -lsqlite3 -o build/r4-bg/bg-tests
build/r4-bg/bg-tests
