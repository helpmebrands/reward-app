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

## Environments

The GitHub environment `staging`, written by the Pulumi stack of the same
name, is the operational source of truth; this table is the human-readable
copy. Update it when an environment is added or moved.

| | staging |
| --- | --- |
| GCP project | `helpme-reward-staging` |
| Region | `us-central1` |
| Pulumi stack | `staging` (backend `gs://helpme-reward-staging-pulumi-state`) |
| Cloud Run services | `reward-app` (the PWA), `reward-api` (the service tier) |
| Migration job | `reward-api-migrate`, run by `cd-api.yml` before each api deploy |
| Database | Cloud SQL `reward-api-db-staging`, PostgreSQL 16, `db-f1-micro`; database `reward`, user `api` |
| Secret | `reward-api-database-url-staging` in Secret Manager: the api's whole `DATABASE_URL` |
| Secrets key | KMS `projects/helpme-reward-staging/locations/us-central1/keyRings/pulumi/cryptoKeys/staging`, the stack's secrets provider |
| URLs | PWA <https://staging.helpmereward.com> (also <https://reward-app-bduraqeztq-uc.a.run.app>); api <https://reward-api-bduraqeztq-uc.a.run.app> |
| DNS | Cloudflare zone `helpmereward.com`; CNAME `staging` → `ghs.googlehosted.com`, DNS only |
| Deployed from | `develop`: the PWA by `cd.yml`, the api by `cd-api.yml`, each on merges that touch it |
| First deployed | PWA 2026-09-17; api 2026-09-18 |
| GitHub token | fine-grained, this repository only, minted by `oravecz` on 2026-09-21, **no expiry**; held as `github:token` on the `staging` and `repo` stacks. Rotate by hand and update this row |
| iOS signing | Apple Distribution certificate `2737R9KZJP` and App Store profile `F43PSVY32N` (with Sign in with Apple and Associated Domains), team `LMFUSVPCDH`, both **expire 2027-09-21**; held only in Secret Manager as `reward-app-ios-*-staging`. Renew per [08](08-mobile-setup.md#later-renewing-the-certificate) and update this row |

## What owns what

The single most important thing to internalise, because getting it wrong causes
a silent rollback of production:

- **Pulumi owns the shape of the infrastructure** — the two services and the
  migration job, their scaling, their identities, the database, the secret,
  the registry, who may deploy, the budget alert, and the GitHub environment
  each stack deploys through. `infra/` has a stack per environment;
  `infra-repo/` has one stack, `repo`, for what is true of the repository
  regardless of environment (today the `develop` ruleset). Touch `infra-repo/`
  when a verify job is added or renamed; touch `infra/` for everything else.
- **CI owns which image is running.** A push to `develop` builds the image of
  whichever deployable it touched and points Cloud Run at that exact digest,
  for the api after running the migration job on it.

`infra/index.ts` therefore declares `ignoreChanges` on the container image, the
deploy labels and the revision name of both services. If that were removed,
the next `pulumi up` would reset the service to whichever image Pulumi last
recorded — deploying old code as a side effect of an unrelated infrastructure
change. Template changes are applied with `pulumi up --refresh` for the same
reason; [03](03-infrastructure-change.md#the-image-is-not-yours-to-manage) explains.

## The pieces

```
GitHub (develop)
  │
  ├─ CI (verify.yml): PWA lint · typecheck · test · build · a11y
  │                   Dart analyze · domain tests · Flutter tests · api tests
  │                   api tests against a Postgres container · both images built
  │                   infra typecheck · pulumi preview against staging
  │
  ├─ CD (cd.yml, apps/pwa): build image ──► Artifact Registry ──► reward-app revision ──► smoke test
  │
  └─ CD api (cd-api.yml, services/api + packages/domain):
         build image ──► Artifact Registry ──► reward-api-migrate job ──► reward-api revision ──► smoke test
                                                       │                        │
                                                       └── Cloud SQL reward-api-db ─┘
                                                          (unix socket; DATABASE_URL from Secret Manager)

       every job authenticated by Workload Identity Federation
       (short-lived OIDC token; no service-account key exists)
```

The PWA keeps its data in the browser's IndexedDB, so its deploy carries no
migration and no data risk. The api has a database: a deploy runs the
migrations first and stops if they fail, and the data at risk is device
registrations, not a household's cards. [06 — Database](06-database.md) has
the backup and restore procedure; [04 — Rollback](04-rollback.md) says why a
service rollback never rolls the schema back with it.

## Conventions used here

- `$` prefixes a command you run locally.
- Placeholders are `<angle-bracketed>`; replace them including the brackets.
- Anything labelled **Verify** is a step you should not skip — each one exists
  because the preceding step can fail silently.
