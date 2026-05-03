package Balance::Web::Controller::Sonarr;

use v5.42;
use Mojo::Base 'Mojolicious::Controller', -signatures;

our $VERSION = '0.01';
use POSIX qw(strftime);

sub index ($c) {
    $c->render(template => 'sonarr/index');
    return;
}

sub _require_sonarr_config ($c) {
    my $ac = $c->balance_config;
    unless ($ac->has_sonarr) {
        $c->render(text => 'Sonarr configuration is incomplete: base URL and API key are required', status => 400);
        return;
    }
    return $ac;
}

sub plan ($c) {
    # Plan only needs manifest + path-map; Sonarr credentials are not required
    my $ac = $c->balance_config;
    my $job_id = $c->new_job_id('sonarr-plan');
    my $store = $c->job_store;
    try { $c->job_store->insert_job($job_id, 'sonarr_plan') }
    catch ($e) {
        $c->render(text => "Cannot start: $e", status => 409);
        return;
    }
    $c->job_store->update_job($job_id,
        status     => 'running',
        started_at => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime),
    );
    $c->job_runner->start_job($job_id,
        'sonarr_reconcile.pl',
        '--manifest-file=' . $ac->manifest_file,
        '--path-map-file=' . $ac->sonarr_path_map_file,
        '--report-file='   . $ac->sonarr_report_file,
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
    my $ac = $c->_require_sonarr_config or return;
    my $job_id = $c->new_job_id('sonarr-dry-run');
    my $store = $c->job_store;
    try { $c->job_store->insert_job($job_id, 'sonarr_dry_run') }
    catch ($e) {
        $c->render(text => "Cannot start: $e", status => 409);
        return;
    }
    $c->job_store->update_job($job_id,
        status     => 'running',
        started_at => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime),
    );
    $c->job_runner->start_job($job_id,
        'sonarr_reconcile.pl', 'dry-run',
        '--base-url=' . $ac->sonarr_url,
        '--api-key='  . $ac->sonarr_api_key,
        '--report-file=' . $ac->sonarr_report_file,
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
    my $ac = $c->_require_sonarr_config or return;
    my $job_id = $c->new_job_id('sonarr-apply');
    my $store = $c->job_store;
    try { $c->job_store->insert_job($job_id, 'sonarr_apply') }
    catch ($e) {
        $c->render(text => "Cannot start: $e", status => 409);
        return;
    }
    $c->job_store->update_job($job_id,
        status     => 'running',
        started_at => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime),
    );
    $c->job_runner->start_job($job_id,
        'sonarr_reconcile.pl', 'apply',
        '--base-url=' . $ac->sonarr_url,
        '--api-key='  . $ac->sonarr_api_key,
        '--report-file=' . $ac->sonarr_report_file,
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

sub audit ($c) {
    my $ac = $c->_require_sonarr_config or return;
    my $job_id = $c->new_job_id('sonarr-audit');
    my $store = $c->job_store;
    try { $c->job_store->insert_job($job_id, 'sonarr_audit') }
    catch ($e) {
        $c->render(text => "Cannot start: $e", status => 409);
        return;
    }
    $c->job_store->update_job($job_id,
        status     => 'running',
        started_at => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime),
    );
    $c->job_runner->start_job($job_id,
        'sonarr_reconcile.pl', 'audit',
        '--base-url=' . $ac->sonarr_url,
        '--api-key='  . $ac->sonarr_api_key,
        '--report-file=' . $ac->sonarr_audit_report_file,
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

sub repair ($c) {
    my $ac = $c->_require_sonarr_config or return;
    my $job_id = $c->new_job_id('sonarr-repair');
    my $store = $c->job_store;
    try { $c->job_store->insert_job($job_id, 'sonarr_repair') }
    catch ($e) {
        $c->render(text => "Cannot start: $e", status => 409);
        return;
    }
    $c->job_store->update_job($job_id,
        status     => 'running',
        started_at => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime),
    );
    $c->job_runner->start_job($job_id,
        'sonarr_reconcile.pl', 'repair',
        '--base-url=' . $ac->sonarr_url,
        '--api-key='  . $ac->sonarr_api_key,
        '--report-file=' . $ac->sonarr_audit_report_file,
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

Balance::Web::Controller::Sonarr - Sonarr reconcile UI controller

=head1 DESCRIPTION

Handles Sonarr reconcile plan/dry-run/apply, series audit, and repair job
submission for the Balance web UI.

=head1 LICENSE

Copyright (C) 2026 Sam Robertson. This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
