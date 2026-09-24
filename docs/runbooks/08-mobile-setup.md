# 08 — Sign-in providers

People sign in to HelpMe Reward with Google or Apple, through Firebase
Authentication on Identity Platform in the stack's own Google Cloud project.
Pulumi turns Identity Platform on and declares both providers (#212), but
each provider needs credentials that only a person can create, one in the
Google Cloud console and one in the Apple Developer portal. This runbook
covers those hand steps and where their results go.

Do this once per environment. The examples are for staging; for another
stack, change `STACK` and the project id in the URLs.

```sh
$ export STACK=staging
$ export PROJECT=helpme-reward-staging
$ cd infra
$ pulumi stack select $STACK
```

## What you will end up with

| Stack config key | Secret | Where it comes from |
| --- | --- | --- |
| `reward-app:googleOAuthClientId` | no | Google: the web OAuth client |
| `reward-app:googleOAuthClientSecret` | yes | Google: the same client |
| `reward-app:appleServicesId` | no | Apple: the Services ID, e.g. `com.helpmebrands.reward.signin` |
| `reward-app:appleKeyId` | no | Apple: the ten-character id of the Sign in with Apple key |
| `reward-app:appleServicesKey` | yes | Apple: the `.p8` private key file of that key |

The Apple team id, `LMFUSVPCDH`, is already known. The Pulumi change for
#212 commits it as `reward-app:appleTeamId` in the stack file.

Credentials are **stack config, not Secret Manager**. Pulumi hands them to
Identity Platform when it applies, and the api never reads them, since it
only verifies the ID tokens that Firebase issues. The secret values are
encrypted with the stack's KMS key (runbook 01, step 3) before they reach
`Pulumi.<stack>.yaml`, so that file stays safe to commit.

Every provider sends people back to the same handler, which Firebase serves
on the project's default auth domain:

```
https://helpme-reward-staging.firebaseapp.com/__/auth/handler
```

That domain only answers after Firebase has been added to the project, which
the same Pulumi change does. You can create both credentials before then,
because each console stores the URL as text and does not call it.

## Google

Identity Platform's `google.com` provider needs a **web** OAuth client, even
for the phone apps. The Firebase SDK on iOS and Android runs Google's sign-in
through the handler above, not through a platform client.

1. **Branding.** Open the Google Cloud console for the project, then
   *Google Auth Platform → Branding*. Set the app name to `HelpMe Reward`, a
   support email you read, and the developer contact. Under *Authorised
   domains*, add `helpme-reward-staging.firebaseapp.com`, or the project's
   own `firebaseapp.com` host on another stack.
2. **Audience.** Choose *External*. Staging can stay in *Testing*, but then
   only the test users listed on this page can sign in, up to 100 of them.
   Add every tester's Google account. Production must be published, which
   may need Google's verification of the branding.
3. **Client.** Go to *Google Auth Platform → Clients → Create client*:
   - Application type: *Web application*
   - Name: `reward-app sign-in (staging)`
   - Authorised JavaScript origins: `https://helpme-reward-staging.firebaseapp.com`
   - Authorised redirect URIs: `https://helpme-reward-staging.firebaseapp.com/__/auth/handler`

   The dialog shows the client id and the client secret once. Copy both.
4. **Store them.** Enter the secret at a prompt, so it stays out of your
   shell history:

   ```sh
   $ pulumi config set reward-app:googleOAuthClientId 1234567890-abc.apps.googleusercontent.com
   $ read -rs GOOGLE_SECRET && printf '%s' "$GOOGLE_SECRET" | pulumi config set --secret reward-app:googleOAuthClientSecret && unset GOOGLE_SECRET
   ```

## Apple

Sign in with Apple needs four things in the Apple Developer portal
(<https://developer.apple.com/account>, team `LMFUSVPCDH`). The app id gets
the capability, a **Services ID** lets Android and the web flow use the
handler above, a **key** signs the requests Identity Platform makes to Apple,
and the provisioning profile has to be made again to carry the new
entitlement.

1. **Capability on the app id.** Go to *Certificates, IDs & Profiles →
   Identifiers*, open `XC com helpmebrands reward` (`com.helpmebrands.reward`),
   tick **Sign in with Apple**, keep *Enable as a primary App ID*, and save.
2. **Services ID.** Under *Identifiers → + → Services IDs*:
   - Description: `HelpMe Reward sign-in`
   - Identifier: `com.helpmebrands.reward.signin`

   Register it, open it again, tick **Sign in with Apple**, then *Configure*:
   - Primary App ID: `com.helpmebrands.reward`
   - Domains and subdomains: `helpme-reward-staging.firebaseapp.com`
   - Return URLs: `https://helpme-reward-staging.firebaseapp.com/__/auth/handler`

   Save, then *Continue* and *Save* again. Apple discards the configuration
   unless you save the Services ID page as well.
3. **Key.** Under *Keys → +*, name it `reward-app sign-in`, tick **Sign in
   with Apple**, *Configure* it with the primary App ID
   `com.helpmebrands.reward`, and register it. Note the ten-character **Key
   ID** and download `AuthKey_<KEYID>.p8`. **Apple lets you download it only
   once.** Keep it until the next step is done, then delete it.
4. **Provisioning profile.** The App Store profile `6595DT67WA` was made
   before the app id had this capability, so it does not carry the
   `com.apple.developer.applesignin` entitlement. An archive signed with it
   fails at signing once the app declares the entitlement (#219). Make a new
   profile for the same app id and certificate, check it, and add it as a new
   version of `reward-app-ios-provisioning-profile-$STACK`. Follow runbook 07
   (*iOS: the provisioning profile* and *Check and clean up*), and also check
   that `security cms -D` shows `com.apple.developer.applesignin` in the
   entitlements. Then update the *iOS signing* row of the
   [README](README.md#environments) with the new profile id.
5. **Store them.** The key file goes into the secret from stdin, so it never
   appears in a command line:

   ```sh
   $ pulumi config set reward-app:appleServicesId com.helpmebrands.reward.signin
   $ pulumi config set reward-app:appleKeyId ABCDE12345
   $ pulumi config set --secret reward-app:appleServicesKey < ~/Downloads/AuthKey_ABCDE12345.p8
   $ rm ~/Downloads/AuthKey_ABCDE12345.p8
   ```

Optional: to reach people who hide their email behind Apple's relay, register
`noreply@helpme-reward-staging.firebaseapp.com` under *Services → Sign in with
Apple for Email Communication*. Nothing sends email yet.

## Apply

Commit the changed `Pulumi.<stack>.yaml` on a branch and let CI's preview
show the two providers. After the merge, apply it the way runbook 03
describes:

```sh
$ USER_PROJECT_OVERRIDE=true GOOGLE_BILLING_PROJECT=$PROJECT pulumi up --refresh
```

### The Apple sign-in config

The Pulumi provider (`@pulumi/gcp` 8.41) declares the `apple.com` provider
with its Services ID only. It has no field for `appleSignInConfig`, which
holds the bundle ids that may use native sign-in on iOS and the code-flow key
that Android and the web flow need. Set it once after the first apply, and
again whenever the key is rotated:

```sh
$ jq -n \
    --arg team "$(pulumi config get reward-app:appleTeamId)" \
    --arg key "$(pulumi config get reward-app:appleKeyId)" \
    --arg pem "$(pulumi config get reward-app:appleServicesKey)" \
    '{appleSignInConfig: {bundleIds: ["com.helpmebrands.reward"],
      codeFlowConfig: {teamId: $team, keyId: $key, privateKey: $pem}}}' \
  | curl -sS -X PATCH \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H "x-goog-user-project: $PROJECT" \
    -H 'Content-Type: application/json' \
    --data-binary @- \
    "https://identitytoolkit.googleapis.com/admin/v2/projects/$PROJECT/defaultSupportedIdpConfigs/apple.com?updateMask=appleSignInConfig"
```

The response echoes the provider with `appleSignInConfig.bundleIds` filled
in. Identity Platform does not return the private key.

## Check

Both providers are listed and enabled:

```sh
$ curl -sS -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H "x-goog-user-project: $PROJECT" \
    "https://identitytoolkit.googleapis.com/admin/v2/projects/$PROJECT/defaultSupportedIdpConfigs" \
  | jq '.defaultSupportedIdpConfigs[] | {name, enabled, clientId}'
```

Then sign in once with each provider from a build of the app. A
`redirect_uri_mismatch` from Google, or `invalid_client` from Apple, means the
handler URL in that console does not match the one above exactly.

## Invite links

An invite link, `https://api.staging.helpmereward.com/invite/<code>`, opens the app only once three more hand steps are done. Until then it opens the fallback page in the browser, which still shows the code.

1. **DNS.** Add a CNAME record `api.staging` pointing to `ghs.googlehosted.com`, *DNS only*, beside the existing `staging` record. `pulumi up` maps the domain, and `pulumi stack output apiCustomDomainStatus` names the record once Google has issued the certificate.
2. **Associated Domains on the app id.** In the Apple Developer portal, open `XC com helpmebrands reward` and tick **Associated Domains**. Then make a new App Store provisioning profile, as in step 4 of *Apple* above, and check that the entitlements show `com.apple.developer.associated-domains`.
3. **Android certificates.** Once the Play signing key exists (#115), copy its SHA-256 fingerprint from Play Console → *App integrity* and set it:

   ```sh
   $ pulumi config set reward-app:androidSha256Fingerprints AA:BB:…
   ```

   Then apply, so the api serves it in `assetlinks.json`.

Check it with `curl -sS https://api.staging.helpmereward.com/.well-known/apple-app-site-association`, which answers JSON naming `LMFUSVPCDH.com.helpmebrands.reward`.

## Rotating

- **Google secret.** Add a new secret to the same client in *Clients*, set it
  with the `--secret` command above, apply, then delete the old secret in the
  console.
- **Apple key.** Create a new key (step 3), set `appleKeyId` and
  `appleServicesKey`, apply, run the PATCH again, then revoke the old key.
  Apple allows two Sign in with Apple keys per team at once.
