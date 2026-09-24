# 08 — Mobile setup

Everything a person has to do by hand before the first mobile release can
reach testers and people can sign in: the store records, the signing
material, the sign-in credentials and the invite-link domain. **Do it once,
top to bottom, in this order.** Each step says where to click, what to type
and what you should have at the end. The order matters: a step that needs
something made earlier comes after it.

Releasing a build after setup is [07 — Mobile release](07-mobile-release.md).
The sections at the end (*Later: …*) cover what to do when something changes:
a new capability, a certificate that is about to expire, or a key to rotate.

Start this runbook after [01 — Initial deployment](01-initial-deployment.md):
the stack must exist, because it creates the empty Secret Manager containers
and the Play publisher identity used below.

## What you will end up with

Both stores key everything on the application id, so there is **one record
per app, not per environment**. Staging and production are different builds
of `com.helpmebrands.reward`, sent to different tracks and TestFlight groups.
A staging app installed beside the production one would need a second id
(Flutter flavors), which is a product decision, not a runbook step.

| What | Made in | Stored in |
| --- | --- | --- |
| App id `com.helpmebrands.reward` with its capabilities | Apple Developer portal | Apple |
| Sign in with Apple Services ID and key | Apple Developer portal | stack config `appleServicesId`, `appleKeyId`, `appleServicesKey` |
| App Store Connect API key (`.p8`, key id, issuer id) | App Store Connect | Secret Manager `reward-app-asc-*` |
| Apple Distribution certificate (`.p12` and its password) | Keychain Access and the portal | Secret Manager `reward-app-ios-distribution-cert-*`, `reward-app-ios-cert-password-*` |
| App Store provisioning profile | Apple Developer portal | Secret Manager `reward-app-ios-provisioning-profile-*` |
| App Store Connect app record | App Store Connect | Apple |
| Play Console app record | Play Console | Google |
| Upload keystore (`.jks` and its one password) | `keytool` on your Mac | Secret Manager `reward-app-android-*` |
| Play signing key fingerprint | Play Console | stack config `androidSha256Fingerprints` |
| Google OAuth web client | Google Cloud console | stack config `googleOAuthClientId`, `googleOAuthClientSecret` |
| `api.<env>` DNS record | Cloudflare | Cloudflare |

Two kinds of storage, for a reason:

- **Secret Manager** holds what the release workflow needs to sign and
  upload. The stack declares one empty container per secret and lets the
  deployer read exactly those. It never writes a value: you add each value
  once, as a new version, and the workflow always reads `latest`. Nothing
  is stored in GitHub, so a leaked workflow log exposes nothing durable.
- **Stack config** holds what Identity Platform needs for sign-in. Pulumi
  hands it to Identity Platform when it applies, and the api never reads
  it. Secret values are encrypted with the stack's KMS key (runbook 01,
  step 3) before they reach `Pulumi.<stack>.yaml`, so that file stays safe
  to commit.

| Secret Manager id | Holds |
| --- | --- |
| `reward-app-asc-api-key-staging` | the App Store Connect API key, the `.p8` file |
| `reward-app-asc-api-key-id-staging` | its key id |
| `reward-app-asc-issuer-id-staging` | the issuer id |
| `reward-app-ios-distribution-cert-staging` | the distribution certificate with its private key, `.p12` |
| `reward-app-ios-cert-password-staging` | the `.p12` password |
| `reward-app-ios-provisioning-profile-staging` | the App Store provisioning profile, `.mobileprovision` |
| `reward-app-android-upload-keystore-staging` | the upload keystore, `.jks` |
| `reward-app-android-keystore-password-staging` | the keystore password |
| `reward-app-android-key-password-staging` | the `upload` key's password, the same as the keystore's (2.2 says why) |

## Before you start

