# 05 — Troubleshooting

Specific failures, what they actually mean, and the fix. Ordered roughly by how
often they happen.

## Deploy fails: `Permission denied` on the identity provider

```
failed to generate Google Cloud federated token ... Permission 'iam.serviceAccounts.getAccessToken' denied
```

Almost always one of three things:

1. **`reward-app:githubRepo` does not match the repository.** It is compared
   exactly, including case and owner. Check:
   ```sh
   $ cd infra && pulumi config get reward-app:githubRepo
   ```
2. **`WIF_PROVIDER` is not the full resource name.** It must look like
   `projects/123456789/locations/global/workloadIdentityPools/github-dev/providers/github`,
   not a short id. Re-copy it from `pulumi stack output workloadIdentityProvider`.
3. **The workflow lacks `id-token: write`.** Without it GitHub never mints an
   OIDC token and the exchange has nothing to present.

## `pulumi up` fails: `One or more users named in the policy do not belong to a permitted customer`

The organisation enforces domain-restricted sharing, which rejects `allUsers`
(and any other external principal) in an IAM policy. The service is public
through `invokerIamDisabled` on the service itself, not through an invoker
binding, so this error means someone has reintroduced an `allUsers` member.
Remove it rather than carving a project-wide policy exception.

## Deploy fails: `denied: Permission "artifactregistry.repositories.uploadArtifacts" denied`

The deployer can authenticate but not push. Either `ARTIFACT_REPO` names a
repository that does not exist, or the region in the image tag disagrees with
the registry's. The tag must be
`<REGION>-docker.pkg.dev/<PROJECT>/<REPO>/reward-app:<sha>` — a mismatched
region produces this exact error rather than a helpful one.

## Deploy fails: `Permission denied on secret` or `secretmanager.versions.access`

Cloud Run checks, when it creates the api revision, that the runtime identity
can read every secret the template references. The api's identity holds
`secretAccessor` on exactly one secret, `reward-api-database-url-<env>`, via
`api-runtime-reads-database-url` in `infra/index.ts`; a renamed secret, a
second secret without its own binding, or a `pulumi up` that has not applied
the binding yet all produce this. Fix the binding, not the identity's roles.

## `cd-api.yml` fails at `Run the migrations`

The job's exit code is the step's, so a failing migration stops the deploy
before any replica serves the new code, which is the point. Read the job's
log before anything else:

```sh
$ gcloud run jobs executions list --job reward-api-migrate --region "$REGION" --limit 3
$ gcloud logging read 'resource.type="cloud_run_job" AND resource.labels.job_name="reward-api-migrate"' \
    --limit 20 --format='value(timestamp,textPayload)'
```

