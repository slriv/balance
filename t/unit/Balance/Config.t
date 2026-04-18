use v5.38;
use Test::More;
use Test::Exception;
use File::Temp qw(tempfile);

use Balance::Config qw(load_env_file service_defaults redact_value);

# --- load_env_file ---

subtest 'load_env_file returns 0 for missing file' => sub {
    is(load_env_file('/nonexistent/path/.env'), 0, 'returns 0');
};

subtest 'load_env_file returns 0 for undef' => sub {
    is(load_env_file(undef), 0, 'returns 0 for undef');
};

subtest 'load_env_file loads key=value pairs' => sub {
    my ($fh, $path) = tempfile(UNLINK => 1);
    print {$fh} "TEST_KEY_CFG=hello\n";
    close $fh;

    delete $ENV{TEST_KEY_CFG};
    my $rc = load_env_file($path);
    is($rc, 1, 'returns 1');
    is($ENV{TEST_KEY_CFG}, 'hello', 'sets env var');
    delete $ENV{TEST_KEY_CFG};
};

subtest 'load_env_file does not override existing env vars' => sub {
    my ($fh, $path) = tempfile(UNLINK => 1);
    print {$fh} "TEST_KEY_CFG2=from_file\n";
    close $fh;

    local $ENV{TEST_KEY_CFG2} = 'already_set';
    load_env_file($path);
    is($ENV{TEST_KEY_CFG2}, 'already_set', 'existing env var not overridden');
};

subtest 'load_env_file strips matching single quotes' => sub {
    my ($fh, $path) = tempfile(UNLINK => 1);
    print {$fh} "TEST_KEY_CFG3='quoted_value'\n";
    close $fh;

    delete $ENV{TEST_KEY_CFG3};
    load_env_file($path);
    is($ENV{TEST_KEY_CFG3}, 'quoted_value', 'strips single quotes');
    delete $ENV{TEST_KEY_CFG3};
};

subtest 'load_env_file strips matching double quotes' => sub {
    my ($fh, $path) = tempfile(UNLINK => 1);
    print {$fh} "TEST_KEY_DQUOTE=\"double_quoted\"\n";
    close $fh;

    delete $ENV{TEST_KEY_DQUOTE};
    load_env_file($path);
    is($ENV{TEST_KEY_DQUOTE}, 'double_quoted', 'strips double quotes');
    delete $ENV{TEST_KEY_DQUOTE};
};

subtest 'load_env_file does not strip mismatched quotes' => sub {
    my ($fh, $path) = tempfile(UNLINK => 1);
    print {$fh} "TEST_KEY_MISMATCH='mismatch\"\n";
    close $fh;

    delete $ENV{TEST_KEY_MISMATCH};
    load_env_file($path);
    is($ENV{TEST_KEY_MISMATCH}, q{'mismatch"}, 'mismatched quotes not stripped');
    delete $ENV{TEST_KEY_MISMATCH};
};

subtest 'load_env_file skips comments and blank lines' => sub {
    my ($fh, $path) = tempfile(UNLINK => 1);
    print {$fh} "# a comment\n\nTEST_KEY_CFG4=ok\n";
    close $fh;

    delete $ENV{TEST_KEY_CFG4};
    load_env_file($path);
    is($ENV{TEST_KEY_CFG4}, 'ok', 'loads after skipping comment and blank');
    delete $ENV{TEST_KEY_CFG4};
};

# --- service_defaults ---

subtest 'service_defaults dies on empty service' => sub {
    dies_ok { service_defaults('') } 'dies on empty string';
    dies_ok { service_defaults(undef) } 'dies on undef';
};

subtest 'service_defaults dies on unknown service' => sub {
    dies_ok { service_defaults('bogus') } 'dies on unknown service';
};

subtest 'service_defaults returns sonarr structure' => sub {
    local $ENV{SONARR_BASE_URL}  = 'http://sonarr:8989';
    local $ENV{SONARR_API_KEY}   = 'testkey';
    my $d = service_defaults('sonarr');
    is($d->{base_url},         'http://sonarr:8989', 'base_url');
    is($d->{credential_name},  'SONARR_API_KEY',     'credential_name');
    is($d->{credential_value}, 'testkey',            'credential_value');
    ok(exists $d->{manifest_file}, 'has manifest_file');
    ok(exists $d->{report_file},   'has report_file');
};

subtest 'service_defaults returns plex structure' => sub {
    local $ENV{PLEX_BASE_URL} = 'http://plex:32400';
    local $ENV{PLEX_TOKEN}    = 'mytoken';
    my $d = service_defaults('plex');
    is($d->{base_url},         'http://plex:32400', 'base_url');
    is($d->{credential_name},  'PLEX_TOKEN',        'credential_name');
    is($d->{credential_value}, 'mytoken',           'credential_value');
    ok(exists $d->{library_ids}, 'has library_ids key');
};

# --- redact_value ---

subtest 'redact_value handles undef and empty' => sub {
    is(redact_value(undef), '(unset)', 'undef -> (unset)');
    is(redact_value(''),    '(unset)', 'empty -> (unset)');
};

subtest 'redact_value masks short values' => sub {
    is(redact_value('ab'),   '****', 'two chars -> ****');
    is(redact_value('abcd'), '****', 'four chars -> ****');
};

subtest 'redact_value shows first two and last two chars' => sub {
    my $r = redact_value('abcdefgh');
    like($r, qr/^ab\*+gh$/, 'starts with ab, ends with gh, middle masked');
};

done_testing;
