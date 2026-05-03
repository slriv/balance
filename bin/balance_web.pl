#!/usr/bin/env perl
use v5.42;
use lib '/usr/local/lib';
use Balance::Web::App;

Balance::Web::App->new->start;

__END__

=head1 NAME

balance_web.pl - Balance Mojolicious web UI server

=head1 SYNOPSIS

  balance_web.pl daemon -l http://*:8080

=head1 DESCRIPTION

Starts the L<Balance::Web::App> Mojolicious application. Accepts all
standard Mojolicious command-line options (C<daemon>, C<prefork>, etc.).

=head1 LICENSE

Copyright (C) 2026 Sam Robertson. This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
