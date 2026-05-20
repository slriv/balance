# App::Balance

> [!CAUTION]
> **Work in progress.** Lots of churn, lots of untested code.

App::Balance plans and applies media folder rebalancing across mounts, then reconciles Sonarr and Plex to keep service library paths consistent.

## Synopsis

Or build from this repository:

```bash
make cpan-build
sudo make install
```

Run the tools after installation:

```bash
balance --help
balance_sonarr --help
balance_plex --help
balance_web --help
```

## Verified doc examples

Runnable versions of the README command examples live in `doc-examples/`:

- `doc-examples/01-cli-help.sh`
- `doc-examples/02-balance-workflow.sh`
- `doc-examples/03-reconcile-help.sh`
- `doc-examples/04-web-ui-help.sh`

From source checkout, run:

```bash
./doc-examples/01-cli-help.sh
./doc-examples/02-balance-workflow.sh
./doc-examples/03-reconcile-help.sh
./doc-examples/04-web-ui-help.sh
```

These scripts set `PERL5LIB` for local source execution (so `balance` can load
`WebService::Arr` from a sibling checkout) and avoid long-running daemon
execution during verification.

## Description

App::Balance is a Perl command-line toolset and web dashboard for managing media across multiple filesystem mounts. It generates move plans, applies file migrations safely, and produces Sonarr/Plex reconciliation plans so media services continue to reference valid library paths.

The packaged distribution includes:

- `script/balance` — plan and execute media moves using explicitly configured media paths
- `script/balance_sonarr` — build and apply Sonarr reconciliation plans
- `script/balance_plex` — build and apply Plex reconciliation plans
- `script/balance_web` — optional web dashboard for plan/dry-run/apply workflows

## Installation

### From source

```bash
perl Makefile.PL
make
sudo make install
```

### Install runtime dependencies

The distribution requires Perl 5.042 or later and declares these prerequisites:

- `Mojolicious`
- `DBI`
- `DBD::SQLite`
- `File::ShareDir`
- `WebService::Plex`
- `LWP::UserAgent`
- `JSON::XS`
- `HTTP::Tiny`
- `JSON::PP`

## Usage

### Command-line workflow

Use `balance` to generate a move plan and optionally apply it:

```bash
balance --mount=/media --mount=/media2 --dry-run
balance --mount=/media --mount=/media2 --apply
```

Use `balance_sonarr` and `balance_plex` to generate and apply service reconcile plans:

```bash
balance_sonarr [options]
balance_sonarr apply [--report-file=FILE]
balance_plex [options]
balance_plex apply [--report-file=FILE]
```

### Web UI

The web interface is an optional dashboard for plan/dry-run/apply workflows. It is backed by SQLite and the job runner in the repository.

```bash
balance_web daemon
```

## Configuration

App::Balance stores its runtime integration configuration in the app's persistent config store and manages service settings through the web UI. Media mount selection is explicit and stored as configured `media_paths`, not discovered from legacy env vars.

Key configuration entrypoints:

- the web UI config page — persisted service integration and runtime settings
- `config/sonarr-path-map` — Sonarr path translation map
- `config/plex-path-map` — Plex path translation map

For mounts, configure media paths explicitly in the UI or pass `--mount=<path>` to `balance` rather than relying on deprecated `MEDIA_PATH_*` discovery.

## Development

This repository includes helper targets for local development.

Lint the code with:

```bash
make lint
```

Build the distribution tarball:

```bash
make cpan-build
```

## Running locally

The repository can be executed directly.

```bash
perl script/balance_web daemon
```

## Running with Docker

This repository includes a `Dockerfile` that builds `App::Balance` and also
installs:

- `WebService::Arr` from `slriv/perl-arrapi`
- `WebService::Plex` from `slriv/perl-plexapi`

Build the image from this repository root:

```bash
docker build -t balance-app .
```

Run the web UI and persist artifacts on the host:

```bash
docker run --rm \
  -p 3010:3010 \
  -v "$PWD/artifacts:/artifacts" \
  balance-app
```

The container defaults `BALANCE_ARTIFACT_ROOT=/artifacts` and starts:

```text
balance_web daemon -l http://0.0.0.0:3010
```

### Docker Compose (media mounts)

`docker-compose.yml` defines named volumes that bind host media folders into the
container at `/media/*`.

By default, the compose file uses these host paths (override any of them via
environment variables):

- `BALANCE_MUSIC_PATH` (default `/Volumes/music`)
- `BALANCE_TVSHOWS_PATH` (default `/Volumes/tvshows`)
- `BALANCE_MOVIES_PATH` (default `/Volumes/movies`)
- `BALANCE_BOOKS_PATH` (default `/Volumes/books`)
- `BALANCE_PHOTOS_PATH` (default `/Volumes/photos`)
- `BALANCE_DVR_PATH` (default `/Volumes/dvr`)
- `BALANCE_HOMEVIDEO_PATH` (default `/Volumes/homevideo`)
- `BALANCE_TVSHOWS_UHD_PATH` (default `/Volumes/tvshowsuhd`)
- `BALANCE_TVSHOWS2_PATH` (default `/Volumes/tvshows2`)
- `BALANCE_TVSHOWS3_PATH` (default `/Volumes/tvshows3`)
- `BALANCE_TVSHOWS4_PATH` (default `/Volumes/tvshows4`)
- `BALANCE_TVNAS2_PATH` (default `/Volumes/tvnas2`)
- `BALANCE_MOVIES_UHD_PATH` (default `/Volumes/moviesuhd`)

Start with compose:

```bash
docker compose up -d
```

If you run Docker on Colima, the Docker daemon is inside a Linux VM, so host
paths like `/Volumes/*` must be mounted into that VM first:

```bash
colima stop
colima start --mount /Volumes:w
docker compose up -d
```

If you change bind source paths, recreate volumes so `driver_opts.device`
changes are applied:

```bash
docker compose down -v
docker compose up -d
```

### Pin dependency branches/tags (optional)

You can pin `arrapi` / `plexapi` refs at build time:

```bash
docker build \
  --build-arg ARRAPI_REF=main \
  --build-arg PLEXAPI_REF=main \
  -t balance-app .
```

## Repository layout

- `script/` — executable entrypoints
- `lib/Balance/` — shared module implementation
- `config/` — path map examples
- `scripts/` — helper scripts
- `share/` — bundled shared data installed via `File::ShareDir`

## Support

Report issues and feature requests on GitHub:

<https://github.com/slriv/balance/issues>

## License

This distribution is released under the Perl license (Artistic License 2.0 or GNU General Public License v1.0+).
