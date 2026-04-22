package Balance::Web::Controller::Sonarr;

use v5.42;
use Mojo::Base 'Mojolicious::Controller', -signatures;

our $VERSION = '0.01';
use Balance::Config qw(service_defaults load_env_file);
use POSIX qw(strftime);

sub index ($c) {
    $c->render(template => 'sonarr/index');
    return;
}

sub plan ($c) {
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
        'sonarr_reconcile',
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
    load_env_file('.env');
    my $defs = service_defaults('sonarr');
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
        'sonarr_reconcile', 'dry-run',
        "--report-file=$defs->{report_file}",
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
    load_env_file('.env');
    my $defs = service_defaults('sonarr');
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
        'sonarr_reconcile', 'apply',
        "--report-file=$defs->{report_file}",
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
    load_env_file('.env');
    my $defs = service_defaults('sonarr');
    my $audit_file = $defs->{audit_report_file};
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
        'sonarr_reconcile', 'audit',
        "--report-file=$audit_file",
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
    load_env_file('.env');
    my $defs = service_defaults('sonarr');
    my $audit_file = $defs->{audit_report_file};
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
        'sonarr_reconcile', 'repair',
        "--report-file=$audit_file",
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

Copyright (C) 2026 Sam Robertson. GNU General Public License v3 or later.

=cut
