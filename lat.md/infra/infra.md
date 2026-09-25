# Infra

The platform: how the repository is verified and deployed, the Pulumi program and the tests that pin its configuration and the repository's shape.

- [[deployment]] — CI/CD, the Pulumi-owns-shape / CI-owns-image rule, the container, cache and security headers, infrastructure including the database, its secret and the KMS-guarded state.
- [[infra-tests]] — Pulumi config, runbooks, workflows, the monorepo layout and this graph's shape.

## Runbooks

The operating procedures live outside this graph, in `docs/runbooks/`, because they are prose for a person under pressure rather than a spec; this graph says what is true and the runbooks say what to type. Pinned by [[infra-tests#Infrastructure config#README records both services and the database]].

- `docs/runbooks/README.md` — the index, the staging environment table (both services, the job, the database, the secret, the key) and the ownership rule.
- `01-initial-deployment.md` — an empty project to the api's live URL, including the KMS key bootstrap the stack cannot do for itself ([[infra-tests#Infrastructure config#Runbook 01 bootstraps the KMS secrets provider]]).
- `02-routine-change.md` — the loop per workspace, which merge triggers which deploy, and the additive-migration rule.
- `03-infrastructure-change.md` — `pulumi up --refresh`, the CI-owned fields, the deployer's roles, costs including Cloud SQL, a production stack on its own key.
- `04-rollback.md` — traffic shifts for the api and why the schema never rolls back with them; the site rolls back in runbook 09.
- `05-troubleshooting.md` — including the reserved `/healthz` path, the gen1 socket stall, secret bindings, preview permissions and push that does not arrive.
- `06-database.md` — migrations by job, backups, restore, the proxy, all rehearsed on staging on 2026-09-18 ([[infra-tests#Infrastructure config#Runbooks 06 and 07 exist with their rehearsed commands]]).
- `07-mobile-release.md` — versioning, local builds and the tag-driven release to the test tracks; setup is left to 08 ([[infra-tests#Infrastructure config#Runbook 07 leaves setup to runbook 08]]).
- `08-mobile-setup.md` — the one-time mobile setup in the order it must be done: the Apple app id with every capability before its one profile, the signing material in Secret Manager, the Play record, the sign-in credentials as stack config, the invite-link domain, the `appleSignInConfig` PATCH the Pulumi provider cannot express, the APNs key and the reminder job ([[infra-tests#Infrastructure config#Runbook 08 turns on the reminder job]]), then re-making the profile and renewing the certificate ([[infra-tests#Infrastructure config#Runbook 08 is the one mobile setup flow]]).
- `09-cloudflare-pages.md` — the site on Cloudflare Pages per stack: Pulumi's token and the deploy token, the account and zone ids, clearing the old record, the apply, the first deploy, `main` for `helpmereward.com`, rollback and rotation ([[infra-tests#Infrastructure config#Runbook 09 sets up Cloudflare Pages]]).

## Local verify

The root `Makefile` runs the verify workflow's jobs on a laptop, in CI's order, so a push is rarely the first place a failure shows; `.githooks/pre-push` runs it once `make init` has set `core.hooksPath`.

`make verify` covers every job that needs no cloud credentials: `make node` typechecks and tests the two Pulumi projects and the repository config suites, then Dart analyze and test, the Flutter checks through `apps/mobile/Makefile`, and the api tests against docker compose. `make verify-full` adds the api container build. The Pulumi previews stay in CI ([[deployment#Pipeline]]); runbook 02 maps each job to its row. Pinned by [[infra-tests#Infrastructure config#Root Makefile runs the verify gate locally]].
