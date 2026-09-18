# 07 — Mobile release

Getting a build of the Flutter app in `apps/mobile` to testers, and what is
and is not automated. Read the last section first: most of this runbook
describes steps nobody has taken yet, and it says so where that is the case.

## What exists

| | |
| --- | --- |
| Package | `apps/mobile`, pubspec name `reward`, on the pub workspace with `packages/domain` |
| Application id | `com.helpmebrands.reward` on both platforms (`PRODUCT_BUNDLE_IDENTIFIER` in `ios/Runner.xcodeproj`, `applicationId` in `android/app/build.gradle.kts`) |
| Display name | `Reward` (`CFBundleDisplayName`); the product name is HelpMe Reward |
| Version | `version: 1.0.0+1` in `apps/mobile/pubspec.yaml` |
| Minimum Flutter | 3.35 (AGENTS.md rule 9); CI uses the version pinned in `verify.yml` |
| CI | the `flutter` job of `verify.yml`: `flutter analyze --fatal-infos` and `flutter test` on every pull request and before every deploy |
| CD | none. No workflow builds, signs or uploads the app. |
| Signing | none in the repository: no certificates, provisioning profiles, keystore or `key.properties` |
| Store accounts | none configured for this app as of 2026-09-18 |

The api it will talk to is `reward-api` ([README](README.md#environments));
device registration is `POST /v1/devices` with the FCM token, an installation
id the app generates, `ios` or `android`, and the IANA zone. Push delivery
itself is not built yet.

## Versioning

Flutter reads one line, `version: <name>+<build>`, and writes it into both
platforms' manifests at build time:

- **`<name>`** (`1.0.0`) is what users see: `CFBundleShortVersionString` on
  iOS, `versionName` on Android. Bump it for a release people should notice.
- **`<build>`** (`1`) is what the stores order uploads by: `CFBundleVersion`
  and `versionCode`. **Every upload to either store needs a build number
  higher than the last one it saw**, whether or not the name changed. Bump it
  for every build you hand to a store.

```sh
$ cd apps/mobile
$ sed -i '' 's/^version: .*/version: 1.0.1+2/' pubspec.yaml
$ git commit -am 'chore(mobile): bump to 1.0.1+2'
```

Do not edit the versions inside `ios/` or `android/`; the build overwrites
them from the pubspec.

## Building

Both builds are done on a laptop for now, because CI has no signing material.
Run the checks CI runs first; a release build does not run tests.

```sh
$ cd apps/mobile
$ flutter --version                  # 3.35 or newer
$ dart pub get
$ flutter analyze --fatal-infos
$ flutter test
```

**iOS** needs a Mac with Xcode, an Apple Developer Program membership and an
App Store Connect record for `com.helpmebrands.reward`. iOS and macOS
dependencies are Swift Package Manager, never CocoaPods (rule 9).

```sh
$ flutter build ipa --release        # writes build/ios/ipa/*.ipa
```

The first time, open `ios/Runner.xcworkspace` in Xcode, sign in under
*Signing & Capabilities* with the team that owns the bundle id, and tick
*Automatically manage signing*; Xcode creates the certificate and profile.
Push notifications will need the *Push Notifications* capability and an APNs
key uploaded to Firebase, which is part of wiring FCM and not of this runbook.

**Android** needs an upload keystore and a Play Console record.

```sh
$ keytool -genkey -v -keystore ~/reward-upload.jks -keyalg RSA -keysize 2048 \
    -validity 10000 -alias upload
```

Keep the keystore and its passwords out of the repository (a password
manager, and later a CI secret). `android/key.properties` names them and is
gitignored by the Flutter template; `android/app/build.gradle.kts` needs the
standard `signingConfigs.release` block reading it before the next command
produces a signed bundle.

```sh
$ flutter build appbundle --release  # writes build/app/outputs/bundle/release/app-release.aab
```

## Getting it to testers

**TestFlight** (iOS). Upload the `.ipa` with the Transporter app or from
Xcode (*Product → Archive → Distribute*), wait for processing, then add
testers to an internal group in App Store Connect. Internal testers (members
of the team) get builds without review; external groups need a short review
once per version name.

**Play internal testing track** (Android). In the Play Console, *Testing →
Internal testing → Create new release*, upload the `.aab`, and add tester
email addresses or a Google Group to the track. Internal track releases are
available within minutes and do not need review. Promote to closed or open
testing from the same release when it is time.

For both, the build number rule above is the thing that fails: a rejected
upload almost always means the store already has that number.

## What CI does and does not do

CI proves the app analyses and its widget tests pass on Linux. It does not
build a release, does not sign, does not upload, and does not run on a device
or simulator. Making it do so means putting the signing material in GitHub
secrets (a base64 keystore and its passwords; a certificate, a profile and an
App Store Connect API key) and adding a macOS runner for the iOS build; do
that in its own issue, with the secrets handled the way the rest of this
repository handles trust (no long-lived credential that a leaked log could
expose without a rotation plan).

## Rules that apply

From AGENTS.md rule 9: Dart formatted with `flutter format .`; only Flutter
Favourite packages without a human's approval; Swift Package Manager, not
CocoaPods; Material, not Cupertino; every widget has a Widget Preview;
minimum Flutter 3.35. A release build that needed an exception to any of
these is a conversation, not a commit.
