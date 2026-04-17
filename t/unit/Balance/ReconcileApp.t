use v5.38;
use Test::More;
use Test::Exception;
use File::Temp qw(tempdir);

use Balance::ReconcileApp qw(run);

# We test run() with a mock service module that returns canned data,
# avoiding all filesystem/NAS side-effects.

# --- Helpers ---

sub _write_manifest {
    my ($dir, @records) = @_;
    use JSON::PP ();
    my $path = "$dir/manifest.jsonl";
    open my $fh, '>', $path or die $!;
    print {$fh} JSON::PP::encode_json($_), "\n" for @records;
    close $fh;
    return $path;
}

sub _write_path_map {
    my ($dir) = @_;
    my $path = "$dir/path-map.conf";
    open my $fh, '>', $path or die $!;
    print {$fh} "/nas/tv = /mnt/tv\n";
    close $fh;
    return $path;
}

# --- Tests ---

subtest 'run dies without service_name' => sub {
    dies_ok { run(service_module => 'SomeModule') } 'dies without service_name';
};

subtest 'run dies without service_module' => sub {
    dies_ok { run(service_name => 'sonarr') } 'dies without service_module';
};

subtest 'run --show-config returns 0 without hitting files' => sub {
    # Mock service module so we don't need real Sonarr module loaded
    my $mock_module = 'MockService';
    $INC{'MockService.pm'} = 1;  # prevent require from hitting disk
    no strict 'refs';  ## no critic (TestingAndDebugging::ProhibitNoStrict)
    *{'MockService::defaults'} = sub {
        return {
            base_url         => 'http://localhost:1234',
            credential_name  => 'API_KEY',
            credential_value => 'testkey',
            manifest_file    => '/dev/null',
            path_map_file    => '/dev/null',
            report_file      => '/dev/null',
        };
    };
    use strict;

    my $rc;
    my $buf = '';
    open(local *STDOUT, '>', \$buf) or die $!;
    $rc = run(
        service_name   => 'mock',
        service_module => $mock_module,
        argv           => ['--show-config'],
    );

    is($rc, 0, 'returns 0 for --show-config');
    like($buf, qr/mock config/i, 'config output produced');
};

subtest 'run processes manifest and returns 0' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $manifest = _write_manifest(
        $dir,
        { mode => 'apply', status => 'applied', from_path => '/nas/tv/Show/S01', to_path => '/nas/tv/Show/S02' },
    );
    my $path_map = _write_path_map($dir);
    my $report   = "$dir/report.json";

    my $mock_module = 'MockService2';
    $INC{'MockService2.pm'} = 1;  # prevent require from hitting disk
    no strict 'refs';  ## no critic (TestingAndDebugging::ProhibitNoStrict)
    *{'MockService2::defaults'} = sub {
        return {
            base_url         => 'http://localhost:1234',
            credential_name  => 'API_KEY',
            credential_value => 'testkey',
            manifest_file    => $manifest,
            path_map_file    => $path_map,
            report_file      => $report,
        };
    };
    *{'MockService2::build_plan'} = sub {
        my ($pkg, %args) = @_;
        return [ map { { %$_, reconcile_status => 'planned' } } @{ $args{records} } ];
    };
    *{'MockService2::write_report'} = sub { return; };
    use strict;

    my $buf = '';
    open(local *STDOUT, '>', \$buf) or die $!;
    my $rc = run(
        service_name   => 'mock2',
        service_module => $mock_module,
        argv           => [],
    );

    is($rc, 0, 'returns 0 on success');
    like($buf, qr/reconcile plan created/i, 'success message printed');
};

done_testing;
