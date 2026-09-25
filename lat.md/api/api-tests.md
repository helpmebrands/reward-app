# Api tests

What the api's `dart test` suite in `services/api/test/` guards, run by the `api` job of the verify gate ([[deployment#Pipeline]]).

## Health

`health_test.dart` drives the handler directly with shelf requests, no socket, so the route is tested as a function ([[api-architecture#Handler]]).

### GET health answers 200 with the version

`GET /health` returns 200, a JSON content type, `status` of `ok` and the `version` the package declares.

### Unknown routes answer 404

A path the router does not know returns 404 rather than falling through to anything.

## Contract

`contract_test.dart` holds `openapi.yaml` and the router to each other ([[api-architecture#Contract]]).

Its helpers are in `test/support/`: the spec loader (`yaml`, a dev dependency), a validator for the subset of JSON Schema the spec uses, and `openMigratedSchema`, which gives a suite its own migrated schema.

### The spec is OpenAPI 3.1

`openapi.yaml` parses, declares `openapi: 3.1.x`, has a title and documents at least one operation.

### Every route is documented and every operation served

Every route `buildApi().routes` lists is an operation in the spec, with `<param>` read as `{param}`, and every documented operation is served.

### An undocumented route fails the contract

Adding `GET /v1/secret/<id>` to the served routes makes `undocumentedRoutes` report `GET /v1/secret/{id}`, so a route added without its documentation fails.

### Every documented status is driven

Each operation's documented statuses, except `500`, have a case in the contract's list, so documenting a status without exercising it fails.

### The schema check catches a wrong body

The `Device` schema accepts a valid device and rejects one with platform `web` or without a token, so a passing contract means the bodies were really checked.

### Responses match the documented schemas

Every case answers its status with a body that validates against the documented schema, or no body where none is documented.

Without a database that is the 503s and `/health`; against `DATABASE_URL`, in the suite's own `contract` schema, the 200, 204, 400 and 404 answers.

## Sign-in

`auth_test.dart` covers the verifier and the certificate cache without a database; `me_integration_test.dart` drives `GET /v1/me` through the handler, and against `DATABASE_URL` in its own `sign_in` schema ([[api-architecture#Sign-in]]).

Tokens are signed with a throwaway RSA key made by `openssl` when the suite starts, published to the verifier as Google publishes Firebase's certificates, so no private key is committed.

### A Firebase ID token is verified against Google's keys

A token shaped as Firebase issues it, for this project and signed by the published key, verifies to its uid and email.

### Expired, misaddressed and forged tokens are refused

Expired, another project's audience or issuer, signed by another key under the same id, an unpublished key id, an empty subject, issued in the future, HS256, and not a token at all: each throws `InvalidToken`.

### Google's certificates are cached for their max-age

Two lookups within the max-age fetch once, one after it fetches again, and `max-age` is read out of a real `Cache-Control` value.

### Without a token the caller gets 401

No `Authorization`, a token that does not verify, and a non-bearer scheme all answer 401 `{"error":"unauthenticated"}`.

### The first call creates the user and later calls reuse it

A valid token for a new uid answers 200 with an id and the email and leaves one `users` row; the same uid again returns the same id and still one row; another uid adds a second.

### Bad tokens create nobody

An expired, a misaddressed and a forged token each answer 401 and no `users` row exists afterwards.

## Households

`households_integration_test.dart` drives the household routes as several signed-in users through `test/support/api.dart`, against `DATABASE_URL` in its own `households` schema ([[api-architecture#Households]]).

### A new user owns a new empty household

A first `GET /v1/household` answers 200 with the caller as sole owner, email included; a second call finds the same household.

### An invite joins its household once, for seven days

An owner's edit invite joins another user as editor, and the household lists both. The code used again answers 410, as does an invite whose `expires_at` has passed; an unknown code is 404; a created invite's link ends in `/invite/<code>`.

### Readers cannot write

A reader's `POST /v1/household/invites` and `DELETE /v1/household/members/{id}` answer 403, and so does an editor's invite, since members are the owner's to manage.

### Leaving a household that holds cards needs confirmation

A user whose household holds a card gets 409 `household holds cards` on accepting; with `confirmLeave: true` they join, and their old household and its card are gone.

### An owner with members cannot leave

An owner with an editor who accepts another household's invite gets 409 `owner has members`.

### A removed member loses access at once

After the owner removes an editor (204, and 404 a second time), the editor's next call finds them owner of a new household of one, and the owner's household has one member.

### An invite names a role

A role other than `read` or `edit` answers 400 `{"error":"invalid","field":"role"}`.

## Catalogue

`catalog_test.dart` holds the seed migration to its generator without a database; `catalog_integration_test.dart` checks the seed, the triggers and the read routes against `DATABASE_URL` in its own `catalog` schema ([[api-architecture#Catalogue]]).

### The seed migration is generated from catalog.dart

The committed `0006_catalog_seed.sql` equals `renderCatalogSeed(cardTemplates)`, the failure saying how to regenerate it; the render leaves out `blank` and doubles apostrophes.

### The seed is version 1 of every template

After migrating, every template but `blank` exists as published version 1 whose JSON equals the Dart template's, credits included.

### A published version cannot change

Updating or deleting a published version's credits, updating the version itself, or adding a credit to it all fail in the database; a draft's credit can still be changed.

### The catalogue serves each template's version in force

With versions from 2000, 2020 and 2999, `GET /v1/catalog` serves the 2020 one and its $20 credit; a template with only a draft is absent; the seeded templates are listed.

### One template's published versions

`GET /v1/catalog/{id}` lists versions 1 and 2, including one not yet in force, and leaves out the draft; an unknown template is 404.

## Catalogue admin

`catalog_admin_integration_test.dart` drives the admin routes as an admin and as a member against `DATABASE_URL` in its own `catalog_admin` schema ([[api-architecture#Catalogue admin]]).

### Only admins reach the admin routes

A member without an `admins` row gets 403 from creating a template, starting a draft, editing one and publishing.

### A draft is invisible until published

A draft of the Gold is version 2 with the Gold's credits; a second draft is 409. After an edit to the fee the catalogue still serves version 1; after publishing, with the publisher and source recorded, it serves version 2.

### Publishing needs a date and a source

Publishing without `sourceUrl`, without `effectiveFrom`, with a date that is not one, or with a source that is not a web address, answers 400.

### A published version needs a new draft

Editing or publishing a published version answers 409, and the next draft is version 3.

### Every publish writes one event

Two publishes of one template leave two `catalog_events` rows, the first of kind `version published` for version 2.

### Edits follow the domain's rules

A credit made rolling without months answers 400 naming `credits[0].intervalMonths`, and passes with 48; a zero value, an unknown cadence and a credit id under another template are refused.

### A new template starts as a draft

`POST /v1/admin/catalog` answers 201 with draft version 1, absent from the catalogue until published; an existing id is 409.

## Household data

`household_data_integration_test.dart` drives the card, credit and claim routes as several users against `DATABASE_URL` in its own `household_data` schema ([[api-architecture#Household data]]).

### A template card's benefits are the resolved version

A Gold added from its template is linked and unlabelled; the household snapshot serves one credit per template credit, each equal to the domain's `resolveLinkedBenefit` for today, and the card's issuer and fee are the template's.

### Duplicate products get numbered labels

A second Gold is labelled "American Express Gold (1)"; that label again, in another case, is 409 `label taken`; "Travel" is accepted.

### A retried claim is stored once

The same claim with the same `Idempotency-Key` answers 201 twice with one id and one stored claim; a different amount under that key is 409; no key is 400; the claim then deletes with 204.

### System-maintained terms cannot be edited

On a linked card, editing a credit's value, the card's fee, or adding a credit is 409 `system maintained`, while its enrolment state changes. On a household card, a credit is added and its value edited, and the fee and label change.

### Readers cannot write the household's data

A reader's add, edit and delete of a card, state change and claim are 403, while their snapshot read shows the household's card.

### Another household's ids are not found

Another user's edit or delete of the card is 404, and their snapshot is empty.

### Deleting a card takes its credits and claims

After a claim on a Gold's credit, deleting the card leaves no card, credit or claim.

## Conversion

`convert_integration_test.dart` converts a Gold with claims, enrolment and two members' mutes against `DATABASE_URL` in its own `convert` schema ([[api-architecture#Conversion]]).

### Conversion keeps totals and history

After conversion the household has one card, maintained by the user, with the old label, last four and anniversary.

Its claim history (credit name, cycle, amount) and its claimable, captured and missed totals equal the ones just before, and every claim points at the new credit.

### The converted credits are the terms at conversion

The converted card's credits equal the linked card's resolved credits apart from ids and timestamps, compared as sets because copies are listed in a new order, and none carries a template link.

### A new version leaves a converted card alone

Publishing a version 2 of the Gold with a new product name, fee and credits leaves the converted household's snapshot byte-for-byte the same.

### Every member's mutes follow the card

Both members who muted the Gold and its credit read mutes of the new card and the new credit id.

### Only a linked card converts

Adding a credit to a linked card is 409; converting the converted card is 409 `user maintained`; the old id is 404.

## Member preferences

`preferences_integration_test.dart` drives the preference and mute routes as members of one household and an outsider, against `DATABASE_URL` in its own `preferences` schema ([[api-architecture#Member preferences]]).

### A new member reads the defaults

A first `GET /v1/me/preferences` equals `defaultMemberPreferences`, nothing muted.

### Preferences are the member's own

Ann's new time, floor and switches, her card mute and her credit mute read back as hers, while Bob in the same household still reads the defaults; unmuting the card clears it.

### A reader can mute

A reader mutes a card of the household (204, and it reads back) and replaces their settings (200).

### Muting another household's card is not found

An outsider muting the household's card or credit, or an id that does not exist, gets 404.

### Preferences are validated

A time of `25:00`, a negative floor or a switch that is not a boolean answers 400 naming the field.

## Invite links

`app_links_test.dart` drives the association files and the fallback page through the handler with a test `AppLinks` ([[api-architecture#Invite links]]).

### The app claims the invite path on iOS

The apple-app-site-association answers JSON whose one detail names the app id and the component `/invite/*`.

### The app claims the invite path on Android

`assetlinks.json` answers one statement handling all URLs for the package with its certificate fingerprints.

### Without the app an invite shows its code

`/invite/ABCD2345` answers an HTML page with the code and both store links, unmangled by escaping; a code with other characters is 404.

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

With `buildHandler()` given no session, `POST /v1/devices` and `DELETE /v1/devices/{token}` answer 503 `{"error":"no database"}` while `/health` is unaffected.

### The devices migration creates the table

After the runner has applied `services/api/migrations/` to `public`, `to_regclass('public.devices')` is not null, proving `0002_devices.sql` ran through the same runner a deploy uses.

### Registering the same token twice upserts

Two `POST /v1/devices` with one token and different installation, platform and zone both answer 200 echoing what was sent, and the table holds one row carrying the second body with `updated_at` at or after `registered_at`.

### Missing or unknown timezone answers 400

A body without `timezone` answers 400 `{"error":"invalid","field":"timezone"}`; so does `Mars/Olympus_Mons`, which passes the shape check but is unknown to `pg_timezone_names`, and nothing is stored. A body that is not a JSON object answers 400 too.

### Deleting a token removes it and a second delete is 404

After a registration, `DELETE /v1/devices/{token}` answers 204 and the table is empty; the same delete again answers 404.
