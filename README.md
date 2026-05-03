# App::Balance

> [!CAUTION]
> **Work in progress.** Lots of churn, lots of untested code.

App::Balance plans and applies media folder rebalancing across mounts, then reconciles Sonarr and Plex to keep service library paths consistent.

## Synopsis


Or build from this repository:

```bash
make cpan-build
make test
sudo make install
```

Run the tools after installation:

```bash
balance --help
sonarr_reconcile.pl --help
plex_reconcile.pl --help
balance_web.pl --help
```

## Description

App::Balance is a Perl command-line toolset and web dashboard for managing media across multiple filesystem mounts. It generates move plans, applies file migrations safely, and produces Sonarr/Plex reconciliation plans so media services continue to reference valid library paths.

The packaged distribution includes:

- `bin/balance` — plan and execute media moves using explicitly configured media paths
- `bin/sonarr_reconcile.pl` — build and apply Sonarr reconciliation plans
- `bin/plex_reconcile.pl` — build and apply Plex reconciliation plans
- `bin/balance_web.pl` — optional web dashboard for plan/dry-run/apply workflows

## Installation

### From CPAN

```bash
cpanm App::Balance
```

### From source

```bash
perl Makefile.PL
make
make test
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

Use `sonarr_reconcile.pl` and `plex_reconcile.pl` to generate and apply service reconcile plans:

```bash
sonarr_reconcile.pl [options]
sonarr_reconcile.pl apply [--report-file=FILE]
plex_reconcile.pl [options]
plex_reconcile.pl apply [--report-file=FILE]
```

### Web UI

The web interface is an optional dashboard for plan/dry-run/apply workflows. It is backed by SQLite and the job runner in the repository.

```bash
balance_web.pl daemon
```

## Configuration

App::Balance stores its runtime integration configuration in the app's persistent config store and manages service settings through the web UI. Media mount selection is explicit and stored as configured `media_paths`, not discovered from legacy env vars.

Key configuration entrypoints:

- the web UI config page — persisted service integration and runtime settings
- `config/sonarr-path-map` — Sonarr path translation map
- `config/plex-path-map` — Plex path translation map

For mounts, configure media paths explicitly in the UI or pass `--mount=<path>` to `balance` rather than relying on deprecated `MEDIA_PATH_*` discovery.

## Development

This repository includes helper targets for local development and testing.

Run tests locally:

```bash
make test
make test-all
```

Lint the code with:

```bash
make lint
```

Build the distribution tarball:

```bash
make cpan-build
```

Package and verify with:

```bash
make cpan-test
```

## Running locally

The repository is intended to be executed directly rather than via a container runtime.

```bash
perl bin/balance_web.pl daemon
```

## Repository layout

- `bin/` — executable entrypoints
- `lib/Balance/` — shared module implementation
- `config/` — path map examples
- `scripts/` — helper scripts
- `t/` — test suite
- `share/` — bundled shared data installed via `File::ShareDir`

## Contributing

1. Create a topic branch
2. Make focused changes
3. Run `make lint` and `make test`
4. Open a pull request

## Support

Report issues and feature requests on GitHub:

<https://github.com/slriv/balance/issues>

## License

This distribution is released under the Perl license (Artistic License 2.0 or GNU General Public License v1.0+).
