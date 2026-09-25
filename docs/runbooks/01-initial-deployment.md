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
| Billing Account Costs Manager on the billing account | `gcloud billing accounts get-iam-policy <ACCOUNT_ID>` — the stack declares a budget, and budgets live on the account, not the project |
| Docker | `docker version` — the api runbooks use the `postgres:16` image for `psql` |
| Admin on the GitHub repository | Needed to mint the fine-grained token the stack uses to manage the ruleset and variables (step 3) |

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
$ pulumi config set --secret reward-app:billingAccount "$(gcloud billing projects describe "$PROJECT_ID" --format='value(billingAccountName)' | sed 's|billingAccounts/||')"
```

`billingAccount` feeds the budget alert (runbook 03, *Costs*). It is set as a
secret because the repository is public; the ciphertext that lands in the
stack file is the only form it ever takes here.

This stack also writes the GitHub environment it deploys through (step 5),
so it needs a GitHub credential on the machine that runs `pulumi up`. Mint a
**fine-grained personal access token** (Settings → Developer settings)
scoped to this one repository with *Administration: read and write*,
*Variables: read and write*, *Secrets: read and write* and *Environments:
read and write*, an expiry of a year at most, and store it as secret config
on this stack:

```sh
$ pulumi config set github:owner helpmebrands
$ pulumi config set --secret github:token   # paste when prompted; not in shell history
```

Keep the token to hand: the repository project in step 6 needs the same one
on its own stack. The verify gate does not need it: `pulumi preview` never
calls GitHub unless refreshing, and the workflow's own token covers reads.
Record the token's expiry in step 8. Staging's token was minted without an
expiry on 2026-09-21; a token like that never fails on its own, so its
rotation is a calendar entry, not an error message.

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
$ USER_PROJECT_OVERRIDE=true GOOGLE_BILLING_PROJECT="$PROJECT_ID" pulumi up
```

The two variables name the quota project for the budget API, which the GCP
provider does not take from your ADC file; without them the budget fails to
create with "requires a quota project" (runbook 05). Every `pulumi up` on an
environment stack takes this form; `pulumi preview` needs neither.

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

The stack does this too. Step 4's `pulumi up` created a GitHub
**environment** named after the stack (`staging`) and wrote onto it, as
`github.ActionsEnvironmentVariable` resources, every value the workflows
read:

| Variable | Value |
| --- | --- |
| `GCP_PROJECT_ID` | the project |
| `GCP_REGION` | the region |
| `ARTIFACT_REPO` | the image repository id |
| `CLOUD_RUN_SERVICE` | the PWA service name |
| `WIF_PROVIDER` | the workload identity provider's full name |
| `DEPLOY_SERVICE_ACCOUNT` | the deployer's email |
| `API_CLOUD_RUN_SERVICE` | the api service name |
| `API_MIGRATION_JOB` | the migration job name |

The deploy jobs in `cd.yml` and `cd-api.yml` and the preview job in
`verify.yml` run in that environment, so `vars.X` resolves per stack. None of
these are secret: they are identifiers, and the actual trust is enforced by
Google against the repository name. A variable keeps them readable in logs
when you are debugging a failed deploy. Nothing is set at repository level.

Check what landed:

```sh
$ gh variable list --env staging
```

**If a deploy has already used the environment** before the stack managed it
(GitHub creates an environment the first time a workflow names one), the
`up` in step 4 is rejected with "already exists". Import it first:

```sh
$ pulumi import github:index/repositoryEnvironment:RepositoryEnvironment \
    environment reward-app:staging
$ USER_PROJECT_OVERRIDE=true GOOGLE_BILLING_PROJECT="$PROJECT_ID" pulumi up
```

The import id is `<repository name>:<environment>`, the name without the
owner; the provider rejects `owner/name` with "does not exist".

