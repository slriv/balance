# Quick Start: Local Sandbox Deployment

The easiest way to deploy and test balance locally without Sonarr/Plex endpoints.

## One-Command Deployment

```bash
cd /path/to/balance
./scripts/deploy-sandbox.sh
```

This will:
1. ✓ Create artifact directories (`artifacts/`, `config/`)
2. ✓ Verify Docker and `balance-tv:local` image exist
3. ✓ Start web UI on `http://localhost:8080`
4. ✓ Validate service is responding

## Access the Web UI

Open in browser: **http://localhost:8080**

### Pages Available
- **Dashboard** — Plan/Dry-Run/Apply balance operations
- **Sonarr** — Reconcile paths (requires Sonarr endpoint in `.env`)
- **Plex** — Reconcile paths (requires Plex endpoint in `.env`)

## Using the Web UI

### 1. Plan a Balance Operation

1. Go to **Dashboard**
2. Fill in **Plan Moves** form:
   - Threshold: `20` (rebalance if any disk > 20% different from others)
   - Max moves: (optional, leave blank for unlimited)
3. Click **Run Plan**
4. Job status appears in **Recent Jobs**
5. View log: Click job ID to stream real-time output

### 2. Preview with Dry-Run

1. Click **Dry-Run Apply**
2. Same parameters as Plan
3. Shows what *would* be moved without actually moving

### 3. Execute Apply

1. Click **Apply Moves**
2. Confirms you've reviewed the plan
3. Executes the planned moves
4. Monitor in **Jobs** for completion

## Container Management

### View logs
```bash
docker logs -f balance-web-sandbox
```

### Stop deployment
```bash
docker stop balance-web-sandbox
```

### Remove (cleanup)
```bash
docker rm balance-web-sandbox
```

### Redeploy
```bash
./scripts/deploy-sandbox.sh
```

## Configuration for Sonarr/Plex (Optional)

To add Sonarr/Plex integration, edit `.env`:

```bash
# .env
SONARR_BASE_URL=http://sonarr.local:8989
SONARR_API_KEY=your_api_key
PLEX_BASE_URL=http://plex.local:32400
PLEX_TOKEN=your_token
```

Create path maps in `config/`:

**`config/sonarr-path-map`:**
```
/sonarr/tv           /tv
/sonarr/overflow     /tv2
```

**`config/plex-path-map`:**
```
/plex/tv             /tv
/plex/overflow       /tv2
```

Then restart:
```bash
docker stop balance-web-sandbox
./scripts/deploy-sandbox.sh
```

## Artifacts

All outputs stored in `artifacts/`:
```
artifacts/
  balance-plan.sh              # Generated move commands
  balance-plan.log             # Plan execution log
  balance-apply-manifest.jsonl # Move history
  balance-jobs.db              # Job store (SQLite)
  jobs/
    JOB_ID.log                 # Individual job logs
```

## Full Docker Compose Deployment

For production or multi-service setup:

```bash
make build
docker compose up -d
```

See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed configuration options.

## Troubleshooting

**Service won't start:**
```bash
docker logs balance-web-sandbox
```

**Port 8080 already in use:**
```bash
# Edit .env and change BALANCE_WEB_PORT
# Then redeploy
./scripts/deploy-sandbox.sh
```

**Jobs not appearing:**
- Check `artifacts/jobs/` for log files
- Verify disk mounts exist in `.env` (TV_PATH_1, etc.)

See [README.md](README.md) for more details.
