"""Prints the UDID of the newest available iPhone simulator."""
import json
import re
import sys

with open(sys.argv[1]) as f:
    devices = json.load(f)["devices"]

best = None
for runtime, entries in devices.items():
    if ".iOS-" not in runtime:
        continue
    version = tuple(int(n) for n in re.findall(r"\d+", runtime.split(".iOS-")[-1]))
    for d in entries:
        if not d.get("isAvailable", True) or not d.get("name", "").startswith("iPhone"):
            continue
        key = (version, d["name"])
        if best is None or key > best[0]:
            best = (key, d["udid"])

print(best[1] if best else "")
