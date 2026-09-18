# Api architecture

A shelf handler behind a small entrypoint, compiled ahead of time into a single binary on a minimal image. The routes call [[domain]] for every rule; the service owns transport, storage and delivery, never product logic.

`services/api` is a member of the root pub workspace (`resolution: workspace`) and depends on `packages/domain` by path, so the app and the service share one domain implementation. `shelf` and `shelf_router` are the HTTP stack, as decided on the epic.

## Handler

`buildHandler` in `lib/api.dart` returns the api as one shelf `Handler`: a `shelf_router` router behind middleware that turns any uncaught error into a JSON 500, so a client never sees a stack trace. Routes are added to the router as they land.

`GET /healthz` is liveness for Cloud Run and the smoke tests: 200 with `{"status":"ok","version":…}` while the process serves, the version carried so a deploy can be told apart from the last one. Pinned by [[api-tests#Health]].

## Entrypoint

`bin/server.dart` reads `PORT` (Cloud Run injects it, 8080 otherwise) and serves the handler on every IPv4 interface, because a container bound to loopback answers nobody.

## Container

`services/api/Dockerfile` is two stages built from the repository root, because the workspace lockfile lives there and the api depends on `packages/domain` by path ([[deployment#Container]] does the same for the PWA).

The build stage on the Dart SDK image copies the workspace manifests, drops the Flutter app from its copy of the root manifest (a plain Dart SDK cannot resolve a Flutter package and the api never depends on it), resolves, then `dart compile exe` produces one AOT binary. The runtime stage is `scratch` plus the Dart image's `/runtime/` (root certificates and runtime libraries) and the binary. There is no `HEALTHCHECK`; Cloud Run runs its own probes. The `api` job of the verify gate builds it and smoke-tests `/healthz` ([[infra-tests#Infrastructure config#Verify gate builds and smoke-tests the api]]).
