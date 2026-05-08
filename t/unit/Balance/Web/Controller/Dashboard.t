use v5.38;
no warnings 'once';
use Test::More;
use Test::Mojo;
use Test::MockModule;
use Balance::Config ();
use File::Spec;
use File::Temp qw(tempdir);

use Balance::Web::App;

sub _test_app {
    my $dir = tempdir(CLEANUP => 1);
    my $db_path = File::Spec->catfile($dir, 'balance.db');
    my $log_dir = File::Spec->catdir($dir, 'jobs');
    my $artifact_root = File::Spec->catdir($dir, 'artifacts');
    mkdir $log_dir;
    mkdir $artifact_root;

    my $t = Test::Mojo->new('Balance::Web::App');
    $t->app->config->{balance_job_db} = $db_path;
    $t->app->balance_config->set_bulk({
        artifact_root        => $artifact_root,
        balance_job_db       => $db_path,
        balance_job_log_dir  => $log_dir,
    });
    $t->app->balance_config->set_media_paths([
        { path => '/tmp/media1', label => 'Media 1' },
        { path => '/tmp/media2', label => 'Media 2' },
    ]);
    return $t;
}

sub _write_saved_plan ($t, $name = 'balance-plan-20260507-120000.sh') {
    my $path = File::Spec->catfile($t->app->balance_config->artifact_root, $name);
    open my $fh, '>', $path or die "write $path: $!";
    print {$fh} "#!/usr/bin/env bash\nset -euo pipefail\n\n# Example Show (1M)\nrsync -avP --remove-source-files '/tmp/media1/Example Show/' '/tmp/media2/Example Show'\n";
    close $fh;
    return $path;
}

my $mock_runner = Test::MockModule->new('Balance::JobRunner');
my @start_job_calls;
$mock_runner->mock('start_job', sub {
    my ($self, @args) = @_;
    push @start_job_calls, [@args];
    return;
});

subtest 'GET / returns 200' => sub {
    my $t = _test_app();
    $t->get_ok('/')
      ->status_is(200)
      ->content_like(qr/Dashboard/i)
      ->content_like(qr/Last Updated/i);
};

subtest 'GET / contains navigation links' => sub {
    my $t = _test_app();
    $t->get_ok('/')
      ->element_exists('a[href="/sonarr"]')
      ->element_exists('a[href="/plex"]');
};

subtest 'GET / contains unified balance workflow form' => sub {
    my $t = _test_app();
    my $plan_path = _write_saved_plan($t);

    $t->get_ok('/')
      ->status_is(200)
      ->element_exists('form#balance-operations-form')
      ->element_exists('form#balance-operations-form input[name="threshold"]')
      ->element_exists('form#balance-operations-form input[name="max_size"]')
      ->element_exists('form#balance-operations-form input[name="max_moves"]')
      ->element_exists('form#balance-operations-form select[name="empty_mount"]')
      ->element_exists('form#balance-operations-form input[name="plan_output_file"]')
      ->element_exists('form#balance-operations-form input[name="plan_log_file"]')
      ->element_exists('form#balance-operations-form input[name="apply_log_file"]')
      ->element_exists('form#balance-operations-form input[name="manifest_file"]')
      ->element_exists('form#balance-operations-form input[name="mount[]"]')
      ->element_exists('form#balance-operations-form select[name="selected_plan_file"]')
      ->element_exists(qq{option[value="$plan_path"]})
      ->element_exists('button[formaction="/plan"]')
      ->element_exists('button[formaction="/dry-run"][disabled]')
      ->element_exists('button[formaction="/apply"][disabled]')
      ->content_like(qr/Run Selected Plan \(Dry-Run\)/)
      ->content_like(qr/Run Selected Plan \(Apply\)/);
};

