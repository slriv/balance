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
      ->content_like(qr/Plan/i)
      ->content_like(qr/Dry-Run/i)
      ->content_like(qr/Scan/i)
      ->content_like(qr/Empty Trash/i)
      ->content_like(qr/Apply/i);
};

# --- POST /plex/plan ---

subtest 'POST /plex/plan creates a job and redirects' => sub {
    my $t = Test::Mojo->new('Balance::Web::App');
    $t->post_ok('/plex/plan')
      ->status_is(302)
      ->header_like(Location => qr{/jobs/plex-plan-});
    my $jobs  = $t->app->job_store->recent_jobs(limit => 5);
    my ($job) = grep { $_->{type} eq 'plex_plan' } @{$jobs};
    ok(defined $job, 'plex_plan job recorded in store');
};

# --- POST /plex/dry-run ---

subtest 'POST /plex/dry-run creates a job and redirects' => sub {
    my $t = Test::Mojo->new('Balance::Web::App');
    $t->post_ok('/plex/dry-run')
      ->status_is(302)
      ->header_like(Location => qr{/jobs/plex-dry-run-});
    my $jobs  = $t->app->job_store->recent_jobs(limit => 5);
    my ($job) = grep { $_->{type} eq 'plex_dry_run' } @{$jobs};
    ok(defined $job, 'plex_dry_run job recorded in store');
};

# --- POST /plex/apply ---

subtest 'POST /plex/apply creates a job and redirects' => sub {
    my $t = Test::Mojo->new('Balance::Web::App');
    $t->post_ok('/plex/apply')
      ->status_is(302)
      ->header_like(Location => qr{/jobs/plex-apply-});
    my $jobs  = $t->app->job_store->recent_jobs(limit => 5);
    my ($job) = grep { $_->{type} eq 'plex_apply' } @{$jobs};
    ok(defined $job, 'plex_apply job recorded in store');
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
