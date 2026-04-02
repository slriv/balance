package Balance::Core;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(log_ts dir_size_kb fmt pct_fmt print_state discover_default_mounts);

sub log_ts {
    my @t = localtime();
    return sprintf "%04d-%02d-%02d %02d:%02d:%02d",
        $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0];
}

sub dir_size_kb {
    my ($dir) = @_;
    my $total = 0;
    my @stack = ($dir);
    while (my $d = pop @stack) {
        opendir my $dh, $d or next;
        while (my $f = readdir $dh) {
            next if $f eq '.' || $f eq '..';
            my $path = "$d/$f";
            if (-d $path && !-l $path) {
                push @stack, $path;
            } else {
                $total += (-s $path || 0);
            }
        }
        closedir $dh;
    }
    return int($total / 1024);
}

sub fmt {
    my ($kb, $gb_kb) = @_;
    return sprintf("%.1fG", $kb / $gb_kb) if $kb >= $gb_kb;
    return sprintf("%.0fM", $kb / 1024);
}

sub pct_fmt {
    my ($num, $den) = @_;
    return "0.0%" unless $den;
    return sprintf("%.1f%%", (100 * $num) / $den);
}

sub print_state {
    my (%args) = @_;
    my $label     = $args{label};
    my $mounts    = $args{mounts} || [];
    my $vol       = $args{vol} || {};
    my $target_tv = $args{target_tv} || {};
    my $gb_kb     = $args{gb_kb};
    my $fh        = $args{fh} || *STDOUT;

    printf {$fh} "\n=== %s ===\n", $label;
    printf {$fh} "%-12s %8s %8s %8s %8s %8s %8s %8s\n",
        "MOUNT", "TOTAL", "OTHER", "TV_USED", "FREE", "TARGET_TV", "SHOW_%", "OTHER_%";
    for my $m (@{$mounts}) {
        my $v = $vol->{$m};
        my $free = $v->{total} - $v->{other} - $v->{tv};
        my $tgt  = $target_tv->{$m} // 0;
        printf {$fh} "%-12s %8s %8s %8s %8s %8s %8s %8s\n",
            $m,
            fmt($v->{total}, $gb_kb),
            fmt($v->{other}, $gb_kb),
            fmt($v->{tv}, $gb_kb),
            fmt($free, $gb_kb),
            fmt($tgt, $gb_kb),
            pct_fmt($v->{tv}, $v->{total}),
            pct_fmt($v->{other}, $v->{total});
    }
    my $total_free = 0;
    $total_free += ($vol->{$_}{total} - $vol->{$_}{other} - $vol->{$_}{tv}) for @{$mounts};
    printf {$fh} "%-12s %8s %8s %8s %8s %8s %8s %8s\n", "TOTAL", "", "", "", fmt($total_free, $gb_kb), "", "", "";
}

sub discover_default_mounts {
    my ($prefix) = @_;
    $prefix = '/' unless defined $prefix && length $prefix;
    $prefix =~ s{/$}{} unless $prefix eq '/';

    my %mounted;
    if (open my $mi, '<', '/proc/self/mountinfo') {
        while (my $line = <$mi>) {
            chomp $line;
            my @parts = split /\s+/, $line;
            my $mnt = $parts[4];
            next unless defined $mnt && length $mnt;
            $mnt =~ s/\\040/ /g;
            $mnt =~ s/\\011/\t/g;
            $mnt =~ s/\\012/\n/g;
            $mnt =~ s/\\134/\\/g;
            $mounted{$mnt} = 1;
        }
        close $mi;
    }

    my %found;
    if (%mounted) {
        for my $path (keys %mounted) {
            next unless index($path, $prefix) == 0;
            next unless -d $path;
            $found{$path} = 1;
        }
    } else {
        my $parent = $prefix;
        if ($prefix ne '/') {
            $parent =~ s{/[^/]+$}{};
            $parent = '/' if $parent eq '';
        }

        if (opendir my $dh, $parent) {
            while (my $entry = readdir $dh) {
                next if $entry =~ /^\./;
                my $path = $parent eq '/' ? "/$entry" : "$parent/$entry";
                next unless index($path, $prefix) == 0;
                next unless -d $path;
                $found{$path} = 1;
            }
            closedir $dh;
        }

        $found{$prefix} = 1 if -d $prefix;
    }

    my @found = keys %found;

    @found = sort {
        (length($a) <=> length($b))
            || ($a cmp $b)
    } @found;

    return @found;
}

1;