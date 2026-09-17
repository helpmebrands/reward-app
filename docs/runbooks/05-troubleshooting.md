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

## Deploy succeeds, but the site shows Google's placeholder page

The service is still on the bootstrap image, which means Pulumi created it but
CD has never run successfully. Check the Actions tab; the deploy step either
failed or has not run. `gh workflow run cd.yml --ref develop` to force one.

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

## `pulumi preview` wants to replace the Cloud Run service

Stop and read the diff. Changing the service's `name` or `location` forces a
replacement, which means downtime and — for `location` — a new URL. Almost
always there is a way to express what you want without it.

## `pulumi preview` wants to update the container image

The `ignoreChanges` guard has been removed or broken. Do not apply: it will
deploy whatever image Pulumi last recorded, which is old code. See
[03 — Infrastructure change](03-infrastructure-change.md).

## Cold starts feel slow

First request to an idle service pays container start — about a second for
nginx. `pulumi config set reward-app:minInstances 1` removes it for roughly
$10/month. For a PWA that users install and open from the Home Screen this
matters less than it looks: after the first visit, the service worker serves
the shell locally and the network is not on the critical path at all.

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
