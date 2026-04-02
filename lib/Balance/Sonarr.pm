package Balance::Sonarr;

use strict;
use warnings;
use Balance::Config qw(service_defaults);
use Balance::Reconcile ();

sub defaults {
    return service_defaults('sonarr');
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
