SHELL := /bin/bash
.DEFAULT_GOAL := help

NAS_HOST ?= samr@nas.home
REMOTE_DIR ?= /volume1/docker/balance
ARTIFACTS_HOST_DIR ?= $(REMOTE_DIR)/artifacts
DOCKER_BIN ?= /usr/local/bin/docker
SERVICE ?= balance

HELPER := ./scripts/nas-helper.sh

RUN_ENV = NAS_HOST='$(NAS_HOST)' REMOTE_DIR='$(REMOTE_DIR)' ARTIFACTS_HOST_DIR='$(ARTIFACTS_HOST_DIR)' DOCKER_BIN='$(DOCKER_BIN)' SERVICE='$(SERVICE)'

.PHONY: help lint setup-git-hooks sync build config help-test smoke run dry-run apply apply-bg apply-logs apply-stop apply-restart tail-log sonarr-config sonarr-plan plex-config plex-plan all

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

sync build config help-test smoke run dry-run apply apply-bg apply-logs apply-stop apply-restart tail-log sonarr-config sonarr-plan plex-config plex-plan all:
	@$(RUN_ENV) $(HELPER) $@
