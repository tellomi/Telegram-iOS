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

This gate reads those parameters from the action graph and returns before
exec. It does not grep a build log after the actions have run.
"""
import argparse
import os
import re
import stat
import subprocess
import sys

FEATURE = "--features=apple.skip_codesign_simulator_bundles"
GATED_COMMANDS = ("build", "test")
# Execution-only. It is not part of the analyzed graph and aquery rejects it.
AQUERY_STRIP = ("--subcommands",)

_ACTION_START = re.compile(r"(?m)^(?=action )")
_MNEMONIC = re.compile(r"(?m)^  Mnemonic: (\S+)\s*$")
_COMMAND = re.compile(r"(?m)^  Command Line: (.*)$")
_OUTPUTS = re.compile(r"(?m)^  Outputs: (.*)$")


class Action(object):
    def __init__(self, mnemonic, command, outputs):
        self.mnemonic = mnemonic
        self.command = command
        self.outputs = outputs


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
        'mnemonic("TemplateExpand", {t})'
    ).format(t=target)
    return [real] + startup + ["aquery", "--output=text"] + flags + [query]


def exec_argv(real, make_argv):
    rest = list(make_argv[1:])
    if FEATURE not in rest:
        rest.append(FEATURE)
    return [real] + rest


def parse_actions(text):
    actions = []
    for part in _ACTION_START.split(text or ""):
        if not part.startswith("action "):
            continue
        mnemonic = _MNEMONIC.search(part)
        command = _COMMAND.search(part)
        outputs = _OUTPUTS.search(part)
        actions.append(Action(
            mnemonic.group(1) if mnemonic else "",
            command.group(1).strip() if command else "",
            outputs.group(1).strip() if outputs else "",
        ))
    return actions


def _identity_tokens(blob):
    tokens = []
    for match in re.finditer(r"--codesign_identity(?:\s+|=|\\n)+([^\s\\'\"]+)", blob or ""):
        tokens.append(match.group(1))
    return tokens


def _dangerous_parameter(blob):
    if "/usr/bin/codesign" in blob or "codesign_allocate" in blob:
        return "codesign tool"
    if ".mobileprovision" in blob or "--provisioning_profile" in blob:
        return "provisioning profile"
    if "--entitlements_file" in blob:
        return "entitlements file"
    for token in _identity_tokens(blob):
        if token != "-":
            return "codesign identity %s" % token
    return None


def _dossier_shape_ok(action):
    command = action.command
    if "create" not in command.split() and " create " not in " %s " % command:
        return False
    if "dossier_arguments" not in command or "@" not in command:
        return False
    if "should_sign" in command.split():
        return False
    return True


def _filewrite_for_dossier(actions, dossier):
    marker = "dossier_arguments"
    for action in actions:
        if action.mnemonic == "FileWrite" and marker in action.outputs:
            return action
    referenced = "dossier_arguments" in dossier.command
    if not referenced:
        return None
    for action in actions:
        if action.mnemonic == "FileWrite" and marker in action.command:
            return action
    return None


def evaluate_graph(text, flags):
    """Return whether this configured graph may be executed."""
    reasons = []
    if FEATURE not in flags:
        reasons.append("skip_codesign feature is not on the aquery command")
    cpus = _ios_cpus(flags)
    if "sim_arm64" not in cpus:
        reasons.append("configuration has no sim_arm64 cpu; dossier identity would not be ad-hoc")
    if any(not cpu.startswith("sim_") for cpu in cpus):
        reasons.append("device ios cpu in %s" % ",".join(cpus))

    actions = parse_actions(text)
    if text and "Mnemonic:" in text and not actions:
        reasons.append("action graph text could not be parsed")

    for action in actions:
        blob = "\n".join([action.mnemonic, action.command, action.outputs])
        danger = _dangerous_parameter(blob)
        if danger:
            reasons.append("%s on %s" % (danger, action.mnemonic or "action"))
        if action.mnemonic == "SignBinary":
            reasons.append("SignBinary is a signing action")
        elif action.mnemonic == "ProcessAndSign":
            tokens = action.command.split()
            if not action.command:
                reasons.append(
                    "ProcessAndSign has a mnemonic and no command; empty work is cp -p, "
                    "signing is a generated script, refusing without the command"
                )
            elif "should_sign" in tokens or "should_sign" in action.command:
                reasons.append(
                    "ProcessAndSign should_sign; the codesign lines are inside the generated script"
                )
            elif "cp -p" not in action.command or ".sh" in action.command:
                reasons.append("ProcessAndSign is not the empty cp -p action")
        elif action.mnemonic == "GenerateCodesigningDossier":
            if not action.command or not _dossier_shape_ok(action):
                reasons.append(
                    "GenerateCodesigningDossier parameters are not create @dossier_arguments"
                )
            else:
                written = _filewrite_for_dossier(actions, action)
                if written is not None:
                    body = written.command
                    if "--codesign_identity" not in body:
                        reasons.append(
                            "dossier_arguments is in the graph but its contents are not visible"
                        )
                    else:
                        body_danger = _dangerous_parameter(body)
                        if body_danger:
                            reasons.append("dossier_arguments has %s" % body_danger)
                        elif _identity_tokens(body) != ["-"]:
                            reasons.append("dossier_arguments identity is not the ad-hoc '-'")
        elif action.mnemonic == "TemplateExpand" and "should_sign" in action.command:
            reasons.append("template expansion carries should_sign")

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
