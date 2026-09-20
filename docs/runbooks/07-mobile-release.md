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
| CD | none yet. No workflow builds, signs or uploads the app; the trust it will use exists (below). |
| Signing | nothing in the repository. Secret Manager holds one empty container per piece of signing material (`reward-app-<name>-staging`, declared in `infra/index.ts`), readable by the deployer and filled by hand (*Signing material*, below) |
| Store accounts | a Play publisher identity, `reward-app-play-staging@…`, assumed keylessly from this repository; to be linked in Play Console. No App Store Connect record as of 2026-09-20 |

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

Keep the keystore and its passwords out of the repository: in Secret Manager
under the containers listed in *Signing material* below, which is where the
release workflow will read them. `android/key.properties` names them and is
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

## Signing material

The stack declares, in Secret Manager, one container per piece of signing
material and grants the deployer identity read on exactly those. It never
writes a value: the values are yours to add, once, and to rotate when a
certificate or key expires. Nothing is stored in GitHub, so a leaked
workflow log exposes nothing durable.

| Secret id | Holds |
| --- | --- |
| `reward-app-asc-api-key-staging` | the App Store Connect API key, the `.p8` file |
| `reward-app-asc-api-key-id-staging` | its key id |
| `reward-app-asc-issuer-id-staging` | the issuer id |
| `reward-app-ios-distribution-cert-staging` | the distribution certificate with its private key, `.p12` |
| `reward-app-ios-cert-password-staging` | the `.p12` password |
| `reward-app-ios-provisioning-profile-staging` | the App Store provisioning profile, `.mobileprovision` |
| `reward-app-android-upload-keystore-staging` | the upload keystore, `.jks` |
| `reward-app-android-keystore-password-staging` | the keystore password |
| `reward-app-android-key-password-staging` | the `upload` key's password |

Add a version from the file or value, never from the shell history:

```sh
$ gcloud secrets versions add reward-app-android-upload-keystore-staging \
    --project helpme-reward-staging --data-file ~/reward-upload.jks
$ printf '%s' "$KEYSTORE_PASSWORD" | gcloud secrets versions add \
    reward-app-android-keystore-password-staging --project helpme-reward-staging --data-file -
```

Binary files (`.jks`, `.p12`, `.p8`, `.mobileprovision`) go in as they are;
Secret Manager stores bytes. Rotation is a new version, and the workflow
always reads `latest`. Certificates expire yearly and the App Store Connect
key when you revoke it; put both dates in the README's environment table.

## The Play publisher identity

Uploading to the Play Console needs a Google Cloud service account with
access to the app. The stack declares `reward-app-play-staging@…` and lets
workflows from this repository assume it through the workload identity pool,
so there is no key file. Link it once, by hand, in the Play Console: *Users
and permissions → Invite new users*, the service account's email, with
*Release to testing tracks* on the app. Until the app record exists there is
nothing to link to. The email is on the GitHub environment as
`PLAY_SERVICE_ACCOUNT`, and every secret id above as `SECRET_<NAME>`, for
the release workflow to read.

## What CI does and does not do

CI proves the app analyses and its widget tests pass on Linux. It does not
yet build a release, sign, upload, or run on a device or simulator. The
release workflow that does so (fastlane, a macOS runner for iOS) is its own
issue on epic #96; it reads the signing material above from Secret Manager at
build time as the deployer and never from a GitHub secret.

## Rules that apply

From AGENTS.md rule 9: Dart formatted with `flutter format .`; only Flutter
Favourite packages without a human's approval; Swift Package Manager, not
CocoaPods; Material, not Cupertino; every widget has a Widget Preview;
minimum Flutter 3.35. A release build that needed an exception to any of
these is a conversation, not a commit.
