#!/usr/bin/env python3
"""Print App Store and TestFlight version strings for app.tellomi.chat.

Uses the App Store Connect API key already used by TestFlight. Prints version
strings and states only.
"""

import os
import pathlib
import sys
import tempfile
import time
import urllib.parse

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from prepare_appstore_signing import ApiError, Client, make_jwt, require_env  # noqa: E402

BUNDLE_ID = "app.tellomi.chat"


def pages(client, path):
    for _page in range(30):
        payload = client.request("GET", path)
        for item in payload.get("data") or []:
            yield item
        next_link = ((payload.get("links") or {}).get("next")) or ""
        if not next_link.startswith("https://api.appstoreconnect.apple.com"):
            return
        path = next_link[len("https://api.appstoreconnect.apple.com"):]


def describe_build(item):
    attrs = item.get("attributes") or {}
    return "build {} {} uploaded {} expired {}".format(
        attrs.get("version") or "",
        attrs.get("processingState") or "",
        attrs.get("uploadedDate") or "",
        attrs.get("expired"),
    )


def find_build(client, app_id, version):
    query = urllib.parse.urlencode({
        "filter[app]": app_id,
        "filter[version]": version,
        "limit": 5,
        "fields[builds]": "version,processingState,uploadedDate,expired",
    })
    matches = list(pages(client, "/v1/builds?" + query))
    return matches[0] if matches else None


def list_groups(client, app_id):
    query = urllib.parse.urlencode({
        "limit": 50,
        "fields[betaGroups]": "name,isInternalGroup,publicLinkEnabled,hasAccessToAllBuilds",
    })
    return list(pages(client, "/v1/apps/{}/betaGroups?{}".format(app_id, query)))


def linked_group_names(client, build_id):
    query = urllib.parse.urlencode({
        "limit": 50,
        "fields[betaGroups]": "name,isInternalGroup,publicLinkEnabled,hasAccessToAllBuilds",
    })
    names = []
    for item in pages(client, "/v1/builds/{}/betaGroups?{}".format(build_id, query)):
        attrs = item.get("attributes") or {}
        names.append((attrs.get("name") or item["id"], attrs))
    return names


def safe_links(client, build_id):
    try:
        return linked_group_names(client, build_id)
    except ApiError as error:
        print("  groups unreadable: {}".format(error))
        return []


