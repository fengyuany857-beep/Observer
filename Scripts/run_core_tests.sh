#!/bin/bash
set -euo pipefail
mkdir -p build/core-tests Artifacts

swiftc \
  Sources/Domain/ObserverDomain.swift \
  Sources/Domain/ObserverDataSource.swift \
  Sources/Presentation/ObserverPresentation.swift \
  Sources/Fixtures/ObserverFixtures.swift \
  Tests/ObserverCoreTests.swift \
  -o build/core-tests/ObserverCoreTests
build/core-tests/ObserverCoreTests | tee Artifacts/Observer-Core-Test-Report.txt

swiftc \
  Sources/Domain/ObserverDomain.swift \
  Sources/Domain/ObserverDataSource.swift \
  Sources/Domain/RealObserverDataSource.swift \
  Tests/ObserverTransportDataSourceTests.swift \
  -o build/core-tests/ObserverTransportDataSourceTests
build/core-tests/ObserverTransportDataSourceTests | tee -a Artifacts/Observer-Core-Test-Report.txt