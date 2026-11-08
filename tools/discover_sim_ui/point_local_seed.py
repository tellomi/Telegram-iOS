#!/usr/bin/env python3
"""Point the working-tree seed at the runner's loopback. Does not commit."""

import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
JSON_PATH = ROOT / "Tellomi" / "tellomi-server.json"
HEADER_PATH = ROOT / "submodules" / "MtProtoKit" / "Sources" / "TellomiServerConfigJSON.h"
REMOTE_SEED = '[\n        "api.tellomi.cn"\n      ]'
HEADER_REMOTE_SEED = '[\\n        \\"api.tellomi.cn\\"\\n      ]'


def main():
    committed = subprocess.check_output(
        ["git", "show", "HEAD:Tellomi/tellomi-server.json"],
        cwd=ROOT,
        text=True,
    )
    committed_cfg = json.loads(committed)
    for name in ("production", "testing"):
        if committed_cfg["seeds"][name]["1"] != ["api.tellomi.cn"]:
            sys.exit("committed seed for {} is not api.tellomi.cn; refusing to rewrite".format(name))
    cfg = json.loads(JSON_PATH.read_text())
    for name in ("production", "testing"):
        cfg["seeds"][name]["1"] = ["127.0.0.1"]
    text = json.dumps(cfg, indent=2, ensure_ascii=False) + "\n"
    if REMOTE_SEED in text:
        sys.exit("rewritten config still has the remote seed array")
    JSON_PATH.write_text(text)
    subprocess.check_call([sys.executable, str(ROOT / "Tellomi" / "generate_server_config.py")], cwd=ROOT)
    header = HEADER_PATH.read_text()
    if HEADER_REMOTE_SEED in header or REMOTE_SEED in header:
        sys.exit("generated header still has the remote seed array")
    if header.count('\\"127.0.0.1\\"') < 3:
        sys.exit("generated header does not carry the loopback seeds")
    print("working tree seed is 127.0.0.1; committed seed was not changed")


if __name__ == "__main__":
    main()
