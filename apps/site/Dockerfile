# The web slot: plain HTML and CSS behind nginx, with no build step. The
# placeholder for the app's companion site (#174); its content is #261.
# Built with the repository root as the context, like the api image.

# The unprivileged variant runs as uid 101 and binds 8080 without root, which
# is what Cloud Run wants.
FROM nginxinc/nginx-unprivileged:1.27-alpine

# Cloud Run injects PORT. The stock entrypoint runs envsubst over
# /etc/nginx/templates; the filter keeps it to PORT so nginx's own $uri
# survives substitution.
ENV NGINX_ENVSUBST_FILTER=PORT
ENV PORT=8080

COPY apps/site/deploy/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY apps/site/deploy/security-headers.conf /etc/nginx/conf.d/security-headers.conf
COPY apps/site/public /usr/share/nginx/html

EXPOSE 8080

# No HEALTHCHECK: Cloud Run runs its own startup and liveness probes, and a
# container-level one would just duplicate them.
