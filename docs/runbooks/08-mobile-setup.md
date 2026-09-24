# 08 — Mobile setup

Everything a person has to do by hand so that the mobile app can reach
testers and people can sign in: the store records, the signing material,
the sign-in credentials and the invite-link domain. **Do it once, top to
bottom, in this order.** Every numbered step can be done as soon as the step
above it is finished; nothing depends on a step further down.

Releasing a build is [07 — Mobile release](07-mobile-release.md). The
sections at the end (*Later: …*) cover what to do when something changes:
a new capability, a certificate that is about to expire, or a key to rotate.

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
| `reward-app-android-key-password-staging` | the `upload` key's password, the same as the keystore's (2.3 says why) |

## Before you start

| Need | Check |
| --- | --- |
| [01 — Initial deployment](01-initial-deployment.md) is done: the stack exists and made the empty secret containers and the Play publisher identity | the last command in the block below lists nine ids |
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
    --format='value(name)'
```

The last command must print the nine ids from the table above. Fewer means
the stack is not applied: stop here and finish runbook 01.

Every Secret Manager id is `reward-app-<name>-<stack>`, the `secretId` the
stack declares in `infra/index.ts`, so the commands name them through
`$STACK`. For another environment, change `STACK`, `PROJECT_ID` and the
project id in the URLs.

House rules for the whole runbook:

- Work in `~/reward-signing`. Downloads go there too. Delete the folder at
  the end (Part 4).
- Never type a password or key on a command line, where shell history keeps
  it. The commands use `read -rs`: it waits, you paste the value (nothing
  shows), you press Enter.
- Binary files (`.jks`, `.p12`, `.p8`, `.mobileprovision`) go into Secret
  Manager as they are. It stores bytes.
- Apple lets you download a `.p8` key **only once**. The step that
  downloads one stores it in its very next numbered step.

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
- If it is genuinely missing, register it:
  1. Click **+**.
  2. Choose *App IDs* → *Continue*.
  3. Choose *App* → *Continue*.
  4. Description `HelpMe Reward`, *Explicit*, Bundle ID `com.helpmebrands.reward`.
  5. Click *Continue*, then *Register*. Leave the capabilities for 1.2.

### 1.2 Turn on every capability

A profile records the capabilities its app id had on the day it was made,
and never learns about new ones. That is why this step comes long before
the profile (1.7).

1. Open the app id from 1.1.
2. Tick **Push Notifications**. Push delivery is not built yet; turning it
   on now means the profile will not need re-making when it is.
3. Tick **Sign in with Apple**. Keep *Enable as a primary App ID*.
4. Tick **Associated Domains**. Invite links open the app through it.
5. Click **Save**, and confirm if asked.

These must match the app: `apps/mobile/ios/Runner/Runner.entitlements`
declares `com.apple.developer.applesignin` and
`com.apple.developer.associated-domains`. A later change that adds an
entitlement there is handled by *Later: re-making the iOS profile*.

### 1.3 The Sign in with Apple Services ID

The Services ID lets Android and the web flow use Firebase's sign-in
handler, which every provider sends people back to:

```
https://helpme-reward-staging.firebaseapp.com/__/auth/handler
```

That address does not answer yet; Part 3 makes it. Enter it anyway: the
portal stores it as text and does not call it.

1. *Identifiers* → **+** → *Services IDs* → *Continue*.
2. Description `HelpMe Reward sign-in`, Identifier
   `com.helpmebrands.reward.signin`.
3. Click *Continue*, then *Register*.
4. Open `com.helpmebrands.reward.signin` from the list.
5. Tick **Sign in with Apple** and click its *Configure* button.
6. Primary App ID: `com.helpmebrands.reward`.
7. Domains and subdomains: `helpme-reward-staging.firebaseapp.com`.
8. Return URLs: `https://helpme-reward-staging.firebaseapp.com/__/auth/handler`.
9. Click *Next*, then *Done*.
10. Click *Continue*, then *Save*. Apple discards the configuration unless
    this last *Save* on the Services ID page happens.
