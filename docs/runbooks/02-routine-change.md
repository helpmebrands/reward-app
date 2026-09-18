# 02 — Routine change

The normal loop: a code change from branch to production. Nothing here needs
Google Cloud access.

## The loop

The repository is a monorepo: `apps/pwa` (the frozen reference PWA, an npm
workspace), `packages/domain` and `services/api` (Dart, a pub workspace) and
`apps/mobile` (Flutter). Run the checks for the part you touched; CI runs them
all.

```sh
$ git switch develop && git pull
$ git worktree add ../reward-app-<issue> -b feat/<issue>-<slug> develop   # AGENTS.md rule 6
$ cd ../reward-app-<issue>

# ... work ...

# PWA
$ npm test          # the fast signal — under three seconds
$ npm run lint
$ npm run build     # typechecks, then bundles

# domain and api
$ dart analyze --fatal-infos
$ (cd packages/domain && dart test)
$ (cd services/api && docker compose up -d --wait && \
   DATABASE_URL='postgres://reward:reward@localhost:5432/reward?sslmode=disable' dart test)

# mobile
$ (cd apps/mobile && flutter analyze --fatal-infos && flutter test)

$ git push -u origin feat/<issue>-<slug>
$ gh pr create --base develop
```

The api's integration tests need a database and skip themselves without
`DATABASE_URL`; `services/api/docker-compose.yml` starts the same `postgres:16`
the CI job runs as a service container.

CI runs on the pull request: for the PWA lint, typecheck, tests, production
build, an accessibility pass and a container build that starts the image and
checks the routes; for the Dart packages analysis and tests, the api's against
a Postgres container; for the Flutter app analysis and tests; for `infra/` a
typecheck and a `pulumi preview` against staging, so the review can read the
exact infrastructure diff. Merge when it is green and reviewed.

Merging to `develop` triggers CD, which **re-runs the whole verify suite on the
merge commit** before building. That is deliberate: your pull request was
tested against a different tree than the one that ends up on `develop`, and two
independently-green changes can still break each other.

Watch it:

```sh
$ gh run watch
```

About three minutes later the new PWA revision is live; the api takes a little
longer because its migration job runs first. The run summary carries the
commit, the image digest, and the URL.

## What runs when

| Trigger | Runs | Deploys |
| --- | --- | --- |
| Pull request → `develop` | Verify (all of it, including `pulumi preview`) | No |
| Merge → `develop` touching `apps/pwa`, `infra`, the npm manifests or anything not listed below | Verify, then `cd.yml` | The PWA |
| Merge → `develop` touching `services/api`, `packages/domain`, `pubspec.yaml`, `pubspec.lock` or the api workflows | Verify, then `cd-api.yml` | The api |
| `gh workflow run cd.yml --ref develop` | Verify, then build and deploy | The PWA |
| `gh workflow run cd-api.yml --ref develop` | Verify, then build, migrate and deploy | The api |

A merge that touches both deploys both. `cd.yml` ignores `services/api`,
`packages/domain`, `apps/mobile` and `cd-api.yml`; `cd-api.yml` lists only its
own paths; the Flutter app has no deploy workflow yet
([07](07-mobile-release.md)).

Deploys are serialised per workflow (`concurrency: deploy-develop` and
`deploy-api-develop`) and are never cancelled mid-flight — interrupting a Cloud
Run rollout can leave traffic split across revisions, and interrupting a
migration is worse.

## Changing the api or its schema

Every api deploy runs `services/api/migrations/` through the migration job
before the new revision serves. That gives a rule for what a migration may
contain: **only changes the currently running revision survives.** Add a
column, add a table, add an index. Do not drop or rename anything a revision
that is still serving, or might be rolled back to, reads or writes; do that in
a later release once nothing depends on it. [06 — Database](06-database.md) has
the mechanics and [04 — Rollback](04-rollback.md) the reason.

A new migration is a new file `NNNN_name.sql` with the next number; the test
suite refuses two files with one number, and the runner applies each file once,
in order, in its own transaction.

## Changing anything users are told

HelpMe Reward's job is to notify people about money with a deadline. Two classes
of change deserve more care than their diff suggests:

**The reminder ladder** (`packages/domain/lib/src/ladder.dart`, mirrored by the
frozen PWA's `apps/pwa/src/domain/ladder.ts`) decides when someone is warned.
A change here alters behaviour for every existing user at once, and the failure
mode is silent: nobody reports a notification that did not arrive. The domain
tests cover the schedule arithmetic — if you change the rungs, change the test
spec in `lat.md/product/tests.md` and its test in the same commit and make sure
it fails first.

**The service worker** (`apps/pwa/src/sw.ts`) is what delivers them for the
PWA. A broken worker leaves users on the previous one until they reload with
the app closed. After any change here, verify on the deployed URL rather than
trusting CI:

```sh
$ URL=<your run.app url>
$ curl -sSI "$URL/sw.js" | grep -i cache-control   # no-store, or clients pin to the old build
```

Then load the app, open DevTools → Application → Service Workers, and confirm
the new worker activates rather than sitting in *waiting*.

## Dependency updates

```sh
$ npm outdated
$ npm update            # within existing ranges
$ npm test && npm run build

$ dart pub outdated
$ dart pub upgrade      # within existing ranges, whole workspace
```

Majors go in their own pull request so a revert is one click. The PWA is frozen
as a reference and its stack is pinned deliberately — see the Solid note in
`apps/pwa/README.md`. For Dart and Flutter, AGENTS.md rule 9 applies: only
Flutter Favourite packages may be added without a human's approval, and the
minimum Flutter version is 3.35.

## Adding an environment variable

Remember which side of the build it lands on:

- **`VITE_*`** is inlined at **build** time. It must be a repository variable
  and a `build-args` entry in `cd.yml`. Setting it on the `reward-app` Cloud
  Run service has no effect whatsoever — the string is already baked into the
  JavaScript.
- **The api reads its environment at runtime.** `PORT` comes from Cloud Run
  and `DATABASE_URL` from Secret Manager, both declared on the service in
  `infra/index.ts`. A new variable is an infrastructure change
  ([03](03-infrastructure-change.md)); a new secret is a Secret Manager secret
  plus an `envs` entry with a `secretKeyRef`, and the api's runtime identity
  needs `secretAccessor` on it or the revision refuses to start.
