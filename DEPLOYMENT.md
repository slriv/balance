# Deployment Guide

This document covers deploying the balance application locally (sandbox) or in production.

## Prerequisites

- Docker (29.4.0+)
- Docker Compose (optional, for full multi-service deployment)
- GNU Make (for build/test targets)

## Quick Start (Sandbox with Web UI)

Ideal for testing the application without live Sonarr/Plex endpoints.

### 1. Build the Image

```bash
make build
```

Produces: `balance-tv:local` image with all CLI tools and web service.

### 2. Create Sandbox Environment

```bash
# Copy example config
cp .env.example .env

# Edit .env to point to your paths, or leave defaults for testing
nano .env
```

### 3. Create Required Directories

```bash
mkdir -p artifacts config jobs
```

### 4. Configure Path Maps (Optional for Sandbox)

For sandbox mode (no Sonarr/Plex), these can be empty. For production, populate:

**`config/sonarr-path-map`** (mount-to-container translation):
```
/mnt/sonarr/tv        /tv
/mnt/sonarr/overflow  /tv2
```

**`config/plex-path-map`** (mount-to-container translation):
```
/mnt/plex/tv          /tv
/mnt/plex/overflow    /tv2
```

### 5. Start Web UI Only

```bash
docker run -d \
  --name balance-web \
  -p 8080:8080 \
  --entrypoint balance_web \
  -v "$(pwd)/artifacts:/artifacts" \
  -v "$(pwd)/config:/config" \
  -e BALANCE_JOB_DB=/artifacts/balance-jobs.db \
  -e BALANCE_JOB_LOG_DIR=/artifacts/jobs \
  balance-tv:local daemon -l 'http://*:8080'
```

### 6. Access Dashboard

Open browser to: **http://localhost:8080**

Expected page: Dashboard with "Balance Operations" form section.

### 7. Verify Functionality

**View logs:**
```bash
docker logs -f balance-web
```

**Stop container:**
```bash
docker stop balance-web && docker rm balance-web
```

---

## Full Deployment (Docker Compose)

For production or multi-service testing with Sonarr/Plex endpoints.

### 1. Build Image

```bash
make build
```

### 2. Configure Environment

```bash
# Create .env with actual paths and credentials
cat > .env << 'EOF'
TV_PATH_1=/mnt/storage/tv
TV_PATH_2=/mnt/storage/tv2
TV_PATH_3=/mnt/storage/tv3
TV_PATH_4=/mnt/nas/tvnas2

ARTIFACTS_DIR=./artifacts
CONFIG_DIR=./config
BALANCE_WEB_PORT=8080

SONARR_BASE_URL=http://sonarr.local:8989
SONARR_API_KEY=your_actual_api_key
PLEX_BASE_URL=http://plex.local:32400
PLEX_TOKEN=your_actual_token
EOF
```

### 3. Create Path Maps

**`config/sonarr-path-map`:**
```
/mnt/storage/tv       /tv
/mnt/storage/tv2      /tv2
/mnt/nas/tvnas2       /tvnas2
```

**`config/plex-path-map`:**
```
/media/tv             /tv
/media/overflow       /tv2
```

### 4. Start Services

```bash
# All three services: planner, apply, web UI
docker compose up -d

# Or just the web UI
docker compose up -d balance_web
```

### 5. Monitor

```bash
# View logs
docker compose logs -f

# Check status
docker compose ps
```

### 6. Access Web UI

**http://localhost:8080** (or `${BALANCE_WEB_PORT}` if customized)

### 7. Shutdown

```bash
docker compose down
```

---

## Using the Web UI

After deployment, the web interface provides:

### Dashboard

- **Plan**: Generate move plan (threshold %, optional max moves)
- **Dry-Run**: Preview apply without moving files
- **Apply**: Execute planned moves

### Sonarr

- **Build Reconcile Plan**: Analyze path changes after balance apply
- **Dry-Run Apply**: Preview Sonarr path updates
- **Apply Reconcile Plan**: Update Sonarr with new paths
- **Audit**: Verify Sonarr paths match NAS
- **Repair**: Fix paths that don't match NAS

### Plex

- **Build Reconcile Plan**: Analyze path changes after balance apply
- **Dry-Run Apply**: Preview Plex path updates
- **Apply Reconcile Plan**: Update Plex with new paths
- **Scan Library**: Trigger full library scan
- **Empty Trash**: Clear Plex trash bin

### Jobs

All operations run asynchronously. View status in **Jobs** list:
- Job ID, type, status, timestamps, real-time log streaming

---

## Artifacts

All outputs written to `ARTIFACTS_DIR` (default: `./artifacts`):

```
artifacts/
  balance-plan.sh              # Generated move commands
  balance-plan.log             # Plan generation log
  balance-apply-manifest.jsonl # Record of moves applied
  balance-apply.log            # Apply execution log
  sonarr-plan.jsonl            # Sonarr reconcile plan
  sonarr-audit-report.jsonl    # Sonarr audit results
  plex-plan.jsonl              # Plex reconcile plan
  balance-jobs.db              # SQLite job store
  jobs/                        # Individual job logs
    JOB_ID.log
```

---

## Troubleshooting

**Web UI not accessible:**
```bash
docker logs balance-web
docker ps | grep balance-web
```

**Path map errors during reconcile:**
- Verify `config/sonarr-path-map` and `config/plex-path-map` exist
- Check paths match Sonarr/Plex actual locations
- Review artifacts logs for detail

**Job fails silently:**
- Check `artifacts/jobs/{job_id}.log`
- Verify environment variables in `.env`
- Ensure Sonarr/Plex endpoints reachable if configured

---

## Next Steps

1. Test sandbox mode (no Sonarr/Plex) first
2. Add Sonarr/Plex endpoints when ready
3. Run plan operation from web UI
4. Review artifacts
5. Run dry-run to validate
6. Execute apply when confident

See [README.md](README.md) for architectural details and [Makefile](Makefile) for all available targets.
