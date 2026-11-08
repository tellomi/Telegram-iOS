#!/usr/bin/env python3
"""Print App Store and TestFlight version strings for app.tellomi.chat.

Uses the App Store Connect API key already used by TestFlight. Prints version
strings and states only.
"""

import os
import pathlib
import sys
import tempfile
import urllib.parse

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from prepare_appstore_signing import Client, make_jwt, require_env  # noqa: E402

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


def print_builds(client, app_id):
    """Read build processing and existing beta groups. Do not invite testers."""
    print("builds:")
    query = urllib.parse.urlencode({
        "filter[app]": app_id,
        "limit": 20,
        "sort": "-uploadedDate",
        "fields[builds]": "version,processingState,uploadedDate,expired",
    })
    builds = list(pages(client, "/v1/builds?" + query))
    if not builds:
        print("  (none)")
        return
    wanted = None
    for item in builds:
        attrs = item.get("attributes") or {}
        version = str(attrs.get("version") or "")
        state = attrs.get("processingState") or ""
        uploaded = attrs.get("uploadedDate") or ""
        expired = attrs.get("expired")
        print("  build {} {} uploaded {} expired {}".format(version, state, uploaded, expired))
        if version == "73" and wanted is None:
            wanted = item
    if wanted is None:
        print("build 73: not in the newest 20 builds")
        return
    build_id = wanted["id"]
    linked = []
    group_fields = urllib.parse.urlencode({
        "limit": 50,
        "fields[betaGroups]": "name,isInternalGroup,publicLinkEnabled",
    })
    for item in pages(client, "/v1/builds/{}/betaGroups?{}".format(build_id, group_fields)):
        attrs = item.get("attributes") or {}
        linked.append(item["id"])
        print("  build 73 group {} internal={} publicLink={}".format(
            attrs.get("name") or "",
            attrs.get("isInternalGroup"),
            attrs.get("publicLinkEnabled"),
        ))
        if not linked:
            print("  build 73 groups: (none)")
        state = (wanted.get("attributes") or {}).get("processingState") or ""
        if state != "VALID":
            print("build 73 not attached: processingState {}".format(state))
            return
        group_query = urllib.parse.urlencode({
            "limit": 50,
            "fields[betaGroups]": "name,isInternalGroup,publicLinkEnabled",
        })
        for item in pages(client, "/v1/apps/{}/betaGroups?{}".format(app_id, group_query)):
            attrs = item.get("attributes") or {}
            if attrs.get("isInternalGroup") is not True or attrs.get("publicLinkEnabled"):
                continue
            group_id = item["id"]
            if group_id in linked:
                continue
            # Existing internal group only. No tester create and no invitation endpoint.
            client.request("POST", "/v1/betaGroups/{}/relationships/builds".format(group_id), {
                "data": [{"type": "builds", "id": build_id}],
            })
            print("attached build 73 to internal group {}".format(attrs.get("name") or group_id))


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
        print_builds(client, app_id)
    finally:
        import shutil
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
