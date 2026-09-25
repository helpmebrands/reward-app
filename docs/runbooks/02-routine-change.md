# 02 — Routine change

The normal loop: a code change from branch to production. Nothing here needs
Google Cloud access.

## The loop

The repository is a monorepo: `packages/domain` and `services/api` (Dart, a
pub workspace), `apps/mobile` (Flutter), `apps/site` (the static site, plain
HTML and CSS) and `infra` and `infra-repo` (the Pulumi programs, the npm
workspaces). Run the checks for the part you touched; CI runs them
all.

```sh
$ git switch develop && git pull
$ git worktree add ../reward-app-<issue> -b feat/<issue>-<slug> develop   # AGENTS.md rule 6
$ cd ../reward-app-<issue>

# ... work ...

$ npm test          # the fast signal while working — under three seconds
$ make verify       # what CI will check, about two minutes; see below

$ git push -u origin feat/<issue>-<slug>
$ gh pr create --base develop
```

The api's integration tests need a database and skip themselves without
`DATABASE_URL`; `services/api/docker-compose.yml` starts the same `postgres:16`
the CI job runs as a service container.

CI runs on the pull request: for the npm workspaces a typecheck and the
tests, including the repository config suites; for the Dart packages analysis and tests, the api's against
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

About three minutes later the site's new files are live on Pages; the api takes a little
longer because its migration job runs first. The run summary carries the
commit, the image digest, and the URL.

## What runs when

| Trigger | Runs | Deploys |
| --- | --- | --- |
| Pull request → `develop` | Verify (all of it, including `pulumi preview`) | No |
| Merge → `develop` touching `apps/site`, `infra`, the npm manifests or anything not listed below | Verify, then `cd.yml` | The site |
| Merge → `develop` touching `services/api`, `packages/domain`, `pubspec.yaml`, `pubspec.lock` or the api workflows | Verify, then `cd-api.yml` | The api |
| `gh workflow run cd.yml --ref develop` | Verify, then upload to Pages | The site |
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

HelpMe Reward's job is to notify people about money with a deadline. One class
of change deserves more care than its diff suggests:

**The reminder ladder** (`packages/domain/lib/src/ladder.dart`) decides when
someone is warned.
A change here alters behaviour for every existing user at once, and the failure
mode is silent: nobody reports a notification that did not arrive. The domain
tests cover the schedule arithmetic — if you change the rungs, change the test
spec in `lat.md/product/tests.md` and its test in the same commit and make sure
it fails first.

## Dependency updates

```sh
$ npm outdated
$ npm update            # within existing ranges
$ npm test

$ fvm dart pub outdated
$ fvm dart pub upgrade  # within existing ranges, whole workspace
```

### `make verify` and the CI jobs

The root `Makefile` runs the verify workflow's jobs locally, in CI's order, and the committed `.githooks/pre-push` hook runs it before every push once `make init` has pointed git at it (`git push --no-verify` skips it once).

| CI job | `make verify` row | Local command |
| --- | --- | --- |
| Typecheck and test | `node` | `npm run typecheck`, `npm test`: infra, infra-repo and the repository config suites in `infra/tests` |
| Infra typechecks and previews | `node` for the typechecks | the previews need cloud credentials and stay in CI |
| Dart analyze and test | `dart` | `fvm dart analyze --fatal-infos`, `fvm dart test` in `packages/domain` |
| Flutter analyze and test | `flutter` | `make check` in `apps/mobile` |
| Api analyze, test and container | `api`; the image in `verify-full` | `fvm dart test` in `services/api` against `docker compose`, or with the integration group skipped when docker is down |

Majors go in their own pull request so a revert is one click. For Dart and Flutter, AGENTS.md rule 9 applies: only
Flutter Favourite packages may be added without a human's approval, and the
minimum Flutter version is 3.35.

## Adding an environment variable

Remember which side of the build it lands on:

- **The site has none.** It is static files on Cloudflare Pages.
- **The api reads its environment at runtime.** `PORT` comes from Cloud Run
  and `DATABASE_URL` from Secret Manager, both declared on the service in
  `infra/index.ts`. A new variable is an infrastructure change
  ([03](03-infrastructure-change.md)); a new secret is a Secret Manager secret
  plus an `envs` entry with a `secretKeyRef`, and the api's runtime identity
  needs `secretAccessor` on it or the revision refuses to start.
