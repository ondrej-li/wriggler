# TestFlight

The app builds for the simulator out of the box. Shipping a TestFlight build needs
three one-time things on your side, then it is two commands.

## One-time setup

1. **A development team.** Sign in to Xcode with your Apple ID, then note the
   team ID from *Xcode > Settings > Accounts*. Pass it to the generator so device
   builds and archives sign automatically:

   ```sh
   make generate DEVELOPMENT_TEAM=ABCDE12345
   ```

   Set it once in your shell profile if you prefer:
   `export DEVELOPMENT_TEAM=ABCDE12345`.

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

```sh
make archive                 # signed .xcarchive, then .ipa in build/export
make upload                  # pushes the .ipa to TestFlight
```

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

| Secret | Contents |
| --- | --- |
| `APPLE_TEAM_ID` | your team ID |
| `APP_CONNECT_KEY_ID` | key ID |
| `APP_CONNECT_ISSUER_ID` | issuer UUID |
| `APP_CONNECT_KEY_P8` | the whole `.p8` file, base64 encoded |
| `BUILD_CERTIFICATE_P12` | your distribution certificate, base64 encoded |
| `BUILD_CERTIFICATE_PASSWORD` | the password set when exporting the `.p12` |

Until those exist the workflow will fail at the signing step; local `make archive`
uses whatever signing Xcode already has, which is the simplest path for a solo
developer.

## Testers

Once the first build is processed, add testers under *TestFlight > Internal
Testing*. Internal testers (up to 100, members of your team) get builds
immediately; external testing needs an Apple review of the first build.
