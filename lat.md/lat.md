This directory defines the high-level concepts, business logic, and architecture of this project using markdown. It is managed by [lat.md](https://www.npmjs.com/package/lat.md) — a tool that anchors source code to these definitions. Install the `lat` command with `npm i -g lat.md` and run `lat --help`.

- [[overview]] — What HelpMe Reward is, the household premise, the three distinctions that drive the design, stack and source layout.
- [[domain]] — Cards, benefits, cycles, claims, the status ladder, overlaps, the missed ledger and card value.
- [[reminders]] — The per-cadence ladder, schedule construction and grouping, delivery paths, and service-worker replay.
- [[architecture]] — Layers, IndexedDB persistence, the app and UI stores, the shell, service-worker lifecycle and environment variables.
- [[design]] — Nocturne and Material rules, tokens, the screens, swipe rows, sheets, undo over confirmation, accessibility.
- [[deployment]] — CI/CD, the Pulumi-owns-shape / CI-owns-image rule, the container, cache and security headers, infrastructure.
- [[tests]] — What each Vitest suite guards: dates, cycles, selectors, reminders, and the store.
