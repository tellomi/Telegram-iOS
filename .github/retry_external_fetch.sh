#!/usr/bin/env bash
# Re-run a command only when its failure is an external archive download:
# a read/connect timeout or HTTP 502/503/504. Compiler errors, test assertions,
# checksum mismatches, 401/403 and a missing Bazel target are not retried.
set -euo pipefail

hard_stop() {
  local log="$1"
  grep -E -q 'FAILED in |XCTAssert|: error:|Checksum was|does not match|GET returned 401|GET returned 403|The requested URL returned error: 40[13]|no such target ' "$log"
}

retryable_download() {
  local log="$1"
  grep -E -q 'Read timed out|Connect timed out|GET returned 50[234]|The requested URL returned error: 50[234]|curl: \(56\)|curl: \(28\)|curl: \(52\)|curl: \(18\)' "$log"
}

run_with_retry() {
  local attempt=1 max="${EXTERNAL_FETCH_ATTEMPTS:-3}" status=0 log delay
  log="${EXTERNAL_FETCH_LOG:-${RUNNER_TEMP:-/tmp}/external-fetch.log}"
  mkdir -p "$(dirname "$log")"
  while [[ "$attempt" -le "$max" ]]; do
    set +e
    "$@" >"$log" 2>&1
    status=$?
    set -e
    cat "$log"
    if [[ "$status" -eq 0 ]]; then
      return 0
    fi
    if [[ "$attempt" -lt "$max" ]] && retryable_download "$log" && ! hard_stop "$log"; then
      if [[ -n "${EXTERNAL_FETCH_DELAY_SECONDS+x}" ]]; then
        delay="$EXTERNAL_FETCH_DELAY_SECONDS"
      else
        delay=$((attempt * 15))
      fi
      echo "transient external download failure on attempt ${attempt}; retrying" >&2
      sleep "$delay"
      attempt=$((attempt + 1))
      continue
    fi
    return "$status"
  done
  return "$status"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  [[ "${1:-}" == "--" ]] || { echo "usage: retry_external_fetch.sh -- COMMAND..." >&2; exit 2; }
  shift
  [[ $# -ge 1 ]] || { echo "usage: retry_external_fetch.sh -- COMMAND..." >&2; exit 2; }
  set +e
  run_with_retry "$@"
  status=$?
  set -e
  exit "$status"
fi
