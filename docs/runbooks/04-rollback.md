# 04 — Rollback

Read this before you need it. When you need it you will not want to be reading.

The site is on Cloudflare Pages and rolls back there, a pointer move to an
earlier deployment: [09](09-cloudflare-pages.md#rolling-the-site-back). It is
static files and holds no data. The rest of this runbook is the api.

For the api the same traffic shift works, with one rule underneath it: **the
schema does not roll back.** Migrations run forward only, so the previous
revision must be able to serve on the newer schema. That is why
[02](02-routine-change.md#changing-the-api-or-its-schema) says a migration
may only add. If a migration itself is the problem, see
[06](06-database.md#a-migration-went-wrong).

## Fastest: shift traffic to the previous revision

Seconds, and no build. Do this first, diagnose afterwards.

```sh
$ REGION=us-central1
$ SERVICE=reward-api

# What is running, and what ran before it
$ gcloud run revisions list --service "$SERVICE" --region "$REGION" \
    --format='table(name, active, creationTimestamp)' --limit 5

# Send everything to the known-good one
$ gcloud run services update-traffic "$SERVICE" --region "$REGION" \
    --to-revisions=<good-revision>=100
```

**Verify:**

```sh
$ URL=$(gcloud run services describe "$SERVICE" --region "$REGION" --format='value(status.url)')
$ curl -sS "$URL/health"
```

Revisions are named `<service>-sha-<commit>-<run number>`, so the revision
list doubles as a map back to the commit and the workflow run that produced
it. The run number keeps a manual redeploy of a live commit from colliding
with the revision already there.

## Then: get `develop` back to the truth

Traffic-shifting does not change the repository. Until you fix `develop`, the
next merge redeploys the broken commit.

```sh
$ git switch develop && git pull
$ git revert <bad-sha>
$ git push
```

That runs CD again and deploys the reverted build normally, which also
reconciles the traffic split back to a single latest revision. For the api,
reverting a commit that added a migration file does **not** un-apply it:
`schema_migrations` still records it and the table is still there. Leave the
file in place and revert only the code, or the next deploy's job will see a
recorded version with no file and carry on regardless while the revision
expects the table gone. Forward-fix the schema instead
([06](06-database.md#a-migration-went-wrong)).

Prefer a revert to a force-push. `develop` is shared and probably protected, and
a revert leaves the failure legible to whoever looks next.

## If the image itself is gone

Artifact Registry keeps the 30 most recent releases. To redeploy an older
digest directly:

```sh
$ gcloud artifacts docker images list \
    "$REGION-docker.pkg.dev/$PROJECT_ID/<repo>/$SERVICE" \
    --include-tags --limit 20

$ gcloud run deploy "$SERVICE" --region "$REGION" \
    --image "$REGION-docker.pkg.dev/$PROJECT_ID/<repo>/$SERVICE@sha256:<digest>"
```

The api image and the migration job are the same image; a hand deploy of an
older api digest does not touch the job, which keeps the image of the last
`cd-api.yml` run. That is fine: the schema is already at that run's version.

## Rolling back infrastructure

Different problem, different tool — see
[03 — Infrastructure change](03-infrastructure-change.md). Do not `pulumi
destroy` to undo a bad deploy; it removes the service rather than the change.
