# Tellomi distribution certificate

TestFlight signs with an Apple Distribution certificate that ops supplies. The workflow does not mint one unless that fallback is turned on. Profiles are still created through the App Store Connect API, and each profile must include this certificate.

The `.p8` (`APP_STORE_CONNECT_KEY_P8_BASE64`) is only an API key. It cannot sign the app.

## Create the certificate

On a machine that will keep the private key:

```sh
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out tellomi-distribution.key
openssl req -new -key tellomi-distribution.key -out tellomi-distribution.csr -subj "/CN=Tellomi Distribution"
```

In the Apple Developer portal (Certificates, Identifiers & Profiles → Certificates):

1. Create an **Apple Distribution** certificate.
2. Upload `tellomi-distribution.csr`.
3. Download the `.cer`.
4. If the account already has a current distribution certificate, revoke the unused one first. Apple rejects a second one.

Combine the downloaded certificate with the private key. `openssl` accepts either PEM or DER:

```sh
openssl x509 -in distribution.cer -inform DER -out distribution.pem
# If that fails, the download is already PEM. Use it as distribution.pem.
openssl pkcs12 -export \
  -inkey tellomi-distribution.key \
  -in distribution.pem \
  -out tellomi-distribution.p12
```

`openssl pkcs12 -export` asks for an export password. Remember it. An empty password is allowed; set the password secret to an empty value in that case.

Do not commit the key, the CSR, the `.cer`, or the `.p12`.

## Repository secrets

| Secret | Value |
| --- | --- |
| `APPLE_DIST_CERT_P12_BASE64` | `base64 < tellomi-distribution.p12` (one line is fine; line breaks are stripped) |
| `APPLE_DIST_CERT_P12_PASSWORD` | The export password. Empty if the `.p12` has no password. |

The workflow also needs `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, and `APP_STORE_CONNECT_KEY_P8_BASE64`.

`ImportCertificates.py` imports the `.p12` into a temporary keychain, first with the export password. A modern AES-256 archive and an OpenSSL `-legacy` archive both work. If Keychain rejects the original file, the reader tries the modern parser and then `-legacy`, rewrites to an empty-password archive, and imports that. The password is not printed.

Profiles created for `app.tellomi.chat` and its extensions reference the portal certificate whose serial matches this `.p12`. A serial that is not on the team fails the signing step instead of minting a replacement.

## Minting is opt-in

Set the repository variable `TELLOMI_MINT_DISTRIBUTION_CERT` to `1`, or run the workflow with **mint_distribution_cert**. That path generates a CSR, asks Apple for a certificate, and caches the private key. The cache is scoped to the git ref, so a later tag cannot see a key saved by an earlier tag. Leave this off unless you intend to mint.
