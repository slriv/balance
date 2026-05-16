package Balance::FileIndex;

use v5.42;
use experimental 'class';
use source::encoding 'utf8';
use Balance::Config ();

our $VERSION = '0.01';

class Balance::FileIndex {  ## no critic (Modules::RequireEndWithOne)
    use DBI ();
    use JSON::PP ();

    field $db_path :param;
    field $_dbh;

    ADJUST {
        $db_path = Balance::Config::default_file_index_db()
            unless defined $db_path && length $db_path;
        Balance::Config::ensure_parent_dir($db_path);

        $_dbh = DBI->connect(
            "dbi:SQLite:dbname=$db_path", '', '',
            { RaiseError => 1, AutoCommit => 1, sqlite_unicode => 1 },
        ) or die "Cannot open file index database $db_path: $DBI::errstr\n";

        $_dbh->do('PRAGMA journal_mode=WAL');
        $_dbh->do('PRAGMA foreign_keys=ON');
        $self->_init_schema();
    }

    my method _init_schema() {
        $_dbh->do(<<~'SQL');
            CREATE TABLE IF NOT EXISTS mounts (
                id                    INTEGER PRIMARY KEY AUTOINCREMENT,
                path                  TEXT    NOT NULL UNIQUE,
                enabled               INTEGER NOT NULL DEFAULT 1,
                scan_status           TEXT    NOT NULL DEFAULT 'idle',
                last_scan_started_at  INTEGER,
                last_scan_finished_at INTEGER,
                files_indexed         INTEGER NOT NULL DEFAULT 0,
                error_message         TEXT,
                created_at            INTEGER NOT NULL DEFAULT (unixepoch()),
                updated_at            INTEGER NOT NULL DEFAULT (unixepoch())
            )
        SQL

        $_dbh->do(<<~'SQL');
            CREATE TABLE IF NOT EXISTS files (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                mount_id   INTEGER NOT NULL REFERENCES mounts(id) ON DELETE CASCADE,
                path       TEXT    NOT NULL UNIQUE,
                name       TEXT    NOT NULL,
                dir        TEXT    NOT NULL,
                extension  TEXT,
                size_bytes INTEGER NOT NULL DEFAULT 0,
                mtime      INTEGER,
                file_type  TEXT    NOT NULL DEFAULT 'file',
                tags       TEXT,
                notes      TEXT,
                indexed_at INTEGER NOT NULL DEFAULT (unixepoch()),
                updated_at INTEGER NOT NULL DEFAULT (unixepoch())
            )
        SQL

        for my $sql (
            'CREATE INDEX IF NOT EXISTS idx_files_mount     ON files(mount_id)',
            'CREATE INDEX IF NOT EXISTS idx_files_dir       ON files(dir)',
            'CREATE INDEX IF NOT EXISTS idx_files_name      ON files(name)',
            'CREATE INDEX IF NOT EXISTS idx_files_extension ON files(extension)',
            'CREATE INDEX IF NOT EXISTS idx_files_mtime     ON files(mtime)',
            'CREATE INDEX IF NOT EXISTS idx_files_size      ON files(size_bytes)',
        ) {
            $_dbh->do($sql);
        }

        # Idempotent column migrations (ALTER TABLE ADD COLUMN silently errors on dup)
        for my $col_sql (
            'ALTER TABLE files ADD COLUMN media_title      TEXT',
            'ALTER TABLE files ADD COLUMN media_duration   TEXT',
            'ALTER TABLE files ADD COLUMN media_resolution TEXT',
            'ALTER TABLE files ADD COLUMN media_codec      TEXT',
        ) {
            eval { $_dbh->do($col_sql) };  # ignore "duplicate column" errors
        }

        return;
    }

    # --- Mount management ---

    method ensure_mount($path) {
        $_dbh->do('INSERT OR IGNORE INTO mounts (path) VALUES (?)', {}, $path);
        return $_dbh->selectrow_hashref('SELECT * FROM mounts WHERE path = ?', {}, $path);
    }

    method get_mount($id) {
        return $_dbh->selectrow_hashref('SELECT * FROM mounts WHERE id = ?', {}, $id);
    }

    method get_mount_by_path($path) {
        return $_dbh->selectrow_hashref('SELECT * FROM mounts WHERE path = ?', {}, $path);
    }

    method all_mounts() {
        return $_dbh->selectall_arrayref(
            'SELECT * FROM mounts ORDER BY path', { Slice => {} }
        );
    }

