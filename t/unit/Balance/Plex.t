use v5.38;
use Test::More;
use Test::Exception;
use Test::MockModule;
use JSON::PP ();

use Balance::Plex qw(resolve_library_id build_plan defaults);

# Helper to build the Plex list_libraries() response shape
sub _libs {
    my @sections = @_;
    return { MediaContainer => { Directory => \@sections } };
}

# --- resolve_library_id ---

subtest 'resolve_library_id dies without libraries' => sub {
    dies_ok { resolve_library_id(path => '/mnt/tv', libraries => undef) }
        'dies on undef libraries';
};

subtest 'resolve_library_id returns undef for no match' => sub {
    my $libs = _libs({ key => '1', Location => { path => '/mnt/movies' } });
    is(resolve_library_id(path => '/mnt/tv/Show', libraries => $libs), undef, 'no match -> undef');
};

subtest 'resolve_library_id matches single-location library' => sub {
    my $libs = _libs(
        { key => '1', Location => { path => '/mnt/movies' } },
        { key => '2', Location => { path => '/mnt/tv' } },
    );
    is(resolve_library_id(path => '/mnt/tv/Show/S01', libraries => $libs), '2', 'matches tv library');
};

subtest 'resolve_library_id picks longest matching prefix' => sub {
    my $libs = _libs(
        { key => '1', Location => { path => '/mnt/tv' } },
        { key => '2', Location => { path => '/mnt/tv/anime' } },
    );
    is(
        resolve_library_id(path => '/mnt/tv/anime/Show/S01', libraries => $libs),
        '2',
        'longer prefix wins'
    );
};

subtest 'resolve_library_id handles multi-location library' => sub {
    my $libs = _libs(
        { key => '3', Location => [{ path => '/mnt/tv' }, { path => '/mnt/tv2' }] },
    );
    is(resolve_library_id(path => '/mnt/tv2/Show', libraries => $libs), '3', 'second location matches');
};

subtest 'resolve_library_id does not do partial dir name matches' => sub {
    my $libs = _libs({ key => '1', Location => { path => '/mnt/tv' } });
    is(resolve_library_id(path => '/mnt/tvseries/Show', libraries => $libs), undef, 'no partial match');
};

# --- _url_encode (via round-trip through scan_path arg building) ---
# Test the encoding rule directly by loading the internal sub

subtest '_url_encode encodes all non-safe characters including slashes' => sub {
    my $enc = Balance::Plex::_url_encode('/path/with spaces/and+plus');
    is($enc, '%2Fpath%2Fwith%20spaces%2Fand%2Bplus', 'slashes spaces and + all encoded per RFC3986');
};

subtest '_url_encode leaves safe chars (A-Za-z0-9 - _ . ~) untouched' => sub {
    my $enc = Balance::Plex::_url_encode('Show-Name_v1.0~ok');
    is($enc, 'Show-Name_v1.0~ok', 'safe chars unchanged');
};

# --- build_plan ---

subtest 'build_plan returns arrayref' => sub {
    my $items = build_plan(records => [], path_map => []);
    is_deeply($items, [], 'empty records -> empty plan');
};

# --- defaults ---

subtest 'defaults returns hashref with required keys' => sub {
    local $ENV{PLEX_BASE_URL} = 'http://plex:32400';
    local $ENV{PLEX_TOKEN}    = 'testtoken';
    my $d = defaults();
    ok(defined $d->{base_url},      'base_url present');
    ok(defined $d->{manifest_file}, 'manifest_file present');
    ok(defined $d->{path_map_file}, 'path_map_file present');
    ok(defined $d->{report_file},   'report_file present');
};

# --- Balance::Plex class construction ---

subtest 'new dies without base_url' => sub {
    dies_ok { Balance::Plex->new(token => 'tok') } 'dies without base_url';
};

subtest 'new dies without token' => sub {
    dies_ok { Balance::Plex->new(base_url => 'http://plex:32400') } 'dies without token';
};

subtest 'new dies on empty token' => sub {
    dies_ok { Balance::Plex->new(base_url => 'http://plex:32400', token => '') } 'dies on empty token';
};

# --- HTTP API methods (mocked) ---

my $mock_http = Test::MockModule->new('HTTP::Tiny');

subtest 'list_libraries returns parsed response' => sub {
    my $payload = { MediaContainer => { Directory =>
        { key => '1', title => 'TV', type => 'show', Location => { path => '/mnt/tv' } }
    } };
    $mock_http->mock('get', sub { return { success => 1, content => JSON::PP::encode_json($payload) }; });
    my $plex = Balance::Plex->new(base_url => 'http://plex:32400', token => 'tok');
    my $data = $plex->list_libraries();
    is($data->{MediaContainer}{Directory}{key}, '1', 'library key');
    $mock_http->unmock('get');
};

subtest 'list_libraries dies on API error' => sub {
    $mock_http->mock('get', sub { return { success => 0, status => 401, reason => 'Unauthorized' }; });
    my $plex = Balance::Plex->new(base_url => 'http://plex:32400', token => 'tok');
    dies_ok { $plex->list_libraries() } 'dies on API error';
    $mock_http->unmock('get');
};

subtest 'scan_path calls API and returns 1' => sub {
    $mock_http->mock('get', sub { return { success => 1, content => '' }; });
    my $plex = Balance::Plex->new(base_url => 'http://plex:32400', token => 'tok');
    is($plex->scan_path('2', '/mnt/tv/Show'), 1, 'returns 1');
    $mock_http->unmock('get');
};

subtest 'empty_trash calls API and returns 1' => sub {
    $mock_http->mock('put', sub { return { success => 1, content => '' }; });
    my $plex = Balance::Plex->new(base_url => 'http://plex:32400', token => 'tok');
    is($plex->empty_trash('2'), 1, 'returns 1');
    $mock_http->unmock('put');
};

done_testing;
