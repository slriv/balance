package Balance::Web::Controller::Dashboard;

use v5.42;
use Mojo::Base 'Mojolicious::Controller', -signatures;

our $VERSION = '0.01';
use Balance::Core qw(dir_size_kb fmt pct_fmt);
use POSIX qw(strftime);

sub index ($c) {
    my @mounts = $c->balance_config->media_mounts;
    my (%vol, @sizes);
    for my $m (@mounts) {
        my $used_kb = dir_size_kb($m);
        $vol{$m} = { used_kb => $used_kb, fmt => fmt($used_kb, 1024 * 1024) };
    }
    my $jobs = $c->job_store->recent_jobs(limit => 10);
    $c->render(
        template => 'dashboard/index',
        mounts   => \@mounts,
        vol      => \%vol,
        jobs     => $jobs,
    );
    return;
}

sub plan ($c) {
    my @mounts = $c->balance_config->media_mounts;
    return $c->render(text => 'At least 2 media paths are required', status => 400) unless @mounts >= 2;

    my $job_id = $c->new_job_id('balance-plan');
    my @args = _balance_args($c,
        log_file      => '/artifacts/balance-plan.log',
        include_apply => 0,
    );
    _start_balance_job($c,
        job_id   => $job_id,
        job_type => 'balance_plan',
        cmd      => ['balance', @args],
    );
    return;
}

sub dry_run ($c) {
    my @mounts = $c->balance_config->media_mounts;
    return $c->render(text => 'At least 2 media paths are required', status => 400) unless @mounts >= 2;

    my $job_id = $c->new_job_id('balance-dry-run');
    my @args = _balance_args($c,
        log_file      => '/artifacts/balance-apply.log',
        include_apply => 1,
    );
    push @args, '--dry-run';
    _start_balance_job($c,
        job_id   => $job_id,
        job_type => 'balance_dry_run',
        cmd      => ['balance', @args],
    );
    return;
}

sub apply ($c) {
    my @mounts = $c->balance_config->media_mounts;
    return $c->render(text => 'At least 2 media paths are required', status => 400) unless @mounts >= 2;

    my $job_id = $c->new_job_id('balance-apply');
    my @args = _balance_args($c,
        log_file      => '/artifacts/balance-apply.log',
        include_apply => 1,
    );
    push @args, '--apply';
    _start_balance_job($c,
        job_id   => $job_id,
        job_type => 'balance_apply',
        cmd      => ['balance', @args],
    );
    return;
}

sub _balance_args($c, %opts) {
    my $threshold = $c->param('threshold') // 20;
    $threshold = 20 unless $threshold =~ /^\d+(?:\.\d+)?$/;

    my $max_moves = $c->param('max_moves') // '';

    my @args = (
        "--threshold=$threshold",
        '--plan-file=/artifacts/balance-plan.sh',
        "--log-file=$opts{log_file}",
    );

    push @args, '--manifest-file=' . $c->balance_config->manifest_file
        if $opts{include_apply};

    push @args, "--max-moves=$max_moves"
        if $max_moves =~ /^\d+$/ && $max_moves > 0;

    for my $entry (@{ $c->balance_config->media_paths }) {
        next unless defined $entry->{path} && length $entry->{path};
        push @args, '--mount=' . $entry->{path};
    }

    return @args;
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
