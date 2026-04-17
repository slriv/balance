package Balance::PathMap;

use v5.38;
use feature qw(signatures try);
no warnings qw(experimental::try);  ## no critic (TestingAndDebugging::ProhibitNoWarnings)
use utf8;
use Exporter 'import';

our @EXPORT_OK = qw(load_path_map translate_path);

sub load_path_map($path) {
    open my $fh, '<', $path or die "Can't read path map file $path: $!\n";
    my @maps;
    while (my $line = <$fh>) {
        chomp $line;
        $line =~ s/\s+#.*$//;
        $line =~ s/^\s+|\s+$//g;
        next unless length $line;
        next if $line =~ /^#/;
        my ($from, $to) = split /\s*=\s*/, $line, 2;
        die "Invalid path map entry in $path: $line\n" unless defined $from && defined $to;
        for ($from, $to) {
            die "Path map entries must be absolute in $path: $line\n" unless m{^/};
            s{/$}{} unless $_ eq '/';
        }
        push @maps, { from => $from, to => $to };
    }
    close $fh;
    @maps = sort { length($b->{from}) <=> length($a->{from}) } @maps;
    die "No usable path mappings found in $path\n" unless @maps;
    return \@maps;
}

sub translate_path($maps, $path) {
    return unless defined $path;
    for my $map (@{ $maps || [] }) {
        my $from = $map->{from};
        next unless index($path, $from) == 0;
        my $next = substr($path, length($from), 1);
        next if length($path) > length($from) && $next ne '/';
        return $map->{to} . substr($path, length($from));
    }
    return;
}

1;