def report_build(client, app_id, version):
    """Read one TestFlight build and the groups it is in.

    A VALID build is added only to existing internal groups that do not have a
    public link. This does not create testers, send invitations, submit a
    review, or touch an external group.
    """
    print("build {} filter:".format(version))
    build = None
    for attempt in range(1, 41):
        build = find_build(client, app_id, version)
        if build is None:
            print("  absent, waiting ({}/40)".format(attempt))
            time.sleep(30)
            continue
        state = (build.get("attributes") or {}).get("processingState") or ""
        print("  {} ({}/40)".format(describe_build(build), attempt))
        if state != "PROCESSING":
            break
        time.sleep(30)
    if build is None:
        print("build {} not visible yet".format(version))
        return
    state = (build.get("attributes") or {}).get("processingState") or ""
    build_id = build["id"]
    groups = list_groups(client, app_id)
    print("betaGroups:")
    if not groups:
        print("  (none)")
    for item in groups:
        attrs = item.get("attributes") or {}
        print("  {} internal={} publicLink={} allBuilds={}".format(
            attrs.get("name") or item["id"],
            attrs.get("isInternalGroup"),
            attrs.get("publicLinkEnabled"),
            attrs.get("hasAccessToAllBuilds"),
        ))
    print("build {} groups before:".format(version))
    before = safe_links(client, build_id)
    if before:
        for name, attrs in before:
            print("  {} internal={} publicLink={}".format(
                name, attrs.get("isInternalGroup"), attrs.get("publicLinkEnabled"),
            ))
    else:
        print("  (none)")
    external = [
        name for name, attrs in before
        if attrs.get("isInternalGroup") is not True or attrs.get("publicLinkEnabled") is True
    ]
    if external:
        print("build {} is in a non-internal group: {}".format(version, ", ".join(external)))
        raise SystemExit(1)
    if state != "VALID":
        print("build {} not attached: processingState {}".format(version, state))
        return
    linked_ids = set()
    query = urllib.parse.urlencode({"limit": 50, "fields[betaGroups]": "name"})
    try:
        for item in pages(client, "/v1/builds/{}/betaGroups?{}".format(build_id, query)):
            linked_ids.add(item["id"])
    except ApiError as error:
        print("build {} group ids unreadable: {}".format(version, error))
        return
    for item in groups:
        attrs = item.get("attributes") or {}
        name = attrs.get("name") or item["id"]
        if attrs.get("isInternalGroup") is not True or attrs.get("publicLinkEnabled") is True:
            print("skipped group {}: internal={} publicLink={}".format(
                name, attrs.get("isInternalGroup"), attrs.get("publicLinkEnabled"),
            ))
            continue
        if item["id"] in linked_ids:
            print("build {} already in internal group {}".format(version, name))
            continue
        try:
            client.request("POST", "/v1/betaGroups/{}/relationships/builds".format(item["id"]), {
                "data": [{"type": "builds", "id": build_id}],
            })
        except ApiError as error:
            print("attach build {} to {} failed: {}".format(version, name, error))
            continue
        print("attached build {} to internal group {}".format(version, name))
    print("build {} groups after:".format(version))
    after = safe_links(client, build_id)
    if after:
        for name, attrs in after:
            print("  {} internal={} publicLink={}".format(
                name, attrs.get("isInternalGroup"), attrs.get("publicLinkEnabled"),
            ))
    else:
        print("  (none)")
    external = [
        name for name, attrs in after
        if attrs.get("isInternalGroup") is not True or attrs.get("publicLinkEnabled") is True
    ]
    if external:
        print("build {} is in a non-internal group: {}".format(version, ", ".join(external)))
        raise SystemExit(1)


def main():
    key_id = require_env("APP_STORE_CONNECT_KEY_ID")
    issuer_id = require_env("APP_STORE_CONNECT_ISSUER_ID")
    p8_b64 = require_env("APP_STORE_CONNECT_KEY_P8_BASE64")
    work = pathlib.Path(tempfile.mkdtemp(prefix="tellomi-asc-"))
    p8_path = work / "AuthKey.p8"
    try:
        import base64
        p8_path.write_bytes(base64.b64decode("".join(p8_b64.split())))
        os.chmod(p8_path, 0o600)
        client = Client(make_jwt(key_id, issuer_id, p8_path))
        query = urllib.parse.urlencode({
            "filter[bundleId]": BUNDLE_ID,
            "limit": 5,
        })
        payload = client.request("GET", "/v1/apps?" + query)
        apps = payload.get("data") or []
        if not apps:
            print("no app record for {}".format(BUNDLE_ID))
            return
        match = apps[0]
        app_id = match["id"]
        name = (match.get("attributes") or {}).get("name") or ""
        print("app {} {}".format(app_id, name))
        print("appStoreVersions:")
        store = []
        for item in pages(client, "/v1/apps/{}/appStoreVersions?limit=200".format(app_id)):
            attrs = item.get("attributes") or {}
            version = attrs.get("versionString") or ""
            state = attrs.get("appStoreState") or ""
            platform = attrs.get("platform") or ""
            store.append(version)
            print("  {} {} {}".format(version, platform, state))
        if not store:
            print("  (none)")
        print("preReleaseVersions:")
        pre = []
        for item in pages(client, "/v1/apps/{}/preReleaseVersions?limit=200".format(app_id)):
            attrs = item.get("attributes") or {}
            version = attrs.get("version") or ""
            platform = attrs.get("platform") or ""
            pre.append(version)
            print("  {} {}".format(version, platform))
        if not pre:
            print("  (none)")
        report_build(client, app_id, "74")
    finally:
        import shutil
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
