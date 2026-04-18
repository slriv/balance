# Grand Plan: Balance Web Service + Audit + Test Suite

## TL;DR

Three interleaved workstreams:
1. Adopt modern Perl standards and a test suite across all modules
2. Add Sonarr disk audit & repair feature
3. Replace the Make/CLI operational interface with a Mojolicious web service + HTMX UI

All three inform each other: new modules are written to the new standard from the start; retrofitting existing modules to the standard happens in tandem with writing their tests.

---

## Architecture

- **Makefile** = dev-only: `build`, `rebuild`, `build-test`, `test`, `test-all`, `lint`, `setup-git-hooks`. Nothing else.
- **Image** = portable artifact installable on any Docker host (NAS or elsewhere)
- **All operational interfaces** (reconcile, audit, apply) run inside the container, exposed via the web service and invoked by `JobRunner`
- **`nas-helper.sh`** = break-glass escape hatch only; not referenced by Makefile

---

## Perl Standards Adopted

All modules adopt a consistent standard preamble. There are **two canonical module patterns**; the right one is chosen based on whether the module holds state between calls.

### Shared preamble (all modules)

| Feature | Pragma | Notes |
|---|---|---|
| Version floor | `use v5.38` | Alpine 3.20 ships 5.38.2; unlocks all below |
| Subroutine signatures | `use feature 'signatures'` | Replaces `my (%args) = @_` in procedural subs; `method` already handles this in classes |
| Try/catch/finally | `use feature 'try'; no warnings 'experimental::try'` | Replaces `eval { ... }; if ($@) { ... }` everywhere |
| Native booleans | `use builtin qw(true false); no warnings 'experimental::builtin'` | Clarity in condition returns |
| Weak refs | `use builtin 'weaken'; no warnings 'experimental::builtin'` | Pattern C only — needed for Mojo callback circular refs |
| UTF-8 source | `use utf8` | Required for show name fuzzy matching |

**Not adopted:** Moose/Moo (overkill weight), `Readonly` (`use constant` sufficient), `Object::Pad` (native `class` supersedes it).

### Pattern A — Procedural package (stateless utilities)

Used by: `Config`, `Core`, `Manifest`, `PathMap`, `Reconcile`, `ReconcileApp`, `FuzzyName`, `DiskProbe`, `AuditSonarr`.

```perl
use v5.38;
use feature qw(signatures try);
no warnings qw(experimental::try);
use utf8;
use Exporter 'import';
our @EXPORT_OK = qw(foo bar);

sub foo($arg1, $arg2) { ... }
```

**Import convention — always explicit named imports; never `@EXPORT` (auto-push):**

```perl
# WRONG — pushes into caller namespace without consent
our @EXPORT = qw(foo bar);

# WRONG — noisy, non-idiomatic
Balance::Config::service_defaults('sonarr');

# RIGHT — caller declares exactly what it needs at the top of the file
use Balance::Config qw(service_defaults redact_value);
service_defaults('sonarr');
```

`@EXPORT_OK` (opt-in) is the mechanism; the caller's `use Module qw(...)` is the contract. This is the Perl community consensus — `perlcritic` flags `@EXPORT` use; `Exporter` docs recommend `@EXPORT_OK`. It gives the reader a complete picture of cross-module dependencies at the top of each file — the same clarity benefit as Java's `import` statements, without forcing stateless utilities into classes to achieve it. The two-pattern split lets us have Java's namespace explicitness on pure functions *and* proper encapsulated state on stateful modules, without Java's weakness of forcing everything into a class regardless of whether state is involved.

### Pattern B — Native class (stateful, holds config or connection across calls)

Used by: `WebClient` (HTTP base class), `Sonarr`, `Plex`, `JobStore`, `JobRunner`.

```perl
use v5.38;
use feature qw(class try);
no warnings qw(experimental::class experimental::try);
use utf8;

class Balance::WebClient {
    field $base_url :param;
    field $_http;

    ADJUST {
        die "base_url is required\n" unless length($base_url // '');
        $_http = HTTP::Tiny->new(timeout => 15);
    }

    method _api_get($path) { ... }
    method _auth_headers()  { {} }   # override in subclasses
}

class Balance::Sonarr :isa(Balance::WebClient) {
    field $api_key :param;

    ADJUST { die "api_key is required\n" unless length($api_key // ''); }

    method _auth_headers() {
        return { 'X-Api-Key' => $api_key, 'Accept' => 'application/json' };
    }

    method get_series() { ... }   # $self implicit, never appears
}
```

Key properties: `field` = lexically scoped instance variable; `method` = sub with implicit `$self`; `ADJUST` = post-constructor validation; `:param` = settable via `new()`; `:isa(Base)` = inheritance; bare `field` is private. No `Exporter` — classes are consumed by instantiation, not import.

