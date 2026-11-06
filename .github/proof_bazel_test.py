#!/usr/bin/env python3
"""Simulate Make.py lookup and the jsonproto signing gate."""
import json
import os
import re
import shutil
import stat
import sys
import tempfile
import textwrap

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(ROOT, "build-system", "Make"))

import ci_gate  # noqa: E402
import proof_bazel  # noqa: E402

TARGET = "//Tests/TellomiFeedProof:TellomiFeedProofTests"
FIXTURE_DIR = os.path.join(os.path.dirname(__file__), "proof-fixtures")
RUNNER_TEMPLATE = open(
    os.path.join(FIXTURE_DIR, "ios_test_runner.template.sh"), encoding="utf-8").read()
PROCESS_TEMPLATE = open(
    os.path.join(FIXTURE_DIR, "process_and_sign.sh.template"), encoding="utf-8").read()
DOSSIER_PATH = (
    "bazel-out/ios_sim_arm64-dbg/bin/TellomiFeedProofTests-intermediates/dossier_arguments"
)
RUNNER_OUT = "bazel-out/ios_sim_arm64-dbg/bin/TellomiFeedProofRunner.sh"
EXECUTABLE = "bazel-out/ios_sim_arm64-dbg/bin/TellomiFeedProofTests"
SIGN_SCRIPT = "bazel-out/ios_sim_arm64-dbg/bin/process-and-sign-abc.sh"
RUNNER_FIRST = {
    "%(create_simulator_action_binary)s",
    "%(device_type)s",
    "%(os_version)s",
    "%(post_action_binary)s",
    "%(post_action_determines_exit_code)s",
    "%(pre_action_binary)s",
    "%(sdk_version)s",
    "%(testrunner_binary)s",
}
DOSSIER_LINES = [
    "--output",
    "bazel-out/ios_sim_arm64-dbg/bin/TellomiFeedProofTests_dossier.zip",
    "--zip",
    "--codesign_identity",
    "-",
]
_PLACEHOLDER_RE = re.compile(r"%\([A-Za-z0-9_]+\)s|%[A-Za-z0-9_]+%")


def fail(message):
    sys.stderr.write("proof_bazel_test: %s\n" % message)
    sys.exit(1)


def placeholders(text):
    return set(_PLACEHOLDER_RE.findall(text))


class Builder(object):
    """Minimal Bazel 9.2 ActionGraphContainer JSON."""

    def __init__(self):
        self.next_id = 1
        self.fragments = []
        self.fragment_ids = {}
        self.artifacts = []
        self.actions = []

    def fragment(self, path):
        last = None
        built = ""
        for part in path.split("/"):
            built = part if not built else built + "/" + part
            if built not in self.fragment_ids:
                identifier = self.next_id
                self.next_id += 1
                entry = {"id": identifier, "label": part}
                if last is not None:
                    entry["parentId"] = last
                self.fragments.append(entry)
                self.fragment_ids[built] = identifier
            last = self.fragment_ids[built]
        return last

    def artifact(self, path):
        identifier = self.next_id
        self.next_id += 1
        self.artifacts.append({"id": identifier, "pathFragmentId": self.fragment(path)})
        return identifier

    def add(self, mnemonic, outputs, arguments=None, template=None, substitutions=None,
            file_contents=None, write_contents=False, param_files=None):
        identifiers = [self.artifact(path) for path in outputs]
        action = {
            "mnemonic": mnemonic,
            "targetId": 1,
            "outputIds": identifiers,
            "primaryOutputId": identifiers[0],
        }
        if arguments is not None:
            action["arguments"] = arguments
        if template is not None:
            action["templateContent"] = template
        if substitutions:
            action["substitutions"] = substitutions
        if write_contents:
            action["fileContents"] = file_contents
        if param_files:
            action["paramFiles"] = param_files
        self.actions.append(action)

    def dumps(self):
        return json.dumps({
            "artifacts": self.artifacts,
            "actions": self.actions,
            "pathFragments": self.fragments,
            "targets": [{"id": 1, "label": TARGET}],
        })


