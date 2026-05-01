package Balance::DiskProbe;

use v5.42;
use feature 'signatures';
use source::encoding 'utf8';
use Exporter 'import';
use Balance::FuzzyName qw(matches);

our $VERSION = '0.01';

our @EXPORT_OK = qw(
    path_exists
    list_dir
    dir_metadata
    find_candidates
    probe_service_roots
);

# Returns true if $path is an accessible directory.
sub path_exists($path) {
    return -d $path ? 1 : 0;
}

# Returns an arrayref of entries (excluding . and ..) in $path.
# Returns [] if the path is not a readable directory.
sub list_dir($path) {
    return [] unless -d $path;
    opendir my $dh, $path or return [];
    my @entries = grep { $_ ne '.' && $_ ne '..' } readdir $dh;
    closedir $dh;
    return \@entries;
}

# Inspect a show directory and return coarse metadata for disambiguation.
#
# Returns: { season_dirs => N, episode_files => N, tvdb_id => NNNN or undef }
#
# Season dirs match /^Season \d+/i.
# Episode files are video files (.mkv .mp4 .avi .m4v .mov .wmv) found directly
# inside season dirs (or in $path itself if no season dirs).
# tvdb_id is extracted from the folder name pattern {tvdb-NNNNN} (Sonarr convention).
sub dir_metadata($path) {
    my $entries = list_dir($path);

    my @season_dirs = grep { /^Season\s+\d+/i && -d "$path/$_" } @{$entries};

    my @episode_files;
    if (@season_dirs) {
        for my $sd (@season_dirs) {
            my $sd_entries = list_dir("$path/$sd");
            push @episode_files,
                grep { /\.(mkv|mp4|avi|m4v|mov|wmv)$/i } @{$sd_entries};
        }
    } else {
        push @episode_files,
            grep { /\.(mkv|mp4|avi|m4v|mov|wmv)$/i } @{$entries};
    }

    # Extract tvdb_id from the last path component (Sonarr format: {tvdb-NNNNN})
    my ($basename) = $path =~ m{([^/]+)/*$};
    my $tvdb_id;
    if (defined $basename && $basename =~ /\{tvdb[-\s]?(\d+)\}/i) {
        $tvdb_id = "$1";
    }

    return {
        season_dirs   => scalar @season_dirs,
        episode_files => scalar @episode_files,
        tvdb_id       => $tvdb_id,
    };
}

# Walk each root and find subdirectories whose name fuzzy-matches $name.
# Returns arrayref of full paths.
sub find_candidates($roots, $name) {
    my @candidates;
    for my $root (@{$roots}) {
        my $entries = list_dir($root);
        for my $entry (@{$entries}) {
            next unless -d "$root/$entry";
            push @candidates, "$root/$entry" if matches($entry, $name);
        }
    }
    return \@candidates;
}

# Check whether a list of service root paths are accessible from within the
# balance container.  Accepts separate arrayrefs for Sonarr and Plex roots
# (already fetched from their respective APIs by the caller).
#
# Returns arrayref of { path, service, balance_accessible }.
sub probe_service_roots($sonarr_paths, $plex_paths) {
    my @results;
    my %seen;

    for my $p (@{$sonarr_paths}) {
        next if $seen{"sonarr:$p"}++;
        push @results, {
            path               => $p,
            service            => 'sonarr',
            balance_accessible => path_exists($p),
        };
    }

    for my $p (@{$plex_paths}) {
        next if $seen{"plex:$p"}++;
        push @results, {
            path               => $p,
            service            => 'plex',
            balance_accessible => path_exists($p),
        };
    }

    return \@results;
}

1;

__END__

=head1 NAME

Balance::DiskProbe - Disk and directory inspection for Balance

=head1 DESCRIPTION

Provides directory listing, fuzzy-name candidate search, show-directory
metadata extraction (season count, tvdb ID), and service root accessibility
checks used during Sonarr audit and reconcile operations.

=head1 LICENSE

Copyright (C) 2026 Sam Robertson. GNU General Public License v3 or later.

=cut
