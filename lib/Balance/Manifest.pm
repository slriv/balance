package Balance::Manifest;

use v5.42;
use source::encoding 'utf8';
use Exporter 'import';
use JSON::PP ();

our $VERSION = '0.01';

our @EXPORT_OK = qw(append_manifest_record read_manifest successful_apply_records);

sub append_manifest_record($fh, $record) {
    return unless $fh;
    print {$fh} JSON::PP->new->canonical->encode($record), "\n";
    return;
}

sub read_manifest($path) {
    open my $fh, '<', $path or die "Can't read manifest file $path: $!\n";
    my @records;
    while (my $line = <$fh>) {
        next if $line =~ /^\s*$/;
        push @records, JSON::PP::decode_json($line);
    }
    close $fh;
    return \@records;
}

sub successful_apply_records($records) {
    return [ grep { ($_->{mode} // '') eq 'apply' && ($_->{status} // '') eq 'applied' } @{ $records || [] } ];
}

1;

__END__

=head1 NAME

Balance::Manifest - Read and write Balance apply manifest (JSONL) files

=head1 DESCRIPTION

Appends move records to a JSONL manifest file during apply runs and reads
them back to build reconcile plans for Sonarr and Plex.

=head1 LICENSE

Copyright (C) 2026 Sam Robertson. This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
