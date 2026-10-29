#!/usr/bin/env python3
"""Create App Store signing material from the App Store Connect API key.

Reads APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID and
APP_STORE_CONNECT_KEY_P8_BASE64 from the environment. The .p8 is the API
credential, not a code-signing certificate, so this script generates an
Apple Distribution certificate (reusing one whose private key is already in
--cert-dir) and App Store profiles for every bundle id the Bazel device
build signs.

Nothing from those three variables is written to stdout or stderr.
"""

import argparse
import base64
import http.client
import json
import os
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com"
API_ATTEMPTS = 5
API_TIMEOUT_SECONDS = 120
APP_GROUP = "group.{bundle_id}"


def signing_targets():
    """Bundle ids this script registers. Suffixes come from extension-suffixes.json.

    The watch app is omitted there (register=false): Make.py embeds it only
    with --embedWatchApp. asc_profile_name is the App Store Connect profile
    name (50 character limit).
    """
    from extension_suffixes import registered_targets

    targets = []
    for item in registered_targets():
        targets.append((
            item["suffix"],
            item["name"],
            item["asc_profile_name"],
            list(item["capabilities"]),
        ))
    return targets


class ApiError(Exception):
    def __init__(self, status, body):
        self.status = status
        self.body = body
        detail = _public_error(body)
        super().__init__("App Store Connect API HTTP {} ({})".format(status, detail))


def _public_error(body):
    try:
        payload = json.loads(body)
    except json.JSONDecodeError:
        return "unreadable response"
    errors = payload.get("errors") or []
    parts = []
    for error in errors:
        title = error.get("title") or ""
        detail = error.get("detail") or ""
        parts.append("{} {}".format(title, detail).strip())
    return "; ".join(parts) if parts else "no error detail"


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _der_int(data, index):
    if data[index] != 0x02:
        raise ValueError("ECDSA signature is not a DER integer")
    length = data[index + 1]
    start = index + 2
    if length & 0x80:
        count = length & 0x7F
        length = int.from_bytes(data[start:start + count], "big")
        start += count
    return data[start:start + length], start + length


def der_ecdsa_to_raw(der):
    if der[0] != 0x30:
        raise ValueError("ECDSA signature is not a DER sequence")
    # Skip the sequence header. openssl emits a short-form length for P-256.
    index = 2
    if der[1] & 0x80:
        index = 2 + (der[1] & 0x7F)
    r, index = _der_int(der, index)
    s, index = _der_int(der, index)

    def fixed(part):
        part = part.lstrip(b"\x00")
        if len(part) > 32:
            raise ValueError("ECDSA component is longer than 32 bytes")
        return part.rjust(32, b"\x00")

    return fixed(r) + fixed(s)


def make_jwt(key_id, issuer_id, p8_path):
    now = int(time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}, separators=(",", ":")).encode())
    payload = b64url(json.dumps({
        "iss": issuer_id,
        "iat": now,
        "exp": now + 15 * 60,
        "aud": "appstoreconnect-v1",
    }, separators=(",", ":")).encode())
    signing_input = "{}.{}".format(header, payload).encode()
    signature = subprocess.check_output(
        ["openssl", "dgst", "-sha256", "-sign", str(p8_path)],
        input=signing_input,
    )
    return "{}.{}".format(signing_input.decode(), b64url(der_ecdsa_to_raw(signature)))


def _pause(seconds):
    time.sleep(seconds)


def _retryable_transport(error):
    return isinstance(error, (TimeoutError, urllib.error.URLError, ConnectionError, http.client.HTTPException))


class Client:
    def __init__(self, token):
        self.token = token

    def request(self, method, path, body=None):
        data = None if body is None else json.dumps(body).encode()
        for attempt in range(1, API_ATTEMPTS + 1):
            request = urllib.request.Request(
                API + path,
                data=data,
                method=method,
                headers={
                    "Authorization": "Bearer " + self.token,
                    "Content-Type": "application/json",
                },
            )
            try:
                with urllib.request.urlopen(request, timeout=API_TIMEOUT_SECONDS) as response:
                    raw = response.read()
                    if not raw:
                        return {}
                    return json.loads(raw)
            except urllib.error.HTTPError as error:
                payload = error.read().decode("utf-8", errors="replace")
                if error.code in (429, 500, 502, 503, 504) and attempt < API_ATTEMPTS:
                    self._retry_wait(attempt, "HTTP {}".format(error.code), path)
                    continue
                raise ApiError(error.code, payload)
            except urllib.error.URLError as error:
                # HTTPError is a URLError. It is handled above so a 4xx is not retried.
                if attempt < API_ATTEMPTS and _retryable_transport(error):
                    self._retry_wait(attempt, type(error).__name__, path)
                    continue
                raise
            except (TimeoutError, ConnectionError, http.client.HTTPException) as error:
                if attempt < API_ATTEMPTS:
                    self._retry_wait(attempt, type(error).__name__, path)
                    continue
                raise
        raise RuntimeError("App Store Connect request was not sent")

    def _retry_wait(self, attempt, reason, path):
        delay = 2 ** attempt
        print("App Store Connect {} failed ({}), retrying in {}s ({}/{})".format(
            path.split("?", 1)[0], reason, delay, attempt + 1, API_ATTEMPTS,
        ))
        _pause(delay)