### Pattern C — Mojolicious controller (web layer only)

Used by: all `Web::Controller::*` modules. Subclass `Mojolicious::Controller`; follow Mojo conventions (`$c->render`, `$c->stash`, etc.). Does not use native `class`.

### Retrofit scope

All existing modules are fully retrofitted — not deferred:
- `Config`, `Core`, `Manifest`, `PathMap`, `Reconcile`, `ReconcileApp` → Pattern A (add pragmas, convert subs to signatures; replace any `@EXPORT` lists with `@EXPORT_OK`; update all call sites to explicit `use Module qw(...)`)
- `Sonarr`, `Plex` → Pattern B (convert to `class`; credentials in `field`; CLI runner stays in `bin/` scripts)
- `bin/*.pl` entrypoints → adopt `v5.38`, `signatures`, `try`; no structural change

---

## Testing Infrastructure

**Framework:**
- `Test::More` — stdlib, core assertions
- `Test::Exception` — CPAN; tests that code `die`s correctly
- `Test::MockModule` — CPAN; mock HTTP and filesystem calls in unit tests
- `Test::Mojo` — bundled with Mojolicious; web controller integration tests

**Layout:**
```
t/
  unit/
    Balance/
      Config.t    Manifest.t    PathMap.t
      Core.t      Reconcile.t   FuzzyName.t
      DiskProbe.t AuditSonarr.t JobStore.t
      JobRunner.t Sonarr.t      Plex.t
      WebClient.t
    Balance/Web/Controller/
      Dashboard.t  Jobs.t  Sonarr.t  Plex.t
  integration/    # skipped unless BALANCE_INTEGRATION=1
    sonarr_live.t
    plex_live.t
```

**Conventions:**
- Each `.t` file covers one module; one `subtest` block per public subroutine
- HTTP-calling subs (`Sonarr`, `Plex`) tested with `Test::MockModule` intercepting `HTTP::Tiny`
- `JobStore` tests use SQLite `:memory:` — no disk state
- `DiskProbe` tests mock `opendir`/`-d` via `Test::MockModule`
- Integration tests guarded by `plan skip_all => '...' unless $ENV{BALANCE_INTEGRATION}`

---

## Full Module Map

### Existing modules — retrofitted + tests added

| Module | Pattern | Key subs/methods to test |
|---|---|---|
| `lib/Balance/Config.pm` | A | `load_env_file`, `service_defaults`, `redact_value` |
| `lib/Balance/Core.pm` | A | `log_ts`, `dir_size_kb`, `fmt`, `pct_fmt` |
| `lib/Balance/Manifest.pm` | A | `append_manifest_record`, `read_manifest`, `successful_apply_records` |
| `lib/Balance/PathMap.pm` | A | `load_path_map`, `translate_path`, `reverse_translate_path`, `nas_roots` |
| `lib/Balance/Reconcile.pm` | A | `build_plan`, `write_report` |
| `lib/Balance/ReconcileApp.pm` | A | `run` |
| `lib/Balance/WebClient.pm` | **B** | `base_url`, `_http` (cached), `_api_get($path)`, `_auth_headers()` (override in subclasses) |
| `lib/Balance/Sonarr.pm` | **B** (`:isa(WebClient)`) | `get_series`, `update_series_path`, `rescan_series`, `resolve_series_id`, `apply_plan`, `audit`, `repair` |
| `lib/Balance/Plex.pm` | **B** (`:isa(WebClient)`) | `list_libraries`, `scan_path`, `empty_trash`, `resolve_library_id`, `apply_plan` |

### New — Audit feature (Pattern A)

| Module | Responsibility |
|---|---|
| `lib/Balance/FuzzyName.pm` | Pure string logic: `normalize($name)`, `matches($a, $b)`. Normalize-then-exact (no Levenshtein) — a false positive is more dangerous than a `missing` result. |
| `lib/Balance/DiskProbe.pm` | Filesystem I/O: `path_exists`, `list_dir`, `find_candidates`, `dir_metadata`, `probe_service_roots`. Operates on paths exactly as Sonarr/Plex report them — no translation needed since `balance_web` mounts volumes at the same paths. |
| `lib/Balance/AuditSonarr.pm` | Audit orchestration: `audit_series`, `write_audit_report`, `read_audit_report`. Per-series flow: (1) `path_exists` → `ok`; (2) fuzzy search → `fixable` (single match) or `ambiguous` (2+ candidates); (3) no match → `missing`. |

