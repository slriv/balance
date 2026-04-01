package Balance::Sonarr;

use strict;
use warnings;
use Balance::Reconcile ();

sub defaults {
    return {
        manifest_file => $ENV{BALANCE_MANIFEST_FILE} || 'logs/latest-manifest.jsonl',
        path_map_file => $ENV{SONARR_PATH_MAP_FILE} || 'config/sonarr-path-map.example',
        report_file   => $ENV{SONARR_REPORT_FILE} || 'logs/sonarr-report.json',
    };
}

sub build_plan {
    my (%args) = @_;
    return Balance::Reconcile::build_plan(service => 'sonarr', %args);
}

sub write_report {
    my ($path, $items) = @_;
    Balance::Reconcile::write_report($path, service => 'sonarr', items => $items);
}

1;
