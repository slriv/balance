use v5.42;
use source::encoding 'utf8';
use Test::More;
use Test::Exception;
use File::Temp qw(tempdir);
use File::Spec;
use lib 'lib';
use Balance::Config;

sub _db_path {
    my $dir = tempdir(CLEANUP => 1);
    return File::Spec->catfile($dir, 'config.db');
}

# --- static utility functions ---

subtest 'service_defaults dies on empty service' => sub {
    dies_ok { Balance::Config::service_defaults('') } 'dies on empty string';
    dies_ok { Balance::Config::service_defaults(undef) } 'dies on undef';
};

subtest 'service_defaults dies on unknown service' => sub {
    dies_ok { Balance::Config::service_defaults('bogus') } 'dies on unknown service';
};

subtest 'service_defaults returns sonarr structure' => sub {
    my $d = Balance::Config::service_defaults('sonarr');
    is($d->{base_url},         '', 'base_url default empty');
    is($d->{credential_name},  'SONARR_API_KEY', 'credential_name');
    is($d->{credential_value}, '', 'credential_value default empty');
    is($d->{audit_report_file}, '/artifacts/sonarr-audit-report.json', 'audit_report_file default');
    is($d->{path_map_file},    '/config/sonarr-path-map.example', 'path_map_file default');
    is($d->{report_file},      '/artifacts/sonarr-reconcile-plan.json', 'report_file default');
    is($d->{retry_queue_file}, '/artifacts/sonarr-retry-queue.jsonl', 'retry_queue_file default');
};

subtest 'service_defaults returns plex structure' => sub {
    my $d = Balance::Config::service_defaults('plex');
    is($d->{base_url},         '', 'base_url default empty');
    is($d->{credential_name},  'PLEX_TOKEN', 'credential_name');
    is($d->{credential_value}, '', 'credential_value default empty');
    is($d->{path_map_file},    '/config/plex-path-map.example', 'path_map_file default');
    is($d->{report_file},      '/artifacts/plex-reconcile-plan.json', 'report_file default');
    is($d->{retry_queue_file}, '/artifacts/plex-retry-queue.jsonl', 'retry_queue_file default');
    is($d->{library_ids},      '', 'library_ids default empty');
};

subtest 'redact_value handles undef and empty' => sub {
    is(Balance::Config::redact_value(undef), '(unset)', 'undef -> (unset)');
    is(Balance::Config::redact_value(''),    '(unset)', 'empty -> (unset)');
};

subtest 'redact_value masks short values' => sub {
    is(Balance::Config::redact_value('ab'),   '****', 'two chars -> ****');
    is(Balance::Config::redact_value('abcd'), '****', 'four chars -> ****');
};

subtest 'redact_value shows first two and last two chars' => sub {
    my $r = Balance::Config::redact_value('abcdefgh');
    like($r, qr/^ab\*+gh$/, 'starts with ab, ends with gh, middle masked');
};

# --- persisted object API ---

subtest 'Config constructs from db_path' => sub {
    my $cfg = Balance::Config->new(db_path => _db_path());
    ok($cfg, 'Config created');
};

subtest 'hash-like key API persists values' => sub {
    my $db_path = _db_path();
    my $cfg = Balance::Config->new(db_path => $db_path);

    $cfg->set('custom_key', 'custom_value');
    is($cfg->get('custom_key'), 'custom_value', 'get reads key set in memory/store');

    my $cfg2 = Balance::Config->new(db_path => $db_path);
    is($cfg2->get('custom_key'), 'custom_value', 'value persisted to sqlite and reloads');

    $cfg2->value('another_key', 'v2');
    is($cfg2->value('another_key'), 'v2', 'value() writes and reads by key name');

    ok($cfg2->exists('another_key'), 'exists true for present key');
    $cfg2->delete('another_key');
    ok(!$cfg2->exists('another_key'), 'delete removes key');
};

subtest 'set_bulk, all and reload operate correctly' => sub {
    my $db_path = _db_path();
    my $cfg = Balance::Config->new(db_path => $db_path);
    $cfg->set_bulk({ alpha => 'a', beta => 'b' });
    my $all = $cfg->all;
    is($all->{alpha}, 'a', 'alpha set via bulk');
    is($all->{beta},  'b', 'beta set via bulk');

    my $cfg2 = Balance::Config->new(db_path => $db_path);
    is($cfg2->get('alpha'), 'a', 'bulk value persisted');
    $cfg2->set('alpha', 'z');
    $cfg->reload;
    is($cfg->get('alpha'), 'z', 'reload refreshes in-memory cache');
};

subtest 'Sonarr accessors return defaults when store is empty' => sub {
    my $cfg = Balance::Config->new(db_path => _db_path());
    is($cfg->sonarr_url,               '',                                        'sonarr_url defaults to empty');
    is($cfg->sonarr_api_key,           '',                                        'sonarr_api_key defaults to empty');
    is($cfg->sonarr_report_file,       '/artifacts/sonarr-reconcile-plan.json',   'sonarr_report_file has default');
    is($cfg->sonarr_audit_report_file, '/artifacts/sonarr-audit-report.json',     'sonarr_audit_report_file has default');
    is($cfg->sonarr_path_map_file,     '/config/sonarr-path-map.example',         'sonarr_path_map_file has default');
    is($cfg->sonarr_retry_queue_file,  '/artifacts/sonarr-retry-queue.jsonl',     'sonarr_retry_queue_file has default');
    ok(!$cfg->has_sonarr, 'has_sonarr false when url/key missing');
};

subtest 'Plex accessors return defaults when store is empty' => sub {
    my $cfg = Balance::Config->new(db_path => _db_path());
    is($cfg->plex_url,              '',                                     'plex_url defaults to empty');
    is($cfg->plex_token,            '',                                     'plex_token defaults to empty');
    is($cfg->plex_report_file,      '/artifacts/plex-reconcile-plan.json',  'plex_report_file has default');
    is($cfg->plex_path_map_file,    '/config/plex-path-map.example',        'plex_path_map_file has default');
    is($cfg->plex_retry_queue_file, '/artifacts/plex-retry-queue.jsonl',    'plex_retry_queue_file has default');
    ok(!$cfg->has_plex, 'has_plex false when url/token missing');
};

subtest 'runtime accessors return defaults when store is empty' => sub {
    my $cfg = Balance::Config->new(db_path => _db_path());
    is($cfg->job_db,        '/artifacts/balance-jobs.db',              'job_db has default');
    is($cfg->job_log_dir,   '/artifacts/jobs',                         'job_log_dir has default');
    is($cfg->manifest_file, '/artifacts/balance-apply-manifest.jsonl', 'manifest_file has default');
};

subtest 'media_paths persistence and validation' => sub {
    my $cfg = Balance::Config->new(db_path => _db_path());
    $cfg->set_media_paths([
        { path => '/mnt/a', label => 'A' },
        { path => '/mnt/b', label => 'B' },
    ]);

    my $paths = $cfg->media_paths;
    is(ref $paths, 'ARRAY', 'media_paths returns arrayref');
    is(scalar @$paths, 2, 'two media paths returned');
    is($paths->[0]{path}, '/mnt/a', 'first media path preserved');

    my @mounts = $cfg->media_mounts;
    is_deeply(\@mounts, ['/mnt/a', '/mnt/b'], 'media_mounts derives path list');

    $cfg->delete_media_paths;
    is_deeply($cfg->media_paths, [], 'delete_media_paths clears media paths');

    eval { $cfg->set_media_paths('not-an-array') };
    ok($@, 'invalid media_paths dies');
};

done_testing;
