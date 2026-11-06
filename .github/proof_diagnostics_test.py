#!/usr/bin/env python3
"""Diagnostics never execute a build, and the log projection stays redacted."""
import io
import json
import sys

sys.path.insert(0, __import__("os").path.dirname(__file__))

import proof_bazel  # noqa: E402
import proof_bazel_test  # noqa: E402


def fail(message):
    sys.stderr.write("proof_diagnostics_test: %s\n" % message)
    sys.exit(1)


class Completed(object):
    def __init__(self, code, out, err=""):
        self.returncode = code
        self.stdout = out
        self.stderr = err


def sample_document():
    secret = "ghp_supersecretvalue"
    return {
        "pathFragments": [
            {"id": 1, "label": "bazel-out"},
            {"id": 2, "label": "runner.sh", "parentId": 1},
            {"id": 3, "label": "TellomiFeedProofTests", "parentId": 1},
            {"id": 4, "label": "dossier_arguments", "parentId": 1},
            {"id": 5, "label": "Info.plist", "parentId": 1},
        ],
        "artifacts": [
            {"id": 10, "pathFragmentId": 2},
            {"id": 11, "pathFragmentId": 3},
            {"id": 12, "pathFragmentId": 4},
            {"id": 13, "pathFragmentId": 5},
        ],
        "targets": [{"id": 1, "label": "//Tests/TellomiFeedProof:TellomiFeedProofTests"}],
        "depSetOfFiles": [{"id": 1, "directArtifactIds": [10]}],
        "actions": [
            {
                "mnemonic": "TemplateExpand",
                "targetId": 1,
                "outputIds": [10],
                "templateContent": "#!/bin/bash\n\n# Copyright 2018 The Bazel Authors\n" + secret,
                "environmentVariables": [{"key": "GITHUB_TOKEN", "value": secret}],
                "executionInfo": {"no-sandbox": "1"},
            },
            {
                "mnemonic": "TemplateExpand",
                "targetId": 1,
                "outputIds": [11],
                "inputDepSetIds": [1],
                "templateContent": "ARTIFACT: bazel-out/runner.sh",
                "substitutions": [{"key": "%(test_bundle_path)s", "value": "/Users/runner/secret.mobileprovision"}],
                "arguments": ["--profile", "/Users/runner/secret.mobileprovision"],
            },
            {
                "mnemonic": "FileWrite",
                "targetId": 1,
                "outputIds": [12],
                "fileContents": "--output\nbazel-out/out.zip\n--zip\n--codesign_identity\n-\n",
            },
            {
                "mnemonic": "FileWrite",
                "targetId": 1,
                "outputIds": [13],
                "fileContents": "-----BEGIN PRIVATE KEY-----\n" + secret + "\n-----END PRIVATE KEY-----\n",
            },
            {
                "mnemonic": "TestRunner",
                "targetId": 1,
                "outputIds": [11],
                "arguments": ["run"],
            },
        ],
    }


def test_projection_is_redacted_and_links_producer():
    text = json.dumps(sample_document())
    projected = proof_bazel.project_aquery(text)
    if "ghp_supersecretvalue" in projected:
        fail("projection leaked a token")
    if "GITHUB_TOKEN" in projected or "BEGIN PRIVATE KEY" in projected:
        fail("projection leaked an environment value or private key")
    if "secret.mobileprovision" in projected:
        fail("projection leaked a provisioning path")
    if "environmentVariables: omitted (1)" not in projected:
        fail("environment variables were not omitted by count")
    if "executionInfo: omitted" not in projected:
        fail("execution info was logged")
    if "templateProducer: TemplateExpand bazel-out/runner.sh" not in projected:
        fail("derived template producer was not linked:\n%s" % projected)
    if "#!/bin/bash" not in projected or "# Copyright 2018 The Bazel Authors" not in projected:
        fail("runner template text was dropped")
    if "--codesign_identity" not in projected or "\n-" not in projected and "| -" not in projected:
        # dossier body is included; identity line is "-"
        if "--codesign_identity" not in projected:
            fail("dossier arguments were omitted")
    if "fileContents: omitted" not in projected:
        fail("arbitrary file contents were not omitted")
    if "not a raw action graph" not in projected:
        fail("projection was presented as a complete graph")
    if "TestRunner" not in projected or "TemplateExpand" not in projected:
        fail("mnemonics missing from projection")
    huge = json.dumps({
        "actions": [{
            "mnemonic": "TemplateExpand",
            "outputIds": [],
            "templateContent": "A" * 10000,
        }],
        "artifacts": [],
        "pathFragments": [],
    })
    huge_projected = proof_bazel.project_aquery(huge)
    if "truncated" not in huge_projected or "not a complete graph" not in huge_projected:
        fail("truncated template was presented as complete")
    if proof_bazel.project_aquery("{").count("not a complete graph") < 1:
        fail("unparsed document was treated as a graph")
    if "AAAA" in proof_bazel.project_aquery("{"):
        fail("unparsed document leaked raw text")


def _run(document, code, diagnose):
    calls = []

    def run(argv, check=False, stdout=None, stderr=None, text=False):
        calls.append(list(argv))
        if code != 0:
            return Completed(code, "", "aquery exploded")
        return Completed(0, document, "")

    executed = []

    def execv(path, argv):
        executed.append(list(argv))

    stderr = io.StringIO()
    previous = sys.stderr
    sys.stderr = stderr
    try:
        status = proof_bazel.wrapper_main(
            ["wrapper", "build", "//Tests/TellomiFeedProof:TellomiFeedProofTests", "--ios_multi_cpus=sim_arm64"],
            "/tmp/bazel-real",
            run=run,
            execv=execv,
            environ={"TELLOMI_PROOF_DIAGNOSTICS": "1" if diagnose else "0"},
        )
    finally:
        sys.stderr = previous
    return status, executed, stderr.getvalue(), calls


def test_diagnostics_never_executes():
    allowed = proof_bazel_test.SAFE_GRAPH
    refused = json.dumps(sample_document())
    for document, aquery_code, diagnose in (
        (allowed, 0, True),
        (refused, 0, True),
        (allowed, 3, True),
        (refused, 0, False),
    ):
        status, executed, log, calls = _run(document, aquery_code, diagnose)
        if executed:
            fail("build was executed diagnose=%s aquery=%s" % (diagnose, aquery_code))
        if not calls or calls[0][calls[0].index("aquery") + 1:].count("build"):
            pass
        if "aquery" not in calls[0]:
            fail("aquery was not requested")
        if diagnose and aquery_code == 0 and "diagnostics-only: build was not executed" not in log:
            fail("diagnostics mode did not record that the build was skipped")
        if aquery_code != 0 and "not a complete graph" not in log:
            fail("failed aquery was treated as a complete graph")
        if status == 0:
            fail("diagnostics or refusal returned success")
    status, executed, log, _calls = _run(allowed, 0, False)
    if status != 0 or not executed:
        fail("default allow path no longer builds: %s %s" % (status, executed))
    if "diagnostics-only" in log:
        fail("default path enabled diagnostics-only")
    workflow = open(
        __import__("os").path.join(__import__("os").path.dirname(__file__), "workflows", "proof-compile.yml"),
        encoding="utf-8",
    ).read()
    if "inputs.diagnostics_only == true" not in workflow or "default: false" not in workflow:
        fail("diagnostics input is not default-off")
    print("diagnostics never execute a build; default allow path still would")


def main():
    test_projection_is_redacted_and_links_producer()
    test_diagnostics_never_executes()
    print("proof diagnostics tests passed")


if __name__ == "__main__":
    main()
