#!/usr/bin/env bash
# Retry a Bazel command only when the failure is a pure central-registry fetch.
# Assertion failures, a missing target or package, and every other build error
# are returned immediately with the command's own exit status.
set -euo pipefail

log_path() {
  printf '%s\n' "${BAZEL_RETRY_LOG:-${RUNNER_TEMP:-/tmp}/bazel-attempt.log}"
}

has_assertion_failure() {
  local log="$1"
  grep -E -q 'FAILED in | test FAILED|XCTAssert|error: -\[|Test Case '\''.*'\'' failed|BUILD FAILED' "$log"
}

has_missing_target() {
  local log="$1"
  grep -E -q 'no such target|no such package' "$log"
}

# True when an ERROR line is not the registry-mapping fetch failure.
has_other_build_error() {
  local log="$1" line
  while IFS= read -r line; do
    case "$line" in
      *"Error accessing registry"*|*"Failed to fetch registry file"*|*"Error computing the main repository mapping"*)
        ;;
      *)
        return 0
        ;;
    esac
  done < <(grep -E 'ERROR:' "$log" || true)
  return 1
}

# The failure recorded for run 42416611063 is one ERROR line: Bazel could not
# download a registry MODULE.bazel and the transport timed out. A bare
# "Connect timed out", or the same words next to a test failure, is not this.
is_pure_registry_fetch_failure() {
  local log="$1"
  grep -E -q 'ERROR:.*(Error accessing registry|Error computing the main repository mapping).*Failed to fetch registry file' "$log" \
    && grep -E -q 'Connect timed out|DEADLINE_EXCEEDED|Could not resolve host|Connection reset by peer|Network is unreachable' "$log"
}

# Prints retry, skip, or stop. Classification itself exits 0.
classify_log() {
  local log="$1"
  if [[ ! -f "$log" ]]; then
    printf 'stop\n'
    return 0
  fi
  if has_assertion_failure "$log"; then
    printf 'stop\n'
    return 0
  fi
  if has_missing_target "$log"; then
    printf 'skip\n'
    return 0
  fi
  if has_other_build_error "$log"; then
    printf 'stop\n'
    return 0
  fi
  if is_pure_registry_fetch_failure "$log"; then
    printf 'retry\n'
    return 0
  fi
  printf 'stop\n'
}

delay_for_attempt() {
  local attempt="$1"
  if [[ -n "${BAZEL_RETRY_DELAY_SECONDS+x}" ]]; then
    printf '%s\n' "$BAZEL_RETRY_DELAY_SECONDS"
  else
    printf '%s\n' $((attempt * 20))
  fi
}

run_with_retry() {
  local attempt=1 max="${BAZEL_RETRY_ATTEMPTS:-3}" status=0 log disposition delay
  log="$(log_path)"
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
    disposition="$(classify_log "$log")"
    if [[ "$attempt" -lt "$max" && "$disposition" == "retry" ]]; then
      echo "transient Bazel registry failure on attempt ${attempt}; retrying" >&2
      delay="$(delay_for_attempt "$attempt")"
      sleep "$delay"
      attempt=$((attempt + 1))
      continue
    fi
    return "$status"
  done
  return "$status"
}

usage() {
  echo "usage: bazel_registry_retry.sh classify LOG | run -- COMMAND..." >&2
  exit 2
}

main() {
  local status
  case "${1:-}" in
    classify)
      [[ $# -eq 2 ]] || usage
      classify_log "$2"
      ;;
    run)
      shift
      [[ "${1:-}" == "--" ]] || usage
      shift
      [[ $# -ge 1 ]] || usage
      set +e
      run_with_retry "$@"
      status=$?
      set -e
      exit "$status"
      ;;
    *)
      usage
      ;;
  esac
}

main "$@"
