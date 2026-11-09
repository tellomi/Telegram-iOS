"""Bundle-id suffixes shared by signing, profile copy, and the Bazel config.

Tellomi/extension-suffixes.json is the only list. Change a suffix there when
App Store Connect uses a different extension name.
"""

import json
import pathlib

PATH = pathlib.Path(__file__).resolve().parent / "extension-suffixes.json"


def load():
    return json.loads(PATH.read_text(encoding="utf-8"))


def targets():
    return load()["targets"]


def registered_targets():
    return [item for item in targets() if item.get("register")]


def profile_name_mapping():
    return {item["suffix"]: item["profile_file"] for item in targets()}


def bazel_suffix_lines():
    lines = []
    for item in targets():
        variable = item.get("bazel_variable")
        if not variable:
            continue
        lines.append('{} = "{}"\n'.format(variable, item["suffix"]))
    return "".join(lines)
