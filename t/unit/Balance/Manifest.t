use v5.38;
use Test::More;
use Test::Exception;
use File::Temp qw(tempfile);
use JSON::PP ();

use Balance::Manifest qw(append_manifest_record read_manifest successful_apply_records);

# --- append_manifest_record ---

subtest 'append_manifest_record is a no-op for falsy fh' => sub {
    lives_ok { append_manifest_record(undef, { a => 1 }) } 'does not die on undef fh';
};

subtest 'append_manifest_record writes canonical JSON line' => sub {
    open my $fh, '>', \my $buf or die $!;
    append_manifest_record($fh, { z => 2, a => 1 });
    close $fh;
    chomp(my $line = $buf);
    my $decoded = JSON::PP::decode_json($line);
    is_deeply($decoded, { z => 2, a => 1 }, 'round-trips data');
    # canonical means keys are sorted
    like($buf, qr/"a":1,"z":2/, 'canonical key order');
};

# --- read_manifest ---

subtest 'read_manifest dies on missing file' => sub {
    dies_ok { read_manifest('/nonexistent/manifest.jsonl') } 'dies on missing';
};

subtest 'read_manifest returns arrayref of decoded records' => sub {
    my ($fh, $path) = tempfile(UNLINK => 1);
    print {$fh} JSON::PP::encode_json({ src => '/a', dst => '/b' }), "\n";
    print {$fh} "\n";  # blank line should be skipped
    print {$fh} JSON::PP::encode_json({ src => '/c', dst => '/d' }), "\n";
    close $fh;

    my $records = read_manifest($path);
    is(scalar @{$records}, 2, 'two records (blank skipped)');
    is($records->[0]{src}, '/a', 'first record src');
    is($records->[1]{src}, '/c', 'second record src');
};

# --- successful_apply_records ---

subtest 'successful_apply_records returns empty for empty input' => sub {
    my $r = successful_apply_records([]);
    is_deeply($r, [], 'empty input -> empty');
};

subtest 'successful_apply_records filters by mode=apply and status=applied' => sub {
    my @records = (
        { mode => 'apply', status => 'applied',  src => '/a' },
        { mode => 'apply', status => 'failed',   src => '/b' },
        { mode => 'dry-run', status => 'applied', src => '/c' },
        { mode => 'apply', status => 'applied',  src => '/d' },
    );
    my $r = successful_apply_records(\@records);
    is(scalar @{$r}, 2, 'two matching records');
    is($r->[0]{src}, '/a', 'first match');
    is($r->[1]{src}, '/d', 'second match');
};

subtest 'successful_apply_records handles undef input' => sub {
    my $r = successful_apply_records(undef);
    is_deeply($r, [], 'undef input -> empty');
};

done_testing;
