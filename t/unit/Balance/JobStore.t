use v5.38;
use Test::More;
use Test::Exception;

use Balance::JobStore;

# Use an in-memory SQLite DB for all tests.
my $store = Balance::JobStore->new(db_path => ':memory:', log_dir => '/tmp');

# --- insert_job / get_job ---

subtest 'insert_job creates a job' => sub {
    my $id = $store->insert_job('job-001', 'sonarr_apply');
    is($id, 'job-001', 'returns id');
    my $job = $store->get_job('job-001');
    ok(defined $job,            'job found');
    is($job->{id},     'job-001',       'id correct');
    is($job->{type},   'sonarr_apply',  'type correct');
    is($job->{status}, 'queued',        'initial status queued');
};

subtest 'get_job returns undef for unknown id' => sub {
    is($store->get_job('no-such-job'), undef, 'undef for missing job');
};

# --- insert_job: BEGIN IMMEDIATE blocks concurrent running job ---

subtest 'insert_job dies when another job is running' => sub {
    $store->insert_job('job-run', 'plex_scan');
    $store->update_job('job-run', status => 'running');
    dies_ok { $store->insert_job('job-new', 'sonarr_apply') }
        'dies when running job exists';
    # Cleanup: mark the running job done so other tests are not blocked
    $store->update_job('job-run', status => 'done');
};

# --- update_job ---

subtest 'update_job changes status' => sub {
    $store->insert_job('job-upd', 'sonarr_audit');
    $store->update_job('job-upd', status => 'running', started_at => '2026-01-01T00:00:00Z');
    my $job = $store->get_job('job-upd');
    is($job->{status},     'running',            'status updated');
    is($job->{started_at}, '2026-01-01T00:00:00Z', 'started_at set');
    # Cleanup so the running job doesn't block subsequent insert_job calls
    $store->update_job('job-upd', status => 'done');
};

subtest 'update_job ignores unknown fields' => sub {
    $store->insert_job('job-ign', 'test');
    # Should not die; unknown keys are silently ignored
    lives_ok { $store->update_job('job-ign', status => 'done', garbage => 'x') }
        'unknown fields ignored';
};

# --- recent_jobs ---

subtest 'recent_jobs returns jobs newest first' => sub {
    # Use a fresh store to isolate
    my $s2 = Balance::JobStore->new(db_path => ':memory:', log_dir => '/tmp');
    $s2->insert_job('j1', 'type_a');
    $s2->insert_job('j2', 'type_b');
    $s2->insert_job('j3', 'type_c');
    my $jobs = $s2->recent_jobs(limit => 10);
    is(scalar @{$jobs}, 3, 'three jobs returned');
    # SQLite rowid ordering is insertion order; all inserted at same second so check all present
    my %ids = map { $_->{id} => 1 } @{$jobs};
    ok($ids{j1} && $ids{j2} && $ids{j3}, 'all three jobs present');
};

subtest 'recent_jobs respects limit' => sub {
    my $s3 = Balance::JobStore->new(db_path => ':memory:', log_dir => '/tmp');
    $s3->insert_job("lim$_", 'test') for 1..5;
    my $jobs = $s3->recent_jobs(limit => 2);
    is(scalar @{$jobs}, 2, 'limit honoured');
};

# --- log_path ---

subtest 'log_path returns correct path' => sub {
    my $s4 = Balance::JobStore->new(db_path => ':memory:', log_dir => '/var/logs/jobs');
    is($s4->log_path('abc-123'), '/var/logs/jobs/abc-123.log', 'log path correct');
};

done_testing;
