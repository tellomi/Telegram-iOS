# Tellomi

The MTProto server this client opens is [`Tellomi/tellomi-server.json`](../Tellomi/tellomi-server.json). That file is the only copy of the seed addresses, the TCP ports and the server RSA public keys. Regenerate the header the app compiles in after an edit:

```sh
python3 Tellomi/generate_server_config.py
python3 Tellomi/check_server_config.py
```

`submodules/MtProtoKit/Sources/TellomiServerConfigJSON.h` is generated. Do not edit it. MtProtoKit has no app bundle to read the JSON from at runtime, so the generator turns the file into one Objective-C string.

## Production seed

Datacenter 1. A fresh install dials, in order:

1. `8.156.40.105` port 10443
2. `8.156.40.105` port 443
3. `api.tellomi.cn` port 10443
4. `api.tellomi.cn` port 443

The built-in IP is first on a fresh install, the same way Telegram ships DC addresses. A non-empty `help.getConfig` list replaces that seed and is dialed in the order it was saved. The seed is used again only when the saved list is missing or empty. Port 10443 is still tried before 443 on the seed host. `api.tellomi.cn` is the DNS fallback and currently resolves to `8.156.40.105` (`seed_address_a_record`). That field is not dialed by itself. The testing seed is `api.tellomi.cn` on the same two ports.

The server announces the 2026-11 RSA key first (little-endian fingerprint `4381149949997195609`) and keeps Teamgram's development key (`12240908862933197005`) last. Dev login SMS code is `12345`.
