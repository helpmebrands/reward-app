This directory defines the high-level concepts, business logic, and architecture of this project using markdown. It is managed by [lat.md](https://www.npmjs.com/package/lat.md) — a tool that anchors source code to these definitions. Install the `lat` command with `npm i -g lat.md` and run `lat --help`.

One graph, split by area, so the mobile and api graphs link to the product spec they are written against.

- [[product]] — `product/`: the rules that outlive any implementation. [[overview]], [[domain]], [[reminders]], [[design]] and the [[tests]] specs.
- [[pwa]] — `pwa/`: the frozen reference PWA in `apps/pwa`. [[architecture]], [[delivery]], [[interaction]] and [[pwa-tests]].
- [[mobile]] — `mobile/`: the Flutter app in `apps/mobile`. [[mobile-architecture]] and [[mobile-tests]].
- [[api]] — `api/`: the service tier in `services/api`. [[api-architecture]] and [[api-tests]].
- [[infra]] — `infra/`: the platform. [[deployment]] and [[infra-tests]].
