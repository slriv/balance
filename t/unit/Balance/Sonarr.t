use v5.38;
use Test::More;
use Test::Exception;
use Test::MockModule;
use JSON::PP ();

use Balance::Sonarr qw(resolve_series_id build_plan defaults);

# --- resolve_series_id ---
# This is pure logic with no I/O, so it's the best candidate for unit testing.

my @series = (
    { id => 1, path => '/mnt/tv/Show A' },
    { id => 2, path => '/mnt/tv/Show B' },
    { id => 3, path => '/mnt/tv/Show AB' },  # longer name, should not shadow Show A
);

subtest 'resolve_series_id dies without series' => sub {
    dies_ok { resolve_series_id(path => '/mnt/tv/Show A', series => undef) } 'dies on undef series';
};

subtest 'resolve_series_id returns undef for no match' => sub {
    is(resolve_series_id(path => '/mnt/other/path', series => \@series), undef, 'no match -> undef');
};

subtest 'resolve_series_id exact path match' => sub {
    is(resolve_series_id(path => '/mnt/tv/Show A', series => \@series), 1, 'exact match');
};

subtest 'resolve_series_id matches subdirectory path' => sub {
    is(resolve_series_id(path => '/mnt/tv/Show B/Season 01', series => \@series), 2, 'subdir match');
};

subtest 'resolve_series_id does not match partial directory name' => sub {
    # /mnt/tv/Show AB should match series 3, not series 1 (/mnt/tv/Show A)
    is(resolve_series_id(path => '/mnt/tv/Show AB', series => \@series), 3, 'no partial dir match');
};

subtest 'resolve_series_id picks longest matching prefix' => sub {
    my @overlapping = (
        { id => 10, path => '/mnt/tv' },
        { id => 11, path => '/mnt/tv/Deep/Show' },
    );
    is(
        resolve_series_id(path => '/mnt/tv/Deep/Show/S01', series => \@overlapping),
        11,
        'longer prefix wins'
    );
};

subtest 'resolve_series_id handles trailing slash in series path' => sub {
    my @with_slash = (
        { id => 20, path => '/mnt/tv/Slashy/' },
    );
    is(resolve_series_id(path => '/mnt/tv/Slashy', series => \@with_slash), 20, 'trailing slash stripped');
};

# --- build_plan (delegates to Balance::Reconcile) ---

subtest 'build_plan returns arrayref' => sub {
    my $items = build_plan(records => [], path_map => []);
    is_deeply($items, [], 'empty records -> empty plan');
};

# --- defaults ---

subtest 'defaults returns hashref with required keys' => sub {
    local $ENV{SONARR_BASE_URL} = 'http://sonarr:8989';
    local $ENV{SONARR_API_KEY}  = 'testkey';
    my $d = defaults();
    ok(defined $d->{base_url},        'base_url present');
    ok(defined $d->{manifest_file},   'manifest_file present');
    ok(defined $d->{path_map_file},   'path_map_file present');
    ok(defined $d->{report_file},     'report_file present');
};

# --- Balance::Sonarr class construction ---

subtest 'new dies without base_url' => sub {
    dies_ok { Balance::Sonarr->new(api_key => 'k') } 'dies without base_url';
};

subtest 'new dies without api_key' => sub {
    dies_ok { Balance::Sonarr->new(base_url => 'http://sonarr:8989') } 'dies without api_key';
};

subtest 'new dies on empty base_url' => sub {
    dies_ok { Balance::Sonarr->new(base_url => '', api_key => 'k') } 'dies on empty base_url';
};

# --- HTTP API methods (mocked) ---

my $mock_http = Test::MockModule->new('HTTP::Tiny');

subtest 'get_series returns parsed list' => sub {
    my $payload = [{ id => 1, title => 'Show A', path => '/mnt/tv/Show A', sortTitle => 'show a' }];
    $mock_http->mock('get', sub { return { success => 1, content => JSON::PP::encode_json($payload) }; });
    my $sonarr = Balance::Sonarr->new(base_url => 'http://sonarr:8989', api_key => 'testkey');
    my $list = $sonarr->get_series();
    is(scalar @$list, 1, 'one series');
    is($list->[0]{id}, 1, 'series id');
    $mock_http->unmock('get');
};

subtest 'get_series dies on API error' => sub {
    $mock_http->mock('get', sub { return { success => 0, status => 503, reason => 'Unavailable' }; });
    my $sonarr = Balance::Sonarr->new(base_url => 'http://sonarr:8989', api_key => 'testkey');
    dies_ok { $sonarr->get_series() } 'dies on API error';
    $mock_http->unmock('get');
};

subtest 'rescan_series posts command and returns response' => sub {
    my $resp = { id => 42, status => 'queued' };
    $mock_http->mock('post', sub { return { success => 1, content => JSON::PP::encode_json($resp) }; });
    my $sonarr = Balance::Sonarr->new(base_url => 'http://sonarr:8989', api_key => 'testkey');
    my $r = $sonarr->rescan_series(1);
    is($r->{status}, 'queued', 'command queued');
    $mock_http->unmock('post');
};

subtest 'rescan_series dies on API error' => sub {
    $mock_http->mock('post', sub { return { success => 0, status => 500, reason => 'Error' }; });
    my $sonarr = Balance::Sonarr->new(base_url => 'http://sonarr:8989', api_key => 'testkey');
    dies_ok { $sonarr->rescan_series(1) } 'dies on API error';
    $mock_http->unmock('post');
};

done_testing;
