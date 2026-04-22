use v5.38;
use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use File::Spec;

# Test configuration controller
# Note: Persistence testing is done in Balance::ConfigStore.t

my $tempdir = tempdir(CLEANUP => 1);
my $db_path = File::Spec->catfile($tempdir, 'test.db');
$ENV{BALANCE_JOB_DB} = $db_path;

subtest 'Config page displays form' => sub {
    my $t = Test::Mojo->new('Balance::Web::App');
    
    $t->get_ok('/config')
        ->status_is(200)
        ->content_like(qr/Configuration/i)
        ->content_like(qr/Mount Paths/i)
        ->content_like(qr/Sonarr/i)
        ->content_like(qr/Plex/i)
        ->element_exists('input[name="tv_path_1"]')
        ->element_exists('input[name="sonarr_url"]')
        ->element_exists('input[name="plex_url"]');
};

subtest 'Config form shows default values from environment' => sub {
    local $ENV{TV_PATH_1} = '/test/tv1';
    local $ENV{SONARR_BASE_URL} = 'http://sonarr:8989';
    
    my $t = Test::Mojo->new('Balance::Web::App');
    
    $t->get_ok('/config')
        ->status_is(200)
        ->element_exists('input[name="tv_path_1"][value="/test/tv1"]')
        ->element_exists('input[name="sonarr_url"][value="http://sonarr:8989"]');
};

subtest 'Config update endpoint returns JSON success' => sub {
    my $t = Test::Mojo->new('Balance::Web::App');
    
    $t->post_ok('/config/update', json => {
        tv_path_1        => '/new/tv1',
        tv_path_2        => '/new/tv2',
        tv_path_3        => '/new/tv3',
        tv_path_4        => '/new/tv4',
        sonarr_url       => 'http://new-sonarr:8989',
        sonarr_api_key   => 'new-key',
        plex_url         => 'http://new-plex:32400',
        plex_token       => 'new-token',
        plex_library_ids => '1,2,3',
    })
        ->status_is(200)
        ->json_has('/success')
        ->json_has('/message')
        ->json_like('/message', qr/updated/i);
};

done_testing();
