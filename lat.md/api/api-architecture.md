# Api architecture

A shelf handler behind a small entrypoint, compiled ahead of time into a single binary on a minimal image. The routes call [[domain]] for every rule; the service owns transport, storage and delivery, never product logic.

`services/api` is a member of the root pub workspace (`resolution: workspace`) and depends on `packages/domain` by path, so the app and the service share one domain implementation. `shelf` and `shelf_router` are the HTTP stack, as decided on the epic.

## Handler

`buildHandler` in `lib/api.dart` returns the api as one shelf `Handler`: a `shelf_router` router behind middleware that turns any uncaught error into a JSON 500, so a client never sees a stack trace.

It takes an optional Postgres `Session` for the storage-backed routes: a `Connection` in tests, a `Pool` in the server, and none at all when only liveness is wanted, in which case those routes answer 503 `{"error":"no database"}` rather than pretending ([[api-tests#Devices#Without a database the device routes answer 503]]).

`GET /health` is liveness for Cloud Run and the smoke tests: 200 with `{"status":"ok","version":…}` while the process serves, the version carried so a deploy can be told apart from the last one. Pinned by [[api-tests#Health]].

Not `/healthz`: Google's frontend answers exactly that path itself on `run.app` hosts with its own 404 page, and the request never reaches the container; `/health`, `/livez` and `/readyz` all pass through. The error middleware writes every caught error and stack to stderr before answering 500, because a 500 on Cloud Run with nothing in the log is undiagnosable.

## Entrypoint

`bin/server.dart` reads `PORT` (Cloud Run injects it, 8080 otherwise) and serves the handler on every IPv4 interface, because a container bound to loopback answers nobody.

With `DATABASE_URL` set it opens a driver `Pool` on that URL, so a dropped connection is replaced rather than poisoning every later request; without one it serves health only and says so on its startup line, which is what the container smoke test runs against.

## Devices

Push-device registration in `lib/devices.dart`: the first real endpoint, replacing the `VITE_PUSH_API` backend the PWA never had ([[delivery#Delivery paths]]). A device row is not yet tied to a user; that comes with sign-in.

Sending reminders is not built yet.

`POST /v1/devices` takes `{token, installationId, platform, timezone}`: the FCM token, an id the app generated for its own installation, `ios` or `android`, and an IANA zone name. `Device.parse` names the first field that is missing, blank or malformed as a 400 `{"error":"invalid","field":…}`; a body that is not a JSON object is field `body`. The zone's shape is checked in Dart and its existence by asking `pg_timezone_names`, so the api ships no zone list of its own. The row is upserted by token: a repeat registration replaces installation, platform and zone and bumps `updated_at`. The response is 200 with the stored fields.

`DELETE /v1/devices/{token}` removes the row: 204, or 404 when nothing was registered under that token, so a client can tell the two apart.

`0002_devices.sql` creates `devices (token PRIMARY KEY, installation_id, platform CHECK ios|android, timezone, registered_at, updated_at)`. A token reissued by FCM leaves the old row behind under the same installation id; reconciling those is a later concern, once something sends. Pinned by [[api-tests#Devices]].

## Migrations

The schema is a series of numbered SQL files in `services/api/migrations/`, applied once each in version order by `migrate` in `lib/migrate.dart` and recorded in `schema_migrations`. Pinned by [[api-tests#Migrations]].

A file is `NNNN_name.sql`. `listMigrations` sorts the `.sql` files by numeric version and refuses a name that does not match or a version claimed twice, because skipping either silently would leave a database that looks migrated and is not. Other files in the directory are ignored.

`migrate` creates `schema_migrations (version, name, applied_at)` if missing, reads the versions already recorded, and applies each unrecorded file in its own transaction together with its row, in simple query mode because a file holds several statements. A failure rolls the file and its row back together, so the next run retries it; a second run over the same files applies nothing. There is no down migration: a mistake is corrected by the next numbered file.

`bin/migrate.dart` is the runner: `dart run bin/migrate.dart` from `services/api` with `DATABASE_URL` set, which is a libpq-style URL the driver parses itself. It resolves `migrations/` beside its own `bin/` (or beside the compiled `/migrate` in the image), prints each version applied, and exits 2 without a URL. Running it is a deploy step, not something the server does at start, so a broken migration fails the deploy rather than every replica: on staging the Cloud Run job `reward-api-migrate` runs it before each deploy ([[deployment#Infrastructure]]).

`services/api/docker-compose.yml` starts `postgres:16` locally as `reward:reward@localhost:5432/reward`; the container speaks plain TCP, so the URL carries `sslmode=disable` where the driver would otherwise insist on TLS. The `api` CI job runs the same image as a service container ([[infra-tests#Infrastructure config#Api job tests against a Postgres service container]]).

`0001_init.sql` is the first migration and sets only a comment on the schema; `0002_devices.sql` brings the first table ([[api-architecture#Devices]]).

## Container

`services/api/Dockerfile` is two stages built from the repository root, because the workspace lockfile lives there and the api depends on `packages/domain` by path ([[deployment#Container]] does the same for the PWA).

The build stage on the Dart SDK image copies the workspace manifests, drops the Flutter app from its copy of the root manifest (a plain Dart SDK cannot resolve a Flutter package and the api never depends on it), resolves, then `dart compile exe` produces two AOT binaries: the server and the migrator. The runtime stage is `scratch` plus the Dart image's `/runtime/` (root certificates and runtime libraries), `/server`, `/migrate` and `/migrations/` beside it, because the migrator resolves its files relative to its own path ([[api-architecture#Migrations]]). There is no `HEALTHCHECK`; Cloud Run runs its own probes. The `api` job of the verify gate builds it and smoke-tests `/health` ([[infra-tests#Infrastructure config#Verify gate builds and smoke-tests the api]]); the Cloud Run migration job runs `/migrate` from it before each deploy ([[infra-tests#Infrastructure config#Api image carries the migrator and the migrations]]).