def pairs(keys, values=None):
    values = values or {}
    return [{"key": key, "value": values.get(key, "filled")} for key in sorted(keys)]


def safe_document(process_text=None, signing_value="", omit_keys=(),
                  process_arguments=None, dossier_text=None, dossier_params=None,
                  include_dossier_write=True, include_process_template=False,
                  artifact_path=None):
    process_text = PROCESS_TEMPLATE if process_text is None else process_text
    builder = Builder()
    if include_dossier_write:
        builder.add(
            "FileWrite",
            [DOSSIER_PATH],
            file_contents="\n".join(DOSSIER_LINES) if dossier_text is None else dossier_text,
            write_contents=True,
        )
    dossier_arguments = [
        "external/apple_support/bin/dossier_codesigningtool",
        "create",
        "@" + DOSSIER_PATH,
    ]
    param_files = None
    if dossier_params is not None:
        param_files = [{"execPath": DOSSIER_PATH, "arguments": dossier_params}]
    builder.add(
        "GenerateCodesigningDossier",
        ["bazel-out/ios_sim_arm64-dbg/bin/TellomiFeedProofTests_dossier.zip"],
        arguments=dossier_arguments,
        param_files=param_files,
    )
    builder.add(
        "ProcessAndSign",
        ["bazel-out/ios_sim_arm64-dbg/bin/TellomiFeedProofTests.zip"],
        arguments=process_arguments or [
            "/bin/bash",
            "-c",
            "cp -p 'bazel-out/ios_sim_arm64-dbg/bin/unprocessed_archive.zip' "
            "'bazel-out/ios_sim_arm64-dbg/bin/TellomiFeedProofTests.zip'",
        ],
    )
    runner_keys = placeholders(RUNNER_TEMPLATE)
    first = runner_keys & RUNNER_FIRST
    second = runner_keys - RUNNER_FIRST
    builder.add(
        "TemplateExpand",
        [RUNNER_OUT],
        template=RUNNER_TEMPLATE,
        substitutions=pairs(first),
    )
    builder.add(
        "TemplateExpand",
        [EXECUTABLE],
        template="ARTIFACT: " + (artifact_path or RUNNER_OUT),
        substitutions=pairs(second),
    )
    if include_process_template:
        sign_keys = placeholders(process_text)
        sign_values = {key: "filled" for key in sign_keys}
        if "%signing_command_lines%" in sign_keys:
            sign_values["%signing_command_lines%"] = signing_value
        sign_pairs = [item for item in pairs(sign_keys, sign_values) if item["key"] not in omit_keys]
        builder.add(
            "TemplateExpand",
            [SIGN_SCRIPT],
            template=process_text,
            substitutions=sign_pairs,
        )
    return builder.dumps()


SAFE_GRAPH = safe_document()
HARDCODED_TEMPLATE = PROCESS_TEMPLATE.replace(
    "%signing_command_lines%",
    "/usr/bin/codesign --force --sign - \"$WORK_DIR\"\n%signing_command_lines%",
    1,
)
HARDCODED_GRAPH = safe_document(
    process_text=HARDCODED_TEMPLATE,
    process_arguments=[SIGN_SCRIPT],
    include_process_template=True,
)
HIDDEN_SCRIPT = HARDCODED_GRAPH


def flags_of():
    return [
        "--output=jsonproto",
        "--include_commandline",
        "--include_param_files",
        "--include_file_write_contents",
        "--announce_rc",
        "--ios_multi_cpus=sim_arm64",
        "--//Telegram:disableProvisioningProfiles",
        proof_bazel.FEATURE,
    ]


def expect_allow(text, flags, label):
    decision = proof_bazel.evaluate_graph(text, flags)
    if not decision.allow:
        fail("%s was refused: %s" % (label, "; ".join(decision.reasons)))


