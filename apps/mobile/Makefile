# Developer entry points for the Flutter app, the way package.json scripts
# serve the PWA. Every Flutter and Dart call goes through FVM so the SDK is
# the one pinned in the root .fvmrc (AGENTS.md rule 9).
#
#   make help
#   make init                 first-time setup on a machine
#   make build ios            release build; `make build` does both platforms
#   make test                 widget suite; `make test ios` adds the e2e run
#   make e2e android          integration tests on an emulator or device
#   make run                  lists devices and asks which; `make run ios` opens the simulator
#   make deploy VERSION=0.1.0-rc.1
#
# `ios` and `android` after a target are platform arguments, not targets.
# ARGS="..." appends flags to the underlying flutter command; DEVICE=<id>
# picks a device for e2e and run. scripts/pick-device.sh does the choosing
# and boots a simulator or emulator when none is running.

ROOT      := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)
FLUTTER   := fvm flutter
DART      := fvm dart
PLATFORMS := ios android
PLATFORM  := $(filter $(PLATFORMS),$(MAKECMDGOALS))
PICK      := scripts/pick-device.sh

.DEFAULT_GOAL := help
.PHONY: help init get analyze format check test e2e build build-ios build-android devices run clean deploy $(PLATFORMS)

# Platform words are accepted as goals so `make build ios` parses; they do nothing themselves.
$(PLATFORMS):
	@:

help: ## List the targets
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  %-9s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo
	@echo "  Platform argument: make build ios | make build android | make test android | make e2e ios"
	@echo "  ARGS=\"...\" appends flutter flags; DEVICE=<id> picks a device for e2e and run"

init: ## Install FVM if missing, fetch the pinned Flutter SDK, resolve the workspace, run doctor
	@command -v fvm >/dev/null || { \
	  command -v brew >/dev/null || { echo "Install Homebrew, or FVM by hand: https://fvm.app"; exit 2; }; \
	  brew tap leoafarias/fvm && brew install fvm; }
	cd $(ROOT) && fvm install --skip-pub-get
	$(FLUTTER) --version
	$(DART) pub get
	$(FLUTTER) doctor

get: ## Resolve the pub workspace
	$(DART) pub get

analyze: ## Static analysis, as the verify gate runs it
	$(FLUTTER) analyze --fatal-infos

format: ## Format the Dart code (rule 9)
	$(DART) format .

check: analyze test ## What CI checks: analyze, widget tests, formatting
	$(DART) format --output=none --set-exit-if-changed .

test: ## Unit and widget tests; `make test ios` or `make test android` also runs e2e there
	$(FLUTTER) test $(ARGS)
	@$(foreach p,$(PLATFORM),$(MAKE) --no-print-directory e2e $(p) &&) true

e2e: ## Integration tests on a simulator or emulator: `make e2e` (iOS), `make e2e android`; boots one if none is running
	@set -e; device=$$($(PICK) "$(or $(firstword $(PLATFORM)),ios)" "$(DEVICE)"); \
	echo "running integration tests on $$device"; \
	$(FLUTTER) test integration_test -d "$$device" $(ARGS)

build: ## Release build: `make build ios` (Runner.app), `make build android` (app bundle), or both
	@$(foreach p,$(or $(PLATFORM),$(PLATFORMS)),$(MAKE) --no-print-directory build-$(p) &&) true

build-ios:
	$(FLUTTER) build ios --release $(ARGS)

build-android:
	$(FLUTTER) build appbundle --release $(ARGS)

devices: ## List the devices, simulators and emulators Flutter can see
	$(FLUTTER) devices
	$(FLUTTER) emulators

run: ## Run the app: `make run ios` (visible simulator) or `make run android`; `make run` lists devices and asks; DEVICE=<id> skips the question
	@set -e; platform="$(firstword $(PLATFORM))"; device="$(DEVICE)"; \
	if [ -z "$$platform" ] && [ -z "$$device" ]; then \
	  $(FLUTTER) devices; \
	  printf 'Device id, or part of its name: '; read -r device; \
	  [ -n "$$device" ] || { echo "no device chosen"; exit 2; }; \
	elif [ -n "$$platform" ]; then \
	  device=$$($(PICK) "$$platform" "$$device"); \
	  [ "$$platform" != ios ] || open -a Simulator; \
	fi; \
	$(FLUTTER) run -d "$$device" $(ARGS)

clean: ## Remove build output
	$(FLUTTER) clean

deploy: ## Tag develop and push it; the release workflow ships both stores. `make deploy VERSION=0.1.0-rc.1`
	@test -z "$(PLATFORM)" || { echo "one tag releases both platforms (docs/runbooks/07-mobile-release.md); drop '$(PLATFORM)'"; exit 2; }
	@test -n "$(VERSION)" || { echo "usage: make deploy VERSION=x.y.z[-rc.n]"; exit 2; }
	@test "$$(git -C $(ROOT) branch --show-current)" = develop || { echo "deploy from develop"; exit 2; }
	@git -C $(ROOT) diff --quiet HEAD || { echo "commit or stash your changes first"; exit 2; }
	git -C $(ROOT) pull --ff-only
	git -C $(ROOT) tag v$(VERSION)
	git -C $(ROOT) push origin v$(VERSION)
	@echo "pushed v$(VERSION); follow it with: gh run watch"
