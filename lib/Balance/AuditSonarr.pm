package Balance::AuditSonarr;

use v5.38;
use feature 'signatures';
use utf8;
use Exporter 'import';
use JSON::PP ();
use Balance::DiskProbe ();  # called as Balance::DiskProbe::* so mocks intercept

our @EXPORT_OK = qw(audit_series write_audit_report read_audit_report);

# Determine the audit status for a single Sonarr series.
#
# $series   - hashref from Sonarr GET /api/v3/series (needs: id, title, path, tvdbId)
# $roots    - arrayref of root directory paths to search for candidates
#
# Returns a hashref with at minimum: { status, id, title, path }
# Additional keys per status:
#   fixable:   candidate_path, confidence ('name_match' | 'exact')
#   ambiguous: candidates (arrayref of paths)
#
# Status values:
#   ok        - series.path exists on disk
#   missing   - not found; no fuzzy candidates
#   fixable   - unambiguous candidate found via fuzzy search
#   ambiguous - 2+ candidates; metadata could not disambiguate
sub audit_series($series, $roots) {
    my $id    = $series->{id};
    my $title = $series->{title} // '';
    my $path  = $series->{path} // '';

    if (Balance::DiskProbe::path_exists($path)) {
        return { status => 'ok', id => $id, title => $title, path => $path };
    }

    my $candidates = Balance::DiskProbe::find_candidates($roots, $title);

    if (!@{$candidates}) {
        return { status => 'missing', id => $id, title => $title, path => $path };
    }

    if (@{$candidates} == 1) {
        return {
            status         => 'fixable',
            confidence     => 'name_match',
            id             => $id,
            title          => $title,
            path           => $path,
            candidate_path => $candidates->[0],
        };
    }

    # 2+ candidates — attempt tvdbId disambiguation.
    my $tvdb_id = $series->{tvdbId};
    if (defined $tvdb_id && length $tvdb_id) {
        my @exact = grep {
            my $meta = Balance::DiskProbe::dir_metadata($_);
            defined $meta->{tvdb_id} && $meta->{tvdb_id} eq "$tvdb_id";
        } @{$candidates};

        if (@exact == 1) {
            return {
                status         => 'fixable',
                confidence     => 'exact',
                id             => $id,
                title          => $title,
                path           => $path,
                candidate_path => $exact[0],
            };
        }
    }

    return {
        status     => 'ambiguous',
        id         => $id,
        title      => $title,
        path       => $path,
        candidates => $candidates,
    };
}

# Write an audit report JSON file.
# $path  - file path to write
# $items - arrayref of audit_series results
sub write_audit_report($path, $items) {
    open my $fh, '>', $path or die "Cannot write audit report $path: $!\n";
    print $fh JSON::PP->new->utf8->pretty->encode({
        generated_at => scalar localtime,
        items        => $items,
    });
    close $fh;
    return 1;
}

# Read an audit report JSON file.  Returns the items arrayref.
sub read_audit_report($path) {
    open my $fh, '<', $path or die "Cannot read audit report $path: $!\n";
    my $data = JSON::PP::decode_json(do { local $/; <$fh> });
    close $fh;
    return $data->{items} // [];
}

1;
