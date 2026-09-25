# Api architecture

A shelf handler behind a small entrypoint, compiled ahead of time into a single binary on a minimal image. The routes call [[domain]] for every rule; the service owns transport, storage and delivery, never product logic.

`services/api` is a member of the root pub workspace (`resolution: workspace`) and depends on `packages/domain` by path, so the app and the service share one domain implementation. `shelf` and `shelf_router` are the HTTP stack, as decided on the epic.

## Handler

`buildApi` in `lib/api.dart` returns the api's shelf `Handler` and the routes it serves; `buildHandler` is that handler: a `shelf_router` router behind middleware that turns any uncaught error into a JSON 500, so a client never sees a stack trace.

It takes an optional Postgres `Session` for the storage-backed routes: a `Connection` in tests, a `Pool` in the server, and none at all when only liveness is wanted, in which case those routes answer 503 `{"error":"no database"}` rather than pretending; without a token verifier the signed-in ones answer 503 `no auth` first ([[api-tests#Devices#Without sign-in the device routes answer 503]]).

`GET /health` is liveness for Cloud Run and the smoke tests: 200 with `{"status":"ok","version":…}` while the process serves, the version carried so a deploy can be told apart from the last one. Pinned by [[api-tests#Health]].

Not `/healthz`: Google's frontend answers exactly that path itself on `run.app` hosts with its own 404 page, and the request never reaches the container; `/health`, `/livez` and `/readyz` all pass through. The error middleware writes every caught error and stack to stderr before answering 500, because a 500 on Cloud Run with nothing in the log is undiagnosable.

## Contract

`services/api/openapi.yaml` is the api's contract: OpenAPI 3.1, hand-written and spec-first, documenting every route, parameter, body and status. Nothing is generated from it; the Dart models stay hand-written on the domain's `json.dart` spelling.

Routes are added through `RouteTable` (`lib/src/routes.dart`), a `shelf_router` `Router` that also records each method and path, because the router keeps its routes private. `test/contract_test.dart` holds that list to the spec in both directions and drives every documented status of every operation through the handler, validating each body against its schema; only `500` is documented without a case. Pinned by [[api-tests#Contract]].

Hand-written cases run in order as named users, and a case can keep an id or code from its body for later ones. The 401 and 503 of every signed-in operation are generated from the spec, since neither reaches the route.

The spec is linted as OpenAPI by a pinned `npx @redocly/cli` in the `api` CI job and `make api` ([[infra-tests#Infrastructure config#The api spec is linted as OpenAPI in CI and locally]]). Every later route lands in the spec in the same pull request as its code. Operations that need no sign-in say `security: []`.

The contract test found that the device routes answered 503 with one shared `Response`, whose body shelf lets be read once; the second request without a database would have failed. `_noDatabase()` now builds a fresh response.

## Sign-in

Every data route acts for a signed-in person: a Firebase ID token from Identity Platform, Google or Apple, sent as `Authorization: Bearer <token>` and verified by the api itself (`lib/auth.dart`). Pinned by [[api-tests#Sign-in]].

`FirebaseTokenVerifier` checks the token the way Firebase documents it: RS256 and nothing else, whatever the header says; a key id Google currently publishes; the signature against that key's certificate; issuer `https://securetoken.google.com/<project>` and audience the project; not expired; `iat` and `auth_time` not in the future beyond five minutes of skew; a non-empty `sub`. `dart_jsonwebtoken` does the signature and the standard claims, approved under rule 9 for this.

`GoogleCertificates` fetches Google's certificates with `dart:io` and keeps them for the `max-age` Google sends, so a request waits on Google only when the keys rotate. The verifier sits behind `TokenVerifier`, and tests sign their own tokens with an `openssl` key made at run time.

`SignedIn` wraps a protected route: no verifier configured is 503 `no auth`, a missing or unverifiable token 401 `unauthenticated`, no database 503 `no database`. Otherwise `callerFor` finds or creates the caller's `users` row (`0003_users.sql`: `id` uuid, `firebase_uid` unique, `email`, `created_at`) and the handler runs with that `Caller`; path parameters come from `request.params`.

`GET /v1/me` returns the caller as `{id, email}`. The server builds the verifier from `FIREBASE_PROJECT_ID`, which Pulumi sets on the api service ([[infra-tests#Infrastructure config#The api knows its Firebase project]]).

## Households

The household owns the data; each person has their own login and is in exactly one household at a time (`lib/households.dart`, `0004_households.sql`). Pinned by [[api-tests#Households]].

`households`, `memberships (household_id, user_id UNIQUE, role owner|editor|reader, joined_at)` and `invites (code, household_id, role, created_by, expires_at, used_by, used_at)`. The migration also creates `cards (id, household_id)`, because leaving a household that holds cards needs confirmation; the cards api adds the rest of its columns (#216).

`callerFor` runs in one transaction: the user upsert locks the user's row, then a caller without a membership gets a new household with themselves as owner, so a new user always has one and two first calls cannot make two. The `Caller` carries the household id and its `Role`; `Role.canWrite` is false for readers, and every later data route authorises through it.

- `GET /v1/household`: the household id, the caller's role, and every member with email, role and join time.
- `POST /v1/household/invites {role: read|edit}`: owner only (403 otherwise). An eight-character code from an alphabet without 0, O, 1, I, L or U, single-use, expiring after seven days, plus a link: the code appended to `INVITE_LINK_BASE` (default `https://helpmereward.com/invite/`, set per environment with the invite links, #221).
- `POST /v1/invites/{code}/accept {confirmLeave?}`: 404 for an unknown code, 410 once used or expired, 409 `already a member`, `owner has members` while an owner has others, or `household holds cards` without `confirmLeave: true`. Otherwise one transaction moves the caller, deletes their old household if they were its last member (its cards cascade), and marks the invite used.
- `DELETE /v1/household/members/{userId}`: owner only; 409 for the owner themselves, 404 for someone not in the household. The member loses access at once and, on their next call, starts again in a new empty household; they take nothing with them.

`inTransaction` (`lib/src/database.dart`) runs a body on the handler's `Connection` or `Pool`, or inside a transaction already open.

## Catalogue

The card catalogue lives in Postgres as versions of whole templates, so terms change without a deploy ([[domain#Catalogue versions]], `lib/catalog.dart`). Pinned by [[api-tests#Catalogue]].

`0005_catalog.sql` makes `card_templates (id)`, `template_versions (template_id, version, effective_from, status draft|published, issuer, product, network, kind, annual_fee_cents, published_by, published_at, source_url, notes)` and `template_credits` (one row per credit, keyed by the stable credit id, in the domain's spellings). A published version must carry who published it and when.

Triggers make a published version immutable in the database itself: its row cannot be updated or deleted, and its credits cannot be added, changed or removed, so no route or hand-typed SQL can rewrite terms a household's cycles already resolved against.

`0006_catalog_seed.sql` is version 1 of every `catalog.dart` template but `blank`, effective from 2000-01-01 so every cycle a card has had resolves: inserted as drafts, given their credits, then published by `seed` with the file's URL as source. It is generated by `tool/catalog_seed.dart` from `renderCatalogSeed`, and a test holds the committed file to it.

`loadVersions` reads versions back into the domain's `TemplateVersion`s through its JSON codec. `GET /v1/catalog` answers each template's `versionInForce` on the database's `current_date`; `GET /v1/catalog/{templateId}` answers every published version, oldest first, or 404. Both need sign-in; drafts never appear.

## Catalogue admin

Term changes are entered by a person or an agent through the api, and only an explicit publish makes them live (`lib/catalog_admin.dart`, `0007_catalog_admin.sql`). Pinned by [[api-tests#Catalogue admin]].

An admin is a row in `admins (user_id)`, added by hand as runbook 06 shows; every admin route answers 403 to anyone else. There is no route that grants it.

- `POST /v1/admin/catalog` creates a template as draft version 1, 409 if the id exists.
- `POST /v1/admin/catalog/{templateId}/drafts` copies the latest version into draft n + 1; one open draft per template (409), 404 for an unknown template.
- `PUT …/drafts/{version}` replaces the draft's fields and credits; 409 once published, so a change needs a new draft.
- `POST …/drafts/{version}/publish {effectiveFrom, sourceUrl, notes?}` needs a calendar date and an http(s) source (400 otherwise). It records `published_by` (the caller's user id) and `published_at`, and writes one `catalog_events` row of kind `version published`, which the change notices consume ([[api-architecture#Change notices]]).

`parseVersion` checks a body with the domain's own rules: `intervalMonthsError` for a rolling credit, `endsOnError`, `anniversaryError` for dates, `enrollmentUrlError` for the source, the enums in the domain's spellings, positive values, and credit ids of the form `<template id>/<slug>`, unique within the version. The first field at fault answers 400 `{"error":"invalid","field":…}`, `credits[0].intervalMonths` for instance. Every answer is the version with its status and provenance.

## Household data

A household's cards, credits and claims live in the service tier and reach the app as the domain's `AppData` (`lib/household_data.dart`, `0008_household_data.sql`). Pinned by [[api-tests#Household data]].

A card linked to a template stores only the household's own fields (label, kind, last four, anniversary, archived); a card the household maintains also stores issuer, product, network and fee, which a check constraint requires when there is no template. Each credit is the same split: household state (enrolment, spend met, last call only, active) on every row, terms only on a household credit. `UNIQUE (card_id, template_credit_id)` keeps one row per linked credit.

`loadHousehold` builds the snapshot for the database's today. It first makes sure every linked card has a row for every credit any version in force has had, so a credit added in a new version has an id and state the day it appears. A linked card takes issuer, product, network and fee from its template's version in force; each linked credit is `resolveLinkedBenefit`, with its own claims for a rolling one, and a credit no version in force has is left out.

- `GET /v1/household/data` serves the snapshot; readers may read. Beside the snapshot it carries `termsChanged`, the caller's own marks ([[api-architecture#Change notices]]), which the app's snapshot parser ignores.
- `POST /v1/cards {templateId | issuer, product, network, annualFeeCents; anniversaryOn, label?, kind?, last4?}` returns the card and its credits. Without a label a duplicate product gets `defaultLabel`; a label `labelError` refuses is 409 `label taken`.
- `PATCH /v1/cards/{id}` changes household fields on any card and terms only on a household card; `DELETE` cascades to credits and claims.
- `POST /v1/cards/{id}/benefits`, `PUT /v1/benefits/{id}` and `DELETE /v1/benefits/{id}` work on household credits; on a linked card or credit each is 409 `system maintained`, since conversion is the only way to change catalogue terms. Terms are checked by `parseCreditTerms`, the catalogue admin's parser.
- `PUT /v1/benefits/{id}/state` patches household state on any credit.
- `POST /v1/claims` needs an `Idempotency-Key`. The canonical request is stored beside the claim under `UNIQUE (household_id, idempotency_key)`: a retry with the same body answers the stored claim, a different body is 409 `idempotency key reused`. `DELETE /v1/claims/{id}` removes one.

Every write needs an editor or owner (403 for a reader), and an id from another household is 404, never a hint that it exists.

## Conversion

A household that wants to change a linked card's terms, or add a credit to it, converts it into a card it maintains itself; after that the catalogue no longer reaches it (`POST /v1/cards/{cardId}/convert` in `lib/household_data.dart`). Pinned by [[api-tests#Conversion]].

One transaction, for an editor or owner. A new card copies the linked card's household fields, its creation time and the issuer, product, network and fee in force today. Each credit the snapshot resolves becomes a household credit with today's terms and all its household state, under a new id.

The claims and every member's mutes of the card and its credits move to the new ids, and the linked card is deleted, taking any linked row that never resolved. The answer is the new card and credits, the id it replaces and a map from each old credit id to its new one, so a client can follow along. A card the household already maintains is 409 `user maintained`.

## Member preferences

Notification settings and mutes belong to each member, not the household ([[domain#Member preferences]]), and the server keeps them so it can schedule that member's reminders (`lib/preferences.dart`, `0009_member_preferences.sql`). Pinned by [[api-tests#Member preferences]].

`member_preferences` holds one row per member who has changed anything; without one, `GET /v1/me/preferences` answers `defaultMemberPreferences`. `member_mutes` names a card or a credit, never both, and goes with the row it names. The read returns only mutes on the caller's current household, so a member who moved households does not carry old ids.

`PUT /v1/me/preferences` replaces the five settings, checked as a 24-hour `HH:MM`, a floor of zero or more and three switches (400 naming the field). `PUT`/`DELETE /v1/me/mutes/cards/{cardId}` and `/v1/me/mutes/benefits/{benefitId}` are idempotent (204) and 404 for anything outside the caller's household. Readers may do all of it, because nothing shared changes.

## Invite links

An invite's link, `https://api.staging.helpmereward.com/invite/<code>` on staging, opens the app's join screen when the app is installed and a page with the code otherwise (`lib/app_links.dart`). Pinned by [[api-tests#Invite links]].

iOS and Android only hand a link to an app when the link's domain says so, so the api serves both association files from its own domain, mapped in Pulumi as `apiCustomDomain` ([[infra-tests#Infrastructure config#Invite links have the api's own domain]]):

- `/.well-known/apple-app-site-association` claims `/invite/*` for `LMFUSVPCDH.com.helpmebrands.reward`.
- `/.well-known/assetlinks.json` names `com.helpmebrands.reward` and the signing certificates in `ANDROID_SHA256_FINGERPRINTS`, empty until the Play signing key exists (#115).
- `GET /invite/{code}` is a small HTML page with the code and links to both stores, for a browser without the app; a code outside `[A-Z0-9]{4,16}` is 404.

None needs sign-in. `INVITE_LINK_BASE` on the service is `https://<apiCustomDomain>/invite/`, so the links `POST /v1/household/invites` answers point at the same domain.

## Entrypoint

`bin/server.dart` reads `PORT` (Cloud Run injects it, 8080 otherwise) and serves the handler on every IPv4 interface, because a container bound to loopback answers nobody.

With `DATABASE_URL` set it opens a driver `Pool` on that URL, so a dropped connection is replaced rather than poisoning every later request; without one it serves health only and says so on its startup line, which is what the container smoke test runs against. Without `FIREBASE_PROJECT_ID` it says "no sign-in" and the signed-in routes answer 503; with it, the same project is where FCM sends the test notification ([[api-architecture#Reminder sender]]).

## Devices

Push-device registration in `lib/devices.dart`. A device belongs to the member who registered it, so a reminder reaches all of their devices and nobody else's. Pinned by [[api-tests#Devices]].

Both routes are signed in. `POST /v1/devices` takes `{token, installationId, platform, timezone}`: the FCM token, an id the app generated for its own installation, `ios` or `android`, and an IANA zone name. `Device.parse` names the first field that is missing, blank or malformed as a 400 `{"error":"invalid","field":…}`; a body that is not a JSON object is field `body`. The zone's shape is checked in Dart and its existence by asking `pg_timezone_names`, so the api ships no zone list of its own. The row is upserted by token: a repeat registration replaces the member, installation, platform and zone and bumps `updated_at`, because whoever registers a token last is the one signed in on it. The response is 200 with the stored fields.

`DELETE /v1/devices/{token}` removes one of the caller's devices, as the app does on sign-out: 204, or 404 when the caller has nothing under that token, which is also what another member's token answers.

`0002_devices.sql` created `devices (token PRIMARY KEY, installation_id, platform CHECK ios|android, timezone, registered_at, updated_at)`; `0010_reminder_sends.sql` adds `user_id`, deleting the rows from before sign-in that belonged to nobody.

## Reminder sender

The server decides and sends reminders, so they arrive even when the app has not been opened for months (`lib/reminder_sender.dart`, `lib/push.dart`, `bin/remind.dart`). Pinned by [[api-tests#Reminder sender]].

Cloud Scheduler starts the Cloud Run job `reward-api-remind` every 15 minutes ([[deployment#Infrastructure]]). `sendDueReminders` takes every member with reminders on and at least one device, and for each:

1. Builds their schedule with the domain's `buildSchedule` ([[reminders#Schedule construction]]) from their household's data, their preferences and mutes ([[api-architecture#Member preferences]]), starting 36 hours ago.
2. Keeps the reminders whose real instant falls in the last 36 hours, the same grace the domain's `dueReminders` gives a device. Anything later is dropped rather than resurfaced.
3. Claims each in `reminder_sends (user_id, reminder_id)` before sending, so a retried or overlapping run skips it; the id is the schedule's own (`2026-10-31|urgent`), stable across recomputes.
4. Sends it to every one of the member's devices. If no device took it and none was retired, the claim is dropped so the next run retries.

A member's zone is their most recently registered device's, UTC before they have one. The domain schedules in the process's local time, which on Cloud Run is UTC and nobody's, so `scheduleIn` builds the schedule from the member's wall clock and turns each reminder's wall-clock time back into an instant with Postgres's tz database (`AT TIME ZONE`), which knows every zone's daylight saving rules. Two members of one household in different zones each hear at their own `timeOfDay`.

`PushSender` is the seam: `FcmSender` posts to FCM HTTP v1 (`projects/<FIREBASE_PROJECT_ID>/messages:send`), which also reaches APNs, authorised by an OAuth token from the metadata server as the api identity, so no key file exists. The request carries the reminder's title and body, `data` with `reminderId` and `url`, and the reminder's tag as the Android notification tag and the APNs collapse id, so a newer notice for the same day replaces the older one. Only an `UNREGISTERED` error code retires a token, deleting its device row; any other failure keeps the device. Tests use a fake that records.

The same job then sends the catalogue's change notices ([[api-architecture#Change notices]]); `sendOnce` is the claim-send-release step both use.

Two signed-in routes serve the app's Settings screen. `GET /v1/me/reminders/summary` is `{count, next}`: how many reminders the caller's schedule holds from now over the horizon, and the next one's instant, title and body, or null. `POST /v1/me/reminders/test` sends a test notification to each of the caller's devices and answers `{sent}`; without an FCM project it is 503 `no push`.

## Change notices

When a catalogue version is published, the holders of linked cards on that template hear about it (`lib/change_notices.dart`, `0011_change_notices.sql`). Pinned by [[api-tests#Change notices]].

Each run of the reminder job takes every `catalog_events` row not yet `noticed_at`, compares the published version with the one before it and words each change with `termChanges`: `Uber Cash credit changes to $20`, `annual fee changes to $350`, `Uber Cash credit ends`, `new $50 Lounge credit starts`, or `terms change` for anything else. Then, for every member of every household with a linked card on the template:

1. It upserts a `terms_changed (card_id, user_id, version)` mark, one per member so seeing it clears it for that member only.
2. If the member has reminders on and has not muted the card, it sends one push through `sendOnce` under the id `terms|<card>|<version>`: "Your Gold's Uber Cash credit changes to $20 on Jan 1, 2027, and 1 other change.", tagged `terms-<card>` so a later notice replaces it, with `url` `/cards/<card>`.

The event is then marked noticed, so a second run sends nothing. A card the household maintains has no template, so a converted card gets neither; converting or deleting a card takes its marks. `0011` marks every earlier event noticed, so the seed is never announced.

`GET /v1/household/data` carries `termsChanged`: the caller's marks on their household's cards, each `{cardId, version, effectiveFrom, changes}`. `POST /v1/cards/{cardId}/terms-seen` deletes the caller's mark (204, with or without one; 404 outside their household). Readers may, since nothing shared changes.

## Migrations

The schema is a series of numbered SQL files in `services/api/migrations/`, applied once each in version order by `migrate` in `lib/migrate.dart` and recorded in `schema_migrations`. Pinned by [[api-tests#Migrations]].

A file is `NNNN_name.sql`. `listMigrations` sorts the `.sql` files by numeric version and refuses a name that does not match or a version claimed twice, because skipping either silently would leave a database that looks migrated and is not. Other files in the directory are ignored.

`migrate` creates `schema_migrations (version, name, applied_at)` if missing, reads the versions already recorded, and applies each unrecorded file in its own transaction together with its row, in simple query mode because a file holds several statements. A failure rolls the file and its row back together, so the next run retries it; a second run over the same files applies nothing. There is no down migration: a mistake is corrected by the next numbered file.

`bin/migrate.dart` is the runner: `dart run bin/migrate.dart` from `services/api` with `DATABASE_URL` set, which is a libpq-style URL the driver parses itself. It resolves `migrations/` beside its own `bin/` (or beside the compiled `/migrate` in the image), prints each version applied, and exits 2 without a URL. Running it is a deploy step, not something the server does at start, so a broken migration fails the deploy rather than every replica: on staging the Cloud Run job `reward-api-migrate` runs it before each deploy ([[deployment#Infrastructure]]).

`services/api/docker-compose.yml` starts `postgres:16` locally as `reward:reward@localhost:5432/reward`; the container speaks plain TCP, so the URL carries `sslmode=disable` where the driver would otherwise insist on TLS. The `api` CI job runs the same image as a service container ([[infra-tests#Infrastructure config#Api job tests against a Postgres service container]]).

`0001_init.sql` is the first migration and sets only a comment on the schema; `0002_devices.sql` brings the first table ([[api-architecture#Devices]]).

## Container

`services/api/Dockerfile` is two stages built from the repository root, because the workspace lockfile lives there and the api depends on `packages/domain` by path as the retired PWA's image did.

The build stage on the Dart SDK image copies the workspace manifests, drops the Flutter app from its copy of the root manifest (a plain Dart SDK cannot resolve a Flutter package and the api never depends on it), resolves, then `dart compile exe` produces three AOT binaries: the server, the migrator and the reminder sender. The runtime stage is `scratch` plus the Dart image's `/runtime/` (root certificates and runtime libraries), `/server`, `/migrate` and `/migrations/` beside it, because the migrator resolves its files relative to its own path ([[api-architecture#Migrations]]). There is no `HEALTHCHECK`; Cloud Run runs its own probes. The `api` job of the verify gate builds it and smoke-tests `/health` ([[infra-tests#Infrastructure config#Verify gate builds and smoke-tests the api]]); the Cloud Run migration job runs `/migrate` from it before each deploy ([[infra-tests#Infrastructure config#Api image carries the migrator and the migrations]]). A third binary, `/remind`, is the reminder sender the scheduled job runs ([[infra-tests#Infrastructure config#Api image carries the reminder sender]]).
