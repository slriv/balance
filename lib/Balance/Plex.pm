package Balance::Plex;

use strict;
use warnings;
use Balance::Reconcile ();

sub defaults {
    return {
        manifest_file => $ENV{BALANCE_MANIFEST_FILE} || 'logs/latest-manifest.jsonl',
        path_map_file => $ENV{PLEX_PATH_MAP_FILE} || 'config/plex-path-map.example',
        report_file   => $ENV{PLEX_REPORT_FILE} || 'logs/plex-report.json',
    };
}

sub build_plan {
    my (%args) = @_;
    return Balance::Reconcile::build_plan(service => 'plex', %args);
}

sub write_report {
    my ($path, $items) = @_;
    Balance::Reconcile::write_report($path, service => 'plex', items => $items);
}

1;