**Audit result statuses:**
- `ok` — `series.path` exists on disk
- `missing` — path not found, no fuzzy candidates
- `fixable` — unambiguous candidate found; includes `candidate_path` and `confidence` (`exact` = tvdbId confirmed, `heuristic` = metadata-ranked, `name_match` = single fuzzy match)
- `ambiguous` — 2+ fuzzy candidates, metadata inconclusive; requires manual resolution

**Mount note:** `balance_web` mounts all NAS TV volumes at the same paths Sonarr/Plex use internally — so `series.path` from the API is directly `stat`-able. The Dashboard "Setup" view runs `probe_service_roots` to surface any missing mounts before the first audit.

### New — Web service

| Module | Pattern | Responsibility |
|---|---|---|
| `lib/Balance/JobStore.pm` | **B** | SQLite CRUD: `init_db`, `insert_job`, `update_job`, `get_job`, `recent_jobs`, `log_path` |
| `lib/Balance/JobRunner.pm` | **B** | Runs commands via `Mojo::IOLoop::Stream` on a pipe; streams stdout/stderr to log file and registered callbacks; `start_job`, `cancel_job`, `watch_job`, `unwatch_job` |
| `lib/Balance/Web/App.pm` | Mojo app | Route registration, config loading, startup. **Auth: none — internal network only. `# TODO: add HTTP Basic or token auth before external exposure` must appear in `startup()`.** |
| `lib/Balance/Web/Controller/Dashboard.pm` | **C** | Volume state, recent job history |
| `lib/Balance/Web/Controller/Jobs.pm` | **C** | Start/cancel/stream jobs; WebSocket log tail with log-file replay on reconnect |
| `lib/Balance/Web/Controller/Sonarr.pm` | **C** | Series list, plan, apply, audit, repair — each creates a job |
| `lib/Balance/Web/Controller/Plex.pm` | **C** | Library list, scan, empty trash — each creates a job |

---

## Implementation Phases

### Phase 0 — Standards & Scaffolding *(blocks everything)*

- [x] `Dockerfile`: simplified to lean Alpine (`perl coreutils bash rsync`); prod CPAN deps removed *(re-added in Phase 3)*
- [x] `Config.pm`: container-native default paths (`/artifacts/...`, `/config/...`)
- [x] `Sonarr.pm` / `Plex.pm`: `cli_main` exported; sub-command dispatch in `bin/` scripts
- [x] `nas-helper.sh`: all reconcile functions removed
- [x] `.env`: path vars removed; `Config.pm` defaults take over
- [x] **Revert `Makefile`**: stripped to `build`, `rebuild`, `build-test`, `test`, `test-all`, `lint`, `setup-git-hooks` only
- [x] **Revert `docker-compose.yml`**: `sonarr_reconcile` / `plex_reconcile` services removed
- [x] `t/` directory structure created; unit test stubs in place for all existing modules
- [x] `Test::Exception`, `Test::MockModule`, `Perl::Critic` in `Dockerfile.test`
- [x] `make lint` passes clean

### Phase 1 — Full retrofit of existing modules *(complete — 105 tests, all passing)*

- [x] `Config`, `Core`, `Manifest`, `Reconcile`, `ReconcileApp` → Pattern A + unit tests
- [x] `PathMap` → Pattern A + `PathMap.t` (add `reverse_translate_path`, `nas_roots`)
- [x] `Sonarr.pm` → Pattern B (`class :isa(Balance::WebClient)`) + `Sonarr.t` (mock `HTTP::Tiny`)
- [x] `Plex.pm` → Pattern B (same) + `Plex.t`
- [x] `Balance::WebClient` base class extracted; `WebClient.t` added

### Phase 2 — Audit feature *(depends on Phase 1 PathMap + Sonarr)*

- [ ] `FuzzyName.pm` + `FuzzyName.t`
- [ ] `DiskProbe.pm` + `DiskProbe.t` (mock `stat`/`opendir` + HTTP)
- [ ] `AuditSonarr.pm` + `AuditSonarr.t` (test all four status paths with mocked `DiskProbe`)
- [ ] Add `audit` + `repair` to `Sonarr.pm`; extend `Sonarr.t`

### Phase 3 — Web service foundation *(depends on Phase 0)*

- [ ] Add `Mojolicious`, `DBI`, `DBD::SQLite` to `Dockerfile`; create `public/` + `templates/layouts/`
- [ ] `JobStore.pm` + `JobStore.t` (in-memory SQLite; assert `BEGIN IMMEDIATE` blocks concurrent insert)
- [ ] `JobRunner.pm` (`Mojo::IOLoop::Stream` on pipe) + `JobRunner.t`
- [ ] `Web/App.pm` + `bin/balance_web.pl`

### Phase 4 — Web controllers + templates *(depends on Phase 3, parallel)*

