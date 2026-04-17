# Grand Plan: Balance Web Service + Audit + Test Suite

## TL;DR

Three interleaved workstreams:
1. Adopt modern Perl standards and a test suite across all modules
2. Add Sonarr disk audit & repair feature
3. Replace the Make/CLI operational interface with a Mojolicious web service + HTMX UI

All three inform each other: new modules are written to the new standard from the start; retrofitting existing modules to the standard happens in tandem with writing their tests.

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
| Weak refs | `use builtin 'weaken'; no warnings 'experimental::builtin'` | Pattern C only — needed for Mojo callback circular refs; Pattern A/B modules have no such scenarios |
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

### Pattern B — Native class (stateful, holds config or connection across calls)

Used by: `Sonarr`, `Plex`, `JobStore`, `JobRunner`.

```perl
use v5.38;
use feature qw(class try);
no warnings qw(experimental::class experimental::try);
use utf8;

class Balance::Sonarr {
    field $base_url :param;   # set via new(base_url => ...)
    field $api_key  :param;
    field $ua;                # private — not settable from outside

    ADJUST {                  # post-constructor validation
        die "base_url required\n" unless $base_url;
        $ua = HTTP::Tiny->new(timeout => 15);
    }

    method get_series() {     # $self implicit, never appears
        ...
    }
}
```

Key properties: `field` = lexically scoped instance variable; `method` = sub with implicit `$self`; `ADJUST` = post-constructor validation; `:param` = settable via `new()`; `:reader`/`:writer` for accessors; bare `field` is private. No `Exporter` — classes are consumed by instantiation, not import.

### Pattern C — Mojolicious controller (web layer only)

Used by: all `Web::Controller::*` modules. Subclass `Mojolicious::Controller`; follow Mojo conventions (`$c->render`, `$c->stash`, etc.). Does not use native `class`.

### Retrofit scope

All existing modules are fully retrofitted — this is not deferred:
- `Config`, `Core`, `Manifest`, `PathMap`, `Reconcile`, `ReconcileApp` → Pattern A (add pragmas, convert subs to signatures)
- `Sonarr`, `Plex` → Pattern B (convert to `class`; remove credential passing on every call; CLI runner moves entirely to `bin/` scripts)
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
      Config.t          Manifest.t       PathMap.t
      Core.t            Reconcile.t      FuzzyName.t
      DiskProbe.t       AuditSonarr.t    JobStore.t
      JobRunner.t       Sonarr.t         Plex.t
    Balance/Web/
      Controller/Dashboard.t  Controller/Jobs.t
      Controller/Sonarr.t     Controller/Plex.t
  integration/          # skipped unless BALANCE_INTEGRATION=1
    sonarr_live.t
    plex_live.t
