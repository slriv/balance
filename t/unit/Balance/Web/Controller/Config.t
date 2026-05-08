use v5.38;
use Test::More;
use Test::Mojo;
use Cwd qw(abs_path);
use File::Temp qw(tempdir);
use File::Spec;
use Balance::Config;

# Test configuration controller
# Note: Persistence testing is done in Balance::Config unit tests

my $tempdir = tempdir(CLEANUP => 1);
my $db_path = File::Spec->catfile($tempdir, 'test.db');
my $artifact_dir = File::Spec->catdir($tempdir, 'artifacts');
mkdir $artifact_dir;
my $manifest_file = File::Spec->catfile($artifact_dir, 'balance-apply-manifest.jsonl');
my $sonarr_audit_report = File::Spec->catfile($artifact_dir, 'sonarr-audit-report.json');
my $sonarr_report_file = File::Spec->catfile($artifact_dir, 'sonarr-reconcile-plan.json');
my $sonarr_retry_queue = File::Spec->catfile($artifact_dir, 'sonarr-retry-queue.jsonl');
my $plex_report_file = File::Spec->catfile($artifact_dir, 'plex-reconcile-plan.json');
my $plex_retry_queue = File::Spec->catfile($artifact_dir, 'plex-retry-queue.jsonl');
my $artifact_root = File::Spec->catdir($tempdir, 'balance_artifacts');

sub _test_app {
    my $t = Test::Mojo->new('Balance::Web::App');
    $t->app->config->{balance_job_db} = $db_path;
    $t->app->balance_config->set('balance_job_log_dir', File::Spec->catdir($tempdir, 'jobs'));
    return $t;
}

subtest 'Config page displays form' => sub {
    my $t = _test_app();
    
    $t->get_ok('/config')
        ->status_is(200)
        ->content_like(qr/Configuration/i)
        ->content_like(qr/Mount Paths/i)
        ->content_like(qr/Artifact Root Directory/i)
        ->content_like(qr/Sonarr/i)
        ->content_like(qr/Plex/i)
        ->element_exists('input[name="media_path[]"]')
        ->element_exists('input[name="media_path[]"][data-picker-kind="directory"]')
        ->element_exists('input[name="artifact_root"]')
        ->element_exists('input[name="artifact_root"][data-picker-kind="directory"]')
        ->element_exists('input[name="balance_manifest_file"]')
        ->element_exists('input[name="balance_manifest_file"][data-picker-kind="file"]')
        ->element_exists('input[name="sonarr_url"]')
        ->element_exists('input[name="plex_url"]')
        ->content_like(qr/Choose Path/i);
};

subtest 'Config form shows default empty values when config is unset' => sub {
    my $t = _test_app();

    $t->get_ok('/config')
        ->status_is(200)
        ->element_exists('input[name="sonarr_url"]')
        ->element_exists('input[name="sonarr_url"][value=""]');
};

subtest 'Config form shows stored persisted values' => sub {
    my $config = Balance::Config->new(db_path => $db_path);
    $config->set('sonarr_url', 'http://persisted-sonarr:8989');
    $config->set('artifact_root', $artifact_root);

    my $t = _test_app();

    $t->get_ok('/config')
        ->status_is(200)
        ->element_exists('input[name="sonarr_url"][value="http://persisted-sonarr:8989"]')
        ->element_exists('input[name="artifact_root"][value="' . $artifact_root . '"]');
};

subtest 'Config update endpoint returns JSON success' => sub {
    my $t = _test_app();
    
    $t->post_ok('/config/update', json => {
        media_paths => [
            { path => '/new/media1', label => 'Media 1' },
            { path => '/new/media2', label => 'Media 2' },
        ],
        artifact_root            => $artifact_root,
        balance_manifest_file   => $manifest_file,
        balance_job_db          => $db_path,
        balance_job_log_dir     => File::Spec->catdir($tempdir, 'jobs'),
        sonarr_url              => 'http://new-sonarr:8989',
        sonarr_api_key          => 'new-key',
        sonarr_audit_report_file => $sonarr_audit_report,
        sonarr_path_map_file    => File::Spec->catfile($tempdir, 'sonarr-path-map.example'),
        sonarr_report_file      => $sonarr_report_file,
        sonarr_retry_queue_file => $sonarr_retry_queue,
        plex_url                => 'http://new-plex:32400',
        plex_token              => 'new-token',
        plex_library_ids        => '1,2,3',
        plex_path_map_file      => File::Spec->catfile($tempdir, 'plex-path-map.example'),
        plex_report_file        => $plex_report_file,
        plex_retry_queue_file   => $plex_retry_queue,
    })
        ->status_is(200)
        ->json_has('/success')
        ->json_has('/message')
        ->json_like('/message', qr/updated/i);

    my $config = Balance::Config->new(db_path => $db_path);
    is($config->get('artifact_root'), $artifact_root, 'artifact_root persisted');
};

subtest 'Config update requires at least two media paths' => sub {
    my $t = _test_app();

    $t->post_ok('/config/update', json => {
        media_paths => [ { path => '/new/media1', label => 'Media 1' } ],
        sonarr_url => 'http://new-sonarr:8989',
    })
        ->status_is(200)
        ->json_has('/success')
        ->json_is('/success', \0)
        ->json_like('/error', qr/At least 2 media paths/);
};

subtest 'Config browse lists filesystem entries for directory pickers' => sub {
        my $browse_root = File::Spec->catdir($tempdir, 'browse-root');
        my $child_dir = File::Spec->catdir($browse_root, 'child-dir');
        my $child_file = File::Spec->catfile($browse_root, 'child-file.txt');
        mkdir $browse_root;
        mkdir $child_dir;
        open my $fh, '>', $child_file or die "write $child_file: $!";
        print {$fh} 'example';
        close $fh;

        my $canonical_root = abs_path($browse_root);
        my $canonical_child_dir = abs_path($child_dir);
        my $canonical_child_file = abs_path($child_file);

        my $t = _test_app();
        $t->get_ok('/config/browse?kind=file&path=' . $browse_root)
            ->status_is(200)
            ->json_is('/success', \1)
            ->json_is('/current_path', $canonical_root)
            ->json_is('/entries/0/path', $canonical_child_dir)
            ->json_is('/entries/1/path', $canonical_child_file);
};

done_testing();
