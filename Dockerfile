# HelpMe Reward is a static PWA, so the image is a build stage plus a web server.
# Cloud Run was chosen over object hosting because the roadmap has a Web Push
# backend on it (see README) — this container can grow an /api route without a
# second piece of infrastructure and a second deploy path.

# ---- build ----------------------------------------------------------------
FROM node:22-alpine AS build

WORKDIR /app

# Copy manifests first so the dependency layer is cached independently of the
# source; `npm ci` then reruns only when the lockfile actually changes.
COPY package.json package-lock.json ./
RUN npm ci

COPY . .

# Vite inlines `import.meta.env.*` at BUILD time, so these have to be present
# here — setting them on the Cloud Run service later would have no effect. The
# VAPID value is a public key; nothing secret is baked into the image.
ARG VITE_VAPID_PUBLIC_KEY=""
ARG VITE_PUSH_API=""
ENV VITE_VAPID_PUBLIC_KEY=$VITE_VAPID_PUBLIC_KEY
ENV VITE_PUSH_API=$VITE_PUSH_API

# `npm run build` typechecks before bundling, so a type error fails the image
# rather than shipping.
RUN npm run build

# ---- runtime --------------------------------------------------------------
# The unprivileged variant runs as uid 101 and binds 8080 without root, which
# is what Cloud Run wants.
FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime

# Cloud Run injects PORT. The stock entrypoint runs envsubst over
# /etc/nginx/templates; the filter keeps it to PORT so nginx's own $uri,
# $host and friends survive substitution.
ENV NGINX_ENVSUBST_FILTER=PORT
ENV PORT=8080

COPY deploy/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY deploy/security-headers.conf /etc/nginx/conf.d/security-headers.conf
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 8080

# No HEALTHCHECK: Cloud Run runs its own startup and liveness probes, and a
# container-level one would just duplicate them.
