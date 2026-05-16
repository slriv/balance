package Balance::FileIndexer;

use v5.42;
use experimental 'class';
use source::encoding 'utf8';

our $VERSION = '0.01';

# Probe for Image::ExifTool once at load time; extraction is skipped if absent.
my $EXIFTOOL_AVAILABLE = eval { require Image::ExifTool; 1 } // 0;

my @MEDIA_EXTS = qw(mkv mp4 avi m4v mov wmv ts mpg mpeg m2ts mp3 flac ogg m4a aac);
my %MEDIA_EXT  = map { $_ => 1 } @MEDIA_EXTS;

class Balance::FileIndexer {  ## no critic (Modules::RequireEndWithOne)
    use File::Find ();
    use File::Basename qw(basename dirname);

    field $index         :param;         # Balance::FileIndex instance
    field $batch_size    :param = 500;   # rows per upsert batch
    field $extract_media :param = 1;     # extract media metadata via ExifTool

    # Full recursive scan of a single mount.
    # Calls $on_progress->($msg) periodically during scanning.
    # Returns the number of files indexed.
    method scan_mount($mount_id, $mount_path, %opts) {
        my $on_progress = $opts{on_progress};
        my $max_depth   = $opts{max_depth};
        my $excludes    = $opts{excludes} // [];

        return 0 unless defined $mount_path && -d $mount_path;

        $index->set_mount_status($mount_id, 'scanning');
        _progress($on_progress, "Starting full scan of $mount_path");

        my $scan_start = time;
        my $count      = 0;
        my @batch;
        my $last_progress = time;

        my $wanted = sub {
            my $path = $File::Find::name;
            return if $path eq $mount_path;

            # Depth limit: count path separators relative to mount root
            if (defined $max_depth) {
                (my $rel = $path) =~ s{\A\Q$mount_path\E/?}{};
                my $depth = scalar(() = $rel =~ m{/}g) + 1;
                if ($depth > $max_depth) {
                    $File::Find::prune = 1;
                    return;
                }
            }

            # Exclude patterns (shell glob style, matched against basename)
            my $base = basename($path);
            for my $pat (@$excludes) {
                if ($base =~ _glob_to_re($pat)) {
                    $File::Find::prune = 1 if -d $path;
                    return;
                }
            }

            my @st = lstat($path);
            return unless @st;

            my $file_type = -d _ ? 'dir' : (-l _ ? 'symlink' : 'file');
            my $dir = dirname($path);
            my $ext = ($file_type eq 'file' && $base =~ /\.([^.]+)\z/) ? lc($1) : undef;

            my %media;
            if ($extract_media && $EXIFTOOL_AVAILABLE
                && $file_type eq 'file' && defined $ext && $MEDIA_EXT{$ext})
            {
                %media = _extract_media_meta($path);
            }

            push @batch, {
                mount_id   => $mount_id,
                path       => $path,
                name       => $base,
                dir        => $dir,
                extension  => $ext,
                size_bytes => $st[7] // 0,
                mtime      => $st[9],
                file_type  => $file_type,
                %media,
            };
            $count++;

            if (@batch >= $batch_size) {
                $index->upsert_file(%$_) for @batch;
                @batch = ();
            }

            if (time - $last_progress >= 10) {
                _progress($on_progress, "Indexed $count files under $mount_path...");
                $last_progress = time;
            }
        };

        my $err;
        eval {
            File::Find::find({
                wanted   => $wanted,
                no_chdir => 1,
            }, $mount_path);
        };
        $err = $@ if $@;

        # Flush remaining batch
        $index->upsert_file(%$_) for @batch;

        if ($err) {
            $index->set_mount_status($mount_id, 'error', error => "Scan failed: $err");
            _progress($on_progress, "ERROR scanning $mount_path: $err");
            return 0;
        }

        # Prune entries not touched during this scan (deleted files)
        $index->delete_stale_files($mount_id, $scan_start);

        $index->set_mount_status($mount_id, 'complete', files_indexed => $count);
        _progress($on_progress, "Completed scan of $mount_path: $count files indexed");

        return $count;
    }

