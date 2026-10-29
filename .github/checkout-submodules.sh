#!/bin/bash
# Fetch each submodule at the commit this tree records.
#
# actions/checkout with fetch-depth: 1 runs `submodule update --depth 1`, which
# clones the default-branch tip. Most of these pins are not that tip, and two
# (rules_apple, webrtc) are not on the default branch at all. GitHub accepts a
# fetch of the commit sha, so each submodule is cloned at that sha.
set -euo pipefail

resolve_url() {
  python3 - "$1" "$2" << 'PY'
import posixpath
import sys
from urllib.parse import urlsplit, urlunsplit

base, url = sys.argv[1], sys.argv[2]
if "://" in url or url.startswith("git@"):
    print(url)
    raise SystemExit(0)
parts = urlsplit(base)
# Git resolves a relative submodule URL against the superproject URL as if the
# repository path were a directory: ../tgcalls.git next to org/repo.git is
# org/tgcalls.git.
path = posixpath.normpath(posixpath.join(parts.path, url))
print(urlunsplit((parts.scheme, parts.netloc, path, "", "")))
PY
}

checkout_children() {
  local root="$1"
  if [[ ! -f "$root/.gitmodules" ]]; then
    return 0
  fi
  local base
  base="$(git -C "$root" remote get-url origin 2>/dev/null || true)"
  local pids=()
  local key path name url sha
  while read -r key path; do
    [[ -z "${key:-}" ]] && continue
    name="${key#submodule.}"
    name="${name%.path}"
    url="$(git -C "$root" config -f .gitmodules --get "submodule.${name}.url")"
    url="$(resolve_url "$base" "$url")"
    sha="$(git -C "$root" rev-parse "HEAD:${path}")"
    checkout_one "$root" "$path" "$url" "$sha" &
    pids+=("$!")
  done < <(git -C "$root" config -f .gitmodules --get-regexp '^submodule\..*\.path$' || true)
  local fail=0
  local pid
  for pid in "${pids[@]}"; do
    wait "$pid" || fail=1
  done
  if [[ "$fail" != 0 ]]; then
    echo "submodule checkout failed" >&2
    exit 1
  fi
}

checkout_one() {
  local root="$1"
  local path="$2"
  local url="$3"
  local sha="$4"
  local dest="$root/$path"
  echo "submodule ${path} ${sha} ${url}"
  rm -rf "$dest"
  mkdir -p "$(dirname "$dest")"
  git init -q "$dest"
  git -C "$dest" remote add origin "$url"
  git -C "$dest" fetch --depth 1 origin "$sha"
  git -C "$dest" checkout --force --detach FETCH_HEAD
  checkout_children "$dest"
}

checkout_children "$(pwd)"
