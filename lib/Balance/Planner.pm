package Balance::Planner;
use v5.42;
use experimental 'class';
use feature 'signatures';
use source::encoding 'utf8';

our $VERSION = '0.02';

class Balance::Planner {  ## no critic (Modules::RequireEndWithOne)
    use Exporter 'import';
    use Getopt::Long qw(GetOptionsFromArray Configure);
    use Text::ParseWords qw(shellwords);
    use Balance::Config ();
    use Balance::VolumeScanner ();
    use Balance::Manifest qw(append_manifest_record);
    use Balance::Core qw(log_ts dir_size_kb fmt pct_fmt print_state validate_media_path);

    our @EXPORT_OK = qw(
        load_moves_from_plan_file split_plan_path size_hint_kb_from_comment
        rsync_args_for_move output_timestamp stamp_output_path defaults cli_main
    );

    field $threshold :param = 20;
    field $max_size_kb :param = 0;
    field $max_moves :param = 0;
    field $drain_mount :param = '';
    field $cache_path :param = '';
    field $_scanner;

    ADJUST {
        die "threshold must be >= 0\n" if $threshold < 0;
        die "threshold must be <= 100\n" if $threshold > 100;

        my $cp = $cache_path // Balance::Config::dashboard_volume_cache_file();
        $_scanner = Balance::VolumeScanner->new(cache_path => $cp);
    }

    method get_volumes(@mounts) {
        return $_scanner->scan_cached(@mounts);
    }

