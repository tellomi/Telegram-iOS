"""When the Tellomi binary may request the Siri entitlement.

The SiriIntents App ID is registered with SiriKit. A provisioning profile
created after that capability is on contains ``com.apple.developer.siri``.
The extension still crashes on launch when the signed entitlements omit the
key: iOS kills the intents process instead of handing it a Siri request.
The main app needs the same key before Siri will launch that extension.

A signed build may request the key only when that target's profile grants
it. Requesting it otherwise makes codesign reject the bundle. An unsigned
simulator build ad-hoc signs, so the key can be present without a profile.
"""

SIRI_ENTITLEMENT = "com.apple.developer.siri"


def profile_grants_siri(entitlements):
    if not entitlements:
        return False
    return entitlements.get(SIRI_ENTITLEMENT) is True


def signed_siri_entitlement(profile_grants, provisioning_disabled):
    if provisioning_disabled:
        return True
    return profile_grants is True


def host_bundle_id(bundle_id):
    """Host id an extension derives by dropping its last component.

    ``IntentHandler`` does this with the last ``.`` in
    ``Bundle.main.bundleIdentifier``. ``app.tellomi.chat.SiriIntents`` must
    yield ``app.tellomi.chat``, the same id the app group entitlement uses.
    """
    if not isinstance(bundle_id, str) or "." not in bundle_id:
        return None
    host, dot, suffix = bundle_id.rpartition(".")
    if not host or host.endswith(".") or not suffix:
        return None
    del dot
    return host


def app_group_identifier(host):
    if not host:
        return None
    return "group." + host
