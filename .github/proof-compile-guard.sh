#!/bin/bash
# Guards for the proof-only iOS compile. This script does not invoke Bazel.
set -euo pipefail

usage() {
  echo "usage: proof-compile-guard.sh sha SHA | kind TEXT | bundles TEXT | no-app-ipa PATH | sdk-log FILE | sign-log FILE" >&2
  exit 2
}

[[ $# -ge 2 ]] || usage
mode="$1"
value="$2"

case "$mode" in
  sha)
    [[ "$value" =~ ^[0-9a-fA-F]{40}$ ]] || {
      echo "compile sha must be 40 hex characters, not a branch: ${value}" >&2
      exit 1
    }
    ;;
  kind)
    [[ "$value" == ios_unit_test\ * ]] || {
      echo "refusing: proof target must be an ios_unit_test so the iOS transition applies (${value})" >&2
      exit 1
    }
    ;;
  bundles)
    if grep -E 'ios_application|//Telegram:Telegram' <<<"$value" >/dev/null; then
      echo "refusing: app packaging target in the proof graph" >&2
      echo "$value" >&2
      exit 1
    fi
    ;;
  no-app-ipa)
    if [[ -e "$value" ]]; then
      echo "refusing: Telegram app package exists at ${value}" >&2
      exit 1
    fi
    ;;
  sdk-log)
    grep -E -i -q 'iphonesimulator|ios_sim_arm64|applebin_ios' "$value" || {
      echo "build log has no iOS simulator SDK marker; FeedScreen was not compiled for iOS" >&2
      exit 1
    }
    grep -q 'FeedScreen' "$value" || {
      echo "build log never names FeedScreen" >&2
      exit 1
    }
    ;;
  sign-log)
    if grep -E 'SignBinary|ProcessAndSign|/usr/bin/codesign|\.mobileprovision' "$value" >/dev/null; then
      echo "refusing: a codesign or provisioning action ran" >&2
      exit 1
    fi
    ;;
  *)
    usage
    ;;
esac
