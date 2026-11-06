#!/usr/bin/env python3
"""Create the configuration repository Make.py writes, before any Bazel command.

MODULE.bazel pins build_configuration at ./build-input/configuration-repository.
That directory is not in git. Make.resolve_configuration creates it, writes
MODULE.bazel, variables.bzl and the provisioning package, and only build()
calls it. A bazel query before that call exits 37 because the local path
override does not exist. Query, aquery and build then have to see the same
repository this function writes; an empty directory is not that repository.
"""
import argparse
import os
import sys


class _Arguments(object):
    def __init__(self, configuration_path, bazel_user_root, override_xcode):
        self.configurationPath = configuration_path
        self.bazelUserRoot = bazel_user_root
        self.overrideBazelVersion = False
        self.overrideXcodeVersion = override_xcode
        self.xcodeManagedCodesigning = True
        self.disableProvisioningProfiles = True
        self.gitCodesigningRepository = None
        self.codesigningInformationPath = None
        self.gitCodesigningType = None
        self.gitCodesigningUseCurrent = False


def configuration_root(repo):
    return os.path.join(repo, "build-input", "configuration-repository")


def is_make_configuration(path):
    """True only for the files resolve_configuration actually writes."""
    module_path = os.path.join(path, "MODULE.bazel")
    variables_path = os.path.join(path, "variables.bzl")
    provisioning_build = os.path.join(path, "provisioning", "BUILD")
    if not all(os.path.isfile(candidate) for candidate in (module_path, variables_path, provisioning_build)):
        return False
    with open(module_path, encoding="utf-8") as handle:
        module = handle.read()
    with open(variables_path, encoding="utf-8") as handle:
        variables = handle.read()
    with open(provisioning_build, encoding="utf-8") as handle:
        provisioning = handle.read()
    if module != 'module(\n    name = "build_configuration",\n)\n':
        return False
    if 'telegram_bundle_id = "app.tellomi.chat"' not in variables:
        return False
    if "telegram_bazel_path = " not in variables:
        return False
    if provisioning != "exports_files([\n])\n":
        return False
    return True


def configure(repo, bazel, configuration_path, bazel_user_root, override_xcode=False):
    """Call Make.resolve_configuration. Does not build or sign."""
    make_dir = os.path.join(repo, "build-system", "Make")
    if make_dir not in sys.path:
        sys.path.insert(0, make_dir)
    import Make

    previous = os.getcwd()
    os.chdir(repo)
    try:
        arguments = _Arguments(configuration_path, bazel_user_root, override_xcode)
        command = Make.BazelCommandLine(
            bazel=bazel,
            override_bazel_version=arguments.overrideBazelVersion,
            override_xcode_version=arguments.overrideXcodeVersion,
            bazel_user_root=arguments.bazelUserRoot,
        )
        Make.resolve_configuration(
            base_path=repo,
            bazel_command_line=command,
            arguments=arguments,
            additional_codesigning_output_path=None,
        )
    finally:
        os.chdir(previous)
    root = configuration_root(repo)
    if not is_make_configuration(root):
        raise RuntimeError("resolve_configuration did not write the configuration repository")
    return root


def mismatch_enabled(raw_event_input, typed_input):
    """How the workflow decides ALLOW_XCODE_MISMATCH.

    github.event.inputs values are strings. The string "false" is truthy in
    ``value && 'true'``, so a default-off boolean dispatch still set the
    variable. The typed inputs context compares with true.
    """
    del raw_event_input
    return typed_input is True


def main(argv):
    parser = argparse.ArgumentParser(prog="proof_configure")
    parser.add_argument("--bazel", required=True)
    parser.add_argument("--configuration", required=True)
    parser.add_argument("--bazel-user-root", required=True)
    parser.add_argument("--override-xcode", action="store_true")
    parser.add_argument("--repo", default=".")
    args = parser.parse_args(argv)
    root = configure(
        repo=os.path.abspath(args.repo),
        bazel=os.path.abspath(args.bazel),
        configuration_path=args.configuration,
        bazel_user_root=args.bazel_user_root,
        override_xcode=args.override_xcode,
    )
    print("configuration repository %s" % root)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