    # Incremental scan: re-stat known paths and detect deletions.
    # Much faster than a full scan; intended for periodic background refresh.
    method incremental_scan($mount_id, $mount_path, %opts) {
        my $on_progress = $opts{on_progress};
        return 0 unless defined $mount_path && -d $mount_path;

        _progress($on_progress, "Starting incremental scan of $mount_path");

        my ($updated, $removed) = (0, 0);
        my $page = 1;

        while (1) {
            my $result = $index->list_files(
                mount_id => $mount_id,
                page     => $page,
                per_page => 1000,
                sort_col => 'id',
            );
            last unless @{ $result->{rows} };

            for my $row (@{ $result->{rows} }) {
                unless (-e $row->{path}) {
                    $index->delete_file($row->{path});
                    $removed++;
                    next;
                }

                my @st = lstat($row->{path});
                next unless @st;

                my $mtime = $st[9] // 0;
                if ($mtime > ($row->{indexed_at} // 0)) {
                    my %media;
                    if ($extract_media && $EXIFTOOL_AVAILABLE
                        && ($row->{file_type} // '') eq 'file'
                        && defined $row->{extension} && $MEDIA_EXT{ $row->{extension} })
                    {
                        %media = _extract_media_meta($row->{path});
                    }
                    $index->upsert_file(
                        mount_id   => $mount_id,
                        path       => $row->{path},
                        name       => $row->{name},
                        dir        => $row->{dir},
                        extension  => $row->{extension},
                        size_bytes => $st[7] // 0,
                        mtime      => $mtime,
                        file_type  => $row->{file_type},
                        %media,
                    );
                    $updated++;
                }
            }

            last if $page >= ($result->{pages} // 1);
            $page++;
        }

        _progress($on_progress,
            "Incremental scan complete for $mount_path: $updated updated, $removed removed");
        return $updated + $removed;
    }
}

# Discover non-virtual mounted filesystems via /proc/mounts (Linux).
# Returns a list of mountpoint paths suitable for indexing.
sub discover_mounts {
    return () unless -f '/proc/mounts';

    my %virtual = map { $_ => 1 } qw(
        proc sysfs devtmpfs tmpfs cgroup cgroup2 overlay aufs devpts
        pstore securityfs debugfs hugetlbfs mqueue fusectl binfmt_misc
        configfs tracefs rpc_pipefs nsfs
    );

    open my $fh, '<', '/proc/mounts' or return ();
    my (%seen, @mounts);
    while (my $line = <$fh>) {
        chomp $line;
        my (undef, $mountpoint, $fstype) = split /\s+/, $line;
        next unless defined $mountpoint && defined $fstype;
        next if $virtual{$fstype};
        next if $mountpoint eq '/';
        next unless -d $mountpoint;
        push @mounts, $mountpoint unless $seen{$mountpoint}++;
    }
    close $fh;

    # Also check well-known Docker volume patterns as a fallback / supplement.
    # These paths are conventional bind-mount targets in container deployments.
    my @patterns = qw(
        /tv /tv[0-9] /tv[0-9][0-9]
        /movies /movies[0-9] /movies[0-9][0-9]
        /music /music[0-9]
        /data /data[0-9]
        /media /media/*
        /mnt/*
        /volumes/*
    );
    for my $pat (@patterns) {
        for my $path (glob $pat) {
            push @mounts, $path if -d $path && !$seen{$path}++;
        }
    }

    return @mounts;
}

sub _progress ($cb, $msg) {
    return unless defined $cb && ref $cb eq 'CODE';
    $cb->($msg);
    return;
}

# Extract media metadata using Image::ExifTool.
# Returns a flat hash suitable for spreading into upsert_file %attrs.
# Returns empty hash if ExifTool is unavailable or the file can't be read.
sub _extract_media_meta ($path) {
    return () unless $EXIFTOOL_AVAILABLE;

    my $exif = Image::ExifTool->new;
    $exif->Options(Unknown => 0, DateFormat => '%Y-%m-%d %H:%M:%S');

    my $info = $exif->ImageInfo(
        $path,
        qw(Title TVShow Show Duration ImageSize ImageWidth ImageHeight
           VideoCodec CompressorName CompressorID VideoStreamType Codec),
    );
    return () unless ref $info eq 'HASH';

    # Title: prefer embedded Title, then TV show name
    my $title = $info->{Title} // $info->{TVShow} // $info->{Show};
    $title = undef if defined $title && !length $title;
    $title = undef if defined $title && $title =~ /\A\s*\z/;

    # Duration: normalize ExifTool's various formats to H:MM:SS or M:SS
    my $duration = _normalize_duration($info->{Duration});

    # Resolution: prefer ImageSize "WxH", else compose from W+H
    my $resolution = $info->{ImageSize};
    if (!defined $resolution && defined $info->{ImageWidth} && defined $info->{ImageHeight}) {
        $resolution = "$info->{ImageWidth}x$info->{ImageHeight}";
    }
    $resolution = undef if defined $resolution && $resolution !~ /\d/;

    # Codec: first non-empty candidate
    my $codec;
    for my $key (qw(VideoCodec CompressorName CompressorID VideoStreamType Codec)) {
        if (defined $info->{$key} && length $info->{$key}) {
            $codec = $info->{$key};
            last;
        }
    }

    return (
        media_title      => $title,
        media_duration   => $duration,
        media_resolution => $resolution,
        media_codec      => $codec,
    );
}

sub _normalize_duration ($raw) {
    return undef unless defined $raw && length $raw;
    # ExifTool may return "0:42:17" or "42:17" or "2521.00 s" or "42 min 17 s"
    if ($raw =~ /(\d+):(\d{2}):(\d{2})/) {
        my ($h, $m, $s) = ($1, $2, $3);
        return $h > 0 ? sprintf('%d:%02d:%02d', $h, $m, $s)
                      : sprintf('%d:%02d', $m, $s);
    }
    if ($raw =~ /(\d+):(\d{2})/) {
        return "$1:$2";
    }
    if ($raw =~ /([\d.]+)\s*s/) {
        my $secs = int($1);
        my ($m, $s) = (int($secs / 60), $secs % 60);
        my $h = int($m / 60); $m %= 60;
        return $h > 0 ? sprintf('%d:%02d:%02d', $h, $m, $s)
                      : sprintf('%d:%02d', $m, $s);
    }
    return $raw;  # pass through unknown format
}

sub _glob_to_re ($pattern) {
    my $re = quotemeta($pattern);
    $re =~ s/\\\*/.*/g;
    $re =~ s/\\\?/./g;
    return qr/\A$re\z/i;
}

unless (caller) { exit 0 }

1;

__END__

=head1 NAME

Balance::FileIndexer - Recursive filesystem scanner for the Balance file index

=head1 SYNOPSIS

  use Balance::FileIndex;
  use Balance::FileIndexer;

  my $index   = Balance::FileIndex->new(db_path => '/artifacts/balance-file-index.db');
  my $mount   = $index->ensure_mount('/mnt/tv1');
  my $indexer = Balance::FileIndexer->new(index => $index);

  # Full scan (blocks until complete; run in subprocess)
  my $n = $indexer->scan_mount($mount->{id}, '/mnt/tv1',
      on_progress => sub { warn "$_[0]\n" },
  );

  # Incremental update (fast re-stat of known paths)
  $indexer->incremental_scan($mount->{id}, '/mnt/tv1');

  # Discover all non-virtual mounts on Linux
  my @mounts = Balance::FileIndexer::discover_mounts();

=head1 DESCRIPTION

Provides full recursive file scanning and incremental refresh for the
Balance file index.  C<scan_mount> enumerates every file/dir/symlink under
a mount point, writing metadata in batches via L<Balance::FileIndex>.
C<incremental_scan> re-stats existing index entries to detect mutations and
deletions without a full traversal.

C<discover_mounts> reads F</proc/mounts> on Linux to suggest bind-mounted
volumes that are candidates for indexing.

=head1 LICENSE

Copyright (C) 2026 Sam Robertson. This library is free software; you can
redistribute it and/or modify it under the same terms as Perl itself.

=cut
