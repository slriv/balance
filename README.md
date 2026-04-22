# balance

`balance` plans and applies TV-folder moves across mounts, then reconciles Sonarr and Plex so media paths stay consistent.

The repository currently supports two primary workflows:

1. **Build/test/package** via `make` (developer workflow)
2. **Post-deploy operations** via the **Web UI** (`balance_web`)

After deployment, the intended operations path is the web interface (plan, dry-run, apply, Sonarr/Plex plan/dry-run/apply, audit/repair, scan/trash) rather than invoking `make` targets manually.

---

## What this project does

### Planner / mover

- Computes how to rebalance TV folders across mounted paths (`/tv`, `/tv2`, `/tv3`, `/tvnas2` by default)
- Can run in plan-only mode or apply mode
- Writes timestamped plans/logs and JSONL apply manifest records

### Reconcile

- Reads the apply manifest and generates Sonarr/Plex reconcile plans
- Supports dry-run and apply operations for Sonarr and Plex
- Supports Sonarr audit + repair workflows for path validation/fixes

### Web UI

- Provides a lightweight dashboard and async job runner
- Stores job metadata in SQLite
- Streams job logs

---

## Prerequisites

- Docker
- GNU Make
- (Optional) Sonarr and/or Plex endpoints reachable from where containers run

For local development/test commands, dependencies are containerized via `Dockerfile.test` and `Dockerfile`.

---

## Quick start

### Sandbox (Local Testing)

Fastest way to test without Sonarr/Plex endpoints:

```bash
make build
./scripts/deploy-sandbox.sh
# → Opens http://localhost:8080
```

See [QUICK-START.md](QUICK-START.md) for detailed usage.

### Production / Full Setup

1. Copy `.env.example` to `.env` and set values for your environment.
2. Ensure `config/sonarr-path-map` and `config/plex-path-map` are correct for your path translation needs.
3. Build and validate:
   - `make build`
   - `make lint`
   - `make test`
4. Deploy: `docker compose up -d` or see [DEPLOYMENT.md](DEPLOYMENT.md) for options.

---

## Common make targets

Run `make help` for the definitive list. Key targets:

### Quality

- `make lint` — Perl syntax + perlcritic checks in test container
- `make test` — unit tests
- `make test-all` — full test suite

### Images / packaging

- `make build` — build `balance-tv:local`
- `make rebuild` — build without cache
- `make package` — create distributable package in `dist/`

### Planner / apply

- `make run` — generate move plan (read-only)
- `make dry-run` — preview apply behavior without moving files
- `make apply` — apply planned moves

### Sonarr reconcile

- `make sonarr-plan`
- `make sonarr-dry-run`
- `make sonarr-apply`
- `make sonarr-config`
- `make sonarr-series`
- `make sonarr-rescan SERIES_ID=N`

### Plex reconcile

- `make plex-plan`
- `make plex-dry-run`
- `make plex-apply`
- `make plex-config`
- `make plex-libraries`
- `make plex-scan LIBRARY_ID=N`
- `make plex-scan-path LIBRARY_ID=N SCAN_PATH=/path`
- `make plex-empty-trash LIBRARY_ID=N`

### Utilities

- `make get-plex-token`
- `make setup-git-hooks`

---

## Web UI (docker compose)

`docker-compose.yml` defines:

- `balance` (planner)
- `balance_apply` (apply mode)
- `balance_web` (Mojolicious UI/API)

To run the web UI:

- Build image first (`make build`)
- Start service: `docker compose up -d balance_web`
- Open: `http://localhost:${BALANCE_WEB_PORT:-8080}`

Recommended post-deploy flow in the UI:

1. **Dashboard**: `Plan` → `Dry-Run` → `Apply`
2. **Sonarr**: `Build Reconcile Plan` → `Dry-Run Apply` → `Apply Reconcile Plan`
3. **Plex**: `Build Reconcile Plan` → `Dry-Run Apply` → `Apply Reconcile Plan`

Environment used by web service includes:

- `BALANCE_JOB_DB` (default `/artifacts/balance-jobs.db`)
- `BALANCE_JOB_LOG_DIR` (default `/artifacts/jobs`)
- Sonarr/Plex connection variables from `.env`

> Note: current app has a TODO for auth hardening before external exposure.

---

## Configuration reference

Use `.env.example` as the source-of-truth template.

Important variables include:

- Mount paths: `TV_PATH_1..TV_PATH_4`
- Storage paths: `ARTIFACTS_DIR`, `CONFIG_DIR`
- Web port: `BALANCE_WEB_PORT`
- Sonarr: `SONARR_BASE_URL`, `SONARR_API_KEY`, `SONARR_PATH_MAP_FILE`, `SONARR_AUDIT_REPORT_FILE`, `SONARR_REPORT_FILE`, `SONARR_RETRY_QUEUE_FILE`
- Plex: `PLEX_BASE_URL`, `PLEX_TOKEN`, `PLEX_LIBRARY_IDS`, `PLEX_PATH_MAP_FILE`, `PLEX_REPORT_FILE`, `PLEX_RETRY_QUEUE_FILE`
- Shared: `BALANCE_MANIFEST_FILE`

---

## Artifacts

Default artifact location is `ARTIFACTS_DIR` (host) mounted at `/artifacts` (container).

Common outputs:

- `balance-plan-<timestamp>.sh`
- `balance-plan-<timestamp>.log`
- `balance-apply-<timestamp>.log`
- `balance-apply-manifest-<timestamp>.jsonl`
- `sonarr-reconcile-plan.json`
- `sonarr-audit-report.json`
- `plex-reconcile-plan.json`
- `balance-jobs.db`
- `jobs/*.log`

---

## Repository layout

- `bin/` — CLI entrypoints (`balance_tv.pl`, `sonarr_reconcile.pl`, `plex_reconcile.pl`, `balance_web.pl`)
- `lib/Balance/` — core modules (planner, config, reconcile, job store/runner, web controllers)
- `templates/`, `public/` — web UI templates/assets
- `config/` — path map examples
- `scripts/` — helper scripts (install/token/helpers)
- `t/` — test suite

---

## Contributing

1. Create a topic branch
2. Make focused changes
3. Run `make lint` and tests
4. Open a PR

To enable local protection against pushing directly to `main`:

- `make setup-git-hooks`
