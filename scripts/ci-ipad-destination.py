"""Select an available iPad on the newest installed iOS runtime for CI."""

import json
import re
import sys


def destination(devices):
    candidates = []
    for runtime, entries in devices.items():
        if not runtime.startswith("com.apple.CoreSimulator.SimRuntime.iOS-"):
            continue
        version = tuple(map(int, re.findall(r"\d+", runtime)))
        for device in entries:
            if device.get("isAvailable", False) and device["name"].startswith("iPad"):
                preferred = device["name"] == "iPad Pro 11-inch (M5)"
                candidates.append((version, preferred, device["udid"]))
    if not candidates:
        raise SystemExit("No available iPad simulator. Install an iOS Simulator runtime in Xcode.")
    return f"platform=iOS Simulator,id={max(candidates)[2]}"


if __name__ == "__main__":
    print(destination(json.load(sys.stdin)["devices"]))
