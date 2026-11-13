#!/usr/bin/env python3
"""Run the proof workflow's configure and compile shells on Bash 3.2.

macOS runners execute workflow steps with /bin/bash, which is Bash 3.2.
set -u makes "${empty[@]}" an unbound variable. Run 42270455404 died on that
line before proof_configure.py started. This test extracts those command
blocks from the workflow YAML and runs them on Bash 3.2, with python3 stubbed
so Make.py is not built. Both the default (no Xcode override) and the explicit
override paths must keep every required argument and add no empty one.
"""
import os
import stat
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
WORKFLOW = os.path.join(ROOT, ".github", "workflows", "proof-compile.yml")
CONFIGURE_STEP = "Write the configuration repository Make.py uses"
COMPILE_STEP = "Compile FeedScreen via the iOS unit test"


def fail(message):
    sys.stderr.write("proof_bash32_test: %s\n" % message)
    sys.exit(1)


def bash32():
    chosen = os.environ.get("BASH32", "")
    if chosen and os.access(chosen, os.X_OK):
        return chosen
    system = "/bin/bash"
    if os.access(system, os.X_OK):
        version = subprocess.check_output([system, "--version"], text=True)
        if "version 3.2" in version.splitlines()[0]:
            return system
    fail("Bash 3.2 is required (set BASH32). This host's bash does not reproduce the runner.")


def version_line(shell):
    return subprocess.check_output([shell, "--version"], text=True).splitlines()[0]


def reproduces_unbound(shell):
    script = 'set -u\noverride=()\necho "${override[@]}"\n'
    result = subprocess.run([shell, "-e", "-c", script], capture_output=True, text=True)
    return result.returncode != 0 and "unbound variable" in result.stderr


def extract_run(text, step_name):
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if line.strip() != "- name: %s" % step_name:
            continue
        for cursor in range(index + 1, min(index + 20, len(lines))):
            if lines[cursor].strip() != "run: |":
                continue
            if cursor + 1 >= len(lines):
                break
            indent = len(lines[cursor + 1]) - len(lines[cursor + 1].lstrip(" "))
            body = []
            for raw in lines[cursor + 1:]:
                if raw.strip() == "":
                    body.append("")
                    continue
                width = len(raw) - len(raw.lstrip(" "))
                if width < indent:
                    break
                body.append(raw[indent:])
            return "\n".join(body).rstrip() + "\n"
    fail("workflow has no run block for %s" % step_name)


def run_blocks(workflow_text):
    blocks = []
    lines = workflow_text.splitlines()
    index = 0
    while index < len(lines):
        if lines[index].strip() != "run: |":
            index += 1
            continue
        indent = len(lines[index + 1]) - len(lines[index + 1].lstrip(" "))
        body = []
        index += 1
        while index < len(lines):
            raw = lines[index]
            if raw.strip() == "":
                body.append("")
                index += 1
                continue
            width = len(raw) - len(raw.lstrip(" "))
            if width < indent:
                break
            body.append(raw[indent:])
            index += 1
        blocks.append("\n".join(body))
    return blocks


def unguarded_empty_arrays(body):
    """name=() later expanded as \"${name[@]}\" without a length guard."""
    found = []
    for line in body.splitlines():
        stripped = line.strip()
        if not stripped.endswith("=()") or "=" not in stripped:
            continue
        name = stripped.split("=", 1)[0].strip().lstrip("local ").strip()
        if not name.isidentifier():
            continue
        expansion = '"${%s[@]}"' % name
        if expansion not in body:
            continue
        guard = "${#%s[@]}" % name
        if guard not in body:
            found.append(name)
    return found


def argv_records(path):
    records = []
    with open(path, "rb") as handle:
        for line in handle.read().split(b"\n"):
            if not line:
                continue
            records.append([part.decode("utf-8") for part in line.split(b"\t")])
    return records


def assert_no_empty(argv, label):
    if any(item == "" for item in argv):
        fail("%s passed an empty argument: %s" % (label, argv))