def expect_deny(text, flags, label):
    decision = proof_bazel.evaluate_graph(text, flags)
    if decision.allow:
        fail("%s was allowed" % label)
    return decision.reasons


def test_graph_boundary():
    if not RUNNER_TEMPLATE.startswith("#!/bin/bash\n\n# Copyright 2018 The Bazel Authors"):
        fail("vendored ios_test_runner template is not the pinned file")
    if "%signing_command_lines%" not in PROCESS_TEMPLATE or "/usr/bin/codesign" in PROCESS_TEMPLATE:
        fail("vendored process_and_sign template is not the pinned file")
    if not (placeholders(RUNNER_TEMPLATE) & RUNNER_FIRST):
        fail("runner template has none of the ios_test_runner substitutions")
    if placeholders(RUNNER_TEMPLATE) - RUNNER_FIRST == set():
        fail("runner template has no second-stage placeholders")

    parsed = json.loads(SAFE_GRAPH)
    stored = [
        action["templateContent"]
        for action in parsed["actions"]
        if action.get("mnemonic") == "TemplateExpand"
        and action.get("templateContent", "").startswith("#!/bin/bash")
    ]
    if not stored or stored[0].splitlines()[1] != "":
        fail("jsonproto dropped the template blank line")
    if "# Copyright 2018 The Bazel Authors" not in stored[0]:
        fail("jsonproto dropped the template copyright line")
    if not any(
        action.get("templateContent", "").startswith("ARTIFACT: " + RUNNER_OUT)
        for action in parsed["actions"]
    ):
        fail("unit-test executable template is not an ARTIFACT link")

    flags = flags_of()
    unsigned = json.loads(SAFE_GRAPH)
    if any(
        "%signing_command_lines%" in action.get("templateContent", "")
        for action in unsigned["actions"]
    ):
        fail("the unsigned cp graph still contains a process_and_sign template")
    expect_allow(SAFE_GRAPH, flags, "debug cp -p with runner and dossier and no process template")
    expect_allow(
        safe_document(include_process_template=True),
        flags,
        "a present process_and_sign template with empty signing lines",
    )
    param_only = safe_document(include_dossier_write=False, dossier_params=list(DOSSIER_LINES))
    expect_allow(param_only, flags, "dossier arguments from a param file")

    missing_script = expect_deny(
        safe_document(process_arguments=[SIGN_SCRIPT]),
        flags,
        "ProcessAndSign script with no template body",
    )
    if not any("script contents are not in the graph" in reason for reason in missing_script):
        fail("missing script body was not named: %s" % missing_script)

    hardcoded = expect_deny(
        HARDCODED_GRAPH, flags, "hardcoded codesign with empty signing substitution and no should_sign")
    if not any("template body contains /usr/bin/codesign" in reason for reason in hardcoded):
        fail("hardcoded template codesign was not named: %s" % hardcoded)
    expect_deny(
        safe_document(process_text=HARDCODED_TEMPLATE, include_process_template=True),
        flags,
        "hardcoded codesign while ProcessAndSign is only cp -p",
    )
    expect_allow(
        safe_document(omit_keys=("%signing_command_lines%",), include_process_template=True),
        flags,
        "empty signing substitution omitted by the json printer",
    )
    expect_deny(
        safe_document(omit_keys=("%output_path%",), include_process_template=True),
        flags,
        "a required template placeholder is absent",
    )
    omitted_hardcoded = expect_deny(
        safe_document(
            process_text=HARDCODED_TEMPLATE,
            omit_keys=("%signing_command_lines%",),
            process_arguments=[SIGN_SCRIPT],
            include_process_template=True,
        ),
        flags,
        "hardcoded codesign when the empty signing substitution is omitted",
    )
    if not any("template body contains /usr/bin/codesign" in reason for reason in omitted_hardcoded):
        fail("omitted substitution hid hardcoded codesign: %s" % omitted_hardcoded)
    expect_deny("", flags, "empty graph")
    expect_deny("{", flags, "truncated jsonproto")
    expect_deny(
        safe_document(artifact_path="bazel-out/ios_sim_arm64-dbg/bin/missing-runner.sh"),
        flags,
        "derived template whose body is not in the graph",
    )
    expect_deny(
        safe_document(include_dossier_write=False),
        flags,
        "dossier @file with no contents",
    )
    expect_deny(
        safe_document(process_arguments=[SIGN_SCRIPT, "should_sign"], include_process_template=True),
        flags,
        "should_sign argument",
    )
    expect_deny(
        safe_document(dossier_text="\n".join(DOSSIER_LINES[:-1] + ["Apple Development: Example"])),
        flags,
        "non-adhoc dossier identity",
    )
    expect_deny(
        safe_document(
            include_dossier_write=False,
            dossier_params=DOSSIER_LINES + ["--provisioning_profile", "bazel-out/app.mobileprovision"],
        ),
        flags,
        "param file provisioning profile",
    )
    expect_deny(SAFE_GRAPH, [flag for flag in flags if flag != proof_bazel.FEATURE], "missing feature")
    expect_deny(
        SAFE_GRAPH,
        [flag for flag in flags if flag != "--output=jsonproto"],
        "text output requested instead of jsonproto",
    )
    device = [flag for flag in flags if not flag.startswith("--ios_multi_cpus=")]
    device.append("--ios_multi_cpus=arm64")
    expect_deny(SAFE_GRAPH, device, "device cpu")


