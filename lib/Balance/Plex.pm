package Balance::Plex;

use strict;
use warnings;
use Balance::Config qw(service_defaults);
use Balance::Reconcile ();

sub defaults {
    return service_defaults('plex');
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
