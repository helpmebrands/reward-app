# Api

The service tier in `services/api`: a Dart HTTP service on shelf over [[domain|the shared domain]], deployed to Cloud Run beside the frozen [[pwa]]. It holds the household's data and delivers reminders; push-device registration is the first endpoint built.

- [[api-architecture]] — The handler, the entrypoint, the device routes, the migrations, the container and the workspace wiring.
- [[api-tests]] — What the api suites guard: the health route, the migration runner and device registration.