    method enabled_mounts() {
        return $_dbh->selectall_arrayref(
            'SELECT * FROM mounts WHERE enabled = 1 ORDER BY path', { Slice => {} }
        );
    }

    method set_mount_status($mount_id, $status, %opts) {
        my @set  = ('scan_status = ?', 'updated_at = unixepoch()');
        my @vals = ($status);

        if ($status eq 'scanning') {
            push @set, 'last_scan_started_at = unixepoch()';
            push @set, 'error_message = NULL';
        }
        elsif ($status eq 'complete') {
            push @set, 'last_scan_finished_at = unixepoch()';
            if (defined $opts{files_indexed}) {
                push @set, 'files_indexed = ?';
                push @vals, int($opts{files_indexed});
            }
        }
        elsif ($status eq 'error') {
            push @set, 'last_scan_finished_at = unixepoch()';
            if (defined $opts{error}) {
                push @set, 'error_message = ?';
                push @vals, $opts{error};
            }
        }

        push @vals, $mount_id;
        $_dbh->do('UPDATE mounts SET ' . join(', ', @set) . ' WHERE id = ?', {}, @vals);
        return;
    }

    method set_mount_enabled($mount_id, $enabled) {
        $_dbh->do(
            'UPDATE mounts SET enabled = ?, updated_at = unixepoch() WHERE id = ?',
            {}, $enabled ? 1 : 0, $mount_id,
        );
        return;
    }

    # --- File CRUD ---

    method upsert_file(%attrs) {
        $_dbh->do(<<~'SQL', {},
            INSERT INTO files
                (mount_id, path, name, dir, extension, size_bytes, mtime, file_type,
                 media_title, media_duration, media_resolution, media_codec,
                 indexed_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, unixepoch(), unixepoch())
            ON CONFLICT(path) DO UPDATE SET
                name             = excluded.name,
                dir              = excluded.dir,
                extension        = excluded.extension,
                size_bytes       = excluded.size_bytes,
                mtime            = excluded.mtime,
                file_type        = excluded.file_type,
                media_title      = COALESCE(excluded.media_title,      media_title),
                media_duration   = COALESCE(excluded.media_duration,   media_duration),
                media_resolution = COALESCE(excluded.media_resolution, media_resolution),
                media_codec      = COALESCE(excluded.media_codec,      media_codec),
                indexed_at       = unixepoch(),
                updated_at       = unixepoch()
        SQL
            $attrs{mount_id},
            $attrs{path},
            $attrs{name},
            $attrs{dir},
            $attrs{extension},
            $attrs{size_bytes} // 0,
            $attrs{mtime},
            $attrs{file_type} // 'file',
            $attrs{media_title},
            $attrs{media_duration},
            $attrs{media_resolution},
            $attrs{media_codec},
        );
        return;
    }

    method delete_file($path) {
        $_dbh->do('DELETE FROM files WHERE path = ?', {}, $path);
        return;
    }

    method delete_mount_files($mount_id) {
        $_dbh->do('DELETE FROM files WHERE mount_id = ?', {}, $mount_id);
        return;
    }

    method get_file($id) {
        return $_dbh->selectrow_hashref('SELECT * FROM files WHERE id = ?', {}, $id);
    }

    method update_file_meta($id, %attrs) {
        my @allowed = qw(tags notes);
        my @cols    = grep { exists $attrs{$_} } @allowed;
        return unless @cols;
        my $set  = join ', ', (map { "$_ = ?" } @cols), 'updated_at = unixepoch()';
        my @vals = ((map { $attrs{$_} } @cols), $id);
        $_dbh->do("UPDATE files SET $set WHERE id = ?", {}, @vals);
        return;
    }

    # Remove files not touched since $since_epoch (pre-scan checkpoint for stale pruning)
    method delete_stale_files($mount_id, $since_epoch) {
        $_dbh->do(
            'DELETE FROM files WHERE mount_id = ? AND indexed_at < ?',
            {}, $mount_id, $since_epoch,
        );
        return;
    }

    # --- Query / browse ---

