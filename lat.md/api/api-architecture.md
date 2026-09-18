# Api architecture

A shelf handler behind a small entrypoint, compiled ahead of time into a single binary on a minimal image. The routes call [[domain]] for every rule; the service owns transport, storage and delivery, never product logic.

`services/api` is a member of the root pub workspace (`resolution: workspace`) and depends on `packages/domain` by path, so the app and the service share one domain implementation. `shelf` and `shelf_router` are the HTTP stack, as decided on the epic.

## Handler

`buildHandler` in `lib/api.dart` returns the api as one shelf `Handler`: a `shelf_router` router behind middleware that turns any uncaught error into a JSON 500, so a client never sees a stack trace. Routes are added to the router as they land.

`GET /healthz` is liveness for Cloud Run and the smoke tests: 200 with `{"status":"ok","version":…}` while the process serves, the version carried so a deploy can be told apart from the last one. Pinned by [[api-tests#Health]].

## Entrypoint

`bin/server.dart` reads `PORT` (Cloud Run injects it, 8080 otherwise) and serves the handler on every IPv4 interface, because a container bound to loopback answers nobody.

## Migrations

The schema is a series of numbered SQL files in `services/api/migrations/`, applied once each in version order by `migrate` in `lib/migrate.dart` and recorded in `schema_migrations`. Pinned by [[api-tests#Migrations]].

A file is `NNNN_name.sql`. `listMigrations` sorts the `.sql` files by numeric version and refuses a name that does not match or a version claimed twice, because skipping either silently would leave a database that looks migrated and is not. Other files in the directory are ignored.

`migrate` creates `schema_migrations (version, name, applied_at)` if missing, reads the versions already recorded, and applies each unrecorded file in its own transaction together with its row, in simple query mode because a file holds several statements. A failure rolls the file and its row back together, so the next run retries it; a second run over the same files applies nothing. There is no down migration: a mistake is corrected by the next numbered file.

`bin/migrate.dart` is the runner: `dart run bin/migrate.dart` from `services/api` with `DATABASE_URL` set, which is a libpq-style URL the driver parses itself. It resolves `migrations/` beside its own `bin/`, prints each version applied, and exits 2 without a URL. Running it is a deploy step, not something the server does at start, so a broken migration fails the deploy rather than every replica.

`services/api/docker-compose.yml` starts `postgres:16` locally as `reward:reward@localhost:5432/reward`; the container speaks plain TCP, so the URL carries `sslmode=disable` where the driver would otherwise insist on TLS. The `api` CI job runs the same image as a service container ([[infra-tests#Infrastructure config#Api job tests against a Postgres service container]]).

`0001_init.sql` is the first migration and sets only a comment on the schema: nothing product-shaped lives in the database until the device registration endpoint brings its table.

## Container

`services/api/Dockerfile` is two stages built from the repository root, because the workspace lockfile lives there and the api depends on `packages/domain` by path ([[deployment#Container]] does the same for the PWA).

The build stage on the Dart SDK image copies the workspace manifests, drops the Flutter app from its copy of the root manifest (a plain Dart SDK cannot resolve a Flutter package and the api never depends on it), resolves, then `dart compile exe` produces one AOT binary. The runtime stage is `scratch` plus the Dart image's `/runtime/` (root certificates and runtime libraries) and the binary. There is no `HEALTHCHECK`; Cloud Run runs its own probes. The `api` job of the verify gate builds it and smoke-tests `/healthz` ([[infra-tests#Infrastructure config#Verify gate builds and smoke-tests the api]]).