    # Compute target TV per volume based on threshold and effective capacity
    method compute_targets($vol, @mounts) {
        my $total_tv = 0;
        my @targets = $drain_mount ? (grep { $_ ne $drain_mount } @mounts) : @mounts;

        die "No target volumes available\n" unless @targets;
        die "--drain-mount=$drain_mount not in mount list\n"
            if $drain_mount && !exists $vol->{$drain_mount};

        # Calculate total TV from all mounts' directories
        for my $mnt (@mounts) {
            my $tv_kb = 0;
            $tv_kb += $_ for values %{ $vol->{$mnt}{dirs} // {} };
            $total_tv += $tv_kb;
        }

        # Compute capacity per target
        my (%tv_cap, %eff_cap);
        my ($total_tv_cap, $total_eff_cap) = (0, 0);
        for my $m (@targets) {
            my $capacity = $vol->{$m}{capacity_kb} // 0;
            my $used = $vol->{$m}{used_kb} // 0;
            my $non_tv_used = $used - ($self->_current_tv_kb($vol, $m));

            my $eff = $capacity - $non_tv_used;
            $eff = 0 if $eff < 0;
            my $min_free_kb = $capacity * ($threshold / 100.0);
            my $cap = $eff - $min_free_kb;
            $cap = 0 if $cap < 0;

            $eff_cap{$m} = $eff;
            $tv_cap{$m} = $cap;
            $total_eff_cap += $eff;
            $total_tv_cap += $cap;
        }

        # Distribute target TV proportionally
        my %target_tv;
        if ($total_tv_cap > 0 && $total_tv <= $total_tv_cap) {
            for my $m (@targets) {
                $target_tv{$m} = $total_tv * ($tv_cap{$m} / $total_tv_cap);
            }
        } else {
            my $overflow_kb = $total_tv > $total_tv_cap ? ($total_tv - $total_tv_cap) : 0;
            my $spread_base = $total_eff_cap > 0 ? $total_eff_cap : scalar(@targets);
            for my $m (@targets) {
                my $weight = $total_eff_cap > 0 ? $eff_cap{$m} : 1;
                $target_tv{$m} = $tv_cap{$m} + ($overflow_kb * ($weight / $spread_base));
            }
        }
        $target_tv{$drain_mount} = 0 if $drain_mount;

        return (\%target_tv, $total_tv, $total_tv_cap);
    }

    # Greedy move-selection loop
    method plan_moves($vol, @mounts) {
        my ($target_tv, $total_tv, $total_tv_cap) = $self->compute_targets($vol, @mounts);

        my $GB = 1024 * 1024;  # in KB units
        my $move_slack_kb = $GB;

        my @moves;
        for (1..5000) {  # safety cap
            my %delta;
            for my $m (@mounts) {
                my $current_tv = $self->_current_tv_kb($vol, $m);
                my $tgt = $target_tv->{$m} // 0;
                $delta{$m} = $current_tv - $tgt;
            }
            my @over = sort { $delta{$b} <=> $delta{$a} }
                       grep { $delta{$_} > $move_slack_kb } @mounts;
            my @targets = $drain_mount ? (grep { $_ ne $drain_mount } @mounts) : @mounts;
            my @under = sort { $delta{$a} <=> $delta{$b} }
                        grep { $delta{$_} < -$move_slack_kb } @targets;
            last unless @over && @under;

            my $src = $over[0];
            my $dst = $under[0];
            my $room = -$delta{$dst};

            # Pick smallest show that fits
            my @candidates = sort { $vol->{$src}{dirs}{$a} <=> $vol->{$src}{dirs}{$b} }
                             keys %{ $vol->{$src}{dirs} // {} };
            my $picked;
            for my $show (@candidates) {
                next if exists $vol->{$dst}{dirs}{$show};
                my $sz = $vol->{$src}{dirs}{$show};
                next if $max_size_kb && $sz > $max_size_kb;
                next if $sz > $room;
                next if $sz < $delta{$src} * 0.01 && $delta{$src} > $move_slack_kb * 2;
                $picked = $show;
                last;
            }

            # Try biggest-that-fits if nothing small worked
            unless ($picked) {
                for my $show (reverse @candidates) {
                    next if exists $vol->{$dst}{dirs}{$show};
                    my $sz = $vol->{$src}{dirs}{$show};
                    next if $max_size_kb && $sz > $max_size_kb;
                    next if $sz > $room;
                    $picked = $show;
                    last;
                }
            }

            last unless $picked;
            last if $max_moves && scalar @moves >= $max_moves;

            my $sz = $vol->{$src}{dirs}{$picked};
            push @moves, { show => $picked, from => $src, to => $dst, size => $sz };
            delete $vol->{$src}{dirs}{$picked};
            $vol->{$dst}{dirs}{$picked} = $sz;
        }

        return \@moves;
    }

    # Execute moves via rsync
    method apply($moves, %args) {
        my $dry_run = $args{dry_run} // 0;
        my $log_file = $args{log_file} // '';
        my $manifest_file = $args{manifest_file} // '';

        my ($ok, $failed) = (0, 0);
        my $run_id = join('-', 'balance', time(), $$);

        my $lf;
        my $mf;
        if ($log_file) {
            open $lf, '>>', $log_file or die "Can't open log file $log_file: $!\n";
            $lf->autoflush(1);
            printf {$lf} "=== %s started %s: %d move(s) ===\n",
                ($dry_run ? 'DRY-RUN' : 'APPLY'), log_ts(), scalar @{$moves};
        }
        if ($manifest_file && !$dry_run) {
            open $mf, '>>', $manifest_file or die "Can't open manifest file $manifest_file: $!\n";
            $mf->autoflush(1);
        }

        for my $m (@{$moves}) {
            my $src_dir = $m->{source_path} // "$m->{from}/$m->{show}/";
            my $dst_dir = $m->{dest_path} // "$m->{to}/$m->{show}";
            my $started_at = log_ts();
            printf "[%s] (%d/%d) %s -> %s\n", $started_at, $ok + $failed + 1, scalar @{$moves}, $src_dir, $dst_dir;
            if ($lf) {
                printf {$lf} "[%s] (%d/%d) %s -> %s\n", $started_at, $ok + $failed + 1, scalar @{$moves}, $src_dir, $dst_dir;
            }

            my @rsync_args = rsync_args_for_move($m, $dry_run, !!$log_file);
            if (open my $pipe, '-|', 'rsync', @rsync_args) {
                while (my $line = <$pipe>) {
                    print $line;
                    print {$lf} $line if $lf;
                }
                close $pipe;
            } else {
                my $err = "Can't exec rsync: $!\n";
                print $err;
                print {$lf} $err if $lf;
            }

            my $rc = $?;
            if ($rc == 0) {
                $ok++;
                append_manifest_record($mf, {
                    run_id        => $run_id,
                    timestamp     => $started_at,
                    mode          => $dry_run ? 'dry-run' : 'apply',
                    status        => 'applied',
                    show          => $m->{show},
                    from_mount    => $m->{from},
                    to_mount      => $m->{to},
                    from_path     => $src_dir,
                    to_path       => $dst_dir,
                    size_kb       => $m->{size},
                }) if $mf;
            } else {
                printf "FAILED (exit=%d)\n", $rc >> 8;
                if ($lf) {
                    printf {$lf} "FAILED (exit=%d)\n", $rc >> 8;
                }
                $failed++;
            }
        }

        my $mode_label = $dry_run ? 'DRY-RUN' : 'APPLY';
        printf "\n%s summary: %d succeeded, %d failed\n", $mode_label, $ok, $failed;
        if ($lf) {
            printf {$lf} "\n%s summary: %d succeeded, %d failed\n", $mode_label, $ok, $failed;
            printf {$lf} "=== %s ended %s ===\n", $mode_label, log_ts();
            close $lf;
        }
        close $mf if $mf;

        return { ok => $ok, failed => $failed };
    }

    # --- Stateless exports ---

    sub load_moves_from_plan_file($path) {
        open my $fh, '<', $path or die "Can't read saved plan file $path: $!\n";

        my @moves;
        my $size_hint_kb = 0;
        while (my $line = <$fh>) {
            chomp $line;
            $line =~ s/\r\z//;

            next if $line =~ /^\s*$/;
            next if $line =~ /^\s*#!/;
            next if $line =~ /^\s*set\s+/;

            if ($line =~ /^\s*#\s*(.+?)\s*$/) {
                $size_hint_kb = size_hint_kb_from_comment($1);
                next;
            }

            my @argv = shellwords($line);
            die "Unsupported command in saved plan $path: $line\n"
                unless @argv && $argv[0] eq 'rsync' && @argv >= 3;

            my $src_dir = $argv[-2];
            my $dst_dir = $argv[-1];
            my ($from_mount, $show) = split_plan_path($src_dir);
            my ($to_mount) = split_plan_path($dst_dir);

            push @moves, {
                show        => $show,
                from        => $from_mount,
                to          => $to_mount,
                size        => $size_hint_kb,
                source_path => $src_dir,
                dest_path   => $dst_dir,
                rsync_args  => [@argv],
            };
            $size_hint_kb = 0;
        }

        close $fh;
        return \@moves;
    }

    sub split_plan_path($path) {
        my $normalized = $path // '';
        $normalized =~ s{/\z}{} unless $normalized eq '/';
        die "Invalid path in saved plan: $path\n" unless $normalized =~ m{^/} && $normalized ne '/';

        my ($mount, $show) = $normalized =~ m{^(.*?)/([^/]+)\z};
        die "Invalid path in saved plan: $path\n" unless defined $mount && defined $show;
        $mount = '/' if $mount eq '';
        return ($mount, $show);
    }

    sub size_hint_kb_from_comment($comment) {
        return 0 unless defined $comment && $comment =~ /\((\d+(?:\.\d+)?)([GM])\)\s*\z/i;

        my ($amount, $unit) = ($1, uc $2);
        return int($amount * 1024 * 1024) if $unit eq 'G';
        return int($amount * 1024) if $unit eq 'M';
        return 0;
    }

    sub rsync_args_for_move($move, $dry_run_enabled, $has_log_file) {
        if ($move->{rsync_args} && @{ $move->{rsync_args} }) {
            my @args = @{ $move->{rsync_args} };
            shift @args if @args && $args[0] eq 'rsync';

            if ($dry_run_enabled) {
                unshift @args, '-n'
                    unless grep { $_ eq '-n' || /^-[^-]*n/ || $_ eq '--dry-run' } @args;
            }

            return @args;
        }

        my $src_dir = $move->{source_path} // "$move->{from}/$move->{show}/";
        my $dst_dir = $move->{dest_path} // "$move->{to}/$move->{show}";

        return $dry_run_enabled
            ? ($has_log_file ? ('-avn', '--partial', $src_dir, $dst_dir)
                             : ('-avPn', $src_dir, $dst_dir))
            : ($has_log_file ? ('-av', '--partial', '--remove-source-files', $src_dir, $dst_dir)
                             : ('-avP', '--remove-source-files', $src_dir, $dst_dir));
    }

    sub output_timestamp() {
        my @t = localtime();
        return sprintf "%04d%02d%02d-%02d%02d%02d",
            $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0];
    }

    sub stamp_output_path($path, $stamp) {
        return $path unless defined $path && length $path;
        return $path if $path =~ /-\d{8}-\d{6}(?:\.[^\/]+)?$/;

        if ($path =~ /(\.[^\/.]+)$/) {
            my $ext = $1;
            $path =~ s/\Q$ext\E$//;
            return "$path-$stamp$ext";
        }
        return "$path-$stamp";
    }

    sub defaults() {
        return Balance::Config::service_defaults('balance');
    }

    # --- CLI ---

    sub cli_main(@argv) {
        $| = 1;  # unbuffered stdout
        STDERR->autoflush(1);

        local $SIG{__DIE__}  = sub {
            return if $^S;
            my $message = join '', @_;
            chomp $message;
            $message =~ s/\s+at\s+\S+\s+line\s+\d+\.?$//;
            print STDERR "FATAL: $message\n";
            exit 1;
        };
        local $SIG{__WARN__} = sub { warn "WARN: @_" };

        BEGIN {
            printf STDERR "balance starting: perl %s on %s\n", $], $^O;
        }

        my $empty = '';
        my $threshold = 20;
        my $max_size = 0;
        my $max_moves = 0;
        my $plan_file = '';
        my $input_plan_file = '';
        my $manifest_file = '';
        my $apply = 0;
        my $dry_run = 0;
        my $log_file = '';
        my $verbose = 0;
        my $help = 0;
        my @MOUNTS;
        my $mount_override = 0;

        Configure('pass_through');
        GetOptionsFromArray(
            \@argv,
            'help|h'      => \$help,
            'empty=s'     => \$empty,
            'threshold=f' => \$threshold,
            'max-size=i'  => \$max_size,
            'max-moves=i' => \$max_moves,
            'plan-file=s' => \$plan_file,
            'input-plan-file=s' => \$input_plan_file,
            'manifest-file=s' => \$manifest_file,
            'apply|execute' => \$apply,
            'dry-run'     => \$dry_run,
            'log-file=s'  => \$log_file,
            'verbose'     => \$verbose,
            'mount=s@'    => sub {
                @MOUNTS = () unless $mount_override++;
                push @MOUNTS, $_[1];
            },
        ) or _cli_usage(2, "Invalid options.");

        _cli_usage(0) if $help;
        _cli_usage(2, "--threshold must be >= 0") if $threshold < 0;
        _cli_usage(2, "--threshold must be <= 100") if $threshold > 100;
        $apply = 1 if $dry_run;
        _cli_usage(2, "--input-plan-file requires --apply or --dry-run") if $input_plan_file && !$apply;

        if (!$log_file) {
            if ($plan_file && $plan_file =~ m{^(.*/)[^/]+$}) {
                $log_file = $1 . 'balance-plan.log';
            } elsif (-d '/artifacts') {
                $log_file = '/artifacts/balance-plan.log';
            } else {
                $log_file = 'balance-plan.log';
            }
        }

        my $output_stamp = output_timestamp();
        $plan_file = stamp_output_path($plan_file, $output_stamp) if $plan_file;
        $log_file = stamp_output_path($log_file, $output_stamp) if $log_file;
        $manifest_file = stamp_output_path($manifest_file, $output_stamp) if $manifest_file;

        my $max_size_kb = $max_size ? $max_size * (1024 * 1024) : 0;

        # Parse input plan or generate new one
        my @moves;
        my $planning_lf;
        if ($log_file) {
            open $planning_lf, '>>', $log_file or die "Can't open log file $log_file: $!\n";
            $planning_lf->autoflush(1);
            printf {$planning_lf} "=== %s started %s ===\n",
                ($input_plan_file ? 'PLAN INPUT' : 'PLAN'),
                log_ts();
        }

        if ($input_plan_file) {
            @moves = @{ load_moves_from_plan_file($input_plan_file) };
            my $message = sprintf "Loaded %d move(s) from saved plan file: %s\n",
                scalar(@moves), $input_plan_file;
            print $message;
            print {$planning_lf} $message if $planning_lf;
        } else {
            if (!@MOUNTS) {
                die "At least two mounts must be provided via --mount=/path\n";
            }
            for my $mnt (@MOUNTS) {
                unless (validate_media_path($mnt)) {
                    die "Invalid mount path: $mnt\n";
                }
            }
            _cli_usage(2, "At least two mounts are required") if @MOUNTS < 2;

            # Scan volumes
            my $planner = __PACKAGE__->new(
                threshold   => $threshold,
                max_size_kb => $max_size_kb,
                max_moves   => $max_moves,
                drain_mount => $empty,
            );

            my $scanner = Balance::VolumeScanner->new(cache_path => '');
            printf STDERR "[%s] Scanning %d mount(s) for current usage...\n", log_ts(), scalar @MOUNTS;
            print {$planning_lf} "[" . log_ts() . "] Scanning " . scalar(@MOUNTS) . " mount(s) for current usage...\n" if $planning_lf;

            my $vol = $scanner->scan(\@MOUNTS, log_fh => $planning_lf);

            # Prune mounts that didn't scan
            @MOUNTS = grep { exists $vol->{$_} } @MOUNTS;
            die "No usable mounts found. Check your volume mappings.\n" unless @MOUNTS;

            printf STDERR "Loaded %d volumes: %s\n", scalar @MOUNTS, join(', ', @MOUNTS);

            # Generate move plan
            @moves = @{ $planner->plan_moves($vol, @MOUNTS) };

            if ($plan_file && @moves) {
                open my $pf, '>', $plan_file or die "Can't write plan file $plan_file: $!\n";
                print {$pf} "#!/usr/bin/env bash\n";
                print {$pf} "set -euo pipefail\n\n";
                for my $m (@moves) {
                    printf {$pf} "# %s (%s KB)\n", $m->{show}, $m->{size};
                    my $safe = $m->{show};
                    $safe =~ s/'/'\\''/g;
                    my $cmd = sprintf "rsync -avP --remove-source-files '%s/%s/' '%s/%s'",
                        $m->{from}, $safe, $m->{to}, $safe;
                    printf {$pf} "%s\n\n", $cmd;
                }
                close $pf;
                chmod 0755, $plan_file;
                printf "Saved plan file: %s\n", $plan_file;
                printf {$planning_lf} "Saved plan file: %s\n", $plan_file if $planning_lf;
            } elsif (!@moves) {
                if ($plan_file) {
                    open my $pf, '>', $plan_file or die "Can't write plan file $plan_file: $!\n";
                    print {$pf} "#!/usr/bin/env bash\n";
                    printf {$pf} "# No moves required for minimum-free target (%.1f%%).\n", $threshold;
                    close $pf;
                    chmod 0755, $plan_file;
                    printf "Saved plan file: %s\n", $plan_file;
                    printf {$planning_lf} "Saved plan file: %s\n", $plan_file if $planning_lf;
                }
                printf "No moves required for minimum-free target (%.1f%%).\n", $threshold;
                printf {$planning_lf} "No moves required for minimum-free target (%.1f%%).\n", $threshold if $planning_lf;
            }

            if ($planning_lf) {
                printf {$planning_lf} "=== PLAN ended %s ===\n", log_ts();
                close $planning_lf;
            }

            exit 0 unless $apply;
        }

        # Apply moves
        if ($apply) {
            my $planner = __PACKAGE__->new(
                threshold   => $threshold,
                max_size_kb => $max_size_kb,
                max_moves   => $max_moves,
                drain_mount => $empty,
            );

            my $mode_label = $dry_run ? 'DRY-RUN' : 'APPLY';
            printf "\n=== %s MODE: %d planned move(s) ===\n", $mode_label, scalar @moves;
            print "    (no files will be moved)\n" if $dry_run;

            my $result = $planner->apply(\@moves,
                dry_run => $dry_run,
                log_file => $log_file,
                manifest_file => $manifest_file,
            );

            exit($result->{failed} ? 1 : 0);
        }

        return 0;
    }