```

**Conventions:**
- Each `.t` file covers one module; one `subtest` block per public subroutine
- HTTP-calling subs (`Sonarr`, `Plex`) are tested with `Test::MockModule` intercepting `Mojo::UserAgent`
- `JobStore` tests use SQLite `:memory:` — no disk state
- `DiskProbe` tests mock `opendir`/`-d` via `Test::MockModule` overriding the probed subs
- Integration tests guarded by `plan skip_all => '...' unless $ENV{BALANCE_INTEGRATION}`

**Makefile targets (the only Make targets that survive):**
- `make test` — `prove -Ilib -r t/unit/`
- `make test-all` — `prove -Ilib -r t/`
- `make lint` — Perl `-c` on all `.pm` and `.pl` files
- `make build` — `docker build`

---

## Full Module Map

### Existing modules — fully retrofitted (Pattern A or B) + tests added

| Module | Pattern | Retrofit changes | Key subs/methods to test |
|---|---|---|---|
| `lib/Balance/Config.pm` | A | `v5.38`, `signatures`, `try` | `load_env_file`, `service_defaults`, `redact_value` |
| `lib/Balance/Core.pm` | A | `v5.38`, `signatures`, `try` | `log_ts`, `dir_size_kb`, `fmt`, `pct_fmt` (`print_state` — no-op test only) |
| `lib/Balance/Manifest.pm` | A | `v5.38`, `signatures`, `try` | `append_manifest_record`, `read_manifest`, `successful_apply_records` |
| `lib/Balance/PathMap.pm` | A | `v5.38`, `signatures`, `try` | `load_path_map`, `translate_path` |
| `lib/Balance/Reconcile.pm` | A | `v5.38`, `signatures`, `try` | `build_plan`, `write_report` |
| `lib/Balance/ReconcileApp.pm` | A | `v5.38`, `signatures`, `try` | `run` |
| `lib/Balance/Sonarr.pm` | **B** | Convert to `class`; credentials in `field`; methods replace subs; `__DATA__` / bottom-of-file CLI dispatch block moves to the existing `bin/sonarr_reconcile.pl` (no new bin script created) | `get_series`, `update_series_path`, `rescan_series`, `resolve_series_id`, `apply_plan`, `audit`, `repair` |
| `lib/Balance/Plex.pm` | **B** | Convert to `class`; credentials in `field`; methods replace subs; `__DATA__` / bottom-of-file CLI dispatch block moves to the existing `bin/plex_reconcile.pl` (no new bin script created) | `list_libraries`, `scan_path`, `empty_trash`, `resolve_library_id`, `apply_plan` |

### New — Audit feature (Pattern A)

| Module | Responsibility | Key subs |
|---|---|---|
| `lib/Balance/FuzzyName.pm` | Pure string logic, no I/O | `normalize($name)` — applies in order: NFC Unicode normalization, strip trailing ` (YYYY)`, invert "Title, The/A/An" article form, lowercase, replace `.`/`_`/`-` with space, collapse whitespace; `matches($a, $b)` — `normalize($a) eq normalize($b)`. Algorithm is intentionally normalize-then-exact (no Levenshtein/trigrams) — a false positive match is more dangerous than a `missing` result for an operation that writes back to Sonarr. `FuzzyName.t` tests explicit input/output pairs for each normalization step and combined cases. |
| `lib/Balance/DiskProbe.pm` | Filesystem I/O only — operates on paths exactly as Sonarr/Plex report them; no translation. Sonarr and Plex container paths (e.g. `/tv`) are mounted at the same paths in `balance_web`, so paths from the API are directly `stat`-able. | `path_exists($path)`, `list_dir($path)`, `find_candidates(\@roots, $name)`, `dir_metadata($path)` → `{ season_dirs, episode_files, tvdb_id }`, `probe_service_roots($sonarr_roots, $plex_roots)` → per-root `{ path, service_accessible, balance_accessible }` — used by the setup probe UI |
| `lib/Balance/AuditSonarr.pm` | Audit orchestration — calls DiskProbe, builds report. No path translation: `series.path` from Sonarr API is used directly. | `audit_series($series, \@roots)`, `write_audit_report($path, $items)`, `read_audit_report($path)`. Per-series flow: (1) `path_exists(series.path)` — if true → `ok`; (2) `find_candidates(\@roots, series.title)` — fuzzy name search. Disambiguation when 2+ name-matched candidates: (a) exactly one has `dir_metadata.tvdb_id` matching `series.tvdbId` → `fixable` with `confidence: exact`; (b) season/episode counts differ significantly → `fixable` with `confidence: heuristic`; (c) inconclusive → `ambiguous`. Single-candidate match → `fixable` with `confidence: name_match`. |

**Note on mounts and path translation:** Sonarr and Plex each report paths as they appear *inside their own container* (e.g. `/tv/Breaking Bad`). Because `balance_web` mounts the same NAS volumes at the same container-internal paths, those paths are directly `stat`-able — no translation is needed and the reconcile path maps are not used by the audit feature at all.

**Note on first-run mount setup:** Before the first audit run, the user must ensure every volume root that Sonarr or Plex manages is mounted in the `balance_web` container at the same path. Missing mounts cause false `missing` results for entire volume roots. The setup probe (see `probe_service_roots`) surfaces this clearly.

**Mount probe (first-run / on-demand):** `DiskProbe.probe_service_roots` calls `GET /api/v3/rootfolder` (Sonarr) and `GET /library/sections` (Plex) to enumerate all configured root paths, then `stat`s each in balance's namespace. The Dashboard "Setup" view displays the result as a table — `path | Sonarr accessible | Plex accessible | balance accessible` — so any missing mount is identified precisely before any audit job runs.

**Audit result statuses per series:**
- `ok` — `series.path` exists on disk
- `missing` — `series.path` not found and no fuzzy candidates found
- `fixable` — unambiguous candidate found via fuzzy name search; includes `candidate_path` and `confidence` (`exact` = tvdbId confirmed, `heuristic` = metadata-ranked, `name_match` = single fuzzy match only)
- `ambiguous` — 2+ fuzzy candidates, metadata could not disambiguate; includes `candidates` list with per-candidate metadata; requires manual resolution

### New — Web service (Pattern B for JobStore/JobRunner; Pattern C for controllers)

| Module | Pattern | Responsibility |
|---|---|---|
| `lib/Balance/JobStore.pm` | **B** | SQLite CRUD for job history; `init_db`, `insert_job`, `update_job`, `get_job`, `recent_jobs`, `log_path` |
| `lib/Balance/JobRunner.pm` | **B** | Runs external commands via `Mojo::IOLoop::Stream` on a pipe; writes stdout/stderr to `/artifacts/jobs/<job_id>.log` and simultaneously pushes bytes to registered callbacks; `start_job`, `cancel_job`, `watch_job($job_id, $cb)`, `unwatch_job($job_id, $cb)` — in-memory watcher registry. On WebSocket connect: `Controller::Jobs` replays existing log file (handles reconnect/page refresh), registers watcher for live push, unregisters on close. No polling or inotify needed. |
| `lib/Balance/Web/App.pm` | Mojo app | Mojolicious application class; route registration, config loading, startup. **Auth: none — internal trusted network only. `# TODO: add HTTP Basic or token auth before any external exposure` must appear in `startup()` so it is not silently forgotten.** |
| `lib/Balance/Web/Controller/Dashboard.pm` | **C** | Volume state (via `Balance::Core`), recent job history |
| `lib/Balance/Web/Controller/Jobs.pm` | **C** | Start/cancel/stream jobs; WebSocket log tail |
| `lib/Balance/Web/Controller/Sonarr.pm` | **C** | Series list, plan, apply, audit, repair — each creates a job |
| `lib/Balance/Web/Controller/Plex.pm` | **C** | Library list, scan, empty trash — each creates a job |

