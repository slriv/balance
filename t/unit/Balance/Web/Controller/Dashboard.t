use v5.38;
use Test::More;
use Test::Mojo;
use Test::MockModule;
use File::Temp qw(tempdir);

# Use in-memory SQLite and temp dir for log files
local $ENV{BALANCE_JOB_DB}      = ':memory:';
local $ENV{BALANCE_JOB_LOG_DIR} = tempdir(CLEANUP => 1);

my $mock_runner = Test::MockModule->new('Balance::JobRunner');
$mock_runner->mock('start_job', sub { return });

use Balance::Web::App;

# --- GET / ---

subtest 'GET / returns 200' => sub {
    my $t = Test::Mojo->new('Balance::Web::App');
    $t->get_ok('/')->status_is(200)->content_like(qr/Dashboard/i);
};

subtest 'GET / contains navigation links' => sub {
    my $t = Test::Mojo->new('Balance::Web::App');
    $t->get_ok('/')
      ->element_exists('a[href="/sonarr"]')
      ->element_exists('a[href="/plex"]');
};

subtest 'GET / contains balance operation forms' => sub {
    my $t = Test::Mojo->new('Balance::Web::App');
        $t->get_ok('/')
            ->element_exists('form[action="/plan"]')
            ->element_exists('form[action="/dry-run"]')
            ->element_exists('form[action="/apply"]');
};

subtest 'POST /plan creates a balance_plan job and redirects' => sub {
    my $t = Test::Mojo->new('Balance::Web::App');
        $t->post_ok('/plan' => form => { threshold => 25, max_moves => 3 })
            ->status_is(302)
            ->header_like(Location => qr{/jobs/balance-plan-});
        my $jobs  = $t->app->job_store->recent_jobs(limit => 5);
        my ($job) = grep { $_->{type} eq 'balance_plan' } @{$jobs};
        ok(defined $job, 'balance_plan job recorded in store');
};

subtest 'POST /dry-run creates a balance_dry_run job and redirects' => sub {
    my $t = Test::Mojo->new('Balance::Web::App');
        $t->post_ok('/dry-run' => form => { threshold => 20, max_moves => 2 })
            ->status_is(302)
            ->header_like(Location => qr{/jobs/balance-dry-run-});
        my $jobs  = $t->app->job_store->recent_jobs(limit => 5);
        my ($job) = grep { $_->{type} eq 'balance_dry_run' } @{$jobs};
        ok(defined $job, 'balance_dry_run job recorded in store');
};

subtest 'POST /apply creates a balance_apply job and redirects' => sub {
    my $t = Test::Mojo->new('Balance::Web::App');
        $t->post_ok('/apply' => form => { threshold => 20, max_moves => 1 })
            ->status_is(302)
            ->header_like(Location => qr{/jobs/balance-apply-});
        my $jobs  = $t->app->job_store->recent_jobs(limit => 5);
        my ($job) = grep { $_->{type} eq 'balance_apply' } @{$jobs};
        ok(defined $job, 'balance_apply job recorded in store');
};

done_testing;
