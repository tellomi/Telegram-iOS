#!/usr/bin/env bash
# Drive the already-built simulator app. Does not edit the server seed,
# upload an IPA, or send a code to a real phone or mailbox.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
artifact_dir="${ARTIFACT_DIR:-${root}/discover-sim-ui}"
mkdir -p "$artifact_dir"

{
  echo "head=$(git rev-parse HEAD)"
  echo "tree=$(git rev-parse 'HEAD^{tree}')"
  echo "product_base=9696899d867940a19a202ad678d808758376b04e"
  echo "release_ios=c75e2177c7e14848387f9b9e412c24021ca7e30a"
  echo "uploaded_build=73"
  git diff --stat 9696899d867940a19a202ad678d808758376b04e -- . \
    ':(exclude).github/workflows/discover-sim-ui.yml' \
    ':(exclude)tools/discover_sim_ui'
} | tee "${artifact_dir}/identity.txt"

if ! git diff --quiet -- Tellomi/tellomi-server.json submodules/MtProtoKit/Sources/TellomiServerConfigJSON.h; then
  echo "server seed files differ from the commit; refusing to run" >&2
  exit 2
fi

ipa="bazel-bin/Telegram/Telegram.ipa"
test -f "$ipa"
stage="$(mktemp -d)"
unzip -q -o "$ipa" -d "$stage"
app="$(echo "${stage}"/Payload/*.app)"
bundle="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${app}/Info.plist")"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${app}/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${app}/Info.plist")"
{
  echo "bundle=${bundle}"
  echo "marketing=${version}"
  echo "simulator_build=${build}"
  echo "note=simulator build is not TestFlight 73"
} | tee "${artifact_dir}/bundle.txt"
test "$bundle" = "app.tellomi.chat"

python3 - <<'PY'
import sys
print("refusing remote seed: api.tellomi.cn is not an isolated TestPhones service in this run", file=sys.stderr)
sys.exit(3)
PY

phone="${DISCOVER_TEST_PHONE:-}"
if [[ -z "$phone" ]]; then
  n=$(( ($(date +%s) % 8000) + 1000 ))
  phone="999661${n}"
fi
if [[ ! "$phone" =~ ^999661[0-9]{4}$ ]]; then
  echo "phone must be a 999661 test number" >&2
  exit 2
fi
national="${phone:3}"
code="11111"
echo "test_phone=${phone} code=${code} national=${national}" | tee "${artifact_dir}/account.txt"

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
chosen.sort()
print(chosen[-1][1])
PY
)"
echo "simulator=${udid}" | tee -a "${artifact_dir}/identity.txt"
xcrun simctl boot "$udid" || true
xcrun simctl bootstatus "$udid" -b
xcrun simctl spawn "$udid" defaults write NSGlobalDomain AppleLanguages -array zh-Hans
xcrun simctl spawn "$udid" defaults write NSGlobalDomain AppleLocale -string zh_CN
xcrun simctl shutdown "$udid" || true
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b
xcrun simctl install "$udid" "$app"

if ! java -version >/dev/null 2>&1; then
  if [[ -x /usr/libexec/java_home ]]; then
    export JAVA_HOME
    JAVA_HOME="$(/usr/libexec/java_home)"
    export PATH="${JAVA_HOME}/bin:${PATH}"
  fi
fi
if ! java -version >/dev/null 2>&1; then
  echo "JDK is missing on this runner; Maestro cannot start" | tee "${artifact_dir}/blocker.txt"
  xcrun simctl io "$udid" screenshot "${artifact_dir}/no-maestro.png" || true
  exit 4
fi
export PATH="${PATH}:${HOME}/.maestro/bin"
export MAESTRO_CLI_NO_ANALYTICS=1
export MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED=true
if [[ ! -x "${HOME}/.maestro/bin/maestro" ]]; then
  curl -fsSL "https://get.maestro.mobile.dev" | bash
fi
maestro --version | tee "${artifact_dir}/maestro-version.txt"

set +e
maestro test --udid "$udid" --debug-output "$artifact_dir" \
  -e PLATFORM=ios \
  -e "PHONE_NATIONAL=${national}" \
  -e "CODE=${code}" \
  -e "FIRST_NAME=E2EDiscover" \
  "${root}/tools/discover_sim_ui/flow.yaml"
status=$?
set -e
xcrun simctl io "$udid" screenshot "${artifact_dir}/final.png" || true
maestro hierarchy >"${artifact_dir}/hierarchy.txt" 2>"${artifact_dir}/hierarchy.err" || true
if [[ -d "${HOME}/.maestro/tests" ]]; then
  mkdir -p "${artifact_dir}/maestro-tests"
  cp -R "${HOME}/.maestro/tests/." "${artifact_dir}/maestro-tests/" || true
fi
find "$artifact_dir" -name '*.png' | tee "${artifact_dir}/screenshots.txt"
exit "$status"
