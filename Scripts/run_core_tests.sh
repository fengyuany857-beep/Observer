#!/bin/bash
set -euo pipefail
mkdir -p build/core-tests Artifacts

python3 Scripts/validate_b0_contract.py | tee Artifacts/Observer-B0-Contract-Test-Report.txt
python3 Scripts/test_b1_approval_broker.py | tee Artifacts/Observer-B1-Approval-Test-Report.txt
python3 Scripts/validate_b8_live_graft.py | tee Artifacts/Observer-B8-Live-Graft-Static-Report.txt
python3 Scripts/validate_uiv2_overview_live.py | tee Artifacts/Observer-UIV2-Overview-Live-Static-Report.txt
python3 Scripts/validate_uiv2_project_detail.py | tee Artifacts/Observer-UIV2-Project-Detail-Static-Report.txt
python3 Scripts/validate_uiv2_approvals_owner_control.py | tee Artifacts/Observer-UIV2-Approvals-Owner-Control-Static-Report.txt
python3 Scripts/validate_uiv2_session_close.py | tee Artifacts/Observer-UIV2-Session-Close-Static-Report.txt
python3 Scripts/validate_uiv2_deadline_ux.py | tee Artifacts/Observer-UIV2-Deadline-UX-Static-Report.txt
python3 Scripts/validate_uiv2_static_topology.py | tee Artifacts/Observer-UIV2-Static-Topology-Report.txt
python3 Scripts/validate_uiv2_ambient_topology_motion.py | tee Artifacts/Observer-UIV2-Ambient-Topology-Motion-Report.txt
python3 Scripts/validate_uiv2_semantic_motion.py | tee Artifacts/Observer-UIV2-Semantic-Motion-Report.txt

swiftc \
  Sources/Domain/ObserverDomain.swift \
  Sources/Domain/ObserverB8Truth.swift \
  Sources/Domain/ObserverDataSource.swift \
  Sources/Presentation/ObserverPresentation.swift \
  Sources/Fixtures/ObserverFixtures.swift \
  Tests/ObserverCoreTests.swift \
  -o build/core-tests/ObserverCoreTests
build/core-tests/ObserverCoreTests | tee Artifacts/Observer-Core-Test-Report.txt

swiftc \
  Sources/Domain/ObserverDomain.swift \
  Sources/Domain/ObserverB8Truth.swift \
  Sources/Domain/ObserverDataSource.swift \
  Sources/Domain/RealObserverDataSource.swift \
  Tests/ObserverTransportDataSourceTests.swift \
  -o build/core-tests/ObserverTransportDataSourceTests
build/core-tests/ObserverTransportDataSourceTests | tee -a Artifacts/Observer-Core-Test-Report.txt

swiftc \
  Sources/Domain/ObserverDomain.swift \
  Sources/Domain/ObserverB8Truth.swift \
  Sources/Domain/ObserverDataSource.swift \
  Sources/Domain/RealObserverDataSource.swift \
  Sources/Domain/ObserverRuntimeConfiguration.swift \
  Sources/Domain/ObserverOwnerControl.swift \
  Sources/Domain/ObserverOwnerConfiguration.swift \
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

swiftc \
  Sources/Domain/ObserverDomain.swift \
  Sources/Domain/ObserverB8Truth.swift \
  Sources/Domain/ObserverDataSource.swift \
  Sources/Domain/ObserverCurrentOperationOverlay.swift \
  Sources/Domain/RealObserverDataSource.swift \
  Sources/Domain/ObserverB8LiveDataSource.swift \
  Tests/ObserverB8LiveDataSourceTests.swift \
  -o build/core-tests/ObserverB8LiveDataSourceTests
build/core-tests/ObserverB8LiveDataSourceTests | tee -a Artifacts/Observer-Core-Test-Report.txt

swiftc \
  Sources/Domain/ObserverOwnerControl.swift \
  Tests/ObserverOwnerControlTests.swift \
  -o build/core-tests/ObserverOwnerControlTests
build/core-tests/ObserverOwnerControlTests | tee -a Artifacts/Observer-Core-Test-Report.txt

swiftc \
  Sources/Domain/ObserverDomain.swift \
  Sources/Domain/ObserverB8Truth.swift \
  Sources/Domain/ObserverDataSource.swift \
  Sources/Presentation/ObserverPresentation.swift \
  Sources/Presentation/ObserverDeadlinePresentation.swift \
  Tests/ObserverDeadlineUXTests.swift \
  -o build/core-tests/ObserverDeadlineUXTests
build/core-tests/ObserverDeadlineUXTests | tee -a Artifacts/Observer-Core-Test-Report.txt

swiftc \
  Sources/SwiftUI/Visual/ObserverTopologyMotion.swift \
  Tests/ObserverTopologyMotionTests.swift \
  -o build/core-tests/ObserverTopologyMotionTests
build/core-tests/ObserverTopologyMotionTests | tee -a Artifacts/Observer-Core-Test-Report.txt

swiftc \
  Sources/Domain/ObserverDomain.swift \
  Sources/Domain/ObserverB8Truth.swift \
  Sources/Domain/ObserverDataSource.swift \
  Sources/Presentation/ObserverPresentation.swift \
  Sources/Domain/ObserverOwnerControl.swift \
  Sources/SwiftUI/Visual/ObserverSemanticMotion.swift \
  Tests/ObserverSemanticMotionTests.swift \
  -o build/core-tests/ObserverSemanticMotionTests
build/core-tests/ObserverSemanticMotionTests | tee -a Artifacts/Observer-Core-Test-Report.txt
