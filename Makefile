SHELL := /bin/bash
.DEFAULT_GOAL := help

define HELP_TEXT
Targets:
  lint             - Syntax check Perl + bash helper
  setup-git-hooks  - Enable repo pre-push hook (blocks pushes to main)
  sync             - Copy project files to NAS
  build            - Build image on NAS
  config           - Validate compose config on NAS
  help-test        - Run container with --help
  smoke            - Run planner and show first output lines
  run              - Planner run (writes plan file on NAS)
  dry-run          - Simulate apply with rsync -n
  test-apply       - Apply exactly MAX_MOVES moves (default 10); safe end-to-end test
  apply            - Apply moves in foreground
  apply-bg         - Start apply service in background
  apply-logs       - Tail apply service logs
  apply-status     - Show apply service container state and exit code
  apply-stop       - Stop apply service
  apply-restart    - Restart apply service
  tail-log         - Tail persistent artifacts/balance-apply.log on NAS
  sonarr-plan      - Build Sonarr reconcile plan (runs in container on NAS)
  sonarr-dry-run   - Preview Sonarr reconcile apply (runs in container on NAS)
  sonarr-apply     - Apply Sonarr reconcile plan (runs in container on NAS)
  plex-plan        - Build Plex reconcile plan (runs in container on NAS)
  plex-dry-run     - Preview Plex reconcile apply (runs in container on NAS)
  plex-apply       - Apply Plex reconcile plan (runs in container on NAS)
  sonarr-config    - Show resolved Sonarr config locally (no API calls)
  sonarr-series    - List Sonarr series with IDs and paths (local)
  sonarr-rescan    - Trigger disk rescan for a series  SERIES_ID=N (local)
  plex-config      - Show resolved Plex config locally (no API calls)
  plex-libraries   - List Plex library sections (local)
  plex-scan        - Trigger full library scan  LIBRARY_ID=N (local)
  plex-scan-path   - Trigger partial path scan  LIBRARY_ID=N SCAN_PATH=/... (local)
  plex-empty-trash - Empty library trash  LIBRARY_ID=N (local)
  get-plex-token   - Authenticate with Plex.tv and print your PLEX_TOKEN
                     Options: APP_NAME=balance POLL_INTERVAL=2 TIMEOUT=300
  all              - sync + config + build + help-test + smoke

Override remote settings as needed:
  make run NAS_HOST=user@nas REMOTE_DIR=/volume1/docker/balance
  make run ARTIFACTS_HOST_DIR=/volume1/docker/shared/balance-artifacts
endef
export HELP_TEXT

NAS_HOST ?= samr@nas.home
REMOTE_DIR ?= /volume1/docker/balance
ARTIFACTS_HOST_DIR ?= $(REMOTE_DIR)/artifacts
DOCKER_BIN ?= /usr/local/bin/docker
SERVICE ?= balance

HELPER := ./scripts/nas-helper.sh

RUN_ENV = NAS_HOST='$(NAS_HOST)' REMOTE_DIR='$(REMOTE_DIR)' ARTIFACTS_HOST_DIR='$(ARTIFACTS_HOST_DIR)' DOCKER_BIN='$(DOCKER_BIN)' SERVICE='$(SERVICE)'

.PHONY: help lint setup-git-hooks sync build rebuild config help-test smoke run dry-run test-apply apply apply-bg apply-logs apply-status apply-stop apply-restart tail-log sonarr-plan sonarr-dry-run sonarr-apply plex-plan plex-dry-run plex-apply sonarr-config sonarr-series sonarr-rescan plex-config plex-libraries plex-scan plex-scan-path plex-empty-trash get-plex-token all

