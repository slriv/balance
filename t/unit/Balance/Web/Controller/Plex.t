use v5.38;
use Test::More;
use Test::Mojo;
use Test::MockModule;
use File::Temp qw(tempdir);
use File::Spec;

sub _test_app {
    my $dir = tempdir(CLEANUP => 1);
    my $db_path = File::Spec->catfile($dir, 'balance.db');
    my $log_dir = File::Spec->catdir($dir, 'jobs');
    mkdir $log_dir;

    my $t = Test::Mojo->new('Balance::Web::App');
    $t->app->config->{balance_job_db} = $db_path;
    $t->app->balance_config->set_bulk({
        balance_job_db      => $db_path,
        balance_job_log_dir => $log_dir,
        plex_url            => 'http://plex:32400',
        plex_token          => 'test-token',
    });
    return $t;
}

# Mock JobRunner so we don't actually fork processes.
my $mock_runner = Test::MockModule->new('Balance::JobRunner');
$mock_runner->mock('start_job', sub { return });

use Balance::Web::App;

# --- GET /plex ---

subtest 'GET /plex returns 200 with action buttons' => sub {
    my $t = _test_app();
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
    my $t = _test_app();
    $t->post_ok('/plex/plan')
      ->status_is(302)
      ->header_like(Location => qr{/jobs/plex-plan-});
    my $jobs  = $t->app->job_store->recent_jobs(limit => 5);
    my ($job) = grep { $_->{type} eq 'plex_plan' } @{$jobs};
    ok(defined $job, 'plex_plan job recorded in store');
};

# --- POST /plex/dry-run ---

subtest 'POST /plex/dry-run creates a job and redirects' => sub {
    my $t = _test_app();
    $t->post_ok('/plex/dry-run')
      ->status_is(302)
      ->header_like(Location => qr{/jobs/plex-dry-run-});
    my $jobs  = $t->app->job_store->recent_jobs(limit => 5);
    my ($job) = grep { $_->{type} eq 'plex_dry_run' } @{$jobs};
    ok(defined $job, 'plex_dry_run job recorded in store');
};

# --- POST /plex/apply ---

subtest 'POST /plex/apply creates a job and redirects' => sub {
    my $t = _test_app();
    $t->post_ok('/plex/apply')
      ->status_is(302)
      ->header_like(Location => qr{/jobs/plex-apply-});
    my $jobs  = $t->app->job_store->recent_jobs(limit => 5);
    my ($job) = grep { $_->{type} eq 'plex_apply' } @{$jobs};
    ok(defined $job, 'plex_apply job recorded in store');
};

# --- POST /plex/scan ---

subtest 'POST /plex/scan creates a job and redirects' => sub {
    my $t = _test_app();
    $t->post_ok('/plex/scan')
      ->status_is(302)
      ->header_like(Location => qr{/jobs/plex-scan-});
    my $jobs  = $t->app->job_store->recent_jobs(limit => 5);
    my ($job) = grep { $_->{type} eq 'plex_scan' } @{$jobs};
    ok(defined $job, 'plex_scan job recorded in store');
};

# --- POST /plex/empty-trash ---

subtest 'POST /plex/empty-trash creates a job and redirects' => sub {
    my $t = _test_app();
    $t->post_ok('/plex/empty-trash')
      ->status_is(302)
      ->header_like(Location => qr{/jobs/plex-trash-});
    my $jobs  = $t->app->job_store->recent_jobs(limit => 5);
    my ($job) = grep { $_->{type} eq 'plex_empty_trash' } @{$jobs};
    ok(defined $job, 'plex_empty_trash job recorded in store');
};

# --- Conflict: second job while one is running ---

subtest 'POST /plex/scan returns 409 when a job is running' => sub {
    my $t = _test_app();
    $t->app->job_store->insert_job('running-plex-1', 'plex_scan');
    $t->app->job_store->update_job('running-plex-1', status => 'running');
    $t->post_ok('/plex/scan')->status_is(409);
};

done_testing;
