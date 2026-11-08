#!/usr/bin/env bash
# Stub curl and a stub command. Proves the pinned download and the external-fetch
# wrapper keep checksums, 403, and test assertions, and bound 5xx/timeouts.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
fetch="$root/.github/fetch_pinned.sh"
wrap="$root/.github/retry_external_fetch.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_eq() {
  if [[ "$1" != "$2" ]]; then
    fail "$3: got [$1] want [$2]"
  fi
}

hash_of() {
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  else
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  fi
}

good_hash="$(hash_of GOODBYTES)"
bin="$work/bin"
mkdir -p "$bin"
cat >"$bin/curl" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -w) shift 2 ;;
    --connect-timeout|--max-time) shift 2 ;;
    -sS|-s|-S|-L|-f|-fsSL) shift ;;
    *) shift ;;
  esac
done
cursor="$(cat "$STUB_CURL_CURSOR")"
line="$(sed -n "$((cursor + 1))p" "$STUB_CURL_PLAN")"
[[ -n "$line" ]] || { echo "curl ran out of steps" >&2; exit 99; }
status="${line%%$'\t'*}"
rest="${line#*$'\t'}"
http="${rest%%$'\t'*}"
body="${rest#*$'\t'}"
echo $((cursor + 1)) >"$STUB_CURL_CURSOR"
if [[ -n "$out" ]]; then
  printf '%s' "$body" >"$out"
fi
if [[ "$http" != "000" ]]; then
  printf '%s' "$http"
fi
if [[ "$status" -ne 0 ]]; then
  echo "curl: (${status}) The requested URL returned error: ${http}" >&2
fi
exit "$status"
EOS
chmod +x "$bin/curl"

plan="$work/curl.plan"
cursor="$work/curl.cursor"
run_fetch() {
  local name="$1" want_status="$2" want_calls="$3" sha="$4"
  shift 4
  : >"$plan"
  local step=0
  while [[ $# -ge 3 ]]; do
    printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$plan"
    shift 3
    step=$((step + 1))
  done
  echo 0 >"$cursor"
  local dest="$work/${name}.out" status
  rm -f "$dest"
  set +e
  PATH="$bin:$PATH" FETCH_ATTEMPTS=4 FETCH_DELAY_SECONDS=0 \
    STUB_CURL_PLAN="$plan" STUB_CURL_CURSOR="$cursor" \
    bash "$fetch" "https://github.com/example/pinned" "$dest" "$sha"
  status=$?
  set -e
  assert_eq "$status" "$want_status" "fetch ${name} status"
  assert_eq "$(cat "$cursor")" "$want_calls" "fetch ${name} calls"
  if [[ "$want_status" -eq 0 ]]; then
    assert_eq "$(cat "$dest")" "GOODBYTES" "fetch ${name} bytes"
  fi
}

run_fetch http503-then-ok 0 2 "$good_hash" \
  56 503 "" \
  0 200 GOODBYTES
run_fetch persistent-503 56 4 "$good_hash" \
  56 503 "" \
  56 503 "" \
  56 503 "" \
  56 503 ""
run_fetch timeout-then-ok 0 2 "$good_hash" \
  28 000 "" \
  0 200 GOODBYTES
run_fetch http403-once 22 1 "$good_hash" \
  0 403 "" \
  0 200 GOODBYTES
run_fetch checksum-rejected 2 1 "$good_hash" \
  0 200 BADBYTES \
  0 200 GOODBYTES

# External command wrapper.
cmd="$work/cmd.sh"
cat >"$cmd" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
cursor="$(cat "$STUB_CMD_CURSOR")"
line="$(sed -n "$((cursor + 1))p" "$STUB_CMD_PLAN")"
[[ -n "$line" ]] || { echo "command ran out of steps" >&2; exit 99; }
code="${line%%$'\t'*}"
file="${line#*$'\t'}"
cat "$file"
echo $((cursor + 1)) >"$STUB_CMD_CURSOR"
exit "$code"
EOS
chmod +x "$cmd"
cplan="$work/cmd.plan"
ccursor="$work/cmd.cursor"

write_log() {
  printf '%s\n' "$2" >"$1"
}

run_wrap() {
  local name="$1" want_status="$2" want_calls="$3"
  shift 3
  : >"$cplan"
  local n=0 path
  while [[ $# -ge 2 ]]; do
    path="$work/${name}-${n}.log"
    write_log "$path" "$2"
    printf '%s\t%s\n' "$1" "$path" >>"$cplan"
    shift 2
    n=$((n + 1))
  done
  echo 0 >"$ccursor"
  local status
  set +e
  EXTERNAL_FETCH_ATTEMPTS=3 EXTERNAL_FETCH_DELAY_SECONDS=0 \
    EXTERNAL_FETCH_LOG="$work/${name}-attempt.log" \
    STUB_CMD_PLAN="$cplan" STUB_CMD_CURSOR="$ccursor" \
    bash "$wrap" -- "$cmd"
  status=$?
  set -e
  assert_eq "$status" "$want_status" "wrap ${name} status"
  assert_eq "$(cat "$ccursor")" "$want_calls" "wrap ${name} calls"
}

timeout_log='WARNING: Download from https://github.com/bazel-contrib/bazel_features/releases/download/v1.51.0/bazel_features-v1.51.0.tar.gz failed: class java.io.IOException Read timed out'
assert_log='//submodules/Example:ExampleTests FAILED in 1.2s
error: -[ExampleTests testExample] : XCTAssertEqual failed: ("1") is not equal to ("2")'
forbidden_log='GET returned 403 Forbidden'
hash_log='Checksum was abcdef but wanted 123456'
missing_log="ERROR: no such target '//missing:MissingTests': target 'MissingTests' not declared"

run_wrap download-then-ok 0 2 \
  1 "$timeout_log" \
  0 "ok"
run_wrap persistent-timeout 1 3 \
  1 "$timeout_log" \
  1 "$timeout_log" \
  1 "$timeout_log"
run_wrap assertion-not-swallowed 3 1 \
  3 "$assert_log"$'\n'"$timeout_log" \
  0 "ok"
run_wrap http403-not-retried 22 1 \
  22 "$forbidden_log" \
  0 "ok"
run_wrap checksum-not-retried 2 1 \
  2 "$hash_log"$'\n'"$timeout_log" \
  0 "ok"
run_wrap missing-target-not-retried 7 1 \
  7 "$missing_log"$'\n'"GET returned 504" \
  0 "ok"

python3 - "$root/Tellomi/prepare_appstore_signing.py" <<'PY'
import importlib.util
import sys
path = sys.argv[1]
spec = importlib.util.spec_from_file_location("signing", path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
plan = mod.app_record_plan
assert plan(True) == "use"
assert plan(False) == "create_once"
assert plan(False, 409, False) == "use"
assert plan(False, 403, True) == "use"
assert plan(False, 403, False) == "fail"
assert plan(False, 401, False) == "fail"
print("app record plan: ok")
PY

echo "download_retry_test: ok"
