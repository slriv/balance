#!/usr/bin/env perl
use strict;
use warnings;
use Carp;
use Getopt::Long;
$| = 1;  # unbuffered stdout
STDERR->autoflush(1);

BEGIN {
    printf STDERR "balance_tv starting: perl %s on %s\n", $], $^O;
}

$SIG{__DIE__}  = sub { Carp::confess("FATAL: @_") };
$SIG{__WARN__} = sub { warn "WARN: @_" };

# -- Config: edit or override with --mount flags --
my @MOUNTS = qw(/tv /tv2 /tv3 /tvnas2);

my $empty     = '';
my $threshold = 20;   # %, max deviation from target before we stop
my $max_size  = 0;    # GB, skip shows larger than this (0 = no limit)
my $plan_file = '';
my $apply     = 0;
my $dry_run   = 0;
my $log_file  = '';
my $verbose   = 0;
my $help      = 0;
my $mount_override = 0;

sub usage {
    my ($exit_code, $error) = @_;
    print STDERR "$error\n\n" if defined $error && length $error;
    print <<"USAGE";
Usage: $0 [options]

Plan TV folder moves across mounts to balance storage use.
This script prints rsync commands; it does not execute them.

Options:
  --empty=/path        Drain this mount by setting its target TV to 0.
                       Example: --empty=/tvnas2

  --threshold=N        Stop balancing when every mount is within N% of target TV.
                       Default: 20

  --max-size=N         Skip shows larger than N GB (0 = no size limit).
                       Default: 0

  --plan-file=/path    Save generated rsync move commands to this file.
                       File is overwritten on each run.

  --apply, --execute   Apply the generated move plan immediately using rsync.
                       Requires writable mounts in the container.

  --dry-run            Run rsync with -n (no files moved; shows what would happen).
                       Implies --apply.

  --log-file=/path     Tee all rsync output to this file (appended each run).
                       Use /logs/apply.log when running in container.

  --mount=/path        Mount to include. Repeat to define custom mount list.
                       If used, replaces defaults on first use.
                       Default mounts: /tv, /tv2, /tv3, /tvnas2

  --verbose            Print each selected move during planning.

  --help, -h           Show this help message and exit.

Examples:
  $0
  $0 --threshold=3 --max-size=50
  $0 --plan-file=/plans/latest-plan.sh
  $0 --apply --log-file=/logs/apply.log
  $0 --dry-run
  $0 --empty=/tvnas2
  $0 --mount=/tv --mount=/tv2 --mount=/tv3 --verbose
USAGE
    exit $exit_code;
}

GetOptions(
    'help|h'      => \$help,
    'empty=s'     => \$empty,
    'threshold=f' => \$threshold,
    'max-size=i'  => \$max_size,
    'plan-file=s' => \$plan_file,
    'apply|execute' => \$apply,
    'dry-run'     => \$dry_run,
    'log-file=s'  => \$log_file,
    'verbose'     => \$verbose,
    'mount=s@'    => sub {
        @MOUNTS = () unless $mount_override++;
        push @MOUNTS, $_[1];
    },
) or usage(2, "Invalid options.");

usage(0) if $help;
usage(2, "--threshold must be >= 0") if $threshold < 0;
$apply = 1 if $dry_run;

my $GB = 1024*1024;  # in KB units (du -sk)
my $max_size_kb  = $max_size ? $max_size * $GB : 0;
my $min_threshold_kb = $GB;  # 1GB floor so tiny targets don't over-trigger moves

# -- Gather volume info --
my %vol;
for my $mnt (@MOUNTS) {
    unless (-d $mnt) {
        warn "SKIP: $mnt not a directory\n";
        next;
    }
    my $df_line = `df -k \Q$mnt\E | tail -1`;
    my @f = split /\s+/, $df_line;
    my ($total_kb, $used_kb) = ($f[1], $f[2]);

    my %shows;
    opendir my $dh, $mnt or die "Can't opendir $mnt: $!\n";
    while (my $d = readdir $dh) {
        next if $d =~ /^\./;
        my $path = "$mnt/$d";
        next unless -d $path;
        $shows{$d} = dir_size_kb($path);
    }
    closedir $dh;

    my $tv_kb = 0;
    $tv_kb += $_ for values %shows;
    $vol{$mnt} = {
        total  => $total_kb,
        other  => $used_kb - $tv_kb,
        tv     => $tv_kb,
        shows  => \%shows,
    };
}
# prune mounts that didn't resolve
@MOUNTS = grep { exists $vol{$_} } @MOUNTS;
die "No usable mounts found. Check your volume mappings.\n" unless @MOUNTS;
printf STDERR "Loaded %d volumes: %s\n", scalar @MOUNTS, join(', ', @MOUNTS);
for my $m (@MOUNTS) {
    printf STDERR "  %-12s total=%s shows=%d\n", $m, fmt($vol{$m}{total}), scalar keys %{$vol{$m}{shows}};
}

