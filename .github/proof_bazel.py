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

The gate uses Bazel 9.2 --output=jsonproto (JsonFormat.printer of
ActionGraphContainer). TemplateExpand.template_content is one string, so the
blank lines, shebang, and # copyright lines in rules_apple templates stay
inside the field. A text dump of that same string ends the action at the
first blank line and then treats # Copyright as a new record.

rules_apple 485016eb:
- ios_test_runner and the unit-test executable are expand_template actions.
  The executable's template is a derived artifact, so getTemplateContent
  returns "ARTIFACT: <exec path>" and the body is the earlier expansion.
- process_and_sign.sh.template is expanded only when there is signing work,
  a post-processor, or compression. codesigning_support.bzl registers the
  cp -p ProcessAndSign and returns before expand_template otherwise. Debug
  simulator builds do not compress, and the skip-codesign feature leaves
  signing_command_lines empty, so that template action is absent. A direct
  cp does not need it. A ProcessAndSign that executes a script, or a
  template that is present, is audited from the expanded body. The real
  template has %signing_command_lines% and no /usr/bin/codesign. A body
  that hardcodes that path still signs when the substitution is empty.
- Empty ProcessAndSign is /bin/bash -c "cp -p ...". should_sign runs the
  generated script.
- GenerateCodesigningDossier writes dossier_arguments with actions.write.
  Simulator identity is the ad-hoc "-". A profile is not embedded for it.

