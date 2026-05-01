# Adopting Perl v5.42 in Balance

## Current state

- All modules declare `use v5.38`; v5.42.2 is installed locally
- 5 of 15 modules already use the `class`/`field`/`method` OOP syntax: `Balance::WebClient`, `Balance::Plex`, `Balance::Sonarr`, `Balance::JobStore`, `Balance::JobRunner`
- 1 module still uses the old `bless` style: `Balance::ConfigStore`
- Every class file carries `use feature qw(class)` and `no warnings qw(experimental::class)` boilerplate
- Modules using `try`/`catch` carry a parallel `use feature qw(try)` + `no warnings 'experimental::try'` block

---

## What changed in 5.42

| Feature | Status |
| --- | --- |
| `class`/`field`/`method` | Still experimental — boilerplate stays |
| `try`/`catch` | **Stable** in 5.42, enabled by `use v5.42`, no feature flag needed |
| `:writer` field attribute | **New** in 5.42 — generates `set_$fieldname` mutators |
| `my method` + `->&` | **New** in 5.42 — lexical (private) methods |
| `any`/`all` keywords | **New** in 5.42, experimental (`keyword_any`/`keyword_all`) |
| `source::encoding` pragma | **New** in 5.42 — replaces `use utf8` |

---

## Step 1 — Bump version declarations and drop `try` boilerplate

`use v5.42` enables `try`/`catch` natively. The `use feature qw(try)` and
`no warnings 'experimental::try'` lines in every module become dead weight.

Files to update mechanically:

```bash
# Bump version
perl -pi -e 's/^use v5\.38;$/use v5.42;/' lib/Balance/*.pm lib/Balance/**/*.pm bin/*.pl balance_tv.pl

# Remove try feature/warning lines
perl -pi -e '/^use feature qw\(try\);$/d;
             /^use feature qw\(signatures try\);$/{s/use feature qw\(signatures try\);/use feature qw(signatures);/}
             /^no warnings qw\(experimental::try\);$/d;
             s/ experimental::try\b//g;
             s/qw\(\s*\)/qw()/g' lib/Balance/*.pm
```

`class` boilerplate (`use feature 'class'` / `no warnings 'experimental::class'`) stays until `class` graduates from experimental — do not remove it.

---

## Step 2 — Convert ConfigStore.pm to `class`

`Balance::ConfigStore` is the only remaining `bless`-based class:

```perl
package Balance::ConfigStore;
use v5.42;
use feature 'class';
no warnings 'experimental::class';  ## no critic (TestingAndDebugging::ProhibitNoWarnings)
use utf8;
use DBI ();

class Balance::ConfigStore {  ## no critic (Modules::RequireEndWithOne)
    field $db_path :param;
    field $_dbh;

    ADJUST {
        die "db_path required\n" unless length($db_path // '');
        $_dbh = DBI->connect("dbi:SQLite:$db_path", '', '', {
            RaiseError => 1, AutoCommit => 1,
        }) or die "Cannot open $db_path: $DBI::errstr\n";
        $_dbh->do(<<'SQL');
CREATE TABLE IF NOT EXISTS config (
    key TEXT PRIMARY KEY,
    value TEXT,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
)
SQL
    }

    method get($key) { ... }
    method get_all()  { ... }
    method set($key, $value) { ... }
    method set_bulk($values) { ... }
    method delete($key) { ... }
}
```

`:param` on `$db_path` means callers keep their existing `->new(db_path => $path)` syntax.

---

## Step 3 — Replace trivial accessor methods with `:reader`

Fields are private to their declaring class. Subclasses can only reach them via a method call. Any zero-body `method foo() { $foo }` pattern is a candidate for `:reader`:

```perl
# Before
field $base_url :param;
method base_url() { $base_url }

# After
field $base_url :param :reader;
```

Applies to `Balance::WebClient` (`$base_url`, `$_http`). Check `Balance::Sonarr`,
`Balance::Plex`, and `Balance::JobRunner` for the same pattern.

Use `:writer` (new in 5.42) when a field needs a setter too — it generates
`set_$fieldname` automatically. Nothing currently needs this, but it's the
right tool when a mutable field surfaces.

---

## Step 4 — Use `my method` for private implementation details

`my method` declares a lexically-scoped method — it cannot be called via
normal `->method` dispatch and is invisible outside the class body. Use it
for internal helpers that should never be overridden or called externally.

```perl
# Before — visible in the method table
method _init_db() { ... }

# After — truly private
my method _init_db() { ... }
# Called as:
$self->&_init_db();
```

Good candidates: `_init_db` in `Balance::JobStore`. Do **not** convert
`_auth_headers` or `_api_get` in `Balance::WebClient` — those are template
methods that subclasses intentionally override.

---

## Step 5 — Replace `use utf8` with `source::encoding`

`source::encoding 'utf8'` is equivalent to `use utf8` but its stricter
`'ascii'` variant (the v5.42 default) will catch mojibake earlier. Drop-in
replacement for all modules that currently have `use utf8`:

```perl
# Before
use utf8;

# After — identical behaviour, cleaner intent
use source::encoding 'utf8';
```

---

## Step 6 — Verify `## no critic` annotations

After Steps 1–5, audit remaining inline annotations:

- `## no critic (TestingAndDebugging::ProhibitNoWarnings)` — remove from any
  line where the `no warnings` itself was removed
- `## no critic (Modules::RequireEndWithOne)` — keep on `class` blocks until
  Perl::Critic ships a rule aware of the `class` keyword

---

## Recommended order

| # | Step | Risk | Ships alone? |
| --- | --- | --- | --- |
| 1 | Bump `use v5.42`, drop `try` boilerplate | Low — mechanical | Yes |
| 2 | Convert `ConfigStore.pm` to `class` | Medium — logic change | Yes |
| 3 | Apply `:reader` to accessor methods | Low | Yes |
| 4 | Convert private helpers to `my method` | Low | Yes |
| 5 | `source::encoding` swap | Trivial | Yes |

Run `make test` after each step.
