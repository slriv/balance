use v5.38;
use Test::More;
use Test::Mojo;
use File::Temp qw(tempdir);
use File::Spec;
use Balance::Web::App;

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
    });
    return $t;
}

my $t = _test_app();

# Seed a job into the store
my $store = $t->app->job_store;
$store->insert_job('test-job-1', 'sonarr_audit');
$store->update_job('test-job-1', status => 'done', finished_at => '2024-01-01T00:00:00Z');

# --- GET /jobs/:id ---

subtest 'GET /jobs/:id shows job details' => sub {
    $t->get_ok('/jobs/test-job-1')
      ->status_is(200)
      ->content_like(qr/test-job-1/)
      ->content_like(qr/sonarr_audit/);
};

subtest 'GET /jobs/:id for unknown job returns 404' => sub {
    $t->get_ok('/jobs/no-such-job')->status_is(404);
};

# --- POST /jobs/:id/cancel ---

subtest 'POST /jobs/:id/cancel redirects to job page' => sub {
    $store->insert_job('test-job-2', 'sonarr_apply');
    $store->update_job('test-job-2', status => 'running');
    $t->post_ok('/jobs/test-job-2/cancel')
      ->status_is(302)
      ->header_like(Location => qr{/jobs/test-job-2});
};

subtest 'cancel updates job status to cancelled' => sub {
    my $job = $store->get_job('test-job-2');
    is($job->{status}, 'cancelled', 'status updated to cancelled');
};

# --- WebSocket /jobs/:id/stream ---

subtest 'WebSocket /jobs/:id/stream connects successfully' => sub {
    # Write a log file so the handler has content to replay
    my $log_dir = $t->app->balance_config->job_log_dir;
    open my $fh, '>', "$log_dir/test-job-1.log"
        or plan skip_all => "Cannot create log file: $!";
    print $fh "line one\nline two\n";
    close $fh;

    $t->websocket_ok('/jobs/test-job-1/stream')
      ->message_ok
      ->message_like(qr/line one/)
      ->finish_ok;
};

done_testing;
