#!/usr/bin/env bash
# Drives bazel_registry_retry.sh with fixture logs and a stateful stub command.
# A passing run proves the attempt count and the preserved exit status, not only
# the wording of a grep.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
script="$root/.github/bazel_registry_retry.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

registry_log='ERROR: Error computing the main repository mapping: Error accessing registry https://bcr.bazel.build/: Failed to fetch registry file https://bcr.bazel.build/modules/zlib/1.2.12/MODULE.bazel: Connect timed out'
assertion_log='//submodules/Example:ExampleTests FAILED in 1.2s
error: -[ExampleTests testExample] : XCTAssertEqual failed: ("1") is not equal to ("2")
INFO: Build completed, 1 test FAILED, 4 total actions'
mixed_log="${registry_log}
${assertion_log}"
missing_mixed_log="${registry_log}
ERROR: Skipping '//missing:MissingTests': no such target '//missing:MissingTests'"
missing_and_failed_log='ERROR: no such package '\''missing'\'': BUILD file not found
//missing:MissingTests FAILED in 0.1s'
other_error_log='ERROR: /workspace/BUILD:12:1: Compiling foo.swift failed: (Exit 1)'
bare_timeout_log='Connect timed out
Failed to fetch registry file not from an ERROR line'

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local got="$1" want="$2" name="$3"
  if [[ "$got" != "$want" ]]; then
    fail "${name}: got [${got}] want [${want}]"
  fi
}

classify() {
  bash "$script" classify "$1"
}

write_log() {
  local path="$1"
  shift
  printf '%s\n' "$*" >"$path"
}

check_classify() {
  local name="$1" text="$2" want="$3" path
  path="$work/${name}.log"
  write_log "$path" "$text"
  assert_eq "$(classify "$path")" "$want" "classify ${name}"
}

check_classify pure-registry "$registry_log" retry
check_classify pure-assertion "$assertion_log" stop
check_classify registry-plus-assertion "$mixed_log" stop
check_classify missing-plus-registry "$missing_mixed_log" skip
check_classify missing-plus-assertion "$missing_and_failed_log" stop
check_classify other-build-error "$other_error_log" stop
check_classify bare-connect-timeout "$bare_timeout_log" stop
check_classify empty "" stop

# Stateful command. Each line of the plan is "exitcode<TAB>logfile".
# The stub prints the logfile and exits with the code, then advances.
plan_file="$work/plan"
cursor_file="$work/cursor"
echo 0 >"$cursor_file"

stub="$work/stub.sh"
cat >"$stub" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
cursor="$(cat "$STUB_CURSOR")"
line="$(sed -n "$((cursor + 1))p" "$STUB_PLAN")"
[[ -n "$line" ]] || { echo "stub ran out of steps" >&2; exit 99; }
code="${line%%$'\t'*}"
file="${line#*$'\t'}"
cat "$file"
echo $((cursor + 1)) >"$STUB_CURSOR"
exit "$code"
EOS
chmod +x "$stub"

run_plan() {
  local name="$1" want_status="$2" want_calls="$3"
  shift 3
  : >"$plan_file"
  local step=0 code text path
  while [[ $# -ge 2 ]]; do
    code="$1"
    text="$2"
    shift 2
    path="$work/${name}-${step}.log"
    write_log "$path" "$text"
    printf '%s\t%s\n' "$code" "$path" >>"$plan_file"
    step=$((step + 1))
  done
  echo 0 >"$cursor_file"
  local log="$work/${name}-attempt.log" status
  set +e
  BAZEL_RETRY_LOG="$log" \
    BAZEL_RETRY_DELAY_SECONDS=0 \
    BAZEL_RETRY_ATTEMPTS=3 \
    STUB_PLAN="$plan_file" \
    STUB_CURSOR="$cursor_file" \
    bash "$script" run -- "$stub"
  status=$?
  set -e
  assert_eq "$status" "$want_status" "run ${name} status"
  assert_eq "$(cat "$cursor_file")" "$want_calls" "run ${name} calls"
}

# Pure registry outage: every attempt fails the same way. Last status survives.
run_plan pure-network-exhausted 37 3 \
  37 "$registry_log" \
  37 "$registry_log" \
  37 "$registry_log"

# Pure assertion. The next step would succeed and must not run.
run_plan pure-assertion 3 1 \
  3 "$assertion_log" \
  0 "ok"

# Registry wording plus an assertion. Must not be retried into the later success.
run_plan mixed-assertion 4 1 \
  4 "$mixed_log" \
  0 "ok"

# Missing target mixed with the registry line. One attempt, original status.
run_plan mixed-missing 7 1 \
  7 "$missing_mixed_log" \
  0 "ok"

# Missing target that also carries a test failure stays a hard stop.
run_plan missing-and-failed 8 1 \
  8 "$missing_and_failed_log" \
  0 "ok"

# A compile error is not a registry fetch.
run_plan other-error 2 1 \
  2 "$other_error_log" \
  0 "ok"

# A timeout phrase without the registry ERROR line is not retried.
run_plan bare-timeout 6 1 \
  6 "$bare_timeout_log" \
  0 "ok"

# Two registry failures, then a real success. Only this shape may turn green.
run_plan network-then-success 0 3 \
  34 "$registry_log" \
  35 "$registry_log" \
  0 "ok"

# One registry failure, then success.
run_plan network-once-then-success 0 2 \
  36 "$registry_log" \
  0 "ok"

# An already successful command is not repeated.
run_plan already-success 0 1 \
  0 "ok"

# The workflow must call this script. The old broad grep retried any log that
# merely contained a registry phrase, including an assertion failure.
workflow="$root/.github/workflows/pr-tests.yml"
if grep -F -q "grep -E -q 'Connect timed out|Failed to fetch registry file|Error accessing registry'" "$workflow"; then
  fail "pr-tests.yml still retries on a broad registry grep"
fi
if ! grep -F -q 'bazel_registry_retry.sh' "$workflow"; then
  fail "pr-tests.yml does not call bazel_registry_retry.sh"
fi
if ! grep -F -q 'exit "$status"' "$workflow" && ! grep -F -q 'exit "$fail"' "$workflow"; then
  fail "pr-tests.yml does not preserve a failure status"
fi

echo "bazel_registry_retry_test: ok"
