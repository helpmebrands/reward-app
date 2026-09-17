# 04 — Rollback

Read this before you need it. When you need it you will not want to be reading.

There is no database and no migration, so a rollback is purely "serve the
previous bytes again". Nothing about user data is at risk — it lives in each
browser's IndexedDB and is untouched by deploys.

## Fastest: shift traffic to the previous revision

Seconds, and no build. Do this first, diagnose afterwards.

```sh
$ REGION=us-central1
$ SERVICE=reward-app

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
$ curl -sS -o /dev/null -w '%{http_code}\n' "$URL/"
```

Revisions are named `reward-app-sha-<commit>`, so the revision list doubles as
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
reconciles the traffic split back to a single latest revision.

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
    "$REGION-docker.pkg.dev/$PROJECT_ID/<repo>/reward-app" \
    --include-tags --limit 20

$ gcloud run deploy "$SERVICE" --region "$REGION" \
    --image "$REGION-docker.pkg.dev/$PROJECT_ID/<repo>/reward-app@sha256:<digest>"
```

## Rolling back infrastructure

Different problem, different tool — see
[03 — Infrastructure change](03-infrastructure-change.md). Do not `pulumi
destroy` to undo a bad deploy; it removes the service rather than the change.