    # List immediate child directories of $mount_path for a mount.
    # Returns arrayref of hashrefs with: path, name, file_count, total_bytes, dir_count
    method list_top_dirs($mount_id, $mount_path) {
        # Strip trailing slash for consistent prefix matching
        (my $root = $mount_path) =~ s{/+\z}{};

        # Find all 'dir' entries whose parent is exactly the mount root
        my $rows = $_dbh->selectall_arrayref(<<'SQL', { Slice => {} }, $mount_id, $root);
            SELECT
                f.path,
                f.name,
                f.mtime,
                (SELECT COUNT(*) FROM files c
                 WHERE c.mount_id = f.mount_id
                   AND c.file_type = 'file'
                   AND c.dir LIKE f.path || '%') AS file_count,
                (SELECT COUNT(*) FROM files c
                 WHERE c.mount_id = f.mount_id
                   AND c.file_type = 'dir'
                   AND c.dir LIKE f.path || '%') AS dir_count,
                (SELECT COALESCE(SUM(c.size_bytes),0) FROM files c
                 WHERE c.mount_id = f.mount_id
                   AND c.file_type = 'file'
                   AND c.dir LIKE f.path || '%') AS total_bytes
            FROM files f
            WHERE f.mount_id = ?
              AND f.file_type = 'dir'
              AND f.dir = ?
            ORDER BY f.name
SQL
        return $rows;
    }

