#!/usr/bin/env perl
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Balance::ReconcileApp qw(run);
use Balance::Sonarr qw(cli_main);

# Sub-commands handled by the Sonarr module CLI (apply/dry-run/API ops)
my @MODULE_CMDS = qw(series rescan refresh apply dry-run audit repair audit-dry-run repair-dry-run);
if (@ARGV && grep { $ARGV[0] eq $_ } @MODULE_CMDS) {
    exit cli_main(@ARGV);
}

exit run(
    service_name   => 'sonarr',
    service_module => 'Balance::Sonarr',
    argv           => \@ARGV,
);

__END__

=head1 NAME

sonarr_reconcile - Reconcile Sonarr library paths after Balance media moves

=head1 SYNOPSIS

  sonarr_reconcile [--env-file=.env]
  sonarr_reconcile apply [--report-file=FILE]
  sonarr_reconcile dry-run
  sonarr_reconcile series
  sonarr_reconcile audit

=head1 DESCRIPTION

Builds and applies a Sonarr path-reconcile plan based on the Balance apply
manifest. Also provides direct Sonarr API commands (series listing, rescan,
audit, repair). See L<Balance::Sonarr> and L<Balance::ReconcileApp>.

=head1 LICENSE

Copyright (C) 2026 Sam Robertson. GNU General Public License v3 or later.

=cut
