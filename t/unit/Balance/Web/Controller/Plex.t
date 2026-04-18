use v5.38;
use Test::More;
use Test::Mojo;
use Test::MockModule;
use File::Temp qw(tempdir);

local $ENV{BALANCE_JOB_DB}      = ':memory:';
local $ENV{BALANCE_JOB_LOG_DIR} = tempdir(CLEANUP => 1);

# Mock JobRunner so we don't actually fork processes.
my $mock_runner = Test::MockModule->new('Balance::JobRunner');
$mock_runner->mock('start_job', sub { return });

use Balance::Web::App;

# --- GET /plex ---

subtest 'GET /plex returns 200 with action buttons' => sub {
    my $t = Test::Mojo->new('Balance::Web::App');
    $t->get_ok('/plex')
      ->status_is(200)
      ->content_like(qr/Scan/i)
      ->content_like(qr/Empty Trash/i);
};

# --- POST /plex/scan ---

subtest 'POST /plex/scan creates a job and redirects' => sub {
    my $t = Test::Mojo->new('Balance::Web::App');
    $t->post_ok('/plex/scan')
      ->status_is(302)
      ->header_like(Location => qr{/jobs/plex-scan-});
    my $jobs  = $t->app->job_store->recent_jobs(limit => 5);
    my ($job) = grep { $_->{type} eq 'plex_scan' } @{$jobs};
    ok(defined $job, 'plex_scan job recorded in store');
};

# --- POST /plex/empty-trash ---

subtest 'POST /plex/empty-trash creates a job and redirects' => sub {
    my $t = Test::Mojo->new('Balance::Web::App');
    $t->post_ok('/plex/empty-trash')
      ->status_is(302)
      ->header_like(Location => qr{/jobs/plex-trash-});
    my $jobs  = $t->app->job_store->recent_jobs(limit => 5);
    my ($job) = grep { $_->{type} eq 'plex_empty_trash' } @{$jobs};
    ok(defined $job, 'plex_empty_trash job recorded in store');
};

# --- Conflict: second job while one is running ---

subtest 'POST /plex/scan returns 409 when a job is running' => sub {
    my $t = Test::Mojo->new('Balance::Web::App');
    $t->app->job_store->insert_job('running-plex-1', 'plex_scan');
    $t->app->job_store->update_job('running-plex-1', status => 'running');
    $t->post_ok('/plex/scan')->status_is(409);
};

done_testing;
