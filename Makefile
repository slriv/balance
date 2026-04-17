SHELL := /bin/bash
.DEFAULT_GOAL := help

define HELP_TEXT
Targets:
  build-test       - Build local test image (balance-test:local) via Dockerfile.test
  test             - Run unit tests in container (prove -Ilib -r t/unit/)
  test-all         - Run all tests in container including integration
  lint             - Syntax check Perl in container + perlcritic --severity 4; bash check
  build            - Build production image locally (Colima)
  rebuild          - Build production image locally (--no-cache)
  setup-git-hooks  - Enable repo pre-push hook (blocks pushes to main)
endef
export HELP_TEXT

LOCAL_DOCKER  ?= docker
IMAGE         ?= balance-tv:local
TEST_IMAGE    ?= balance-test:local

.PHONY: help build-test test test-all lint setup-git-hooks build rebuild

help:
	@echo "$$HELP_TEXT"

build-test:
	@$(LOCAL_DOCKER) build -f Dockerfile.test -t $(TEST_IMAGE) .

test: build-test
	@$(LOCAL_DOCKER) run --rm \
		-v $(CURDIR)/lib:/app/lib \
		-v $(CURDIR)/t:/app/t \
		-w /app \
		$(TEST_IMAGE) prove -Ilib -r t/unit/

test-all: build-test
	@$(LOCAL_DOCKER) run --rm \
		-v $(CURDIR)/lib:/app/lib \
		-v $(CURDIR)/t:/app/t \
		-w /app \
		$(TEST_IMAGE) prove -Ilib -r t/

lint: build-test
	@bash -n scripts/nas-helper.sh
	@bash -n balance_tv.pl
	@$(LOCAL_DOCKER) run --rm \
		-v $(CURDIR)/lib:/app/lib \
		-v $(CURDIR)/bin:/app/bin \
		-v $(CURDIR)/scripts:/app/scripts \
		-v $(CURDIR)/balance_tv.pl:/app/balance_tv.pl \
		-v $(CURDIR)/.perlcriticrc:/app/.perlcriticrc \
		-w /app \
		$(TEST_IMAGE) sh -c \
		'perl -Ilib -c bin/balance_tv.pl && perl -Ilib -c bin/sonarr_reconcile.pl && perl -Ilib -c bin/plex_reconcile.pl && perlcritic --profile /app/.perlcriticrc --severity 4 lib/ bin/'

setup-git-hooks:
	@git config core.hooksPath .githooks
	@chmod +x .githooks/pre-push
	@echo "Git hooks enabled via .githooks/pre-push"

# ----- Local: build -----

build:
	@$(LOCAL_DOCKER) build -t $(IMAGE) .

rebuild:
	@$(LOCAL_DOCKER) build --no-cache -t $(IMAGE) .

push-image:
	@echo "==> Saving $(IMAGE) and loading into NAS docker..."
	@$(LOCAL_DOCKER) save $(IMAGE) | ssh $(NAS_HOST) "sudo -n $(DOCKER_BIN) load"

pull-artifacts:
	@mkdir -p '$(LOCAL_ARTIFACTS)'
	@scp -O '$(NAS_HOST):$(ARTIFACTS_HOST_DIR)/*.jsonl' '$(LOCAL_ARTIFACTS)/' 2>/dev/null || true
	@scp -O '$(NAS_HOST):$(ARTIFACTS_HOST_DIR)/*.json' '$(LOCAL_ARTIFACTS)/' 2>/dev/null || true
	@scp -O '$(NAS_HOST):$(ARTIFACTS_HOST_DIR)/*.sh' '$(LOCAL_ARTIFACTS)/' 2>/dev/null || true
	@echo "==> Artifacts pulled to $(LOCAL_ARTIFACTS)"

# ----- Local: compose config validation -----

config:
	@python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1])); print('docker-compose.yml OK')" docker-compose.yml

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

# ----- NAS: source sync + image build -----

sync:
	@$(RUN_ENV) $(HELPER) sync

nas-build: sync
	@$(RUN_ENV) $(HELPER) build

nas-rebuild: sync
	@$(RUN_ENV) $(HELPER) rebuild

# ----- NAS: planner and apply (need media volumes) -----

help-test smoke run dry-run apply apply-bg apply-logs apply-status apply-stop apply-restart tail-log all:
	@$(RUN_ENV) $(HELPER) $@

MAX_MOVES ?= 10
test-apply:
	@$(RUN_ENV) MAX_MOVES='$(MAX_MOVES)' $(HELPER) test-apply
