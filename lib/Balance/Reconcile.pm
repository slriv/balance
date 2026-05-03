package Balance::Reconcile;

use v5.42;
use source::encoding 'utf8';
use Exporter 'import';
use JSON::PP ();
use POSIX qw(strftime);
use Balance::PathMap qw(translate_path);

our $VERSION = '0.01';

our @EXPORT_OK = qw(build_plan write_report);

sub build_plan(%args) {
    my $service  = $args{service}  or die "service is required\n";
    my $records  = $args{records}  || [];
    my $path_map = $args{path_map} || [];

    my @items;
    for my $record (@$records) {
        my $remote_from = translate_path($path_map, $record->{from_path});
        my $remote_to   = translate_path($path_map, $record->{to_path});
        my %item = (
            %$record,
            service         => $service,
            remote_from_path => $remote_from,
            remote_to_path   => $remote_to,
            reconcile_status => defined($remote_to) ? 'planned' : 'pending',
        );
        $item{reason} = 'no_path_mapping' unless defined $remote_to;
        push @items, \%item;
    }
    return \@items;
}

sub write_report($path, %args) {
    my $service = $args{service} || 'unknown';
    my $items    = $args{items} || [];
    my %counts;
    $counts{ $_->{reconcile_status} || 'unknown' }++ for @$items;

    my $payload = {
        service      => $service,
        generated_at => strftime('%Y-%m-%d %H:%M:%S', localtime),
        counts       => \%counts,
        items        => $items,
    };

    open my $fh, '>', $path or die "Can't write report file $path: $!\n";
    print {$fh} JSON::PP->new->canonical->pretty->encode($payload);
    close $fh;
    return;
}

1;

__END__

=head1 NAME

Balance::Reconcile - Build and write reconcile plans for Sonarr and Plex

=head1 DESCRIPTION

Translates move manifest records through a path map to produce a reconcile
plan JSON file, which is then applied by L<Balance::Sonarr> or
L<Balance::Plex> to update library paths after media moves.

=head1 LICENSE

Copyright (C) 2026 Sam Robertson. This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
