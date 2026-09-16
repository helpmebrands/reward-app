# 02 — Routine change

The normal loop: a code change from branch to production. Nothing here needs
Google Cloud access.

## The loop

```sh
$ git switch develop && git pull
$ git switch -c feature/expiring-badge

# ... work ...

$ npm test          # the fast signal — under three seconds
$ npm run lint
$ npm run build     # typechecks, then bundles

$ git push -u origin feature/expiring-badge
$ gh pr create --base develop
```

CI runs on the pull request: lint, typecheck, tests, production build, and a
container build that starts the image and checks the routes. Merge when it is
green and reviewed.

Merging to `develop` triggers CD, which **re-runs the whole verify suite on the
merge commit** before building. That is deliberate: your pull request was
tested against a different tree than the one that ends up on `develop`, and two
independently-green changes can still break each other.

Watch it:

```sh
$ gh run watch
```

About three minutes later the new revision is live. The run summary carries the
commit, the image digest, and the URL.

## What runs when

| Trigger | Runs | Deploys |
| --- | --- | --- |
| Pull request → `develop` | Verify | No |
| Merge → `develop` | Verify, then build and deploy | Yes |
| `gh workflow run cd.yml --ref develop` | Verify, then build and deploy | Yes |

Deploys are serialised (`concurrency: deploy-develop`) and are never cancelled
mid-flight — interrupting a Cloud Run rollout can leave traffic split across
revisions.

## Changing anything users are told

Cardvantage's job is to notify people about money with a deadline. Two classes
of change deserve more care than their diff suggests:

**The reminder ladder** (`src/domain/ladder.ts`) decides when someone is warned.
A change here alters behaviour for every existing user at once, and the failure
mode is silent: nobody reports a notification that did not arrive. `npm test`
covers the schedule arithmetic — if you change the rungs, change
`tests/reminders.test.ts` in the same commit and make sure it fails first.

**The service worker** (`src/sw.ts`) is what delivers them. A broken worker
leaves users on the previous one until they reload with the app closed. After
any change here, verify on the deployed URL rather than trusting CI:

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
```

Majors go in their own pull request so a revert is one click. The stack is
pinned deliberately in places — see the Solid note in `README.md` before
upgrading `solid-js`, because 2.x is a rewrite rather than a version bump.

## Adding an environment variable

Remember which side of the build it lands on:

- **`VITE_*`** is inlined at **build** time. It must be a repository variable
  and a `build-args` entry in `cd.yml`. Setting it on the Cloud Run service has
  no effect whatsoever — the string is already baked into the JavaScript.
- Anything read at **runtime** would need a server. There is not one; the
  container serves static files.

This catches people out roughly once per project, usually at the point where a
push backend is added.