help:
	@echo "Targets:"
	@echo "  lint          - Syntax check Perl + bash helper"
	@echo "  setup-git-hooks - Enable repo pre-push hook (blocks pushes to main)"
	@echo "  sync          - Copy project files to NAS"
	@echo "  build         - Build image on NAS"
	@echo "  config        - Validate compose config on NAS"
	@echo "  help-test     - Run container with --help"
	@echo "  smoke         - Run planner and show first output lines"
	@echo "  run           - Planner run (writes plan file on NAS)"
	@echo "  dry-run       - Simulate apply with rsync -n"
	@echo "  apply         - Apply moves in foreground"
	@echo "  apply-bg      - Start apply service in background"
	@echo "  apply-logs    - Tail apply service logs"
	@echo "  apply-stop    - Stop apply service"
	@echo "  apply-restart - Restart apply service"
	@echo "  tail-log      - Tail persistent artifacts/balance-apply.log on NAS"
	@echo "  sonarr-config - Show resolved Sonarr config (redacted; no API calls)"
	@echo "  sonarr-plan   - Build Sonarr reconcile plan from latest manifest"
	@echo "  plex-config   - Show resolved Plex config (redacted; no API calls)"
	@echo "  plex-plan     - Build Plex reconcile plan from latest manifest"
	@echo "  all           - sync + config + build + help-test + smoke"
	@echo
	@echo "Override remote settings as needed:"
	@echo "  make run NAS_HOST=user@nas REMOTE_DIR=/volume1/docker/balance"
	@echo "  make run ARTIFACTS_HOST_DIR=/volume1/docker/shared/balance-artifacts"

lint:
	@perl -Ilib -c bin/balance_tv.pl
	@perl -Ilib -c bin/sonarr_reconcile.pl
	@perl -Ilib -c bin/plex_reconcile.pl
	@bash -n scripts/nas-helper.sh
	@bash -n balance_tv.pl

setup-git-hooks:
	@git config core.hooksPath .githooks
	@chmod +x .githooks/pre-push
	@echo "Git hooks enabled via .githooks/pre-push"

plex-libraries:
	@$(PLEX_CLI) libraries

plex-scan:
ifndef LIBRARY_ID
	$(error LIBRARY_ID is required: make plex-scan LIBRARY_ID=2)
endif
	@$(PLEX_CLI) scan --library-id='$(LIBRARY_ID)'

plex-scan-path:
ifndef LIBRARY_ID
	$(error LIBRARY_ID is required: make plex-scan-path LIBRARY_ID=2 SCAN_PATH=/tv/ShowName)
endif
ifndef SCAN_PATH
	$(error SCAN_PATH is required: make plex-scan-path LIBRARY_ID=2 SCAN_PATH=/tv/ShowName)
endif
	@$(PLEX_CLI) scan-path --library-id='$(LIBRARY_ID)' --path='$(SCAN_PATH)'

plex-empty-trash:
ifndef LIBRARY_ID
	$(error LIBRARY_ID is required: make plex-empty-trash LIBRARY_ID=2)
endif
	@$(PLEX_CLI) empty-trash --library-id='$(LIBRARY_ID)'

sonarr-series:
	@$(SONARR_CLI) series

sonarr-rescan:
ifndef SERIES_ID
	$(error SERIES_ID is required: make sonarr-rescan SERIES_ID=N)
endif
	@$(SONARR_CLI) rescan --series-id='$(SERIES_ID)'

sonarr-config:
	@perl -Ilib bin/sonarr_reconcile.pl --show-config --env-file='$(SONARR_ENV_FILE)'

plex-config:
	@perl -Ilib bin/plex_reconcile.pl --show-config --env-file='$(PLEX_ENV_FILE)'

APP_NAME      ?= balance
POLL_INTERVAL ?= 2
TIMEOUT       ?= 300
get-plex-token:
	@perl scripts/plex_auth.pl --app-name='$(APP_NAME)' --poll-interval='$(POLL_INTERVAL)' --timeout='$(TIMEOUT)'

sync build rebuild config help-test smoke run dry-run apply apply-bg apply-logs apply-status apply-stop apply-restart tail-log sonarr-plan sonarr-dry-run sonarr-apply plex-plan plex-dry-run plex-apply all:
	@$(RUN_ENV) $(HELPER) $@

MAX_MOVES ?= 10
test-apply:
	@$(RUN_ENV) MAX_MOVES='$(MAX_MOVES)' $(HELPER) test-apply
