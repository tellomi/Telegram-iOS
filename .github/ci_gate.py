"""GitHub push path filter and the CI package gate.

A push runs a workflow with paths-ignore only when at least one changed file
matches none of the patterns. A push that only touches .github matches
.github/** and does not start that workflow. workflow_dispatch ignores
paths-ignore. Packaging and the GitHub Release run only when that dispatch
sets package_release.
"""


def path_ignored(path, pattern):
    if pattern.endswith("/**"):
        root = pattern[:-3].rstrip("/")
        return path == root or path.startswith(root + "/")
    return path == pattern


def push_triggers(paths, patterns):
    """True when GitHub would start the workflow for this push diff."""
    if not paths:
        return True
    return any(not any(path_ignored(path, pattern) for pattern in patterns) for path in paths)


def package_job_runs(event_name, package_release):
    return event_name == "workflow_dispatch" and package_release is True


def release_publishes(event_name, package_release, ref):
    return package_job_runs(event_name, package_release) and ref == "refs/heads/master"