class Completed(object):
    def __init__(self, code, out, err=""):
        self.returncode = code
        self.stdout = out
        self.stderr = err


def test_wrapper_order(make_argv, real):
    calls = []

    def run(argv, check=False, stdout=None, stderr=None, text=False):
        calls.append(list(argv))
        if "should-fail-aquery" in argv:
            return Completed(2, "", "aquery exploded")
        if "--deny-script" in argv:
            return Completed(0, HIDDEN_SCRIPT, "")
        return Completed(0, SAFE_GRAPH, "")

    executed = []

    def execv(path, argv):
        if not calls:
            fail("build executed before aquery")
        executed.append(list(argv))

    code = proof_bazel.wrapper_main(make_argv, real, run=run, execv=execv)
    if code != 0 or len(calls) != 1 or len(executed) != 1:
        fail("safe graph did not aquery then exec: code=%s calls=%s exec=%s" % (code, calls, executed))
    query = calls[0]
    if query[0] != real or "aquery" not in query or proof_bazel.FEATURE not in query:
        fail("aquery argv lost the real binary or the feature: %s" % query)
    if "--subcommands" in query:
        fail("aquery kept the execution-only --subcommands flag")
    expression = " ".join(query)
    if expression.count("mnemonic(") != 1 or " union " in expression:
        fail("aquery filter must be one mnemonic(), not a union Bazel 9.2 drops: %s" % query)
    if "deps(%s)" % TARGET not in expression:
        fail("aquery does not include dependency actions: %s" % query)
    for name in ("SignBinary", "ProcessAndSign", "GenerateCodesigningDossier", "TemplateExpand", "FileWrite"):
        if name not in expression:
            fail("aquery filter missing %s: %s" % (name, query))
    for option in ("--output=jsonproto", "--include_file_write_contents", "--include_param_files", "--include_commandline"):
        if option not in query:
            fail("aquery argv missing %s: %s" % (option, query))
    built = executed[0]
    if built[0] != real or proof_bazel.FEATURE not in built or TARGET not in built:
        fail("executed argv is not the real binary with the feature and target: %s" % built)
    if "build" not in built:
        fail("executed argv dropped the build command: %s" % built)
    calls[:] = []
    executed[:] = []
    denied = proof_bazel.wrapper_main(
        make_argv + ["--deny-script"], real, run=run, execv=execv)
    if denied == 0 or executed:
        fail("signing script was executed: %s %s" % (denied, executed))

    calls[:] = []
    executed[:] = []
    failed = proof_bazel.wrapper_main(
        make_argv + ["should-fail-aquery"], real, run=run, execv=execv)
    if failed == 0 or executed:
        fail("aquery failure still executed the build")


