# 03 — Infrastructure change

Changing anything in `infra/`. Slower and more deliberate than a code change,
because Pulumi will do exactly what you tell it.

## The loop

```sh
$ cd infra
$ pulumi stack select staging

# ... edit index.ts ...

$ npm run typecheck
$ pulumi preview --refresh  # read every line
$ pulumi up --refresh
```

The pull request's `infra` job runs the same preview against staging with the
deployer's read-only roles, so reviewers see the diff without credentials of
their own. It cannot apply anything.

**Read the preview properly.** The words that should stop you:

| Preview says | Meaning |
| --- | --- |
| `+ create` | Fine. |
| `~ update` | Usually fine — check *which* property. |
| `+- replace` | **The resource is destroyed and recreated.** For the Cloud Run service that is downtime and a new URL. |
| `- delete` | Something is going away. Be sure you meant it. |

If a replace surprises you, stop. `pulumi preview --diff` shows the property
forcing it; most replacements come from changing a name or a location, and
there is usually a way to express the change without one.

## The image is not yours to manage

`infra/index.ts` sets `ignoreChanges` (the `ciOwnedServiceFields` list) on the
container image, the deploy labels and the revision name of both Cloud Run
services and on the job's image. **Do not remove it.** CI points the service
at a new digest on every deploy; if Pulumi also owned that field, the next
`pulumi up` would reset it to whatever it last recorded — deploying old code
as a side effect of an unrelated change, with nothing in the preview that
obviously says so.

There is a second, quieter version of the same trap, which is why the loop
above says `--refresh`. Ignoring a property means Pulumi sends the value it
*last recorded as input* for it, and the value it recorded when it created the
service is the bootstrap placeholder image. Any template change applied
without a refresh would therefore ship the placeholder. `--refresh` first
reads the live service, records the real digest as the input, and only then
diffs; the preview will show the refresh lines for the image and the
`managed-by`/`commit-sha` labels the deploy action writes, followed by your
change alone.

If you see `~ update` touching `template.containers[0].image` in the update
section (not the refresh section), the guard has been lost. Do not apply.

## Changing the deploy permissions

The deployer service account can push images, deploy revisions of the two
services, run the migration job, and act as the two runtime identities. For
pull-request previews it can also read the project (`viewer`), take the state
lock (`storage.objectUser` on the state bucket) and decrypt the stack's
secrets (`cloudkms.cryptoKeyDecrypter` on the one key); none of those can
apply a change. That is the entire blast radius of a compromised workflow, so
widen it only with a reason you could defend later.

To restrict deploys to the `develop` branch specifically, narrow the
impersonation binding in `index.ts`:

