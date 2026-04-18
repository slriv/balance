package Balance::Web::App;

use v5.38;
use Mojo::Base 'Mojolicious', -signatures;
use Balance::JobStore;
use Balance::JobRunner;

sub startup ($self) {
    # TODO: add HTTP Basic or token auth before any external exposure

    # Helpers — one instance per app object (isolated per Test::Mojo run)
    $self->helper(job_store => sub ($c) {
        return $c->app->{_job_store} //= Balance::JobStore->new(
            db_path => ($ENV{BALANCE_JOB_DB}      || '/artifacts/balance-jobs.db'),
            log_dir => ($ENV{BALANCE_JOB_LOG_DIR}  || '/artifacts/jobs'),
        );
    });

    $self->helper(job_runner => sub ($c) {
        return $c->app->{_job_runner} //= Balance::JobRunner->new(
            log_dir => ($ENV{BALANCE_JOB_LOG_DIR}  || '/artifacts/jobs'),
        );
    });

    # Generate a simple unique job ID from time + random digits
    $self->helper(new_job_id => sub ($c, $prefix = 'job') {
        return sprintf('%s-%d%04d', $prefix, time(), int(rand(9999)));
    });

    $self->routes->namespaces(['Balance::Web::Controller']);

    my $r = $self->routes;
    $r->get('/')->to('dashboard#index');

    $r->get('/jobs/:id')->to('jobs#show');
    $r->post('/jobs/:id/cancel')->to('jobs#cancel');
    $r->websocket('/jobs/:id/stream')->to('jobs#stream');

    $r->get('/sonarr')->to('sonarr#index');
    $r->post('/sonarr/apply')->to('sonarr#apply');
    $r->post('/sonarr/audit')->to('sonarr#audit');
    $r->post('/sonarr/repair')->to('sonarr#repair');

    $r->get('/plex')->to('plex#index');
    $r->post('/plex/scan')->to('plex#scan');
    $r->post('/plex/empty-trash')->to('plex#empty_trash');
    return;
}

1;