| Need | Check |
| --- | --- |
| Apple Developer Program membership, team `LMFUSVPCDH`, with the *Admin* or *Account Holder* role | you can open <https://developer.apple.com/account> and <https://appstoreconnect.apple.com> |
| Google Play developer account | you can open <https://play.google.com/console> |
| Owner on the Google Cloud project | `gcloud projects get-iam-policy helpme-reward-staging` lists you |
| Cloudflare access to the `helpmereward.com` zone | you can add a DNS record |
| A Mac with Xcode, `gcloud`, `pulumi`, `jq` and a JDK (for `keytool`) | each answers `--version` |

Open a terminal and set these once. Every command below uses them:

```sh
$ export PROJECT_ID=helpme-reward-staging
$ export STACK=staging
$ mkdir -p ~/reward-signing && cd ~/reward-signing
$ gcloud secrets list --project "$PROJECT_ID" --filter="name~reward-app-.*-$STACK" \
    --format='value(name)'          # the nine ids from the table; if not, apply the stack first
```

Every Secret Manager id is `reward-app-<name>-<stack>`, the `secretId` the
stack declares in `infra/index.ts`, so the commands name them through
`$STACK`. For another environment, change `STACK`, `PROJECT_ID` and the
project id in the URLs.

House rules for the whole runbook:

- Work in `~/reward-signing`. Downloads go there too. Delete the folder at
  the end (Part 4).
- Never type a password or key on a command line, where shell history keeps
  it. The commands use `read -rs`, which takes the value from the keyboard
  without showing or recording it; press Enter after typing.
- Binary files (`.jks`, `.p12`, `.p8`, `.mobileprovision`) go into Secret
  Manager as they are. It stores bytes.
- Apple lets you download a `.p8` key **only once**. Store it before you do
  anything else.

## Part 1 — Apple (iOS)

Everything in this part is at <https://developer.apple.com/account>, under
*Certificates, IDs & Profiles*, unless it says App Store Connect. The
Services ID and the key in steps 1.3 and 1.4 are for sign-in on **both**
platforms; they are made here because Apple is where they live.

### 1.1 Find or register the app id

Go to *Identifiers*. Look for `com.helpmebrands.reward`.

- If the app has ever been run on a device from Xcode, the id is already
  there, named `XC com helpmebrands reward`. **Use that one.** Do not
  register a second id under a friendlier name. A profile made for any other
  identifier fails the build at signing time, and an earlier pass of this
  runbook did exactly that.
- If it is genuinely missing, click **+**, choose *App IDs*, then *App*,
  and register an **explicit** id: `com.helpmebrands.reward`.

### 1.2 Turn on every capability

Open the app id. Tick all three of these, then **Save**:

- [ ] **Push Notifications**. Push delivery is not built yet; turning it on
  now means the profile will not need re-making when it is.
- [ ] **Sign in with Apple**. Keep *Enable as a primary App ID*.
- [ ] **Associated Domains**. Invite links open the app through it.

These must match the app. `apps/mobile/ios/Runner/Runner.entitlements`
declares `com.apple.developer.applesignin` and
`com.apple.developer.associated-domains`; if a later change adds an
entitlement there, tick it here and follow *Later: re-making the iOS
profile*.

**This is the step that must come before the profile (1.7).** A profile
records the capabilities its app id had on the day it was made, and never
learns about new ones.

### 1.3 The Sign in with Apple Services ID

The Services ID lets Android and the web flow use Firebase's sign-in
handler, which every provider sends people back to:

```
https://helpme-reward-staging.firebaseapp.com/__/auth/handler
```

That address only answers after the stack has added Firebase to the project
(Part 3). You can still enter it now: the portal stores it as text and does
not call it.

1. *Identifiers* → **+** → *Services IDs*:
   - Description: `HelpMe Reward sign-in`
   - Identifier: `com.helpmebrands.reward.signin`
2. Register it, open it again, tick **Sign in with Apple**, then
   *Configure*:
   - Primary App ID: `com.helpmebrands.reward`
   - Domains and subdomains: `helpme-reward-staging.firebaseapp.com`
   - Return URLs: `https://helpme-reward-staging.firebaseapp.com/__/auth/handler`
