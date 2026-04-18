<a id="readme-top"></a>

[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stars][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]

<br />
<div align="center">
  <h3 align="center">balance</h3>
  <p align="center">
    Rebalance TV show folders across NAS mounts and reconcile Sonarr and Plex — all from a single <code>make</code> command.
    <br />
    <a href="#usage"><strong>Runbook »</strong></a>
    &nbsp;·&nbsp;
    <a href="https://github.com/slriv/balance/issues/new?labels=bug">Report Bug</a>
    &nbsp;·&nbsp;
    <a href="https://github.com/slriv/balance/issues/new?labels=enhancement">Request Feature</a>
  </p>
</div>

<details>
  <summary>Table of Contents</summary>
  <ol>
    <li><a href="#about-the-project">About The Project</a></li>
    <li><a href="#built-with">Built With</a></li>
    <li>
      <a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#installation">Installation</a></li>
      </ul>
    </li>
    <li><a href="#usage">Usage</a></li>
    <li>
      <a href="#reference">Reference</a>
      <ul>
        <li><a href="#make-targets">Make targets</a></li>
        <li><a href="#environment-variables">Environment variables</a></li>
        <li><a href="#artifacts">Artifacts</a></li>
        <li><a href="#nas-directory-layout">NAS directory layout</a></li>
        <li><a href="#repo-layout">Repo layout</a></li>
      </ul>
    </li>
    <li><a href="#contributing">Contributing</a></li>
  </ol>
</details>

---

## About The Project

`balance` solves the problem of uneven disk usage across multiple NAS mounts. When one TV volume fills up, it plans and executes `rsync` moves to redistribute shows across available mounts — then updates Sonarr series paths and triggers Plex library scans automatically so nothing breaks.

The workflow has three phases:

1. **Plan** — `make run` computes which shows to move and where, writing a human-readable plan to `ARTIFACTS_HOST_DIR`. Review it before proceeding.
2. **Apply** — `make apply` executes the moves via `rsync` and records each successful move in a JSONL manifest.
3. **Reconcile** — `make sonarr-plan` / `make plex-plan` translate manifest paths and produce service-specific plans; `make sonarr-apply` / `make plex-apply` update Sonarr series paths and trigger Plex library scans.

Everything runs in Docker containers on the NAS. `scripts/nas-helper.sh` orchestrates all phases over SSH from your local machine via `make` targets.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Built With

