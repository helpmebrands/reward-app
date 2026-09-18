# Api

The service tier in `services/api`: a Dart HTTP service on shelf over [[domain|the shared domain]], deployed to Cloud Run beside the frozen [[pwa]]. Its first job is push-device registration, the one gap the PWA exposed.

- [[api-architecture]] — The handler, the entrypoint, the container and the workspace wiring.
- [[api-tests]] — What the api suites guard: the health route.