def assert_once(argv, flag, label):
    if argv.count(flag) != 1:
        fail("%s expected one %s, got %s" % (label, flag, argv))


def assert_absent(argv, flag, label):
    if flag in argv:
        fail("%s included %s: %s" % (label, flag, argv))


def prepare_workspace(root, stub_log):
    src = os.path.join(root, "src")
    tools = os.path.join(root, "proof-tools", ".github")
    stub = os.path.join(root, "stub")
    os.makedirs(src)
    os.makedirs(tools)
    os.makedirs(stub)
    guard_src = os.path.join(ROOT, ".github", "proof-compile-guard.sh")
    with open(guard_src, encoding="utf-8") as handle:
        guard = handle.read()
    with open(os.path.join(tools, "proof-compile-guard.sh"), "w", encoding="utf-8") as handle:
        handle.write(guard)
    os.chmod(os.path.join(tools, "proof-compile-guard.sh"), 0o755)
    stub_py = os.path.join(stub, "python3")
    with open(stub_py, "w", encoding="utf-8") as handle:
        handle.write("""#!/bin/bash
out="$STUB_ARGV"
joined="$*"
{
  first=1
  for arg in "$@"; do
    if [[ "$first" -eq 1 ]]; then
      printf '%s' "$arg"
      first=0
    else
      printf '\\t%s' "$arg"
    fi
  done
  printf '\\n'
} >> "$out"
if [[ "$joined" == *proof_configure.py* ]]; then
  mkdir -p build-input/configuration-repository
  printf 'module\\n' > build-input/configuration-repository/MODULE.bazel
  printf 'variables\\n' > build-input/configuration-repository/variables.bzl
fi
if [[ "$joined" == *Make.py* ]]; then
  printf 'swiftc -sdk iPhoneSimulator.sdk FeedScreen\\n'
fi
exit 0
""")
    os.chmod(stub_py, os.stat(stub_py).st_mode | stat.S_IXUSR)
    return src, stub