def write_real_bazel(path, version):
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("#!/bin/bash\n")
        handle.write('if [[ "$1" == "--version" ]]; then echo "bazel %s"; exit 0; fi\n' % version)
        handle.write('echo "real bazel must not run during the simulation: $*" >&2\n')
        handle.write("exit 9\n")
    os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)


def run_make(repo, cwd, argv, locate):
    import BuildEnvironment
    import Make

    os.chdir(cwd)
    with open(os.path.join(repo, "versions.json"), encoding="utf-8") as handle:
        versions = json.load(handle)

    def xcode_version():
        return versions["xcode"]

    BuildEnvironment.get_xcode_version = xcode_version
    recorded = []

    def fake_call(arguments, use_clean_environment=True, check_result=True):
        recorded.append(list(arguments))
        return 0

    Make.call_executable = fake_call
    Make.PostboxImportCheck.run = lambda path: 0
    Make.IconSizeCheck.run = lambda path: 0
    Make.ChatListSwipeCheck.run = lambda path: 0
    Make.locate_bazel = locate
    previous = sys.argv
    sys.argv = argv
    try:
        tail = open(Make.__file__, encoding="utf-8").read().split("if __name__ == '__main__':", 1)[1]
        exec(textwrap.dedent(tail), Make.__dict__)
    finally:
        sys.argv = previous
    return recorded


