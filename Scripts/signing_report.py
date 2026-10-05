#!/usr/bin/env python3
import json, os, plistlib, hashlib, pathlib, subprocess
root=pathlib.Path('.')
app=root/'build/DerivedDataDevice/Build/Products/Release-iphoneos/Observer.app'
report={
  "pipeline_version":"Observer CI + Self-Sign Pipeline V1",
  "signing_state":"UNSIGNED_CI_OUTPUT",
  "main_bundle_id":"com.fnauy.observer",
  "extensions":["com.fnauy.observer.widgets"],
  "v1_capability_policy":{
    "app_groups":False,
    "push_notifications":False,
    "remote_live_activity_updates":False,
    "local_widget":True,
    "local_live_activity_scaffold":True
  },
  "self_sign_requirements":[
    "Re-sign the main Observer.app executable.",
    "Re-sign every nested PlugIns/*.appex executable with a compatible profile/certificate.",
    "Do not add entitlements that the selected provisioning profile does not authorize.",
    "After signing, verify launch plus Widget extension discovery before treating installation as accepted."
  ],
  "built_app_exists":app.is_dir(),
  "embedded_extensions":[]
}
if app.is_dir():
    for appex in sorted((app/'PlugIns').glob('*.appex')) if (app/'PlugIns').exists() else []:
        info=appex/'Info.plist'
        bundle=None
        if info.exists():
            with info.open('rb') as f:
                bundle=plistlib.load(f).get('CFBundleIdentifier')
        report['embedded_extensions'].append({"path":str(appex.relative_to(app)),"bundle_id":bundle})
ipa=root/'Artifacts/Observer-unsigned.ipa'
if ipa.exists():
    report['ipa_sha256']=hashlib.sha256(ipa.read_bytes()).hexdigest()
(pathlib.Path('Artifacts')/'Observer-Signing-Report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+"\n")
with (pathlib.Path('Artifacts')/'Observer-Signing-Report.txt').open('w') as f:
    f.write("Observer Signing Compatibility Report\n")
    f.write("===================================\n")
    f.write(json.dumps(report,indent=2,ensure_ascii=False))
    f.write("\n")
