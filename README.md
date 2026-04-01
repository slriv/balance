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

- `balance` service: read-only mounts, computes plan, writes `/plans/latest-plan.sh` on NAS.
- `balance_apply` service: writable mounts, executes rsync moves, appends `/logs/apply.log` on NAS, and writes `/logs/latest-manifest.jsonl` for downstream reconciliation.
- `scripts/nas-helper.sh`: remote orchestration over SSH + Synology Docker path.

## Configuration

Targets and credentials are environment-driven (see `.env.example`):

- `NAS_HOST` (default `samr@nas.home`)
- `REMOTE_DIR` (default `/volume1/docker`)
- `DOCKER_BIN` (default `/usr/local/bin/docker`)
- `SERVICE` (default `balance`)

Use inline overrides if needed:

`NAS_HOST=user@my-nas REMOTE_DIR=/volume1/docker make run`

## Reconciliation artifacts

- `/volume1/docker/plans/latest-plan.sh` — human-readable move plan
- `/volume1/docker/logs/apply.log` — rsync/apply output log
- `/volume1/docker/logs/latest-manifest.jsonl` — machine-readable records for successful APPLY moves
- `config/sonarr-path-map.example` — template for NAS→Sonarr path translation
- `config/plex-path-map.example` — template for NAS→Plex path translation

## Repo layout

- `bin/balance_tv.pl` — canonical planner/apply script
- `bin/sonarr_reconcile.pl` — Sonarr-specific reconcile planning entrypoint
- `bin/plex_reconcile.pl` — Plex-specific reconcile planning entrypoint
- `balance_tv.pl` — compatibility launcher to `bin/balance_tv.pl`
- `lib/Balance/*.pm` — shared manifest/path-map/reconcile modules
- `Dockerfile`, `docker-compose.yml` — container/runtime definition
- `scripts/nas-helper.sh` — NAS helper commands
- `Makefile` — developer-facing command aliases
