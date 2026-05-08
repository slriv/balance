package Balance::VolumeScanner;
use v5.42;
use experimental 'class';
use feature 'signatures';
use source::encoding 'utf8';

our $VERSION = '0.01';

class Balance::VolumeScanner {  ## no critic (Modules::RequireEndWithOne)
    use JSON::PP ();
    use POSIX qw(strftime);
    use Balance::Config ();
    use Balance::Core qw(dir_size_kb);

    field $cache_path :param;
    field $ttl :param = 900;

    # Scan mounts and return a hashref of { /path => { capacity_kb, used_kb, free_kb, dirs => {...}, scanned_at } }
    # Usage: $scanner->scan(@mounts, log_fh => $fh)
    method scan($mounts, %opts) {
        my $log_fh = $opts{log_fh};
        my @mounts_list = ref $mounts eq 'ARRAY' ? @$mounts : ($mounts);
        my %vol;
        my $mount_count = scalar @mounts_list;
        my $mount_index = 0;

        for my $mnt (@mounts_list) {
            $mount_index++;
            next unless -d $mnt;

            _progress_log($log_fh, sprintf('[scan %d/%d] %s: probing filesystem usage', $mount_index, $mount_count, $mnt));

            # Get filesystem capacity via df -k
            open my $df_fh, '-|', 'df', '-k', $mnt
                or die "Can't run df on $mnt: $!\n";
            my $df_line;
            $df_line = $_ while <$df_fh>;
            close $df_fh;
            my @f = split /\s+/, $df_line;
            my ($capacity_kb, $used_kb) = ($f[1], $f[2]);

            # Scan show directories
            my %dirs;
            opendir my $dh, $mnt or die "Can't opendir $mnt: $!\n";
            my @entries;
            while (my $d = readdir $dh) {
                next if $d =~ /^\./;
                my $path = "$mnt/$d";
                next unless -d $path;
                push @entries, [$d, $path];
            }
            closedir $dh;

            _progress_log($log_fh, sprintf('[scan %d/%d] %s: measuring %d show director%s',
                $mount_index, $mount_count, $mnt,
                scalar @entries,
                scalar(@entries) == 1 ? 'y' : 'ies'));

            # Size each directory
            my $processed = 0;
            my $last_progress_at = time;
            for my $entry (@entries) {
                my ($dir_name, $path) = @{$entry};
                $dirs{$dir_name} = dir_size_kb($path);
                $processed++;

                if ($processed == scalar @entries || time - $last_progress_at >= 10) {
                    _progress_log($log_fh, sprintf('[scan %d/%d] %s: sized %d/%d shows (latest: %s)',
                        $mount_index, $mount_count, $mnt,
                        $processed, scalar @entries, $dir_name));
                    $last_progress_at = time;
                }
            }

            my $total_show_kb = 0;
            $total_show_kb += $_ for values %dirs;

            $vol{$mnt} = {
                capacity_kb => $capacity_kb,
                used_kb     => $used_kb,
                free_kb     => $capacity_kb - $used_kb,
                dirs        => \%dirs,
                scanned_at  => _format_timestamp(time),
            };

            _progress_log($log_fh, sprintf('[scan %d/%d] %s: complete (%d shows, tv=%s)',
                $mount_index, $mount_count, $mnt,
                scalar keys %dirs,
                _format_size_kb($total_show_kb)));
        }

        return \%vol;
    }

    # Scan if cache is stale or missing; otherwise return cached data
    method scan_cached(@mounts) {
        my $cached = _read_volume_cache($cache_path);
        if ($cached && !_is_cache_stale($cached, $ttl)) {
            return $cached;
        }
        my $result = $self->scan(\@mounts);
        _write_volume_cache($cache_path, $result);
        return $result;
    }

    # Read the cache file; return undef if missing or invalid
    method read_cache() {
        return _read_volume_cache($cache_path);
    }

    # Write cache atomically via temp file + rename
    method write_cache($data) {
        return _write_volume_cache($cache_path, $data);
    }
}

# Stateless helpers

sub is_stale($entry, $ttl = 900) {
    return 1 unless $entry && ref $entry eq 'HASH';
    my $scanned_at = $entry->{scanned_at};
    return 1 unless defined $scanned_at;

    my $scanned_time = _parse_timestamp($scanned_at);
    return 1 unless defined $scanned_time;

    my $age = time - $scanned_time;
    return $age > $ttl;
}

sub cache_path_default() {
    return Balance::Config::dashboard_volume_cache_file();
}

sub _is_cache_stale($cache, $ttl) {
    return 1 unless $cache && ref $cache eq 'HASH';
    for my $mnt (keys %{$cache}) {
        my $entry = $cache->{$mnt};
        return 1 if is_stale($entry, $ttl);
    }
    return 0;
}

sub _read_volume_cache($path) {
    return { } unless defined $path && length $path && -f $path;

    open my $fh, '<', $path or return { };
    local $/;
    my $json = <$fh>;
    close $fh;

    return { } unless defined $json && length $json;

    my $data = eval { JSON::PP->new->utf8->decode($json) };
    return { } if $@ || ref $data ne 'HASH';
    return $data;
}

sub _write_volume_cache($path, $data) {
    return unless defined $path && length $path;

    Balance::Config::ensure_parent_dir($path);

    my $tmp = "$path.$$\.tmp";
    open my $fh, '>', $tmp or return;
    print {$fh} JSON::PP->new->utf8->canonical->encode($data);
    close $fh or do {
        unlink $tmp;
        return;
    };

    rename $tmp, $path or unlink $tmp;
    return;
}

sub _format_timestamp($epoch) {
    return strftime('%Y-%m-%dT%H:%M:%SZ', gmtime($epoch // time));
}

sub _parse_timestamp($str) {
    return undef unless defined $str && $str =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z$/;
    my ($y, $m, $d, $h, $min, $s) = ($1, $2, $3, $4, $5, $6);
    require Time::Local;
    my $epoch = eval { Time::Local::timegm($s, $min, $h, $d, $m - 1, $y) };
    return $epoch;
}

sub _progress_log($fh, $message) {
    return unless defined $message && length $message;

    my $line = sprintf "[%s] %s\n", strftime('%Y-%m-%d %H:%M:%S', localtime(time)), $message;
    print STDERR $line;
    print {$fh} $line if $fh;
    return;
}

sub _format_size_kb($kb) {
    my $GB = 1024 * 1024;
    my $MB = 1024;
    if ($kb >= $GB) {
        return sprintf "%.1f GB", $kb / $GB;
    } elsif ($kb >= $MB) {
        return sprintf "%.1f MB", $kb / $MB;
    } else {
        return sprintf "%d KB", $kb;
    }
}

unless (caller) {
    exit 0;
}

1;

=head1 NAME

Balance::VolumeScanner - Scan media mount volumes for usage stats

=head1 SYNOPSIS

  my $scanner = Balance::VolumeScanner->new(cache_path => '/path/to/cache.json');
  my $vol = $scanner->scan_cached(@mounts);

=head1 DESCRIPTION

Provides volume scanning with caching support. Scans filesystem capacity
(via `df -k`) and directory sizes (via `dir_size_kb`) for media mounts.
Results are cached with configurable TTL.

=head1 LICENSE

Copyright (C) 2026 Sam Robertson. This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
