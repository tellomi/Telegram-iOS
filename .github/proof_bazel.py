#!/usr/bin/env python3
"""Explicit Bazel path for the proof compile.

Make.py selects a binary in two ways (build-system/Make/Make.py):

    if args.bazel is None:
        bazel_path = locate_bazel(...)
    else:
        bazel_path = args.bazel

locate_bazel hashes build-input/bazel-<version>-<arch> against versions.json
and deletes a mismatch before downloading the release binary. A wrapper placed
at that path, without --bazel, is removed and never executed. --bazel is the
supported path. --bazelArguments is parsed and never applied, so the feature
is added by this wrapper after Make.py has built its argv and before the real
binary runs.

The wrapper runs `aquery` with the same flags plus
--features=apple.skip_codesign_simulator_bundles, and refuses to exec the
build unless that graph's signing parameters are inside the boundary below.
rules_apple 485016eb codesigning_support.bzl:

- _should_sign_simulator_bundles returns False when the feature is set, before
  ios_unit_test's skip_simulator_signing_allowed=False would force signing.
- ProcessAndSign with no work is still mnemonic ProcessAndSign and runs
  `cp -p` (the empty action around line 679). A later log grep of the mnemonic
  cannot tell that apart from signing.
- Real signing is a generated process-and-sign script. The action argument is
  `should_sign`; /usr/bin/codesign is inside the script, not the mnemonic line.
- GenerateCodesigningDossier is unconditional for test bundles
  (apple_test_bundle_support.bzl). Its identity is written to dossier_arguments.
  Simulator builds use the ad-hoc pseudo-identity "-". A provisioning profile
  is not embedded when that identity is used. Device builds can carry a real
  identity and entitlements.

The gate asks Bazel 9.2 for the text graph with --include_param_files and
--include_file_write_contents. Command Line is pretty-printed across lines
(CommandFailureUtils, prettyPrintArgs). FileWrite contents are one base64
field, FileWriteContents, not a command. An empty graph, a truncated field,
or a referenced args file whose contents are absent is not a safe graph.
GenerateCodesigningDossier with the ad-hoc identity "-" and no profile is
dossier generation. ProcessAndSign signs only when its arguments include
should_sign or its script does; the empty action is the multi-line cp -p.
"""
import argparse
import base64
import binascii
import os
import re
import stat
import subprocess
import sys

FEATURE = "--features=apple.skip_codesign_simulator_bundles"
GATED_COMMANDS = ("build", "test")
# Execution-only. It is not part of the analyzed graph and aquery rejects it.
AQUERY_STRIP = ("--subcommands",)

# A field is indented two spaces. Continuation lines are indented further,
# which is how Bazel 9.2 prints every argument after the first.
_FIELD_RE = re.compile(r"^  (?! )([^:]+): ?(.*)$")
_COMMAND_TRAILER_RE = re.compile(r"\n# (?:Configuration|Execution platform|Runner):")
_FILE_CONTENTS_RE = re.compile(r"^\[([A-Za-z0-9+/=]*)\]$")

AQUERY_OPTIONS = (
    "--output=text",
    "--include_commandline",
    "--include_param_files",
    "--include_file_write_contents",
)


class Action(object):
    def __init__(self):
        self.mnemonic = ""
        self.outputs = []
        self.command = ""
        self.arguments = []
        self.command_truncated = False
        self.params = {}
        self.param_truncated = False
        self.file_contents = None
        self.file_contents_error = None
        self.substitutions = {}
        self.substitutions_truncated = False


class Decision(object):
    def __init__(self, allow, reasons):
        self.allow = allow
        self.reasons = reasons


def command_index(argv):
    """Index of build/test in a Make.py bazel argv, or None."""
    for index, arg in enumerate(argv):
        if index == 0:
            continue
        if arg in GATED_COMMANDS:
            return index
    return None


def target_and_flags(argv, command_at):
    target = None
    flags = []
    for arg in argv[command_at + 1:]:
        if target is None and not arg.startswith("-"):
            target = arg
        else:
            flags.append(arg)
    if target is None:
        raise ValueError("bazel build argv has no target")
    return target, flags


