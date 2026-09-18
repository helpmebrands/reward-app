# The service tier: an AOT-compiled Dart binary on a minimal runtime image.
#
# The build context is the repository root, because the pub workspace keeps
# its one lockfile there and the api depends on packages/domain by path.

# ---- build ----------------------------------------------------------------
FROM dart:3.12.2 AS build

WORKDIR /app

# The workspace manifests first, so the dependency layer is cached
# independently of the source. The Flutter app is a workspace member but a
# plain Dart SDK cannot resolve it, so it is dropped from the copy of the
# root manifest this image resolves; the api never depends on it.
COPY pubspec.yaml pubspec.lock ./
COPY packages/domain/pubspec.yaml packages/domain/
COPY services/api/pubspec.yaml services/api/
RUN sed -i '/apps\/mobile/d' pubspec.yaml && dart pub get

COPY packages/domain packages/domain
COPY services/api services/api
RUN dart pub get --offline \
  && dart compile exe services/api/bin/server.dart -o /app/server \
  && dart compile exe services/api/bin/migrate.dart -o /app/migrate

# ---- runtime --------------------------------------------------------------
# The minimal runtime image the Dart team publishes for AOT binaries: the
# root certificates and the runtime libraries, nothing else.
FROM scratch AS runtime

COPY --from=build /runtime/ /
COPY --from=build /app/server /server
# The migrator and its files, run by the Cloud Run job before each deploy
# (`/migrate` resolves `../migrations/` beside itself, hence the root).
COPY --from=build /app/migrate /migrate
COPY --from=build /app/services/api/migrations /migrations

ENV PORT=8080
EXPOSE 8080

# No HEALTHCHECK: Cloud Run runs its own startup and liveness probes.
CMD ["/server"]