def test_make_lookup():
    import BazelLocation
    from BuildEnvironment import BuildEnvironmentVersions, is_apple_silicon

    version = json.load(open(os.path.join(ROOT, "versions.json"), encoding="utf-8"))["bazel"].split(":", 1)[0]
    temp = tempfile.mkdtemp(prefix="tellomi-proof-argv-")
    previous = os.getcwd()
    try:
        real = os.path.join(temp, "bazel-real")
        wrapper = os.path.join(temp, "tellomi-proof-bazel")
        write_real_bazel(real, version)
        proof_bazel.install(wrapper, real, os.path.dirname(__file__))
        if "/build-input/bazel-" in wrapper:
            fail("wrapper was installed on the locate_bazel path")

        shutil.copy(os.path.join(ROOT, "versions.json"), os.path.join(temp, "versions.json"))
        locate_calls = []

        def refuse_locate(**kwargs):
            locate_calls.append(kwargs)
            raise AssertionError("locate_bazel ran")

        make_argv = run_make(ROOT, temp, [
            "Make.py",
            "--bazel", wrapper,
            "--bazelUserRoot", os.path.join(temp, "user-root"),
            "build",
            "--configurationPath", os.path.join(ROOT, "build-system", "appstore-configuration.json"),
            "--xcodeManagedCodesigning",
            "--disableProvisioningProfiles",
            "--configuration", "debug_sim_arm64",
            "--buildNumber", "1",
            "--showActions",
            "--target", TARGET,
        ], refuse_locate)
        if locate_calls:
            fail("explicit --bazel still called locate_bazel")
        if len(make_argv) != 1:
            fail("Make.py build did not invoke bazel once: %s" % make_argv)
        invoked = make_argv[0]
        if invoked[0] != wrapper:
            fail("Make.py argv[0] is %s, not the --bazel path" % invoked[0])
        if proof_bazel.FEATURE in invoked:
            fail("Make.py itself added the feature; the test would no longer prove the wrapper")
        for required in (
            "build",
            TARGET,
            "--ios_multi_cpus=sim_arm64",
            "--//Telegram:disableProvisioningProfiles",
            "--subcommands",
            "--define=buildNumber=1",
        ):
            if required not in invoked:
                fail("Make.py build argv missing %s: %s" % (required, invoked))
        print("Make.py argv0=%s" % invoked[0])
        print("Make.py feature_in_argv=%s" % (proof_bazel.FEATURE in invoked))
        test_wrapper_order(invoked, real)

        # The previous design: replace build-input/bazel-* and do not pass --bazel.
        # locate_bazel hashes that path and deletes the mismatch.
        os.chdir(temp)
        versions = BuildEnvironmentVersions(base_path=temp)
        arch = "darwin-arm64" if is_apple_silicon() else "darwin-x86_64"
        pinned_name = "bazel-%s-%s" % (versions.bazel_version, arch)
        pinned = os.path.join(temp, "build-input", pinned_name)
        os.makedirs(os.path.dirname(pinned), exist_ok=True)
        with open(pinned, "w", encoding="utf-8") as handle:
            handle.write("#!/bin/bash\necho wrapper\n")
        curls = []

        def fake_curl(arguments, use_clean_environment=True, check_result=True):
            curls.append(list(arguments))
            return 0

        BazelLocation.call_executable = fake_curl
        try:
            BazelLocation.locate_bazel(base_path=temp, cache_host_or_path=None, cache_dir=None)
        except OSError:
            pass
        if os.path.exists(pinned):
            fail("locate_bazel left the mismatched wrapper at %s" % pinned)
        if not curls or "releases/download" not in " ".join(curls[0]):
            fail("locate_bazel did not replace the wrapper with the release binary: %s" % curls)
        print("locate_bazel deleted %s and requested %s" % (pinned_name, curls[0][2]))

        # Without --bazel, Make.py's own branch calls locate_bazel.
        os.chdir(temp)
        called = []

        def record_locate(**kwargs):
            called.append(kwargs)
            return real

        run_make(ROOT, temp, [
            "Make.py",
            "--bazelUserRoot", os.path.join(temp, "user-root"),
            "build",
            "--configurationPath", os.path.join(ROOT, "build-system", "appstore-configuration.json"),
            "--xcodeManagedCodesigning",
            "--disableProvisioningProfiles",
            "--configuration", "debug_sim_arm64",
            "--buildNumber", "1",
            "--target", TARGET,
        ], record_locate)
        if not called:
            fail("omitting --bazel did not call locate_bazel")
        print("omit --bazel calls locate_bazel: yes")
    finally:
        os.chdir(previous)
        shutil.rmtree(temp)


def push_patterns(workflow_text):
    patterns = []
    in_push = False
    in_ignore = False
    for line in workflow_text.splitlines():
        if line.startswith("  push:"):
            in_push = True
            in_ignore = False
            continue
        if in_push and line.startswith("  ") and not line.startswith("    ") and line.strip().endswith(":"):
            break
        if in_push and line.strip() == "paths-ignore:":
            in_ignore = True
            continue
        if in_ignore:
            stripped = line.strip()
            if stripped.startswith("- "):
                value = stripped[2:].strip().strip("'").strip('"')
                patterns.append(value)
                continue
            if stripped:
                break
    return patterns


def changed_files():
    import subprocess
    base = subprocess.check_output(
        ["git", "merge-base", "origin/master", "HEAD"], cwd=ROOT, text=True).strip()
    diff = subprocess.check_output(
        ["git", "diff", "--name-only", base], cwd=ROOT, text=True).splitlines()
    status = subprocess.check_output(
        ["git", "status", "--porcelain"], cwd=ROOT, text=True).splitlines()
    files = set(diff)
    for line in status:
        path = line[3:].strip()
        if " -> " in path:
            path = path.split(" -> ", 1)[1]
        files.add(path)
    return sorted(path for path in files if path)


