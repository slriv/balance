SHELL := /bin/bash
.DEFAULT_GOAL := help

NAS_HOST ?= samr@nas.home
REMOTE_DIR ?= /volume1/docker
DOCKER_BIN ?= /usr/local/bin/docker
SERVICE ?= balance

HELPER := ./scripts/nas-helper.sh

RUN_ENV = NAS_HOST='$(NAS_HOST)' REMOTE_DIR='$(REMOTE_DIR)' DOCKER_BIN='$(DOCKER_BIN)' SERVICE='$(SERVICE)'

.PHONY: help lint sync build config help-test smoke run dry-run apply apply-bg apply-logs apply-stop apply-restart tail-log all

help:
	@echo "Targets:"
	@echo "  lint          - Syntax check Perl + bash helper"
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
	@echo "  tail-log      - Tail persistent /logs/apply.log on NAS"
	@echo "  all           - sync + config + build + help-test + smoke"
	@echo
	@echo "Override remote settings as needed:"
	@echo "  make run NAS_HOST=user@nas REMOTE_DIR=/volume1/docker"

lint:
	@perl -c bin/balance_tv.pl
	@bash -n scripts/nas-helper.sh
	@bash -n balance_tv.pl

sync build config help-test smoke run dry-run apply apply-bg apply-logs apply-stop apply-restart tail-log all:
	@$(RUN_ENV) $(HELPER) $@
