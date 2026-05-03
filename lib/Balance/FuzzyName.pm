package Balance::FuzzyName;

use v5.42;
use feature 'signatures';
use source::encoding 'utf8';
use Unicode::Normalize ();
use Exporter 'import';

our $VERSION = '0.01';

our @EXPORT_OK = qw(normalize matches);

# Normalize a show name for fuzzy comparison.
#
# Steps applied in order:
#   1. NFC Unicode normalization (collapses combining-character variants)
#   2. Strip trailing year: " (YYYY)"
#   3. Invert trailing article: "Title, The" -> "The Title" (also A, An)
#   4. Lowercase
#   5. Replace . _ - with space (common filename separators)
#   6. Collapse and trim whitespace
#
# Algorithm is intentionally normalize-then-exact (no Levenshtein). A false
# positive match is more dangerous than a 'missing' audit result for an
# operation that writes back to Sonarr.
sub normalize($name) {
    $name = Unicode::Normalize::NFC($name);
    $name =~ s/\s*\(\d{4}\)\s*$//;                  # strip trailing (YYYY)
    $name =~ s/^(.+),\s*(The|A|An)\s*$/$2 $1/i;     # invert "Title, The"
    $name = lc $name;
    $name =~ s/[._-]/ /g;                            # separators -> space
    $name =~ s/\s+/ /g;                              # collapse whitespace
    $name =~ s/^\s+|\s+$//g;                         # trim
    return $name;
}

# True if two names are equivalent after normalization.
sub matches($a, $b) {
    return normalize($a) eq normalize($b);
}

1;

__END__

=head1 NAME

Balance::FuzzyName - Fuzzy show-name normalization for Balance

=head1 DESCRIPTION

Normalizes TV show directory names for comparison: strips years, inverts
trailing articles ("Title, The"), lowercases, and collapses separators.
Uses exact post-normalization comparison (no Levenshtein) to avoid false
positives when updating Sonarr paths.

=head1 LICENSE

Copyright (C) 2026 Sam Robertson. This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
