#!/usr/bin/env perl
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Balance::ReconcileApp qw(run);
use Balance::Sonarr qw(cli_main);

# Sub-commands handled by the Sonarr module CLI (apply/dry-run/API ops)
my @MODULE_CMDS = qw(series rescan refresh apply dry-run);
if (@ARGV && grep { $ARGV[0] eq $_ } @MODULE_CMDS) {
    exit cli_main(@ARGV);
}

exit run(
    service_name   => 'sonarr',
    service_module => 'Balance::Sonarr',
    argv           => \@ARGV,
);