# -- Determine active target volumes --
my @targets = $empty ? (grep { $_ ne $empty } @MOUNTS) : @MOUNTS;
die "--empty=$empty not in mount list\n" if $empty && !exists $vol{$empty};

# -- Compute target free per active volume --
# effective_cap = total - other (max TV a volume could hold)
# total_tv = sum of all TV across ALL volumes (including one being emptied)
# total_effective = sum of effective_cap across targets only
# target: distribute TV proportionally to effective_cap
my $total_tv = 0;
$total_tv += $vol{$_}{tv} for @MOUNTS;
my $total_eff = 0;
$total_eff += ($vol{$_}{total} - $vol{$_}{other}) for @targets;

# target_tv per volume = proportion of its effective_cap
my %target_tv;
for my $m (@targets) {
    my $eff = $vol{$m}{total} - $vol{$m}{other};
    $target_tv{$m} = $total_tv * ($eff / $total_eff);
}
$target_tv{$empty} = 0 if $empty;

print_state("CURRENT STATE");

# -- Greedy move loop --
my @moves;
for (1..5000) {  # safety cap
    # delta = how much TV to shed (positive) or absorb (negative)
    my %delta;
    my %limit;
    for my $m (@MOUNTS) {
        my $tgt = $target_tv{$m} // 0;
        $delta{$m} = $vol{$m}{tv} - $tgt;

        my $base_kb = $tgt > 0 ? $tgt : $vol{$m}{tv};
        my $pct_limit_kb = $base_kb * ($threshold / 100.0);
        $limit{$m} = $pct_limit_kb > $min_threshold_kb ? $pct_limit_kb : $min_threshold_kb;
    }
    my @over  = sort { $delta{$b} <=> $delta{$a} } grep { $delta{$_} > $limit{$_} } @MOUNTS;
    my @under = sort { $delta{$a} <=> $delta{$b} } grep { $delta{$_} < -$limit{$_} } @targets;
    last unless @over && @under;

    my $src = $over[0];
    my $dst = $under[0];
    my $room = -$delta{$dst};

    # pick smallest show from src that fits (low-hanging fruit first)
    my @candidates = sort { $vol{$src}{shows}{$a} <=> $vol{$src}{shows}{$b} }
                     keys %{$vol{$src}{shows}};
    my $picked;
    for my $show (@candidates) {
        next if exists $vol{$dst}{shows}{$show};
        my $sz = $vol{$src}{shows}{$show};
        next if $max_size_kb && $sz > $max_size_kb;
        next if $sz > $room;
        # don't move something so small it barely helps (< 1% of delta)
        next if $sz < $delta{$src} * 0.01 && $delta{$src} > $limit{$src} * 2;
        $picked = $show;
        last;
    }
    # if nothing small enough worked, try biggest-that-fits (need to close the gap)
    unless ($picked) {
        for my $show (reverse @candidates) {
            next if exists $vol{$dst}{shows}{$show};
            my $sz = $vol{$src}{shows}{$show};
            next if $max_size_kb && $sz > $max_size_kb;
            next if $sz > $room;
            $picked = $show;
            last;
        }
    }
    last unless $picked;

    # "move" it in our data model
    my $sz = $vol{$src}{shows}{$picked};
    push @moves, { show => $picked, from => $src, to => $dst, size => $sz };
    delete $vol{$src}{shows}{$picked};
    $vol{$src}{tv} -= $sz;
    $vol{$dst}{shows}{$picked} = $sz;
    $vol{$dst}{tv} += $sz;
    printf "  move: %-45s %s → %s  (%s)\n", qq{"$picked"}, $src, $dst, fmt($sz) if $verbose;
}

# -- Output --
print_state("PROJECTED STATE");
printf "\n=== MOVE PLAN: %d moves ===\n", scalar @moves;
my $total_move_kb = 0;
$total_move_kb += $_->{size} for @moves;
printf "    Total data to move: %s\n", fmt($total_move_kb) if @moves;