def require_env(name):
    value = os.environ.get(name)
    if not value:
        print("Missing environment variable {}".format(name), file=sys.stderr)
        sys.exit(1)
    return value


def bundle_targets(bundle_id):
    group = APP_GROUP.format(bundle_id=bundle_id)
    targets = []
    for suffix, name, profile_name, capabilities in signing_targets():
        targets.append((bundle_id + suffix, name, profile_name, capabilities, group))
    return targets


def _bundle_id_pages(client, query):
    path = "/v1/bundleIds?" + query
    for _page in range(50):
        payload = client.request("GET", path)
        for item in payload.get("data") or []:
            yield item
        next_link = ((payload.get("links") or {}).get("next")) or ""
        if not next_link.startswith(API):
            return
        path = next_link[len(API):]


def find_bundle_id(client, identifier):
    # filter[identifier] is prefix-ish: app.tellomi.chat also returns
    # app.tellomi.chat.Share. Only an exact attribute match counts.
    query = urllib.parse.urlencode({
        "filter[identifier]": identifier,
        "limit": 200,
    })
    for item in _bundle_id_pages(client, query):
        found = (item.get("attributes") or {}).get("identifier") or ""
        if found == identifier:
            return item["id"]
    return None


def _not_available(error):
    return error.status == 409 and "not available" in str(error).lower()


def ensure_bundle_id(client, identifier, name):
    existing = find_bundle_id(client, identifier)
    if existing:
        print("bundle id exists: {}".format(identifier))
        return existing
    print("creating bundle id {}".format(identifier))
    try:
        payload = client.request("POST", "/v1/bundleIds", {
            "data": {
                "type": "bundleIds",
                "attributes": {
                    "identifier": identifier,
                    "name": name,
                    "platform": "IOS",
                },
            }
        })
    except ApiError as error:
        if error.status != 409:
            raise
        # 409 "is not available" means this identifier is already registered.
        if _not_available(error):
            print("bundle id {} already registered".format(identifier))
        else:
            print("bundle id create conflict for {}".format(identifier))
        for attempt in range(1, API_ATTEMPTS + 1):
            existing = find_bundle_id(client, identifier)
            if existing:
                print("bundle id exists: {}".format(identifier))
                return existing
            if attempt < API_ATTEMPTS:
                _pause(2 ** attempt)
        raise
    return payload["data"]["id"]


def capability_settings(capability, group):
    # The App Store Connect API rejects APP_GROUPS when settings names the
    # group. Enable every capability, including APP_GROUPS and SIRIKIT, with
    # an empty settings list. The group id is checked on the downloaded
    # profile afterwards (require_app_group).
    del capability, group
    return []


def ensure_capability(client, bundle_resource_id, capability, group):
    settings = capability_settings(capability, group)
    body = {
        "data": {
            "type": "bundleIdCapabilities",
            "attributes": {
                "capabilityType": capability,
                "settings": settings,
            },
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_resource_id}},
            },
        }
    }
    try:
        client.request("POST", "/v1/bundleIdCapabilities", body)
        print("enabled {} ".format(capability))
    except ApiError as error:
        if error.status == 409:
            print("{} already enabled".format(capability))
            return
        raise


def list_distribution_certs(client):
    query = urllib.parse.urlencode({
        "filter[certificateType]": "DISTRIBUTION",
        "limit": 20,
    })
    payload = client.request("GET", "/v1/certificates?" + query)
    return payload.get("data") or []


def certificate_serial(cert_path):
    output = subprocess.check_output(
        ["openssl", "x509", "-in", str(cert_path), "-noout", "-serial"],
        text=True,
    )
    return output.strip().split("=", 1)[1].lower().lstrip("0")