3. Click *Save*, then *Continue*, then *Save* again. Apple discards the
   configuration unless you save the Services ID page as well.
4. Store the id:

   ```sh
   $ cd <your checkout>/infra && pulumi stack select $STACK
   $ pulumi config set reward-app:appleServicesId com.helpmebrands.reward.signin
   ```

The Apple team id is already committed as `reward-app:appleTeamId` in
`Pulumi.staging.yaml`.

### 1.4 The Sign in with Apple key

1. *Keys* → **+**. Name it `reward-app sign-in`, tick **Sign in with
   Apple**, *Configure* it with the primary App ID `com.helpmebrands.reward`,
   and register it.
2. Note the ten-character **Key ID** and download `AuthKey_<KEYID>.p8` into
   `~/reward-signing`. **This is the only chance to download it.**
3. Store both, still in `infra/`:

   ```sh
   $ pulumi config set reward-app:appleKeyId ABCDE12345
   $ pulumi config set --secret reward-app:appleServicesKey < ~/reward-signing/AuthKey_ABCDE12345.p8
   $ rm ~/reward-signing/AuthKey_ABCDE12345.p8
   ```

Optional: to reach people who hide their email behind Apple's relay, register
`noreply@helpme-reward-staging.firebaseapp.com` under *Services → Sign in with
Apple for Email Communication*. Nothing sends email yet.

### 1.5 The App Store Connect API key

This key lets the release workflow upload to TestFlight without anyone
signed in to Apple.

1. At <https://appstoreconnect.apple.com>: *Users and Access → Integrations
   → App Store Connect API → Team Keys → Generate API Key*. Name it
   `reward-app release`, role **App Manager**.
2. Download the `.p8` into `~/reward-signing`. **Only once**, as before.
3. On the same page, note the key's **Key ID** and the page's **Issuer ID**.
4. Store all three. Each `read -r` waits for you to paste the value and
   press Enter:

   ```sh
   $ cd ~/reward-signing
   $ gcloud secrets versions add reward-app-asc-api-key-$STACK \
       --project "$PROJECT_ID" --data-file AuthKey_XXXXXXXXXX.p8
   $ read -r ASC_KEY_ID; printf '%s' "$ASC_KEY_ID" | gcloud secrets versions add \
       reward-app-asc-api-key-id-$STACK --project "$PROJECT_ID" --data-file -
   $ read -r ASC_ISSUER_ID; printf '%s' "$ASC_ISSUER_ID" | gcloud secrets versions add \
       reward-app-asc-issuer-id-$STACK --project "$PROJECT_ID" --data-file -
   ```

The key id and issuer id are not secret in themselves, but they travel with
the key so the workflow reads all three from one place. Keep the `.p8` until
Part 4 if you want to use the command-line route in the appendix; Secret
Manager is its only other copy.

### 1.6 The distribution certificate

An **Apple Distribution** certificate with its private key, exported as a
password-protected `.p12`. The Fastfile signs with the identity name
`Apple Distribution`, so it must be that type, not the older *iOS
Distribution*.

1. On the Mac, open *Keychain Access → Certificate Assistant → Request a
   Certificate From a Certificate Authority*. Enter your email and the
   common name `HelpMe Reward release`, choose *Saved to disk*. This puts
   a private key in your login keychain and a `.certSigningRequest` file in
   the folder you pick.
2. In the portal, *Certificates* → **+** → **Apple Distribution**. Upload
   the request and download `distribution.cer`. Double-click it so it pairs
   with the private key in Keychain Access.
3. In Keychain Access, *My Certificates*, right-click `Apple Distribution:
   HelpMe Brands …` → *Export*. Choose `.p12`, save it as
   `~/reward-signing/distribution.p12`, and set a password when asked. That
   is the certificate password.
4. Store both:

   ```sh
   $ gcloud secrets versions add reward-app-ios-distribution-cert-$STACK \
       --project "$PROJECT_ID" --data-file distribution.p12
   $ read -rs CERT_PASSWORD; printf '%s' "$CERT_PASSWORD" | gcloud secrets versions add \
       reward-app-ios-cert-password-$STACK --project "$PROJECT_ID" --data-file -
   ```

