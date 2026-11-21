#!/usr/bin/env bash
# Prints the UDID of an available iPhone simulator on the newest installed iOS runtime.
# Skips "iPhone Duo", where the test runner hangs.
#
#   scripts/pick-simulator.sh            # e.g. in CI: -destination "id=$(scripts/pick-simulator.sh)"
set -euo pipefail

xcrun simctl list devices available --json | python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]

def version(runtime):
    return tuple(int(n) for n in re.findall(r"\d+", runtime.split("iOS-")[-1]))

for runtime in sorted((r for r in devices if ".iOS-" in r), key=version, reverse=True):
    phones = [d for d in devices[runtime] if d["name"].startswith("iPhone") and "Duo" not in d["name"]]
    # Prefer a standard Pro model, then any iPhone.
    phones.sort(key=lambda d: (not d["name"].endswith(" Pro"), d["name"]))
    if phones:
        print(phones[0]["udid"])
        sys.exit(0)
sys.exit("error: no available iPhone simulator")
'
