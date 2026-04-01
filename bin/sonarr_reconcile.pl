#!/usr/bin/env perl
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Balance::ReconcileApp qw(run);

exit run(
    service_name   => 'sonarr',
    service_module => 'Balance::Sonarr',
    argv           => \@ARGV,
);