A file that failed rolled back with its `schema_migrations` row, so the next
run retries it; fix the SQL and merge. `DATABASE_URL is not set` means the
job lost its secret; a timeout with nothing logged means the socket, see the
504 entry below. [06 — Database](06-database.md#a-migration-went-wrong) has
the recovery when a migration applied and was wrong.

## Deploy succeeds, but the site shows Google's placeholder page

The service is still on the bootstrap image, which means Pulumi created it but
CD has never run successfully. Check the Actions tab; the deploy step either
failed or has not run. `gh workflow run cd.yml --ref develop` (or `cd-api.yml`)
to force one.

## `/healthz` answers 404 with a Google error page

Google's frontend answers exactly `/healthz` itself on `run.app` hosts, with
its own HTML 404, no `server` header, and no entry in the revision's request
log: the container never saw the request. The api's liveness route is
`/health` for this reason and the config tests refuse `/healthz` in either
workflow. Nothing is wrong with the service; use the right path.

## The api answers 504 on any route that touches the database

`upstream request timeout` after exactly the service's request timeout, and
nothing in the container log, while `/health` is fine: a Dart connection to
the Cloud SQL unix socket on the **first-generation** execution environment
never completes. `infra/index.ts` sets `EXECUTION_ENVIRONMENT_GEN2` on the
service and the job; check the revision:

```sh
$ gcloud run revisions describe <revision> --region "$REGION" \
    --format='value(metadata.annotations."run.googleapis.com/execution-environment")'
```

Empty or `gen1` means the setting was lost. The migration job was gen2 by
default and connected fine, which is how this was found; a revision created
by hand with `gcloud run deploy` keeps the service's setting.

## The api answers 500 `{"error":"internal"}`

The error middleware logs the exception and stack to stderr before answering,
so the revision's log has it:

```sh
$ gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="reward-api" AND severity>=ERROR' \
    --limit 10 --format='value(timestamp,textPayload)'
```

`relation "devices" does not exist` means the migrations have not run against
this database; `cd-api.yml` always runs them, so this is a hand deploy or a
restore from before the table existed ([06](06-database.md)).

## Deploy succeeds, but users still see the old version

In order of likelihood:

1. **A stale service worker.** The old worker serves the old precache until it
   is replaced. Confirm the header is intact:
   ```sh
   $ curl -sSI "$URL/sw.js" | grep -i cache-control    # must include no-store
   ```
   If it does not, that is the bug — fix `deploy/nginx.conf.template` rather
   than telling users to clear their cache. If it does, the client simply has
   not reloaded with every tab closed yet.

2. **Traffic is still split.** A rollback that was never reconciled:
   ```sh
   $ gcloud run services describe reward-app --region "$REGION" \
       --format='value(status.traffic)'
   ```

3. **You are looking at your own cached page.** Hard-reload with DevTools open
   and *Disable cache* ticked, or use a private window.

## The app loads but is completely unstyled

A Content Security Policy problem. Open the console: `Refused to apply inline
style` means `style-src` lost `'unsafe-inline'`.

This is not optional for this app. Solid's `style={{ ... }}` prop writes a
`style` **attribute**, which `style-src` governs. Removing `'unsafe-inline'`
from `deploy/security-headers.conf` leaves every inline style dropped and the
layout collapsed. `script-src` stays strict — that is the directive that
matters for injection.

## A client route 404s on refresh, but works when navigating

The SPA fallback is broken. `/credits` typed into the address bar must return
the shell. CI asserts this, so if it reaches production the container in use is
not the one CI built — check that the deploy step used the digest from the
build step rather than a floating tag.

## The service worker fails to install, with a cache error

Usually a missing asset being served as HTML. If `/assets/<hash>.js` 404s but
returns `index.html` with a `200`, the worker caches HTML under a JavaScript URL
and fails in a way that looks like cache corruption. The `try_files $uri =404`
in the `/assets/` block prevents it; CI asserts it.

## `pulumi up` fails with `SERVICE_DISABLED`

API enablement is eventually consistent. Wait a minute and run it again. If it
persists past two attempts, the project probably has no billing account
attached:

```sh
$ gcloud billing projects describe "$PROJECT_ID"
```

## `pulumi up` fails: `billingbudgets.googleapis.com API requires a quota project`

The budget resource is created against the billing account, and the API
insists on a project to bill the request to. Your ADC file may already name
one (`gcloud auth application-default set-quota-project`); the GCP provider
still does not send it. Run the apply with the override:

```sh
$ USER_PROJECT_OVERRIDE=true GOOGLE_BILLING_PROJECT="$PROJECT_ID" pulumi up
```

Seen on 2026-09-20 on the first apply of the budget. Previews and the verify
gate never hit this because they do not call the budget API.

## `pulumi preview` wants to replace the Cloud Run service

Stop and read the diff. Changing the service's `name` or `location` forces a
replacement, which means downtime and — for `location` — a new URL. Almost
always there is a way to express what you want without it.

## `pulumi preview` wants to update the container image

In the update section: the `ignoreChanges` guard has been removed or broken.
Do not apply: it will deploy whatever image Pulumi last recorded, which is old
code. In the refresh section of `pulumi preview --refresh`: expected, that is
the refresh recording the live digest. See
[03 — Infrastructure change](03-infrastructure-change.md#the-image-is-not-yours-to-manage).

## `pulumi preview` wants to change `managed-by` labels or `template.revision`

The deploy action stamps `managed-by=github-actions`, `commit-sha` and the
revision name on every deploy; those fields are in `ciOwnedServiceFields` so
Pulumi leaves them alone. If a preview proposes changing them, the list has
lost an entry; applying would roll a pointless new revision of the service.

## `pulumi` prompts for a passphrase

`Pulumi.<stack>.yaml` has lost its `secretsprovider` line, or you are on a
machine without KMS access. The staging stack's secrets are encrypted with
`projects/helpme-reward-staging/locations/us-central1/keyRings/pulumi/cryptoKeys/staging`;
there is no passphrase and never should be. Restore the two lines from git
and check `gcloud auth application-default print-access-token` works.

## The `infra` job fails with `403` reading the state bucket or the KMS key

The pull-request preview runs as the deployer, which needs `storage.objectUser`
on the state bucket, `cloudkms.cryptoKeyDecrypter` on the key and `viewer` on
the project (`deployer-can-lock-state`, `deployer-can-decrypt-secrets`,
`deployer-can-read-project` in `infra/index.ts`). A new environment gets them
on its first `pulumi up`, so its first pull request can only preview after
that. A `reauth related error` locally, by contrast, is your own expired
credentials: `gcloud auth login` and `gcloud auth application-default login`.

## Cold starts feel slow

First request to an idle service pays container start — about a second for
nginx, less for the api's AOT binary, plus the api's first database connection
on the first request that needs one. `pulumi config set reward-app:minInstances 1`
removes it for roughly $10/month per service. For a PWA that users install and
open from the Home Screen this matters less than it looks: after the first
visit, the service worker serves the shell locally and the network is not on
the critical path at all.

## Notifications stopped arriving

Check in this order, because the cheapest checks are also the likeliest:

1. Is the **service worker** the current one? DevTools → Application → Service
   Workers. A worker stuck in *waiting* is serving an old schedule.
2. Is the browser still **permitted**? Permission can be revoked at the OS
   level without the site knowing.
3. On **iOS**, is the app still installed to the Home Screen? Notifications
   only work for installed PWAs there, and removing the icon removes them.
4. Is the schedule actually populated? Settings shows the count and the next
   fire time. Zero means the ladder computed nothing — likely every credit is
   muted, captured, or beyond the horizon.

Reminder delivery is client-side. A deploy cannot break it for a user who never
reopens the app, and equally cannot fix it for them.