def write_p12(key_path, cert_path, p12_path):
    # ImportCertificates.py imports with an empty password. -legacy is what
    # the macOS security tool in this repo's profile generator can read.
    command = [
        "openssl", "pkcs12", "-export",
        "-inkey", str(key_path),
        "-in", str(cert_path),
        "-out", str(p12_path),
        "-passout", "pass:",
        "-legacy",
    ]
    try:
        subprocess.check_call(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        command.remove("-legacy")
        subprocess.check_call(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def extract_cached_cert(p12_path, cert_path):
    attempts = [
        ["openssl", "pkcs12", "-in", str(p12_path), "-nokeys", "-passin", "pass:", "-out", str(cert_path), "-legacy"],
        ["openssl", "pkcs12", "-in", str(p12_path), "-nokeys", "-passin", "pass:", "-out", str(cert_path)],
    ]
    last = None
    for command in attempts:
        try:
            subprocess.check_call(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return
        except subprocess.CalledProcessError as error:
            last = error
    raise last


def ensure_certificate(client, cert_dir):
    cert_dir.mkdir(parents=True, exist_ok=True)
    p12_path = cert_dir / "Distribution.p12"
    cer_path = cert_dir / "Distribution.cer"
    portal = list_distribution_certs(client)
    if p12_path.exists():
        try:
            extract_cached_cert(p12_path, cer_path)
            serial = certificate_serial(cer_path)
        except subprocess.CalledProcessError:
            serial = None
        if serial:
            for item in portal:
                portal_serial = (item.get("attributes") or {}).get("serialNumber") or ""
                if portal_serial.lower().lstrip("0") == serial:
                    print("reusing Apple Distribution certificate")
                    return item["id"]
        print("cached distribution certificate is not in the portal; creating a new one")

    work = pathlib.Path(tempfile.mkdtemp(prefix="tellomi-csr-"))
    try:
        key_path = work / "distribution.key"
        csr_path = work / "distribution.csr"
        subprocess.check_call([
            "openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes",
            "-keyout", str(key_path),
            "-out", str(csr_path),
            "-subj", "/CN=Tellomi Distribution",
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        csr = csr_path.read_text(encoding="utf-8")
        try:
            created = client.request("POST", "/v1/certificates", {
                "data": {
                    "type": "certificates",
                    "attributes": {
                        "certificateType": "DISTRIBUTION",
                        "csrContent": csr,
                    },
                }
            })
        except ApiError as error:
            if error.status == 409:
                print(
                    "Apple refused a new distribution certificate (the account is at its certificate limit). "
                    "Revoke an unused Apple Distribution certificate in the developer portal, or restore the "
                    "private key for an existing one into the signing cache.",
                    file=sys.stderr,
                )
            raise
        content = created["data"]["attributes"]["certificateContent"]
        cer_path.write_bytes(base64.b64decode(content))
        write_p12(key_path, cer_path, p12_path)
        print("created Apple Distribution certificate")
        return created["data"]["id"]
    finally:
        shutil.rmtree(work, ignore_errors=True)


def delete_profile_named(client, name):
    query = urllib.parse.urlencode({"filter[name]": name, "limit": 5})
    payload = client.request("GET", "/v1/profiles?" + query)
    for item in payload.get("data") or []:
        if item.get("attributes", {}).get("name") == name:
            client.request("DELETE", "/v1/profiles/" + item["id"])


def create_profile(client, name, bundle_resource_id, certificate_id, destination):
    delete_profile_named(client, name)
    created = client.request("POST", "/v1/profiles", {
        "data": {
            "type": "profiles",
            "attributes": {
                "name": name,
                "profileType": "IOS_APP_STORE",
            },
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_resource_id}},
                "certificates": {"data": [{"type": "certificates", "id": certificate_id}]},
            },
        }
    })
    content = created["data"]["attributes"]["profileContent"]
    destination.write_bytes(base64.b64decode(content))
    print("profile {}".format(name))


def profile_plist(path):
    # mobileprovision is CMS. openssl smime -verify -noverify prints the plist.
    plist_bytes = subprocess.check_output([
        "openssl", "smime", "-inform", "der", "-verify", "-noverify", "-in", str(path),
    ], stderr=subprocess.DEVNULL)
    return plistlib.loads(plist_bytes)


def team_id_from_profile(path):
    payload = profile_plist(path)
    teams = payload.get("TeamIdentifier") or []
    if not teams:
        raise SystemExit("Provisioning profile has no TeamIdentifier")
    entitlements = payload.get("Entitlements") or {}
    if "aps-environment" not in entitlements:
        raise SystemExit(
            "The main App Store profile has no aps-environment entitlement. "
            "Push Notifications must be enabled on the app id; Make.py refuses to build without it."
        )
    return teams[0]


def require_app_group(path, group):
    groups = (profile_plist(path).get("Entitlements") or {}).get("com.apple.security.application-groups") or []
    if group not in groups:
        raise SystemExit("Provisioning profile {} does not include {}".format(path.name, group))


def write_configuration(source, destination, team_id):
    config = json.loads(pathlib.Path(source).read_text(encoding="utf-8"))
    config["team_id"] = team_id
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
    print("team id {}".format(team_id))


def next_build_number(client, bundle_id, floor):
    query = urllib.parse.urlencode({"filter[bundleId]": bundle_id, "limit": 1})
    payload = client.request("GET", "/v1/apps?" + query)
    apps = payload.get("data") or []
    if not apps:
        print("no App Store Connect app record yet; build number {}".format(floor))
        return floor
    app_id = apps[0]["id"]
    query = urllib.parse.urlencode({
        "filter[app]": app_id,
        "limit": 200,
        "fields[builds]": "version",
    })
    highest = 0
    path = "/v1/builds?" + query
    for _page in range(10):
        payload = client.request("GET", path)
        for item in payload.get("data") or []:
            version = (item.get("attributes") or {}).get("version") or ""
            if version.isdigit():
                highest = max(highest, int(version))
        next_link = ((payload.get("links") or {}).get("next")) or ""
        if not next_link.startswith(API):
            break
        path = next_link[len(API):]
    number = max(highest + 1, floor)
    print("build number {} (previous highest {})".format(number, highest))
    return number


def ensure_app_record(client, bundle_resource_id, name):
    # Creating the app record is what makes the first TestFlight upload have a destination.
    # A 409 means the name or sku is taken, or the app already exists; the upload still
    # works when the bundle id is already registered.
    try:
        client.request("POST", "/v1/apps", {
            "data": {
                "type": "apps",
                "attributes": {
                    "name": name,
                    "primaryLocale": "en-US",
                    "sku": "tellomi-ios",
                },
                "relationships": {
                    "bundleId": {"data": {"type": "bundleIds", "id": bundle_resource_id}},
                },
            }
        })
        print("created App Store Connect app record")
    except ApiError as error:
        if error.status == 409:
            print("App Store Connect app record already exists")
            return
        print("could not create the App Store Connect app record: {}".format(error), file=sys.stderr)


def prepare(args):
    key_id = require_env("APP_STORE_CONNECT_KEY_ID")
    issuer_id = require_env("APP_STORE_CONNECT_ISSUER_ID")
    p8_b64 = require_env("APP_STORE_CONNECT_KEY_P8_BASE64")
    config = json.loads(pathlib.Path(args.configuration).read_text(encoding="utf-8"))
    bundle_id = config["bundle_id"]
    app_name = config["app_name"]

    p8_dir = pathlib.Path(tempfile.mkdtemp(prefix="tellomi-api-key-"))
    p8_path = p8_dir / "AuthKey.p8"
    try:
        p8_path.write_bytes(base64.b64decode(p8_b64))
        os.chmod(p8_path, 0o600)
        token = make_jwt(key_id, issuer_id, p8_path)
        client = Client(token)
        targets = bundle_targets(bundle_id)
        ids = {}
        for identifier, name, _profile_name, capabilities, group in targets:
            resource_id = ensure_bundle_id(client, identifier, name)
            ids[identifier] = resource_id
            for capability in capabilities:
                print("capability {} on {}".format(capability, identifier))
                ensure_capability(client, resource_id, capability, group)
        certificate_id = ensure_certificate(client, pathlib.Path(args.cert_dir))
        profile_dir = pathlib.Path(args.output) / "profiles"
        profile_dir.mkdir(parents=True, exist_ok=True)
        cert_out = pathlib.Path(args.output) / "certs"
        cert_out.mkdir(parents=True, exist_ok=True)
        for filename in ("Distribution.p12", "Distribution.cer"):
            source = pathlib.Path(args.cert_dir) / filename
            if source.exists():
                shutil.copyfile(source, cert_out / filename)
        main_profile = None
        for identifier, _name, profile_name, _capabilities, group in targets:
            destination = profile_dir / (profile_name + ".mobileprovision")
            create_profile(client, profile_name, ids[identifier], certificate_id, destination)
            require_app_group(destination, group)
            if identifier == bundle_id:
                main_profile = destination
        team_id = team_id_from_profile(main_profile)
        write_configuration(args.configuration, pathlib.Path(args.configuration_out), team_id)
        ensure_app_record(client, ids[bundle_id], app_name)
        number = next_build_number(client, bundle_id, args.build_number_floor)
        pathlib.Path(args.build_number_out).write_text(str(number) + "\n", encoding="utf-8")
    finally:
        shutil.rmtree(p8_dir, ignore_errors=True)


def self_test():
    work = pathlib.Path(tempfile.mkdtemp(prefix="tellomi-jwt-"))
    try:
        key = work / "key.p8"
        subprocess.check_call([
            "openssl", "genpkey", "-algorithm", "EC", "-pkeyopt", "ec_paramgen_curve:P-256",
            "-out", str(key),
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        token = make_jwt("TESTKEYID", "TEST-ISSUER", key)
        parts = token.split(".")
        if len(parts) != 3:
            raise SystemExit("JWT self-test failed")
        signature = base64.urlsafe_b64decode(parts[2] + "=" * (-len(parts[2]) % 4))
        if len(signature) != 64:
            raise SystemExit("JWT signature is not raw R||S")
        header = json.loads(base64.urlsafe_b64decode(parts[0] + "=="))
        if header.get("alg") != "ES256" or header.get("kid") != "TESTKEYID":
            raise SystemExit("JWT header is wrong")
        print("jwt self-test passed")
        if capability_settings("APP_GROUPS", "group.app.tellomi.chat") != []:
            raise SystemExit("APP_GROUPS capability settings must be empty")
        if capability_settings("SIRIKIT", "group.app.tellomi.chat") != []:
            raise SystemExit("capability settings must be empty")
        siri = [item for item in signing_targets() if item[0] == ".SiriIntents"]
        if len(siri) != 1 or "SIRIKIT" not in siri[0][3]:
            raise SystemExit("SiriIntents must enable SiriKit")
        if API_TIMEOUT_SECONDS != 120 or API_ATTEMPTS != 5:
            raise SystemExit("App Store Connect retry policy changed")

        class PrefixList:
            def request(self, method, path, body=None):
                return {
                    "data": [
                        {"id": "share", "attributes": {"identifier": "app.tellomi.chat.Share"}},
                        {"id": "main", "attributes": {"identifier": "app.tellomi.chat"}},
                    ],
                    "links": {},
                }

        if find_bundle_id(PrefixList(), "app.tellomi.chat") != "main":
            raise SystemExit("exact bundle id match failed")
        if find_bundle_id(PrefixList(), "missing.bundle") is not None:
            raise SystemExit("missing bundle id matched a prefix")

        class Flaky:
            def __init__(self):
                self.calls = 0

            def __call__(self, request, timeout=None):
                if timeout != API_TIMEOUT_SECONDS:
                    raise SystemExit("read timeout is {}".format(timeout))
                self.calls += 1
                if self.calls < 3:
                    raise TimeoutError("timed out")

                class Response:
                    def read(self):
                        return b'{"ok": true}'

                    def __enter__(self):
                        return self

                    def __exit__(self, *args):
                        return False

                return Response()

        flaky = Flaky()
        original_open = urllib.request.urlopen
        original_pause = globals()["_pause"]
        slept = []

        def record(seconds):
            slept.append(seconds)

        urllib.request.urlopen = flaky
        globals()["_pause"] = record
        try:
            payload = Client("token").request("GET", "/v1/bundleIds?filter[identifier]=app.tellomi.chat")
        finally:
            urllib.request.urlopen = original_open
            globals()["_pause"] = original_pause
        if payload != {"ok": True} or flaky.calls != 3 or slept != [2, 4]:
            raise SystemExit("retry backoff failed: calls={} slept={}".format(flaky.calls, slept))
        print("retry self-test passed")
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main():
    parser = argparse.ArgumentParser(description="Prepare Tellomi App Store signing material.")
    parser.add_argument("--configuration", required=False)
    parser.add_argument("--configuration-out", required=False)
    parser.add_argument("--output", required=False, help="Directory with profiles/ and certs/ for Make.py")
    parser.add_argument("--cert-dir", required=False, help="Persistent directory for Distribution.p12")
    parser.add_argument("--build-number-out", required=False)
    parser.add_argument("--build-number-floor", type=int, default=1)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    missing = [
        name for name in ("configuration", "configuration_out", "output", "cert_dir", "build_number_out")
        if not getattr(args, name)
    ]
    if missing:
        print("missing arguments: {}".format(", ".join(missing)), file=sys.stderr)
        sys.exit(2)
    prepare(args)


if __name__ == "__main__":
    main()
