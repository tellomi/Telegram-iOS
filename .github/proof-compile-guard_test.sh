#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
guard="$root/proof-compile-guard.sh"
fail() { echo "guard test failed: $*" >&2; exit 1; }

"$guard" sha "69ceeac993e838e4625f4bbb2ad07c8552739cb1"
if "$guard" sha "cursor/discover-image-publish-7881" 2>/dev/null; then
  fail "branch name was accepted as a sha"
fi
if "$guard" sha "69ceeac9" 2>/dev/null; then
  fail "short sha was accepted"
fi
"$guard" kind "swift_library //submodules/TelegramUI/Components/Tellomi/FeedScreen:FeedScreen"
if "$guard" kind "ios_application //Telegram:Telegram" 2>/dev/null; then
  fail "ios_application was accepted"
fi
"$guard" deps ""
if "$guard" deps "ios_application //Telegram:Telegram" 2>/dev/null; then
  fail "bundle dependency was accepted"
fi
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
"$guard" no-ipa "$dir/Telegram.ipa"
touch "$dir/Telegram.ipa"
if "$guard" no-ipa "$dir/Telegram.ipa" 2>/dev/null; then
  fail "ipa was accepted"
fi
mkdir -p "$dir/out"
touch "$dir/out/TellomiFeedScreen.swiftmodule"
"$guard" module "$dir/out/TellomiFeedScreen.swiftmodule"
touch "$dir/out/Telegram.ipa"
if "$guard" module "$dir/out/Telegram.ipa" 2>/dev/null; then
  fail "ipa was accepted as a module"
fi
echo "proof-compile-guard tests passed"