def _ios_cpus(flags):
    cpus = []
    for flag in flags:
        if flag.startswith("--ios_multi_cpus="):
            cpus.extend(part for part in flag.split("=", 1)[1].split(",") if part)
    return cpus


def aquery_argv(real, make_argv):
    command_at = command_index(make_argv)
    if command_at is None:
        raise ValueError("not a build or test argv")
    startup = list(make_argv[1:command_at])
    target, flags = target_and_flags(make_argv, command_at)
    flags = [flag for flag in flags if flag not in AQUERY_STRIP]
    if FEATURE not in flags:
        flags.append(FEATURE)
    query = (
        'mnemonic("SignBinary", {t}) union '
        'mnemonic("ProcessAndSign", {t}) union '
        'mnemonic("GenerateCodesigningDossier", {t}) union '
        'mnemonic("TemplateExpand", {t}) union '
        'mnemonic("FileWrite", {t})'
    ).format(t=target)
    return [real] + startup + ["aquery"] + list(AQUERY_OPTIONS) + flags + [query]


def exec_argv(real, make_argv):
    rest = list(make_argv[1:])
    if FEATURE not in rest:
        rest.append(FEATURE)
    return [real] + rest


def unescape_shell_arg(arg):
    """Undo Bazel ShellEscaper strong quotes. Unclosed quotes stay unchanged."""
    if not arg.startswith("'"):
        if " " in arg or "\t" in arg:
            return None
        return arg
    out = []
    index = 1
    while index < len(arg):
        if arg.startswith("'\\''", index):
            out.append("'")
            index += 4
            continue
        if arg[index] == "'":
            if index != len(arg) - 1:
                return None
            return "".join(out)
        out.append(arg[index])
        index += 1
    return None


def split_pretty_command(value):
    """Split a Bazel 9.2 pretty-printed Command Line into argv.

    prettyPrintArgs puts the executable on the first line and every later
    argument after ' \\\\\\n    '. A single line that still contains spaces is
    not that format. Returns (arguments, truncated).
    """
    body = _COMMAND_TRAILER_RE.split(value, maxsplit=1)[0].strip()
    if not body.startswith("(exec ") or not body.endswith(")"):
        return [], True
    inner = body[len("(exec "):-1]
    if inner.endswith("\\"):
        return [], True
    pieces = inner.split(" \\\n    ")
    arguments = []
    for piece in pieces:
        decoded = unescape_shell_arg(piece)
        if decoded is None:
            return [], True
        arguments.append(decoded)
    return arguments, False


def decode_file_write_contents(value):
    """Decode FileWriteContents: [base64]. Official fixture is hello world."""
    match = _FILE_CONTENTS_RE.match(value.strip())
    if match is None:
        return None, "truncated"
    try:
        raw = base64.b64decode(match.group(1), validate=True)
    except binascii.Error:
        return None, "not base64"
    try:
        return raw.decode("utf-8"), None
    except UnicodeDecodeError:
        return None, "not utf-8"


def parse_param_lines(lines):
    """Recover arguments from Params File Content continuation lines.

    Bazel joins ParameterFileWriteAction arguments with ' \\\\\\n    '.
    Every line but the last therefore ends in ' \\\\', and a trailing
    backslash means the file was cut off.
    """
    raw = []
    for line in lines:
        if not line.startswith("    "):
            return None
        raw.append(line[4:])
    if not raw:
        return []
    if raw[-1].endswith("\\"):
        return None
    if any(not part.endswith(" \\") for part in raw[:-1]):
        return None
    return "\n".join(raw).split(" \\\n")


def _bracket_list(value):
    value = value.strip()
    if not (value.startswith("[") and value.endswith("]")):
        return None
    inner = value[1:-1].strip()
    if not inner:
        return []
    return [part.strip() for part in inner.split(",")]


def _parse_substitutions(lines):
    substitutions = {}
    pending_key = None
    pending = []
    for line in lines:
        if line == "  ]":
            if pending_key is not None:
                return None
            return substitutions
        if pending_key is None:
            match = re.match(r"^    \{([^:{}]+): (.*)$", line)
            if match is None:
                return None
            pending_key = match.group(1)
            pending = [match.group(2)]
            if pending[-1].endswith("}"):
                substitutions[pending_key] = pending[-1][:-1]
                pending_key = None
                pending = []
            continue
        if line.endswith("}"):
            pending.append(line[:-1])
            substitutions[pending_key] = "\n".join(pending)
            pending_key = None
            pending = []
        else:
            pending.append(line)
    return None


