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


SECRET = "sk_live_not_in_regex"
BOMB = "\n::add-mask::" + SECRET + "\r::error::" + SECRET + "\n::set-output::name=" + SECRET + "\x1b"


def assert_log_safe(text):
    if SECRET in text:
        fail("log contained the unknown token")
    if "\r" in text or "\x1b" in text:
        fail("log contained a raw control character")
    for line in text.splitlines():
        if line.lstrip().startswith("::"):
            fail("log line starts a workflow command: %s" % line)
    for command in ("::add-mask::", "::error::", "::set-output::"):
        if command in text:
            fail("workflow command text was copied: %s" % command)


def sample_document():
    return {
        "pathFragments": [
            {"id": 1, "label": "bazel-out"},
            {"id": 2, "label": "runner.sh", "parentId": 1},
            {"id": 3, "label": BOMB, "parentId": 1},
        ],
        "artifacts": [
            {"id": 10, "pathFragmentId": 2},
            {"id": 11, "pathFragmentId": 3},
        ],
        "targets": [{"id": 1, "label": "//Tests/TellomiFeedProof:TellomiFeedProofTests"},
                    {"id": 2, "label": BOMB}],
        "depSetOfFiles": [{"id": 1, "directArtifactIds": [10]}],
        "actions": [
            {
                "mnemonic": "TemplateExpand",
                "targetId": 1,
                "outputIds": [10],
                "templateContent": "#!/bin/bash\n" + SECRET + BOMB,
                "environmentVariables": [{"key": BOMB, "value": SECRET}],
                "executionInfo": {BOMB: SECRET},
                "paramFiles": [{
                    "execPath": "bazel-out/" + SECRET,
                    "arguments": ["--codesign_identity", "-", SECRET, BOMB],
                }],
            },
            {
                "mnemonic": BOMB,
                "targetId": 2,
                "outputIds": [11],
                "inputDepSetIds": [1],
                "templateContent": "ARTIFACT: bazel-out/runner.sh",
                "substitutions": [
                    {"key": "%(test_bundle_path)s", "value": SECRET + BOMB},
                    {"key": SECRET, "value": BOMB},
                    {"key": BOMB, "value": SECRET},
                ],
                "arguments": ["create", "should_sign", SECRET, BOMB],
                "fileContents": SECRET + BOMB,
            },
        ],
    }


def test_projection_fingerprints_unknown_text():
    projected = proof_bazel.project_aquery(json.dumps(sample_document()))
    assert_log_safe(projected)
    if "not a raw action graph" not in projected:
        fail("projection was presented as a raw graph")
    if '"text": "TemplateExpand"' not in projected:
        fail("public mnemonic was not kept")
    if '"text": "%(test_bundle_path)s"' not in projected:
        fail("public placeholder key was not kept")
    if '"text": "--codesign_identity"' not in projected or '"text": "-"' not in projected:
        fail("public dossier tokens were not kept")
    path_id = proof_bazel.fingerprint("bazel-out/runner.sh")["sha256"]
    if projected.count(path_id) < 2:
        fail("derived template was not tied to its producer fingerprint:\n%s" % projected)
    if '"contents": "omitted"' not in projected:
        fail("free-text contents were not omitted")
    if '"reason": "absent"' in projected:
        fail("producer that is in the document was reported absent")
    failure = proof_bazel.project_aquery_failure(SECRET + BOMB)
    assert_log_safe(failure)
    if "not a complete graph" not in failure or '"contents": "omitted"' not in failure:
        fail("failed aquery stderr was not reduced to a fingerprint")
    unparsed = proof_bazel.project_aquery("{" + SECRET)
    assert_log_safe(unparsed)
    if "not a complete graph" not in unparsed:
        fail("unparsed document was treated as a graph")


def _run(document, code, diagnose, err=""):
    calls = []

    def run(argv, check=False, stdout=None, stderr=None, text=False):
        calls.append(list(argv))
        if code != 0:
            return Completed(code, "", err or "aquery exploded")
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


def test_regex_shaped_secrets_stay_fingerprints():
    mnemonic = "GhpSupersecretvalue"
    label = "//pkg:ghp_supersecretvalue"
    key = "%ghp_supersecretvalue%"
    projected = proof_bazel.project_aquery(json.dumps({
        "pathFragments": [],
        "artifacts": [],
        "targets": [{"id": 1, "label": label}],
        "actions": [{
            "mnemonic": mnemonic,
            "targetId": 1,
            "outputIds": [],
            "substitutions": [{"key": key, "value": ""}],
        }],
    }))
    for secret in (mnemonic, label, key):
        if secret in projected:
            fail("regex-shaped secret was shown: %s" % secret)
    token = proof_bazel.project_token(mnemonic, "mnemonic")
    if token.get("shown") or token["sha256"] not in projected:
        fail("unknown mnemonic was not kept as a hash")
    reason = proof_bazel.log_reason("unknown action " + mnemonic)
    if mnemonic in reason or token["sha256"] not in reason:
        fail("default unknown reason leaked the mnemonic: %s" % reason)
    if proof_bazel.log_reason("unknown action TestRunner") != "signing-boundary: unknown action TestRunner":
        fail("known mnemonic reason was fingerprinted")
    print("regex-shaped secrets stayed fingerprints")


def test_diagnostics_never_executes():
    allowed = proof_bazel_test.SAFE_GRAPH
    refused = json.dumps(sample_document())
    for document, aquery_code, diagnose in (
        (allowed, 0, True),
        (refused, 0, True),
        (allowed, 3, True),
        (refused, 0, False),
    ):
        status, executed, log, calls = _run(document, aquery_code, diagnose, SECRET + BOMB)
        assert_log_safe(log)
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
    if "diagnostics-only" in log or log.startswith("diag ") or "\ndiag " in log:
        fail("default allow path logged a projection")
    status, executed, refused_log, _calls = _run(refused, 0, False)
    if executed or "diag " in refused_log:
        fail("default refusal logged a projection or executed: %s" % refused_log)
    if "signing-boundary:" not in refused_log:
        fail("default refusal dropped the existing gate reasons")
    status, executed, failed_log, _calls = _run(allowed, 3, False, SECRET + BOMB)
    assert_log_safe(failed_log)
    if executed or "diag " in failed_log:
        fail("default aquery failure logged stderr or executed")
    workflow = open(
        __import__("os").path.join(__import__("os").path.dirname(__file__), "workflows", "proof-compile.yml"),
        encoding="utf-8",
    ).read()
    if "inputs.diagnostics_only == true" not in workflow or "default: false" not in workflow:
        fail("diagnostics input is not default-off")
    print("diagnostics never execute a build; default allow path still would")


def main():
    test_projection_fingerprints_unknown_text()
    test_regex_shaped_secrets_stay_fingerprints()
    test_diagnostics_never_executes()
    print("proof diagnostics tests passed")


if __name__ == "__main__":
    main()
