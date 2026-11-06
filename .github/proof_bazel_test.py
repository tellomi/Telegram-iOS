#!/usr/bin/env python3
"""Simulate Make.py lookup and the proof Bazel argv, then the signing boundary."""
import json
import os
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
DOSSIER_PATH = "bazel-out/ios_sim_arm64-dbg/bin/TellomiFeedProofTests-intermediates/dossier_arguments"
# Literal from bazel 9.2 src/test/shell/integration/aquery_test.sh test_file_write.
# It is base64("hello world"), not a string this test invented.
OFFICIAL_HELLO_B64 = "aGVsbG8gd29ybGQ="
_SAFE_CHARS = set("@%-_+:,./")


def shell_escape(text):
    """Bazel 9.2 ShellEscaper.escapeString for ASCII arguments."""
    if text == "":
        return "''"
    if all(char.isascii() and (char.isalnum() or char in _SAFE_CHARS) for char in text):
        return text
    return "'" + text.replace("'", "'\\''") + "'"


def bazel92_command(argv):
    """CommandFailureUtils.describeCommand(COMPLETE, prettyPrintArgs=true)."""
    rendered = " \\\n    ".join(shell_escape(arg) for arg in argv)
    return (
        "(exec %s)\n"
        "# Configuration: cfg123\n"
        "# Execution platform: @@apple_support~//platforms:macos_arm64"
    ) % rendered


def command_field(argv):
    rendered = bazel92_command(argv)
    return "  Command Line: " + rendered + "\n"


def file_write_block(path, contents_b64):
    return (
        "action 'Writing file %s'\n"
        "  Mnemonic: FileWrite\n"
        "  Target: //pkg:bar\n"
        "  Outputs: [%s]\n"
        "  IsExecutable: false\n"
        "  FileWriteContents: [%s]\n"
    ) % (path, path, contents_b64)


DOSSIER_LINES = [
    "--output",
    "bazel-out/ios_sim_arm64-dbg/bin/TellomiFeedProofTests_dossier.zip",
    "--zip",
    "--codesign_identity",
    "-",
]
DOSSIER_TEXT = "\n".join(DOSSIER_LINES)
DOSSIER_B64 = __import__("base64").b64encode(DOSSIER_TEXT.encode("utf-8")).decode("ascii")
COPY_SCRIPT = (
    "cp -p 'bazel-out/ios_sim_arm64-dbg/bin/unprocessed_archive.zip' "
    "'bazel-out/ios_sim_arm64-dbg/bin/TellomiFeedProofTests.zip'"
)


def process_block(argv):
    return (
        "action 'Processing and signing TellomiFeedProofTests'\n"
        "  Mnemonic: ProcessAndSign\n"
        "  Target: %s\n"
        "  Outputs: [bazel-out/ios_sim_arm64-dbg/bin/TellomiFeedProofTests.zip]\n"
        "%s"
    ) % (TARGET, command_field(argv))


def dossier_block(argv, extra=""):
    return (
        "action 'Generating codesigning dossier for TellomiFeedProofTests'\n"
        "  Mnemonic: GenerateCodesigningDossier\n"
        "  Target: %s\n"
        "  Outputs: [bazel-out/ios_sim_arm64-dbg/bin/TellomiFeedProofTests_dossier.zip]\n"
        "%s"
        "%s"
    ) % (TARGET, command_field(argv), extra)


def graph(*blocks):
    return "\n\n".join(block.rstrip("\n") for block in blocks) + "\n"


SAFE_GRAPH = graph(
    process_block(["/bin/bash", "-c", COPY_SCRIPT]),
    dossier_block(["external/apple_support/bin/dossier_codesigningtool", "create", "@" + DOSSIER_PATH]),
    file_write_block(DOSSIER_PATH, DOSSIER_B64),
    file_write_block("bazel-out/k8-fastbuild/bin/pkg/bar.count", OFFICIAL_HELLO_B64),
)

