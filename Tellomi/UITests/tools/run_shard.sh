#!/usr/bin/env bash
# Compile the UI test bundle against the prebuilt simulator app and run one shard.
# Usage: run_shard.sh <shard 1-5> <Telegram.app> <output dir>
set -euo pipefail

shard="${1:?shard}"
app="${2:?Telegram.app}"
out="${3:?output dir}"
root="$(cd "$(dirname "$0")/.." && pwd)"

case "${shard}" in
  1)
    tests=(
      TellomiLoggedOutUITests/testPhoneEntrySkipsTheWelcomeCarousel
      TellomiLoggedOutUITests/testCountryCodeDefaultsTo86AndContinueFollowsTheNumber
      TellomiLoggedOutUITests/testClosedLoginMethods
      TellomiLoggedOutUITests/testHomeScreenNameIsTellomi
    )
    ;;
  2)
    tests=(
      TellomiLoginFlowUITests/testAccountASubmitsTheFixedTestCode
      TellomiLoginFlowUITests/testAccountBReachesTheCodeScreen
    )
    ;;
  3)
    tests=(
      TellomiLoggedInShellUITests/testSettingsRows
      TellomiLoggedInShellUITests/testNavigationToggles
      TellomiLoggedInShellUITests/testLegalLinks
      TellomiLoggedInShellUITests/testPremiumEntriesStayHidden
    )
    ;;
  4)
    tests=(
      TellomiDiscoverUITests/testDiscoverTabAndProfileDoesNotHostMoments
      TellomiDiscoverUITests/testTellomiAndTelegramSchemesOpenTheLoggedOutApp
    )
    ;;
  5)
    tests=(
      TellomiComposerEntryUITests/testAIAndTranslateEntriesStayAtTheirDefaults
    )
    ;;
  *)
    echo "shard must be 1..5" >&2
    exit 2
    ;;
esac

mkdir -p "${out}/logs" "${out}/screenshots"
derived="${out}/DerivedData"
export TELLOMI_PREBUILT_APP="${app}"

udid="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone 17/ && /Shutdown|Booted/ { print $2; exit }')"
if [[ -z "${udid}" ]]; then
  echo "no iPhone 17 simulator" >&2
  xcrun simctl list devices available >&2 || true
  exit 1
fi
xcrun simctl boot "${udid}" || true
xcrun simctl bootstatus "${udid}" -b

xcodebuild build-for-testing \
  -project "${root}/TellomiClientUITests.xcodeproj" \
  -scheme TellomiClientUITests \
  -destination "platform=iOS Simulator,id=${udid}" \
  -derivedDataPath "${derived}" \
  CODE_SIGNING_ALLOWED=NO

xctestrun="$(find "${derived}" -name '*.xctestrun' -print | head -n 1)"
if [[ -z "${xctestrun}" ]]; then
  echo "xcodebuild did not write an xctestrun" >&2
  exit 1
fi
python3 "${root}/tools/inject_test_env.py" "${xctestrun}"

if [[ -n "${TELLOMI_TEST_PHONE_A:-}" ]]; then
  export TEST_RUNNER_TELLOMI_TEST_PHONE_A="${TELLOMI_TEST_PHONE_A}"
fi
if [[ -n "${TELLOMI_TEST_PHONE_B:-}" ]]; then
  export TEST_RUNNER_TELLOMI_TEST_PHONE_B="${TELLOMI_TEST_PHONE_B}"
fi
if [[ -n "${TELLOMI_TEST_CODE:-}" ]]; then
  export TEST_RUNNER_TELLOMI_TEST_CODE="${TELLOMI_TEST_CODE}"
fi
if [[ -n "${TELLOMI_TEST_PASSWORD:-}" ]]; then
  export TEST_RUNNER_TELLOMI_TEST_PASSWORD="${TELLOMI_TEST_PASSWORD}"
fi

bundle="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${app}/Info.plist")"
status=0
for test in "${tests[@]}"; do
  name="${test//\//__}"
  xcrun simctl uninstall "${udid}" "${bundle}" || true
  set +e
  xcodebuild test-without-building \
    -xctestrun "${xctestrun}" \
    -destination "platform=iOS Simulator,id=${udid}" \
    -only-testing:"TellomiClientUITests/${test}" \
    > "${out}/logs/${name}.log" 2>&1
  test_status=$?
  set -e
  xcrun simctl io "${udid}" screenshot "${out}/screenshots/${name}.png" || true
  if [[ "${test_status}" -ne 0 ]]; then
    status=1
    echo "failed ${test}" >&2
    tail -n 40 "${out}/logs/${name}.log" >&2 || true
  else
    echo "finished ${test}"
  fi
done

python3 "${root}/tools/collect_shard.py" \
  --sources "${root}/Sources" \
  --logs "${out}/logs" \
  --shard "${shard}" \
  --out "${out}/results.json"
exit "${status}"
