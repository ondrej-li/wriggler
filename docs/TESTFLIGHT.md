# Publishing

**CI does not publish.** There is no workflow that uploads to App Store Connect,
and no Apple credential is stored in this repository. Publishing is a manual step
from a machine with Xcode and the developer account signed in; the commit-time
workflow (`ci.yml`) only builds and tests.

Why: an upload needs a distribution identity, and an identity is a private key
Apple hands out once per certificate. Every arrangement that puts one in CI
either stores a long-lived secret (which has to be exported out of a keychain) or
re-creates the certificate per run (which mails the account holder and
invalidates profiles built on it). Neither is worth it for a handful of releases
a year.

## How to ship

__SHIP__

```sh
make archive          # signed .xcarchive, then .ipa in build/export
make upload           # pushes the .ipa to TestFlight
make upload-xcode     # or: archive, export and upload via the signed-in Xcode account
```

`make upload` needs an App Store Connect API key in the environment
(`APP_CONNECT_KEY_ID`, `APP_CONNECT_ISSUER_ID`, `APP_CONNECT_KEY_PATH`);
`make upload-xcode` needs only the Apple ID signed into Xcode. `BUILD_NUMBER=42`
overrides `CFBundleVersion`, which TestFlight refuses to reuse.

The rest of the store checklist — export compliance, privacy manifest, the
opaque app icon, the iPad orientation rule — is documented in the README and
`docs/`.