* [Perl](https://www.perl.org/) — planner, API clients, reconcile logic
* [Docker](https://www.docker.com/) + [Alpine Linux](https://alpinelinux.org/) — NAS container runtime
* [rsync](https://rsync.samba.org/) — file move engine

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Getting Started

### Prerequisites

* A Synology (or compatible) NAS with Docker and SSH access
* `docker compose` v2.20+ on the NAS (`sudo docker compose version`)
* SSH key auth configured to the NAS (`ssh-copy-id user@nas.home`)
* Perl with `LWP::UserAgent`, `JSON`, `Data::GUID`, `IO::Socket::SSL` installed **locally** (only needed for `make get-plex-token` and local dev targets — not for NAS operations)
* Sonarr and/or Plex running and reachable from the NAS

### Installation

1. **Clone the repo** on your local machine:

   ```sh
   git clone https://github.com/slriv/balance.git
   cd balance
   ```

2. **Get your Plex token** (skip if not using Plex):

   ```sh
   make get-plex-token
   ```

   Follow the browser prompt. Copy the printed `PLEX_TOKEN=...` line for the next step.

3. **Create `.env` on the NAS** at `REMOTE_DIR` (default `/volume1/docker/balance/.env`).
   Use `/artifacts` and `/config` as path roots — these are the container mount points:

   ```sh
   # Sonarr
   SONARR_BASE_URL=http://sonarr-host:8989
   SONARR_API_KEY=your-api-key
   SONARR_PATH_MAP_FILE=/config/sonarr-path-map.json
   SONARR_REPORT_FILE=/artifacts/sonarr-reconcile-plan.json
   SONARR_RETRY_QUEUE_FILE=/artifacts/sonarr-retry-queue.jsonl

   # Plex
   PLEX_BASE_URL=http://plex-host:32400
   PLEX_TOKEN=your-token
   PLEX_PATH_MAP_FILE=/config/plex-path-map.json
   PLEX_REPORT_FILE=/artifacts/plex-reconcile-plan.json
   PLEX_RETRY_QUEUE_FILE=/artifacts/plex-retry-queue.jsonl

   # Shared
   BALANCE_MANIFEST_FILE=/artifacts/balance-apply-manifest.jsonl
   ```

4. **Create path map files** on the NAS at `REMOTE_DIR/config/`.
   See `config/sonarr-path-map.example` and `config/plex-path-map.example` for format.
   Each line maps a NAS path prefix to the path the service sees:

   ```
   /volume2/TV=/tv
   /volumeUSB1/usbshare=/tv2
   ```

5. **Sync and build**:

   ```sh
   make sync    # rsync project files to NAS
   make build   # build balance-tv:local image on NAS
   make smoke   # sanity check: run planner and show first output lines
   ```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Usage

### Full end-to-end rebalance

#### 1. Plan (read-only, no moves)

```sh
make run
```

Reviews disk state and writes a timestamped `balance-plan-<timestamp>.sh` to `ARTIFACTS_HOST_DIR`. Read it to confirm the proposed moves before proceeding.

Optionally simulate the full rsync without moving anything:

```sh
make dry-run
```

#### 2. Apply moves

Run a limited test first to validate the full pipeline end-to-end:

```sh
make test-apply            # move MAX_MOVES shows (default 10)
make test-apply MAX_MOVES=5
```

When satisfied, run the full apply:

```sh
make apply-bg       # start balance_apply container in background
make apply-logs     # tail container logs
make tail-log       # tail the persistent apply log on the NAS
make apply-status   # show container state and exit code when done
```

Or in foreground (blocks until complete):

```sh
make apply
```

When done, `ARTIFACTS_HOST_DIR/balance-apply-manifest.jsonl` contains one JSONL record per successful move.

#### 3. Build reconcile plans

```sh
make sonarr-plan
make plex-plan
```

Reads the manifest, applies the path map, and writes a JSON plan to `/artifacts/`. Stops with a clear error if the manifest does not exist yet.

#### 4. Preview reconcile actions

```sh
make sonarr-dry-run
make plex-dry-run
```

Makes read-only API calls to resolve series/library IDs, then prints what it would do without writing anything.

#### 5. Apply reconcile

```sh
make sonarr-apply
make plex-apply
```

**Sonarr**: updates each series `path` to the new location and triggers a `RescanSeries` command.

**Plex**: triggers a partial scan on the old and new paths for each moved show, then empties library trash for each affected section.

---

### Other operations

```sh
make apply-stop       # stop the apply container
make apply-restart    # restart it
make config           # validate compose config on NAS
make lint             # local Perl + bash syntax check
make help-test        # run container --help on NAS
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Reference

### Make targets

Run `make help` for the full list. Key targets:

| Target | Description |
|---|---|
| `sync` | rsync project files to NAS |
| `build` | build `balance-tv:local` image on NAS |
| `run` | generate move plan (read-only) |
| `dry-run` | simulate apply with `rsync -n` |
| `test-apply` | apply exactly `MAX_MOVES` moves (default 10) |
| `apply` / `apply-bg` | execute moves in foreground / background |
| `apply-logs` | tail container logs |
| `apply-status` | show container state and exit code |
| `tail-log` | tail persistent `balance-apply.log` on NAS |
| `sonarr-plan` | build Sonarr reconcile plan from manifest |
| `sonarr-dry-run` | preview Sonarr API updates (no writes) |
| `sonarr-apply` | update Sonarr series paths + trigger rescans |
| `plex-plan` | build Plex reconcile plan from manifest |
| `plex-dry-run` | preview Plex scan operations (no writes) |
| `plex-apply` | trigger Plex scans + empty trash |
| `get-plex-token` | authenticate with Plex.tv and print `PLEX_TOKEN` |
| `sonarr-config` | show resolved Sonarr config (redacted, no API) |
| `sonarr-series` | list all Sonarr series with IDs and paths |
| `sonarr-rescan SERIES_ID=N` | trigger rescan for one series |
| `plex-config` | show resolved Plex config (redacted, no API) |
| `plex-libraries` | list Plex library sections with IDs and paths |
| `plex-scan LIBRARY_ID=N` | trigger a full library scan |
| `plex-scan-path LIBRARY_ID=N SCAN_PATH=/...` | trigger a partial path scan |
| `plex-empty-trash LIBRARY_ID=N` | empty library trash |

Override settings inline:

```sh
make run NAS_HOST=user@my-nas REMOTE_DIR=/volume1/docker/balance
make run ARTIFACTS_HOST_DIR=/volume1/docker/shared/balance-artifacts
make test-apply MAX_MOVES=5
make get-plex-token APP_NAME=mynas TIMEOUT=120
```

### Environment variables

**NAS/orchestration** (Makefile defaults, override inline or in a local `.env.local`):

| Variable | Default | Description |
|---|---|---|
| `NAS_HOST` | `samr@nas.home` | SSH target for NAS |
| `REMOTE_DIR` | `/volume1/docker/balance` | Project root on NAS |
| `ARTIFACTS_HOST_DIR` | `${REMOTE_DIR}/artifacts` | Output directory on NAS host |
| `DOCKER_BIN` | `/usr/local/bin/docker` | Docker binary path on NAS |
| `SERVICE` | `balance` | Compose service name for planner |
| `MAX_MOVES` | `10` | Move limit for `test-apply` |
| `APP_NAME` | `balance` | App name shown in Plex device list (`get-plex-token`) |
| `POLL_INTERVAL` | `2` | Poll interval in seconds (`get-plex-token`) |
| `TIMEOUT` | `300` | Auth timeout in seconds (`get-plex-token`) |

**Container env** (set in `.env` on the NAS; all paths are container-relative):

| Variable | Description |
|---|---|
| `BALANCE_MANIFEST_FILE` | Manifest written by `balance_apply`, read by all reconcile plan containers |
| `SONARR_BASE_URL` | Sonarr server base URL |
| `SONARR_API_KEY` | Sonarr API key |
| `SONARR_PATH_MAP_FILE` | NAS-to-Sonarr path map file |
| `SONARR_REPORT_FILE` | Sonarr reconcile plan output path |
| `SONARR_RETRY_QUEUE_FILE` | Sonarr retry queue path |
| `PLEX_BASE_URL` | Plex server base URL |
| `PLEX_TOKEN` | Plex authentication token (use `make get-plex-token`) |
| `PLEX_LIBRARY_IDS` | Optional comma-separated Plex library section IDs to scope operations |
| `PLEX_PATH_MAP_FILE` | NAS-to-Plex path map file |
| `PLEX_REPORT_FILE` | Plex reconcile plan output path |
| `PLEX_RETRY_QUEUE_FILE` | Plex retry queue path |

### Artifacts

All output files land in `ARTIFACTS_HOST_DIR` on the NAS (mounted at `/artifacts` in all containers):

| File | Written by | Description |
|---|---|---|
| `balance-plan-<timestamp>.sh` | `balance` | Human-readable rsync move plan |
| `balance-plan-<timestamp>.log` | `balance` | Full planner output per run |
| `balance-apply.log` | `balance_apply` | rsync apply output (appended each run) |
| `balance-apply-manifest.jsonl` | `balance_apply` | One JSONL record per successful move |
| `sonarr-reconcile-plan.json` | `sonarr_plan` | Sonarr reconcile operations |
| `plex-reconcile-plan.json` | `plex_plan` | Plex reconcile operations |

### NAS directory layout

```
/volume1/docker/balance/              <- REMOTE_DIR (synced by make sync)
    docker-compose.yml
    Dockerfile
    .env                              <- credentials (not synced; create manually)
    bin/
    lib/
    config/
        sonarr-path-map.json          <- NAS-to-Sonarr path translation
        plex-path-map.json            <- NAS-to-Plex path translation

/volume1/docker/balance/artifacts/    <- ARTIFACTS_HOST_DIR (mounted at /artifacts)
    balance-plan-<timestamp>.sh
    balance-plan-<timestamp>.log
    balance-apply.log
    balance-apply-manifest.jsonl
    sonarr-reconcile-plan.json
    plex-reconcile-plan.json
```

### Repo layout

```
bin/
    balance_tv.pl           planner/apply entrypoint (runs in container)
    sonarr_reconcile.pl     Sonarr reconcile plan builder
    plex_reconcile.pl       Plex reconcile plan builder
lib/Balance/
    Config.pm               .env loading and service defaults
    Core.pm                 volume state calculations, logging utilities
    Manifest.pm             JSONL manifest read/write
    PathMap.pm              NAS-to-service path translation
    Reconcile.pm            reconcile plan builder (shared)
    ReconcileApp.pm         reconcile CLI runner (shared)
    Sonarr.pm               Sonarr API client + CLI
    Plex.pm                 Plex API client + CLI
    WebClient.pm            shared HTTP base class (Sonarr, Plex)
t/unit/Balance/
    WebClient.t  Config.t  Core.t  Manifest.t
    PathMap.t    Reconcile.t  ReconcileApp.t
    Sonarr.t     Plex.t
scripts/
    nas-helper.sh           SSH orchestration for all NAS operations
    plex_auth.pl            Plex.tv PIN auth flow -- prints PLEX_TOKEN
Dockerfile
docker-compose.yml
Makefile                    make help for full target list
.env.example                template for local/Makefile overrides
config/
    sonarr-path-map.example path map format reference
    plex-path-map.example   path map format reference
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Contributing

1. Fork the project
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes
4. Push to the branch and open a pull request

This repo blocks direct pushes to `main` via a tracked pre-push hook. Enable it with:

```sh
make setup-git-hooks
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

<!-- MARKDOWN LINKS -->
[contributors-shield]: https://img.shields.io/github/contributors/slriv/balance.svg?style=for-the-badge
[contributors-url]: https://github.com/slriv/balance/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/slriv/balance.svg?style=for-the-badge
[forks-url]: https://github.com/slriv/balance/network/members
[stars-shield]: https://img.shields.io/github/stars/slriv/balance.svg?style=for-the-badge
[stars-url]: https://github.com/slriv/balance/stargazers
[issues-shield]: https://img.shields.io/github/issues/slriv/balance.svg?style=for-the-badge
[issues-url]: https://github.com/slriv/balance/issues
