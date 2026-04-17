package Balance::Manifest;

use v5.38;
use feature qw(signatures try);
no warnings qw(experimental::try);  ## no critic (TestingAndDebugging::ProhibitNoWarnings)
use utf8;
use Exporter 'import';
use JSON::PP ();

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
