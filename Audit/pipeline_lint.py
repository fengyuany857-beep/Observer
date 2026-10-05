#!/usr/bin/env python3
from pathlib import Path
import re, sys, json
try:
    import yaml
except Exception as e:
    print('PyYAML unavailable:', e)
    sys.exit(2)
root=Path(__file__).resolve().parents[1]
checks=[]
def check(name, cond, detail=''):
    checks.append((name,bool(cond),detail))
project=yaml.safe_load((root/'project.yml').read_text())
workflow=yaml.safe_load((root/'.github/workflows/observer-ci.yml').read_text())
project_text=(root/'project.yml').read_text()
workflow_text=(root/'.github/workflows/observer-ci.yml').read_text()
app=(root/'App/ObserverApp.swift').read_text()
fixtures=(root/'Sources/Fixtures/ObserverFixtures.swift').read_text()
capture=(root/'Scripts/capture_snapshots.sh').read_text()
unsigned=(root/'Scripts/build_unsigned_ipa.sh').read_text()
widget=(root/'WidgetExtension/ObserverWidgets.swift').read_text()
readme=(root/'README.md').read_text()

check('targets_exact', set(project.get('targets',{}))=={'Observer','ObserverWidgets'})
check('main_bundle_id', 'com.fnauy.observer' in project_text)
check('extension_bundle_id', 'com.fnauy.observer.widgets' in project_text)
check('extension_embedded', 'target: ObserverWidgets' in project_text and 'embed: true' in project_text)
check('no_app_group_v1', 'application-groups' not in project_text and 'group.com.' not in project_text)
check('no_push_entitlement_v1', 'aps-environment' not in project_text)
check('live_activity_plist', 'NSSupportsLiveActivities: true' in project_text)
check('remote_live_activity_not_frequent', 'NSSupportsLiveActivitiesFrequentUpdates: false' in project_text)
check('widget_extension_point', 'com.apple.widgetkit-extension' in project_text)
check('local_live_activity_widget', 'ActivityConfiguration' in widget)
check('workflow_macos26', 'runs-on: macos-26' in workflow_text)
check('workflow_xcode26_5', 'Select Xcode 26.5' in workflow_text)
check('workflow_readonly_permissions', re.search(r'permissions:\s*\n\s*contents: read',workflow_text) is not None)
check('checkout_current_major', 'actions/checkout@v7' in workflow_text)
check('artifact_current_major', 'actions/upload-artifact@v7' in workflow_text)
check('device_signing_disabled', 'CODE_SIGNING_ALLOWED=NO' in unsigned and 'CODE_SIGNING_REQUIRED=NO' in unsigned)
check('generic_ios_device_build', "generic/platform=iOS" in unsigned)
check('payload_ipa_packaging', 'Payload/Observer.app' in unsigned and 'Observer-unsigned.ipa' in unsigned)
check('scenario_cli', '--scenario' in app and '--surface' in app)
check('detail_initializer_shape', 'RunDetailSummaryView(presentation: detail)' in app and 'connectionIncident:' not in app)
scenario_block=fixtures.split('public enum ObserverPreviewScenario')[1].split('public var ordinal')[0]
scenarios=re.findall(r'^\s*case\s+(\w+)',scenario_block,re.M)
check('scenario_count_18', len(scenarios)==18, str(scenarios))
check('all_scenarios_captured', all(s in capture for s in scenarios))
check('core3_capture', all(x in capture for x in ['runs','detail','settings']))
check('deterministic_status_bar', '--time "09:41"' in capture)
check('dark_appearance', 'appearance dark' in capture)
check('signing_report_generated', 'Observer-Signing-Report' in (root/'Scripts/package_artifacts.sh').read_text())
check('no_signing_secrets_in_workflow', not re.search(r'(p12|certificate|private[_ -]?key|provisioning[_ -]?profile|apple[_ -]?id|password|secret\.)', workflow_text, re.I))
check('self_sign_nested_appex_rule', 'PlugIns/*.appex' in readme)
check('no_network_runtime_in_sources', not any(token in ''.join(p.read_text(errors='ignore') for p in (root/'Sources').rglob('*.swift')) for token in ['URLSession','WebSocket','NWConnection']))
check('read_only_harness', 'No network, VPS, push, approval, retry, restore, deploy, or command execution' in (root/'Sources/SwiftUI/ObserverPreviewShell.swift').read_text())

fails=[c for c in checks if not c[1]]
for name,ok,detail in checks:
    print(('PASS' if ok else 'FAIL'), name, detail)
print(f'CHECKS={len(checks)} PASS={len(checks)-len(fails)} FAIL={len(fails)}')
if fails: sys.exit(1)
