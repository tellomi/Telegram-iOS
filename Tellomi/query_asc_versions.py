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
            "include": "bundleId",
            "limit": 20,
        })
        payload = client.request("GET", "/v1/apps?" + query)
        included = {}
        for item in payload.get("included") or []:
            included[item.get("id")] = (item.get("attributes") or {}).get("identifier") or ""
        match = None
        for app in payload.get("data") or []:
            relation = (((app.get("relationships") or {}).get("bundleId") or {}).get("data") or {})
            identifier = included.get(relation.get("id"), "")
            if identifier == BUNDLE_ID:
                match = app
                break
        if match is None and len(payload.get("data") or []) == 1:
            match = payload["data"][0]
        if match is None:
            print("no app record for {}".format(BUNDLE_ID))
            return
        app_id = match["id"]
        print("app {}".format(app_id))
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
    finally:
        import shutil
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
