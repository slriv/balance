# Project Guidelines

## Code Style
- Follow existing Perl style in `bin/*.pl` and `lib/Balance/*.pm`: `use strict; use warnings;`, small focused subs, clear `die` messages.
- Keep shell changes compatible with `bash` and existing helper conventions in `scripts/nas-helper.sh`.
- Prefer minimal, surgical edits; do not refactor unrelated files.

## Architecture
- Planner/apply entrypoint: `bin/balance_tv.pl`.
- Reconcile entrypoints: `bin/sonarr_reconcile.pl`, `bin/plex_reconcile.pl`.
- Shared modules live in `lib/Balance/`:
  - `Config.pm` for `.env` loading and service defaults
  - `Manifest.pm` for JSONL manifest records
  - `PathMap.pm` for NAS-to-service path translation
  - `Reconcile.pm` / `ReconcileApp.pm` for reconcile planning flow
- Container/runtime definitions are in `Dockerfile` and `docker-compose.yml`.

## Build and Test
- Prefer Make targets (single source of truth):
  - `make lint` (Perl and bash syntax checks)
  - `make run` (plan generation)
  - `make dry-run` (simulate apply)
  - `make apply` / `make apply-bg` (execute moves)
  - `make sonarr-plan` / `make plex-plan` (reconcile plans)
- For routine validation after code changes, run `make lint` first.

## Conventions
- Treat size math as KB-based unless code clearly states otherwise (`du -sk` / `df -k` assumptions).
- Preserve manifest JSONL compatibility and append-only behavior expected by reconcile tooling.
- Preserve path-map semantics (absolute paths, longest-prefix match behavior).
- Do not duplicate operational runbooks in new docs; link to existing docs instead:
  - `README.md` for workflow, configuration, and runbook
  - `Makefile` (`help`) for command reference
  - `config/*-path-map.example` for path-map format

## Safety and Workflow
- Respect branch protection workflow: do not push directly to `main`; use topic branches.
- When changing move/apply behavior, prefer plan or dry-run flows before apply flows.