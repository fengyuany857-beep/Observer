#!/usr/bin/env python3
import json, subprocess, sys
preferred = ["iPhone 17 Pro", "iPhone 17", "iPhone 16 Pro", "iPhone 16"]
data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"]))
phones=[]
for runtime, devices in data.get("devices", {}).items():
    if "iOS" not in runtime:
        continue
    for d in devices:
        if d.get("isAvailable") and d.get("name", "").startswith("iPhone"):
            phones.append((runtime, d["name"], d["udid"]))
if not phones:
    raise SystemExit("No available iPhone simulator")
def version_key(runtime):
    tail=runtime.split("iOS-")[-1]
    return tuple(int(x) for x in tail.split("-") if x.isdigit())
phones.sort(key=lambda x: version_key(x[0]), reverse=True)
latest_runtime=phones[0][0]
latest=[p for p in phones if p[0]==latest_runtime]
for name in preferred:
    for runtime,n,udid in latest:
        if n==name:
            print(udid); sys.exit(0)
print(latest[0][2])
