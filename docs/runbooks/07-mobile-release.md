# 07 — Mobile release

Getting a build of the Flutter app in `apps/mobile` to testers, and what is
and is not automated. The release is a tag push (*Getting it to testers*);
the store records, the signing material and the Play Console link are
one-time hand steps this runbook spells out, and it says where a step has
not been taken yet.

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
$ brew tap leoafarias/fvm && brew install fvm   # once per machine
$ fvm install                        # at the repository root: fetches the version in .fvmrc
$ cd apps/mobile
$ fvm flutter --version              # must match .fvmrc; the first run also fills the SDK cache that `fvm dart` needs
$ fvm dart pub get
$ fvm flutter analyze --fatal-infos
$ fvm flutter test
```

Both stores key everything on the application id, so there is **one record
per app, not per environment**: staging and production are different builds
of `com.helpmebrands.reward` sent to different tracks and TestFlight groups.
A staging app that installs beside the production one would need a second id
through Flutter flavors, which is a product decision, not a runbook step.

**iOS** needs a Mac with Xcode, an Apple Developer Program membership and an
App Store Connect record for `com.helpmebrands.reward`. iOS and macOS
dependencies are Swift Package Manager, never CocoaPods (rule 9).

```sh
$ fvm flutter build ipa --release    # writes build/ios/ipa/*.ipa
```

The first time, open `ios/Runner.xcworkspace` in Xcode, sign in under
*Signing & Capabilities* with the team that owns the bundle id, and tick
*Automatically manage signing*; Xcode creates the certificate and profile.
Push notifications will need the *Push Notifications* capability and an APNs
key uploaded to Firebase, which is part of wiring FCM and not of this runbook.

**Android** needs an upload keystore and a Play Console record. The keystore
is generated once and stored only in Secret Manager; *Signing material*
below has the exact commands. For a local signed build, fetch it and write
`android/key.properties` the way `release-mobile.yml` does. `android/key.properties` names them and is
gitignored by the Flutter template; `android/app/build.gradle.kts` needs the
standard `signingConfigs.release` block reading it before the next command
produces a signed bundle.

```sh
$ fvm flutter build appbundle --release  # writes build/app/outputs/bundle/release/app-release.aab
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

The procedure below goes from nothing to nine versions. Work in a scratch
directory outside the repository, delete it when the versions are in, and
never paste a password on a command line where the shell history keeps it.
Binary files (`.jks`, `.p12`, `.p8`, `.mobileprovision`) go in as they are;
Secret Manager stores bytes. Rotation is a new version, and the workflow
always reads `latest`.

Every secret id in the table is `reward-app-<name>-<stack>`, the
`secretId` the stack declares in `infra/index.ts`, so the commands below
name them through `$STACK`. Set it, with the project, before any of them:

```sh
$ export PROJECT_ID=helpme-reward-staging
$ export STACK=staging
$ mkdir -p ~/reward-signing && cd ~/reward-signing
$ gcloud secrets list --project "$PROJECT_ID" --filter="name~reward-app-.*-$STACK" \
    --format='value(name)'          # the nine ids from the table; if not, apply the stack first
```

### Android: the upload keystore

Play App Signing is on by default for a new app: Google holds the key that
signs what users install, and this keystore is only the **upload** key that
proves a bundle came from you. Losing it is recoverable through Play support;
leaking it means rotating it there.

```sh
$ keytool -genkey -v -keystore upload.jks -keyalg RSA -keysize 2048 \
    -validity 10000 -alias upload
```

`keytool` prompts for a keystore password and, since Java 9, uses the same
password for the key unless you say otherwise; the workflow sends both, so
answer both prompts even if the answers match. The alias must be `upload`,
which `release-mobile.yml` writes into `key.properties`. Then:

```sh
$ gcloud secrets versions add reward-app-android-upload-keystore-$STACK \
    --project "$PROJECT_ID" --data-file upload.jks
$ read -rs KEYSTORE_PASSWORD; printf '%s' "$KEYSTORE_PASSWORD" | gcloud secrets versions add \
    reward-app-android-keystore-password-$STACK --project "$PROJECT_ID" --data-file -
$ read -rs KEY_PASSWORD; printf '%s' "$KEY_PASSWORD" | gcloud secrets versions add \
    reward-app-android-key-password-$STACK --project "$PROJECT_ID" --data-file -
```

`read -rs` takes the value from the keyboard without echoing it or
recording it.

**First upload quirk.** The Play Console creates the app record but the Play
Developer API cannot; and the console may insist that the very first bundle
of a new app arrives through its own upload page, which is where Play App
Signing enrolment happens. If the release workflow's first run fails on the
upload step with a message about app signing or a missing release, build
once on a laptop with this keystore (`fvm flutter build appbundle --release`
after writing `android/key.properties` as the workflow does) and upload the
`.aab` by hand under *Testing → Internal testing*. Every run after that goes
through the API.

