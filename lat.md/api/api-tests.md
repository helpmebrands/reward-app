# Api tests

What the api's `dart test` suite in `services/api/test/` guards, run by the `api` job of the verify gate ([[deployment#Pipeline]]).

## Health

`health_test.dart` drives the handler directly with shelf requests, no socket, so the route is tested as a function ([[api-architecture#Handler]]).

### GET healthz answers 200 with the version

`GET /healthz` returns 200, a JSON content type, `status` of `ok` and the `version` the package declares.

### Unknown routes answer 404

A path the router does not know returns 404 rather than falling through to anything.

## Migrations

`migrate_test.dart` covers the file listing with a temporary directory and no database; `migrate_integration_test.dart` needs `DATABASE_URL` and skips itself otherwise ([[api-architecture#Migrations]]).

Without a database `dart test` still passes with the integration group marked skipped; in CI the `api` job's service container provides the URL, so the group runs in review. The suite works inside its own `migrate_test` schema, created in `setUp` and dropped in `tearDown`, so it can discard `schema_migrations` freely while [[api-tests#Devices]] uses the migrated `public` schema in parallel.

### Migration files are ordered by version

Given `0010_ten.sql`, `0002_two.sql` and a `README.md`, `listMigrations` returns versions 2 then 10 with names `two` and `ten`, numerically not lexically, and ignores the non-SQL file.

### Malformed and duplicate file names are rejected

A `.sql` file without a `NNNN_` prefix, or two files claiming the same version, make `listMigrations` throw a `FormatException` rather than skip or pick one.

### Real migrations apply from DATABASE_URL and land in schema_migrations

Against a database with no `schema_migrations`, running `services/api/migrations/` applies at least one file starting at version 1, and the table records every applied version with its name and an `applied_at` timestamp.

### A second run applies nothing

Two fixture files, one holding two statements, apply on the first run and return an empty list on the second; `schema_migrations` holds exactly versions 1 and 2 and the second file's insert happened once.

### A failing migration rolls back and is not recorded

A fixture whose second statement fails makes `migrate` throw the server error; its version is absent from `schema_migrations` and the table its first statement created does not exist, proving the file ran in one transaction.

## Devices

`devices_test.dart` covers the body parser and the no-database answer without a connection; `devices_integration_test.dart` drives the routes through the handler against `DATABASE_URL` ([[api-architecture#Devices]]).

The integration suite migrates `public` once in `setUpAll` and truncates `devices` before each test.

### Registration body is validated field by field

A complete body parses to its four fields; each of `token`, `installationId`, `platform` and `timezone` missing or blank throws `InvalidField` naming it.

A platform other than `ios` or `android`, or a zone not shaped like an IANA name, is named likewise.

### Without a database the device routes answer 503

With `buildHandler()` given no session, `POST /v1/devices` and `DELETE /v1/devices/{token}` answer 503 `{"error":"no database"}` while `/healthz` is unaffected.

### The devices migration creates the table

After the runner has applied `services/api/migrations/` to `public`, `to_regclass('public.devices')` is not null, proving `0002_devices.sql` ran through the same runner a deploy uses.

### Registering the same token twice upserts

Two `POST /v1/devices` with one token and different installation, platform and zone both answer 200 echoing what was sent, and the table holds one row carrying the second body with `updated_at` at or after `registered_at`.

### Missing or unknown timezone answers 400

A body without `timezone` answers 400 `{"error":"invalid","field":"timezone"}`; so does `Mars/Olympus_Mons`, which passes the shape check but is unknown to `pg_timezone_names`, and nothing is stored. A body that is not a JSON object answers 400 too.

### Deleting a token removes it and a second delete is 404

After a registration, `DELETE /v1/devices/{token}` answers 204 and the table is empty; the same delete again answers 404.