11. Store the id:

   ```sh
   $ cd <your checkout>/infra && pulumi stack select $STACK
   $ pulumi config set reward-app:appleServicesId com.helpmebrands.reward.signin
   ```

The Apple team id is already committed as `reward-app:appleTeamId` in
`Pulumi.staging.yaml`.

### 1.4 The Sign in with Apple key

1. *Keys* → **+**.
2. Key name `reward-app sign-in`.
3. Tick **Sign in with Apple** and click *Configure*.
4. Primary App ID `com.helpmebrands.reward`, then *Save*.
5. Click *Continue*, then *Register*.
6. Note the ten-character **Key ID**.
7. Download `AuthKey_<KEYID>.p8` into `~/reward-signing`. **This is the only
   chance to download it.**
8. Store both, still in `infra/`. The last command deletes the local copy:

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
   → App Store Connect API → Team Keys → Generate API Key*.
2. Name `reward-app release`, access **App Manager**, *Generate*.
3. Download the `.p8` into `~/reward-signing`. **Only once**, as before.
4. On the same page, note the key's **Key ID** and the page's **Issuer ID**.
5. Store all three. Each `read -r` waits for you to paste the value and
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
the key so the workflow reads all three from one place. The `.p8` stays in
`~/reward-signing` for the appendix route; Part 4 deletes it, and Secret
Manager keeps the only other copy.

### 1.6 The distribution certificate

An **Apple Distribution** certificate with its private key, exported as a
password-protected `.p12`. The Fastfile signs with the identity name
`Apple Distribution`, so it must be that type, not the older *iOS
Distribution*.

1. On the Mac, open *Keychain Access → Certificate Assistant → Request a
   Certificate From a Certificate Authority*.
2. Your email, common name `HelpMe Reward release`, *Saved to disk*,
   *Continue*, and save it in `~/reward-signing`. This puts a private key in
   your login keychain and a `.certSigningRequest` file in the folder.
3. In the portal, *Certificates* → **+** → **Apple Distribution** →
   *Continue*.
4. Upload the `.certSigningRequest` → *Continue*.
5. Download `distribution.cer` and double-click it. Keychain Access pairs it
   with the private key from step 2.
6. In Keychain Access, *My Certificates*, right-click `Apple Distribution:
   HelpMe Brands …` → *Export*.
7. Format `.p12`, save as `~/reward-signing/distribution.p12`.
8. Set a password when asked; save it in your password manager. That is
   the certificate password.
9. Store both:

   ```sh
   $ gcloud secrets versions add reward-app-ios-distribution-cert-$STACK \
       --project "$PROJECT_ID" --data-file distribution.p12
   $ read -rs CERT_PASSWORD; printf '%s' "$CERT_PASSWORD" | gcloud secrets versions add \
       reward-app-ios-cert-password-$STACK --project "$PROJECT_ID" --data-file -
   ```

10. Note the certificate's id (the ten characters in its portal URL) and its
    expiry date, a year from today. Part 5 records them.

Leave this terminal open: Part 4 uses `CERT_PASSWORD`.

### 1.7 The provisioning profile

The profile carries every capability ticked in 1.2 and the certificate
from 1.6. It is made once.

1. In the portal, *Profiles* → **+**.
2. Under *Distribution* choose **App Store Connect** → *Continue*.
3. App ID: `com.helpmebrands.reward` (the `XC com helpmebrands reward`
   entry) → *Continue*.
4. Certificate: the one from 1.6 → *Continue*.
5. Name: `HelpMe Reward App Store` → *Generate*. The Fastfile reads the name
   from inside the file, so any name works, but keeping this one keeps the
   history readable.
6. Download `HelpMe_Reward_App_Store.mobileprovision` into
   `~/reward-signing`.
7. Note the profile's id (in its portal URL) and its expiry date. Part 5
   records them.
