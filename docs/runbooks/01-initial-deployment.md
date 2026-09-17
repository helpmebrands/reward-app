# 01 — Initial deployment

From an empty Google Cloud project to a live URL. You do this once per
environment. Budget about 45 minutes, most of it waiting on API enablement.

## Before you start

| Need | Check |
| --- | --- |
| Node 22+ | `node -v` |
| Pulumi CLI | `pulumi version` — [install](https://www.pulumi.com/docs/install/) |
| gcloud CLI | `gcloud version` — [install](https://cloud.google.com/sdk/docs/install) |
| A Google Cloud project **with billing enabled** | `gcloud billing projects describe <PROJECT_ID>` |
| `roles/owner` (or equivalent) on that project | Needed to enable APIs and create IAM bindings |
| Admin on the GitHub repository | Needed to set variables and branch protection |

Billing genuinely must be on. Cloud Run and Artifact Registry both refuse to
enable without it, and the error arrives several steps later as a permission
failure that does not mention billing.

## 1. Pick a project and region

```sh
$ export PROJECT_ID=<your-project-id>
$ export REGION=us-central1

$ gcloud auth login
$ gcloud config set project "$PROJECT_ID"
```

Region matters more than it looks: Artifact Registry and Cloud Run should share
one, or every deploy pulls the image across regions and pays for it in both
latency and egress.

## 2. Log in to the state backend

Pulumi records what it has created. That state must outlive your laptop, so it
lives in a versioned GCS bucket in the staging project:

```sh
$ pulumi login gs://helpme-reward-staging-pulumi-state
$ pulumi whoami -v      # Backend URL must be the bucket, not file://~
```

Do not `pulumi stack init` against any other backend. A second copy of the
state means two programs each believing they own the same resources.

The bucket was created once, on 2026-09-17, with:

```sh
$ gcloud storage buckets create gs://helpme-reward-staging-pulumi-state \
    --project=helpme-reward-staging --location=us-central1 \
    --uniform-bucket-level-access
$ gcloud storage buckets update gs://helpme-reward-staging-pulumi-state --versioning
```

**Verify** versioning is on. State corruption is rare and unrecoverable
without it:

```sh
$ gcloud storage buckets describe gs://helpme-reward-staging-pulumi-state \
    --format='value(versioning_enabled)'
True
```

A new environment gets its own bucket, created the same way.

## 3. Select the stack

Stack configuration is committed: `infra/Pulumi.staging.yaml` carries the
project, region and `githubRepo`. The stack holds no secrets, so the passphrase
that would guard them is empty; export it or every command prompts for one.

```sh
$ cd infra
$ npm ci
$ export PULUMI_CONFIG_PASSPHRASE=""
$ pulumi stack select staging
$ pulumi config get reward-app:githubRepo     # helpmebrands/reward-app
```

`githubRepo` is a security control, not a label — it pins which repository is
allowed to mint credentials for this project. Get it wrong and deploys fail
with a permission error; leave it too broad and other repositories could
deploy.

Before the first secret goes into a stack, move it to a real secrets provider
(`pulumi stack change-secrets-provider "gcpkms://..."`). An empty passphrase
protects nothing.

A new environment is `pulumi stack init <env>` followed by
`pulumi config set gcp:project <project-id>` and the `githubRepo` above; commit
the resulting `Pulumi.<env>.yaml`. Optional:

```sh
$ pulumi config set reward-app:minInstances 1   # avoid cold starts, ~$10/mo
$ pulumi config set reward-app:maxInstances 4   # spend ceiling
```

## 4. Create the infrastructure

```sh
$ pulumi up
```

Read the preview before confirming. Expect 16 resources: six API enablements,
a registry, two service accounts, the Cloud Run service, the identity pool and
provider, and four IAM bindings. There is no `allUsers` invoker binding: the
organisation's domain-restricted sharing policy rejects one, so the service is
public through its own `invokerIamDisabled` setting instead.

The first run takes a few minutes because enabling APIs is slow. If it fails
with `SERVICE_DISABLED` or a permission error on the very first attempt, wait a
minute and run it again — API enablement is eventually consistent, and the
second run almost always succeeds.

**Verify.** The service exists and serves Google's placeholder page:

```sh
$ curl -sS -o /dev/null -w '%{http_code}\n' "$(pulumi stack output serviceUrl)"
200
```

A `200` here is the placeholder, not HelpMe Reward. That is expected — Cloud Run
cannot create a service without an image, and the real one does not exist until
CI builds it in step 7.

## 5. Give GitHub the values it needs

```sh
$ pulumi stack output
```

Set these as **repository variables** (Settings → Secrets and variables →
Actions → *Variables*), not secrets:

| Variable | From output |
| --- | --- |
| `GCP_PROJECT_ID` | `gcpProject` |
| `GCP_REGION` | `gcpRegion` |
| `ARTIFACT_REPO` | `artifactRepository` |
| `CLOUD_RUN_SERVICE` | `cloudRunService` |
| `WIF_PROVIDER` | `workloadIdentityProvider` |
| `DEPLOY_SERVICE_ACCOUNT` | `deployServiceAccount` |

None of these are secret. They are identifiers, and the actual trust is
enforced by Google against the repository name — a variable is the honest
classification, and it keeps them readable in logs when you are debugging a
failed deploy.

Or with the `gh` CLI, from `infra/`:

```sh
$ gh variable set GCP_PROJECT_ID        --body "$(pulumi stack output gcpProject)"
$ gh variable set GCP_REGION            --body "$(pulumi stack output gcpRegion)"
$ gh variable set ARTIFACT_REPO         --body "$(pulumi stack output artifactRepository)"
$ gh variable set CLOUD_RUN_SERVICE     --body "$(pulumi stack output cloudRunService)"
$ gh variable set WIF_PROVIDER          --body "$(pulumi stack output workloadIdentityProvider)"
$ gh variable set DEPLOY_SERVICE_ACCOUNT --body "$(pulumi stack output deployServiceAccount)"
```

### If you have Web Push keys

`VITE_VAPID_PUBLIC_KEY` and `VITE_PUSH_API` are **build-time** values — Vite
inlines them into the bundle, so setting them on the Cloud Run service does
nothing. Set them as repository variables and the CD workflow passes them as
build arguments. The VAPID *public* key is safe in a variable; the private key
belongs only to the push backend and never enters this repository.

Without them the app falls back to service-worker replay, which works.

## 6. Protect `develop`

Settings → Branches → Add rule for `develop`:

- Require a pull request before merging
- Require status checks to pass — add the CI checks (they appear in the list
  after the first pull request has run, so come back for this)
- Require branches to be up to date before merging

Without the second one, CI is advisory: a red pull request stays mergeable and
the deploy pipeline is the first thing to notice.

## 7. First real deploy

Merge anything into `develop`, or trigger one by hand:

```sh
$ gh workflow run cd.yml --ref develop
$ gh run watch
```

The workflow re-runs the full verify suite, builds the image, pushes it, points
Cloud Run at the digest, and smoke-tests the result.

**Verify** — the smoke test in the workflow already checks these, but confirm
by hand once so you know what good looks like:

```sh
$ URL=$(cd infra && pulumi stack output serviceUrl)

$ curl -sS -o /dev/null -w '%{http_code}\n' "$URL/"          # 200
$ curl -sS -o /dev/null -w '%{http_code}\n' "$URL/credits"   # 200 — SPA fallback
$ curl -sSI "$URL/sw.js" | grep -i cache-control             # must say no-store
```

Then open the URL in a browser: the app should load, and DevTools →
Application → Service Workers should show one activated.

## 8. Record what you did

Add the environment to the table in [README.md](README.md#environments):
project id, region, stack, state backend and URL. The repository variables are
the operational source of truth, but a new starter should not have to
reverse-engineer which GCP project is which. Staging was recorded there on
2026-09-17.

## What you have now

- A Cloud Run service on a `run.app` URL, publicly readable
- Images in Artifact Registry, tagged by commit SHA, pruned after 30 releases
- Keyless deploys from `develop` only
- A runtime identity with no permissions at all

Next: [02 — Routine change](02-routine-change.md), and read
[04 — Rollback](04-rollback.md) before you need it.
