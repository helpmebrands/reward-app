# Infrastructure tests

What the repository-level suites pin: the Pulumi configuration, the runbooks that quote it, the workflows, the monorepo layout and the shape of this graph.

## Infrastructure config

`apps/pwa/tests/infra-config.test.ts` pins the committed Pulumi configuration, the runbooks that quote it and the monorepo layout ([[deployment#Infrastructure]]). Drift here is only noticed when a deploy is rejected at the auth step.

Tests that import program code live beside it (`infra-repo/verify-checks.test.ts`, run by that workspace's own `vitest`), because the PWA image typechecks `apps/pwa/tests` without the Pulumi workspaces present and a cross-workspace import breaks the container build.

### Project is named reward-app

`infra/Pulumi.yaml` names the project `reward-app`, which is also the config namespace the program reads. The pre-rebrand name would recreate every resource once a stack exists.

### Project config declares no namespaced keys

Pulumi rejects a namespaced key such as `gcp:project` declared at project level without a value, so `infra/Pulumi.yaml` declares only the project's own unprefixed keys.

### Staging targets the decided project

`infra/Pulumi.staging.yaml` sets `gcp:project` to `helpme-reward-staging`, the project decided on epic #3, not the misspelt `helpme-rewards-staging`.

### Staging maps its custom domain

`infra/Pulumi.staging.yaml` sets `customDomain` to `staging.helpmereward.com`, so a clean checkout previews no diff against the live mapping. The apex is reserved for `prod`.

### Staging uses the KMS secrets provider

`Pulumi.staging.yaml` names `gcpkms://projects/helpme-reward-staging/locations/us-central1/keyRings/pulumi/cryptoKeys/staging` in `secretsprovider` and carries an `encryptedkey` ([[deployment#Infrastructure]]).

With both pinned, the stack can never fall back to the empty passphrase it started with.

### Project config declares the database tier

`Pulumi.yaml` declares `dbTier` with `default: db-f1-micro`, the smallest Cloud SQL machine, so a stack that says nothing gets the cheapest instance and raising it is a visible config change.

### Staging trusts this repository

`githubRepo` is `helpmebrands/reward-app`. The WIF attribute condition and the impersonation binding are built from it, so a wrong value rejects every deploy.

### Staging lists the Play app signing fingerprint

`Pulumi.staging.yaml` sets `androidSha256Fingerprints` to one or more colon-separated SHA-256 fingerprints, which `infra/index.ts` passes to the api for `assetlinks.json` ([[api-architecture#Invite links]]).

The value is the app signing key Play generated when the first bundle was uploaded (#115), not the upload keystore in Secret Manager; with the wrong one Android never opens invite links in the app.

### No stale repository or project names

Nothing under `infra/`, `docs/` or `.github/` names `oravecz/cardvantage` or `helpme-rewards-`.

### No cardvantage in infrastructure names

Nothing under `infra/`, `docs/`, `.github/`, `apps/pwa/deploy/` or `apps/pwa/Dockerfile` names `cardvantage`. Service, image, registry and service-account ids all derive from `reward-app`.

### Runbook names the real state backend

Runbook 01 logs Pulumi into `gs://helpme-reward-staging-pulumi-state` rather than offering a choice, so nobody initialises a second, competing copy of the state.

### README records both services and the database

`docs/runbooks/README.md` names `reward-app`, `reward-api`, `reward-api-migrate`, `reward-api-db-staging`, `reward-api-database-url-staging`, the api URL and the 06 and 07 rows, and no longer claims there is no database ([[infra#Runbooks]]).

### Runbook 01 bootstraps the KMS secrets provider

`01-initial-deployment.md` creates the key ring with `gcloud kms keyrings create` and moves an existing stack with `pulumi stack change-secrets-provider` ([[deployment#Infrastructure]]).

It also sets `API_CLOUD_RUN_SERVICE` and `API_MIGRATION_JOB`, and never sets an empty `PULUMI_CONFIG_PASSPHRASE`.

### Runbooks 06 and 07 exist with their rehearsed commands

`06-database.md` quotes `gcloud run jobs execute`, `gcloud sql backups create` and `restore`, `cloud-sql-proxy` and `schema_migrations`; `07-mobile-release.md` covers `flutter build`, TestFlight and the Play internal track.

### README records the staging environment

`docs/runbooks/README.md` names the staging project, region, state bucket, `run.app` URL and custom hostname, so a new starter does not reverse-engineer which project is which from repository variables.

### Verify gate typechecks the Pulumi program

`verify.yml` has an `infra` job that runs `npm ci --workspace infra` and `npm run typecheck --workspace infra` against the root lockfile, so a type error in `infra/index.ts` fails review instead of the next hand-run `pulumi up`.

### Verify gate previews the Pulumi program with keyless credentials

The `infra` job authenticates with `google-github-actions/auth@v2`, logs Pulumi into `gs://helpme-reward-staging-pulumi-state` and runs `pulumi preview` ([[deployment#Pipeline]]).

Both `ci.yml` and `cd.yml` grant `id-token: write`, without which the OIDC exchange has no token to present.

### Required checks derive from verify.yml

`infra/verify-checks.ts` maps every job in a workflow to `verify / <job name>` (the job id when unnamed) and throws on a workflow with no jobs, so the ruleset can never silently require nothing ([[deployment#Infrastructure]]).

### Program declares the develop ruleset

`infra-repo/index.ts` reads `.github/workflows/verify.yml` and declares one `github.RepositoryRuleset` whose required checks come from `requiredChecks`, so the ruleset and the workflow cannot disagree.

`infra/index.ts` declares no ruleset, because two environment stacks cannot both own one repository setting.

### Repo-level project has its own stack

`infra-repo/Pulumi.yaml` names the project `reward-app-repo` and `Pulumi.repo.yaml` sets `github:owner` on the KMS secrets provider with no plain-text token, so the repository-wide configuration has exactly one stack ([[deployment#Infrastructure]]).

### Every verify job is a required check

Applied to the real `verify.yml`, the derivation yields exactly one context per job and includes all seven current job names, so a red Dart, Flutter, api or accessibility job blocks a merge.

### Staging names the GitHub owner

`Pulumi.staging.yaml` sets `github:owner` to `helpmebrands` and never carries `github:token` in plain text; the token is secret config or the `GITHUB_TOKEN` environment variable.

### Verify gate previews GitHub resources with the workflow token

The `Preview against staging` step passes `GITHUB_TOKEN: ${{ github.token }}`, which can read the repository but not administer it, all a preview without refresh needs ([[deployment#Pipeline]]).

### Runbook 01 describes the ruleset, not the settings UI

Step 6 of `01-initial-deployment.md` names `RepositoryRuleset` and the one-time `pulumi import`, and no longer sends the operator to *Settings → Branches*.

### Every workflow variable is declared on the environment

Every `vars.*` the workflows read, except the optional build-time `VITE_*` pair, is a key of `environmentVariables` in `infra/index.ts`, so a variable a workflow needs cannot be missing from the stack that deploys it ([[deployment#Infrastructure]]).

The same program declares the `github.RepositoryEnvironment` the variables are written to.

### Workflows run in the stack's environment

`cd.yml`, `cd-api.yml` and the `infra` job of `verify.yml` run in the `staging` environment and never `develop`, so `vars.*` resolves from the environment the stack writes rather than from repository variables that no longer exist.

### Verify gate covers both Pulumi projects

The `infra` job installs, typechecks and previews `infra-repo` as well as `infra` (`pulumi stack select repo` from `working-directory: infra-repo`) and runs its tests, so a broken ruleset program fails review like a broken environment program ([[deployment#Pipeline]]).

### PWA image knows every workspace manifest

`apps/pwa/Dockerfile` copies `infra-repo/package.json` beside the other manifests before `npm ci`, because npm refuses a lockfile whose workspaces are not all present.

### Runbook 01 no longer copies outputs into GitHub by hand

Step 5 of `01-initial-deployment.md` names `ActionsEnvironmentVariable` and contains no `gh variable set`, so the copy step that the runbook once defended as "shows up on the next pull request" is gone for good.

### No runbook sends the operator to the GitHub settings UI

No file under `docs/runbooks/` contains `gh variable set` or `Settings → Branches`, or calls repository variables the source of truth, so a hand step the stack replaced cannot creep back into the prose ([[infra#Runbooks]]).

### Runbook 01 applies with the quota project override

Step 4 of `01-initial-deployment.md` and runbook 03 show `USER_PROJECT_OVERRIDE=true GOOGLE_BILLING_PROJECT=…` on `pulumi up`, because the budget API rejects an apply without a quota project and the provider does not take it from ADC.

### Runbook 01 records the token expiry and the GitHub-side results

Step 8 tells the operator to record the GitHub token's expiry, and *What you have now* lists the environment and the ruleset, so a fresh reader sees that GitHub is stack-managed and knows what silently expires.

### README names both Pulumi projects and the environment as source of truth

`docs/runbooks/README.md` names `infra-repo/` and when to touch it, and calls the GitHub environment `staging` the operational source of truth instead of repository variables.

### Runbook 05 explains the quota project error

`05-troubleshooting.md` has a heading for `requires a quota project` with the override that fixes it, so the next operator does not rediscover it from a failed apply.

### Play identity is keyless

`index.ts` enables `androidpublisher.googleapis.com`, declares `reward-app-play-<env>` and lets this repository's workflows assume it through the workload identity pool; no `serviceaccount.Key` exists anywhere in the program ([[deployment#Infrastructure]]).

### Signing material has a container and no version

`signingSecrets` lists the nine pieces of signing material and each becomes a `gcp.secretmanager.Secret` with no `SecretVersion`, so the values are added and rotated by hand and never pass through the state.

### Deployer reads exactly the signing secrets

Each signing secret grants `secretmanager.secretAccessor` to the deployer through a `SecretIamMember`, and no `projects.IAMMember` grants that role, so a compromised workflow reads these secrets and nothing else in the project.

### Release identifiers reach the environment

`environmentVariables` carries `PLAY_SERVICE_ACCOUNT` and one `SECRET_<NAME>` per signing secret, so the release workflow hard-codes no identity and no secret id.

### Runbook 08 uploads the APNs key to Firebase

Step 3.6 of `08-mobile-setup.md` creates an Apple Push Notifications service key and uploads it under *APNs Authentication Key* with the team id `LMFUSVPCDH`, without which FCM cannot reach an iPhone ([[mobile-architecture#Push]]).

### Runbook 07 no longer calls push unbuilt

`07-mobile-release.md` drops "Push delivery itself is not built" and the claim that the APNs key is not its concern, and links runbook 08 §3.6 instead.

### Runbook 08 turns on the reminder job

§3.7 of `08-mobile-setup.md` is numbered steps: apply the stack, check `API_REMIND_JOB` on the environment, describe the scheduler, execute `reward-api-remind` and read the `sent N reminder and N notice pushes` line ([[api-architecture#Reminder sender]]).

### Runbook 08 checks push on a device

Part 4 has a numbered **Push reaches a device.** check: turn on Send me reminders, allow the prompt, and Send a test notification from Settings.

### Runbook 05 covers push that does not arrive

`05-troubleshooting.md` has "Push notifications do not reach the app", naming the APNs Authentication Key, `roles/firebasecloudmessaging.admin`, a job that sent 0 and tokens retired on `UNREGISTERED`.

### Runbook 08 has the store hand steps

`08-mobile-setup.md` shows `gcloud secrets versions add` for the signing material and the *Users and permissions* link of the Play identity, and no longer proposes GitHub secrets.
### Release workflow runs on version tags in the environment

`release-mobile.yml` triggers on `v*` tags with an `android` job on `ubuntu-latest` and an `ios` job on `macos-latest`, both in the `staging` environment and both passing `--build-name` and `--build-number ${{ github.run_number }}` ([[deployment#Pipeline]]).

### Release workflow stores nothing in GitHub secrets

The release workflow references no `secrets.*` except `GITHUB_TOKEN`, so the signing material can only come from Secret Manager at build time.

### Release workflow reads signing material from Secret Manager

Every `SECRET_<NAME>` on the environment is read with `gcloud secrets versions access latest` after a keyless `google-github-actions/auth@v2`, and the Play upload authenticates as `PLAY_SERVICE_ACCOUNT`.

### Store uploads are scripted beside the app

`apps/mobile/scripts/play-upload.sh` drives the Play Developer API (edit, bundle, `tracks/internal`, `:commit`) and the iOS `Fastfile` imports the certificate and calls `upload_to_testflight` with an API key.

The workflow calls both, so the store logic is reviewable code beside the app rather than YAML.

### Release builds sign with the upload key from key.properties

`apps/mobile/android/app/build.gradle.kts` loads `key.properties` when it exists, declares a `release` signing config from its four keys, and the `release` build type uses it, falling back to the debug config without the file.

Play refuses a debug-signed bundle, and both the laptop build in runbook 08 and `release-mobile.yml` write `key.properties` and expect Gradle to read it (#115). The fallback keeps `flutter run --release` and the verify job working with no secrets.

### Android app uses AGP built-in Kotlin

`gradle.properties` sets `android.builtInKotlin=true`, the app module applies no Kotlin plugin and keeps only `kotlin { compilerOptions }`, and `settings.gradle.kts` pins KGP with `apply false`.

The template's `builtInKotlin=false` opt-out made `firebase_core` and `firebase_auth` apply the Kotlin Gradle Plugin themselves, which Flutter warns will stop building (#247).

Built-in Kotlin needs Flutter 3.47, whose Gradle plugin stops force-applying `kotlin-android` to plugin subprojects. The `apply false` line stays because AGP 9 bundles Kotlin 2.2.10 and Flutter 3.47 requires 2.2.20, as its own template does.

Flutter still prints the plugin warning for `firebase_core` and `firebase_auth`: it matches `apply plugin: 'kotlin-android'` in their build files as text, although both only run that line when built-in Kotlin is off.

### Runbook 07 describes the tag-driven release

`07-mobile-release.md` names `release-mobile.yml`, shows `git tag v…`, explains Apple's processing failure, and no longer says CI does not yet build a release.

### Info.plist answers export compliance

`apps/mobile/ios/Runner/Info.plist` sets `ITSAppUsesNonExemptEncryption` to `false`, and the *When it arrives* paragraph of `07-mobile-release.md` says the compliance answer lives there.

The app only speaks HTTPS to its own api, which is exempt, so the answer is a constant. Declaring it answers the export-compliance question at upload time: fastlane no longer waits for a second round of processing, and a build uploaded by Xcode or Transporter is not stuck at *Missing Compliance*.

### Runbook 01 gives the repository project its own step

Step 3 of `01-initial-deployment.md` never mentions `infra-repo`, and a numbered step named for the repository project opens with `cd` into it and `pulumi stack select repo` before its import, so no command block straddles two Pulumi projects ([[infra#Runbooks]]).

### Runbook 01 import ids carry the repository prefix

Every `pulumi import` in runbook 01 ends in `reward-app:<id>`, the repository name without the owner, because the GitHub provider rejects `owner/name` and a bare id alike; an operator copying the block gets the form that works.

### Runbook 08 is the one mobile setup flow

`08-mobile-setup.md` replaces `08-sign-in-providers.md` in the README and everywhere under `docs/`. It has a part for Apple, one for Google Play and one for both platforms, with the auth handler URL and the `appleSignInConfig` PATCH.

The setup steps used to be split over 07 and 08 in the order they were written, and following them made three provisioning profiles, the last still missing an entitlement.

### Runbook 08 Part 2 says what the first Android release taught

Part 2 of `08-mobile-setup.md` says it was rehearsed on 2026-09-24, names the `403` symptom of a missing invite, gives the *Protected with Play* path to the *Classical key* fingerprint, and matches the keystore's `HelpMe Reward Upload` owner.

Step 3.3 also names the `invalid_rapt` reauth error and points at runbook 05. Each of these cost a round trip during #115: the 403 read as an IAM problem, the *App integrity* path no longer exists in the console, and the runbook's lower-case `upload` did not match the keytool output.

### Runbook 08 turns on every capability before the profile

The capabilities step of `08-mobile-setup.md` ticks Push Notifications, Sign in with Apple and Associated Domains, and comes before the provisioning-profile step, so one profile carries every entitlement the app declares.
### Runbook 08 stores credentials as stack secrets

Runbook 08 sets the OAuth client secret and the Apple `.p8` key with `pulumi config set --secret`, and the three ids with plain `pulumi config set`. The sign-in credentials never go to Secret Manager: only Pulumi and Identity Platform use them.

### Runbook 08 re-makes the profile end to end

*Later: re-making the iOS profile* in `08-mobile-setup.md` names the `doesn't include the … entitlement` failure, deletes the old profile, checks and stores the new one, updates the README *iOS signing* row and releases again.

A changed capability is then one procedure rather than steps spread across runbooks.

### Runbook 07 leaves setup to runbook 08

`07-mobile-release.md` has no *Signing material* or *Play publisher identity* section and links to `08-mobile-setup.md`, so each hand step is written once.

### Runbook 08 walks through every piece of signing material

`08-mobile-setup.md` has a step each for the upload keystore, the App Store Connect API key, the distribution certificate and the provisioning profile, each with its `gcloud secrets versions add`.

Its setup block exports `STACK=staging` beside `PROJECT_ID`, because every `versions add` names its secret as `reward-app-<name>-$STACK` and a copied block with `STACK` unset targets an id that does not exist.

It also names the Play App Signing first-upload quirk, so the first failed upload is not a mystery.

The keystore step gives every `keytool` value, `-storetype PKCS12` and a `-dname` among them, and says a PKCS12 keystore has one password, which goes into both password secrets: keytool ignores a separate `-keypass`.
### Runbook 08 writes key.properties step by step

The first-bundle step of `08-mobile-setup.md` shows the four `key.properties` lines, writes them from Secret Manager, checks Gradle reads the file, proves the bundle is not debug-signed, and deletes the file.

The check comes first rather than after a rejected upload: a checkout from before #115 still signs releases with the debug key ([[infra-tests#Infrastructure config#Release builds sign with the upload key from key.properties]]).

### Runbook 08 says store records are per app id

`08-mobile-setup.md` states there is one record per app, not per environment, so nobody creates a staging app in either store by mistake.
### Runbook 08 checks the profile's entitlements before storing it

The profile step of `08-mobile-setup.md` uses the `XC com helpmebrands reward` id and checks `application-identifier`, `aps-environment`, `com.apple.developer.applesignin` and `com.apple.developer.associated-domains` before `gcloud secrets versions add`.

The API route stays as an appendix.

The first pass of the runbook stored a profile made for a second, hand-registered app id, and a later one stored a profile without Associated Domains (release run 35960067543). Both fail only at signing, so the check comes before the version is added.
### Runbook 08 re-checks the stored profile for push

Part 4 decodes the stored profile and greps the four names §1.7 requires, `aps-environment` among them, so a profile without Push Notifications is caught before a release.

### Runbook 08 reads binaries back with --out-file

The *Check everything* part of `08-mobile-setup.md` reads the certificate and profile with `--out-file`, imports the `.p12` into a throwaway keychain, parses the profile, and says stdout redirection corrupts binary payloads.

The key id and issuer id are entered with `read -r` rather than inline placeholders, because the placeholder was once stored verbatim as a version.
### README records the iOS signing expiry

The environment table in `docs/runbooks/README.md` has an *iOS signing* row naming the certificate and profile ids and their expiry date, so renewal is a dated task rather than a surprise.

### README records the GitHub token

The environment table in `docs/runbooks/README.md` has a *GitHub token* row naming who minted it and that it has no expiry, because a token without expiry fails nobody until it is revoked.

### Project config declares the budget

`Pulumi.yaml` declares `billingAccount` and `budgetAmount` with a numeric default, so every stack gets a budget alert and the amount is a visible config change ([[deployment#Infrastructure]]).

### Staging keeps the billing account secret

`Pulumi.staging.yaml` carries `reward-app:billingAccount` only under `secure:`, never in plain text, because the repository is public and the id is a foothold for social engineering.

### Program declares the budget

`index.ts` enables `billingbudgets.googleapis.com` and declares one `gcp.billing.Budget` filtered to `projects/<number>` of the stack's project, so the alert cannot drift to another project on the same billing account.

### Runbook 03 points at the declared budget

The `Costs` section of `03-infrastructure-change.md` names `budgetAmount` and no longer tells the operator to set an alert by hand.

### Root pubspec declares the pub workspace

The root `pubspec.yaml` lists `packages/domain`, `apps/mobile` and `services/api` under `workspace:` and each resolves with `resolution: workspace`, so one `dart pub get` at the root resolves every Dart package.

### Verify gate analyses and tests the Dart workspace

`verify.yml` has a `dart` job that runs `dart pub get`, `dart analyze --fatal-infos` at the root and `dart test` in `packages/domain`, so the port is held to the same gate as the PWA.

The Dart SDK comes from the Flutter SDK, because the workspace includes the Flutter app.

### Verify gate analyses and tests the Flutter app

`verify.yml` has a `flutter` job with `working-directory: apps/mobile` that runs `flutter analyze --fatal-infos` and `flutter test`, so a widget failure names itself rather than hiding in the Dart job ([[mobile-tests]]).

### Flutter version is pinned once with FVM

`.fvmrc` at the root names the exact Flutter version and every `subosito/flutter-action` step in `verify.yml` and `release-mobile.yml` reads it with `flutter-version-file: .fvmrc`, so laptops and CI share one SDK.

The version number lives in one file, and `fvm flutter` on a laptop uses the same SDK as the runners.

### Mobile Makefile is the app's script runner

`apps/mobile/Makefile` defines `help`, `init`, `build`, `test`, `e2e` and `deploy`, every recipe calls `fvm flutter` or `fvm dart` rather than a bare SDK, and the app README lists each target, so the entry points are discoverable and pinned ([[mobile-architecture#Make targets]]).

### macOS is a local run target only

`make build macos` and `make run macos` work, a bare `make build` and the release workflow still cover only iOS and Android, and the macOS target carries the network entitlement with no Podfile ([[mobile-architecture#Make targets]]).

Checked: `PLATFORMS` includes `macos` and `build-macos` calls `fvm flutter build macos`; `RELEASE_PLATFORMS` stays `ios android` and `build` iterates it; `pick-device.sh` has a `macos` case; both entitlements files grant `com.apple.security.network.client`; `apps/mobile/macos/Podfile` does not exist; the README shows `make run macos` and `make build macos`; `release-mobile.yml` never runs `build macos`; the Make targets section names the platform.

### Root Makefile runs the verify gate locally

The root `Makefile` has `verify` and `verify-full` targets, `init` points `core.hooksPath` at `.githooks`, the committed `pre-push` hook is executable and calls `make verify`, and runbook 02 names it as the step before a push ([[infra#Local verify]]).

### Identity Platform signs people in with Google and Apple

`infra/index.ts` enables the Firebase and Identity Toolkit APIs, adds Firebase to the project, turns on Identity Platform, and declares the `google.com` and `apple.com` providers from the runbook 08 config ([[api-architecture#Sign-in]]).

Each provider is declared only once its keys are set, so the preview passes before the hand steps are done.

### The app is registered with Firebase on both platforms

`infra/index.ts` declares a Firebase Apple app and Android app for `com.helpmebrands.reward` and exports each app id, each API key read from the app's config file, and the iOS URL scheme, which the app's Firebase options are copied from ([[mobile-architecture#Sign-in]]).

### Google sign-in returns to the app on iOS

`Info.plist` registers the staging `firebaseIosUrlScheme` so Google's web flow comes back to the app, and the Identity Platform config declares email and phone sign-in off so previews stay clean.

### Invite links have the api's own domain

`infra/index.ts` maps `apiCustomDomain` to the api service and sets `INVITE_LINK_BASE` and `ANDROID_SHA256_FINGERPRINTS` on it; the staging stack sets `apiCustomDomain` to `api.staging.helpmereward.com` ([[api-architecture#Invite links]]).

### The sign-in credentials are the runbook's keys

`Pulumi.yaml` declares every key runbook 08 sets, and the runbook names each one; the staging stack commits `appleTeamId: LMFUSVPCDH`, which is not secret.

### The api knows its Firebase project

The api service's container sets `FIREBASE_PROJECT_ID` to the stack's project, so the tokens it accepts are this environment's.

### The api define is tested with and without it

The `flutter` job of `verify.yml` and `make check` in `apps/mobile` both run `flutter test test/api_config_test.dart --dart-define=API_BASE_URL=https://example.test` after the plain run, so both cases of [[mobile-tests#Api config]] run in review.

### The api spec is linted as OpenAPI in CI and locally

The `api` job of `verify.yml` and the `api` target of the root `Makefile` both run `npx --yes @redocly/cli@<pinned> lint services/api/openapi.yaml`, so an invalid spec fails review before the contract test reads it ([[api-architecture#Contract]]).

### Verify gate builds and smoke-tests the api

`verify.yml` has an `api` job that analyses and tests `services/api`, builds `services/api/Dockerfile` from the repository root and requests `/health` from the running container, so a broken image fails review rather than the deploy ([[api-architecture#Container]]).

The job must not mention `/healthz` at all: Google's edge reserves that path on Cloud Run, so a smoke test on it would pass in CI and fail on staging ([[api-architecture#Handler]]).

### Api job tests against a Postgres service container

The `api` job in `verify.yml` declares a `postgres:16` service with a `pg_isready` health check and runs `dart test` with a `DATABASE_URL` carrying `sslmode=disable`, so the migration integration tests run in review instead of skipping ([[api-architecture#Migrations]]).

### Api CD workflow is path-filtered to the api and the domain

`cd-api.yml` triggers on `services/api/**` and `packages/domain/**` and never mentions `apps/pwa`; `cd.yml` carries a `paths-ignore` naming `services/api/**`, so a merge to one deployable does not roll the other ([[deployment#Pipeline]]).

### Api CD builds, migrates, deploys and smoke-tests

`cd-api.yml` builds `services/api/Dockerfile`, updates and executes `API_MIGRATION_JOB`, deploys `API_CLOUD_RUN_SERVICE` by the built digest, then smoke-tests the live URL.

The smoke test reads `/health` (never `/healthz`) and posts a device without a token, expecting 401 `unauthenticated`, which proves the service was given its Firebase project.

### CD revision names carry the run number

`cd.yml` and `cd-api.yml` pass `--revision-suffix=sha-${{ github.sha }}-${{ github.run_number }}`, so a manual dispatch of an already-deployed commit makes a new revision instead of failing `ALREADY_EXISTS`.

### Api image carries the migrator and the migrations

`services/api/Dockerfile` compiles `bin/migrate.dart` to `/app/migrate` and the runtime stage copies it to `/migrate` with `migrations/` at `/migrations`, where the binary resolves them ([[api-architecture#Container]]).

### Api image carries the reminder sender

`services/api/Dockerfile` compiles `bin/remind.dart` to `/app/remind` and the runtime stage copies it to `/remind` ([[api-architecture#Reminder sender]]).

### The reminder job runs /remind as the api identity

`infra/index.ts` declares the Cloud Run job `${apiServiceName}-remind` running `/remind` as the api runtime account, with `DATABASE_URL` from the secret and `FIREBASE_PROJECT_ID`, its image left to CI.

### Cloud Scheduler runs the reminder job every 15 minutes

A `gcp.cloudscheduler.Job` on `*/15 * * * *` in `Etc/UTC` posts to the job's `run.googleapis.com/v2/…:run` URL with an OAuth token for its own scheduler account.

That account holds `run.invoker` on that job only, and `cloudscheduler.googleapis.com` is enabled.

### The api identity may send through FCM

`fcm.googleapis.com` is enabled and the api runtime account holds `firebasecloudmessaging.admin`, so it sends with a metadata-server token; the program creates no service-account key.

### CD moves the reminder job to each new image

`cd-api.yml` runs `gcloud run jobs update ${{ vars.API_REMIND_JOB }}` with the built digest; the program writes `API_REMIND_JOB` onto the environment, exports `apiRemindJob`, and grants the deployer `run.developer` on the job.

### Api service runs on the gen2 execution environment

`infra/index.ts` sets `EXECUTION_ENVIRONMENT_GEN2` on the api service and both job templates (migration and reminders), because on the first-generation sandbox a Dart connect to the Cloud SQL unix socket never completes ([[deployment#Infrastructure]]).

### Stack outputs name the api service and job

`infra/index.ts` exports `apiCloudRunService`, `apiServiceUrl` and `apiMigrationJob`, the values `cd-api.yml` reads as repository variables ([[deployment#Infrastructure]]).

### Root package declares the workspaces

The root `package.json` lists exactly `apps/pwa` and `infra` as npm workspaces, so one lockfile covers both and `npm test`, `lint`, `typecheck` and `build` delegate from the root ([[pwa#Source layout]]).

### The PWA lives in apps/pwa

`apps/pwa/package.json` is still `@helpmebrands/reward-app`, and its `Dockerfile` and `deploy/nginx.conf.template` moved with it, so the frozen reference app is self-contained under one path.

### Workflows build the PWA image from its Dockerfile

Both `verify.yml` and `cd.yml` pass `file: apps/pwa/Dockerfile` with the repository root as the build context, which is what lets the image `npm ci` against the workspace lockfile ([[deployment#Container]]).

### The graph is split by area

`apps/pwa/tests/lat-graph.test.ts` checks that `lat.md/` holds only its index at the top level and that `product/`, `pwa/` and `infra/` each hold at least one file, so every new section has to choose an owner.

### The index names the three areas

`lat.md/lat.md` links each subdirectory, so a reader landing on the index finds the product spec, the frozen PWA and the platform without guessing.

### The product spec names no PWA technology

No file under `lat.md/product/` mentions Solid, IndexedDB, Vite, the service worker or Web Push, because the Dart port and the Flutter app are written against it and must not inherit a browser decision by accident.

### Every workflow action declares the Node 24 runtime

Every `uses:` in `.github/workflows/` pins a major at or above the first one whose `action.yml` declares `node24`, so no run prints the Node 20 deprecation warning ([[deployment#Pipeline#Action runtimes]]).

The floors live in an audited table in the test. An action missing from the table fails the test, which forces the audit on every new dependency.

### Pulumi CLI comes from the maintained action

`verify.yml` installs the CLI with `pulumi/actions` in install-only mode (a `pulumi-version` and no `command`), never `pulumi/setup-pulumi`, which still declares Node 12 and was last committed in 2021 ([[deployment#Pipeline#Action runtimes]]).

### Nobody opts back into Node 20

No workflow, runbook, Makefile or Pulumi program sets `ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION`; the runtime is Node 24 because every action asks for it, not because the warning was silenced.

### Dependabot watches the workflow actions

`.github/dependabot.yml` is version 2 with a `github-actions` entry, so the next runtime deprecation arrives as a pull request instead of a warning on every run ([[deployment#Pipeline#Action runtimes]]).