    # List direct contents of a single directory path (non-recursive).
    method list_dir($mount_id, $dir_path, %args) {
        my $sort_col = _safe_sort_column($args{sort_col} // 'file_type');
        my $sort_dir = ($args{sort_dir} // 'asc') eq 'desc' ? 'DESC' : 'ASC';
        my $page     = int($args{page} // 1);
        $page        = 1 if $page < 1;
        my $per_page = int($args{per_page} // 200);
        $per_page    = 10   if $per_page < 1;
        $per_page    = 1000 if $per_page > 1000;
        my $offset   = ($page - 1) * $per_page;

        (my $dir = $dir_path) =~ s{/+\z}{};

        my ($total) = $_dbh->selectrow_array(
            'SELECT COUNT(*) FROM files WHERE mount_id = ? AND dir = ?',
            {}, $mount_id, $dir,
        );
        my $rows = $_dbh->selectall_arrayref(
            "SELECT * FROM files WHERE mount_id = ? AND dir = ?
             ORDER BY $sort_col $sort_dir LIMIT ? OFFSET ?",
            { Slice => {} }, $mount_id, $dir, $per_page, $offset,
        );
        return {
            rows     => $rows,
            total    => $total // 0,
            page     => $page,
            per_page => $per_page,
            pages    => _ceil_div($total // 0, $per_page),
            dir      => $dir,
        };
    }

    # Return the best-guess media title for a directory tree.
    # Prefers the stored media_title extracted from file metadata;
    # falls back to cleaning up the filename.
    method dir_media_title($mount_id, $dir_path) {
        (my $dir = $dir_path) =~ s{/+\z}{};
        my $row = $_dbh->selectrow_hashref(<<'SQL', {}, $mount_id, $dir . '%');
            SELECT name, media_title FROM files
            WHERE mount_id = ?
              AND dir LIKE ?
              AND file_type = 'file'
              AND extension IN ('mkv','mp4','avi','m4v','wmv','mov','ts','mpg','mpeg')
            ORDER BY size_bytes DESC
            LIMIT 1
SQL
        return undef unless $row;
        return $row->{media_title}
            if defined $row->{media_title} && length $row->{media_title};
        return _clean_media_name($row->{name});  # filename-parsing fallback
    }

    method list_files(%args) {
        my $mount_id = $args{mount_id};
        my $filter   = $args{filter};
        my $ext      = $args{extension};
        my $type     = $args{file_type};
        my $sort_col = _safe_sort_column($args{sort_col} // 'name');
        my $sort_dir = ($args{sort_dir} // 'asc') eq 'desc' ? 'DESC' : 'ASC';
        my $page     = int($args{page} // 1);
        $page = 1 if $page < 1;
        my $per_page = int($args{per_page} // 100);
        $per_page = 10  if $per_page < 1;
        $per_page = 1000 if $per_page > 1000;
        my $offset   = ($page - 1) * $per_page;

        my (@where, @bind);

        if (defined $mount_id && length $mount_id) {
            push @where, 'mount_id = ?';
            push @bind, $mount_id;
        }
        if (defined $filter && length $filter) {
            push @where, '(name LIKE ? OR path LIKE ?)';
            my $like = '%' . $filter . '%';
            push @bind, $like, $like;
        }
        if (defined $ext && length $ext) {
            push @where, 'extension = ?';
            push @bind, $ext;
        }
        if (defined $type && length $type) {
            push @where, 'file_type = ?';
            push @bind, $type;
        }

        my $where = @where ? 'WHERE ' . join(' AND ', @where) : '';

        my ($total) = $_dbh->selectrow_array(
            "SELECT COUNT(*) FROM files $where", {}, @bind
        );

        my $rows = $_dbh->selectall_arrayref(
            "SELECT * FROM files $where ORDER BY $sort_col $sort_dir LIMIT ? OFFSET ?",
            { Slice => {} }, @bind, $per_page, $offset,
        );

        return {
            rows     => $rows,
            total    => $total // 0,
            page     => $page,
            per_page => $per_page,
            pages    => _ceil_div($total // 0, $per_page),
        };
    }

    method distinct_extensions($mount_id = undef) {
        my ($where, @bind);
        if (defined $mount_id && length $mount_id) {
            $where = 'WHERE mount_id = ?';
            @bind  = ($mount_id);
        }
        else {
            $where = '';
            @bind  = ();
        }
        my $rows = $_dbh->selectcol_arrayref(
            "SELECT DISTINCT extension FROM files $where ORDER BY extension",
            {}, @bind,
        );
        return [ grep { defined $_ && length $_ } @$rows ];
    }

    method distinct_tags() {
        my $rows = $_dbh->selectcol_arrayref(
            "SELECT DISTINCT tags FROM files WHERE tags IS NOT NULL AND tags != ''"
        );
        my (%seen, @tags);
        for my $json (@$rows) {
            my $arr = eval { JSON::PP->new->utf8->decode($json) };
            next if $@ || ref $arr ne 'ARRAY';
            for my $t (@$arr) {
                push @tags, $t unless $seen{$t}++;
            }
        }
        return [ sort @tags ];
    }

    method count_files($mount_id = undef) {
        return (defined $mount_id && length $mount_id)
            ? $_dbh->selectrow_array('SELECT COUNT(*) FROM files WHERE mount_id = ?', {}, $mount_id)
            : $_dbh->selectrow_array('SELECT COUNT(*) FROM files');
    }
}

sub _safe_sort_column ($col) {
    my %ok = map { $_ => 1 }
        qw(id name path dir extension size_bytes mtime file_type indexed_at updated_at);
    return $ok{$col} ? $col : 'name';
}

sub _ceil_div ($n, $d) {
    return 0 unless $d && $d > 0;
    return int(($n + $d - 1) / $d);
}

# Derive a human-readable title from a raw media filename.
# e.g. "Breaking.Bad.S01E01.720p.BluRay.mkv" → "Breaking Bad"
sub _clean_media_name ($name) {
    $name =~ s/\.[^.]+\z//;               # strip extension
    $name =~ s/[._]/ /g;                   # dots/underscores → spaces
    # Strip from year, season/episode tag, or quality tag onwards
    $name =~ s/\s*[\(\[]?\b(?:19|20)\d{2}\b.*\z//;
    $name =~ s/\s*\bS\d{2}E\d{2}\b.*\z//i;
    $name =~ s/\s*\b(?:720p|1080p|2160p|4K|HDTV|BluRay|WEB-?DL|REMUX|x264|x265|HEVC|AAC|DTS|AC3)\b.*\z//i;
    $name =~ s/\s+/ /g;
    $name =~ s/\A\s+|\s+\z//g;
    return length($name) ? $name : undef;
}

unless (caller) { exit 0 }

1;

__END__

=head1 NAME

Balance::FileIndex - SQLite-backed file metadata store for Balance

=head1 SYNOPSIS

  my $index = Balance::FileIndex->new(db_path => '/artifacts/balance-file-index.db');
  my $mount = $index->ensure_mount('/mnt/tv1');
  $index->upsert_file(mount_id => $mount->{id}, path => '/mnt/tv1/Show/ep.mkv', ...);
  my $result = $index->list_files(mount_id => $mount->{id}, sort_col => 'size_bytes');

=head1 DESCRIPTION

Persists file metadata (path, size, mtime, type, user tags/notes) to a
dedicated SQLite database.  Uses WAL journal mode so the indexer writer
does not block HTTP reader queries.

=head1 LICENSE

Copyright (C) 2026 Sam Robertson. This library is free software; you can
redistribute it and/or modify it under the same terms as Perl itself.

=cut