Keep `CERT_PASSWORD` set in this terminal; Part 4 uses it. Note the
certificate's id (the ten characters in its portal URL) and its expiry date
for Part 5. It lasts a year.

### 1.7 The provisioning profile

Only now, with every capability from 1.2 on the app id and the certificate
from 1.6 in place, make the profile. It is made once and carries all of
them.

1. In the portal, *Profiles* → **+**. Under *Distribution* choose **App
   Store Connect**.
2. App ID: `com.helpmebrands.reward` (the `XC com helpmebrands reward` entry).
3. Certificate: the one from 1.6.
4. Name: `HelpMe Reward App Store`. The Fastfile reads the name from inside
   the file, so any name works, but keeping this one keeps the history
   readable.
5. Generate, then download `HelpMe_Reward_App_Store.mobileprovision` into
   `~/reward-signing`. Note the profile's id (in its portal URL) and its
   expiry date for Part 5.

**Check it before it goes anywhere near Secret Manager:**

```sh
$ security cms -D -i HelpMe_Reward_App_Store.mobileprovision | plutil -p - \
    | grep -E 'application-identifier|aps-environment|com.apple.developer.applesignin|com.apple.developer.associated-domains|ExpirationDate'
```

You must see **all five** of these. The values after `=>` for the last
three entitlements do not matter; the names must be there.

- [ ] `"application-identifier" => "LMFUSVPCDH.com.helpmebrands.reward"`.
  Anything else means the profile was made for another app id: delete it
  and make it again from the right one.
- [ ] `"aps-environment"` (Push Notifications)
- [ ] `"com.apple.developer.applesignin"` (Sign in with Apple)
- [ ] `"com.apple.developer.associated-domains"` (Associated Domains)
- [ ] `"ExpirationDate"`, a year from now

A missing entitlement means that capability was not ticked in 1.2 when the
profile was made. Tick it, then follow *Later: re-making the iOS profile*;
do not store this one.

When all five are there:

```sh
$ gcloud secrets versions add reward-app-ios-provisioning-profile-$STACK \
    --project "$PROJECT_ID" --data-file HelpMe_Reward_App_Store.mobileprovision
```

### 1.8 The App Store Connect app record

At <https://appstoreconnect.apple.com>, *Apps* → **+** → *New App*:
platform iOS, name `HelpMe Reward`, bundle id `com.helpmebrands.reward`, a
SKU of your choosing. This is the only Apple step that only the web UI can
do, and `upload_to_testflight` fails without it.

Then add testers under *TestFlight → Internal Testing*: members of the
App Store Connect team get builds without review. The workflow never touches
tester lists.

## Part 2 — Google Play (Android)

> **Not rehearsed yet.** Android's first release is #115. The steps are the
> intended procedure; correct them here when #115 runs them for real. If you
> are not doing Android yet, skip this part, then come back and apply the
> stack again after 2.5.

### 2.1 The Play Console app record

At <https://play.google.com/console>, *Create app*: name `HelpMe Reward`,
app, free. The package name is set by the first upload (2.3) and is
`com.helpmebrands.reward`. Play App Signing is on by default for a new app:
Google holds the key that signs what people install, and your keystore is
only the **upload** key that proves a bundle came from you.

### 2.2 The upload keystore

Losing this keystore is recoverable through Play support; leaking it means
rotating it there.

**The values, and why:**

