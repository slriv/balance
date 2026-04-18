use v5.38;
use Test::More;
use Test::Exception;
use Test::MockModule;
use JSON::PP ();

use Balance::WebClient;

# --- construction ---

subtest 'new requires base_url' => sub {
    dies_ok { Balance::WebClient->new() } 'dies without base_url';
};

subtest 'new dies on empty base_url' => sub {
    dies_ok { Balance::WebClient->new(base_url => '') } 'dies on empty base_url';
};

subtest 'new succeeds with base_url' => sub {
    my $wc = Balance::WebClient->new(base_url => 'http://host:8080');
    ok(defined $wc, 'object created');
    is($wc->base_url, 'http://host:8080', 'base_url accessor');
};

# --- _api_get (default _auth_headers returns empty hashref) ---

my $mock_http = Test::MockModule->new('HTTP::Tiny');

subtest '_api_get calls HTTP::Tiny get with correct URL' => sub {
    my ($got_url, $got_opts);
    $mock_http->mock('get', sub { (undef, $got_url, $got_opts) = @_; return { success => 1, content => '{}' }; });

    my $wc = Balance::WebClient->new(base_url => 'http://host:9090');
    $wc->_api_get('/some/path');

    is($got_url, 'http://host:9090/some/path', 'URL composed correctly');
    is_deeply($got_opts->{headers}, {}, 'default auth headers empty');
    $mock_http->unmock('get');
};

subtest '_http accessor returns cached HTTP::Tiny instance' => sub {
    my $wc = Balance::WebClient->new(base_url => 'http://host:9090');
    my $h1 = $wc->_http;
    my $h2 = $wc->_http;
    is($h1, $h2, 'same instance returned on each call');
};

done_testing;
