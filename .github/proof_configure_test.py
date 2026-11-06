#!/usr/bin/env python3
"""Clean checkout: configuration-repository is absent until Make writes it."""
import json
import os
import shutil
import stat
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(ROOT, "build-system", "Make"))

import proof_configure  # noqa: E402


def fail(message):
    sys.stderr.write("proof_configure_test: %s\n" % message)
    sys.exit(1)


def write_bazel(path, version):
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("#!/bin/bash\n")
        handle.write('if [[ "$1" == "--version" ]]; then echo "bazel %s"; exit 0; fi\n' % version)
        handle.write('echo "configure must not build: $*" >&2\n')
        handle.write("exit 9\n")
    os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)


def test_clean_checkout_has_no_configuration_repository():
    import BuildEnvironment

    version = json.load(open(os.path.join(ROOT, "versions.json"), encoding="utf-8"))
    temp = tempfile.mkdtemp(prefix="tellomi-proof-config-")
    try:
        shutil.copy(os.path.join(ROOT, "versions.json"), os.path.join(temp, "versions.json"))
        configuration = os.path.join(temp, "appstore-configuration.json")
        shutil.copy(os.path.join(ROOT, "build-system", "appstore-configuration.json"), configuration)
        bazel = os.path.join(temp, "bazel-real")
        write_bazel(bazel, version["bazel"].split(":", 1)[0])
        BuildEnvironment.get_xcode_version = lambda: version["xcode"]

        root = proof_configure.configuration_root(temp)
        if os.path.exists(root):
            fail("clean checkout already had a configuration repository")
        if proof_configure.is_make_configuration(root):
            fail("missing repository was treated as configured")

        os.makedirs(root)
        if proof_configure.is_make_configuration(root):
            fail("an empty directory was accepted as Make's configuration")
        with open(os.path.join(root, "MODULE.bazel"), "w", encoding="utf-8") as handle:
            handle.write("module(name = \"not_the_writer\")\n")
        if proof_configure.is_make_configuration(root):
            fail("a stand-in MODULE.bazel was accepted")
        shutil.rmtree(root)

        written = proof_configure.configure(
            repo=temp,
            bazel=bazel,
            configuration_path=configuration,
            bazel_user_root=os.path.join(temp, "user-root"),
            override_xcode=False,
        )
        if written != root or not proof_configure.is_make_configuration(root):
            fail("resolve_configuration did not produce the real repository")
        variables = open(os.path.join(root, "variables.bzl"), encoding="utf-8").read()
        if 'telegram_bazel_path = "%s"' % bazel not in variables:
            fail("variables.bzl does not record the bazel path configure was given")
        first = open(os.path.join(root, "variables.bzl"), "rb").read()
        proof_configure.configure(
            repo=temp,
            bazel=bazel,
            configuration_path=configuration,
            bazel_user_root=os.path.join(temp, "user-root"),
            override_xcode=False,
        )
        second = open(os.path.join(root, "variables.bzl"), "rb").read()
        if first != second:
            fail("a second resolve_configuration did not rewrite the same variables.bzl")
        print("clean checkout configuration repository: written by resolve_configuration")
    finally:
        shutil.rmtree(temp)


def test_mismatch_flag_defaults_off():
    workflow = open(
        os.path.join(ROOT, ".github", "workflows", "proof-compile.yml"), encoding="utf-8").read()
    if "github.event.inputs.allow_xcode_mismatch && 'true'" in workflow:
        fail("workflow still treats the string false as a mismatch override")
    if "inputs.allow_xcode_mismatch == true" not in workflow:
        fail("workflow does not compare the typed boolean")
    if proof_configure.mismatch_enabled("false", False):
        fail("default false dispatch would still allow an Xcode mismatch")
    if not proof_configure.mismatch_enabled("true", True):
        fail("an explicit mismatch opt-in was ignored")
    if proof_configure.mismatch_enabled("false", False) or proof_configure.mismatch_enabled(None, None):
        fail("push or omitted input would allow an Xcode mismatch")
    print("ALLOW_XCODE_MISMATCH default: false")


def main():
    test_clean_checkout_has_no_configuration_repository()
    test_mismatch_flag_defaults_off()
    print("proof_configure tests passed")


if __name__ == "__main__":
    main()
