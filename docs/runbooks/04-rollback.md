# 04 — Rollback

Read this before you need it. When you need it you will not want to be reading.

For the PWA a rollback is purely "serve the previous bytes again". Nothing
about a household's data is at risk — it lives in each browser's IndexedDB and
is untouched by deploys.

For the api the same traffic shift works, with one rule underneath it: **the
schema does not roll back.** Migrations run forward only, so the previous
revision must be able to serve on the newer schema. That is why
[02](02-routine-change.md#changing-the-api-or-its-schema) says a migration
may only add. If a migration itself is the problem, see
[06](06-database.md#a-migration-went-wrong).

## Fastest: shift traffic to the previous revision

Seconds, and no build. Do this first, diagnose afterwards. The same commands
apply to both services; set `SERVICE` to `reward-app` or `reward-api`.

```sh
$ REGION=us-central1
$ SERVICE=reward-app          # or reward-api

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
$ curl -sS -o /dev/null -w '%{http_code}\n' "$URL/"          # the PWA
$ curl -sS "$URL/health"                                      # the api
```

Revisions are named `<service>-sha-<commit>`, so the revision list doubles as
a map back to the commit that produced it.

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

## What a service-worker rollback does not fix

A client that already installed the bad service worker keeps it until it next
loads the app with no other tab open. Rolling back fixes *new* loads
immediately; existing clients recover on their next visit, because `sw.js` is
served `no-store` and the worker calls `skipWaiting()`.

If a build ever shipped `sw.js` with a long cache lifetime, that recovery path
is gone and clients are stuck until the cache expires. This is the reason the
smoke test in CI and CD asserts the header on every deploy, and why it should
never be relaxed to make a deploy pass.

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
