package Balance::Web::Controller::Plex;

use v5.42;
use Mojo::Base 'Mojolicious::Controller', -signatures;

our $VERSION = '0.01';
use POSIX qw(strftime);

sub index ($c) {
    $c->render(template => 'plex/index');
    return;
}

sub _require_plex_config ($c) {
    my $ac = $c->balance_config;
    unless ($ac->has_plex) {
        $c->render(text => 'Plex configuration is incomplete: base URL and token are required', status => 400);
        return;
    }
    return $ac;
}

sub plan ($c) {
    # Plan only needs manifest + path-map; Plex credentials are not required
    my $ac = $c->balance_config;
    my $job_id = $c->new_job_id('plex-plan');
    my $store  = $c->job_store;
    try { $c->job_store->insert_job($job_id, 'plex_plan') }
    catch ($e) {
        $c->render(text => "Cannot start: $e", status => 409);
        return;
    }
    $c->job_store->update_job($job_id,
        status     => 'running',
        started_at => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime),
    );
    $c->job_runner->start_job($job_id,
        'plex_reconcile.pl',
        '--manifest-file=' . $ac->manifest_file,
        '--path-map-file=' . $ac->plex_path_map_file,
        '--report-file='   . $ac->plex_report_file,
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

sub dry_run ($c) {
    my $ac = $c->_require_plex_config or return;
    my $job_id = $c->new_job_id('plex-dry-run');
    my $store  = $c->job_store;
    try { $c->job_store->insert_job($job_id, 'plex_dry_run') }
    catch ($e) {
        $c->render(text => "Cannot start: $e", status => 409);
        return;
    }
    $c->job_store->update_job($job_id,
        status     => 'running',
        started_at => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime),
    );
    $c->job_runner->start_job($job_id,
        'plex_reconcile.pl', 'dry-run',
        '--base-url=' . $ac->plex_url,
        '--token='    . $ac->plex_token,
        '--report-file=' . $ac->plex_report_file,
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

sub apply ($c) {
    my $ac = $c->_require_plex_config or return;
    my $job_id = $c->new_job_id('plex-apply');
    my $store  = $c->job_store;
    try { $c->job_store->insert_job($job_id, 'plex_apply') }
    catch ($e) {
        $c->render(text => "Cannot start: $e", status => 409);
        return;
    }
    $c->job_store->update_job($job_id,
        status     => 'running',
        started_at => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime),
    );
    $c->job_runner->start_job($job_id,
        'plex_reconcile.pl', 'apply',
        '--base-url=' . $ac->plex_url,
        '--token='    . $ac->plex_token,
        '--report-file=' . $ac->plex_report_file,
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

sub scan ($c) {
    my $ac     = $c->_require_plex_config or return;
    my $lib_id = $c->param('library_id') // '';
    my $job_id = $c->new_job_id('plex-scan');
    my $store  = $c->job_store;
    try { $c->job_store->insert_job($job_id, 'plex_scan') }
    catch ($e) {
        $c->render(text => "Cannot start: $e", status => 409);
        return;
    }
    $c->job_store->update_job($job_id,
        status     => 'running',
        started_at => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime),
    );
    my @cmd = (
        'plex_reconcile.pl', 'scan',
        '--base-url=' . $ac->plex_url,
        '--token='    . $ac->plex_token,
    );
    push @cmd, "--library-id=$lib_id" if length $lib_id;
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

sub empty_trash ($c) {
    my $ac     = $c->_require_plex_config or return;
    my $lib_id = $c->param('library_id') // '';
    my $job_id = $c->new_job_id('plex-trash');
    my $store  = $c->job_store;
    try { $c->job_store->insert_job($job_id, 'plex_empty_trash') }
    catch ($e) {
        $c->render(text => "Cannot start: $e", status => 409);
        return;
    }
    $c->job_store->update_job($job_id,
        status     => 'running',
        started_at => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime),
    );
    my @cmd = (
        'plex_reconcile.pl', 'empty-trash',
        '--base-url=' . $ac->plex_url,
        '--token='    . $ac->plex_token,
    );
    push @cmd, "--library-id=$lib_id" if length $lib_id;
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

Balance::Web::Controller::Plex - Plex reconcile UI controller

=head1 DESCRIPTION

Handles Plex reconcile plan/dry-run/apply, library scan, and empty-trash
job submission for the Balance web UI.

=head1 LICENSE

Copyright (C) 2026 Sam Robertson. This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
