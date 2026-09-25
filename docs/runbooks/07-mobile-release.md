# 07 — Mobile release

Getting a build of the Flutter app in `apps/mobile` to testers, and what is
and is not automated. The release is a tag push (*Getting it to testers*).
The store records, the signing material, the sign-in credentials and the
Play Console link are one-time hand steps, done once in order in
[08 — Mobile setup](08-mobile-setup.md), which also covers re-making the
iOS profile and renewing the certificate.

## What exists

| | |
| --- | --- |
| Package | `apps/mobile`, pubspec name `reward`, on the pub workspace with `packages/domain` |
| Application id | `com.helpmebrands.reward` on both platforms (`PRODUCT_BUNDLE_IDENTIFIER` in `ios/Runner.xcodeproj`, `applicationId` in `android/app/build.gradle.kts`) |
| Display name | `Reward` (`CFBundleDisplayName`); the product name is HelpMe Reward |
| Version | `version: 1.0.0+1` in `apps/mobile/pubspec.yaml` |
| Flutter | pinned in `.fvmrc` at the root, used by `fvm flutter` locally and by CI; minimum 3.35 (AGENTS.md rule 9) |
| Minimum iOS | 15.0 (`IPHONEOS_DEPLOYMENT_TARGET` in `ios/Runner.xcodeproj`); Xcode 27 refuses anything lower |
| CI | the `flutter` job of `verify.yml`: `flutter analyze --fatal-infos` and `flutter test` on every pull request and before every deploy |
| CD | `release-mobile.yml` on a `v*` tag: Android to the Play internal track, iOS to TestFlight (*Getting it to testers*) |
| Signing | nothing in the repository. Secret Manager holds one container per piece of signing material (`reward-app-<name>-staging`, declared in `infra/index.ts`), readable by the deployer and filled by hand ([08](08-mobile-setup.md)) |
| Store accounts | an App Store Connect record for `com.helpmebrands.reward` (first TestFlight build 2026-09-22); a Play publisher identity, `reward-app-play-staging@…`, assumed keylessly from this repository, to be linked in Play Console once the Play record exists (#115). Both are set up in [08](08-mobile-setup.md) |

The api it will talk to is `reward-api` ([README](README.md#environments));
device registration is `POST /v1/devices` with the FCM token, an installation
id the app generates, `ios` or `android`, and the IANA zone. The server sends
reminders from the Cloud Run job `reward-api-remind`; setting it up is
[08 §3.6 and §3.7](08-mobile-setup.md#36-the-apns-key-for-push).

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
$ brew tap leoafarias/fvm && brew install fvm   # once per machine
$ fvm install                        # at the repository root: fetches the version in .fvmrc
$ cd apps/mobile
$ fvm flutter --version              # must match .fvmrc; the first run also fills the SDK cache that `fvm dart` needs
$ fvm dart pub get
$ fvm flutter analyze --fatal-infos
$ fvm flutter test
```

**iOS** needs a Mac with Xcode, an Apple Developer Program membership and an
App Store Connect record for `com.helpmebrands.reward`. iOS and macOS
dependencies are Swift Package Manager, never CocoaPods (rule 9).

```sh
$ fvm flutter build ipa --release    # writes build/ios/ipa/*.ipa
```

The first time, open `ios/Runner.xcworkspace` in Xcode, sign in under
*Signing & Capabilities* with the team that owns the bundle id, and tick
*Automatically manage signing*; Xcode creates the certificate and profile.
Push notifications need the *Push Notifications* capability on the app id and
an APNs key uploaded to Firebase; both are in
[08](08-mobile-setup.md#36-the-apns-key-for-push).

**Android** needs an upload keystore and a Play Console record. The keystore
is generated once and stored only in Secret Manager ([08, step
2.3](08-mobile-setup.md#23-the-upload-keystore)). A signed build on a laptop
needs `android/key.properties` written first; [08, step
2.4](08-mobile-setup.md#24-the-first-bundle-by-hand) has the numbered steps,
including the check that `android/app/build.gradle.kts` reads that file,
which it does not yet (#115). Without it:

```sh
$ fvm flutter build appbundle --release  # writes build/app/outputs/bundle/release/app-release.aab, debug-signed
```

## Getting it to testers

Tag `develop`. `release-mobile.yml` does the rest: one job builds the
signed app bundle on Linux and uploads it to the Play internal testing
track, the other builds, signs and uploads the iOS archive to TestFlight on
a macOS runner, both in the `staging` environment with the signing material
fetched from Secret Manager at build time.

```sh
$ git checkout develop && git pull
$ git tag v0.1.0-rc.1
$ git push origin v0.1.0-rc.1
$ gh run watch                     # pick the "Release mobile" run
```

The workflow refuses any ref but a `v*` tag: its first job fails before
either platform builds. A build from a branch would reach the stores under a
name no tag gave it, as 1.0.0 (2) from `develop` once did, and it could only
be expired by hand. *Run workflow* in the Actions tab is for rerunning a
tag: pick the tag, not a branch, under *Use workflow from*.

The **build name** is the tag without `v` and without any pre-release
suffix (`v0.1.0-rc.1` builds `0.1.0`), because the stores accept only
`x.y.z` there. The **build number** is the workflow run number, so it always
rises, and a rerun of the same tag carries the same number: the store
rejects it as a duplicate rather than shipping the build twice. The
`version:` line in `pubspec.yaml` is not used by the workflow; keep it
sensible for local builds.

**When it arrives.** Internal testers on TestFlight (members of the team in
App Store Connect) get the build without review once Apple's processing
finishes; the iOS job waits for processing, so a build Apple rejects fails
the run rather than a tester's afternoon. The Play internal track is live
within minutes and needs no review. The export compliance answer is in
`Info.plist` (`ITSAppUsesNonExemptEncryption` is `false`, because the app
only speaks HTTPS to its own api), so Apple never holds a build at *Missing
Compliance* and fastlane does not wait for a second round of processing.
Add testers once, in each console; the workflow never touches tester lists.
Promote to closed or open testing, or to an external TestFlight group, from
the consoles when it is time.

**When Apple rejects the build in processing.** The run's iOS job fails on
`upload_to_testflight` with Apple's reason: most often a missing usage
description in `Info.plist`, an icon problem, or an export compliance
question. Fix on a branch, merge, tag again. The Play job of the same tag
has already succeeded and needs nothing.

**When the store says the number exists.** The run was rerun, or someone
uploaded by hand from a laptop with a higher number. Tag a new version; do
not lower anything.

## What CI does and does not do

The verify gate proves the app analyses and its widget tests pass on Linux,
on every pull request. It does not build a release and does not run on a
device or simulator.

`release-mobile.yml` runs only on a `v*` tag. Android: `flutter build
appbundle` with the keystore written to `android/key.properties` in the
runner, then `apps/mobile/scripts/play-upload.sh`, which drives the Play
Developer API with a token minted keylessly as the Play publisher identity
(fastlane's `supply` wants a service-account key file, which this project
does not have). iOS: `flutter build ios --no-codesign`, then the `beta` lane
in `apps/mobile/ios/fastlane/Fastfile` imports the certificate into a
throwaway keychain, installs the profile, archives with manual signing and
uploads with the App Store Connect API key. Both jobs read the material
from Secret Manager as the deployer and reference no GitHub secret; a
leaked log has nothing durable in it. Rule 9 holds: fastlane is a Ruby tool
on the runner, not a pub package.

## Rules that apply

From AGENTS.md rule 9: Dart formatted with `fvm dart format .`; only Flutter
Favourite packages without a human's approval; Swift Package Manager, not
CocoaPods; Material, not Cupertino; every widget has a Widget Preview;
minimum Flutter 3.35. A release build that needed an exception to any of
these is a conversation, not a commit.