### iOS: the App Store Connect API key

The key lets the workflow upload to TestFlight without an Apple ID session.
In [App Store Connect](https://appstoreconnect.apple.com), *Users and Access
→ Integrations → App Store Connect API → Team Keys → Generate API Key*: name
it `reward-app release`, role **App Manager**. Download the `.p8` **once**;
Apple never offers it again. On the same page, note the key's **Key ID** and
the page's **Issuer ID**.

```sh
$ gcloud secrets versions add reward-app-asc-api-key-$STACK \
    --project "$PROJECT_ID" --data-file AuthKey_XXXXXXXXXX.p8
$ read -r ASC_KEY_ID; printf '%s' "$ASC_KEY_ID" | gcloud secrets versions add \
    reward-app-asc-api-key-id-$STACK --project "$PROJECT_ID" --data-file -
$ read -r ASC_ISSUER_ID; printf '%s' "$ASC_ISSUER_ID" | gcloud secrets versions add \
    reward-app-asc-issuer-id-$STACK --project "$PROJECT_ID" --data-file -
```

The key id and issuer id are not secret in themselves, but they travel with
the key so the workflow reads all three from one place. `read -r` takes each
id from the keyboard: the first pass of this runbook stored its own inline
placeholder as a version, which is why there are no placeholders here.

### iOS: the distribution certificate

Before any of this, look under *Identifiers* at
[developer.apple.com](https://developer.apple.com/account) for
`com.helpmebrands.reward`. If the app has ever been run on a device from
Xcode with automatic signing it is already there, named
`XC com helpmebrands reward`; use that entry. Do not register a second id
under a friendlier name: a profile made for any other identifier fails the
build at signing time, and the first pass of this runbook did exactly that.
If the id is genuinely missing, register it (App IDs, explicit,
`com.helpmebrands.reward`). Either way the *Push Notifications* capability
goes on it, by hand or by the script in the next subsection. Then create the
app record in App Store Connect under *Apps → +* with that id; the record is
the one thing in this section that only the web UI can create, and
`upload_to_testflight` fails without it.

The certificate is an **Apple Distribution** certificate with its private
key, exported as a password-protected `.p12`. The Fastfile signs with the
identity name `Apple Distribution`, so it must be that type, not the older
*iOS Distribution*.

1. On the Mac, *Keychain Access → Certificate Assistant → Request a
   Certificate From a Certificate Authority*: your email, common name
   `HelpMe Reward release`, *Saved to disk*. This creates the private key in
   the login keychain and a `.certSigningRequest` file.
2. At developer.apple.com, *Certificates → +*, choose **Apple Distribution**,
   upload the request, download `distribution.cer`, double-click it so it
   pairs with the private key in Keychain Access.
3. In Keychain Access, *My Certificates*, right-click the `Apple
   Distribution: HelpMe Brands …` entry, *Export*, format `.p12`, and set a
   password when asked. That password is the certificate password below.

```sh
$ gcloud secrets versions add reward-app-ios-distribution-cert-$STACK \
    --project "$PROJECT_ID" --data-file distribution.p12
$ read -rs CERT_PASSWORD; printf '%s' "$CERT_PASSWORD" | gcloud secrets versions add \
    reward-app-ios-cert-password-$STACK --project "$PROJECT_ID" --data-file -
```

Distribution certificates last a year. Put the date in the README table;
when it passes, repeat this subsection and the next.

### iOS: the provisioning profile

Either at developer.apple.com, *Profiles → +*, choose **App Store Connect**
under Distribution, the `com.helpmebrands.reward` app id, the certificate
from the previous step, name `HelpMe Reward App Store`, download
`HelpMe_Reward_App_Store.mobileprovision`; or let the App Store Connect API
key from two subsections up do it, which cannot pick the wrong app id. The
script below adds the Push Notifications capability to the id and generates
the profile with the team's distribution certificate; it needs only Ruby's
standard library, and `ASC_KEY_PATH` is the `.p8`.

```ruby
# Adds the Push Notifications capability to the app id and generates its App
# Store profile with the team's distribution certificate, through the App
# Store Connect API key. Usage: ruby asc-profile.rb <bundle id> <profile name> <out.mobileprovision>
require 'openssl'; require 'json'; require 'base64'; require 'net/http'
kid, iss, p8 = ENV.fetch('ASC_KEY_ID'), ENV.fetch('ASC_ISSUER_ID'), ENV.fetch('ASC_KEY_PATH')
b64 = ->(s) { Base64.urlsafe_encode64(s, padding: false) }
now = Time.now.to_i
signing = "#{b64.({ alg: 'ES256', kid: kid, typ: 'JWT' }.to_json)}.#{b64.({ iss: iss, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' }.to_json)}"
der = OpenSSL::PKey.read(File.read(p8)).sign(OpenSSL::Digest.new('SHA256'), signing)
jwt = "#{signing}.#{b64.(OpenSSL::ASN1.decode(der).value.map { |v| v.value.to_s(2).rjust(32, "\0") }.join)}"
api = lambda do |method, path, body = nil|
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  req = Net::HTTP.const_get(method).new(uri, 'Authorization' => "Bearer #{jwt}", 'Content-Type' => 'application/json')
  req.body = body.to_json if body
  JSON.parse(Net::HTTP.start(uri.host, 443, use_ssl: true) { |h| h.request(req) }.body)
end
bundle = api.(:Get, "/v1/bundleIds?filter[identifier]=#{ARGV[0]}").fetch('data').fetch(0).fetch('id')
cert = api.(:Get, '/v1/certificates?filter[certificateType]=DISTRIBUTION').fetch('data').fetch(0).fetch('id')
api.(:Post, '/v1/bundleIdCapabilities', data: { type: 'bundleIdCapabilities', attributes: { capabilityType: 'PUSH_NOTIFICATIONS' },
  relationships: { bundleId: { data: { type: 'bundleIds', id: bundle } } } })
profile = api.(:Post, '/v1/profiles', data: { type: 'profiles', attributes: { name: ARGV[1], profileType: 'IOS_APP_STORE' },
  relationships: { bundleId: { data: { type: 'bundleIds', id: bundle } }, certificates: { data: [{ type: 'certificates', id: cert }] } } })
File.binwrite(ARGV[2], Base64.decode64(profile.fetch('data').fetch('attributes').fetch('profileContent')))
```

```sh
$ ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=AuthKey_XXXXXXXXXX.p8 \
    ruby asc-profile.rb com.helpmebrands.reward 'HelpMe Reward App Store' \
    HelpMe_Reward_App_Store.mobileprovision
```

Whichever way it was made, **verify the profile is for the app** before it
goes anywhere near Secret Manager. The one line that matters is
`application-identifier`:

```sh
$ security cms -D -i HelpMe_Reward_App_Store.mobileprovision | plutil -p - \
    | grep -E 'application-identifier|aps-environment|ExpirationDate'
    "application-identifier" => "LMFUSVPCDH.com.helpmebrands.reward"
    "aps-environment" => "production"
  "ExpirationDate" => 2027-09-21 14:44:44 +0000
```

If the identifier is anything but the team id followed by
`com.helpmebrands.reward`, the profile was made for another app id; make it
again. The Fastfile reads the team id and the profile name out of this file,
so nothing else needs configuring.

```sh
$ gcloud secrets versions add reward-app-ios-provisioning-profile-$STACK \
    --project "$PROJECT_ID" --data-file HelpMe_Reward_App_Store.mobileprovision
```

A profile is tied to its certificate: a new certificate means a new profile.

### Check and clean up

Count the versions, then read the two iOS binaries back and prove they are
what the workflow needs: a certificate that imports as a signing identity,
and a profile for the app.

```sh
$ for s in $(gcloud secrets list --project "$PROJECT_ID" --filter='name~reward-app-' --format='value(name)'); do
    printf '%s: %s\n' "$s" "$(gcloud secrets versions list "$s" --project "$PROJECT_ID" --filter='state=enabled' --format='value(name)' | wc -l)"
  done
$ gcloud secrets versions access latest --secret reward-app-ios-distribution-cert-$STACK \
    --project "$PROJECT_ID" --out-file check.p12
$ security create-keychain -p '' check.keychain-db
$ security import check.p12 -k check.keychain-db -P "$CERT_PASSWORD" -T /usr/bin/codesign
$ security find-identity -v -p codesigning check.keychain-db
  1) 2B69E218… "Apple Distribution: … (LMFUSVPCDH)"
     1 valid identities found
$ security delete-keychain check.keychain-db
$ gcloud secrets versions access latest --secret reward-app-ios-provisioning-profile-$STACK \
    --project "$PROJECT_ID" --out-file check.mobileprovision
$ security cms -D -i check.mobileprovision | plutil -p - | grep application-identifier
    "application-identifier" => "LMFUSVPCDH.com.helpmebrands.reward"
$ cd ~ && rm -rf ~/reward-signing
```

Every count should read `1`. Read binaries with `--out-file`, never by
redirecting stdout: `gcloud` writes stdout as text and every byte above
`0x7F` comes out as U+FFFD, so a check made that way fails on material that
is fine. The workflow uses `--out-file` and is unaffected.

The keystore and the `.p12` now exist only in Secret Manager and, if you
choose, in a password manager; the `.p8` exists only in Secret Manager,
because Apple will not hand it out twice.

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
