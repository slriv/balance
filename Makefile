SHELL := /bin/bash
.DEFAULT_GOAL := help

define HELP_TEXT
Targets:
	help             - Show this help text

	build-test       - Build local test image (balance-test:local) via Dockerfile.test
	test             - Run unit tests in container (prove -Ilib -r t/unit/)
	test-all         - Run all tests in container (prove -Ilib -r t/)
	lint             - Syntax-check Perl + run perlcritic --severity 4

	build            - Build production image locally
	rebuild          - Build production image locally (--no-cache)
	package          - Build image + save distributable package to dist/
	config           - Validate docker-compose.yml syntax

	sonarr-plan      - Build Sonarr reconcile plan from manifest
	sonarr-dry-run   - Preview Sonarr apply actions
	sonarr-apply     - Apply Sonarr reconcile plan
	sonarr-config    - Show Sonarr resolved config (redacted)
	sonarr-series    - List Sonarr series
	sonarr-rescan    - Trigger Sonarr rescan (requires SERIES_ID)

	plex-plan        - Build Plex reconcile plan from manifest
	plex-dry-run     - Preview Plex apply actions
	plex-apply       - Apply Plex reconcile plan
	plex-config      - Show Plex resolved config (redacted)
	plex-libraries   - List Plex libraries
	plex-scan        - Trigger Plex full scan (requires LIBRARY_ID)
	plex-scan-path   - Trigger Plex partial scan (requires LIBRARY_ID, SCAN_PATH)
	plex-empty-trash - Empty Plex trash (requires LIBRARY_ID)

	get-plex-token   - Run Plex PIN auth helper
	setup-git-hooks  - Enable repo pre-push hook (blocks pushes to main)
endef
export HELP_TEXT

LOCAL_DOCKER  ?= docker
IMAGE         ?= balance-tv:local
TEST_IMAGE    ?= balance-test:local

LOCAL_ARTIFACTS ?= artifacts
ENV_FILE        ?= .env
DIST_DIR        ?= dist
IMAGE_TAR       ?= $(DIST_DIR)/balance-tv.tar
RELEASE_TAR     ?= $(DIST_DIR)/balance-tv-release.tar.gz

# Base docker run for local dev targets: reads .env, mounts artifacts + config.
# No media volumes — suitable for plan/dry-run/config inspection locally.
_LOCAL_RUN = $(LOCAL_DOCKER) run --rm \
	$(if $(wildcard $(ENV_FILE)),--env-file $(ENV_FILE),) \
	-v $(CURDIR)/$(LOCAL_ARTIFACTS):/artifacts \
	-v $(CURDIR)/config:/config \
	$(IMAGE)

SONARR_RUN ?= $(_LOCAL_RUN) sonarr_reconcile
PLEX_RUN   ?= $(_LOCAL_RUN) plex_reconcile

.PHONY: \
	help build-test test test-all lint setup-git-hooks build rebuild package config \
	sonarr-plan sonarr-dry-run sonarr-apply sonarr-config sonarr-series sonarr-rescan \
	plex-plan plex-dry-run plex-apply plex-config plex-libraries plex-scan plex-scan-path plex-empty-trash \
	get-plex-token

help:
	@echo "$$HELP_TEXT"

build-test:
	@$(LOCAL_DOCKER) build -f Dockerfile.test -t $(TEST_IMAGE) .

test: build-test
	@$(LOCAL_DOCKER) run --rm \
		-v $(CURDIR)/bin:/app/bin \
		-v $(CURDIR)/lib:/app/lib \
		-v $(CURDIR)/t:/app/t \
		-v $(CURDIR)/templates:/app/templates \
		-v $(CURDIR)/public:/app/public \
		-w /app \
		$(TEST_IMAGE) prove -Ilib -r t/unit/

test-all: build-test
	@$(LOCAL_DOCKER) run --rm \
		-v $(CURDIR)/bin:/app/bin \
		-v $(CURDIR)/lib:/app/lib \
		-v $(CURDIR)/t:/app/t \
		-v $(CURDIR)/templates:/app/templates \
		-v $(CURDIR)/public:/app/public \
		-w /app \
		$(TEST_IMAGE) prove -Ilib -r t/

lint: build-test
	@$(LOCAL_DOCKER) run --rm \
		-v $(CURDIR)/lib:/app/lib \
		-v $(CURDIR)/bin:/app/bin \
		-v $(CURDIR)/scripts:/app/scripts \
		-v $(CURDIR)/balance_tv.pl:/app/balance_tv.pl \
		-v $(CURDIR)/.perlcriticrc:/app/.perlcriticrc \
		-w /app \
		$(TEST_IMAGE) sh -c \
		'perl -Ilib -c bin/balance_tv.pl && perl -Ilib -c bin/sonarr_reconcile.pl && perl -Ilib -c bin/plex_reconcile.pl && perl -Ilib -c bin/balance_web.pl && perlcritic --profile /app/.perlcriticrc --severity 4 lib/ bin/'

