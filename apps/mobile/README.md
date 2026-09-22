# HelpMe Reward, the Flutter app

The product from `apps/pwa` rebuilt on `packages/domain` for iOS and Android.
It talks to `services/api`. macOS is a local run target only, there to try
the medium and expanded width classes on a laptop; it is never released. Design and test notes live in `lat.md/mobile/`;
getting a build to testers is `docs/runbooks/07-mobile-release.md`.

The Flutter version is pinned in the root `.fvmrc` and managed with
[FVM](https://fvm.app). Every Flutter and Dart command runs through it as
`fvm flutter` and `fvm dart` (AGENTS.md rule 9). The `Makefile` here wraps
the everyday commands the way `package.json` scripts do for the PWA.

## Make targets

Run them from this directory. `make help` prints the same list.

| Target | Does |
| --- | --- |
| `make init` | Installs FVM if missing, fetches the pinned Flutter SDK, resolves the pub workspace and runs `flutter doctor`. Once per machine. |
| `make build ios` / `make build android` / `make build macos` | Release build for one platform (`Runner.app`, the app bundle, or the macOS `.app`). `make build` alone does the two store platforms. |
| `make test` | The unit and widget suite. `make test ios` or `make test android` runs it and then the e2e suite on that platform. |
| `make e2e` / `make e2e android` | The integration tests in `integration_test/` on a simulator (default iOS) or emulator, booting one if none is running. `DEVICE=<id>` picks a specific device. The simulator stays booted afterwards; `xcrun simctl shutdown all` stops it. |
| `make deploy VERSION=0.1.0-rc.1` | Tags `develop` and pushes the tag. The release workflow builds both platforms from it and ships to TestFlight and the Play internal track; there is no per-platform deploy. |
| `make check` | What the verify gate runs: analyze, widget tests, format check. |
| `make run` | Lists the devices Flutter sees and asks which to run on. Pass part of the name (`Air`) or the id. `make run ios` boots and shows the iPhone simulator; `make run android` does the same with an emulator; `make run macos` opens the app in a resizable window so the wider width classes can be dragged into view. `DEVICE=<id>` skips the question. |
| `make devices` | Lists devices, simulators and emulators. A wireless phone appears a few seconds after the wired ones. |
| `make analyze`, `make format`, `make get`, `make clean` | The matching `fvm flutter` or `fvm dart` command. |
| `make help` | Lists the targets. |

`ARGS="..."` appends flags to the underlying command, for example
`make test ARGS="--name first-run"`.
