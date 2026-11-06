#!/usr/bin/env python3
"""Point Make.py's bazel path at a wrapper that adds one rules_apple feature."""
import os
import stat
import sys

def main():
    path, real = sys.argv[1], sys.argv[2]
    script = """#!/bin/bash
cmd=""
for arg in "$@"; do
  case "$arg" in
    build|test) cmd="$arg"; break ;;
  esac
done
if [[ "$cmd" == "build" || "$cmd" == "test" ]]; then
  exec "%s" "$@" --features=apple.skip_codesign_simulator_bundles
fi
exec "%s" "$@"
""" % (real, real)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(script)
    os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

if __name__ == "__main__":
    main()
