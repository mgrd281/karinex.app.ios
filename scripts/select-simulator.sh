#!/usr/bin/env bash
#
# Prints the UDID of an available iPhone simulator on the newest installed iOS runtime.
#
# Preference order within that runtime: the newest plain iPhone ("iPhone 17"), then the
# newest "e", "Plus" and "Air" models, then Pro, then Pro Max. The chosen device is
# described on stderr so CI logs show what ran; stdout carries only the UDID, so the script
# can be used as `-destination "id=$(scripts/select-simulator.sh)"`.
#
# Environment:
#   KX_SIMULATOR_NAME   pick this exact device name instead (e.g. "iPhone 16"), still on the
#                       newest runtime that offers it.
#
# Requires Xcode (xcrun simctl) and python3.

set -euo pipefail

if ! command -v xcrun >/dev/null 2>&1; then
    echo "error: xcrun not found. Install Xcode and run xcode-select." >&2
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "error: python3 not found." >&2
    exit 1
fi

devices_file="$(mktemp "${TMPDIR:-/tmp}/kx-simulators.XXXXXX")"
trap 'rm -f "$devices_file"' EXIT

xcrun simctl list --json devices available >"$devices_file"

KX_SIMULATOR_NAME="${KX_SIMULATOR_NAME:-}" python3 - "$devices_file" <<'PYTHON'
import json
import os
import re
import sys

requested = os.environ.get("KX_SIMULATOR_NAME", "").strip()
with open(sys.argv[1], encoding="utf-8") as handle:
    devices_by_runtime = json.load(handle).get("devices", {})


def runtime_version(identifier):
    """(major, minor, patch) of an iOS runtime identifier, or None for other platforms."""
    match = re.search(r"SimRuntime\.iOS-(\d+)(?:-(\d+))?(?:-(\d+))?$", identifier)
    if not match:
        return None
    return tuple(int(part or 0) for part in match.groups())


VARIANT_RANK = {"": 0, "e": 1, "plus": 2, "air": 3, "pro": 4, "pro max": 5}


def device_rank(name):
    """Sort key: plain models first, then newer generations, then the name."""
    match = re.match(r"^iPhone\s+(\d+)\s*(.*)$", name)
    if match:
        generation = int(match.group(1))
        variant = match.group(2).strip().lower()
    elif name.startswith("iPhone Air"):
        generation, variant = 0, "air"
    else:
        generation, variant = -1, name.lower()
    return (VARIANT_RANK.get(variant, len(VARIANT_RANK)), -generation, name)


candidates = []
for runtime, devices in devices_by_runtime.items():
    version = runtime_version(runtime)
    if version is None:
        continue
    for device in devices:
        name = device.get("name", "")
        if not name.startswith("iPhone") or not device.get("isAvailable", False):
            continue
        if requested and name != requested:
            continue
        candidates.append((version, device))

if not candidates:
    wanted = "iPhone simulator named '%s'" % requested if requested else "iPhone simulator"
    sys.stderr.write(
        "error: no available %s found. Install an iOS runtime in Xcode > Settings > Components.\n" % wanted
    )
    sys.exit(1)

newest = max(version for version, _ in candidates)
on_newest = [device for version, device in candidates if version == newest]
chosen = sorted(on_newest, key=lambda device: device_rank(device["name"]))[0]
parts = list(newest[:2]) if newest[2] == 0 else list(newest)
runtime_label = ".".join(str(part) for part in parts)
sys.stderr.write("Selected simulator: %s (iOS %s) %s\n" % (chosen["name"], runtime_label, chosen["udid"]))
print(chosen["udid"])
PYTHON
