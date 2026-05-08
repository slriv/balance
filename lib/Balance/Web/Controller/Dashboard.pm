package Balance::Web::Controller::Dashboard;

use v5.42;
use Mojo::Base 'Mojolicious::Controller', -signatures;

our $VERSION = '0.01';
our $VOLUME_CACHE_TTL = $ENV{BALANCE_VOLUME_CACHE_TTL} // 900;
our %VOLUME_REFRESH_STATE;

use Balance::Config ();
use Balance::Core qw(dir_size_kb fmt pct_fmt);
use File::Spec ();
use JSON::PP ();
use Mojo::IOLoop ();
use Mojo::IOLoop::Subprocess ();
use POSIX qw(strftime);

sub index ($c) {
    my $config = $c->balance_config;
    my @mounts = $config->media_mounts;
    my $vol = _load_volume_state($c, \@mounts);
    my $jobs = $c->job_store->recent_jobs(limit => 10);
    my $volume_refresh_pending = grep { $vol->{$_}{refreshing} } @mounts;
    my $available_plans = _available_balance_plans($c);
    $c->render(
        template               => 'dashboard/index',
        mounts                 => \@mounts,
        mount_entries          => $config->media_paths,
        vol                    => $vol,
        jobs                   => $jobs,
        available_plans        => $available_plans,
        balance_plan_output_default => $config->balance_plan_file,
        balance_plan_log_default    => $config->balance_plan_log,
        balance_apply_log_default   => $config->balance_apply_log,
        balance_manifest_default    => $config->manifest_file,
        volume_refresh_pending => $volume_refresh_pending,
    );
    return;
}

sub plan ($c) {
    my @mounts = _selected_balance_mounts($c);
    return $c->render(text => 'At least 2 media paths are required', status => 400) unless @mounts >= 2;

    my $job_id = $c->new_job_id('balance-plan');
    my @args = _balance_plan_args($c, \@mounts);
    return unless @args;

    _start_balance_job($c,
        job_id   => $job_id,
        job_type => 'balance_plan',
        cmd      => [$c->cli_command('balance', @args)],
    );
    return;
}

sub dry_run ($c) {
    my $plan = _selected_balance_plan($c) or return;

    my $job_id = $c->new_job_id('balance-dry-run');
    my @args = _saved_plan_args($c, $plan->{path}, mode => 'dry-run');
    _start_balance_job($c,
        job_id   => $job_id,
        job_type => 'balance_dry_run',
        cmd      => [$c->cli_command('balance', @args)],
    );
    return;
}

sub apply ($c) {
    my $plan = _selected_balance_plan($c) or return;

    my $job_id = $c->new_job_id('balance-apply');
    my @args = _saved_plan_args($c, $plan->{path}, mode => 'apply');
    _start_balance_job($c,
        job_id   => $job_id,
        job_type => 'balance_apply',
        cmd      => [$c->cli_command('balance', @args)],
    );
    return;
}

sub _load_volume_state($c, $mounts) {
    my $cache_path = $c->balance_config->dashboard_volume_cache_file;
    my $cache = _read_volume_cache($cache_path);
    my $now = time;
    my $ttl = $VOLUME_CACHE_TTL;

    my %active = map { $_ => 1 } @$mounts;
    my $changed = 0;
    for my $cached_mount (keys %{ $cache->{mounts} }) {
        next if $active{$cached_mount};
        delete $cache->{mounts}{$cached_mount};
        $changed = 1;
    }

    my %vol;
    my @refresh_mounts;
    for my $mount (@$mounts) {
        my $entry = $cache->{mounts}{$mount};
        if ($entry
            && defined $entry->{used_kb}
            && defined $entry->{updated_at}
            && ($now - $entry->{updated_at}) <= $ttl) {
            $vol{$mount} = _volume_state_entry($entry, cached => 1);
            next;
        }

        push @refresh_mounts, $mount;

        if ($entry && defined $entry->{used_kb}) {
            $vol{$mount} = _volume_state_entry($entry,
                cached     => 1,
                stale      => 1,
                refreshing => 1,
            );
            next;
        }

        $vol{$mount} = _volume_state_entry(undef, refreshing => 1);
    }

    _write_volume_cache($cache_path, $cache) if $changed;
    _schedule_volume_refresh($c, $cache_path, \@refresh_mounts) if @refresh_mounts;
    return \%vol;
}

sub _volume_state_entry($entry, %opts) {
    my $used_kb = $entry && defined $entry->{used_kb} ? $entry->{used_kb} : undef;
    my $updated_at = $entry && defined $entry->{updated_at} ? $entry->{updated_at} : undef;

    return {
        used_kb    => $used_kb,
        fmt        => defined $used_kb ? fmt($used_kb, 1024 * 1024) : 'Refreshing...',
        updated_at => $updated_at,
        updated_fmt => defined $updated_at
            ? strftime('%Y-%m-%d %H:%M:%S UTC', gmtime($updated_at))
            : ($opts{refreshing} ? 'Pending background refresh' : 'Unknown'),
        cached     => $opts{cached} ? !!1 : !!0,
        stale      => $opts{stale} ? !!1 : !!0,
        refreshing => $opts{refreshing} ? !!1 : !!0,
    };
}