subtest 'GET / returns placeholder volume state and schedules background refresh when cache missing' => sub {
    my $t = _test_app();
    my $cache_file = $t->app->balance_config->dashboard_volume_cache_file;
    my $mock_dashboard = Test::MockModule->new('Balance::Web::Controller::Dashboard');
    my @scheduled;
    my $dir_size_calls = 0;

    $mock_dashboard->mock('_schedule_volume_refresh', sub ($c, $path, $mounts) {
        push @scheduled, {
            cache_path => $path,
            mounts     => [@{$mounts}],
        };
        return;
    });
    $mock_dashboard->mock('dir_size_kb', sub ($mount) {
        $dir_size_calls++;
        return $mount eq '/tmp/media1' ? 1024 : 2048;
    });

    $t->get_ok('/')
      ->status_is(200)
      ->content_like(qr/Refreshing volume sizes in the background/i)
      ->content_like(qr/Pending background refresh/i)
      ->content_like(qr/balance-dashboard-form-state/i);

    is($dir_size_calls, 0, 'request does not compute mount sizes inline');
    ok(@scheduled, 'background refresh was scheduled');
    is($scheduled[0]{cache_path}, $cache_file, 'background refresh uses configured cache path');
    is_deeply($scheduled[0]{mounts}, ['/tmp/media1', '/tmp/media2'], 'all mounts are queued for refresh');
    ok(!-f $cache_file, 'cache file is not written until background refresh completes');
};

subtest 'POST /plan creates a balance_plan job and redirects' => sub {
    my $t = _test_app();
    @start_job_calls = ();

    my $custom_plan = File::Spec->catfile($t->app->balance_config->artifact_root, 'custom-plan.sh');
    my $custom_log = File::Spec->catfile($t->app->balance_config->artifact_root, 'custom-plan.log');

    $t->post_ok('/plan' => form => {
        threshold        => 25,
        max_size         => 50,
        max_moves        => 3,
        empty_mount      => '/tmp/media1',
        verbose          => 1,
        plan_output_file => $custom_plan,
        plan_log_file    => $custom_log,
    })
      ->status_is(302)
      ->header_like(Location => qr{/jobs/balance-plan-});

    my $jobs = $t->app->job_store->recent_jobs(limit => 5);
    my ($job) = grep { $_->{type} eq 'balance_plan' } @{$jobs};
    ok(defined $job, 'balance_plan job recorded in store');

    my $call = $start_job_calls[-1];
    ok($call, 'job runner invoked');
    is($call->[1], $^X, 'plan job runs via current perl interpreter');
    like($call->[2], qr{/script/balance\z}, 'plan job resolves bundled balance script path');
    ok(grep($_ eq '--threshold=25', @{$call}), 'plan job forwards threshold');
    ok(grep($_ eq '--max-size=50', @{$call}), 'plan job forwards max-size');
    ok(grep($_ eq '--max-moves=3', @{$call}), 'plan job forwards max-moves');
    ok(grep($_ eq '--empty=/tmp/media1', @{$call}), 'plan job forwards drain mount');
    ok(grep($_ eq '--verbose', @{$call}), 'plan job forwards verbose flag');
    ok(grep($_ eq '--mount=/tmp/media1', @{$call}), 'plan job forwards configured mount 1');
    ok(grep($_ eq '--mount=/tmp/media2', @{$call}), 'plan job forwards configured mount 2');
    ok(grep($_ eq '--plan-file=' . $custom_plan, @{$call}), 'plan job uses overridden plan output file');
    ok(grep($_ eq '--log-file=' . $custom_log, @{$call}), 'plan job uses overridden plan log file');
};

subtest 'POST /dry-run requires a selected saved plan' => sub {
    my $t = _test_app();
    $t->post_ok('/dry-run' => form => {})
      ->status_is(400)
      ->content_like(qr/Select a saved plan file/i);
};

subtest 'POST /dry-run creates a balance_dry_run job and redirects' => sub {
    my $t = _test_app();
    my $plan_path = _write_saved_plan($t);
    @start_job_calls = ();

    my $custom_apply_log = File::Spec->catfile($t->app->balance_config->artifact_root, 'custom-apply.log');
    my $custom_manifest = File::Spec->catfile($t->app->balance_config->artifact_root, 'custom-manifest.jsonl');

    $t->post_ok('/dry-run' => form => {
        selected_plan_file => $plan_path,
        apply_log_file     => $custom_apply_log,
        manifest_file      => $custom_manifest,
    })
      ->status_is(302)
      ->header_like(Location => qr{/jobs/balance-dry-run-});

    my $jobs = $t->app->job_store->recent_jobs(limit => 5);
    my ($job) = grep { $_->{type} eq 'balance_dry_run' } @{$jobs};
    ok(defined $job, 'balance_dry_run job recorded in store');

    my $call = $start_job_calls[-1];
    ok($call, 'job runner invoked for dry-run');
    ok(grep($_ eq '--input-plan-file=' . $plan_path, @{$call}), 'dry-run uses selected saved plan');
    ok(grep($_ eq '--dry-run', @{$call}), 'dry-run passes dry-run flag');
    ok(grep($_ eq '--log-file=' . $custom_apply_log, @{$call}), 'dry-run uses overridden apply log');
    ok(grep($_ eq '--manifest-file=' . $custom_manifest, @{$call}), 'dry-run uses overridden manifest path');
};