The executed text of a template is the body after substitutions, following
ARTIFACT: links. An empty graph, a truncated document, a missing body, or an
unresolved placeholder is not evidence that the action is unsigned.
"""
import argparse
import hashlib
import json
import os
import re
import stat
import subprocess
import sys

FEATURE = "--features=apple.skip_codesign_simulator_bundles"
GATED_COMMANDS = ("build", "test")
AQUERY_STRIP = ("--subcommands",)
AQUERY_OPTIONS = (
    "--output=jsonproto",
    "--include_commandline",
    "--include_param_files",
    "--include_file_write_contents",
)
_PLACEHOLDER_RE = re.compile(r"%\([A-Za-z0-9_]+\)s|%[A-Za-z0-9_]+%")
_COPY_RE = re.compile(r"^cp -p (?:'[^']+'|\S+) (?:'[^']+'|\S+)$")
_RUNNER_COPYRIGHT = "# Copyright 2018 The Bazel Authors"


class Action(object):
    def __init__(self):
        self.mnemonic = ""
        self.arguments = []
        self.outputs = []
        self.params = {}
        self.file_contents = None
        self.saw_file_contents = False
        self.template_content = None
        self.substitutions = {}
        self.expanded = None


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


def _fragment_path(fragments, fragment_id, seen):
    if fragment_id in seen or fragment_id not in fragments:
        return None
    fragment = fragments[fragment_id]
    label = fragment.get("label")
    if not isinstance(label, str) or label == "":
        return None
    parent = fragment.get("parentId") or 0
    if not parent:
        return label
    prefix = _fragment_path(fragments, parent, seen | {fragment_id})
    if prefix is None:
        return None
    return prefix + "/" + label


def _as_dict_list(value):
    if value is None:
        return []
    if not isinstance(value, list) or any(not isinstance(item, dict) for item in value):
        return None
    return value


def load_actions(text):
    """Parse a Bazel 9.2 aquery jsonproto document."""
    if text is None or text.strip() == "":
        return [], ["empty action graph"]
    try:
        document = json.loads(text)
    except json.JSONDecodeError:
        return [], ["truncated or invalid jsonproto"]
    if not isinstance(document, dict):
        return [], ["jsonproto is not an object"]
    raw_actions = _as_dict_list(document.get("actions"))
    raw_artifacts = _as_dict_list(document.get("artifacts"))
    raw_fragments = _as_dict_list(document.get("pathFragments"))
    if raw_actions is None or raw_artifacts is None or raw_fragments is None:
        return [], ["jsonproto fields are not the Bazel 9.2 container shape"]
    if not raw_actions:
        return [], ["empty action graph"]

    fragments = {}
    for fragment in raw_fragments:
        identifier = fragment.get("id")
        if not isinstance(identifier, int):
            return [], ["path fragment id is missing"]
        if identifier in fragments:
            return [], ["duplicate path fragment id"]
        fragments[identifier] = fragment
    artifacts = {}
    for artifact in raw_artifacts:
        identifier = artifact.get("id")
        fragment_id = artifact.get("pathFragmentId")
        if not isinstance(identifier, int) or not isinstance(fragment_id, int):
            return [], ["artifact path is missing"]
        if identifier in artifacts:
            return [], ["duplicate artifact id"]
        path = _fragment_path(fragments, fragment_id, set())
        if path is None:
            return [], ["artifact path fragment is truncated or cyclic"]
        artifacts[identifier] = path

    actions = []
    for raw in raw_actions:
        action = Action()
        mnemonic = raw.get("mnemonic")
        if not isinstance(mnemonic, str) or mnemonic == "":
            return [], ["action has no mnemonic"]
        action.mnemonic = mnemonic
        arguments = raw.get("arguments", [])
        if not isinstance(arguments, list) or any(not isinstance(item, str) for item in arguments):
            return [], ["action arguments are not a string list"]
        action.arguments = arguments
        output_ids = raw.get("outputIds", [])
        if not isinstance(output_ids, list):
            return [], ["action outputs are truncated"]
        for output_id in output_ids:
            if output_id not in artifacts:
                return [], ["action output artifact is missing"]
            action.outputs.append(artifacts[output_id])
        if "fileContents" in raw:
            if not isinstance(raw["fileContents"], str):
                return [], ["fileContents is not a string"]
            action.file_contents = raw["fileContents"]
            action.saw_file_contents = True
        if "templateContent" in raw:
            if not isinstance(raw["templateContent"], str):
                return [], ["templateContent is not a string"]
            action.template_content = raw["templateContent"]
        substitutions = raw.get("substitutions", [])
        if not isinstance(substitutions, list):
            return [], ["substitutions are truncated"]
        for pair in substitutions:
            if not isinstance(pair, dict):
                return [], ["substitution is not a key/value"]
            key = pair.get("key")
            value = pair.get("value", "")
            if not isinstance(key, str) or key == "" or not isinstance(value, str):
                return [], ["substitution key or value is not a string"]
            if key in action.substitutions:
                return [], ["duplicate substitution key"]
            action.substitutions[key] = value
        for param in raw.get("paramFiles", []):
            if not isinstance(param, dict):
                return [], ["param file is truncated"]
            path = param.get("execPath")
            param_args = param.get("arguments")
            if not isinstance(path, str) or not isinstance(param_args, list):
                return [], ["param file is truncated"]
            if any(not isinstance(item, str) for item in param_args):
                return [], ["param file arguments are not strings"]
            if path in action.params:
                return [], ["duplicate param file"]
            action.params[path] = param_args
        actions.append(action)
    return actions, []


def expand_template(template, substitutions):
    """One-pass Bazel expand_template. Overlapping keys are ambiguous."""
    keys = list(substitutions)
    for left in keys:
        for right in keys:
            if left != right and (left in right or right in left):
                return None
    if not keys:
        return template
    ordered = sorted(keys, key=len, reverse=True)
    pattern = re.compile("|".join(re.escape(key) for key in ordered))
    return pattern.sub(lambda match: substitutions[match.group(0)], template)


def resolve_templates(actions):
    """Fill action.expanded. Follow ARTIFACT: links from getTemplateContent."""
    errors = []
    pending = [action for action in actions if action.mnemonic == "TemplateExpand"]
    produced = {}
    progressed = True
    while pending and progressed:
        progressed = False
        remaining = []
        for action in pending:
            content = action.template_content
            if content is None:
                errors.append("TemplateExpand templateContent is missing")
                progressed = True
                continue
            if content.startswith("ERROR: "):
                errors.append("TemplateExpand template failed to load")
                progressed = True
                continue
            if content.startswith("ARTIFACT: "):
                path = content[len("ARTIFACT: "):]
                if path not in produced:
                    remaining.append(action)
                    continue
                content = produced[path]
            expanded = expand_template(content, action.substitutions)
            if expanded is None:
                errors.append("template substitutions overlap; expansion is ambiguous")
                progressed = True
                continue
            # JsonFormat.printer omits empty strings. rules_apple always sets
            # %signing_command_lines%, and an empty value means the script
            # does not sign. Any other leftover placeholder is unresolved.
            if "%signing_command_lines%" not in action.substitutions:
                expanded = expanded.replace("%signing_command_lines%", "")
            action.expanded = expanded
            if not action.outputs:
                errors.append("TemplateExpand output path is missing")
            for path in action.outputs:
                if path in produced and produced[path] != expanded:
                    errors.append("two templates write %s" % path)
                produced[path] = expanded
            progressed = True
        pending = remaining
    if pending:
        errors.append("derived template body is not visible")
    return errors


def _signing_marker(text):
    if text is None:
        return None
    if "/usr/bin/codesign" in text or "codesign_allocate" in text:
        return "/usr/bin/codesign"
    if ".mobileprovision" in text or "--provisioning_profile" in text:
        return "provisioning profile"
    if "--entitlements_file" in text or "--infer_identity" in text:
        return "entitlement or inferred identity"
    if re.search(r"(^|[\s'\"])should_sign($|[\s'\"])", text):
        return "should_sign"
    return None


def dossier_lines_safe(lines):
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
    if arguments == ["should_sign"] or "should_sign" in arguments:
        return False
    if len(arguments) != 3 or arguments[1] != "-c":
        return False
    if not (arguments[0] == "bash" or arguments[0].endswith("/bash")):
        return False
    return _COPY_RE.match(arguments[2]) is not None


def _contents_for(path, action, actions):
    found = []
    if path in action.params:
        found.append("\n".join(action.params[path]))
    for other in actions:
        if path in other.outputs and other.file_contents is not None:
            found.append(other.file_contents)
        if path in other.outputs and other.expanded is not None:
            found.append(other.expanded)
    if not found:
        return None, False
    normalized = [item.rstrip("\n") for item in found]
    if any(item != normalized[0] for item in normalized[1:]):
        return None, True
    return normalized[0], False


def _artifact_refs(actions):
    refs = set()
    for action in actions:
        content = action.template_content or ""
        if content.startswith("ARTIFACT: "):
            refs.add(content[len("ARTIFACT: "):])
    return refs


def _runner_source(action):
    content = action.template_content or ""
    return (
        content.startswith("#!/bin/bash\n")
        and "\n\n# Copyright" in "\n" + content
        and _RUNNER_COPYRIGHT in content
        and "%(test_bundle_path)s" in content
    )


def evaluate_graph(text, flags):
    """Return whether this configured graph may be executed."""
    reasons = []
    if FEATURE not in flags:
        reasons.append("skip_codesign feature is not on the aquery command")
    if "--output=jsonproto" not in flags:
        reasons.append("aquery output is not jsonproto")
    for option in ("--include_file_write_contents", "--include_param_files"):
        if option not in flags:
            reasons.append("aquery was not asked for %s" % option)
    cpus = _ios_cpus(flags)
    if "sim_arm64" not in cpus:
        reasons.append("configuration has no sim_arm64 cpu")
    if any(not cpu.startswith("sim_") for cpu in cpus):
        reasons.append("device ios cpu in %s" % ",".join(cpus))

    actions, parse_errors = load_actions(text)
    reasons.extend(parse_errors)
    reasons.extend(resolve_templates(actions))
    referenced_templates = _artifact_refs(actions)

    saw_runner = False
    saw_runner_executable = False
    for action in actions:
        if action.mnemonic == "FileWrite" and not action.saw_file_contents:
            reasons.append("FileWrite fileContents is missing")
        if action.mnemonic == "SignBinary":
            reasons.append("SignBinary is a signing action")
        elif action.mnemonic == "ProcessAndSign":
            if not action.arguments:
                reasons.append("ProcessAndSign arguments are not visible")
            elif "should_sign" in action.arguments:
                reasons.append("ProcessAndSign should_sign; the generated script signs")
            elif _empty_copy(action.arguments):
                pass
            else:
                scripts = [arg for arg in action.arguments if arg.endswith(".sh")]
                if not scripts:
                    reasons.append("ProcessAndSign is not the empty cp -p action")
                for script in scripts:
                    body, conflict = _contents_for(script, action, actions)
                    if conflict:
                        reasons.append("ProcessAndSign script sources disagree")
                    elif body is None:
                        reasons.append("ProcessAndSign script contents are not in the graph")
                    else:
                        marker = _signing_marker(body)
                        if marker:
                            reasons.append("ProcessAndSign script contains %s" % marker)
        elif action.mnemonic == "GenerateCodesigningDossier":
            if len(action.arguments) < 3 or action.arguments[1] != "create":
                reasons.append("GenerateCodesigningDossier arguments are not visible")
            else:
                referenced = [arg[1:] for arg in action.arguments if arg.startswith("@")]
                if len(referenced) != 1:
                    reasons.append("GenerateCodesigningDossier args file is not a single @file")
                else:
                    body, conflict = _contents_for(referenced[0], action, actions)
                    if conflict:
                        reasons.append("dossier argument sources disagree")
                    elif body is None:
                        reasons.append("dossier_arguments contents are not in the graph")
                    else:
                        problem = dossier_lines_safe(body.splitlines())
                        if problem:
                            reasons.append(problem)
        elif action.mnemonic == "TemplateExpand":
            if _runner_source(action):
                saw_runner = True
            if (action.template_content or "").startswith("ARTIFACT: "):
                produced = (action.template_content or "")[len("ARTIFACT: "):]
                producer = next((
                    other for other in actions
                    if produced in other.outputs and _runner_source(other)
                ), None)
                if producer is not None and action.expanded is not None:
                    saw_runner_executable = True
            if action.expanded is None:
                continue
            marker = _signing_marker(action.expanded)
            if marker:
                reasons.append("template body contains %s" % marker)
            final = not any(path in referenced_templates for path in action.outputs)
            if final and _PLACEHOLDER_RE.search(action.expanded):
                reasons.append("expanded template still has an unresolved placeholder")
        elif action.mnemonic == "FileWrite":
            if action.file_contents is not None:
                marker = _signing_marker(action.file_contents)
                if marker:
                    reasons.append("FileWrite contains %s" % marker)
        else:
            reasons.append("unknown action %s" % action.mnemonic)

    if not saw_runner or not saw_runner_executable:
        reasons.append(
            "ios_test_runner expand_template chain is missing; "
            "the unit-test executable template was not audited"
        )
    if not any(action.mnemonic == "ProcessAndSign" for action in actions):
        reasons.append("ProcessAndSign is absent")
    if not any(action.mnemonic == "GenerateCodesigningDossier" for action in actions):
        reasons.append("GenerateCodesigningDossier is absent")

    unique = []
    for reason in reasons:
        if reason not in unique:
            unique.append(reason)
    return Decision(not unique, unique)


_LIST_LIMIT = 40
_MNEMONIC_RE = re.compile(r"^[A-Z][A-Za-z0-9]{0,40}$")
_LABEL_RE = re.compile(r"^//[A-Za-z0-9.+/-]*:[A-Za-z0-9.+_-]+$")
_PLACEHOLDER_KEY_RE = re.compile(r"^%(?:\([A-Za-z_][A-Za-z0-9_]*\)s|[a-z][a-z0-9_]+%)$")
_EXACT_TOKENS = frozenset((
    "-",
    "-c",
    "bash",
    "/bin/bash",
    "/usr/bin/bash",
    "/usr/bin/codesign",
    "codesign_allocate",
    "create",
    "should_sign",
    "--output",
    "--zip",
    "--codesign_identity",
    "--embedded_dossier",
    "--entitlements_file",
    "--provisioning_profile",
    "--infer_identity",
))


def diagnostics_requested(environ=None):
    """Explicit diagnostics mode. Default off. Never changes the allow decision."""
    environ = os.environ if environ is None else environ
    return environ.get("TELLOMI_PROOF_DIAGNOSTICS") == "1"


def fingerprint(text):
    """Stable id for a string that is not on the public-syntax allowlist."""
    encoded = text.encode("utf-8")
    return {
        "shown": False,
        "sha256": hashlib.sha256(encoded).hexdigest()[:16],
        "len": len(encoded),
    }


def project_token(text, kind):
    """Return a log value. Unknown strings are fingerprints, never copied."""
    if kind == "mnemonic" and _MNEMONIC_RE.match(text):
        return {"type": "mnemonic", "shown": True, "text": text}
    if kind == "label" and _LABEL_RE.match(text) and "\n" not in text and "\r" not in text:
        return {"type": "label", "shown": True, "text": text}
    if kind == "key" and _PLACEHOLDER_KEY_RE.match(text):
        return {"type": "placeholder", "shown": True, "text": text}
    if kind == "token" and text in _EXACT_TOKENS:
        return {"type": "token", "shown": True, "text": text}
    ident = fingerprint(text)
    ident["type"] = kind
    return ident


def _emit(records):
    """One diag JSON object per line. User text cannot start a workflow command."""
    lines = []
    for record in records:
        encoded = json.dumps(record, ensure_ascii=True, sort_keys=True)
        if "\n" in encoded or "\r" in encoded:
            encoded = json.dumps(
                {"kind": "dropped", "reason": "serializer emitted a control character"},
                ensure_ascii=True,
            )
        line = "diag " + encoded
        if line.lstrip().startswith("::"):
            line = "diag " + json.dumps({"kind": "dropped", "reason": "workflow command"})
        lines.append(line)
    return "\n".join(lines) + "\n"


def _artifact_paths(document):
    fragments = {}
    for fragment in document.get("pathFragments") or []:
        if isinstance(fragment, dict) and isinstance(fragment.get("id"), int):
            fragments[fragment["id"]] = fragment
    paths = {}
    for artifact in document.get("artifacts") or []:
        if not isinstance(artifact, dict):
            continue
        identifier = artifact.get("id")
        fragment_id = artifact.get("pathFragmentId")
        if not isinstance(identifier, int) or not isinstance(fragment_id, int):
            continue
        path = _fragment_path(fragments, fragment_id, set())
        if path is not None:
            paths[identifier] = path
    return paths


def _walk_inputs(document, paths, dep_ids, cap):
    depsets = {}
    for depset in document.get("depSetOfFiles") or []:
        if isinstance(depset, dict) and isinstance(depset.get("id"), int):
            depsets[depset["id"]] = depset
    found = []
    truncated = False
    seen = set()
    stack = list(dep_ids or [])
    while stack:
        dep_id = stack.pop()
        if dep_id in seen:
            continue
        seen.add(dep_id)
        depset = depsets.get(dep_id)
        if depset is None:
            truncated = True
            continue
        for artifact_id in depset.get("directArtifactIds") or []:
            path = paths.get(artifact_id)
            if path is None:
                truncated = True
                continue
            if len(found) >= cap:
                truncated = True
                return found, truncated
            found.append(path)
        stack.extend(depset.get("transitiveDepSetIds") or [])
    return found, truncated


def _field_list(values, kind, truncated):
    shown = []
    if not isinstance(values, list):
        return [{"type": kind, "shown": False, "reason": "not a list"}], True
    for value in values[:_LIST_LIMIT]:
        if not isinstance(value, str):
            shown.append({"type": kind, "shown": False, "reason": "not a string"})
            truncated = True
            continue
        shown.append(project_token(value, kind))
    if len(values) > _LIST_LIMIT:
        truncated = True
        shown.append({"type": kind, "shown": False, "reason": "truncated", "count": len(values)})
    return shown, truncated


def _template_record(template, producers):
    if not isinstance(template, str):
        return {"contents": "omitted", "reason": "not a string"}, True
    if template.startswith("ARTIFACT: ") and "\n" not in template and "\r" not in template:
        path = template[len("ARTIFACT: "):]
        ident = project_token(path, "path")
        producer = producers.get(path)
        return {
            "contents": "omitted",
            "form": "artifact-ref",
            "path": ident,
            "producer": project_token(producer, "mnemonic") if producer else {"shown": False, "reason": "absent"},
        }, producer is None
    ident = fingerprint(template)
    ident["contents"] = "omitted"
    ident["form"] = "template"
    return ident, False


def project_aquery(text):
    """Whitelist projection. Free text is fingerprinted, never copied."""
    header = {
        "kind": "header",
        "note": "whitelist projection; not a raw action graph",
    }
    if text is None or str(text).strip() == "":
        return _emit([header, {
            "kind": "unparsed",
            "note": "aquery document was not parsed; not a complete graph",
            "documentBytes": 0,
        }])
    try:
        document = json.loads(text)
    except json.JSONDecodeError:
        return _emit([header, {
            "kind": "unparsed",
            "note": "aquery document was not parsed; not a complete graph",
            "documentBytes": len(text),
        }])
    if not isinstance(document, dict) or not isinstance(document.get("actions"), list):
        return _emit([header, {
            "kind": "unparsed",
            "note": "aquery document was not parsed; not a complete graph",
        }])
    actions = document["actions"]
    paths = _artifact_paths(document)
    labels = {}
    for target in document.get("targets") or []:
        if isinstance(target, dict) and isinstance(target.get("id"), int):
            labels[target["id"]] = target.get("label") if isinstance(target.get("label"), str) else ""
    producers = {}
    counts = {}
    for raw in actions:
        if not isinstance(raw, dict):
            continue
        mnemonic = raw.get("mnemonic") if isinstance(raw.get("mnemonic"), str) else ""
        counts[mnemonic] = counts.get(mnemonic, 0) + 1
        for output_id in raw.get("outputIds") or []:
            path = paths.get(output_id)
            if path:
                producers[path] = mnemonic
    truncated = False
    records = [header, {
        "kind": "summary",
        "actions": len(actions),
        "mnemonics": {
            (name if _MNEMONIC_RE.match(name) else fingerprint(name)["sha256"]): counts[name]
            for name in sorted(counts)
        },
    }]
    shown = 0
    for raw in actions:
        if not isinstance(raw, dict):
            continue
        if shown >= _LIST_LIMIT:
            truncated = True
            records.append({"kind": "truncated", "note": "action list truncated", "count": len(actions)})
            break
        shown += 1
        mnemonic = raw.get("mnemonic") if isinstance(raw.get("mnemonic"), str) else ""
        outputs = []
        for output_id in raw.get("outputIds") or []:
            path = paths.get(output_id)
            outputs.append(project_token(path, "path") if path else {"type": "path", "shown": False, "reason": "unresolved"})
        inputs, inputs_cut = _walk_inputs(document, paths, raw.get("inputDepSetIds") or [], _LIST_LIMIT)
        truncated = truncated or inputs_cut
        arguments, arg_cut = _field_list(raw.get("arguments") or [], "token", False)
        truncated = truncated or arg_cut
        template_record = None
        template_cut = False
        if "templateContent" in raw:
            template_record, template_cut = _template_record(raw.get("templateContent"), producers)
            truncated = truncated or template_cut
        substitutions = []
        pairs = raw.get("substitutions") or []
        if isinstance(pairs, list):
            for pair in pairs[:_LIST_LIMIT]:
                if not isinstance(pair, dict) or not isinstance(pair.get("key"), str) or not isinstance(pair.get("value", ""), str):
                    truncated = True
                    substitutions.append({"key": {"shown": False}, "value": {"contents": "omitted"}})
                    continue
                value = pair.get("value", "")
                substitutions.append({
                    "key": project_token(pair["key"], "key"),
                    "value": {"contents": "omitted", **fingerprint(value)},
                })
            if len(pairs) > _LIST_LIMIT:
                truncated = True
        param_files = []
        for param in raw.get("paramFiles") or []:
            if not isinstance(param, dict):
                truncated = True
                continue
            param_args, param_cut = _field_list(param.get("arguments") or [], "token", False)
            truncated = truncated or param_cut
            path = param.get("execPath") if isinstance(param.get("execPath"), str) else ""
            param_files.append({"path": project_token(path, "path"), "arguments": param_args})
        file_record = None
        if "fileContents" in raw:
            body = raw.get("fileContents")
            if isinstance(body, str):
                file_record = {"contents": "omitted", **fingerprint(body)}
            else:
                file_record = {"contents": "omitted", "shown": False, "reason": "not a string"}
                truncated = True
        records.append({
            "kind": "action",
            "mnemonic": project_token(mnemonic, "mnemonic"),
            "target": project_token(labels.get(raw.get("targetId"), ""), "label"),
            "outputs": outputs,
            "inputs": [project_token(path, "path") for path in inputs],
            "inputsTruncated": inputs_cut,
            "arguments": arguments,
            "template": template_record,
            "substitutions": substitutions,
            "paramFiles": param_files,
            "fileContents": file_record,
            "environmentVariables": {"contents": "omitted", "count": len(raw.get("environmentVariables") or [])},
            "executionInfo": "omitted" if "executionInfo" in raw else None,
        })
    if truncated:
        records.append({
            "kind": "truncated",
            "note": "truncated fields are incomplete; not a complete graph",
        })
    return _emit(records)


def project_aquery_failure(stderr):
    body = stderr or ""
    return _emit([{
        "kind": "failure",
        "note": "aquery failed; not a complete graph",
        "stderr": {"contents": "omitted", **fingerprint(body)},
    }])


_SAFE_REASON = re.compile(
    r"^(?:unknown action [A-Z][A-Za-z0-9]*"
    r"|template body contains (?:/usr/bin/codesign|provisioning profile|entitlement or inferred identity|should_sign)"
    r"|ProcessAndSign script contains (?:/usr/bin/codesign|provisioning profile|entitlement or inferred identity|should_sign)"
    r"|FileWrite contains (?:/usr/bin/codesign|provisioning profile|entitlement or inferred identity|should_sign)"
    r"|aquery was not asked for --[a-z_]+"
    r"|device ios cpu in [a-z0-9_]+(?:,[a-z0-9_]+)*)$"
)


def log_reason(reason):
    """Print a gate reason only when it is our own sentence, not graph text."""
    if "\n" not in reason and "\r" not in reason and (
        reason in {
            "skip_codesign feature is not on the aquery command",
            "aquery output is not jsonproto",
            "configuration has no sim_arm64 cpu",
            "empty action graph",
            "empty action graph is not evidence that signing is absent",
            "truncated or invalid jsonproto",
            "jsonproto is not an object",
            "jsonproto fields are not the Bazel 9.2 container shape",
            "path fragment id is missing",
            "duplicate path fragment id",
            "artifact path is missing",
            "duplicate artifact id",
            "artifact path fragment is truncated or cyclic",
            "action has no mnemonic",
            "action arguments are not a string list",
            "action outputs are truncated",
            "action output artifact is missing",
            "fileContents is not a string",
            "templateContent is not a string",
            "substitutions are truncated",
            "substitution is not a key/value",
            "substitution key or value is not a string",
            "duplicate substitution key",
            "param file is truncated",
            "param file arguments are not strings",
            "duplicate param file",
            "TemplateExpand templateContent is missing",
            "TemplateExpand template failed to load",
            "template substitutions overlap; expansion is ambiguous",
            "TemplateExpand output path is missing",
            "derived template body is not visible",
            "FileWrite fileContents is missing",
            "SignBinary is a signing action",
            "ProcessAndSign arguments are not visible",
            "ProcessAndSign should_sign; the generated script signs",
            "ProcessAndSign is not the empty cp -p action",
            "ProcessAndSign script sources disagree",
            "ProcessAndSign script contents are not in the graph",
            "GenerateCodesigningDossier arguments are not visible",
            "GenerateCodesigningDossier args file is not a single @file",
            "dossier argument sources disagree",
            "dossier_arguments contents are not in the graph",
            "dossier arguments are empty",
            "dossier arguments contain /usr/bin/codesign",
            "dossier arguments contain provisioning profile",
            "dossier arguments contain entitlement or inferred identity",
            "dossier arguments contain should_sign",
            "dossier identity is truncated",
            "dossier arguments have no --output/--zip",
            "ios_test_runner expand_template chain is missing; the unit-test executable template was not audited",
            "ProcessAndSign is absent",
            "GenerateCodesigningDossier is absent",
            "expanded template still has an unresolved placeholder",
        }
        or _SAFE_REASON.match(reason)
    ):
        return "signing-boundary: " + reason
    ident = fingerprint(reason)
    return "signing-boundary: omitted sha256:%s len:%d" % (ident["sha256"], ident["len"])


def wrapper_main(argv, real, run=None, execv=None, environ=None):
    """Gate build/test, then exec the real binary. Other commands are forwarded."""
    run = run or subprocess.run
    execv = execv or os.execv
    diagnose = diagnostics_requested(environ)
    if command_index(argv) is None:
        forwarded = [real] + list(argv[1:])
        execv(forwarded[0], forwarded)
        return 0

    query = aquery_argv(real, argv)
    completed = run(query, check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if completed.returncode != 0:
        if diagnose:
            sys.stderr.write(project_aquery_failure(completed.stderr))
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
    if diagnose:
        sys.stderr.write(project_aquery(completed.stdout or ""))
    if diagnose:
        sys.stderr.write("diagnostics-only: build was not executed\n")
        if not decision.allow:
            sys.stderr.write("refusing to execute bazel; signing boundary failed before any build action\n")
            for reason in decision.reasons:
                sys.stderr.write(log_reason(reason) + "\n")
        return 2
    if not decision.allow:
        sys.stderr.write("refusing to execute bazel; signing boundary failed before any build action\n")
        for reason in decision.reasons:
            sys.stderr.write(log_reason(reason) + "\n")
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