setup-git-hooks:
	@git config core.hooksPath .githooks
	@chmod +x .githooks/pre-push
	@echo "Git hooks enabled via .githooks/pre-push"

# ----- Local: build -----

build:
	@$(LOCAL_DOCKER) build -t $(IMAGE) .

rebuild:
	@$(LOCAL_DOCKER) build --no-cache -t $(IMAGE) .

# ----- Distributable package -----
# Produces dist/balance-tv.tar (Docker image) + dist/balance-tv-release.tar.gz
# (compose file + config templates + .env.example + load script).
# Install on any Docker host: see dist/install.sh

package: build
	@mkdir -p '$(DIST_DIR)'
	@echo '==> Saving Docker image to $(IMAGE_TAR)'
	@$(LOCAL_DOCKER) save -o '$(IMAGE_TAR)' $(IMAGE)
	@echo '==> Building release archive'
	@tar -czf '$(RELEASE_TAR)' \
		docker-compose.yml \
		.env.example \
		config/ \
		scripts/install.sh
	@echo '==> Package ready in $(DIST_DIR)/'
	@echo '    Image:   $(IMAGE_TAR)'
	@echo '    Release: $(RELEASE_TAR)'

# ----- Local: compose config validation -----

config:
	@if $(LOCAL_DOCKER) compose version >/dev/null 2>&1; then \
		$(LOCAL_DOCKER) compose -f docker-compose.yml config -q; \
	elif command -v docker-compose >/dev/null 2>&1; then \
		docker-compose -f docker-compose.yml config -q; \
	else \
		echo "Neither 'docker compose' nor 'docker-compose' is available"; \
		exit 1; \
	fi
	@echo "docker-compose.yml OK"

# ----- Local: Sonarr (container, no NAS needed) -----

sonarr-plan:
	@mkdir -p '$(LOCAL_ARTIFACTS)'
	@$(SONARR_RUN)

sonarr-dry-run:
	@mkdir -p '$(LOCAL_ARTIFACTS)'
	@$(SONARR_RUN) dry-run

sonarr-apply:
	@mkdir -p '$(LOCAL_ARTIFACTS)'
	@$(SONARR_RUN) apply

sonarr-config:
	@$(SONARR_RUN) --show-config

sonarr-series:
	@$(SONARR_RUN) series

sonarr-rescan:
ifndef SERIES_ID
	$(error SERIES_ID is required: make sonarr-rescan SERIES_ID=N)
endif
	@$(SONARR_RUN) rescan --series-id='$(SERIES_ID)'

# ----- Local: Plex (container, no NAS needed) -----

plex-plan:
	@mkdir -p '$(LOCAL_ARTIFACTS)'
	@$(PLEX_RUN)

plex-dry-run:
	@mkdir -p '$(LOCAL_ARTIFACTS)'
	@$(PLEX_RUN) dry-run

plex-apply:
	@mkdir -p '$(LOCAL_ARTIFACTS)'
	@$(PLEX_RUN) apply

plex-config:
	@$(PLEX_RUN) --show-config

plex-libraries:
	@$(PLEX_RUN) libraries

plex-scan:
ifndef LIBRARY_ID
	$(error LIBRARY_ID is required: make plex-scan LIBRARY_ID=2)
endif
	@$(PLEX_RUN) scan --library-id='$(LIBRARY_ID)'

plex-scan-path:
ifndef LIBRARY_ID
	$(error LIBRARY_ID is required: make plex-scan-path LIBRARY_ID=2 SCAN_PATH=/tv/ShowName)
endif
ifndef SCAN_PATH
	$(error SCAN_PATH is required: make plex-scan-path LIBRARY_ID=2 SCAN_PATH=/tv/ShowName)
endif
	@$(PLEX_RUN) scan-path --library-id='$(LIBRARY_ID)' --path='$(SCAN_PATH)'

plex-empty-trash:
ifndef LIBRARY_ID
	$(error LIBRARY_ID is required: make plex-empty-trash LIBRARY_ID=2)
endif
	@$(PLEX_RUN) empty-trash --library-id='$(LIBRARY_ID)'

APP_NAME      ?= balance
POLL_INTERVAL ?= 2
TIMEOUT       ?= 300
get-plex-token:
	@perl scripts/plex_auth.pl --app-name='$(APP_NAME)' --poll-interval='$(POLL_INTERVAL)' --timeout='$(TIMEOUT)'