8. Check it:

   ```sh
   $ cd ~/reward-signing
   $ security cms -D -i HelpMe_Reward_App_Store.mobileprovision | plutil -p - \
       | grep -E 'application-identifier|aps-environment|com.apple.developer.applesignin|com.apple.developer.associated-domains|ExpirationDate'
   ```

   You must see **all five** of these. The values after `=>` for the last
   three entitlements do not matter; the names must be there.

   - [ ] `"application-identifier" => "LMFUSVPCDH.com.helpmebrands.reward"`
   - [ ] `"aps-environment"` (Push Notifications)
   - [ ] `"com.apple.developer.applesignin"` (Sign in with Apple)
   - [ ] `"com.apple.developer.associated-domains"` (Associated Domains)
   - [ ] `"ExpirationDate"`, a year from now

   **Stop if any line is wrong or missing. Do not store this profile.**
   - A different `application-identifier` means the profile was made for
     another app id. Delete it in the portal and start this step again at 1,
     choosing the right id in 3.
   - A missing entitlement means that capability was not ticked in 1.2.
     Go to *Later: re-making the iOS profile* and start at its step 1.

9. All five are there. Store it:

   ```sh
   $ gcloud secrets versions add reward-app-ios-provisioning-profile-$STACK \
       --project "$PROJECT_ID" --data-file HelpMe_Reward_App_Store.mobileprovision
   ```

### 1.8 The App Store Connect app record

`upload_to_testflight` fails without this record, and only the web UI can
make it.

1. At <https://appstoreconnect.apple.com>, *Apps* → **+** → *New App*.
2. Platform iOS, name `HelpMe Reward`, primary language, bundle id
   `com.helpmebrands.reward`, SKU `helpme-reward`, *Full Access* → *Create*.
3. Open the app → *TestFlight* → *Internal Testing* → **+** to make a
   group, and add testers. Members of the App Store Connect team get builds
   without review. The workflow never touches tester lists.

## Part 2 — Google Play (Android)

> **Not rehearsed yet.** Android's first release is #115. These steps are
> the intended procedure; #115 corrects them here as it runs them.
>
> Not doing Android yet? Skip to Part 3. Later:
> 1. Do 2.1 to 2.5.
> 2. Apply the stack as in 3.3, so `assetlinks.json` gets the fingerprint.

### 2.1 The Play Console app record

1. At <https://play.google.com/console>, *Create app*.
2. App name `HelpMe Reward`, default language, *App*, *Free*.
3. Tick the declarations → *Create app*.

The package name is not asked for here: the first bundle (2.4) sets it to
`com.helpmebrands.reward`. Play App Signing is on by default for a new app:
Google holds the key that signs what people install, and your keystore is
only the **upload** key that proves a bundle came from you.

### 2.2 Link the Play publisher identity

The release workflow uploads as a Google Cloud service account that it
assumes keylessly, so no key file exists. The stack created it. This step
needs only the app record from 2.1, not a release.

1. Print its email:

   ```sh
   $ gcloud iam service-accounts list --project "$PROJECT_ID" \
       --filter='email~^reward-app-play-' --format='value(email)'
   ```

2. In Play Console, *Users and permissions → Invite new users*.
3. Paste the email.
4. *App permissions* → *Add app* → `HelpMe Reward`, and tick *Release to
   testing tracks*.
5. *Invite user*. A service account accepts at once.

The email is also on the GitHub environment as `PLAY_SERVICE_ACCOUNT`, and
every secret id as `SECRET_<NAME>`, for the workflow to read.

