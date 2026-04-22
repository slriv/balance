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

# --- GET /sonarr ---

subtest 'GET /sonarr returns 200 with action buttons' => sub {
    my $t = Test::Mojo->new('Balance::Web::App');
    $t->get_ok('/sonarr')
      ->status_is(200)
      ->content_like(qr/Plan/i)
      ->content_like(qr/Dry-Run/i)
      ->content_like(qr/Audit/i)
      ->content_like(qr/Repair/i)
      ->content_like(qr/Apply/i);
};

# --- POST /sonarr/plan ---

subtest 'POST /sonarr/plan creates a job and redirects' => sub {
    my $t = Test::Mojo->new('Balance::Web::App');
    $t->post_ok('/sonarr/plan')
      ->status_is(302)
      ->header_like(Location => qr{/jobs/sonarr-plan-});
    my $jobs  = $t->app->job_store->recent_jobs(limit => 5);
    my ($job) = grep { $_->{type} eq 'sonarr_plan' } @{$jobs};
    ok(defined $job, 'sonarr_plan job recorded in store');
};

# --- POST /sonarr/dry-run ---

subtest 'POST /sonarr/dry-run creates a job and redirects' => sub {
    my $t = Test::Mojo->new('Balance::Web::App');
    $t->post_ok('/sonarr/dry-run')
      ->status_is(302)
      ->header_like(Location => qr{/jobs/sonarr-dry-run-});
    my $jobs  = $t->app->job_store->recent_jobs(limit => 5);
    my ($job) = grep { $_->{type} eq 'sonarr_dry_run' } @{$jobs};
    ok(defined $job, 'sonarr_dry_run job recorded in store');
};

# --- POST /sonarr/audit ---

subtest 'POST /sonarr/audit creates a job and redirects' => sub {
    my $t = Test::Mojo->new('Balance::Web::App');
    $t->post_ok('/sonarr/audit')
      ->status_is(302)
      ->header_like(Location => qr{/jobs/sonarr-audit-});
    my $jobs  = $t->app->job_store->recent_jobs(limit => 5);
    my ($job) = grep { $_->{type} eq 'sonarr_audit' } @{$jobs};
    ok(defined $job, 'sonarr_audit job recorded in store');
};

# --- POST /sonarr/apply ---

subtest 'POST /sonarr/apply creates a job and redirects' => sub {
    my $t = Test::Mojo->new('Balance::Web::App');
    $t->post_ok('/sonarr/apply')
      ->status_is(302)
      ->header_like(Location => qr{/jobs/sonarr-apply-});
};

# --- POST /sonarr/repair ---

subtest 'POST /sonarr/repair creates a job and redirects' => sub {
    my $t = Test::Mojo->new('Balance::Web::App');
    $t->post_ok('/sonarr/repair')
      ->status_is(302)
      ->header_like(Location => qr{/jobs/sonarr-repair-});
};

# --- Conflict: second job while one is running ---

subtest 'POST /sonarr/audit returns 409 when a job is running' => sub {
    my $t = Test::Mojo->new('Balance::Web::App');
    $t->app->job_store->insert_job('running-job-1', 'sonarr_audit');
    $t->app->job_store->update_job('running-job-1', status => 'running');
    $t->post_ok('/sonarr/audit')->status_is(409);
};

done_testing;