---

## Implementation Phases

### Phase 0 — Standards & Scaffolding *(blocks everything)*

1. Create `t/` directory structure; add `Test::Exception`, `Test::MockModule` to Dockerfile CPAN installs
2. Update `Makefile` to new minimal form (`test`, `test-all`, `lint`, `build`). `lint` runs both `perl -c` (syntax) and `perlcritic --severity 4` (semantic — catches missing `use v5.38`, bareword filehandles, etc.); add `Perl::Critic` to Dockerfile CPAN installs.

### Phase 1 — Full retrofit of existing modules *(parallel per module)*

3. Retrofit `Config`, `Core`, `Manifest`, `Reconcile`, `ReconcileApp` → Pattern A (`v5.38`, `signatures`, `try`); write unit tests for each
4. Retrofit `PathMap` → Pattern A; write `t/unit/Balance/PathMap.t`
5. Retrofit `Sonarr` → Pattern B (convert to `class`; CLI runner moves to `bin/`); write `t/unit/Balance/Sonarr.t` with `Test::MockModule` on `HTTP::Tiny`
6. Retrofit `Plex` → Pattern B (convert to `class`; CLI runner moves to `bin/`); write `t/unit/Balance/Plex.t` with `Test::MockModule` on `HTTP::Tiny`

### Phase 2 — Audit feature *(depends on Phase 1 Steps 4–5)*

7. Create `lib/Balance/FuzzyName.pm` (Pattern A); write `t/unit/Balance/FuzzyName.t`
8. Create `lib/Balance/DiskProbe.pm` (Pattern A); write `t/unit/Balance/DiskProbe.t` (mock `stat`/`opendir`; mock HTTP responses for `probe_service_roots`)
9. Create `lib/Balance/AuditSonarr.pm` (Pattern A) *(depends on 7, 8)*; write `t/unit/Balance/AuditSonarr.t` — test `ok`/`missing`/`fixable`/`ambiguous` paths with mocked `DiskProbe`
10. Add `audit` and `repair` methods to `lib/Balance/Sonarr.pm`; extend `t/unit/Balance/Sonarr.t` *(depends on 9)*

### Phase 3 — Web service foundation *(depends on Phase 0)*