sub _schedule_volume_refresh($c, $cache_path, $mounts) {
    return unless defined $cache_path && length $cache_path;
    return unless $mounts && @$mounts;

    my $state = ($VOLUME_REFRESH_STATE{$cache_path} //= {
        pending       => {},
        running       => 0,
        running_mount => undef,
    });

    for my $mount (@$mounts) {
        next unless defined $mount && length $mount;
        next if $state->{pending}{$mount};
        next if defined $state->{running_mount} && $state->{running_mount} eq $mount;
        $state->{pending}{$mount} = 1;
    }

    _run_next_volume_refresh($c->app, $cache_path) unless $state->{running};
    return;
}

sub _run_next_volume_refresh($app, $cache_path) {
    my $state = $VOLUME_REFRESH_STATE{$cache_path} or return;
    my ($mount) = sort keys %{ $state->{pending} };

    unless (defined $mount) {
        delete $VOLUME_REFRESH_STATE{$cache_path};
        return;
    }

    delete $state->{pending}{$mount};
    $state->{running} = 1;
    $state->{running_mount} = $mount;

    my $subprocess = $state->{subprocess} = Mojo::IOLoop::Subprocess->new;
    $subprocess->run(
        sub ($subprocess) {
            return {
                mount      => $mount,
                used_kb    => dir_size_kb($mount),
                updated_at => time,
            };
        },
        sub ($subprocess, $err, $result) {
            delete $state->{subprocess};

            if ($err) {
                $app->log->error("dashboard volume refresh failed for $mount: $err");
            } elsif (ref $result eq 'HASH' && defined $result->{mount}) {
                _apply_volume_refresh_result(
                    $cache_path,
                    $result->{mount},
                    $result->{used_kb},
                    $result->{updated_at},
                );
            }

            $state->{running} = 0;
            $state->{running_mount} = undef;
            _run_next_volume_refresh($app, $cache_path);
        },
    );

    return;
}

sub _apply_volume_refresh_result($cache_path, $mount, $used_kb, $updated_at = time) {
    return unless defined $cache_path && length $cache_path;
    return unless defined $mount && length $mount;

    my $cache = _read_volume_cache($cache_path);
    $cache->{mounts}{$mount} = {
        used_kb    => $used_kb,
        updated_at => $updated_at,
    };
    _write_volume_cache($cache_path, $cache);
    return;
}

sub _read_volume_cache($path) {
    return { mounts => {} } unless defined $path && length $path && -f $path;

    open my $fh, '<', $path or return { mounts => {} };
    local $/;
    my $json = <$fh>;
    close $fh;

    return { mounts => {} } unless defined $json && length $json;

    my $data = eval { JSON::PP->new->utf8->decode($json) };
    return { mounts => {} } if $@ || ref $data ne 'HASH';
    $data->{mounts} = {} unless ref $data->{mounts} eq 'HASH';
    return $data;
}

sub _write_volume_cache($path, $cache) {
    return unless defined $path && length $path;

    Balance::Config::ensure_parent_dir($path);

    my $tmp = "$path.$$\.tmp";
    open my $fh, '>', $tmp or return;
    print {$fh} JSON::PP->new->utf8->canonical->encode($cache);
    close $fh or do {
        unlink $tmp;
        return;
    };

    rename $tmp, $path or unlink $tmp;
    return;
}

sub _balance_plan_args($c, $mounts) {
    my $threshold = $c->param('threshold') // 20;
    $threshold = 20 unless $threshold =~ /^\d+(?:\.\d+)?$/;

    my $max_size = $c->param('max_size') // '';
    my $max_moves = $c->param('max_moves') // '';
    my $empty_mount = $c->param('empty_mount') // '';
    my $plan_output_file = _path_override_or_default($c, 'plan_output_file', $c->balance_config->balance_plan_file);
    my $plan_log_file = _path_override_or_default($c, 'plan_log_file', $c->balance_config->balance_plan_log);

    my @args = (
        "--threshold=$threshold",
        "--plan-file=$plan_output_file",
        "--log-file=$plan_log_file",
    );

    push @args, "--max-size=$max_size"
        if $max_size =~ /^\d+$/ && $max_size > 0;

    push @args, "--max-moves=$max_moves"
        if $max_moves =~ /^\d+$/ && $max_moves > 0;

    if (defined $empty_mount && length $empty_mount) {
        unless (grep { $_ eq $empty_mount } @{$mounts}) {
            $c->render(text => 'Selected drain mount must be one of the included mounts', status => 400);
            return;
        }
        push @args, "--empty=$empty_mount";
    }

    push @args, '--verbose' if $c->param('verbose');
    push @args, map { '--mount=' . $_ } @{$mounts};

    return @args;
}

