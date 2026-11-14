#!/usr/bin/env python3
"""Copy TELLOMI_TEST_* from the environment into an xctestrun file.

The values are not printed. Xcode passes the test target's
EnvironmentVariables dictionary to the runner.
"""

from __future__ import annotations

import plistlib
import sys
from pathlib import Path

KEYS = (
    "TELLOMI_TEST_PHONE_A",
    "TELLOMI_TEST_PHONE_B",
    "TELLOMI_TEST_CODE",
    "TELLOMI_TEST_PASSWORD",
)


def inject(node: object, values: dict[str, str]) -> int:
    added = 0
    if isinstance(node, dict):
        if "TestBundlePath" in node:
            env = node.get("EnvironmentVariables")
            if not isinstance(env, dict):
                env = {}
                node["EnvironmentVariables"] = env
            env.update(values)
            added += 1
        for child in node.values():
            added += inject(child, values)
    elif isinstance(node, list):
        for child in node:
            added += inject(child, values)
    return added


def main() -> int:
    path = Path(sys.argv[1])
    import os

    values = {key: os.environ[key] for key in KEYS if os.environ.get(key)}
    with path.open("rb") as handle:
        payload = plistlib.load(handle)
    added = inject(payload, values)
    if added == 0:
        print("xctestrun has no test target to receive environment", file=sys.stderr)
        return 1
    with path.open("wb") as handle:
        plistlib.dump(payload, handle)
    print(f"injected {len(values)} test variables into {added} targets")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