def parse_actions(text):
    """Parse Bazel 9.2 --output=text. Returns (actions, errors)."""
    if text is None:
        text = ""
    errors = []
    if text.strip() == "":
        return [], ["empty action graph"]
    if not text.endswith("\n"):
        errors.append("truncated aquery output")
    lines = text.splitlines()
    actions = []
    index = 0
    while index < len(lines):
        line = lines[index]
        if not line.startswith("action "):
            if line.strip():
                errors.append("unexpected aquery line")
                return actions, errors
            index += 1
            continue
        action = Action()
        index += 1
        while index < len(lines) and lines[index] != "" and not lines[index].startswith("action "):
            match = _FIELD_RE.match(lines[index])
            if match is None:
                errors.append("truncated action field")
                return actions, errors
            key = match.group(1)
            rest = match.group(2)
            index += 1
            if key == "Mnemonic":
                action.mnemonic = rest.strip()
            elif key == "Outputs":
                outputs = _bracket_list(rest)
                if outputs is None:
                    errors.append("truncated Outputs list")
                    return actions, errors
                action.outputs = outputs
            elif key == "Command Line":
                chunks = [rest]
                while index < len(lines):
                    nxt = lines[index]
                    if nxt == "" or nxt.startswith("action ") or _FIELD_RE.match(nxt):
                        break
                    chunks.append(nxt)
                    index += 1
                action.command = "\n".join(chunks)
                action.arguments, action.command_truncated = split_pretty_command(action.command)
            elif key.startswith("Params File Content ("):
                path = key[len("Params File Content ("):-1]
                body = []
                while index < len(lines) and lines[index].startswith("    "):
                    body.append(lines[index])
                    index += 1
                parsed = parse_param_lines(body)
                if parsed is None:
                    action.param_truncated = True
                else:
                    action.params[path] = parsed
            elif key == "FileWriteContents":
                decoded, error = decode_file_write_contents(rest)
                action.file_contents = decoded
                action.file_contents_error = error
            elif key == "Substitutions":
                body = []
                while index < len(lines) and lines[index] != "":
                    body.append(lines[index])
                    index += 1
                    if body[-1] == "  ]":
                        break
                parsed = _parse_substitutions(body)
                if parsed is None:
                    action.substitutions_truncated = True
                else:
                    action.substitutions = parsed
            # Other fields (Target, Configuration, Inputs, IsExecutable, ...)
            # are kept only as evidence the block continued. Their values are
            # not a signing boundary by themselves.
        actions.append(action)
        if index < len(lines) and lines[index] == "":
            index += 1
    return actions, errors


def _signing_marker(text):
    if text is None:
        return None
    if "/usr/bin/codesign" in text or "codesign_allocate" in text:
        return "codesign tool"
    if ".mobileprovision" in text or "--provisioning_profile" in text:
        return "provisioning profile"
    if "--entitlements_file" in text or "--infer_identity" in text:
        return "entitlement or inferred identity"
    if re.search(r"(^|\s)should_sign($|\s)", text):
        return "should_sign"
    return None


def dossier_lines_safe(lines):
    """True when these are an ad-hoc dossier and not a bundle signature."""
    if not lines:
        return "dossier arguments are empty"
    marker = _signing_marker("\n".join(lines))
    if marker:
        return "dossier arguments contain %s" % marker
    identities = []
    index = 0
    while index < len(lines):
        if lines[index] == "--codesign_identity":
            if index + 1 >= len(lines):
                return "dossier identity is truncated"
            identities.append(lines[index + 1])
            index += 2
            continue
        index += 1
    if identities != ["-"]:
        return "dossier identity is %s, not the ad-hoc '-'" % identities
    if "--output" not in lines or "--zip" not in lines:
        return "dossier arguments have no --output/--zip"
    return None


def _empty_copy(arguments):
    if len(arguments) != 3:
        return False
    if arguments[1] != "-c":
        return False
    if not (arguments[0] == "bash" or arguments[0].endswith("/bash")):
        return False
    script = arguments[2]
    return re.match(r"^cp -p (?:'[^']+'|\S+) (?:'[^']+'|\S+)$", script) is not None


