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
SAFE_GRAPH = """
action 'Processing and signing TellomiFeedProofTests'
  Mnemonic: ProcessAndSign
  Target: %s
  Command Line: (exec /bin/bash -c 'cp -p bazel-out/ios_sim_arm64-dbg/bin/unprocessed_archive.zip bazel-out/ios_sim_arm64-dbg/bin/TellomiFeedProofTests.zip')

action 'Generating codesigning dossier for TellomiFeedProofTests'
  Mnemonic: GenerateCodesigningDossier
  Target: %s
  Command Line: (exec external/apple_support/dossier_codesigningtool create @bazel-out/ios_sim_arm64-dbg/bin/TellomiFeedProofTests-intermediates/dossier_arguments)
""" % (TARGET, TARGET)

HIDDEN_SCRIPT = """
action 'Processing and signing TellomiFeedProofTests'
  Mnemonic: ProcessAndSign
  Target: %s
  Command Line: (exec bazel-out/ios_sim_arm64-dbg/bin/process-and-sign-abc.sh should_sign)

action 'Generating codesigning dossier for TellomiFeedProofTests'
  Mnemonic: GenerateCodesigningDossier
  Target: %s
  Command Line: (exec external/apple_support/dossier_codesigningtool create @bazel-out/ios_sim_arm64-dbg/bin/dossier_arguments)
""" % (TARGET, TARGET)

MNEMONIC_ONLY = """
action 'Processing and signing TellomiFeedProofTests'
  Mnemonic: ProcessAndSign
  Target: %s
""" % TARGET

SIGN_BINARY = SAFE_GRAPH + """
action 'Signing binary'
  Mnemonic: SignBinary
  Target: %s
  Command Line: (exec /bin/bash -c 'cp in out')
""" % TARGET

DOSSIER_PROFILE = """
action 'Generating codesigning dossier for TellomiFeedProofTests'
  Mnemonic: GenerateCodesigningDossier
  Target: %s
  Command Line: (exec tool create @bazel-out/dossier_arguments --provisioning_profile bazel-out/app.mobileprovision)
""" % TARGET

DOSSIER_IDENTITY = """
action 'Generating codesigning dossier for TellomiFeedProofTests'
  Mnemonic: GenerateCodesigningDossier
  Target: %s
  Outputs: [bazel-out/TellomiFeedProofTests_dossier.zip]
  Command Line: (exec tool create @bazel-out/ios_sim_arm64-dbg/bin/dossier_arguments)

action 'Writing file bazel-out/ios_sim_arm64-dbg/bin/dossier_arguments'
  Mnemonic: FileWrite
  Outputs: [bazel-out/ios_sim_arm64-dbg/bin/dossier_arguments]
  Command Line: (exec /bin/bash -c 'printf --output\\n/tmp/out\\n--zip\\n--codesign_identity\\nApple Development: Example > bazel-out/dossier_arguments')
""" % TARGET

ADHOC_BODY = """
action 'Processing and signing TellomiFeedProofTests'
  Mnemonic: ProcessAndSign
  Command Line: (exec /bin/bash -c 'cp -p in.zip out.zip')

action 'Generating codesigning dossier for TellomiFeedProofTests'
  Mnemonic: GenerateCodesigningDossier
  Command Line: (exec tool create @bazel-out/ios_sim_arm64-dbg/bin/dossier_arguments)

action 'Writing file bazel-out/ios_sim_arm64-dbg/bin/dossier_arguments'
  Mnemonic: FileWrite
  Outputs: [bazel-out/ios_sim_arm64-dbg/bin/dossier_arguments]
  Command Line: (exec /bin/bash -c 'printf --output\\n/tmp/out\\n--zip\\n--codesign_identity\\n- > bazel-out/dossier_arguments')
"""

OPAQUE_BODY = ADHOC_BODY.replace(
    "printf --output\\n/tmp/out\\n--zip\\n--codesign_identity\\n- > bazel-out/dossier_arguments",
    "FileWrite",
)


def fail(message):
    sys.stderr.write("proof_bazel_test: %s\n" % message)
    sys.exit(1)


def flags_of(graph_ok=True):
    return [
        "--output=text",
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
    flags = flags_of()
    expect_allow(SAFE_GRAPH, flags, "empty ProcessAndSign plus args-file dossier")
    expect_allow(ADHOC_BODY, flags, "visible ad-hoc dossier body")
    expect_allow("", flags, "graph with no signing actions")

    hidden = expect_deny(HIDDEN_SCRIPT, flags, "generated signing script")
    if not any("should_sign" in reason for reason in hidden):
        fail("hidden script was not attributed to should_sign: %s" % hidden)
    if "/usr/bin/codesign" in HIDDEN_SCRIPT or "SignBinary" in HIDDEN_SCRIPT or ".mobileprovision" in HIDDEN_SCRIPT:
        fail("fixture was supposed to be invisible to the old log grep")

    expect_deny(MNEMONIC_ONLY, flags, "mnemonic without a command")
    expect_deny(SIGN_BINARY, flags, "SignBinary")
    expect_deny(DOSSIER_PROFILE, flags, "dossier provisioning profile")
    expect_deny(DOSSIER_IDENTITY, flags, "non-adhoc dossier identity")
    expect_deny(OPAQUE_BODY, flags, "dossier file present without contents")
    expect_deny(SAFE_GRAPH, [flag for flag in flags if flag != proof_bazel.FEATURE], "missing feature")
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
