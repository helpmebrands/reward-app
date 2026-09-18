# 01 — Initial deployment

From an empty Google Cloud project to two live URLs: the PWA and the api, with
its database. You do this once per environment. Budget about an hour, most of
it waiting on API enablement and Cloud SQL.

## Before you start

| Need | Check |
| --- | --- |
| Node 22+ | `node -v` |
| Pulumi CLI | `pulumi version` — [install](https://www.pulumi.com/docs/install/) |
| gcloud CLI | `gcloud version` — [install](https://cloud.google.com/sdk/docs/install) |
| A Google Cloud project **with billing enabled** | `gcloud billing projects describe <PROJECT_ID>` |
| `roles/owner` (or equivalent) on that project | Needed to enable APIs, create the KMS key and IAM bindings |
| Docker | `docker version` — the api runbooks use the `postgres:16` image for `psql` |
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

## 3. Create the secrets key and select the stack

The stack holds a secret — the api's database password — so its state and
config are encrypted with a Cloud KMS key. That key cannot live in the stack
it guards, so it is made by hand, once per environment, before the stack is
touched:

```sh
$ gcloud services enable cloudkms.googleapis.com --project "$PROJECT_ID"
$ gcloud kms keyrings create pulumi --location "$REGION" --project "$PROJECT_ID"
$ gcloud kms keys create <env> --keyring pulumi --location "$REGION" \
    --purpose encryption --project "$PROJECT_ID"
```

**Verify:**

```sh
$ gcloud kms keys list --keyring pulumi --location "$REGION" --project "$PROJECT_ID" \
    --format='value(name,purpose)'
projects/<project>/locations/us-central1/keyRings/pulumi/cryptoKeys/<env>   ENCRYPT_DECRYPT
```

Stack configuration is committed: `infra/Pulumi.staging.yaml` carries the
project, region, `githubRepo`, the state bucket and the key, and names the key
as its `secretsprovider`. Whoever runs Pulumi needs `cloudkms.cryptoKeyEncrypterDecrypter`
on the key; an owner has it.

```sh
$ cd infra
$ npm ci
$ pulumi stack select staging
$ pulumi config get reward-app:githubRepo     # helpmebrands/reward-app
```

`githubRepo` is a security control, not a label — it pins which repository is
allowed to mint credentials for this project. Get it wrong and deploys fail
with a permission error; leave it too broad and other repositories could
deploy.

A new environment is a new stack on the new key:

```sh
$ pulumi stack init <env> \
    --secrets-provider "gcpkms://projects/$PROJECT_ID/locations/$REGION/keyRings/pulumi/cryptoKeys/<env>"
$ pulumi config set gcp:project "$PROJECT_ID"
$ pulumi config set gcp:region "$REGION"
$ pulumi config set reward-app:githubRepo helpmebrands/reward-app
$ pulumi config set reward-app:stateBucket <the bucket from step 2>
$ pulumi config set reward-app:secretsKey projects/$PROJECT_ID/locations/$REGION/keyRings/pulumi/cryptoKeys/<env>
```

Commit the resulting `Pulumi.<env>.yaml`; the `encryptedkey` line in it is the
stack's data key wrapped by KMS and is safe to commit. Staging was moved from
its original empty passphrase with
`pulumi stack change-secrets-provider "gcpkms://…/cryptoKeys/staging"` on
2026-09-18, which is the command for an existing stack. Optional:

```sh
$ pulumi config set reward-app:minInstances 1   # avoid cold starts, ~$10/mo
$ pulumi config set reward-app:maxInstances 4   # spend ceiling
$ pulumi config set reward-app:dbTier db-custom-1-3840   # more database; db-f1-micro by default
```

## 4. Create the infrastructure

```sh
$ pulumi up
```

Read the preview before confirming. Expect 37 resources: nine API enablements,
a registry, three service accounts, two Cloud Run services and the migration
job, the Cloud SQL instance with its database and user, a generated password,
a Secret Manager secret and its version, the identity pool and provider, twelve
IAM bindings, and the domain mapping if one is configured. There is no
`allUsers` invoker binding: the organisation's domain-restricted sharing policy
rejects one, so both services are public through their own `invokerIamDisabled`
setting instead.

The first run takes six to ten minutes: enabling APIs is slow and Cloud SQL
takes about six minutes on its own. If it fails with `SERVICE_DISABLED` or a
permission error on the very first attempt, wait a minute and run it again —
API enablement is eventually consistent, and the second run almost always
succeeds.

**Verify.** Both services exist and serve Google's placeholder page:

```sh
$ curl -sS -o /dev/null -w '%{http_code}\n' "$(pulumi stack output serviceUrl)"
200
$ curl -sS -o /dev/null -w '%{http_code}\n' "$(pulumi stack output apiServiceUrl)"
200
```

A `200` here is the placeholder, not HelpMe Reward. That is expected — Cloud Run
cannot create a service without an image, and the real ones do not exist until
CI builds them in step 7. The database exists and is empty; the first api
deploy creates its tables.

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
| `API_CLOUD_RUN_SERVICE` | `apiCloudRunService` |
| `API_MIGRATION_JOB` | `apiMigrationJob` |

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
$ gh variable set API_CLOUD_RUN_SERVICE  --body "$(pulumi stack output apiCloudRunService)"
$ gh variable set API_MIGRATION_JOB      --body "$(pulumi stack output apiMigrationJob)"
```

The `infra` job of every pull request also runs `pulumi preview` with these
same variables, so a wrong one shows up on the next pull request rather than
the next deploy.

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

## 7. First real deploys

Each deployable has its own workflow, filtered to the paths that reach its
image. Trigger both by hand the first time:

```sh
$ gh workflow run cd.yml --ref develop       # the PWA
$ gh workflow run cd-api.yml --ref develop   # the api
$ gh run watch
```

Each re-runs the full verify suite, builds its image, pushes it, points Cloud
Run at the digest, and smoke-tests the result. The api workflow runs the
migration job on the new image before the service moves to it, so the first
run also creates the tables.

**Verify** — the smoke tests in the workflows already check these, but confirm
by hand once so you know what good looks like:

```sh
$ URL=$(cd infra && pulumi stack output serviceUrl)
$ API=$(cd infra && pulumi stack output apiServiceUrl)

$ curl -sS -o /dev/null -w '%{http_code}\n' "$URL/"          # 200
$ curl -sS -o /dev/null -w '%{http_code}\n' "$URL/credits"   # 200 — SPA fallback
$ curl -sSI "$URL/sw.js" | grep -i cache-control             # must say no-store

$ curl -sS "$API/health"                                     # {"status":"ok","version":"…"}
$ curl -sS -X POST "$API/v1/devices" -H 'content-type: application/json' \
    -d '{"token":"t","installationId":"i","platform":"ios","timezone":"Mars/Olympus_Mons"}'
{"error":"invalid","field":"timezone"}                       # a 400 that came through the database
```

The last request is the one that proves the database path: the zone is shaped
correctly, so only Postgres can refuse it. Do not use `/healthz` for anything
on Cloud Run; Google's edge answers that exact path itself and the container
never sees it.

Then open the PWA URL in a browser: the app should load, and DevTools →
Application → Service Workers should show one activated.

## 8. Record what you did

Add the environment to the table in [README.md](README.md#environments):
project id, region, stack, state backend, services, job, database, secret,
key and URLs. The repository variables are the operational source of truth,
but a new starter should not have to reverse-engineer which GCP project is
which. Staging was recorded there on 2026-09-17 and extended for the api on
2026-09-18.

## What you have now

- Two Cloud Run services on `run.app` URLs, publicly readable: the PWA and the api
- A Cloud SQL PostgreSQL 16 instance the api reaches over the Cloud SQL
  connector, with nightly backups, and a migration job that runs before each
  api deploy
- The api's connection URL in Secret Manager, readable by exactly one identity
- Images in Artifact Registry, tagged by commit SHA, pruned after 30 releases
- Keyless deploys from `develop` only, and keyless previews from pull requests
- A PWA runtime identity with no permissions at all, and an api runtime
  identity with exactly two
- Stack secrets encrypted with a KMS key, never a passphrase

Next: [02 — Routine change](02-routine-change.md), and read
[04 — Rollback](04-rollback.md) and [06 — Database](06-database.md) before you
need them.
