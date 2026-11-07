#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
guard="$root/proof-compile-guard.sh"
fail() { echo "guard test failed: $*" >&2; exit 1; }

"$guard" sha "69ceeac993e838e4625f4bbb2ad07c8552739cb1"
if "$guard" sha "cursor/proof-compile-feed-7881" 2>/dev/null; then
  fail "branch name was accepted"
fi
"$guard" kind "ios_unit_test //Tests/TellomiFeedProof:TellomiFeedProofTests"
if "$guard" kind "swift_library //submodules/TelegramUI/Components/Tellomi/FeedScreen:FeedScreen" 2>/dev/null; then
  fail "host swift_library was accepted as the proof target"
fi
if "$guard" kind "ios_application //Telegram:Telegram" 2>/dev/null; then
  fail "app was accepted"
fi
"$guard" bundles ""
"$guard" bundles "ios_unit_test_runner //Tests/TellomiFeedProof:TellomiFeedProofRunner"
if "$guard" bundles "ios_application //Telegram:Telegram" 2>/dev/null; then
  fail "Telegram app dep was accepted"
fi
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
"$guard" no-app-ipa "$dir/Telegram.ipa"
touch "$dir/Telegram.ipa"
if "$guard" no-app-ipa "$dir/Telegram.ipa" 2>/dev/null; then
  fail "app ipa was accepted"
fi
printf 'swiftc -sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk FeedScreen.swift\n' >"$dir/build.log"
"$guard" sdk-log "$dir/build.log"
printf 'swiftc -sdk MacOSX.sdk Other.swift\n' >"$dir/host.log"
if "$guard" sdk-log "$dir/host.log" 2>/dev/null; then
  fail "host SDK log was accepted"
fi
echo "proof-compile-guard tests passed"