- [ ] `Controller::Dashboard` + `templates/dashboard/` + test
- [ ] `Controller::Jobs` (WebSocket log stream, log-file replay) + `templates/jobs/` + test
- [ ] `Controller::Sonarr` + `templates/sonarr/` + test *(depends on Phase 2)*
- [ ] `Controller::Plex` + `templates/plex/` + test

### Phase 5 — Container & compose wiring *(depends on Phases 3–4)*

- [ ] `docker-compose.yml`: add `balance_web` service (port 8080, all TV volume mounts + `/artifacts` + `/config`)
- [ ] `Dockerfile`: add CPAN deps, copy `templates/` + `public/`, new entrypoint `balance_web`
- [ ] `git commit` everything

---

## Files Affected

| File | Change |
|---|---|
| `Dockerfile` | Add CPAN deps, copy templates/public, new entrypoint |
| `docker-compose.yml` | Add `balance_web`; remove obsolete reconcile services |
| `Makefile` | Strip to dev targets only |
| `lib/Balance/PathMap.pm` | Add `reverse_translate_path`, `nas_roots` |
| `lib/Balance/WebClient.pm` | **New** — shared HTTP base class |
| `lib/Balance/Sonarr.pm` | Convert to Pattern B (`:isa(Balance::WebClient)`); add `audit`, `repair` |
| `lib/Balance/Plex.pm` | Convert to Pattern B (`:isa(Balance::WebClient)`) |
| `lib/Balance/FuzzyName.pm` | **New** |
| `lib/Balance/DiskProbe.pm` | **New** |
| `lib/Balance/AuditSonarr.pm` | **New** |
| `lib/Balance/JobStore.pm` | **New** |
| `lib/Balance/JobRunner.pm` | **New** |
| `lib/Balance/Web/App.pm` | **New** |
| `lib/Balance/Web/Controller/Dashboard.pm` | **New** |
| `lib/Balance/Web/Controller/Jobs.pm` | **New** |
| `lib/Balance/Web/Controller/Sonarr.pm` | **New** |
| `lib/Balance/Web/Controller/Plex.pm` | **New** |
| `bin/balance_web.pl` | **New** |
| `templates/layouts/main.html.ep` | **New** |
| `templates/dashboard/index.html.ep` | **New** |
| `templates/jobs/show.html.ep` | **New** |
| `templates/sonarr/*.html.ep` | **New** |
| `templates/plex/*.html.ep` | **New** |
| `public/htmx.min.js` | **New** (vendored) |
| `t/unit/Balance/*.t` (×13, including `WebClient.t`) | **New** |
| `t/unit/Balance/Web/Controller/*.t` (×4) | **New** |

---

## Verification

1. `make lint` — all `.pm` and `.pl` files pass `-c` and perlcritic `--severity 4`
2. `make test` — all unit tests pass; >90% subroutine coverage
3. `docker compose up balance_web` → `http://localhost:8080` renders dashboard with volume state
4. Trigger Sonarr audit from UI → job appears, log streams live, JSON report written to `/artifacts/sonarr-audit-report.json`
5. Review report in UI, trigger repair → fixable series updated in Sonarr and rescanned
6. Trigger Plex plan + apply from UI → picks up corrected paths
7. `make test-all BALANCE_INTEGRATION=1` against running NAS — all API calls succeed

---

## Decisions

- **All modules retrofitted** — no deferred passes; standards applied consistently across the entire codebase
- **Two module patterns**: Pattern A (procedural + Exporter) for stateless utilities; Pattern B (native `class`) for stateful service clients and job management; Pattern C (Mojolicious conventions) for web controllers
- **`Sonarr.pm` and `Plex.pm` become proper classes** — credentials passed once at construction, not on every call
- **No SSH in DiskProbe** — `balance_web` container mounts volumes directly at the same paths
- **One path map, bidirectional** — `reverse_translate_path` replaces any separate audit path map
- **Job concurrency**: one active job at a time enforced by `JobStore::insert_job` using `BEGIN IMMEDIATE` SQLite transaction — prevents TOCTOU race across Hypnotoad workers. `balance_web` also runs with `workers => 1` in `hypnotoad.conf` as a second layer.
- **`nas-helper.sh`**: retired as an operational tool; kept in repo as break-glass escape hatch only
- **`bin/balance_tv.pl`, `bin/sonarr_reconcile.pl`, `bin/plex_reconcile.pl`**: kept as CLI tools; invoked by `JobRunner` from the web service
- **Auth**: none — internal trusted network only
- **Frontend**: HTMX + Mojolicious server-side templates + Tailwind CSS (CDN); no build pipeline, no JS framework
- **Job state**: SQLite in `/artifacts/balance-jobs.db`; survives container restarts
