package Balance::Web::App;

use v5.42;
use Mojo::Base 'Mojolicious', -signatures;
use Balance::Config;
use Balance::JobStore;
use Balance::JobRunner;
use Balance::FileIndex;
use Balance::FileIndexer;
use Mojo::IOLoop ();
use Mojo::IOLoop::Subprocess ();
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use FindBin qw($RealBin);
use File::ShareDir qw(dist_dir);
use File::Spec;

our $VERSION = '0.02';

sub startup ($self) {
    # TODO: add HTTP Basic or token auth before any external exposure

    # NOTE: balance_config, job_store, and job_runner are memoized per process.
    # Changing balance_job_db or balance_job_log_dir via the config UI requires
    # a process restart for the new paths to take effect.
    # TODO: consider invalidating cached helpers after config updates to those keys.
    $self->helper(balance_config => sub ($c) {
        return $c->app->{_balance_config} //= Balance::Config->new(
            db_path => $c->app->config->{balance_job_db} // Balance::Config::default_job_db(),
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

    $self->helper(file_index => sub ($c) {
        return $c->app->{_file_index} //= Balance::FileIndex->new(
            db_path => $c->balance_config->file_index_db,
        );
    });

    # Generate a simple unique job ID from time + random digits
    $self->helper(new_job_id => sub ($c, $prefix = 'job') {
        return sprintf('%s-%d%04d', $prefix, time(), int(rand(9999)));
    });

    $self->helper(cli_command => sub ($c, $script, @args) {
        my @candidates = (
            File::Spec->catfile($RealBin, $script),
            File::Spec->catfile(dirname(__FILE__), '..', '..', '..', 'script', $script),
        );

        for my $candidate (@candidates) {
            my $resolved = eval { abs_path($candidate) } // $candidate;
            next unless defined $resolved && -f $resolved;
            return ($^X, $resolved, @args);
        }

        return ($script, @args);
    });

    my $share = -d 'share' ? 'share' : dist_dir('App-Balance');
    $self->renderer->paths(["$share/templates"]);
    $self->static->paths(["$share/public"]);

    $self->routes->namespaces(['Balance::Web::Controller']);

    my $r = $self->routes;
    
    # Config management
    $r->get('/config')->to('config#index');
    $r->get('/config/browse')->to('config#browse');
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

    # File index browser
    $r->get('/files')->to('files#index');
    $r->get('/files/dirs')->to('files#dirs');
    $r->get('/files/data')->to('files#data');
    $r->get('/files/browse')->to('files#browse');
    $r->get('/files/dir-title')->to('files#dir_title');
    $r->get('/files/:id/meta')->to('files#get_meta');
    $r->put('/files/:id/meta')->to('files#update_meta');
    $r->get('/files/scan/status')->to('files#scan_status');
    $r->post('/files/scan/start')->to('files#scan_start');
    $r->get('/files/scan/events')->to('files#scan_events');
    $r->post('/files/mounts/:id/toggle')->to('files#toggle_mount');
    $r->get('/files/tags')->to('files#list_tags');
    $r->get('/files/export.csv')->to('files#export_csv');
    $r->post('/files/bulk-tag')->to('files#bulk_tag');

    # Background file indexer lifecycle
    $self->{_indexer_events}     = [];   # ring buffer, max 500 events
    $self->{_indexer_event_seq}  = 0;
    $self->{_indexer_sse_clients} = {};
    $self->{_indexer_client_seq}  = 0;

    $self->hook(after_worker_start => sub ($app, $worker) {
        # Only worker 0 runs the indexer to avoid N duplicate scans in prefork
        return unless ($worker->number // 0) == 0;
        _start_indexer($app);
    });

    return;
}

sub _start_indexer ($app) {
    my $index   = $app->file_index;
    my $mounts  = $index->enabled_mounts();

    # Discover any new mounts on Linux and add them disabled by default,
    # so the user must explicitly enable them before scanning begins.
    if (-f '/proc/mounts') {
        my @sys_mounts = Balance::FileIndexer::discover_mounts();
        for my $mp (@sys_mounts) {
            $index->ensure_mount($mp, enabled => 0);
        }
    }

    for my $mount (@$mounts) {
        $app->_queue_indexer_scan($mount);
    }

    # Incremental rescan every 60 minutes
    Mojo::IOLoop->recurring(3600 => sub {
        for my $mount (@{ $app->file_index->enabled_mounts() }) {
            _run_incremental_scan($app, $mount);
        }
    });
    return;
}

sub _queue_indexer_scan ($app, $mount) {
    my $mount_id   = $mount->{id};
    my $mount_path = $mount->{path};

    $app->_indexer_emit("scan_start:$mount_path");

    my $subprocess = Mojo::IOLoop::Subprocess->new;
    $subprocess->run(
        sub {
            # Runs in a forked subprocess — safe to do blocking I/O
            my $index   = Balance::FileIndex->new(
                db_path => $app->balance_config->file_index_db,
            );
            my $indexer = Balance::FileIndexer->new(index => $index);
            my @events;
            my $n = $indexer->scan_mount(
                $mount_id, $mount_path,
                on_progress => sub ($msg) { push @events, $msg },
            );
            return { count => $n, events => \@events };
        },
        sub ($subprocess, $err, $result) {
            if ($err) {
                $app->_indexer_emit("scan_error:$mount_path:$err");
                return;
            }
            $app->_indexer_emit("scan_progress:$mount_path:$_")
                for @{ $result->{events} // [] };
            $app->_indexer_emit("scan_complete:$mount_path:$result->{count}");
        },
    );
    return;
}

sub _run_incremental_scan ($app, $mount) {
    my $mount_id   = $mount->{id};
    my $mount_path = $mount->{path};

    my $subprocess = Mojo::IOLoop::Subprocess->new;
    $subprocess->run(
        sub {
            my $index   = Balance::FileIndex->new(
                db_path => $app->balance_config->file_index_db,
            );
            my $indexer = Balance::FileIndexer->new(index => $index);
            my @events;
            my $n = $indexer->incremental_scan(
                $mount_id, $mount_path,
                on_progress => sub ($msg) { push @events, $msg },
            );
            return { count => $n, events => \@events };
        },
        sub ($subprocess, $err, $result) {
            return if $err;
            $app->_indexer_emit("incremental_complete:$mount_path:$result->{count}");
        },
    );
    return;
}

# --- SSE event infrastructure ---

sub _indexer_emit ($app, $data) {
    my $id = ++$app->{_indexer_event_seq};
    my $ev = { id => $id, data => $data };
    push @{ $app->{_indexer_events} }, $ev;
    # Keep ring buffer bounded
    shift @{ $app->{_indexer_events} }
        while @{ $app->{_indexer_events} } > 500;

    # Push to connected SSE clients
    for my $client (values %{ $app->{_indexer_sse_clients} }) {
        eval { $client->write("id: $id\ndata: $data\n\n") };
    }
    return;
}

sub _indexer_event_ring ($app) {
    return $app->{_indexer_events} //= [];
}

sub _indexer_add_sse_client ($app, $c) {
    my $id = ++$app->{_indexer_client_seq};
    $app->{_indexer_sse_clients}{$id} = $c;
    return $id;
}

sub _indexer_remove_sse_client ($app, $id) {
    delete $app->{_indexer_sse_clients}{$id};
    return;
}

1;

__END__

=head1 NAME

Balance::Web::App - Mojolicious application for the Balance web UI

=head1 SYNOPSIS

    # script/balance_web
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
