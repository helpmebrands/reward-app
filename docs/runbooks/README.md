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

## What owns what

The single most important thing to internalise, because getting it wrong causes
a silent rollback of production:

- **Pulumi owns the shape of the infrastructure** — the service, its scaling,
  its identity, the registry, who may deploy.
- **CI owns which image is running.** Every push to `develop` builds an image
  and points Cloud Run at that exact digest.

`infra/index.ts` therefore declares `ignoreChanges` on the container image. If
that were removed, the next `pulumi up` would reset the service to whichever
image Pulumi last recorded — deploying old code as a side effect of an
unrelated infrastructure change.

## The pieces

```
GitHub (develop)
  │
  ├─ CI: lint · typecheck · test · build · container smoke test
  │
  └─ CD: build image ──► Artifact Registry ──► Cloud Run revision ──► smoke test
             │                                        │
             └── authenticated by Workload Identity Federation ──┘
                 (short-lived OIDC token; no service-account key exists)
```

There is no database and no backend. HelpMe Reward keeps everything in the
browser's IndexedDB, so a deploy carries no migration and no data risk — the
worst case of a bad deploy is that the app is wrong or unavailable, never that
user data is lost. That is why the rollback runbook is short.

## Conventions used here

- `$` prefixes a command you run locally.
- Placeholders are `<angle-bracketed>`; replace them including the brackets.
- Anything labelled **Verify** is a step you should not skip — each one exists
  because the preceding step can fail silently.
