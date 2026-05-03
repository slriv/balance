package Balance::Web::App;

use v5.42;
use Mojo::Base 'Mojolicious', -signatures;
use Balance::Config;
use Balance::JobStore;
use Balance::JobRunner;
use File::ShareDir qw(dist_dir);

our $VERSION = '0.01';

sub startup ($self) {
    # TODO: add HTTP Basic or token auth before any external exposure

    # NOTE: balance_config, job_store, and job_runner are memoized per process.
    # Changing balance_job_db or balance_job_log_dir via the config UI requires
    # a process restart for the new paths to take effect.
    # TODO: consider invalidating cached helpers after config updates to those keys.
    $self->helper(balance_config => sub ($c) {
        return $c->app->{_balance_config} //= Balance::Config->new(
            db_path => $c->app->config->{balance_job_db} // '/artifacts/balance-jobs.db',
        );
    });

    $self->helper(job_store => sub ($c) {
        return $c->app->{_job_store} //= do {
            my $cfg = $c->balance_config;
            Balance::JobStore->new(db_path => $cfg->job_db, log_dir => $cfg->job_log_dir);
        };
    });

    $self->helper(job_runner => sub ($c) {
        return $c->app->{_job_runner} //= do {
            Balance::JobRunner->new(log_dir => $c->balance_config->job_log_dir);
        };
    });


    # Generate a simple unique job ID from time + random digits
    $self->helper(new_job_id => sub ($c, $prefix = 'job') {
        return sprintf('%s-%d%04d', $prefix, time(), int(rand(9999)));
    });

    my $share = -d 'share' ? 'share' : dist_dir('App-Balance');
    $self->renderer->paths(["$share/templates"]);
    $self->static->paths(["$share/public"]);

    $self->routes->namespaces(['Balance::Web::Controller']);

    my $r = $self->routes;
    
    # Config management
    $r->get('/config')->to('config#index');
    $r->post('/config/update')->to('config#update');
    $r->post('/config/test-sonarr')->to('config#test_sonarr');
    $r->post('/config/test-plex')->to('config#test_plex');
    
    $r->get('/')->to('dashboard#index');
    $r->post('/plan')->to('dashboard#plan');
    $r->post('/dry-run')->to('dashboard#dry_run');
    $r->post('/apply')->to('dashboard#apply');

    $r->get('/jobs/:id')->to('jobs#show');
    $r->post('/jobs/:id/cancel')->to('jobs#cancel');
    $r->websocket('/jobs/:id/stream')->to('jobs#stream');

    $r->get('/sonarr')->to('sonarr#index');
    $r->post('/sonarr/plan')->to('sonarr#plan');
    $r->post('/sonarr/dry-run')->to('sonarr#dry_run');
    $r->post('/sonarr/apply')->to('sonarr#apply');
    $r->post('/sonarr/audit')->to('sonarr#audit');
    $r->post('/sonarr/repair')->to('sonarr#repair');

    $r->get('/plex')->to('plex#index');
    $r->post('/plex/plan')->to('plex#plan');
    $r->post('/plex/dry-run')->to('plex#dry_run');
    $r->post('/plex/apply')->to('plex#apply');
    $r->post('/plex/scan')->to('plex#scan');
    $r->post('/plex/empty-trash')->to('plex#empty_trash');
    return;
}

1;

__END__

=head1 NAME

Balance::Web::App - Mojolicious application for the Balance web UI

=head1 SYNOPSIS

  # bin/balance_web.pl
  use Mojolicious::Commands;
  Mojolicious::Commands->start_app('Balance::Web::App');

=head1 DESCRIPTION

The L<Mojolicious> application class for Balance. Configures helpers for
L<Balance::JobStore>, L<Balance::JobRunner>, and L<Balance::Config>,
uses persisted config for runtime wiring, and declares all
routes for the dashboard, job management, config UI, Sonarr, and Plex
reconcile pages.

Templates and static assets are resolved via L<File::ShareDir> when
installed from CPAN, with a fallback to the local C<share/> directory for
development.

=head1 LICENSE

Copyright (C) 2026 Sam Robertson. This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