sub _saved_plan_args($c, $selected_plan, %opts) {
    my $manifest_file = _path_override_or_default($c, 'manifest_file', $c->balance_config->manifest_file);
    my $apply_log_file = _path_override_or_default($c, 'apply_log_file', $c->balance_config->balance_apply_log);
    my @args = (
        "--input-plan-file=$selected_plan",
        "--manifest-file=$manifest_file",
        "--log-file=$apply_log_file",
    );

    push @args, $opts{mode} eq 'dry-run' ? '--dry-run' : '--apply';
    return @args;
}

sub _selected_balance_mounts($c) {
    my @requested = map {
        ref $_ eq 'ARRAY' ? @$_ : $_
    } $c->every_param('mount[]');
    @requested = grep { defined $_ && !ref $_ && length $_ } @requested;

    unless (@requested) {
        @requested = map {
            ref $_ eq 'ARRAY' ? @$_ : $_
        } $c->every_param('mount');
        @requested = grep { defined $_ && !ref $_ && length $_ } @requested;
    }

    my @configured = map { $_->{path} }
        grep { defined $_->{path} && length $_->{path} }
        @{ $c->balance_config->media_paths };

    my @mounts = @requested ? @requested : @configured;
    my %allowed = map { $_ => 1 } @configured;
    my %seen;
    return grep { $allowed{$_} && !$seen{$_}++ } @mounts;
}

sub _available_balance_plans($c) {
    my $artifact_root = $c->balance_config->artifact_root;
    return [] unless defined $artifact_root && length $artifact_root && -d $artifact_root;

    opendir my $dh, $artifact_root or return [];
    my @plans;
    while (my $entry = readdir $dh) {
        next unless $entry =~ /\Abalance-plan(?:-\d{8}-\d{6})?\.sh\z/;

        my $path = File::Spec->catfile($artifact_root, $entry);
        next unless -f $path;

        my @stat = stat $path;
        push @plans, {
            name         => $entry,
            path         => $path,
            modified_at  => $stat[9] // 0,
            modified_fmt => strftime('%Y-%m-%d %H:%M:%S UTC', gmtime($stat[9] // 0)),
            size_bytes   => $stat[7] // 0,
            size_fmt     => _format_plan_size($stat[7] // 0),
        };
    }
    closedir $dh;

    return [ sort {
        ($b->{modified_at} <=> $a->{modified_at})
            || ($a->{name} cmp $b->{name})
    } @plans ];
}

sub _selected_balance_plan($c) {
    my $selected_path = $c->param('selected_plan_file') // '';
    unless (length $selected_path) {
        $c->render(text => 'Select a saved plan file before running dry-run or apply', status => 400);
        return;
    }

    my ($plan) = grep { $_->{path} eq $selected_path } @{ _available_balance_plans($c) };
    unless ($plan) {
        $c->render(text => 'Selected plan file is unavailable or outside the artifact root', status => 400);
        return;
    }

    return $plan;
}

sub _path_override_or_default($c, $param_name, $default_path) {
    my $value = $c->param($param_name) // '';
    return $value if length $value;
    return $default_path;
}

sub _format_plan_size($bytes) {
    return sprintf('%.1f GiB', $bytes / (1024 ** 3)) if $bytes >= 1024 ** 3;
    return sprintf('%.1f MiB', $bytes / (1024 ** 2)) if $bytes >= 1024 ** 2;
    return sprintf('%.1f KiB', $bytes / 1024) if $bytes >= 1024;
    return "$bytes B";
}

sub _start_balance_job($c, %opts) {
    my $job_id   = $opts{job_id};
    my $job_type = $opts{job_type};
    my @cmd      = @{ $opts{cmd} // [] };

    my $store = $c->job_store;
    try { $store->insert_job($job_id, $job_type) }
    catch ($e) {
        $c->render(text => "Cannot start: $e", status => 409);
        return;
    }

    $store->update_job($job_id,
        status     => 'running',
        started_at => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime),
    );

    $c->job_runner->start_job($job_id, @cmd,
        sub ($result) {
            my $job = $store->get_job($job_id) or return;
            return unless ($job->{status} // '') eq 'running';
            $store->update_job($job_id,
                status      => $result->{success} ? 'done' : 'failed',
                finished_at => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime),
            );
        },
    );

    $c->redirect_to("/jobs/$job_id");
    return;
}

1;

__END__

=head1 NAME

Balance::Web::Controller::Dashboard - Balance dashboard controller

=head1 DESCRIPTION

Handles the main dashboard page and plan/dry-run/apply job submission.

=head1 LICENSE

Copyright (C) 2026 Sam Robertson. This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
