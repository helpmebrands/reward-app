# Runbooks

Operating HelpMe Reward: how it is deployed, how to change it, and what to do
when a change goes wrong.

| | |
| --- | --- |
| [01 — Initial deployment](01-initial-deployment.md) | From an empty Google Cloud project to a live URL. Done once. |
| [02 — Routine change](02-routine-change.md) | The day-to-day loop: branch, PR, merge, deploy. |
| [03 — Infrastructure change](03-infrastructure-change.md) | Changing Pulumi safely, including custom domains. |
| [04 — Rollback](04-rollback.md) | Getting off a bad revision. Read this **before** you need it. |
| [05 — Troubleshooting](05-troubleshooting.md) | Specific failures and what they actually mean. |
| [06 — Database](06-database.md) | Migrations, backups, restore, and connecting to Cloud SQL from a laptop. |
| [07 — Mobile release](07-mobile-release.md) | Versioning and releasing the Flutter app to TestFlight and the Play internal track. |
| [08 — Mobile setup](08-mobile-setup.md) | Store records, signing material, sign-in credentials and invite links, done once in order; re-making the iOS profile and renewing the certificate. |
| [09 — Cloudflare Pages](09-cloudflare-pages.md) | The static site on Cloudflare Pages per environment: tokens, ids, the domain, the first deploy, `main` for production, rollback. |

## Environments

The GitHub environment `staging`, written by the Pulumi stack of the same
name, is the operational source of truth; this table is the human-readable
copy. Update it when an environment is added or moved.

| | staging |
| --- | --- |
| GCP project | `helpme-reward-staging` |
| Region | `us-central1` |
| Pulumi stack | `staging` (backend `gs://helpme-reward-staging-pulumi-state`) |
| Cloud Run service | `reward-api` (the service tier); the PWA's `reward-app` service was removed in #174 |
| Site | Cloudflare Pages project `helpmereward-staging`, production branch `develop`, deployed by `cd.yml` ([09](09-cloudflare-pages.md)) |
| Migration job | `reward-api-migrate`, run by `cd-api.yml` before each api deploy |
| Database | Cloud SQL `reward-api-db-staging`, PostgreSQL 16, `db-f1-micro`; database `reward`, user `api` |
| Secret | `reward-api-database-url-staging` in Secret Manager: the api's whole `DATABASE_URL` |
| Secrets key | KMS `projects/helpme-reward-staging/locations/us-central1/keyRings/pulumi/cryptoKeys/staging`, the stack's secrets provider |
| URLs | site <https://staging.helpmereward.com> (also <https://helpmereward-staging.pages.dev>); api <https://reward-api-bduraqeztq-uc.a.run.app> |
| DNS | Cloudflare zone `helpmereward.com`; CNAME `staging` → `helpmereward-staging.pages.dev`, proxied, owned by Pulumi; CNAME `api.staging` → `ghs.googlehosted.com`, DNS only, by hand |
| Deployed from | `develop`: the site by `cd.yml`, the api by `cd-api.yml`, each on merges that touch it |
| First deployed | PWA 2026-09-17; api 2026-09-18 |
| GitHub token | fine-grained, this repository only, minted by `oravecz` on 2026-09-21, **no expiry**; held as `github:token` on the `staging` and `repo` stacks. Rotate by hand and update this row |
| iOS signing | Apple Distribution certificate `2737R9KZJP` and App Store profile `F43PSVY32N` (with Sign in with Apple and Associated Domains), team `LMFUSVPCDH`, both **expire 2027-09-21**; held only in Secret Manager as `reward-app-ios-*-staging`. Renew per [08](08-mobile-setup.md#later-renewing-the-certificate) and update this row |
| Android signing | Play app `HelpMe Reward` (`com.helpmebrands.reward`) on developer account `HelpMe Brands LLC`, Play App Signing on; upload keystore alias `upload` (owner `CN=HelpMe Reward Upload`, SHA-256 `CA:30:…:4C:DC`) held only in Secret Manager as `reward-app-android-*-staging`; the app signing key's SHA-256 is `androidSha256Fingerprints` on the stack. First internal-track build: version code 3 on 2026-09-24 |

## What owns what

The single most important thing to internalise, because getting it wrong causes
a silent rollback of production:

- **Pulumi owns the shape of the infrastructure** — the api service and its
  jobs, the site's Pages project, domain and record, their scaling, their identities, the database, the secret,
  the registry, who may deploy, the budget alert, and the GitHub environment
  each stack deploys through. `infra/` has a stack per environment;
  `infra-repo/` has one stack, `repo`, for what is true of the repository
  regardless of environment (today the `develop` ruleset). Touch `infra-repo/`
  when a verify job is added or renamed; touch `infra/` for everything else.
- **CI owns what is running.** A push to `develop` builds the api image and
  points Cloud Run at that exact digest after running the migration job on it,
  or uploads the site's files to its Pages project, whichever it touched.

`infra/index.ts` therefore declares `ignoreChanges` on the container image, the
deploy labels and the revision name of the api service. If that were removed,
the next `pulumi up` would reset the service to whichever image Pulumi last
recorded — deploying old code as a side effect of an unrelated infrastructure
change. Template changes are applied with `pulumi up --refresh` for the same
reason; [03](03-infrastructure-change.md#the-image-is-not-yours-to-manage) explains.

## The pieces

```
GitHub (develop)
  │
  ├─ CI (verify.yml): npm typecheck · test (Pulumi programs, repository config)
  │                   Dart analyze · domain tests · Flutter tests · api tests
  │                   api tests against a Postgres container · api image built
  │                   infra typecheck · pulumi preview against staging
  │
  ├─ CD (cd.yml, apps/site): wrangler pages deploy ──► Pages project helpmereward-staging ──► smoke test
  │
  └─ CD api (cd-api.yml, services/api + packages/domain):
         build image ──► Artifact Registry ──► reward-api-migrate job ──► reward-api revision ──► smoke test
                                                       │                        │
                                                       └── Cloud SQL reward-api-db ─┘
                                                          (unix socket; DATABASE_URL from Secret Manager)

       every job authenticated by Workload Identity Federation
       (short-lived OIDC token; no service-account key exists)
```

The site is static files, so its deploy carries no migration and no data
risk. The api has a database: a deploy runs the
migrations first and stops if they fail, and the data at risk is device
registrations, not a household's cards. [06 — Database](06-database.md) has
the backup and restore procedure; [04 — Rollback](04-rollback.md) says why a
service rollback never rolls the schema back with it.

## Conventions used here

- `$` prefixes a command you run locally.
- Placeholders are `<angle-bracketed>`; replace them including the brackets.
- Anything labelled **Verify** is a step you should not skip — each one exists
  because the preceding step can fail silently.