def test_first_merge_does_not_run_old_ci():
    files = changed_files()
    outside = [path for path in files if not path.startswith(".github/")]
    if outside:
        fail("diff is not limited to .github: %s" % outside)
    if not files:
        fail("no files in the proof diff")
    build_text = open(os.path.join(ROOT, ".github", "workflows", "build.yml"), encoding="utf-8").read()
    proof_text = open(os.path.join(ROOT, ".github", "workflows", "proof-compile.yml"), encoding="utf-8").read()
    build_patterns = push_patterns(build_text)
    proof_patterns = push_patterns(proof_text)
    if build_patterns != [".github/**"] or proof_patterns != [".github/**"]:
        fail("paths-ignore is %s and %s" % (build_patterns, proof_patterns))
    if ci_gate.push_triggers(files, build_patterns):
        fail("this .github-only diff would start CI")
    if ci_gate.push_triggers(files, proof_patterns):
        fail("this .github-only diff would start Proof compile")
    source = files + ["submodules/TelegramUI/Components/Tellomi/FeedScreen/BUILD"]
    if not ci_gate.push_triggers(source, build_patterns):
        fail("a source push was treated as ignored")
    if ci_gate.package_job_runs("push", None):
        fail("a source push would package")
    if ci_gate.release_publishes("push", None, "refs/heads/master"):
        fail("a source push would publish")
    if ci_gate.release_publishes("workflow_dispatch", False, "refs/heads/master"):
        fail("dispatch without package_release would publish")
    if not ci_gate.release_publishes("workflow_dispatch", True, "refs/heads/master"):
        fail("explicit package dispatch would not publish")
    if "contents: write" not in build_text:
        fail("CI contents permission changed")
    if "inputs.package_release" not in build_text or "default: false" not in build_text:
        fail("package_release is not an explicit default-off input")
    flight = os.path.join(ROOT, ".github", "workflows", "testflight.yml")
    if flight.replace(ROOT + "/", "") in files or ".github/workflows/testflight.yml" in files:
        fail("TestFlight workflow is in the diff")
    print("first-merge files:")
    for path in files:
        print("  %s" % path)
    print("CI push triggers for this diff: no")
    print("Proof compile push triggers for this diff: no")
    print("source push packages or publishes: no")


def _load_fixture(name):
    path = os.path.join(FIXTURE_DIR, name)
    return json.load(open(path, encoding="utf-8"))


def _append_filewrite(document, path, source_action):
    """Add a FileWrite whose content keys are exactly those Bazel emitted."""
    parsed = json.loads(document)
    used = [artifact["id"] for artifact in parsed["artifacts"]]
    used.extend(fragment["id"] for fragment in parsed["pathFragments"])
    identifier = max(used) + 1
    parent = None
    built = ""
    for part in path.split("/"):
        built = part if not built else built + "/" + part
        identifier += 1
        entry = {"id": identifier, "label": part}
        if parent is not None:
            entry["parentId"] = parent
        parsed["pathFragments"].append(entry)
        parent = identifier
    artifact_id = identifier + 1
    parsed["artifacts"].append({"id": artifact_id, "pathFragmentId": parent})
    action = {
        "mnemonic": source_action["mnemonic"],
        "targetId": 1,
        "outputIds": [artifact_id],
        "primaryOutputId": artifact_id,
    }
    if "fileContents" in source_action:
        action["fileContents"] = source_action["fileContents"]
    if "isExecutable" in source_action:
        action["isExecutable"] = source_action["isExecutable"]
    parsed["actions"].append(action)
    return json.dumps(parsed)


