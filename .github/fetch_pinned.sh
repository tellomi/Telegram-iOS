#!/usr/bin/env bash
# Download one pinned official archive. The URL, version and sha256 are the caller's.
# Temporary 5xx and transport failures are retried. 401/403, other 4xx, and a
# checksum mismatch are returned as-is and the bad bytes are not kept.
set -euo pipefail

hash_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

retryable_fetch() {
  local status="$1" http="$2"
  case "$http" in
    408|429|500|502|503|504) return 0 ;;
    401|403|404) return 1 ;;
  esac
  case "$status" in
    6|7|18|28|35|52|56) return 0 ;;
  esac
  return 1
}

fetch_pinned() {
  local url="$1" dest="$2" want="$3"
  local attempt=1 max="${FETCH_ATTEMPTS:-4}" status=0 http="" tmp err delay
  tmp="$(mktemp)"
  err="$(mktemp)"
  while [[ "$attempt" -le "$max" ]]; do
    : >"$err"
    set +e
    http="$(curl -sS -L --connect-timeout 20 --max-time 180 -o "$tmp" -w "%{http_code}" "$url" 2>"$err")"
    status=$?
    set -e
    if [[ -s "$err" ]]; then
      cat "$err" >&2
    fi
    if [[ "$status" -eq 0 && "$http" == "200" ]]; then
      local got
      got="$(hash_file "$tmp")"
      if [[ "$got" != "$want" ]]; then
        echo "checksum mismatch for ${url}: got ${got} want ${want}" >&2
        rm -f "$tmp" "$err"
        return 2
      fi
      mv "$tmp" "$dest"
      rm -f "$err"
      return 0
    fi
    rm -f "$tmp"
    tmp="$(mktemp)"
    if [[ "$attempt" -lt "$max" ]] && retryable_fetch "$status" "$http"; then
      if [[ -n "${FETCH_DELAY_SECONDS+x}" ]]; then
        delay="$FETCH_DELAY_SECONDS"
      else
        delay=$((attempt * 5))
      fi
      echo "transient download failure (curl ${status}, HTTP ${http:-none}) attempt ${attempt}; retrying" >&2
      sleep "$delay"
      attempt=$((attempt + 1))
      continue
    fi
    rm -f "$tmp" "$err"
    if [[ "$status" -ne 0 ]]; then
      return "$status"
    fi
    return 22
  done
  rm -f "$tmp" "$err"
  return "${status:-1}"
}

usage() {
  echo "usage: fetch_pinned.sh URL DEST SHA256" >&2
  exit 2
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  [[ $# -eq 3 ]] || usage
  fetch_pinned "$1" "$2" "$3"
fi