11. Add `Mojolicious`, `DBI`, `DBD::SQLite` to Dockerfile; create `public/` + `templates/layouts/`
12. Create `lib/Balance/JobStore.pm` (Pattern B); write `t/unit/Balance/JobStore.t` (in-memory SQLite); include `log_path` accessor test
13. Create `lib/Balance/JobRunner.pm` (Pattern B); uses `Mojo::IOLoop::Stream` on a pipe (not `Mojo::IOLoop::Subprocess`) to run external commands with streaming stdout/stderr; write `t/unit/Balance/JobRunner.t` — mock the stream callbacks, assert log file written and watchers notified
14. Create `lib/Balance/Web/App.pm` (Mojo app class) and `bin/balance_web.pl`

### Phase 4 — Web controllers + templates *(depends on Phase 3, parallel per controller)*

15. `Controller::Dashboard` + `templates/dashboard/` + test
16. `Controller::Jobs` (WebSocket log stream) + `templates/jobs/` + test
17. `Controller::Sonarr` + `templates/sonarr/` + test *(depends on Phase 2)*
18. `Controller::Plex` + `templates/plex/` + test

### Phase 5 — Container & compose wiring *(depends on Phases 3–4)*

19. Update `docker-compose.yml`: add `balance_web` service (port 8080, all TV volume mounts + artifacts + config); remove `sonarr_plan`, `plex_plan`, `sonarr_apply`, `plex_apply` standalone services
20. Update `Dockerfile`: add CPAN installs, copy `templates/`, `public/`, new entrypoint `balance_web`

---

## Files Affected

| File | Change |
|---|---|
| `Dockerfile` | Add CPAN deps, copy templates/public, new entrypoint |
| `docker-compose.yml` | Add `balance_web`; remove obsolete plan/apply services |
| `Makefile` | Strip to `test`, `test-all`, `lint`, `build` |
| `lib/Balance/PathMap.pm` | Add `reverse_translate_path`, `nas_roots` |
| `lib/Balance/Sonarr.pm` | Add `audit`, `repair` sub-commands |
| `lib/Balance/Common.pm` | **New** — standard preamble |
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
| `t/unit/Balance/*.t` (×11) | **New** |
| `t/unit/Balance/Web/Controller/*.t` (×4) | **New** |

---

## Verification

1. `make lint` — all `.pm` and `.pl` files pass `-c`
2. `make test` — all unit tests pass; >90% subroutine coverage
3. `docker compose up balance_web` → `http://localhost:8080` renders dashboard with volume state
4. Trigger Sonarr audit from UI → job appears, log streams live, JSON report written to `/artifacts/sonarr-audit-report.json`
5. Review report in UI, trigger repair → fixable series updated in Sonarr and rescanned
6. Trigger Plex plan + apply from UI → picks up corrected paths
7. `make test-all BALANCE_INTEGRATION=1` against running NAS — Sonarr/Plex API calls succeed

---

## Decisions

- **All modules retrofitted** — no deferred passes; standards are applied consistently across the entire codebase
- **Two module patterns**: Pattern A (procedural + Exporter) for stateless utilities; Pattern B (native `class`) for stateful service clients and job management; Pattern C (Mojolicious conventions) for web controllers
- **`Sonarr.pm` and `Plex.pm` become proper classes** — credentials passed once at construction, not on every call; CLI runner logic moves to `bin/` scripts
- **No SSH in DiskProbe** — web container mounts volumes directly
- **One path map, bidirectional** — `reverse_translate_path` replaces any proposed separate audit path map
- **Job concurrency**: one active job at a time enforced by `JobStore::insert_job` using `BEGIN IMMEDIATE` SQLite transaction — acquires write lock before the running-job check, preventing the TOCTOU race across Hypnotoad's multiple worker processes. `t/unit/Balance/JobStore.t` tests this by pre-inserting a `status='running'` row into in-memory SQLite and asserting that a subsequent `insert_job` call dies — no race simulation needed. Additionally, `balance_web` is documented to run with `workers => 1` in `hypnotoad.conf` (appropriate for a single-ops-at-a-time internal tool), providing a second layer of enforcement.
- **`nas-helper.sh`**: retired as an operational tool; kept in repo as undocumented break-glass escape hatch
- **`bin/balance_tv.pl`, `bin/sonarr_reconcile.pl`, `bin/plex_reconcile.pl`**: kept as CLI tools; invoked by `JobRunner` from the web service, not directly by users
- **Auth**: none — internal trusted network only
- **Frontend**: HTMX + Mojolicious server-side templates + Tailwind CSS (CDN); no build pipeline, no JS framework
- **Job state**: SQLite in `/artifacts/balance-jobs.db`; survives container restarts