PARAM_GRAPH = graph(
    process_block(["/bin/bash", "-c", COPY_SCRIPT]),
    dossier_block(
        ["external/apple_support/bin/dossier_codesigningtool", "create", "@" + DOSSIER_PATH],
        "  Params File Content (%s):\n    %s\n" % (DOSSIER_PATH, " \\\n    ".join(DOSSIER_LINES)),
    ),
)

HIDDEN_SCRIPT = graph(
    process_block([
        "bazel-out/ios_sim_arm64-dbg/bin/process-and-sign-abc.sh",
        "should_sign",
    ]),
    dossier_block(["external/apple_support/bin/dossier_codesigningtool", "create", "@" + DOSSIER_PATH]),
    file_write_block(DOSSIER_PATH, DOSSIER_B64),
)


def fail(message):
    sys.stderr.write("proof_bazel_test: %s\n" % message)
    sys.exit(1)


def flags_of():
    return [
        "--output=text",
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


def first_command_line(text):
    for line in text.splitlines():
        if line.startswith("  Command Line:"):
            return line
    return ""


def without_continuations(text):
    """What the previous one-line Command Line regex kept."""
    kept = []
    skipping = False
    for line in text.splitlines():
        if line.startswith("  Command Line:"):
            kept.append(line)
            skipping = True
            continue
        if skipping:
            if line.startswith("  ") and not line.startswith("    "):
                skipping = False
                kept.append(line)
            elif line.startswith("action "):
                skipping = False
                kept.append(line)
            continue
        kept.append(line)
    return "\n".join(kept) + "\n"


def test_graph_boundary():
    flags = flags_of()
    decoded, error = proof_bazel.decode_file_write_contents("[%s]" % OFFICIAL_HELLO_B64)
    if error or decoded != "hello world":
        fail("official FileWriteContents base64 did not decode to hello world: %s %s" % (decoded, error))
    bad, bad_error = proof_bazel.decode_file_write_contents("[aGVsbG8gd29ybGQ=")
    if bad is not None or bad_error != "truncated":
        fail("truncated FileWriteContents was accepted: %s %s" % (bad, bad_error))

    copy_args, copy_truncated = proof_bazel.split_pretty_command(
        bazel92_command(["/bin/bash", "-c", COPY_SCRIPT]))
    if copy_truncated or copy_args != ["/bin/bash", "-c", COPY_SCRIPT]:
        fail("multi-line cp command did not round-trip: %s truncated=%s" % (copy_args, copy_truncated))
    sign_args, sign_truncated = proof_bazel.split_pretty_command(bazel92_command([
        "bazel-out/ios_sim_arm64-dbg/bin/process-and-sign-abc.sh",
        "should_sign",
    ]))
    if sign_truncated or "should_sign" not in sign_args:
        fail("multi-line should_sign command was not recovered: %s" % sign_args)
    if "cp -p" in first_command_line(SAFE_GRAPH) or "should_sign" in first_command_line(HIDDEN_SCRIPT):
        fail("fixture first lines already contain the parameter; this would not catch the one-line parser")

    expect_allow(SAFE_GRAPH, flags, "multi-line cp plus base64 dossier file")
    expect_allow(PARAM_GRAPH, flags, "multi-line cp plus param file dossier")

    collapsed = without_continuations(SAFE_GRAPH)
    expect_deny(collapsed, flags, "command line reduced to its first line")
    expect_deny("", flags, "empty graph")
    expect_deny(SAFE_GRAPH.rstrip("\n"), flags, "output that does not end in a newline")

    missing_file = graph(
        process_block(["/bin/bash", "-c", COPY_SCRIPT]),
        dossier_block(["external/apple_support/bin/dossier_codesigningtool", "create", "@" + DOSSIER_PATH]),
    )
    expect_deny(missing_file, flags, "dossier @file with no FileWrite and no param file")

    opaque = graph(
        process_block(["/bin/bash", "-c", COPY_SCRIPT]),
        dossier_block(["external/apple_support/bin/dossier_codesigningtool", "create", "@" + DOSSIER_PATH]),
        "action 'Writing file %s'\n  Mnemonic: FileWrite\n  Outputs: [%s]\n  IsExecutable: false\n" % (
            DOSSIER_PATH, DOSSIER_PATH),
    )
    expect_deny(opaque, flags, "FileWrite without FileWriteContents")

    truncated_b64 = SAFE_GRAPH.replace(
        "FileWriteContents: [%s]" % DOSSIER_B64,
        "FileWriteContents: [%s" % DOSSIER_B64,
    )
    expect_deny(truncated_b64, flags, "FileWriteContents missing its closing bracket")

    cut = SAFE_GRAPH.replace(
        bazel92_command(["/bin/bash", "-c", COPY_SCRIPT]),
        "(exec /bin/bash \\\n    -c \\",
        1,
    )
    expect_deny(cut, flags, "command line cut off before its closing paren")

    hidden = expect_deny(HIDDEN_SCRIPT, flags, "should_sign on a continuation line")
    if not any("should_sign" in reason for reason in hidden):
        fail("continuation should_sign was not named: %s" % hidden)

    bad_identity = "\n".join(DOSSIER_LINES[:-1] + ["Apple Development: Example"])
    bad_b64 = __import__("base64").b64encode(bad_identity.encode("utf-8")).decode("ascii")
    expect_deny(SAFE_GRAPH.replace(DOSSIER_B64, bad_b64, 1), flags, "non-adhoc identity in FileWriteContents")

    profile_lines = DOSSIER_LINES + ["--provisioning_profile", "bazel-out/app.mobileprovision"]
    profile_graph = graph(
        process_block(["/bin/bash", "-c", COPY_SCRIPT]),
        dossier_block(
            ["external/apple_support/bin/dossier_codesigningtool", "create", "@" + DOSSIER_PATH],
            "  Params File Content (%s):\n    %s\n" % (DOSSIER_PATH, " \\\n    ".join(profile_lines)),
        ),
    )
    expect_deny(profile_graph, flags, "param file provisioning profile")

    author_single_line = (
        "action 'Processing and signing TellomiFeedProofTests'\n"
        "  Mnemonic: ProcessAndSign\n"
        "  Command Line: (exec /bin/bash -c 'cp -p in.zip out.zip')\n"
        "\n"
        "action 'Generating codesigning dossier for TellomiFeedProofTests'\n"
        "  Mnemonic: GenerateCodesigningDossier\n"
        "  Command Line: (exec tool create @%s)\n"
    ) % DOSSIER_PATH
    expect_deny(author_single_line, flags, "author single-line fixture with no file contents")

    expect_deny(SAFE_GRAPH, [flag for flag in flags if flag != proof_bazel.FEATURE], "missing feature")
    expect_deny(
        SAFE_GRAPH,
        [flag for flag in flags if flag != "--include_file_write_contents"],
        "file write contents not requested",
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
    if 'mnemonic("GenerateCodesigningDossier"' not in " ".join(query):
        fail("aquery does not include GenerateCodesigningDossier: %s" % query)
    if 'mnemonic("ProcessAndSign"' not in " ".join(query) or 'mnemonic("SignBinary"' not in " ".join(query):
        fail("aquery does not include the signing mnemonics: %s" % query)
    if 'mnemonic("FileWrite"' not in " ".join(query):
        fail("aquery does not include FileWrite: %s" % query)
    for option in ("--include_file_write_contents", "--include_param_files", "--include_commandline"):
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


def main():
    test_graph_boundary()
    test_make_lookup()
    test_first_merge_does_not_run_old_ci()
    print("proof_bazel tests passed")


if __name__ == "__main__":
    main()
