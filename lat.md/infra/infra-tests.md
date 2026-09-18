# Infrastructure tests

What the repository-level suites pin: the Pulumi configuration, the runbooks that quote it, the workflows, the monorepo layout and the shape of this graph.

## Infrastructure config

`apps/pwa/tests/infra-config.test.ts` pins the committed Pulumi configuration, the runbooks that quote it and the monorepo layout ([[deployment#Infrastructure]]). Drift here is only noticed when a deploy is rejected at the auth step.

### Project is named reward-app

`infra/Pulumi.yaml` names the project `reward-app`, which is also the config namespace the program reads. The pre-rebrand name would recreate every resource once a stack exists.

### Project config declares no namespaced keys

Pulumi rejects a namespaced key such as `gcp:project` declared at project level without a value, so `infra/Pulumi.yaml` declares only the project's own unprefixed keys.

### Staging targets the decided project

`infra/Pulumi.staging.yaml` sets `gcp:project` to `helpme-reward-staging`, the project decided on epic #3, not the misspelt `helpme-rewards-staging`.

### Staging maps its custom domain

`infra/Pulumi.staging.yaml` sets `customDomain` to `staging.helpmereward.com`, so a clean checkout previews no diff against the live mapping. The apex is reserved for `prod`.

### Staging trusts this repository

`githubRepo` is `helpmebrands/reward-app`. The WIF attribute condition and the impersonation binding are built from it, so a wrong value rejects every deploy.

### No stale repository or project names

Nothing under `infra/`, `docs/` or `.github/` names `oravecz/cardvantage` or `helpme-rewards-`.

### No cardvantage in infrastructure names

Nothing under `infra/`, `docs/`, `.github/`, `apps/pwa/deploy/` or `apps/pwa/Dockerfile` names `cardvantage`. Service, image, registry and service-account ids all derive from `reward-app`.

### Runbook names the real state backend

Runbook 01 logs Pulumi into `gs://helpme-reward-staging-pulumi-state` rather than offering a choice, so nobody initialises a second, competing copy of the state.

### README records the staging environment

`docs/runbooks/README.md` names the staging project, region, state bucket, `run.app` URL and custom hostname, so a new starter does not reverse-engineer which project is which from repository variables.

### Verify gate typechecks the Pulumi program

`verify.yml` has an `infra` job that runs `npm ci --workspace infra` and `npm run typecheck --workspace infra` against the root lockfile, so a type error in `infra/index.ts` fails review instead of the next hand-run `pulumi up`.

### Root package declares the workspaces

The root `package.json` lists exactly `apps/pwa` and `infra` as npm workspaces, so one lockfile covers both and `npm test`, `lint`, `typecheck` and `build` delegate from the root ([[pwa#Source layout]]).

### The PWA lives in apps/pwa

`apps/pwa/package.json` is still `@helpmebrands/reward-app`, and its `Dockerfile` and `deploy/nginx.conf.template` moved with it, so the frozen reference app is self-contained under one path.

### Workflows build the PWA image from its Dockerfile

Both `verify.yml` and `cd.yml` pass `file: apps/pwa/Dockerfile` with the repository root as the build context, which is what lets the image `npm ci` against the workspace lockfile ([[deployment#Container]]).

### The graph is split by area

`apps/pwa/tests/lat-graph.test.ts` checks that `lat.md/` holds only its index at the top level and that `product/`, `pwa/` and `infra/` each hold at least one file, so every new section has to choose an owner.

### The index names the three areas

`lat.md/lat.md` links each subdirectory, so a reader landing on the index finds the product spec, the frozen PWA and the platform without guessing.

### The product spec names no PWA technology

No file under `lat.md/product/` mentions Solid, IndexedDB, Vite, the service worker or Web Push, because the Dart port and the Flutter app are written against it and must not inherit a browser decision by accident.
