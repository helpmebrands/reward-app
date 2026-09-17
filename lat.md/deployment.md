# Deployment

`develop` is the integration branch. A pull request runs the quality gate; merging builds an image, deploys a new Cloud Run revision, and smoke-tests the live URL.

Infrastructure is Pulumi, and GitHub authenticates to Google with Workload Identity Federation, so no service-account key exists anywhere.

The runbooks in `docs/runbooks/` cover it end to end: initial deployment, routine changes, infrastructure changes, rollback and troubleshooting.

## Ownership rule

Pulumi owns the shape of the service; CI owns which image runs. Getting this wrong causes a silent rollback of production.

Every deploy points Cloud Run at a new image digest. If Pulumi also managed the image, the next `pulumi up` would reset the service to whichever digest it last recorded, deploying old code as a side effect of an unrelated infrastructure change. So `infra/index.ts` declares `ignoreChanges` on the container image, and the first `pulumi up` uses a public placeholder image that CI replaces within minutes.

## Pipeline

Three workflows in `.github/workflows/`, with the quality gate defined once and called twice.

- **`verify.yml`** is the gate: `npm ci`, lint, typecheck, test, build, upload `dist/`; an `infra` job that runs `npm ci` and `tsc --noEmit` in `infra/` so a type error in the Pulumi program fails review rather than the next hand-run `pulumi up` (`pulumi preview` needs credentials and stays out); and a container job that builds the image without pushing and smoke-tests it.
- **`ci.yml`** calls it on every pull request into `develop` or `main`. A new push cancels the previous run.
- **`cd.yml`** runs on push to `develop` and on manual dispatch. It calls the gate *again* rather than trusting the PR's tick, because the merge commit is not the commit CI tested. Deploys never cancel in flight; interrupting a Cloud Run rollout leaves traffic split between revisions.

The image is tagged with the commit SHA, never `latest`, and deployed by digest rather than tag. A digest is the exact bytes that were tested a step ago, and naming it is what makes a rollback a one-line command.

### Smoke tests

The deploy reporting success only means Cloud Run accepted the revision. The smoke tests, run against the container in CI and the live URL after a deploy, assert the app is actually served.

They check that `/` and a client route return 200, that a missing asset 404s rather than returning HTML, and that `sw.js` carries `Cache-Control: no-store`. The last one guards the failure this pipeline most needs to catch ([[deployment#Cache rules]]).

## Container

A two-stage `Dockerfile`: `node:22-alpine` runs `npm ci` and `npm run build` (which typechecks first, so a type error fails the image), then `nginx-unprivileged` serves `dist/` as uid 101 on port 8080.

Cloud Run was chosen over object hosting because the roadmap has a Web Push backend; this container can grow an `/api` route without a second piece of infrastructure. Cloud Run injects `PORT`, and the stock nginx entrypoint runs `envsubst` over the config template, filtered to `PORT` so nginx's own `$uri` and `$host` survive. There is no `HEALTHCHECK`: Cloud Run runs its own probes.

`VITE_VAPID_PUBLIC_KEY` and `VITE_PUSH_API` are build args because Vite inlines them at build time ([[architecture#Environment variables]]).

## Cache rules

The cache headers in `deploy/nginx.conf.template` are correctness, not performance. If `sw.js` or `index.html` sit in a browser cache, a user stays pinned to an old service worker and an old reminder schedule.

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

`deploy/security-headers.conf` is included in every `location` block, because nginx's `add_header` does not inherit: a block that declares one header drops every header from its parent.

A location that forgets the include is therefore a silently unprotected route.

The Content Security Policy is same-origin apart from the Inter webfont. `script-src` is strict, which is the directive that stops an injection becoming code execution. `style-src` allows `'unsafe-inline'` because Solid's `style={{...}}` prop writes a style attribute; removing it leaves the app unstyled, and tightening it means moving every inline style into a class. `connect-src` is `'self'` only, so a push backend's origin must be added there or the subscription POST is blocked.

## Infrastructure

`infra/index.ts` declares everything the app needs to be built by GitHub and served by Cloud Run: an image registry, the service, its runtime identity, and a keyless trust path from this repository.

The stack name doubles as the environment (`staging`, `prod`).

Provider settings (`gcp:project`, `gcp:region`) and `githubRepo` live per stack in `infra/Pulumi.<stack>.yaml`. `Pulumi.yaml` declares only the project's own unprefixed keys, because Pulumi rejects a namespaced key declared at project level without a value. `Pulumi.staging.yaml` targets `helpme-reward-staging` and trusts `helpmebrands/reward-app`; the test in [[tests#Infrastructure config]] pins both.

The stack holds no secrets, so its passphrase is empty (`PULUMI_CONFIG_PASSPHRASE=""`); runbook 01 says to move to a real secrets provider before the first secret. Pulumi state lives in the versioned GCS bucket `gs://helpme-reward-staging-pulumi-state`, never on a laptop. Runbook 01 step 2 is the only login procedure, so a second, competing copy of the state is never initialised.

- **APIs** are enabled explicitly and everything depends on them, because enabling is slow and eventually consistent. `disableOnDestroy: false` so tearing down the stack does not switch APIs off underneath anything else.
- **Artifact Registry** keeps the 30 most recent images (rollbacks need them) and deletes untagged images after seven days, so the registry does not grow and bill forever.
- **The runtime service account holds no roles.** The container serves static files and all user data is in the browser, so it has no reason to reach any Google API. Running as the default compute account would hand an attacker who achieved code execution a project-wide identity for nothing.
- **The service** scales 0 to 4 instances, 80 concurrent requests each, CPU only while a request is in flight, with a fast TCP startup probe so a broken image fails rather than hangs. `deletionProtection` is on for the `prod` stack. It is public through `invokerIamDisabled` on the service rather than an `allUsers` invoker binding: the organisation's domain-restricted sharing policy rejects `allUsers` in any IAM policy, and skipping the invoker check on one service is narrower than a project-wide policy exception. The service-level `scaling` block the API reports back is in `ignoreChanges`, or every preview would propose removing it.
- **Keyless deploys.** A Workload Identity Pool trusts GitHub's OIDC issuer, with an attribute condition pinning the repository owner. Only workflows from the configured `githubRepo` may impersonate the deployer account, which holds exactly two scoped roles: `artifactregistry.writer` on the one repository and `run.developer` on the one service, plus `serviceAccountUser` on the runtime account, which deploying a service that runs as another identity requires. No service-account key exists anywhere.
- **Custom domain** mapping is created only when configured, because it fails unless the domain has already been verified in Search Console by the account running `pulumi up`, a manual step. DNS for `helpmereward.com` is in Cloudflare, and the mapping's CNAME must stay DNS-only (unproxied) or Google's managed certificate never issues; runbook 03 has the procedure and the proxy caveats.

Staging is project `helpme-reward-staging` in `us-central1`, stack `staging`, service `reward-app` at <https://reward-app-bduraqeztq-uc.a.run.app>, deployed from `develop` since 2026-09-17. The table in `docs/runbooks/README.md` is the record; [[tests#Infrastructure config]] pins it.

The stack outputs are exactly the values GitHub needs as repository variables: `WIF_PROVIDER`, `DEPLOY_SERVICE_ACCOUNT`, `CLOUD_RUN_SERVICE`, `ARTIFACT_REPO`, `GCP_REGION`, `GCP_PROJECT_ID`.