```ts
member: pulumi.interpolate`principalSet://iam.googleapis.com/${pool.name}/attribute.repository_and_ref/${githubRepo}/refs/heads/develop`,
```

That also requires `attribute.repository_and_ref` in the provider's
`attributeMapping`. The trade-off is that `workflow_dispatch` from another
branch stops working, which is occasionally what you want during an incident.

## Adding a custom domain

Cloud Run will not map a domain you have not proved you own, and that proof is
a manual step. DNS for `helpmereward.com` lives in Cloudflare; the steps below
assume that. Staging is `staging.helpmereward.com`; the apex is reserved for
`prod`.

1. **Make sure Cloudflare is authoritative.** The registrar (Porkbun) must
   point the domain at the two nameservers Cloudflare assigned to the zone.
   Until `dig NS helpmereward.com +short` returns `*.ns.cloudflare.com`,
   records added in Cloudflare do nothing.

2. **Verify the domain** in [Search Console](https://search.google.com/search-console)
   as a *Domain* property, signed in as the same Google account that runs
   `pulumi up`. It gives you a TXT record; add it in Cloudflare on the apex
   (name `@`) and wait for verification to complete. Cloud Run checks the
   verifying account, not the project, so a colleague's verification does
   not count.

   ```sh
   $ gcloud domains list-user-verified      # must list helpmereward.com
   ```

3. **Configure and apply:**

   ```sh
   $ pulumi config set reward-app:customDomain staging.helpmereward.com
   $ pulumi up
   ```

4. **Add the record in Cloudflare — DNS only.** The mapping tells you what it
   needs; for a subdomain it is one CNAME:

   ```sh
   $ pulumi stack output customDomainStatus
   ```

   | Type | Name | Target | Proxy status |
   | --- | --- | --- | --- |
   | CNAME | `staging` | `ghs.googlehosted.com` | **DNS only** (grey cloud) |

   The proxy status is the part people get wrong. With the orange cloud on,
   Cloudflare answers the ACME challenge instead of Google, the managed
   certificate never issues, and the mapping sits in a certificate-pending
   state indefinitely. Turn the proxy on later if you want Cloudflare in front
   of the site, and only after the certificate exists; then set the zone's
   SSL/TLS mode to **Full (strict)**, or Cloudflare will connect to Cloud Run
   over plain HTTP and Google redirects it into a loop.

5. **Wait.** Google issues a managed certificate once DNS resolves. Fifteen
   minutes is normal, an hour is not alarming. The domain serves a certificate
   error until it completes — expected, not a fault.

   ```sh
   $ gcloud beta run domain-mappings describe --domain staging.helpmereward.com \
       --region us-central1 --format='value(status.conditions)'
   ```

   `CertificateProvisioned` flips to `True` when it is done.

**Verify:**

```sh
$ curl -sS -o /dev/null -w '%{http_code}\n' https://staging.helpmereward.com/          # 200
$ curl -sS -o /dev/null -w '%{http_code}\n' https://staging.helpmereward.com/credits   # 200
$ curl -sSI https://staging.helpmereward.com/sw.js | grep -i cache-control            # no-store
$ pulumi preview                                                                       # no changes
```

Then record the hostname in [README.md](README.md#environments). The api has
no custom domain; the Flutter app will be given its `run.app` URL, and mapping
one later is the same procedure with `apiServiceName` in place of the service.

## Adding a production environment

The stack name is the environment, so production is a second stack rather than
a second copy of the code:

Create the state bucket and the KMS key first, exactly as
[01](01-initial-deployment.md) steps 2 and 3 describe, then:

```sh
$ pulumi stack init prod \
    --secrets-provider "gcpkms://projects/<prod-project-id>/locations/us-central1/keyRings/pulumi/cryptoKeys/prod"
$ pulumi config set gcp:project <prod-project-id>
$ pulumi config set gcp:region us-central1
$ pulumi config set reward-app:githubRepo helpmebrands/reward-app
$ pulumi config set reward-app:stateBucket <prod state bucket>
$ pulumi config set reward-app:secretsKey projects/<prod-project-id>/locations/us-central1/keyRings/pulumi/cryptoKeys/prod
$ pulumi config set reward-app:minInstances 1
$ pulumi config set reward-app:dbTier db-custom-1-3840
$ pulumi up
```

Resource names already carry the stack, and `deletionProtection` turns itself
on for the services, the job and the database when the stack is called
`prod`. A separate *project* is stronger isolation than a separate stack in
the same project, and worth it for anything with real users. Turn on
point-in-time recovery for the production database before it holds anything
([06](06-database.md#backups)).

Then add `main` → production workflows alongside `cd.yml` and `cd-api.yml`,
pointed at the `prod` stack's outputs, and promote by merging `develop` into
`main`.

## Costs

Static files on Cloud Run with `minInstances: 0` and `cpuIdle: true` cost close
to nothing at low traffic — you pay per request-second, and an idle service
bills nothing. The things that actually cost money:

- **Cloud SQL.** The one thing in this stack that bills while idle: a
  `db-f1-micro` instance with 10 GB of SSD and seven retained backups is
  roughly $10/month, and it is the floor. `dbTier` raises it; the shared-core
  tiers are fine for device registrations and not for much else.
- `minInstances: 1` keeps an instance warm around the clock. It removes cold
  starts (roughly a second on first load) for roughly $10/month per service.
- Artifact Registry storage, bounded here to the 30 most recent images of
  each service.
- Secret Manager and KMS: cents. Egress, which for a ~600 KB precached app is
  negligible.

Set a budget alert on the project anyway. `maxInstances` is the technical
ceiling; a billing alert is the one that wakes someone up.

## Tearing down

```sh
$ pulumi destroy
```

Refuses on `prod` until you clear `deletionProtection`, which is the point. It
deletes the database and its backups with it: take a final backup and export
it first if anything in it matters ([06](06-database.md)). It will not delete
the Pulumi state, the GCS bucket holding it, or the KMS key ring (KMS keys
cannot be deleted, only disabled); remove those by hand if you really mean it.
