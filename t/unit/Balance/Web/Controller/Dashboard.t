use v5.38;
use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);

# Use in-memory SQLite and temp dir for log files
local $ENV{BALANCE_JOB_DB}      = ':memory:';
local $ENV{BALANCE_JOB_LOG_DIR} = tempdir(CLEANUP => 1);

use Balance::Web::App;
my $t = Test::Mojo->new('Balance::Web::App');

# --- GET / ---

subtest 'GET / returns 200' => sub {
    $t->get_ok('/')->status_is(200)->content_like(qr/Dashboard/i);
};

subtest 'GET / contains navigation links' => sub {
    $t->get_ok('/')
      ->element_exists('a[href="/sonarr"]')
      ->element_exists('a[href="/plex"]');
};

done_testing;
