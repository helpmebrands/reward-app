# Infra

The platform: how the repository is verified and deployed, the Pulumi program and the tests that pin its configuration and the repository's shape.

- [[deployment]] — CI/CD, the Pulumi-owns-shape / CI-owns-image rule, the container, cache and security headers, infrastructure including the database, its secret and the KMS-guarded state.
- [[infra-tests]] — Pulumi config, runbooks, workflows, the monorepo layout and this graph's shape.

## Runbooks

The operating procedures live outside this graph, in `docs/runbooks/`, because they are prose for a person under pressure rather than a spec; this graph says what is true and the runbooks say what to type. Pinned by [[infra-tests#Infrastructure config#README records both services and the database]].

- `docs/runbooks/README.md` — the index, the staging environment table (both services, the job, the database, the secret, the key) and the ownership rule.
- `01-initial-deployment.md` — an empty project to two live URLs, including the KMS key bootstrap the stack cannot do for itself ([[infra-tests#Infrastructure config#Runbook 01 bootstraps the KMS secrets provider]]).
- `02-routine-change.md` — the loop per workspace, which merge triggers which deploy, and the additive-migration rule.
- `03-infrastructure-change.md` — `pulumi up --refresh`, the CI-owned fields, the deployer's roles, costs including Cloud SQL, a production stack on its own key.
- `04-rollback.md` — traffic shifts for either service and why the schema never rolls back with them.
- `05-troubleshooting.md` — including the reserved `/healthz` path, the gen1 socket stall, secret bindings and preview permissions.
- `06-database.md` — migrations by job, backups, restore, the proxy, all rehearsed on staging on 2026-09-18 ([[infra-tests#Infrastructure config#Runbooks 06 and 07 exist with their rehearsed commands]]).
- `07-mobile-release.md` — versioning, signing and the test tracks for the Flutter app, and the honest list of what is not set up.