def _referenced_paths(arguments):
    paths = []
    for argument in arguments:
        if argument.startswith("@"):
            paths.append(argument[1:])
        elif argument.endswith(".sh"):
            paths.append(argument)
    return paths


def _contents_for(path, action, actions):
    """Visible text of a referenced param or script.

    Returns (text, conflict). text is None when nothing in the graph shows
    the contents. conflict is true when two visible sources disagree.
    """
    found = []
    if path in action.params:
        found.append("\n".join(action.params[path]))
    for other in actions:
        if path not in other.outputs:
            continue
        if other.file_contents is not None:
            found.append(other.file_contents)
        signing = other.substitutions.get("%signing_command_lines%")
        if signing is not None:
            found.append(signing)
    if not found:
        return None, False
    normalized = [item.rstrip("\n") for item in found]
    if any(item != normalized[0] for item in normalized[1:]):
        return None, True
    return normalized[0], False


def evaluate_graph(text, flags):
    """Return whether this configured graph may be executed."""
    reasons = []
    if FEATURE not in flags:
        reasons.append("skip_codesign feature is not on the aquery command")
    for option in ("--include_file_write_contents", "--include_param_files"):
        if option not in flags:
            reasons.append("aquery was not asked for %s" % option)
    cpus = _ios_cpus(flags)
    if "sim_arm64" not in cpus:
        reasons.append("configuration has no sim_arm64 cpu")
    if any(not cpu.startswith("sim_") for cpu in cpus):
        reasons.append("device ios cpu in %s" % ",".join(cpus))

    actions, parse_errors = parse_actions(text)
    reasons.extend(parse_errors)
    if not actions and "empty action graph" not in reasons:
        reasons.append("empty action graph is not evidence that signing is absent")

    for action in actions:
        if not action.mnemonic:
            reasons.append("action has no mnemonic")
            continue
        if action.command_truncated:
            reasons.append("%s command line is truncated or not Bazel 9.2 pretty-print" % (
                action.mnemonic or "action"))
        if action.param_truncated:
            reasons.append("param file contents are truncated")
        if action.substitutions_truncated:
            reasons.append("template substitutions are truncated")
        if action.file_contents_error:
            reasons.append("FileWriteContents is %s" % action.file_contents_error)
        if action.mnemonic == "FileWrite" and action.file_contents is None and not action.file_contents_error:
            reasons.append("FileWrite has no FileWriteContents; actions.write is invisible without it")
        marker = _signing_marker(action.command)
        if marker and action.mnemonic not in ("GenerateCodesigningDossier",):
            reasons.append("%s on %s" % (marker, action.mnemonic or "action"))
        if action.file_contents is not None and action.mnemonic == "FileWrite":
            # Unrelated writes are audited. A signing marker in them is not safe.
            # The dossier file itself is judged by dossier_lines_safe below.
            pass
        if action.mnemonic == "SignBinary":
            reasons.append("SignBinary is a signing action")
        elif action.mnemonic == "ProcessAndSign":
            if action.command_truncated or not action.arguments:
                reasons.append("ProcessAndSign arguments are not visible")
            elif "should_sign" in action.arguments:
                reasons.append(
                    "ProcessAndSign should_sign; codesign runs inside the generated script"
                )
            elif _empty_copy(action.arguments):
                pass
            else:
                script_paths = [arg for arg in action.arguments if arg.endswith(".sh")]
                if not script_paths:
                    reasons.append("ProcessAndSign is not the empty cp -p action")
                else:
                    for script_path in script_paths:
                        body, conflict = _contents_for(script_path, action, actions)
                        if conflict:
                            reasons.append("ProcessAndSign script sources disagree")
                        elif body is None:
                            reasons.append("ProcessAndSign script contents are not in the graph")
                        elif body.strip():
                            reasons.append("ProcessAndSign script contains signing commands")
        elif action.mnemonic == "GenerateCodesigningDossier":
            if action.command_truncated or not action.arguments:
                reasons.append("GenerateCodesigningDossier arguments are not visible")
            elif len(action.arguments) < 3 or action.arguments[1] != "create":
                reasons.append("GenerateCodesigningDossier is not the create action")
            else:
                referenced = [arg[1:] for arg in action.arguments if arg.startswith("@")]
                if len(referenced) != 1:
                    reasons.append("GenerateCodesigningDossier args file is not a single @file")
                else:
                    body, conflict = _contents_for(referenced[0], action, actions)
                    if conflict:
                        reasons.append("dossier argument sources disagree")
                    elif body is None:
                        reasons.append(
                            "dossier_arguments contents are not in the graph; "
                            "actions.write is invisible unless FileWriteContents or a param file is present"
                        )
                    else:
                        problem = dossier_lines_safe(body.splitlines())
                        if problem:
                            reasons.append(problem)
        elif action.mnemonic == "TemplateExpand":
            for key, value in action.substitutions.items():
                found = _signing_marker(key + " " + value)
                if found and not (key == "%signing_command_lines%" and value.strip() == ""):
                    reasons.append("template substitution has %s" % found)
        elif action.mnemonic == "FileWrite":
            if action.file_contents is not None:
                found = _signing_marker(action.file_contents)
                referenced = False
                for other in actions:
                    if any(arg[1:] in action.outputs for arg in other.arguments if arg.startswith("@")):
                        referenced = True
                if found and not referenced:
                    reasons.append("FileWrite contains %s" % found)
        elif action.mnemonic:
            reasons.append("unknown action %s; refusing without a signing classification" % action.mnemonic)

    if not any(action.mnemonic == "ProcessAndSign" for action in actions):
        reasons.append("ProcessAndSign is absent, so the bundle action was not audited")
    if not any(action.mnemonic == "GenerateCodesigningDossier" for action in actions):
        reasons.append("GenerateCodesigningDossier is absent, so its arguments were not audited")

    unique = []
    for reason in reasons:
        if reason not in unique:
            unique.append(reason)
    return Decision(not unique, unique)


