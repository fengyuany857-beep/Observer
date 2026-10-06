#!/bin/bash
set -euo pipefail
mkdir -p build/core-tests Artifacts

python3 Scripts/validate_b0_contract.py | tee Artifacts/Observer-B0-Contract-Test-Report.txt
python3 Scripts/test_b1_approval_broker.py | tee Artifacts/Observer-B1-Approval-Test-Report.txt

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

swiftc \
  Sources/Domain/ObserverDomain.swift \
  Sources/Domain/ObserverDataSource.swift \
  Sources/Domain/RealObserverDataSource.swift \
  Sources/Domain/ObserverRuntimeConfiguration.swift \
  Tests/ObserverRuntimeConfigurationTests.swift \
  -framework Security \
  -o build/core-tests/ObserverRuntimeConfigurationTests
build/core-tests/ObserverRuntimeConfigurationTests | tee -a Artifacts/Observer-Core-Test-Report.txt

swiftc \
  Sources/Domain/ObserverDomain.swift \
  Sources/Domain/ObserverCurrentOperationOverlay.swift \
  Tests/ObserverCurrentOperationOverlayTests.swift \
  -o build/core-tests/ObserverCurrentOperationOverlayTests
build/core-tests/ObserverCurrentOperationOverlayTests | tee -a Artifacts/Observer-Core-Test-Report.txt
