use v5.38;
use Test::More;
use Test::Exception;
use Test::MockModule;
use File::Temp qw(tempdir);
use JSON::PP ();

use Balance::AuditSonarr qw(audit_series write_audit_report read_audit_report);

my $tmp = tempdir(CLEANUP => 1);

my $mock_dp = Test::MockModule->new('Balance::DiskProbe');

# --- audit_series: ok ---

subtest 'audit_series: ok when path exists' => sub {
    $mock_dp->mock('path_exists', sub { 1 });
    my $s = { id => 1, title => 'Breaking Bad', path => '/tv/Breaking Bad', tvdbId => 81189 };
    my $r = audit_series($s, []);
    is($r->{status}, 'ok',            'status ok');
    is($r->{id},     1,               'id preserved');
    is($r->{title},  'Breaking Bad',  'title preserved');
    is($r->{path},   '/tv/Breaking Bad', 'path preserved');
    $mock_dp->unmock('path_exists');
};

# --- audit_series: missing ---

subtest 'audit_series: missing when path absent and no candidates' => sub {
    $mock_dp->mock('path_exists',      sub { 0 });
    $mock_dp->mock('find_candidates',  sub { [] });
    my $s = { id => 2, title => 'Lost', path => '/tv/Lost', tvdbId => 73739 };
    my $r = audit_series($s, []);
    is($r->{status}, 'missing', 'status missing');
    $mock_dp->unmock('path_exists');
    $mock_dp->unmock('find_candidates');
};

# --- audit_series: fixable/name_match ---

subtest 'audit_series: fixable name_match with single candidate' => sub {
    $mock_dp->mock('path_exists',     sub { 0 });
    $mock_dp->mock('find_candidates', sub { ['/tv2/Lost'] });
    my $s = { id => 3, title => 'Lost', path => '/tv/Lost', tvdbId => 73739 };
    my $r = audit_series($s, []);
    is($r->{status},         'fixable',     'status fixable');
    is($r->{confidence},     'name_match',  'confidence name_match');
    is($r->{candidate_path}, '/tv2/Lost',   'candidate_path set');
    $mock_dp->unmock('path_exists');
    $mock_dp->unmock('find_candidates');
};

# --- audit_series: fixable/exact (tvdbId disambiguation) ---

subtest 'audit_series: fixable exact when tvdbId matches one candidate' => sub {
    $mock_dp->mock('path_exists',     sub { 0 });
    $mock_dp->mock('find_candidates', sub { ['/tv/Show A', '/tv2/Show A'] });
    $mock_dp->mock('dir_metadata', sub($path) {
        return { tvdb_id => '99999' } if $path eq '/tv/Show A';
        return { tvdb_id => undef };
    });
    my $s = { id => 4, title => 'Show A', path => '/tv3/Show A', tvdbId => 99999 };
    my $r = audit_series($s, []);
    is($r->{status},         'fixable',   'status fixable');
    is($r->{confidence},     'exact',     'confidence exact');
    is($r->{candidate_path}, '/tv/Show A', 'correct candidate selected');
    $mock_dp->unmock('path_exists');
    $mock_dp->unmock('find_candidates');
    $mock_dp->unmock('dir_metadata');
};

# --- audit_series: ambiguous ---

subtest 'audit_series: ambiguous with multiple candidates and no disambig' => sub {
    $mock_dp->mock('path_exists',     sub { 0 });
    $mock_dp->mock('find_candidates', sub { ['/tv/Show B', '/tv2/Show B'] });
    $mock_dp->mock('dir_metadata',    sub { { tvdb_id => undef } });
    my $s = { id => 5, title => 'Show B', path => '/tv3/Show B', tvdbId => 11111 };
    my $r = audit_series($s, []);
    is($r->{status}, 'ambiguous', 'status ambiguous');
    is(scalar @{$r->{candidates}}, 2, 'two candidates listed');
    $mock_dp->unmock('path_exists');
    $mock_dp->unmock('find_candidates');
    $mock_dp->unmock('dir_metadata');
};

# --- audit_series: ambiguous when no tvdbId ---

subtest 'audit_series: ambiguous when tvdbId missing' => sub {
    $mock_dp->mock('path_exists',     sub { 0 });
    $mock_dp->mock('find_candidates', sub { ['/a/Show C', '/b/Show C'] });
    my $s = { id => 6, title => 'Show C', path => '/missing/Show C' };
    my $r = audit_series($s, []);
    is($r->{status}, 'ambiguous', 'status ambiguous without tvdbId');
    $mock_dp->unmock('path_exists');
    $mock_dp->unmock('find_candidates');
};

# --- write_audit_report / read_audit_report ---

subtest 'write and read audit report round-trip' => sub {
    my $report = "$tmp/audit.json";
    my @items = (
        { status => 'ok',      id => 1, title => 'Show One', path => '/tv/Show One' },
        { status => 'missing', id => 2, title => 'Show Two', path => '/tv/Show Two' },
    );
    ok(write_audit_report($report, \@items), 'write returns true');
    ok(-f $report, 'file created');

    my $read_items = read_audit_report($report);
    is(scalar @{$read_items}, 2, 'two items read back');
    is($read_items->[0]{status}, 'ok',      'first item status');
    is($read_items->[1]{title},  'Show Two', 'second item title');
};

subtest 'read_audit_report: dies on missing file' => sub {
    dies_ok { read_audit_report("$tmp/no-such-report.json") } 'dies on missing file';
};

done_testing;
