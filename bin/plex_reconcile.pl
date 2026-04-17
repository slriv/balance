#!/usr/bin/env perl
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Balance::ReconcileApp qw(run);
use Balance::Plex qw(cli_main);

# Sub-commands handled by the Plex module CLI (apply/dry-run/API ops)
my @MODULE_CMDS = qw(libraries scan scan-path apply dry-run empty-trash);
if (@ARGV && grep { $ARGV[0] eq $_ } @MODULE_CMDS) {
    exit cli_main(@ARGV);
}

exit run(
    service_name   => 'plex',
    service_module => 'Balance::Plex',
    argv           => \@ARGV,
);
