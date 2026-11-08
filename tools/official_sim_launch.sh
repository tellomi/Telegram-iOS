#!/usr/bin/env bash
# Install the unsigned simulator build and record the first screen.
# Does not type a phone number, a code, or a message.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
echo "launch cwd=$(pwd)"
out="${root}/official-sim-launch"
mkdir -p "$out"
ipa="bazel-bin/Telegram/Telegram.ipa"
if [[ ! -f "$ipa" ]]; then
  echo "missing $ipa" >&2
  ls -la bazel-bin/Telegram 2>/dev/null || true
  exit 1
fi
stage="$(mktemp -d)"
unzip -q -o "$ipa" -d "$stage"
app="$(echo "${stage}"/Payload/*.app)"
plist="${app}/Info.plist"
bundle="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$plist")"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
{
  echo "bundle=${bundle}"
  echo "display_name=${name}"
  echo "marketing=${version}"
  echo "simulator_build=${build}"
  echo "note=unsigned simulator build, not an App Store upload"
  echo "head=$(git rev-parse HEAD)"
  echo "candidate_sha=${CANDIDATE_SHA:-unset}"
} | tee "${out}/identity.txt"
test "$bundle" = "app.tellomi.chat"
test "$name" = "Tellomi"
test "$version" = "14.0.5"
plutil -extract CFBundleIcons xml1 -o - "$plist" > "${out}/icons.plist" || true
find "$app" -name 'TellomiHomeIpad*.png' -o -name '*Alternate*' -o -name '*.alticon' | tee "${out}/brand-files.txt"

udid="$(python3 - <<'PY'
import json, subprocess, sys
raw = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"], text=True)
chosen = []
for runtime, devices in json.loads(raw).get("devices", {}).items():
    if "iOS" not in runtime:
        continue
    for device in devices:
        name = device.get("name") or ""
        if device.get("isAvailable", True) and name.startswith("iPhone") and "SE" not in name:
            chosen.append((name, device["udid"]))
if not chosen:
    sys.exit("no available iPhone simulator")
regular = [item for item in chosen if "Duo" not in item[0]]
pool = regular or chosen
pool.sort()
print(pool[-1][0] + "\t" + pool[-1][1])
PY
)"
device_name="${udid%%$'\t'*}"
udid="${udid#*$'\t'}"
echo "simulator=${device_name} ${udid}" | tee -a "${out}/identity.txt"

xcrun simctl boot "$udid" || true
xcrun simctl bootstatus "$udid" -b
xcrun simctl ui "$udid" appearance light
xcrun simctl install "$udid" "$app"
xcrun simctl launch "$udid" "$bundle"
sleep 12
display=""
shot() {
  local dest="$1"
  local errfile="${out}/screenshot.err"
  if [[ -n "$display" ]]; then
    xcrun simctl io "$udid" screenshot --display="$display" "$dest"
    return
  fi
  if xcrun simctl io "$udid" screenshot "$dest" 2>"$errfile"; then
    return
  fi
  cat "$errfile"
  display="$(python3 - "$errfile" << 'PY'
import re, sys
text = open(sys.argv[1], errors="replace").read()
primary = ""
any_id = ""
for line in text.splitlines():
    match = re.search(r"--display=(\d+)", line)
    if not match:
        continue
    any_id = match.group(1)
    if "(primary)" in line and "primary-" not in line:
        primary = any_id
print(primary or any_id)
PY
)"
  if [[ -z "$display" ]]; then
    echo "screenshot failed and no display id was offered" >&2
    return 22
  fi
  echo "screenshot_display=${display}" | tee -a "${out}/identity.txt"
  xcrun simctl io "$udid" screenshot --display="$display" "$dest"
}
shot "${out}/portrait-light.png"
xcrun simctl ui "$udid" appearance dark
sleep 2
shot "${out}/portrait-dark.png"
if xcrun simctl ui "$udid" orientation landscapeLeft; then
  sleep 2
  shot "${out}/landscape-dark.png"
  xcrun simctl ui "$udid" orientation portrait || true
else
  echo "orientation command unavailable" | tee "${out}/rotation.txt"
fi
xcrun simctl terminate "$udid" "$bundle" || true
sleep 1
xcrun simctl launch "$udid" "$bundle"
sleep 8
shot "${out}/cold-start.png"
echo "no phone number was entered" | tee -a "${out}/identity.txt"
python3 - "$out" << 'PY'
import sys
from pathlib import Path
out = Path(sys.argv[1])
magic = b"\x89PNG\r\n\x1a\n"
for name in ("portrait-light.png", "portrait-dark.png", "cold-start.png"):
    data = (out / name).read_bytes()
    if not data.startswith(magic):
        raise SystemExit(name + " is not a png")
    print(name, len(data))
PY