Staging is cutting over from repository variables and a `develop`
environment to the `staging` environment (epic #96). Once one deploy of each
service has succeeded from the new variables, delete the old ones by hand so
nothing can fall back to them:

```sh
$ gh variable delete GCP_PROJECT_ID      # and the other seven
$ gh api -X DELETE repos/helpmebrands/reward-app/environments/develop
```

### If you have Web Push keys

`VITE_VAPID_PUBLIC_KEY` and `VITE_PUSH_API` are **build-time** values — Vite
inlines them into the bundle, so setting them on the Cloud Run service does
nothing. Set them as variables on the `staging` environment (they are the one
pair the stack does not write, because they are optional and product-side)
and the CD workflow passes them as build arguments:

```sh
$ gh api -X POST repos/helpmebrands/reward-app/environments/staging/variables \
    -f name=VITE_VAPID_PUBLIC_KEY -f value=<public key>
``` The VAPID *public* key is safe in a variable; the private key
belongs only to the push backend and never enters this repository.

Without them the app falls back to service-worker replay, which works.

## 6. Protect `develop`: the repository project

Everything in this step runs in the **other** Pulumi program. `infra/` has a
stack per environment; `infra-repo/` owns what is true of the repository
regardless of environment, today the `develop` ruleset, and has exactly one
stack, `repo`, on the same backend and the same KMS key. Change directory
and select the stack before anything else, or the commands below land on the
wrong project:

```sh
$ cd ../infra-repo
$ pulumi stack select repo
$ pulumi config get reward-app-repo:githubRepo   # helpmebrands/reward-app
```

The stack was created once, on 2026-09-20, and its config is committed in
`Pulumi.repo.yaml`; a new environment does not repeat this. For the record:

```sh
$ pulumi stack init repo \
    --secrets-provider "gcpkms://projects/$PROJECT_ID/locations/$REGION/keyRings/pulumi/cryptoKeys/staging"
$ pulumi config set reward-app-repo:githubRepo helpmebrands/reward-app
$ pulumi config set github:owner helpmebrands
```

Give this stack the same token as step 3; each stack keeps its own copy:

```sh
$ pulumi config set --secret github:token   # paste when prompted
```

`infra-repo/index.ts` declares a `github.RepositoryRuleset` on
`refs/heads/develop` that requires every job of `verify.yml` as a status
check, by the `verify / <job name>` context each one reports under, and
requires the branch to be up to date. The list of checks is read from the
workflow file when the program runs (`infra-repo/verify-checks.ts`), so
nothing here is typed twice.

Without it, CI is advisory: a red pull request stays mergeable and the deploy
pipeline is the first thing to notice. "Pull request required" for
integration branches is an organisation-level ruleset and is not repeated.

**Adopting a ruleset that already exists** (staging's was created by hand
as id 23613777 before the stack managed it). The import id is
`<repository name>:<ruleset id>`, the name without the owner:

```sh
$ pulumi import github:index/repositoryRuleset:RepositoryRuleset \
    develop-requires-verify reward-app:23613777
$ pulumi preview      # shows only the checks being added
$ pulumi up           # no quota-project variables: this program touches only GitHub
```

`pulumi import` records the live ruleset in the state as it is; the `up`
that follows brings it to what the program declares. Do not skip the import,
or the `up` fails with "Name must be unique" trying to create a second one.
Staging was adopted this way on 2026-09-20.

**When a verify job is renamed or added.** The pull request that changes
`verify.yml` is blocked, because the ruleset still waits for the old name or
does not yet require the new one. From that branch, run `pulumi up`; the
ruleset updates and the pull request becomes mergeable. This is the one
infrastructure change that is applied from a feature branch on purpose.

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
    -d '{"token":"t","installationId":"i","platform":"ios","timezone":"UTC"}'
{"error":"unauthenticated"}                                  # a 401: sign-in is configured
$ gcloud run jobs executions list --job reward-api-migrate --region us-central1 --limit 1
```

The device request proves the api was given its Firebase project (without it
the answer is a 503 `no auth`); the migration job's last execution succeeding
proves the database path. Do not use `/healthz` for anything
on Cloud Run; Google's edge answers that exact path itself and the container
never sees it.

Then open the PWA URL in a browser: the app should load, and DevTools →
Application → Service Workers should show one activated.

## 8. Record what you did

Add the environment to the table in [README.md](README.md#environments):
project id, region, stack, state backend, services, job, database, secret,
key and URLs. The GitHub environment the stack writes is the operational
source of truth, but a new starter should not have to reverse-engineer which
GCP project is which. Staging was recorded there on 2026-09-17 and extended
for the api on 2026-09-18.

Record the GitHub token's expiry date next to it, with who minted it. A
fine-grained token expires silently; the first sign is a `pulumi up` that
fails with `401` on a GitHub resource, and the fix is a new token pasted into
`pulumi config set --secret github:token` on both stacks.

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
- A GitHub environment named after the stack, carrying every variable the
  workflows read, written by the stack rather than copied by hand
- The `develop` ruleset requiring every verify job, owned by the `repo` stack
  of `infra-repo/`, with the check list derived from `verify.yml`
- A monthly budget alert on the project, emailed to the billing account's
  administrators

Next: [02 — Routine change](02-routine-change.md), and read
[04 — Rollback](04-rollback.md) and [06 — Database](06-database.md) before you
need them.