subtest 'POST /apply creates a balance_apply job and redirects' => sub {
    my $t = _test_app();
    my $plan_path = _write_saved_plan($t, 'balance-plan-20260507-120001.sh');
    @start_job_calls = ();

    $t->post_ok('/apply' => form => {
        selected_plan_file => $plan_path,
    })
      ->status_is(302)
      ->header_like(Location => qr{/jobs/balance-apply-});

    my $jobs = $t->app->job_store->recent_jobs(limit => 5);
    my ($job) = grep { $_->{type} eq 'balance_apply' } @{$jobs};
    ok(defined $job, 'balance_apply job recorded in store');

    my $call = $start_job_calls[-1];
    ok($call, 'job runner invoked');
    ok(grep($_ eq '--input-plan-file=' . $plan_path, @{$call}), 'apply uses selected saved plan');
    ok(grep($_ eq '--apply', @{$call}), 'apply passes apply flag');
    ok(grep($_ eq '--log-file=' . $t->app->balance_config->balance_apply_log, @{$call}), 'apply uses configured artifact-root apply log');
    ok(grep($_ eq '--manifest-file=' . $t->app->balance_config->manifest_file, @{$call}), 'apply passes configured manifest file');
};

subtest 'volume refresh results are written incrementally per mount' => sub {
    my $t = _test_app();
    my $cache_file = $t->app->balance_config->dashboard_volume_cache_file;

    Balance::Web::Controller::Dashboard::_apply_volume_refresh_result($cache_file, '/tmp/media1', 1024, 1111);
    my $cache = Balance::Web::Controller::Dashboard::_read_volume_cache($cache_file);
    is_deeply($cache->{mounts}, {
        '/tmp/media1' => {
            used_kb    => 1024,
            updated_at => 1111,
        },
    }, 'first mount result is written to cache');

    Balance::Web::Controller::Dashboard::_apply_volume_refresh_result($cache_file, '/tmp/media2', 2048, 2222);
    $cache = Balance::Web::Controller::Dashboard::_read_volume_cache($cache_file);
    is_deeply($cache->{mounts}, {
        '/tmp/media1' => {
            used_kb    => 1024,
            updated_at => 1111,
        },
        '/tmp/media2' => {
            used_kb    => 2048,
            updated_at => 2222,
        },
    }, 'second mount result is appended without replacing earlier cache entries');
};

subtest 'GET / uses cached values and only refreshes stale mounts' => sub {
    my $t = _test_app();
    my $cache_file = $t->app->balance_config->dashboard_volume_cache_file;
    my $mock_dashboard = Test::MockModule->new('Balance::Web::Controller::Dashboard');
    my @scheduled;
    my $now = time;

    local $Balance::Web::Controller::Dashboard::VOLUME_CACHE_TTL = 3600;
    Balance::Web::Controller::Dashboard::_write_volume_cache($cache_file, {
        mounts => {
            '/tmp/media1' => {
                used_kb    => 1024,
                updated_at => $now - 30,
            },
            '/tmp/media2' => {
                used_kb    => 2048,
                updated_at => $now - 7200,
            },
        },
    });

    $mock_dashboard->mock('_schedule_volume_refresh', sub ($c, $path, $mounts) {
        push @scheduled, {
            cache_path => $path,
            mounts     => [@{$mounts}],
        };
        return;
    });
    $mock_dashboard->mock('dir_size_kb', sub ($mount) {
        die "dir_size_kb should not run during dashboard render for $mount";
    });

    $t->get_ok('/')
      ->status_is(200)
      ->content_like(qr/1M/)
      ->content_like(qr/2M/)
      ->content_like(qr/stale/i)
      ->content_like(qr/refreshing/i);

    ok(@scheduled, 'background refresh was scheduled for stale cache entries');
    is($scheduled[0]{cache_path}, $cache_file, 'stale refresh uses configured cache path');
    is_deeply($scheduled[0]{mounts}, ['/tmp/media2'], 'only stale mounts are queued for refresh');
};

done_testing;