my @plan_lines;
if (!@moves) {
    if ($plan_file) {
        open my $pf, '>', $plan_file or die "Can't write plan file $plan_file: $!\n";
        print {$pf} "#!/usr/bin/env bash\n";
        print {$pf} "# No moves required; already within ${threshold}% threshold.\n";
        close $pf;
        chmod 0755, $plan_file;
        print "Saved plan file: $plan_file\n";
    }
    print "Already balanced within ${threshold}% threshold.\n";
    exit 0;
}
for my $m (@moves) {
    printf "# %s (%s)\n", $m->{show}, fmt($m->{size});
    my $safe = $m->{show};
    $safe =~ s/'/'\\''/g;  # escape single quotes for shell
    my $cmd = sprintf "rsync -avP --remove-source-files '%s/%s/' '%s/%s'",
        $m->{from}, $safe, $m->{to}, $safe;
    push @plan_lines, sprintf("# %s (%s)", $m->{show}, fmt($m->{size}));
    push @plan_lines, $cmd;
    print "$cmd\n";
}
if ($plan_file) {
    open my $pf, '>', $plan_file or die "Can't write plan file $plan_file: $!\n";
    print {$pf} "#!/usr/bin/env bash\n";
    print {$pf} "set -euo pipefail\n\n";
    print {$pf} join("\n", @plan_lines), "\n";
    close $pf;
    chmod 0755, $plan_file;
    print "Saved plan file: $plan_file\n";
}

if ($apply) {
    my $mode_label = $dry_run ? 'DRY-RUN' : 'APPLY';
    print "\n=== $mode_label MODE: ", scalar(@moves), " planned move(s) ===\n";
    print "    (no files will be moved)\n" if $dry_run;

    my $lf;
    if ($log_file) {
        open $lf, '>>', $log_file or die "Can't open log file $log_file: $!\n";
        $lf->autoflush(1);
        printf {$lf} "=== %s started %s: %d move(s) ===\n",
            $mode_label, log_ts(), scalar @moves;
    }
    my $tee = sub { print $_[0]; print {$lf} $_[0] if $lf; };

    my ($ok, $failed) = (0, 0);
    for my $m (@moves) {
        my $src_dir = "$m->{from}/$m->{show}/";
        my $dst_dir = "$m->{to}/$m->{show}";
        $tee->(sprintf "[%s] (%d/%d) %s -> %s\n",
            log_ts(), $ok + $failed + 1, scalar @moves, $src_dir, $dst_dir);
        my @rsync_args = $dry_run
            ? ('-avPn', $src_dir, $dst_dir)
            : ('-avP', '--remove-source-files', $src_dir, $dst_dir);
        if (open my $pipe, '-|', 'rsync', @rsync_args) {
            while (my $line = <$pipe>) { $tee->($line) }
            close $pipe;
        } else {
            $tee->("Can't exec rsync: $!\n");
        }
        my $rc = $?;
        if ($rc == 0) {
            $ok++;
        } else {
            $tee->(sprintf "FAILED (exit=%d)\n", $rc >> 8);
            $failed++;
        }
    }
    my $summary = sprintf "\n%s summary: %d succeeded, %d failed\n", $mode_label, $ok, $failed;
    $tee->($summary);
    if ($lf) {
        printf {$lf} "=== %s ended %s ===\n", $mode_label, log_ts();
        close $lf;
    }
    exit($failed ? 1 : 0);
}

print "\n** Review above, then pipe to sh or run commands manually **\n";

# -- Helpers --
sub log_ts {
    my @t = localtime();
    return sprintf "%04d-%02d-%02d %02d:%02d:%02d",
        $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0];
}
sub dir_size_kb {
    my $dir = shift;
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
    my $kb = shift;
    return sprintf("%.1fG", $kb / $GB) if $kb >= $GB;
    return sprintf("%.0fM", $kb / 1024);
}
sub pct_fmt {
    my ($num, $den) = @_;
    return "0.0%" unless $den;
    return sprintf("%.1f%%", (100 * $num) / $den);
}
sub print_state {
    my $label = shift;
    printf "\n=== %s ===\n", $label;
    printf "%-12s %8s %8s %8s %8s %8s %8s %8s\n",
        "MOUNT", "TOTAL", "OTHER", "TV_USED", "FREE", "TARGET_TV", "SHOW_%", "OTHER_%";
    for my $m (@MOUNTS) {
        my $v = $vol{$m};
        my $free = $v->{total} - $v->{other} - $v->{tv};
        my $tgt  = $target_tv{$m} // 0;
        printf "%-12s %8s %8s %8s %8s %8s %8s %8s\n",
            $m,
            fmt($v->{total}),
            fmt($v->{other}),
            fmt($v->{tv}),
            fmt($free),
            fmt($tgt),
            pct_fmt($v->{tv}, $v->{total}),
            pct_fmt($v->{other}, $v->{total});
    }
    my $total_free = 0;
    $total_free += ($vol{$_}{total} - $vol{$_}{other} - $vol{$_}{tv}) for @MOUNTS;
    printf "%-12s %8s %8s %8s %8s %8s %8s %8s\n", "TOTAL", "", "", "", fmt($total_free), "", "", "";
}
