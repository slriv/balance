package Balance::Web::Controller::Sonarr;

use v5.38;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use Balance::Config qw(service_defaults load_env_file);
use POSIX qw(strftime);

sub index ($c) {
    $c->render(template => 'sonarr/index');
    return;
}

sub apply ($c) {
    load_env_file('.env');
    my $defs = service_defaults('sonarr');
    my $job_id = $c->new_job_id('sonarr-apply');
    eval { $c->job_store->insert_job($job_id, 'sonarr_apply') };
    if ($@) {
        $c->render(text => "Cannot start: $@", status => 409);
        return;
    }
    $c->job_store->update_job($job_id,
        status     => 'running',
        started_at => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime),
    );
    $c->job_runner->start_job($job_id,
        'sonarr_reconcile', 'apply',
        "--report-file=$defs->{report_file}",
    );
    $c->redirect_to("/jobs/$job_id");
    return;
}

sub audit ($c) {
    load_env_file('.env');
    my $audit_file = $ENV{SONARR_AUDIT_REPORT_FILE} || '/artifacts/sonarr-audit-report.json';
    my $job_id = $c->new_job_id('sonarr-audit');
    eval { $c->job_store->insert_job($job_id, 'sonarr_audit') };
    if ($@) {
        $c->render(text => "Cannot start: $@", status => 409);
        return;
    }
    $c->job_store->update_job($job_id,
        status     => 'running',
        started_at => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime),
    );
    $c->job_runner->start_job($job_id,
        'sonarr_reconcile', 'audit',
        "--report-file=$audit_file",
    );
    $c->redirect_to("/jobs/$job_id");
    return;
}

sub repair ($c) {
    load_env_file('.env');
    my $audit_file = $ENV{SONARR_AUDIT_REPORT_FILE} || '/artifacts/sonarr-audit-report.json';
    my $job_id = $c->new_job_id('sonarr-repair');
    eval { $c->job_store->insert_job($job_id, 'sonarr_repair') };
    if ($@) {
        $c->render(text => "Cannot start: $@", status => 409);
        return;
    }
    $c->job_store->update_job($job_id,
        status     => 'running',
        started_at => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime),
    );
    $c->job_runner->start_job($job_id,
        'sonarr_reconcile', 'repair',
        "--report-file=$audit_file",
    );
    $c->redirect_to("/jobs/$job_id");
    return;
}

1;
