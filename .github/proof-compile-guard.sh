#!/bin/bash
# Guards for the proof-only compile. This script does not invoke Bazel.
set -euo pipefail

usage() {
  echo "usage: proof-compile-guard.sh sha SHA | kind TEXT | no-ipa PATH | module PATH" >&2
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
    # `bazel query --output=label_kind` prints one "rule_kind label" line.
    [[ "$value" == swift_library\ * ]] || {
      echo "refusing: target is not a swift_library (${value})" >&2
      exit 1
    }
    case "$value" in
      *ios_application*|*ios_extension*|*apple_bundle*)
        echo "refusing: packaged Apple rule in target kind (${value})" >&2
        exit 1
        ;;
    esac
    ;;
  deps)
    if [[ -n "$value" ]]; then
      echo "refusing: Apple bundle in the dependency graph:" >&2
      echo "$value" >&2
      exit 1
    fi
    ;;
  no-ipa)
    if [[ -e "$value" ]]; then
      echo "refusing: installable package exists at ${value}" >&2
      exit 1
    fi
    ;;
  module)
    if [[ ! -e "$value" ]]; then
      echo "compile finished without a Swift module at ${value}" >&2
      exit 1
    fi
    case "$value" in
      *.ipa|*.app|*.dSYM)
        echo "refusing to treat a packaged product as the compile result: ${value}" >&2
        exit 1
        ;;
    esac
    ;;
  *)
    usage
    ;;
esac
