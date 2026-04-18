package Balance::PathMap;

use v5.38;
use feature qw(signatures try);
no warnings qw(experimental::try);  ## no critic (TestingAndDebugging::ProhibitNoWarnings)
use utf8;
use Exporter 'import';

our @EXPORT_OK = qw(load_path_map translate_path reverse_translate_path nas_roots);

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

# Reverse translation: service path -> NAS path.
# Sorted longest-to-first on the 'to' side (mirrors load_path_map sort on 'from').
sub reverse_translate_path($maps, $path) {
    return unless defined $path;
    my @rev = sort { length($b->{to}) <=> length($a->{to}) } @{ $maps || [] };
    for my $map (@rev) {
        my $to = $map->{to};
        next unless index($path, $to) == 0;
        next if length($path) > length($to) && substr($path, length($to), 1) ne '/';
        return $map->{from} . substr($path, length($to));
    }
    return;
}

# Return the unique list of NAS-side roots (the 'from' side of each map entry),
# in the order they appear after load_path_map's longest-first sort.
sub nas_roots($maps) {
    my %seen;
    return [ grep { !$seen{$_}++ } map { $_->{from} } @{ $maps || [] } ];
}

1;