| Option | Value | Why |
| --- | --- | --- |
| `-keystore` | `upload.jks` | the file name; only you and Secret Manager see it |
| `-storetype` | `PKCS12` | the default since Java 9, written out so an old JDK cannot pick the legacy JKS format |
| `-alias` | `upload` | `release-mobile.yml` writes this alias into `key.properties`; any other fails the build |
| `-keyalg`, `-keysize` | `RSA`, `2048` | what Play and Flutter's own guide use |
| `-validity` | `10000` | days, about 27 years; an upload key should outlive the app |
| `-dname` | `CN=HelpMe Reward upload, O=HelpMe Brands` | the certificate's owner. Nobody sees it, Play does not check it, and giving it here skips the six name, city and country questions |
| password | 20 or more random characters (keytool's minimum is 6) | made below and kept in your password manager |

**One password, not two.** A PKCS12 keystore cannot give the key a
password of its own: keytool uses the keystore password for the key and
ignores `-keypass` with a warning. The release workflow still reads two
secrets, the keystore password and the key password, so both get the same
value.

1. Make the password and save it in your password manager, as *HelpMe
   Reward Android upload keystore*:

   ```sh
   $ openssl rand -base64 24
   ```

2. Make the keystore. keytool asks for the password twice; paste it both
   times. It asks nothing else, because `-dname` answered the rest:

   ```sh
   $ cd ~/reward-signing
   $ keytool -genkeypair -v -keystore upload.jks -storetype PKCS12 \
       -alias upload -keyalg RSA -keysize 2048 -validity 10000 \
       -dname "CN=HelpMe Reward upload, O=HelpMe Brands"
   ```

3. Check it. You should see `Keystore type: PKCS12`, `Alias name: upload`
   and a *Valid until* about 27 years away:

   ```sh
   $ keytool -list -v -keystore upload.jks | grep -E 'Keystore type|Alias name|Owner|until'
   ```

4. Store the keystore, then the password **into both password secrets**.
   `read -rs` waits for you to paste it and press Enter:

   ```sh
   $ gcloud secrets versions add reward-app-android-upload-keystore-$STACK \
       --project "$PROJECT_ID" --data-file upload.jks
   $ read -rs KEYSTORE_PASSWORD
   $ printf '%s' "$KEYSTORE_PASSWORD" | gcloud secrets versions add \
       reward-app-android-keystore-password-$STACK --project "$PROJECT_ID" --data-file -
   $ printf '%s' "$KEYSTORE_PASSWORD" | gcloud secrets versions add \
       reward-app-android-key-password-$STACK --project "$PROJECT_ID" --data-file -
   ```

### 2.3 The first bundle, by hand

The Play Developer API cannot create an app's first release, and the
console may insist that the very first bundle arrives through its own upload
page, which is where Play App Signing enrolment happens. Build once on the
Mac with this keystore (`fvm flutter build appbundle --release` in
`apps/mobile`, after writing `android/key.properties` the way
`release-mobile.yml` does) and upload the `.aab` under *Testing → Internal
testing → Create new release*. Every release after that goes through the
workflow. Add testers on the same page.

### 2.4 Link the Play publisher identity

The release workflow uploads as a Google Cloud service account that it
assumes keylessly, so no key file exists. The stack created it:

```sh
$ gcloud iam service-accounts list --project "$PROJECT_ID" \
    --filter='email~^reward-app-play-' --format='value(email)'
```

In Play Console, *Users and permissions → Invite new users*: that email, with
*Release to testing tracks* on this app. Until the app record exists there
is nothing to link to. The email is also on the GitHub environment as
`PLAY_SERVICE_ACCOUNT`, and every secret id as `SECRET_<NAME>`, for the
workflow to read.

### 2.5 The signing key fingerprint

Android opens invite links in the app only if the api's domain lists the
app's signing certificate in `/.well-known/assetlinks.json`. Once 2.3 has
enrolled the app in Play App Signing, copy the **app signing key**
certificate's SHA-256 fingerprint from *Test and release → App integrity*:

```sh
$ pulumi config set reward-app:androidSha256Fingerprints AA:BB:…
```

Several fingerprints go in comma separated. Part 3 applies it.

## Part 3 — Sign-in and invite links, both platforms

People sign in with Google or Apple through Firebase Authentication on
Identity Platform in the stack's own project. The Pulumi stack turns
Identity Platform on, registers the iOS and Android apps with Firebase, and
declares both providers once their credentials are in the stack config.
This part supplies the last credential, the invite-link domain, and applies.

### 3.1 The Google OAuth client

Identity Platform's `google.com` provider needs a **web** OAuth client, even
for the phone apps: the Firebase SDK on both platforms runs Google's sign-in
through the handler, not through a platform client.

1. **Branding.** In the Google Cloud console for the project, *Google Auth
   Platform → Branding*. App name `HelpMe Reward`, a support email you read,
   and the developer contact. Under *Authorised domains*, add
   `helpme-reward-staging.firebaseapp.com`.
2. **Audience.** Choose *External*. Staging can stay in *Testing*, but then
   only the test users listed on this page can sign in, up to 100. Add every
   tester's Google account. Production must be published, which may need
   Google's verification of the branding.
3. **Client.** *Google Auth Platform → Clients → Create client*:
   - Application type: *Web application*
   - Name: `reward-app sign-in (staging)`
   - Authorised JavaScript origins: `https://helpme-reward-staging.firebaseapp.com`
   - Authorised redirect URIs: `https://helpme-reward-staging.firebaseapp.com/__/auth/handler`

   The dialog shows the client id and the client secret once. Copy both.
4. **Store them**, in `infra/`:

   ```sh
   $ pulumi config set reward-app:googleOAuthClientId 1234567890-abc.apps.googleusercontent.com
   $ read -rs GOOGLE_SECRET && printf '%s' "$GOOGLE_SECRET" | pulumi config set --secret reward-app:googleOAuthClientSecret && unset GOOGLE_SECRET
   ```

### 3.2 The invite-link domain

An invite link, `https://api.staging.helpmereward.com/invite/<code>`, opens
the app only when that domain serves the association files for iOS and
Android. The api serves them; the domain needs pointing at it.

1. The parent domain must already be verified in Search Console by the
   account that runs `pulumi up`
   ([03, *Adding a custom domain*](03-infrastructure-change.md#adding-a-custom-domain),
   step 2). `gcloud domains list-user-verified` lists it if so.
2. The stack config names the domain. For staging it is committed; for
   another stack:

   ```sh
   $ pulumi config set reward-app:apiCustomDomain api.<env>.helpmereward.com
   ```

3. In Cloudflare, add a CNAME `api.staging` → `ghs.googlehosted.com`,
   **DNS only** (grey cloud), beside the existing `staging` record. With the
   orange cloud on, the certificate never issues.

The app's side is already in the code: `Runner.entitlements` names
`applinks:api.staging.helpmereward.com`, and the Android manifest has an
`autoVerify` intent filter for the same host. Another domain means changing
both.

### 3.3 Apply the stack

Commit the changed `Pulumi.<stack>.yaml` on a branch and open a pull
request. CI's preview should show the two sign-in providers and the domain
mapping. After the merge, apply it the way runbook 03 describes:

```sh
$ git checkout develop && git pull
$ cd infra
$ USER_PROJECT_OVERRIDE=true GOOGLE_BILLING_PROJECT=$PROJECT_ID pulumi up --refresh
```

### 3.4 The Apple sign-in config

The Pulumi provider (`@pulumi/gcp` 8.41) declares the `apple.com` provider
with its Services ID only. It has no field for `appleSignInConfig`, which
holds the bundle ids allowed to use native sign-in on iOS and the key that
Android and the web flow need. Set it once after the first apply, and again
whenever the key is rotated:

```sh
$ jq -n \
    --arg team "$(pulumi config get reward-app:appleTeamId)" \
    --arg key "$(pulumi config get reward-app:appleKeyId)" \
    --arg pem "$(pulumi config get reward-app:appleServicesKey)" \
    '{appleSignInConfig: {bundleIds: ["com.helpmebrands.reward"],
      codeFlowConfig: {teamId: $team, keyId: $key, privateKey: $pem}}}' \
  | curl -sS -X PATCH \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H "x-goog-user-project: $PROJECT_ID" \
    -H 'Content-Type: application/json' \
    --data-binary @- \
    "https://identitytoolkit.googleapis.com/admin/v2/projects/$PROJECT_ID/defaultSupportedIdpConfigs/apple.com?updateMask=appleSignInConfig"
```

The response echoes the provider with `appleSignInConfig.bundleIds` filled
in. Identity Platform does not return the private key.

### 3.5 The Firebase options (a new project only)

For staging this is done: `apps/mobile/lib/firebase_options.dart` and the
URL scheme in `Info.plist` carry staging's values. A new project has new
Firebase app ids, so copy them in:

```sh
$ pulumi stack output firebaseIosAppId
$ pulumi stack output firebaseIosApiKey
$ pulumi stack output firebaseAndroidAppId
$ pulumi stack output firebaseAndroidApiKey
$ pulumi stack output firebaseIosUrlScheme
```

The first four are the defaults in `firebase_options.dart` (the sender id
is the project number, the middle part of either app id), and a release
for another environment can pass them as `--dart-define`s instead. The URL
scheme goes in `CFBundleURLSchemes` in `apps/mobile/ios/Runner/Info.plist`;
Google sign-in on iOS returns to the app through it. None of these is a
secret: they ship in every copy of the app.

## Part 4 — Check everything

Each check proves a step that can fail silently.

**Every secret has a version.** Each count should be at least `1`:

```sh
$ for s in $(gcloud secrets list --project "$PROJECT_ID" --filter="name~reward-app-.*-$STACK" --format='value(name)'); do
    printf '%s: %s\n' "$s" "$(gcloud secrets versions list "$s" --project "$PROJECT_ID" --filter='state=enabled' --format='value(name)' | wc -l)"
  done
```

**The certificate imports as a signing identity, and the stored profile is
the one you checked.** Read the binaries back with `--out-file`, never by
redirecting stdout: `gcloud` writes stdout as text and every byte above
`0x7F` comes out as U+FFFD, so a check made that way fails on material that
is fine. The workflow uses `--out-file` and is unaffected.

```sh
$ cd ~/reward-signing
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
$ security cms -D -i check.mobileprovision | plutil -p - \
    | grep -E 'application-identifier|com.apple.developer.applesignin|com.apple.developer.associated-domains'
```

The last command must show the same three names as in 1.7.

**Both sign-in providers are on:**

```sh
$ curl -sS -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H "x-goog-user-project: $PROJECT_ID" \
    "https://identitytoolkit.googleapis.com/admin/v2/projects/$PROJECT_ID/defaultSupportedIdpConfigs" \
  | jq '.defaultSupportedIdpConfigs[] | {name, enabled, clientId}'
```

**The invite-link domain serves the association files.** The certificate
takes up to an hour after the DNS record; `pulumi stack output
apiCustomDomainStatus` names the record until it is done.

```sh
$ curl -sS https://api.staging.helpmereward.com/.well-known/apple-app-site-association
$ curl -sS https://api.staging.helpmereward.com/.well-known/assetlinks.json
```

The first answers JSON naming `LMFUSVPCDH.com.helpmebrands.reward`; the
second lists the fingerprint from 2.5.

**Clean up.** The keystore and the `.p12` now exist only in Secret Manager
and, if you choose, in a password manager; the `.p8` files exist only in
Secret Manager and the stack config.

```sh
$ unset CERT_PASSWORD KEYSTORE_PASSWORD
$ cd ~ && rm -rf ~/reward-signing
```

## Part 5 — Write it down

Update the *iOS signing* row of the [README](README.md#environments) with
the certificate id and profile id from 1.6 and 1.7 and their expiry date.
`apps/pwa/tests/infra-config.test.ts` pins that date (*records the iOS
certificate expiry*), so change it there in the same pull request.

## Part 6 — The first release

Tag `develop` as [07](07-mobile-release.md#getting-it-to-testers) describes.
When the build arrives, sign in with Google and with Apple, and open an
invite link on the device. A `redirect_uri_mismatch` from Google, or
`invalid_client` from Apple, means the handler address in that console does
not match the one in 1.3 exactly.

## Later: re-making the iOS profile

Do this when any of these happens:

- A release fails in the iOS job with
  `Provisioning profile "HelpMe Reward App Store" doesn't include the <…> entitlement`.
  The app asks for a capability the profile was made without.
- `Runner.entitlements` gains an entitlement.
- The certificate was renewed (next section): a profile is tied to its
  certificate.
- The profile is about to expire.

1. **Tick the capability.** If a capability is missing, open the app id
   (1.2), tick it and save. Changing the app id makes existing profiles for
   it invalid; that is expected.
2. **Delete the old profile.** In the portal, *Profiles*, open `HelpMe
   Reward App Store` and remove it, so only one profile carries the name.
   Secret Manager still holds its copy until step 5.
3. **Make the new one**: 1.7, steps 1 to 5, with the same name.
4. **Check it**, with the `security cms -D` command in 1.7. All five lines
   must be there before you go on.
5. **Store it**, and disable the old version so only the new one is live:

   ```sh
   $ gcloud secrets versions add reward-app-ios-provisioning-profile-$STACK \
       --project "$PROJECT_ID" --data-file HelpMe_Reward_App_Store.mobileprovision
   $ gcloud secrets versions list reward-app-ios-provisioning-profile-$STACK \
       --project "$PROJECT_ID"         # the newest is first; note the one below it
   $ gcloud secrets versions disable <previous-version> \
       --secret reward-app-ios-provisioning-profile-$STACK --project "$PROJECT_ID"
   ```

6. **Check the stored copy** with the profile lines of Part 4, then delete
   the local file.
7. **Write it down** as in Part 5: the new profile id and expiry in the
   *iOS signing* row of the README and, if the date changed, in its test.
   One pull request.
8. **Release again.** If Apple never received a build from the failed run,
   re-run its failed jobs; the run number, and so the build number, stay the
   same:

   ```sh
   $ gh run rerun <run-id> --failed
   ```

   Otherwise tag a new version (`git tag v…`, as in 07).

## Later: renewing the certificate

Distribution certificates last a year; the README row has the date. A few
weeks before it:

1. Make a new certificate and store it: 1.6, all four steps. The `.p12` and
   its password are two new secret versions.
2. Re-make the profile with the new certificate: *Later: re-making the iOS
   profile*, steps 2 to 8.
3. Once a release signed with the new pair reaches TestFlight, revoke the
   old certificate in the portal.

## Later: rotating keys and secrets

- **Google OAuth secret.** Add a new secret to the same client in *Clients*,
  set it with the `--secret` command in 3.1, apply, then delete the old
  secret in the console.
- **Sign in with Apple key.** Make a new key (1.4), set `appleKeyId` and
  `appleServicesKey`, apply, run the PATCH in 3.4 again, then revoke the old
  key. Apple allows two Sign in with Apple keys per team at once.
- **App Store Connect API key.** Generate a new one (1.5), add its `.p8`
  and key id as new versions (the issuer id does not change), release once,
  then revoke the old key.
- **Upload keystore.** Rotation goes through Play support; follow their
  instructions, then store the new keystore and passwords as in 2.2.

## Appendix: the profile from the command line

Instead of the portal clicks in 1.7, the App Store Connect API key from 1.5
can make the profile. It cannot pick the wrong app id. It still needs 1.2
done first; it also turns on Push Notifications, which is harmless if that
is already on. It needs only Ruby's standard library, and `ASC_KEY_PATH` is
the `.p8`.

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
$ export ASC_KEY_ID ASC_ISSUER_ID     # read in 1.5; if this is a new terminal, read -r them again first
$ ASC_KEY_PATH=AuthKey_XXXXXXXXXX.p8 ruby asc-profile.rb com.helpmebrands.reward 'HelpMe Reward App Store' \
    HelpMe_Reward_App_Store.mobileprovision
```

The script picks the first distribution certificate on the team; with two
(during a renewal) make the profile in the portal instead. Then check and
store it exactly as in 1.7.
