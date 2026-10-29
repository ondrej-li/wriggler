# TestFlight

The app builds for the simulator out of the box. Shipping a TestFlight build needs
three one-time things on your side, then it is two commands.

## One-time setup

1. **A development team.** Already configured for this checkout: `local.mk` (not
   committed) holds `DEVELOPMENT_TEAM := B592D69P29`, so `make open`, `make build`
   and `make archive` all sign for the right team without extra flags.

   On another machine, either create `local.mk` with the same line or pass it in:
   `make generate DEVELOPMENT_TEAM=ABCDE12345`.

2. **An App Store Connect app record** for the bundle identifier
   `cz.ondrejli.wriggler` (*Apps > + > New App*, platform iOS). TestFlight uploads
   are rejected if no record exists.

3. **An App Store Connect API key** with the *App Manager* role
   (*Users and Access > Integrations > App Store Connect API > +*). Download the
   `.p8` once — Apple will not let you fetch it again. You need:

   | Variable | Where it comes from |
   | --- | --- |
   | `APP_CONNECT_KEY_ID` | the key's ID, e.g. `2X9ABCDEFG` |
   | `APP_CONNECT_ISSUER_ID` | the issuer UUID shown above the key list |
   | `APP_CONNECT_KEY_PATH` | path to `AuthKey_<id>.p8` |

   Also add your team ID under *Users and Access > Integrations* if you want
   Xcode to sign with the same key.

## Ship a build

Two routes. The first needs no API key at all:

```sh
make upload-xcode            # archive, export and upload via the Xcode account
```

The second separates the steps and is the one CI uses:

```sh
make archive                 # signed .xcarchive, then .ipa in build/export
make upload                  # pushes the .ipa to TestFlight
```

`make upload-xcode` uses the Apple ID signed in to Xcode, so it only works on a
machine where that account exists. `make upload` needs the App Store Connect API
key described above.

`make archive` accepts overrides for CI:

```sh
make archive DEVELOPMENT_TEAM=ABCDE12345 BUILD_NUMBER=42
```

`BUILD_NUMBER` sets `CFBundleVersion`. TestFlight refuses a build number it has
already seen for a version, so each upload needs a fresh one — that is why CI uses
the workflow run number.

The upload is usually visible in App Store Connect within a few minutes and then
takes a short while to finish processing before testers can install it.

## What is already handled

- **Version and build number** — `MARKETING_VERSION` and
  `CURRENT_PROJECT_VERSION` live in `project.yml`, overridable per build.
- **Export compliance** — `ITSAppUsesNonExemptEncryption` is `false`, so uploads
  do not sit waiting for the encryption question.
- **Privacy manifest** — `PrivacyInfo.xcprivacy` declares no tracking and no
  collected data, which is accurate: the game writes nothing off the device.
- **App icon** — `make icon` regenerates `AppIcon-1024.png` as opaque RGB. An icon
  with an alpha channel is rejected.
- **iPad orientations** — the app is landscape on iPhone and open on iPad. An iPad
  app that is landscape-only, without requiring full screen, fails validation;
  iOS 26 no longer honours `UIRequiresFullScreen`.
- **Export options** — `Support/ExportOptions.plist` uses `app-store-connect`.

## CI

`.github/workflows/testflight.yml` archives and uploads on demand, or on a `v*`
tag. It needs these repository secrets:

| Secret | Contents | Status |
| --- | --- | --- |
| `APPLE_TEAM_ID` | `B592D69P29` | set |
| `APP_CONNECT_ISSUER_ID` | issuer UUID | set |
| `APP_CONNECT_KEY_ID` | the key's 10-character ID | **needed** |
| `APP_CONNECT_KEY_P8` | the whole `.p8`, base64 encoded | **needed** |
| `BUILD_CERTIFICATE_P12` | distribution certificate, base64 encoded | **needed** |
| `BUILD_CERTIFICATE_PASSWORD` | password chosen when exporting the `.p12` | **needed** |

The key ID and `.p8` come from *Users and Access > Integrations > App Store
Connect API*. The `.p12` is your "Apple Distribution" certificate exported from
Keychain Access (*My Certificates > right-click > Export*).

To base64 a file for a secret:

```sh
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy   # then paste into the secret value
```

Until those exist the workflow will fail at the signing step; local `make archive`
uses whatever signing Xcode already has, which is the simplest path for a solo
developer.

## Testers

Once the first build is processed, add testers under *TestFlight > Internal
Testing*. Internal testers (up to 100, members of your team) get builds
immediately; external testing needs an Apple review of the first build.
