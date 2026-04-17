use v5.38;
use Test::More;
use File::Temp qw(tempdir);

use Balance::Core qw(log_ts dir_size_kb fmt pct_fmt print_state);

# --- log_ts ---

subtest 'log_ts returns ISO-like timestamp string' => sub {
    my $ts = log_ts();
    like($ts, qr/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/, 'format matches');
};

# --- dir_size_kb ---

subtest 'dir_size_kb returns 0 for empty dir' => sub {
    my $dir = tempdir(CLEANUP => 1);
    is(dir_size_kb($dir), 0, 'empty dir = 0 KB');
};

subtest 'dir_size_kb counts file sizes' => sub {
    my $dir = tempdir(CLEANUP => 1);
    open my $fh, '>', "$dir/file.txt" or die $!;
    print {$fh} 'x' x 2048;
    close $fh;
    my $kb = dir_size_kb($dir);
    is($kb, 2, '2048 bytes = 2 KB');
};

subtest 'dir_size_kb recurses into subdirs' => sub {
    my $dir = tempdir(CLEANUP => 1);
    mkdir "$dir/sub";
    open my $fh, '>', "$dir/sub/file.txt" or die $!;
    print {$fh} 'x' x 1024;
    close $fh;
    my $kb = dir_size_kb($dir);
    is($kb, 1, '1024 bytes in subdir = 1 KB');
};

# --- fmt ---

subtest 'fmt returns MB for small values' => sub {
    my $gb_kb = 1024 * 1024;
    like(fmt(500 * 1024, $gb_kb), qr/^500M$/, '500 MB');
};

subtest 'fmt returns GB for large values' => sub {
    my $gb_kb = 1024 * 1024;
    like(fmt(2 * $gb_kb, $gb_kb), qr/^2\.0G$/, '2.0 GB');
};

# --- pct_fmt ---

subtest 'pct_fmt returns 0.0% when denominator is zero' => sub {
    is(pct_fmt(0, 0), '0.0%', 'zero denominator');
};

subtest 'pct_fmt formats percentage correctly' => sub {
    is(pct_fmt(1, 4), '25.0%', '25.0%');
    is(pct_fmt(1, 3), '33.3%', '33.3%');
};

# --- print_state ---

subtest 'print_state produces output with correct headers' => sub {
    my $gb_kb = 1024 * 1024;
    open my $fh, '>', \my $buf or die $!;
    print_state(
        label  => 'TEST',
        mounts => ['/vol1'],
        vol    => { '/vol1' => { total => 2 * $gb_kb, other => 500 * 1024, tv => 1 * $gb_kb } },
        target_tv => {},
        gb_kb  => $gb_kb,
        fh     => $fh,
    );
    close $fh;
    like($buf, qr/=== TEST ===/,       'label in output');
    like($buf, qr/MOUNT/,              'MOUNT header');
    like($buf, qr/\/vol1/,             'mount in output');
};

done_testing;
