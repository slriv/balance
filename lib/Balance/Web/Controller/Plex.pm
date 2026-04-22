package Balance::Web::Controller::Plex;

use v5.38;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use Balance::Config qw(service_defaults load_env_file);
use POSIX qw(strftime);

sub index ($c) {
    $c->render(template => 'plex/index');
    return;
}

sub plan ($c) {
    my $job_id = $c->new_job_id('plex-plan');
    my $store  = $c->job_store;
    eval { $c->job_store->insert_job($job_id, 'plex_plan') };
    if ($@) {
        $c->render(text => "Cannot start: $@", status => 409);
        return;
    }
    $c->job_store->update_job($job_id,
        status     => 'running',
        started_at => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime),
    );
    $c->job_runner->start_job($job_id,
        'plex_reconcile',
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
    my $defs = service_defaults('plex');
    my $job_id = $c->new_job_id('plex-dry-run');
    my $store  = $c->job_store;
    eval { $c->job_store->insert_job($job_id, 'plex_dry_run') };
    if ($@) {
        $c->render(text => "Cannot start: $@", status => 409);
        return;
    }
    $c->job_store->update_job($job_id,
        status     => 'running',
        started_at => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime),
    );
    $c->job_runner->start_job($job_id,
        'plex_reconcile', 'dry-run',
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
    my $defs = service_defaults('plex');
    my $job_id = $c->new_job_id('plex-apply');
    my $store  = $c->job_store;
    eval { $c->job_store->insert_job($job_id, 'plex_apply') };
    if ($@) {
        $c->render(text => "Cannot start: $@", status => 409);
        return;
    }
    $c->job_store->update_job($job_id,
        status     => 'running',
        started_at => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime),
    );
    $c->job_runner->start_job($job_id,
        'plex_reconcile', 'apply',
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

sub scan ($c) {
    load_env_file('.env');
    my $lib_id  = $c->param('library_id') // '';
    my $job_id  = $c->new_job_id('plex-scan');
    my $store   = $c->job_store;
    eval { $c->job_store->insert_job($job_id, 'plex_scan') };
    if ($@) {
        $c->render(text => "Cannot start: $@", status => 409);
        return;
    }
    $c->job_store->update_job($job_id,
        status     => 'running',
        started_at => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime),
    );
    my @cmd = ('plex_reconcile', 'scan');
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
    load_env_file('.env');
    my $lib_id = $c->param('library_id') // '';
    my $job_id = $c->new_job_id('plex-trash');
    my $store  = $c->job_store;
    eval { $c->job_store->insert_job($job_id, 'plex_empty_trash') };
    if ($@) {
        $c->render(text => "Cannot start: $@", status => 409);
        return;
    }
    $c->job_store->update_job($job_id,
        status     => 'running',
        started_at => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime),
    );
    my @cmd = ('plex_reconcile', 'empty-trash');
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