def wrapper_main(argv, real, run=None, execv=None):
    """Gate build/test, then exec the real binary. Other commands are forwarded."""
    run = run or subprocess.run
    execv = execv or os.execv
    if command_index(argv) is None:
        forwarded = [real] + list(argv[1:])
        execv(forwarded[0], forwarded)
        return 0

    query = aquery_argv(real, argv)
    completed = run(query, check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    output = (completed.stdout or "") + "\n" + (completed.stderr or "")
    if completed.returncode != 0:
        sys.stderr.write(output)
        sys.stderr.write("aquery failed; build was not executed\n")
        return completed.returncode or 1

    flags = []
    seen_aquery = False
    for arg in query[1:]:
        if not seen_aquery:
            if arg == "aquery":
                seen_aquery = True
            continue
        flags.append(arg)
    flags = flags[:-1]
    decision = evaluate_graph(completed.stdout or "", flags)
    if not decision.allow:
        sys.stderr.write("refusing to execute bazel; signing boundary failed before any build action\n")
        for reason in decision.reasons:
            sys.stderr.write("signing-boundary: %s\n" % reason)
        return 1

    executed = exec_argv(real, argv)
    execv(executed[0], executed)
    return 0


def install(wrapper_path, real_path, lib_dir):
    """Write a wrapper outside build-input. Its shebang is an absolute interpreter."""
    script = """#!%s
import sys
sys.path.insert(0, %r)
import proof_bazel
sys.exit(proof_bazel.wrapper_main(sys.argv, %r))
""" % (sys.executable, lib_dir, real_path)
    directory = os.path.dirname(wrapper_path)
    if directory:
        os.makedirs(directory, exist_ok=True)
    with open(wrapper_path, "w", encoding="utf-8") as handle:
        handle.write(script)
    os.chmod(wrapper_path, os.stat(wrapper_path).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return wrapper_path


def main(argv):
    parser = argparse.ArgumentParser(prog="proof_bazel")
    sub = parser.add_subparsers(dest="command")
    install_parser = sub.add_parser("install")
    install_parser.add_argument("--wrapper", required=True)
    install_parser.add_argument("--real", required=True)
    install_parser.add_argument("--lib", required=True)
    args = parser.parse_args(argv)
    if args.command != "install":
        parser.error("install is required")
    install(args.wrapper, os.path.abspath(args.real), os.path.abspath(args.lib))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
