# Infrastructure tests

What the repository-level suites pin: the Pulumi configuration, the runbooks that quote it, the workflows, the monorepo layout and the shape of this graph.

## Infrastructure config

`apps/pwa/tests/infra-config.test.ts` pins the committed Pulumi configuration, the runbooks that quote it and the monorepo layout ([[deployment#Infrastructure]]). Drift here is only noticed when a deploy is rejected at the auth step.

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

`index.ts` imports `@pulumi/github`, reads `.github/workflows/verify.yml` and declares one `github.RepositoryRuleset` whose required checks come from `requiredChecks`, so the ruleset and the workflow cannot disagree.

### Every verify job is a required check

Applied to the real `verify.yml`, the derivation yields exactly one context per job and includes all seven current job names, so a red Dart, Flutter, api or accessibility job blocks a merge.

### Staging names the GitHub owner

`Pulumi.staging.yaml` sets `github:owner` to `helpmebrands` and never carries `github:token` in plain text; the token is secret config or the `GITHUB_TOKEN` environment variable.

### Verify gate previews GitHub resources with the workflow token

The `Preview against staging` step passes `GITHUB_TOKEN: ${{ github.token }}`, which can read the repository but not administer it, all a preview without refresh needs ([[deployment#Pipeline]]).

### Runbook 01 describes the ruleset, not the settings UI

Step 6 of `01-initial-deployment.md` names `RepositoryRuleset` and the one-time `pulumi import`, and no longer sends the operator to *Settings → Branches*.

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

### Verify gate builds and smoke-tests the api

`verify.yml` has an `api` job that analyses and tests `services/api`, builds `services/api/Dockerfile` from the repository root and requests `/health` from the running container, so a broken image fails review rather than the deploy ([[api-architecture#Container]]).

The job must not mention `/healthz` at all: Google's edge reserves that path on Cloud Run, so a smoke test on it would pass in CI and fail on staging ([[api-architecture#Handler]]).

### Api job tests against a Postgres service container

The `api` job in `verify.yml` declares a `postgres:16` service with a `pg_isready` health check and runs `dart test` with a `DATABASE_URL` carrying `sslmode=disable`, so the migration integration tests run in review instead of skipping ([[api-architecture#Migrations]]).

### Api CD workflow is path-filtered to the api and the domain

`cd-api.yml` triggers on `services/api/**` and `packages/domain/**` and never mentions `apps/pwa`; `cd.yml` carries a `paths-ignore` naming `services/api/**`, so a merge to one deployable does not roll the other ([[deployment#Pipeline]]).

### Api CD builds, migrates, deploys and smoke-tests

`cd-api.yml` builds `services/api/Dockerfile`, updates and executes `API_MIGRATION_JOB`, deploys `API_CLOUD_RUN_SERVICE` by the built digest, then smoke-tests the live URL.

The smoke test reads `/health` (never `/healthz`) and posts a device with the zone `Mars/Olympus_Mons`, expecting the database-backed 400.

### Api image carries the migrator and the migrations

`services/api/Dockerfile` compiles `bin/migrate.dart` to `/app/migrate` and the runtime stage copies it to `/migrate` with `migrations/` at `/migrations`, where the binary resolves them ([[api-architecture#Container]]).

### Api service runs on the gen2 execution environment

`infra/index.ts` sets `EXECUTION_ENVIRONMENT_GEN2` on both the api service and the migration job templates, because on the first-generation sandbox a Dart connect to the Cloud SQL unix socket never completes ([[deployment#Infrastructure]]).

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
