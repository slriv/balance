# balance

Balance TV show folders across Synology/NAS mounts, generate a move plan, and optionally apply moves with `rsync`.

## Quick start

- Plan only: `make run`
- Dry-run apply (no file moves): `make dry-run`
- Real apply in background: `make apply-bg`
- Follow container logs: `make apply-logs`
- Follow persistent log file: `make tail-log`

## How it works

- `balance` service: read-only mounts, computes plan, writes `/plans/latest-plan.sh` on NAS.
- `balance_apply` service: writable mounts, executes rsync moves, appends `/logs/apply.log` on NAS.
- `scripts/nas-helper.sh`: remote orchestration over SSH + Synology Docker path.

## Configuration

Targets and credentials are environment-driven (see `.env.example`):

- `NAS_HOST` (default `samr@nas.home`)
- `REMOTE_DIR` (default `/volume1/docker`)
- `DOCKER_BIN` (default `/usr/local/bin/docker`)
- `SERVICE` (default `balance`)

Use inline overrides if needed:

`NAS_HOST=user@my-nas REMOTE_DIR=/volume1/docker make run`

## Repo layout

- `bin/balance_tv.pl` — canonical planner/apply script
- `balance_tv.pl` — compatibility launcher to `bin/balance_tv.pl`
- `Dockerfile`, `docker-compose.yml` — container/runtime definition
- `scripts/nas-helper.sh` — NAS helper commands
- `Makefile` — developer-facing command aliases
