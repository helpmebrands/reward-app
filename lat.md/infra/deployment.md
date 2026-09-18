# Deployment

`develop` is the integration branch. A pull request runs the quality gate; merging builds an image, deploys a new Cloud Run revision, and smoke-tests the live URL.

Infrastructure is Pulumi, and GitHub authenticates to Google with Workload Identity Federation, so no service-account key exists anywhere.

The runbooks in `docs/runbooks/` cover it end to end: initial deployment, routine changes, infrastructure changes, rollback and troubleshooting.

## Ownership rule

Pulumi owns the shape of the service; CI owns which image runs. Getting this wrong causes a silent rollback of production.

Every deploy points Cloud Run at a new image digest. If Pulumi also managed the image, the next `pulumi up` would reset the service to whichever digest it last recorded, deploying old code as a side effect of an unrelated infrastructure change. So `infra/index.ts` declares `ignoreChanges` on the container image, and the first `pulumi up` uses a public placeholder image that CI replaces within minutes.

## Pipeline

Three workflows in `.github/workflows/`, with the quality gate defined once and called twice.

- **`verify.yml`** is the gate: `npm ci` at the root, then lint, typecheck, test and build through the workspace scripts, uploading `apps/pwa/dist/`; an `infra` job that runs `npm ci --workspace infra` and `tsc --noEmit`, then authenticates keylessly as the deployer and runs `pulumi preview` against the staging state, so a review sees the exact diff an infrastructure change would apply ([[infra-tests#Infrastructure config#Verify gate previews the Pulumi program with keyless credentials]]); a `dart` job that resolves the pub workspace, analyses it and runs the `packages/domain` tests ([[infra-tests#Infrastructure config#Verify gate analyses and tests the Dart workspace]]); a `flutter` job that analyses and tests `apps/mobile` ([[infra-tests#Infrastructure config#Verify gate analyses and tests the Flutter app]]); an `api` job that tests `services/api`, builds its image and smoke-tests `/healthz` ([[infra-tests#Infrastructure config#Verify gate builds and smoke-tests the api]]); and a container job that builds the image from `apps/pwa/Dockerfile` without pushing and smoke-tests it.
- **`ci.yml`** calls it on every pull request into `develop` or `main`. A new push cancels the previous run.
- **`cd.yml`** runs on push to `develop` and on manual dispatch. It calls the gate *again* rather than trusting the PR's tick, because the merge commit is not the commit CI tested. Deploys never cancel in flight; interrupting a Cloud Run rollout leaves traffic split between revisions.

The image is tagged with the commit SHA, never `latest`, and deployed by digest rather than tag. A digest is the exact bytes that were tested a step ago, and naming it is what makes a rollback a one-line command.

### Smoke tests

The deploy reporting success only means Cloud Run accepted the revision. The smoke tests, run against the container in CI and the live URL after a deploy, assert the app is actually served.

They check that `/` and a client route return 200, that a missing asset 404s rather than returning HTML, and that `sw.js` carries `Cache-Control: no-store`. The last one guards the failure this pipeline most needs to catch ([[deployment#Cache rules]]).

## Container

A two-stage `apps/pwa/Dockerfile`, built with the repository root as its context because the npm workspace keeps its one lockfile there.

`node:22-alpine` copies the root and workspace manifests, runs `npm ci --workspace apps/pwa` and `npm run build --workspace apps/pwa` (which typechecks first, so a type error fails the image), then `nginx-unprivileged` serves `apps/pwa/dist/` as uid 101 on port 8080. The root `.dockerignore` keeps everything but the manifests and `apps/pwa` out of the context.

Cloud Run was chosen over object hosting because the roadmap has a Web Push backend; this container can grow an `/api` route without a second piece of infrastructure. Cloud Run injects `PORT`, and the stock nginx entrypoint runs `envsubst` over the config template, filtered to `PORT` so nginx's own `$uri` and `$host` survive. There is no `HEALTHCHECK`: Cloud Run runs its own probes.

`VITE_VAPID_PUBLIC_KEY` and `VITE_PUSH_API` are build args because Vite inlines them at build time ([[architecture#Environment variables]]).

## Cache rules

The cache headers in `apps/pwa/deploy/nginx.conf.template` are correctness, not performance. If `sw.js` or `index.html` sit in a browser cache, a user stays pinned to an old service worker and an old reminder schedule.

That failure is silent: notifications quietly stop matching the data, and nothing else surfaces it.

| Path | Cache-Control | Why |
| --- | --- | --- |
| `/sw.js` | `no-cache, no-store, must-revalidate` | The browser must notice a new build immediately. |
| `/index.html` and client routes | `no-cache` | Same, for the shell. Client routes fall through to `index.html`. |
| `/assets/` | `public, max-age=31536000, immutable` | Vite fingerprints every file, so the URL changes when the bytes do. |
| `/icons/` | `public, max-age=86400` | Fixed filenames named by the manifest, so not immutable. |
| `/manifest.webmanifest` | `public, max-age=3600` | Needs its own media type or the browser ignores it. |

Two traps the config avoids: the immutable header on `/assets/` is set without `always`, so a 404 is never cached for a year mid-rollout; and a missing asset must 404 rather than fall through to the shell, because HTML served under a `.js` URL breaks service-worker precaching in a way that looks like a corrupt cache.

## Security headers

`apps/pwa/deploy/security-headers.conf` is included in every `location` block, because nginx's `add_header` does not inherit: a block that declares one header drops every header from its parent.

A location that forgets the include is therefore a silently unprotected route.

The Content Security Policy is same-origin apart from the Inter webfont. `script-src` is strict, which is the directive that stops an injection becoming code execution. `style-src` allows `'unsafe-inline'` because Solid's `style={{...}}` prop writes a style attribute; removing it leaves the app unstyled, and tightening it means moving every inline style into a class. `connect-src` is `'self'` only, so a push backend's origin must be added there or the subscription POST is blocked.

## Infrastructure

`infra/index.ts` declares everything the app needs to be built by GitHub and served by Cloud Run: an image registry, the service, its runtime identity, and a keyless trust path from this repository.

The stack name doubles as the environment (`staging`, `prod`).

Provider settings (`gcp:project`, `gcp:region`) and `githubRepo` live per stack in `infra/Pulumi.<stack>.yaml`. `Pulumi.yaml` declares only the project's own unprefixed keys, because Pulumi rejects a namespaced key declared at project level without a value. `Pulumi.staging.yaml` targets `helpme-reward-staging` and trusts `helpmebrands/reward-app`; the test in [[infra-tests#Infrastructure config]] pins both.

Secrets are encrypted with a Cloud KMS key: `Pulumi.staging.yaml` names it in `secretsprovider` (`gcpkms://…/keyRings/pulumi/cryptoKeys/staging`) and carries the stack's wrapped data key in `encryptedkey`, both safe to commit ([[infra-tests#Infrastructure config#Staging uses the KMS secrets provider]]). The key ring and key were created by hand with `gcloud kms` on 2026-09-18 before `pulumi stack change-secrets-provider`, because the key that guards the state cannot live in the state; a new environment repeats that bootstrap. The first secret is the api's database password, generated in the program and never typed by a human. Pulumi state lives in the versioned GCS bucket `gs://helpme-reward-staging-pulumi-state`, never on a laptop; the bucket and key are named in config (`stateBucket`, `secretsKey`) so the program can grant the deployer preview access to them. Runbook 01 step 2 is the only login procedure, so a second, competing copy of the state is never initialised.

- **APIs** are enabled explicitly and everything depends on them, because enabling is slow and eventually consistent. `disableOnDestroy: false` so tearing down the stack does not switch APIs off underneath anything else.
- **Artifact Registry** keeps the 30 most recent images (rollbacks need them) and deletes untagged images after seven days, so the registry does not grow and bill forever.
- **The runtime service account holds no roles.** The container serves static files and all user data is in the browser, so it has no reason to reach any Google API. Running as the default compute account would hand an attacker who achieved code execution a project-wide identity for nothing.
- **The service** scales 0 to 4 instances, 80 concurrent requests each, CPU only while a request is in flight, with a fast TCP startup probe so a broken image fails rather than hangs. `deletionProtection` is on for the `prod` stack. It is public through `invokerIamDisabled` on the service rather than an `allUsers` invoker binding: the organisation's domain-restricted sharing policy rejects `allUsers` in any IAM policy, and skipping the invoker check on one service is narrower than a project-wide policy exception. The service-level `scaling` block the API reports back is in `ignoreChanges`, or every preview would propose removing it.
- **The database** is one Cloud SQL PostgreSQL 16 instance, `reward-api-db-<env>`, at the tier in `dbTier` (`db-f1-micro` by default, the smallest, raised with load), zonal, 10 GB with autoresize, nightly backups on. Public IP with no authorised networks and `ENCRYPTED_ONLY`: nothing connects directly; Cloud Run reaches it through the Cloud SQL connector, a unix socket the platform mounts, authenticated as the runtime identity. It holds the `reward` database and the `api` user, whose password is a `random.RandomPassword` known only to the state and to Secret Manager. Deletion protection follows the `prod` stack like the service.
- **The database secret** `reward-api-database-url-<env>` in Secret Manager holds the whole `DATABASE_URL`, so the api reads one variable on Cloud Run exactly as it does against docker compose ([[api-architecture#Migrations]]). Its form is `postgres://api:<password>@/reward?host=/cloudsql/<connection name>/.s.PGSQL.5432&sslmode=disable`: an empty authority with the socket in `host`, the socket file named in full because the Dart driver connects to that path verbatim rather than appending the file name as libpq does, and TLS off because the connector already encrypts.
- **The api runtime identity** `reward-api-run-<env>` holds exactly `cloudsql.client` (grantable only project-wide) and `secretmanager.secretAccessor` on that one secret. The PWA's runtime account is unchanged and still holds nothing.
- **Keyless deploys.** A Workload Identity Pool trusts GitHub's OIDC issuer, with an attribute condition pinning the repository owner. Only workflows from the configured `githubRepo` may impersonate the deployer account, which holds `artifactregistry.writer` on the one repository and `run.developer` on the one service, plus `serviceAccountUser` on the runtime account, which deploying a service that runs as another identity requires. No service-account key exists anywhere.
- **Previews from CI.** So the `infra` job can run `pulumi preview`, the deployer also holds three read-side roles: `viewer` on the project (read everywhere, and not secret payloads), `storage.objectUser` on the state bucket (a preview takes the state lock, which is an object write) and `cloudkms.cryptoKeyDecrypter` on the one secrets key (the state's secrets must decrypt to diff). None of these can apply a change: the deployer still cannot `pulumi up`.
- **Custom domain** mapping is created only when configured, because it fails unless the domain has already been verified in Search Console by the account running `pulumi up`, a manual step. DNS for `helpmereward.com` is in Cloudflare, and the mapping's CNAME must stay DNS-only (unproxied) or Google's managed certificate never issues; runbook 03 has the procedure and the proxy caveats.

Staging is project `helpme-reward-staging` in `us-central1`, stack `staging`, service `reward-app` at <https://staging.helpmereward.com> (the `run.app` URL <https://reward-app-bduraqeztq-uc.a.run.app> still answers), deployed from `develop` since 2026-09-17. The apex `helpmereward.com` is reserved for `prod`. The table in `docs/runbooks/README.md` is the record; [[infra-tests#Infrastructure config]] pins it.

The stack outputs are exactly the values GitHub needs as repository variables: `WIF_PROVIDER`, `DEPLOY_SERVICE_ACCOUNT`, `CLOUD_RUN_SERVICE`, `ARTIFACT_REPO`, `GCP_REGION`, `GCP_PROJECT_ID`; plus, for the api's service and runbook 06, `apiRuntimeServiceAccount`, `databaseInstanceConnectionName` and `databaseUrlSecretId`.
