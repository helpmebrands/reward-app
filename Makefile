# One entry point for what the verify workflow checks, so a push is rarely
# the first place a failure shows. `make verify` runs every verify job that
# needs no cloud credentials, in CI's order; `make verify-full` adds the slow
# ones. The Pulumi previews stay in CI. The Flutter app has its own Makefile
# in apps/mobile; the flutter row here delegates to it.
#
#   make init          toolchains for every workspace, and the pre-push hook
#   make verify        about two minutes; what .githooks/pre-push runs
#   make verify-full   verify, then the api container

DART   := fvm dart
API_DB := postgres://reward:reward@localhost:5432/reward?sslmode=disable

.DEFAULT_GOAL := help
.PHONY: help init verify verify-full node dart flutter api containers

help: ## List the targets
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

init: ## Install every toolchain and point git at the committed hooks
	npm ci
	$(MAKE) -C apps/mobile init
	git config core.hooksPath .githooks
	@echo "hooks on: .githooks/pre-push runs make verify; skip once with git push --no-verify"

verify: node dart flutter api ## The verify jobs that run without cloud credentials, in CI's order
	@echo "verify: every row passed"

verify-full: verify containers ## verify, then the api container build

node: ## Typecheck and test: the npm job, over infra and infra-repo
	npm run typecheck
	npm test

dart: ## Dart analyze and test: the workspace root and packages/domain
	$(DART) pub get
	$(DART) analyze --fatal-infos
	cd packages/domain && $(DART) test

flutter: ## Flutter analyze, test and format check, through apps/mobile/Makefile
	$(MAKE) -C apps/mobile check

api: ## Api analyze, spec lint and test; against docker compose when docker is up, otherwise with the integration group skipped
	cd services/api && $(DART) analyze --fatal-infos
	npx --yes @redocly/cli@2.53.3 lint services/api/openapi.yaml
	@if docker info >/dev/null 2>&1; then \
	  cd services/api && docker compose up -d --wait && DATABASE_URL='$(API_DB)' $(DART) test; \
	else \
	  echo "api: docker is not running, so the integration group is skipped"; cd services/api && $(DART) test; \
	fi

containers: ## Build the api image the way the api job does
	docker build -f services/api/Dockerfile -t reward-api:verify .