### 2.3 The upload keystore

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
| `-dname` | `CN=HelpMe Reward upload, OU=Mobile, O=HelpMe Brands` | the certificate's owner, from the answers in the next table. Giving it here skips keytool's six questions |
| password | 20 or more random characters (keytool's minimum is 6) | made below and kept in your password manager |

**keytool's questions.** Without `-dname`, keytool asks six questions
about who owns the certificate. These are the answers, and `-dname` above
gives them all at once. Nobody sees them: the app installed from Play is
signed with Google's key, not this one, and Play does not check the
answers. They only have to be the same every time the runbook is followed.

| keytool asks | Answer | `-dname` part |
| --- | --- | --- |
| What is your first and last name? | `HelpMe Reward upload` (what the key is, not a person, so it survives staff changes) | `CN=` |
| What is the name of your organizational unit? | `Mobile` | `OU=` |
| What is the name of your organization? | `HelpMe Brands` | `O=` |
| What is the name of your City or Locality? | press Enter (recorded as `Unknown`) | left out |
| What is the name of your State or Province? | press Enter | left out |
| What is the two-letter country code for this unit? | press Enter | left out |
| Is CN=… correct? | `yes` | not asked |

If you would rather record the company's address, add `L=<city>, ST=<state>,
C=<two-letter country code>` to `-dname`; it changes nothing else.

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
   times. It asks nothing else, because `-dname` answered the six questions:

   ```sh
   $ cd ~/reward-signing
   $ keytool -genkeypair -v -keystore upload.jks -storetype PKCS12 \
       -alias upload -keyalg RSA -keysize 2048 -validity 10000 \
       -dname "CN=HelpMe Reward upload, OU=Mobile, O=HelpMe Brands"
   ```

3. Check it. You should see `Keystore type: PKCS12`, `Alias name: upload`
   and a *Valid until* about 27 years away:

   ```sh
   $ keytool -list -v -keystore upload.jks | grep -E 'Keystore type|Alias name|Owner|until'
   ```

4. Store the keystore and the password. The password goes **into both
   password secrets**. `read -rs` waits for you to paste it and press Enter:

   ```sh
   $ gcloud secrets versions add reward-app-android-upload-keystore-$STACK \
       --project "$PROJECT_ID" --data-file upload.jks
   $ read -rs KEYSTORE_PASSWORD
   $ printf '%s' "$KEYSTORE_PASSWORD" | gcloud secrets versions add \
       reward-app-android-keystore-password-$STACK --project "$PROJECT_ID" --data-file -
   $ printf '%s' "$KEYSTORE_PASSWORD" | gcloud secrets versions add \
       reward-app-android-key-password-$STACK --project "$PROJECT_ID" --data-file -
   ```

### 2.4 The first bundle, by hand

The Play Developer API cannot create an app's first release, and the console
may insist that the very first bundle arrives through its own upload page,
which is where Play App Signing enrolment happens. So the first bundle is
built and signed on the Mac and uploaded in the browser. Every release after
it goes through the workflow.

Signing on the Mac works the way it does in the workflow. The build reads
one small file, `apps/mobile/android/key.properties`, that says where the
keystore is and what its password is. **It does not exist until you create
it in step 3**: it is gitignored (`apps/mobile/android/.gitignore`), never
committed, and step 13 deletes it again. The workflow creates its own copy
on every run. It has exactly four lines:

```properties
storeFile=/Users/<you>/reward-signing/upload.jks
storePassword=<the keystore password>
keyPassword=<the same password again>
keyAlias=upload
```

| Line | What it is |
| --- | --- |
| `storeFile` | the **absolute** path to the keystore; Gradle resolves a relative path from `android/app/`, not from where the file is |
| `storePassword` | the password from 2.3 |
| `keyPassword` | the same password (2.3, *One password, not two*) |
| `keyAlias` | `upload`, the alias from 2.3 |

The steps below write it from Secret Manager, so the passwords are never
typed or shown, and they prove the stored secrets are right.

1. **Check the build reads `key.properties`.** In the repository:

   ```sh
   $ cd <your checkout>/apps/mobile
   $ grep -n 'key.properties' android/app/build.gradle.kts
   ```

   It must print at least one line. **No output means the release build
   still signs with the debug key and Play will refuse the bundle: stop.**
   The Gradle signing config is part of #115; that change has to be merged
   first.

2. **Fetch the keystore** into the signing folder:

   ```sh
   $ mkdir -p ~/reward-signing
   $ gcloud secrets versions access latest --secret reward-app-android-upload-keystore-$STACK \
       --project "$PROJECT_ID" --out-file ~/reward-signing/upload.jks
   ```

3. **Create `key.properties`.** The `>` in the last line creates the file
   (or replaces one left over). This is the same block `release-mobile.yml`
   runs, with the keystore path on your Mac. Run it from `apps/mobile`:

   ```sh
   $ {
       echo "storeFile=$HOME/reward-signing/upload.jks"
       echo "storePassword=$(gcloud secrets versions access latest --secret reward-app-android-keystore-password-$STACK --project "$PROJECT_ID")"
       echo "keyPassword=$(gcloud secrets versions access latest --secret reward-app-android-key-password-$STACK --project "$PROJECT_ID")"
       echo "keyAlias=upload"
     } > android/key.properties
   $ chmod 600 android/key.properties
   ```

   To write it in an editor instead:
   1. `touch android/key.properties && open -e android/key.properties`
   2. Paste the four lines from the example above, with your path and the
      password from your password manager.
   3. Save and close.
   4. `chmod 600 android/key.properties`

4. **Check the file** without showing the passwords. You should see the
   four names, each followed by `=…`, and the second command prints the file
   path, which means Git ignores it:

   ```sh
   $ sed 's/=.*/=…/' android/key.properties
   $ git check-ignore android/key.properties
   ```

5. **Check the password opens the keystore.** It prints `Alias name: upload`:

   ```sh
   $ keytool -list -keystore ~/reward-signing/upload.jks \
       -storepass "$(sed -n 's/^storePassword=//p' android/key.properties)" | grep -i alias
   ```

6. **Build the bundle.** Build number `1`: every workflow run uses its run
   number, which is already higher, so later uploads never collide with it.

   ```sh
   $ fvm flutter build appbundle --release --build-name 0.1.0 --build-number 1
   ```

   It writes `build/app/outputs/bundle/release/app-release.aab`.

7. **Check it is signed with the upload key, not the debug key.** The owner
   must be `CN=HelpMe Reward upload, OU=Mobile, O=HelpMe Brands`.
   `CN=Android Debug` means step 1 was skipped:

   ```sh
   $ keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab | grep Owner
   ```

8. **Upload it.** In Play Console, open `HelpMe Reward` → *Test and release
   → Testing → Internal testing* → *Create new release*.
9. If asked how to sign the app, choose Google's generated key (Play App
   Signing).
10. Drag in `app-release.aab`. The release name fills in as `0.1.0`.
11. *Next* → *Save and publish* (the wording varies) and confirm.
12. On the *Testers* tab of *Internal testing*, create an email list, add
    the testers, and *Save*. The workflow never touches tester lists.
13. **Delete the local signing files.** Secret Manager keeps the keystore
    and passwords:

    ```sh
    $ rm android/key.properties ~/reward-signing/upload.jks
    ```

### 2.5 The signing key fingerprint

Android opens invite links in the app only if the api's domain lists the
app's signing certificate in `/.well-known/assetlinks.json`. The app signing
key exists now, because 2.4's upload enrolled the app in Play App Signing.

1. In Play Console, *Test and release → App integrity → App signing*.
2. Under *App signing key certificate*, copy the **SHA-256** fingerprint.
3. Set it, in `infra/`. Several fingerprints go in comma separated:

   ```sh
   $ pulumi config set reward-app:androidSha256Fingerprints AA:BB:…
   ```

Part 3 applies it.

## Part 3 — Sign-in and invite links, both platforms

People sign in with Google or Apple through Firebase Authentication on
Identity Platform in the stack's own project. The Pulumi stack turns
Identity Platform on, registers the iOS and Android apps with Firebase, and
declares each provider whose credentials are in the stack config.
This part supplies the last credential, the invite-link domain, and applies.

### 3.1 The Google OAuth client

Identity Platform's `google.com` provider needs a **web** OAuth client, even
for the phone apps: the Firebase SDK on both platforms runs Google's sign-in
through the handler, not through a platform client.

1. **Branding.** In the Google Cloud console for the project, *Google Auth
   Platform → Branding*. App name `HelpMe Reward`, a support email you read,
   and the developer contact. Under *Authorised domains*, add
   `helpme-reward-staging.firebaseapp.com`. *Save*.
2. **Audience.** Choose *External*. Staging stays in *Testing*: only the
   test users listed on this page can sign in, up to 100. Add every tester's
   Google account. Production must be published, which may need Google's
   verification of the branding.
3. **Client.** *Google Auth Platform → Clients → Create client*:
   - Application type: *Web application*
   - Name: `reward-app sign-in (staging)`
   - Authorised JavaScript origins: `https://helpme-reward-staging.firebaseapp.com`
   - Authorised redirect URIs: `https://helpme-reward-staging.firebaseapp.com/__/auth/handler`
4. Click *Create*. The dialog shows the client id and the client secret
   once. Copy both.
5. **Store them**, in `infra/`:

   ```sh
   $ pulumi config set reward-app:googleOAuthClientId 1234567890-abc.apps.googleusercontent.com
   $ read -rs GOOGLE_SECRET && printf '%s' "$GOOGLE_SECRET" | pulumi config set --secret reward-app:googleOAuthClientSecret && unset GOOGLE_SECRET
   ```

### 3.2 The invite-link domain

An invite link, `https://api.staging.helpmereward.com/invite/<code>`, opens
the app only when that domain serves the association files for iOS and
Android. The api serves them; the domain needs pointing at it.

1. Check the parent domain is verified for your account. This must list
   `helpmereward.com`:

   ```sh
   $ gcloud domains list-user-verified
   ```

   Not listed: stop, and do step 2 of
   [03, *Adding a custom domain*](03-infrastructure-change.md#adding-a-custom-domain).
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

1. Commit the changed `Pulumi.<stack>.yaml` on a branch and open a pull
   request.
2. Check CI's preview shows the two sign-in providers and the domain
   mapping.
3. Merge the pull request.
4. Apply, the way runbook 03 describes:

   ```sh
   $ git checkout develop && git pull
   $ cd infra
   $ USER_PROJECT_OVERRIDE=true GOOGLE_BILLING_PROJECT=$PROJECT_ID pulumi up --refresh
   ```

### 3.4 The Apple sign-in config

The Pulumi provider (`@pulumi/gcp` 8.41) declares the `apple.com` provider
with its Services ID only. It has no field for `appleSignInConfig`, which
holds the bundle ids allowed to use native sign-in on iOS and the key that
Android and the web flow need. Run this now, in `infra/`. *Later: rotating
keys and secrets* runs it again for a new key.

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
URL scheme in `Info.plist` carry staging's values; skip to Part 4. A new
project has new Firebase app ids. Print them:

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

**The invite-link domain serves the association files.** Google issues the
domain's certificate up to an hour after the DNS record exists.

1. Check the certificate. While it is pending, this names the DNS record it
   waits for:

   ```sh
   $ pulumi stack output apiCustomDomainStatus
   ```

2. Fetch both files:

   ```sh
   $ curl -sS https://api.staging.helpmereward.com/.well-known/apple-app-site-association
   $ curl -sS https://api.staging.helpmereward.com/.well-known/assetlinks.json
   ```

   The first answers JSON naming `LMFUSVPCDH.com.helpmebrands.reward`; the
   second lists the fingerprint from 2.5. A certificate error means step 1
   is still pending.

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

1. Tag `develop` as [07](07-mobile-release.md#getting-it-to-testers)
   describes.
2. Wait for the build in TestFlight and on the internal track.
3. Install it and sign in with Google.
4. Sign out and sign in with Apple.
5. Open an invite link on the device.

A `redirect_uri_mismatch` from Google, or `invalid_client` from Apple, means
the handler address in that console does not match the one in 1.3 exactly.

## Later: re-making the iOS profile

Do this when any of these happens:

- A release fails in the iOS job with
  `Provisioning profile "HelpMe Reward App Store" doesn't include the <…> entitlement`.
  The app asks for a capability the profile was made without.
- `Runner.entitlements` gains an entitlement.
- The certificate was renewed (next section): a profile is tied to its
  certificate.
- The profile is about to expire.

1. **Tick the capability.** Skip this if no capability is missing. Open
   the app id (1.2), tick it and save. Changing the app id makes existing
   profiles for it invalid; that is expected.
2. **Delete the old profile.** In the portal, *Profiles*, open `HelpMe
   Reward App Store` and remove it, so only one profile carries the name.
   Secret Manager keeps its copy until step 5.
3. **Make the new one**: 1.7, steps 1 to 7, with the same name.
4. **Check it.** All five lines of the 1.7, step 8 checklist must show:

   ```sh
   $ cd ~/reward-signing
   $ security cms -D -i HelpMe_Reward_App_Store.mobileprovision | plutil -p - \
       | grep -E 'application-identifier|aps-environment|com.apple.developer.applesignin|com.apple.developer.associated-domains|ExpirationDate'
   ```

   A wrong or missing line: stop, and go back to step 1 here.
5. **Store it**, and disable the old version so only the new one is live:

   ```sh
   $ gcloud secrets versions add reward-app-ios-provisioning-profile-$STACK \
       --project "$PROJECT_ID" --data-file HelpMe_Reward_App_Store.mobileprovision
   $ gcloud secrets versions list reward-app-ios-provisioning-profile-$STACK \
       --project "$PROJECT_ID"         # newest first; the second line is the old version
   $ gcloud secrets versions disable <previous-version> \
       --secret reward-app-ios-provisioning-profile-$STACK --project "$PROJECT_ID"
   ```

6. **Check the stored copy** with the two profile commands at the end of
   the Part 4 code block.
7. **Delete the local file**: `rm ~/reward-signing/HelpMe_Reward_App_Store.mobileprovision`.
8. **Write it down** as in Part 5: the new profile id and expiry in the
   *iOS signing* row of the README and, if the date changed, in its test.
   One pull request.
9. **Release again.** Pick one:
   - Apple never received a build from the failed run: re-run its failed
     jobs. The run number, and so the build number, stay the same.

     ```sh
     $ gh run rerun <run-id> --failed
     ```

   - Otherwise: tag a new version (`git tag v…`, as in 07).

## Later: renewing the certificate

Distribution certificates last a year; the README row has the date. A few
weeks before it:

1. Make a new certificate and store it: 1.6, all ten steps. The `.p12` and
   its password are two new secret versions.
2. Re-make the profile with the new certificate: *Later: re-making the iOS
   profile*, steps 2 to 9. Choose the **new** certificate in 1.7, step 4.
3. Wait for that release to reach TestFlight.
4. Revoke the old certificate in the portal, *Certificates*.

## Later: rotating keys and secrets

**Google OAuth secret**

1. In *Clients*, open the client and add a new secret.
2. Store it with the `--secret` command in 3.1, step 5.
3. Apply (3.3).
4. Delete the old secret in the console.

**Sign in with Apple key.** Apple allows two such keys per team at once.

1. Make a new key and store it: 1.4, all eight steps.
2. Apply (3.3).
3. Run the PATCH in 3.4.
4. Revoke the old key in the portal, *Keys*.

**App Store Connect API key**

1. Generate a new one and store its `.p8` and key id: 1.5. The issuer id
   does not change; skip its line.
2. Release once (07) and check the upload worked.
3. Revoke the old key in App Store Connect.

**Upload keystore**

1. Make a new keystore: 2.3, steps 1 to 3.
2. Ask Play support to reset the upload key, following their instructions.
3. Store the new keystore and password: 2.3, step 4.

## Appendix: the profile from the command line

Instead of the portal clicks in 1.7, steps 1 to 6, the App Store Connect
API key from 1.5 can make the profile. It cannot pick the wrong app id. It
needs 1.2 done, and it also turns on Push Notifications, which is harmless
if that is already on. It needs only Ruby's standard library, and
`ASC_KEY_PATH` is the `.p8`.

1. Save the script as `~/reward-signing/asc-profile.rb`:

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

2. Make sure the key id and issuer id are set. In the terminal from 1.5
   they are; in a new one, `read -r` each again:

   ```sh
   $ read -r ASC_KEY_ID; read -r ASC_ISSUER_ID
   $ export ASC_KEY_ID ASC_ISSUER_ID
   ```

3. Run it:

   ```sh
   $ cd ~/reward-signing
   $ ASC_KEY_PATH=AuthKey_XXXXXXXXXX.p8 ruby asc-profile.rb com.helpmebrands.reward \
       'HelpMe Reward App Store' HelpMe_Reward_App_Store.mobileprovision
   ```

4. Continue at 1.7, step 7.

The script picks the first distribution certificate on the team. With two,
during a renewal, use the portal clicks instead.