def execute(shell, script, env, cwd):
    result = subprocess.run(
        [shell, "-e", "-c", script],
        cwd=cwd,
        env=env,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        fail("shell exited %s\nstdout:\n%s\nstderr:\n%s" % (
            result.returncode, result.stdout, result.stderr))
    return result


def run_case(shell, script, override, stub_name):
    root = tempfile.mkdtemp(prefix="tellomi-bash32-")
    try:
        src, stub = prepare_workspace(root, stub_name)
        argv_path = os.path.join(root, "argv.txt")
        runner_temp = os.path.join(root, "runner-temp")
        os.makedirs(runner_temp)
        env = {
            "PATH": stub + ":/usr/bin:/bin",
            "HOME": root,
            "STUB_ARGV": argv_path,
            "RUNNER_TEMP": runner_temp,
            "BAZEL_BIN": os.path.join(runner_temp, "bazel-real"),
            "PROOF_BAZEL": os.path.join(runner_temp, "tellomi-proof-bazel"),
            "TMPDIR": root,
        }
        if override:
            env["MAKE_XCODE_FLAGS"] = "--overrideXcodeVersion"
        execute(shell, script, env, src)
        records = argv_records(argv_path)
        if len(records) != 1:
            fail("expected one python3 invocation, got %s" % records)
        return records[0]
    finally:
        import shutil
        shutil.rmtree(root)


def check_configure(argv, override):
    assert_no_empty(argv, "configure")
    script = "../proof-tools/.github/proof_configure.py"
    if argv[0] != script:
        fail("configure argv lost the script: %s" % argv)
    required = {
        "--bazel": None,
        "--configuration": "build-system/appstore-configuration.json",
        "--bazel-user-root": "/private/var/tmp/_bazel_proof",
    }
    if "--bazel" not in argv or argv[argv.index("--bazel") + 1].endswith("/tellomi-proof-bazel") is False:
        fail("configure dropped --bazel: %s" % argv)
    for flag, value in required.items():
        if flag not in argv:
            fail("configure dropped %s: %s" % (flag, argv))
        if value is not None and argv[argv.index(flag) + 1] != value:
            fail("configure changed %s: %s" % (flag, argv))
    if override:
        assert_once(argv, "--override-xcode", "configure")
    else:
        assert_absent(argv, "--override-xcode", "configure")


def check_compile(argv, override):
    assert_no_empty(argv, "compile")
    if argv[:2] != ["-u", "build-system/Make/Make.py"]:
        fail("compile dropped python -u Make.py: %s" % argv)
    tail = argv[2:]
    for flag in (
        "--bazel",
        "--xcodeManagedCodesigning",
        "--disableProvisioningProfiles",
        "--configuration=debug_sim_arm64",
        "--buildNumber=1",
        "--showActions",
        "--target=//Tests/TellomiFeedProof:TellomiFeedProofTests",
        "build",
    ):
        if flag not in tail:
            fail("compile dropped %s: %s" % (flag, tail))
    if not tail[tail.index("--bazel") + 1].endswith("/tellomi-proof-bazel"):
        fail("compile dropped the wrapper path: %s" % tail)
    user_root = "--bazelUserRoot=/private/var/tmp/_bazel_proof"
    if user_root not in tail:
        fail("compile dropped bazel user root: %s" % tail)
    build_at = tail.index("build")
    if override:
        if tail[build_at - 1] != "--overrideXcodeVersion":
            fail("override flag was not passed before build: %s" % tail)
        assert_once(tail, "--overrideXcodeVersion", "compile")
    else:
        assert_absent(tail, "--overrideXcodeVersion", "compile")


def main():
    shell = bash32()
    print(version_line(shell))
    if not reproduces_unbound(shell):
        fail("%s does not reproduce the Bash 3.2 empty-array failure" % shell)
    workflow = open(WORKFLOW, encoding="utf-8").read()
    if '"${override[@]}"' in workflow:
        fail("proof workflow still expands an array that is empty by default")
    for body in run_blocks(workflow):
        unsafe = unguarded_empty_arrays(body)
        if unsafe:
            fail("workflow run block expands an empty array under set -u: %s" % unsafe)
    others = [
        os.path.join(ROOT, ".github", "workflows", "build.yml"),
        os.path.join(ROOT, ".github", "workflows", "testflight.yml"),
    ]
    for path in others:
        for body in run_blocks(open(path, encoding="utf-8").read()):
            unsafe = unguarded_empty_arrays(body)
            if unsafe:
                fail("%s expands an empty array under set -u: %s" % (path, unsafe))
    configure = extract_run(workflow, CONFIGURE_STEP)
    compile_step = extract_run(workflow, COMPILE_STEP)
    for override, label in ((False, "default"), (True, "override")):
        configure_argv = run_case(shell, configure, override, "configure-" + label)
        check_configure(configure_argv, override)
        compile_argv = run_case(shell, compile_step, override, "compile-" + label)
        check_compile(compile_argv, override)
        print("%s path configure=%s" % (label, configure_argv))
        print("%s path compile=%s" % (label, compile_argv))
    submodule = open(os.path.join(ROOT, ".github", "checkout-submodules.sh"), encoding="utf-8").read()
    if '[[ ${#pids[@]} -gt 0 ]]' not in submodule or 'for pid in "${pids[@]}"' not in submodule:
        fail("submodule checkout no longer guards an empty pid list")
    guarded = subprocess.run(
        [shell, "-e", "-c", 'set -euo pipefail\npids=()\nif [[ ${#pids[@]} -gt 0 ]]; then\n  for pid in "${pids[@]}"; do wait "$pid"; done\nfi\necho ok\n'],
        capture_output=True, text=True)
    if guarded.returncode != 0 or guarded.stdout.strip() != "ok":
        fail("empty pid list still fails on Bash 3.2: %s" % guarded.stderr)
    print("empty submodule pid list: ok")
    print("proof bash 3.2 argv tests passed")


if __name__ == "__main__":
    main()
