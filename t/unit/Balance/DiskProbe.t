use v5.38;
use Test::More;
use Test::Exception;
use File::Temp qw(tempdir);

use Balance::DiskProbe qw(
    path_exists list_dir dir_metadata find_candidates probe_service_roots
);

my $tmp = tempdir(CLEANUP => 1);

# --- path_exists ---

subtest 'path_exists: existing directory' => sub {
    ok(path_exists($tmp), 'tempdir exists');
};

subtest 'path_exists: non-existent path' => sub {
    ok(!path_exists("$tmp/no-such-dir"), 'missing path returns false');
};

subtest 'path_exists: regular file returns false' => sub {
    my $f = "$tmp/file.txt";
    open my $fh, '>', $f; close $fh;
    ok(!path_exists($f), 'file returns false');
};

# --- list_dir ---

subtest 'list_dir: returns entries excluding . and ..' => sub {
    my $d = "$tmp/list_test";
    mkdir $d;
    mkdir "$d/Show A";
    mkdir "$d/Show B";
    open my $fh, '>', "$d/notes.txt"; close $fh;
    my $entries = list_dir($d);
    is(scalar @{$entries}, 3, 'three entries');
    my %h = map { $_ => 1 } @{$entries};
    ok($h{'Show A'},   'Show A present');
    ok($h{'Show B'},   'Show B present');
    ok($h{'notes.txt'}, 'notes.txt present');
};

subtest 'list_dir: non-existent path returns empty arrayref' => sub {
    my $entries = list_dir("$tmp/nope");
    is_deeply($entries, [], 'empty arrayref');
};

# --- dir_metadata ---

subtest 'dir_metadata: counts season dirs' => sub {
    my $show = "$tmp/meta_show";
    mkdir $show;
    mkdir "$show/Season 01";
    mkdir "$show/Season 02";
    mkdir "$show/Specials";   # not a season dir
    my $m = dir_metadata($show);
    is($m->{season_dirs}, 2, 'two season dirs');
};

subtest 'dir_metadata: counts episode files in season dirs' => sub {
    my $show = "$tmp/meta_eps";
    mkdir $show;
    mkdir "$show/Season 01";
    for my $f (qw(ep1.mkv ep2.mkv ep3.mp4 notes.txt)) {
        open my $fh, '>', "$show/Season 01/$f"; close $fh;
    }
    my $m = dir_metadata($show);
    is($m->{episode_files}, 3, 'three video files counted');
};

subtest 'dir_metadata: extracts tvdb_id from folder name' => sub {
    my $show = "$tmp/My Show {tvdb-12345}";
    mkdir $show;
    my $m = dir_metadata($show);
    is($m->{tvdb_id}, '12345', 'tvdb_id extracted');
};

subtest 'dir_metadata: no tvdb_id when absent' => sub {
    my $show = "$tmp/Plain Show";
    mkdir $show;
    my $m = dir_metadata($show);
    ok(!defined $m->{tvdb_id}, 'tvdb_id undef');
};

# --- find_candidates ---

subtest 'find_candidates: finds exact (normalized) match' => sub {
    my $root = "$tmp/find_root1";
    mkdir $root;
    mkdir "$root/Breaking Bad";
    mkdir "$root/Better Call Saul";
    my $candidates = find_candidates([$root], 'Breaking Bad');
    is(scalar @{$candidates}, 1, 'one candidate');
    is($candidates->[0], "$root/Breaking Bad", 'correct path');
};

subtest 'find_candidates: matches after normalization (year, case)' => sub {
    my $root = "$tmp/find_root2";
    mkdir $root;
    mkdir "$root/Lost";
    my $candidates = find_candidates([$root], 'Lost (2004)');
    is(scalar @{$candidates}, 1, 'found via year-stripped title');
};

subtest 'find_candidates: returns empty for no match' => sub {
    my $root = "$tmp/find_root3";
    mkdir $root;
    mkdir "$root/Unrelated Show";
    my $candidates = find_candidates([$root], 'Completely Different');
    is(scalar @{$candidates}, 0, 'no candidates');
};

subtest 'find_candidates: searches across multiple roots' => sub {
    my $r1 = "$tmp/multi_root1";
    my $r2 = "$tmp/multi_root2";
    mkdir $r1; mkdir $r2;
    mkdir "$r1/Show A";
    mkdir "$r2/Show A";
    my $candidates = find_candidates([$r1, $r2], 'Show A');
    is(scalar @{$candidates}, 2, 'found in both roots');
};

# --- probe_service_roots ---

subtest 'probe_service_roots: marks accessible paths' => sub {
    my $accessible = "$tmp/accessible_root";
    mkdir $accessible;
    my $results = probe_service_roots([$accessible], []);
    is(scalar @{$results}, 1, 'one result');
    is($results->[0]{path},               $accessible, 'path correct');
    is($results->[0]{service},            'sonarr',    'service correct');
    is($results->[0]{balance_accessible}, 1,           'accessible');
};

subtest 'probe_service_roots: marks inaccessible paths' => sub {
    my $missing = "$tmp/no_such_root";
    my $results = probe_service_roots([], [$missing]);
    is($results->[0]{balance_accessible}, 0, 'inaccessible');
    is($results->[0]{service},            'plex', 'plex service');
};

subtest 'probe_service_roots: handles empty lists' => sub {
    my $results = probe_service_roots([], []);
    is_deeply($results, [], 'empty input -> empty output');
};

done_testing;
