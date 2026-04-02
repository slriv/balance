# balance

Balance TV show folders across Synology/NAS mounts, generate a move plan, and optionally apply moves with `rsync`.

## Quick start

- Plan only: `make run`
- Dry-run apply (no file moves): `make dry-run`
- Real apply in background: `make apply-bg`
- Follow container logs: `make apply-logs`
- Follow persistent log file: `make tail-log`
- Build Sonarr/Plex reconcile plans: `make sonarr-plan`, `make plex-plan`

## How it works

- `balance` service: read-only mounts, computes plan, writes `/artifacts/balance-plan.sh` inside the configured artifact host directory.
- `balance_apply` service: writable mounts, executes rsync moves, appends `/artifacts/balance-apply.log`, and writes `/artifacts/balance-apply-manifest.jsonl` for downstream reconciliation.
- `scripts/nas-helper.sh`: remote orchestration over SSH + Synology Docker path.

## Configuration

Targets and credentials are environment-driven (see `.env.example`):

- `NAS_HOST` (default `samr@nas.home`)
- `REMOTE_DIR` (default `/volume1/docker/balance`)
- `ARTIFACTS_HOST_DIR` (default `${REMOTE_DIR}/artifacts`)
- `DOCKER_BIN` (default `/usr/local/bin/docker`)
- `SERVICE` (default `balance`)
- `BALANCE_MANIFEST_FILE` (default `artifacts/balance-apply-manifest.jsonl`)

Plex settings:

- `PLEX_BASE_URL` — base URL for the Plex server, for example `http://plex-host:32400`
- `PLEX_TOKEN` — Plex token used for future API access
- `PLEX_LIBRARY_IDS` — optional comma-separated library section IDs
- `PLEX_PATH_MAP_FILE` — NAS→Plex path map file
- `PLEX_REPORT_FILE` — output report path for Plex planning/reconciliation
- `PLEX_RETRY_QUEUE_FILE` — reserved retry queue path for future API retries

Sonarr settings:

- `SONARR_BASE_URL` — base URL for the Sonarr server, for example `http://sonarr-host:8989`
- `SONARR_API_KEY` — Sonarr API key used for future API access
- `SONARR_PATH_MAP_FILE` — NAS→Sonarr path map file
- `SONARR_REPORT_FILE` — output report path for Sonarr planning/reconciliation
- `SONARR_RETRY_QUEUE_FILE` — reserved retry queue path for future API retries

Use inline overrides if needed:

`NAS_HOST=user@my-nas REMOTE_DIR=/volume1/docker/balance make run`

`ARTIFACTS_HOST_DIR=/volume1/docker/shared/balance-artifacts make run`

To inspect resolved service configuration without making API calls or touching existing media data:

- `make sonarr-config`
- `make plex-config`

These commands load values from `.env` when present, redact credentials in output, and show the exact manifest/path-map/report files that the project will use.

## Branch workflow

This repo is set up to block direct pushes to `main` with a tracked `pre-push` hook.

Enable it in your clone with:

- `make setup-git-hooks`

Expected workflow:

1. Create a topic branch
2. Commit and push that branch
3. Merge to `main` only when the work is ready

The hook blocks pushes where the remote ref is `refs/heads/main`.

## Reconciliation artifacts

- `${ARTIFACTS_HOST_DIR}/balance-plan.sh` — human-readable move plan
- `${ARTIFACTS_HOST_DIR}/balance-plan.log` — planner output (current/projected state, warnings, move plan)
- `${ARTIFACTS_HOST_DIR}/balance-apply.log` — rsync/apply output log
- `${ARTIFACTS_HOST_DIR}/balance-apply-manifest.jsonl` — machine-readable records for successful APPLY moves
- `config/sonarr-path-map.example` — template for NAS→Sonarr path translation
- `config/plex-path-map.example` — template for NAS→Plex path translation
- `artifacts/sonarr-reconcile-plan.json` / `artifacts/plex-reconcile-plan.json` — default reconcile planning outputs

## Runbook

### Normal workflow

1. Sync the current project to the NAS:
   - `make sync`
2. Validate the remote compose config:
   - `make config`
3. Build the current image on the NAS:
   - `make build`
4. Generate a plan without moving files:
   - `make run`
5. Preview real move behavior without changing files:
   - `make dry-run`

### Apply moves

- Foreground apply:
  - `make apply`
- Background apply:
  - `make apply-bg`
- Follow container logs:
  - `make apply-logs`
- Follow persistent apply log:
  - `make tail-log`
- Stop or restart the background apply container:
  - `make apply-stop`
  - `make apply-restart`

### Build reconcile plans

Run these after a successful APPLY run has created `${ARTIFACTS_HOST_DIR}/balance-apply-manifest.jsonl`.

- Sonarr reconcile plan:
  - `make sonarr-plan`
- Plex reconcile plan:
  - `make plex-plan`

If the manifest file does not exist yet, the reconcile commands will stop with a friendly message telling you to run an APPLY job first.

### Quick checks

- Local syntax/lint pass:
  - `make lint`
- Container help on NAS:
  - `make help-test`
- Smoke-test planner output:
  - `make smoke`

## Repo layout

- `bin/balance_tv.pl` — canonical planner/apply script
- `bin/sonarr_reconcile.pl` — Sonarr-specific reconcile planning entrypoint
- `bin/plex_reconcile.pl` — Plex-specific reconcile planning entrypoint
- `balance_tv.pl` — compatibility launcher to `bin/balance_tv.pl`
- `lib/Balance/*.pm` — shared manifest/path-map/reconcile modules
- `Dockerfile`, `docker-compose.yml` — container/runtime definition
- `scripts/nas-helper.sh` — NAS helper commands
- `Makefile` — developer-facing command aliases