    sub _cli_usage($exit_code, $error) {
        print STDERR "$error\n\n" if defined $error && length $error;
        print <<"USAGE";
Usage: balance [options]

Plan media folder moves across mounts to balance storage use.
This script prints rsync commands; it does not execute them.

Options:
  --empty=/path        Drain this mount by setting its target media to 0.
                       Example: --empty=/media-extra

  --threshold=N        Keep at least N% free space on each target volume.
                       Default: 20

  --max-size=N         Skip shows larger than N GB (0 = no size limit).
                       Default: 0

  --max-moves=N        Stop after planning N moves (0 = no limit).
                       Default: 0

  --plan-file=/path    Save generated rsync move commands to this file.

  --input-plan-file=/path
                       Execute a previously generated plan file for --apply or
                       --dry-run instead of recalculating a new plan.

  --manifest-file=/path
                       Append JSONL records for successful APPLY moves.

  --apply, --execute   Apply the generated move plan immediately using rsync.

  --dry-run            Run rsync with -n (no files moved; shows what would happen).
                       Implies --apply.

  --log-file=/path     Write planner/apply output to this file (appended each run).

  --mount=/path        Mount to include. Repeat to define custom mount list.
                       This is required when running balance directly.

  --verbose            Print each selected move during planning.

  --help, -h           Show this help message and exit.

Examples:
  balance
  balance --threshold=30 --max-size=50
  balance --plan-file=/artifacts/balance-plan.sh
  balance --apply --log-file=/artifacts/balance-apply.log
  balance --dry-run
  balance --empty=/media-extra
  balance --mount=/media --mount=/media2 --mount=/media3 --verbose
USAGE
        exit $exit_code;
    }

    # Private helper to get current TV size for a mount
    method _current_tv_kb($vol, $mount) {
        my $tv_kb = 0;
        $tv_kb += $_ for values %{ $vol->{$mount}{dirs} // {} };
        return $tv_kb;
    }
}

unless (caller) {
    exit Balance::Planner::cli_main(@ARGV);
}

1;

=head1 NAME

Balance::Planner - Plan and apply media rebalancing across storage mounts

=head1 SYNOPSIS

  my $planner = Balance::Planner->new(
      threshold   => 20,
      max_size_kb => 0,
      max_moves   => 0,
      drain_mount => '',
  );
  my $vol = $planner->get_volumes(@mounts);
  my $moves = $planner->plan_moves($vol, @mounts);
  my $result = $planner->apply($moves, dry_run => 0, log_file => '...');

  Balance::Planner::cli_main(@ARGV);

=head1 DESCRIPTION

Computes an optimal plan for moving TV show directories across multiple
storage mounts to balance disk usage, enforcing minimum free-space
requirements. Moves are recorded to the Balance apply manifest for
subsequent Sonarr and Plex reconciliation.

=head1 LICENSE

Copyright (C) 2026 Sam Robertson. This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
