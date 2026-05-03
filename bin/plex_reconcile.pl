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

__END__

=head1 NAME

plex_reconcile - Reconcile Plex library paths after Balance media moves

=head1 SYNOPSIS

  plex_reconcile [options]
  plex_reconcile apply [--report-file=FILE]
  plex_reconcile dry-run
  plex_reconcile libraries
  plex_reconcile scan --library-id=2

=head1 DESCRIPTION

Builds and applies a Plex path-reconcile plan based on the Balance apply
manifest. Also provides direct Plex API commands (library listing, scan,
empty-trash). See L<Balance::Plex> and L<Balance::ReconcileApp>.

=head1 LICENSE

Copyright (C) 2026 Sam Robertson. This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