def test_real_bazel_filewrite_json():
    """Bazel 9.2.0 aquery of actions.write('', 'hello', ' ', executable '')."""
    flagged = _load_fixture("bazel-9.2.0-filewrite.json")
    plain = _load_fixture("bazel-9.2.0-filewrite-noflag.json")
    if [action.get("mnemonic") for action in flagged["actions"]] != ["FileWrite"] * 4:
        fail("flagged fixture is not the four FileWrite actions")
    empty, hello, space, executable = flagged["actions"]
    if "fileContents" in empty or "isExecutable" in empty:
        fail("actions.write('') kept a json field: %s" % sorted(empty))
    if hello.get("fileContents") != "hello" or "isExecutable" in hello:
        fail("actions.write('hello') was not kept verbatim: %s" % hello.get("fileContents"))
    if space.get("fileContents") != " ":
        fail("a single space was treated as the proto default")
    if "fileContents" in executable or executable.get("isExecutable") is not True:
        fail("executable empty write was not isExecutable without fileContents")
    hello_without_flag = plain["actions"][1]
    if "fileContents" in hello_without_flag:
        fail("jsonproto kept fileContents when the flag was off")

    flags = flags_of()
    omitted = _append_filewrite(
        SAFE_GRAPH,
        "bazel-out/k8-fastbuild/bin/out.empty",
        empty,
    )
    expect_allow(omitted, flags, "unreferenced FileWrite whose empty body jsonproto omits")
    visible = _append_filewrite(
        SAFE_GRAPH,
        "bazel-out/k8-fastbuild/bin/out.txt",
        hello,
    )
    expect_allow(visible, flags, "unreferenced FileWrite with the real hello body")
    signing = dict(hello)
    signing["fileContents"] = "/usr/bin/codesign"
    expect_deny(
        _append_filewrite(SAFE_GRAPH, "bazel-out/k8-fastbuild/bin/out.txt", signing),
        flags,
        "visible FileWrite body that signs",
    )
    dossier = _append_filewrite(
        safe_document(include_dossier_write=False),
        DOSSIER_PATH,
        empty,
    )
    dossier_reasons = expect_deny(dossier, flags, "dossier @file whose FileWrite body was omitted")
    if not any("dossier_arguments contents are not in the graph" in reason for reason in dossier_reasons):
        fail("omitted dossier body was allowed: %s" % dossier_reasons)
    script = _append_filewrite(
        safe_document(process_arguments=[SIGN_SCRIPT]),
        SIGN_SCRIPT,
        empty,
    )
    script_reasons = expect_deny(script, flags, "ProcessAndSign script whose FileWrite body was omitted")
    if not any("script contents are not in the graph" in reason for reason in script_reasons):
        fail("omitted script body was allowed: %s" % script_reasons)
    # A literal empty string is not the omitted default, and it is still no body.
    blank = json.loads(_append_filewrite(
        safe_document(process_arguments=[SIGN_SCRIPT]),
        SIGN_SCRIPT,
        {"mnemonic": "FileWrite", "fileContents": ""},
    ))
    blank_reasons = expect_deny(json.dumps(blank), flags, "script FileWrite with an explicit empty string")
    if not any("script contents are not in the graph" in reason for reason in blank_reasons):
        fail("explicit empty script was allowed: %s" % blank_reasons)
    unknown = json.loads(SAFE_GRAPH)
    unknown["actions"].append({"mnemonic": "TestRunner", "targetId": 1, "outputIds": [], "arguments": []})
    unknown_reasons = expect_deny(json.dumps(unknown), flags, "unknown TestRunner")
    if not any(reason == "unknown action TestRunner" for reason in unknown_reasons):
        fail("unknown action was allowed: %s" % unknown_reasons)
    stripped = json.loads(SAFE_GRAPH)
    for action in stripped["actions"]:
        action.pop("fileContents", None)
    blind = expect_deny(
        json.dumps(stripped),
        [flag for flag in flags if flag != "--include_file_write_contents"],
        "file writes without the contents flag",
    )
    if not any(reason == "FileWrite fileContents is missing" for reason in blind):
        fail("flag-off FileWrite was not fail-closed: %s" % blind)
    if not any("not asked for --include_file_write_contents" in reason for reason in blind):
        fail("missing contents flag was not named: %s" % blind)
    print("bazel 9.2 filewrite json omission")


def main():
    test_graph_boundary()
    test_real_bazel_filewrite_json()
    test_make_lookup()
    test_first_merge_does_not_run_old_ci()
    print("proof_bazel tests passed")


if __name__ == "__main__":
    main()
