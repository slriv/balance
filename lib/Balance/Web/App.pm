package Balance::Web::App;

use v5.38;
use Mojo::Base 'Mojolicious', -signatures;
use Balance::JobStore;
use Balance::JobRunner;
use Balance::ConfigStore;

sub startup ($self) {
    # TODO: add HTTP Basic or token auth before any external exposure

    # Helpers — one instance per app object (isolated per Test::Mojo run)
    $self->helper(job_store => sub ($c) {
        return $c->app->{_job_store} //= Balance::JobStore->new(
            db_path => ($ENV{BALANCE_JOB_DB}      || '/artifacts/balance-jobs.db'),
            log_dir => ($ENV{BALANCE_JOB_LOG_DIR}  || '/artifacts/jobs'),
        );
    });

    $self->helper(config_store => sub ($c) {
        return $c->app->{_config_store} //= Balance::ConfigStore->new(
            db_path => ($ENV{BALANCE_JOB_DB}      || '/artifacts/balance-jobs.db'),
        );
    });

    $self->helper(job_runner => sub ($c) {
        return $c->app->{_job_runner} //= Balance::JobRunner->new(
            log_dir => ($ENV{BALANCE_JOB_LOG_DIR}  || '/artifacts/jobs'),
        );
    });

    # Seed %ENV from persisted config so job controllers pick it up on startup
    my %config_to_env = (
        tv_path_1        => 'TV_PATH_1',
        tv_path_2        => 'TV_PATH_2',
        tv_path_3        => 'TV_PATH_3',
        tv_path_4        => 'TV_PATH_4',
        sonarr_url       => 'SONARR_BASE_URL',
        sonarr_api_key   => 'SONARR_API_KEY',
        plex_url         => 'PLEX_BASE_URL',
        plex_token       => 'PLEX_TOKEN',
        plex_library_ids => 'PLEX_LIBRARY_IDS',
    );
    $self->hook(before_dispatch => sub ($c) {
        state $seeded = 0;
        return if $seeded++;
        my $stored = $c->config_store->get_all;
        for my $key (keys %config_to_env) {
            $ENV{$config_to_env{$key}} = $stored->{$key}
                if defined $stored->{$key} && $stored->{$key} ne '';
        }
    });

    # Generate a simple unique job ID from time + random digits
    $self->helper(new_job_id => sub ($c, $prefix = 'job') {
        return sprintf('%s-%d%04d', $prefix, time(), int(rand(9999)));
    });

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
