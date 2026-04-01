package Balance::Manifest;

use strict;
use warnings;
use Exporter 'import';
use JSON::PP ();

our @EXPORT_OK = qw(append_manifest_record read_manifest successful_apply_records);

sub append_manifest_record {
    my ($fh, $record) = @_;
    return unless $fh;
    print {$fh} JSON::PP->new->canonical->encode($record), "\n";
}

sub read_manifest {
    my ($path) = @_;
    open my $fh, '<', $path or die "Can't read manifest file $path: $!\n";
    my @records;
    while (my $line = <$fh>) {
        next if $line =~ /^\s*$/;
        push @records, JSON::PP::decode_json($line);
    }
    close $fh;
    return \@records;
}

sub successful_apply_records {
    my ($records) = @_;
    return [ grep { ($_->{mode} // '') eq 'apply' && ($_->{status} // '') eq 'applied' } @{ $records || [] } ];
}

1;
