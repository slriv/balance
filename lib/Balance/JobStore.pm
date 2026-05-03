package Balance::JobStore;

use v5.42;
use experimental 'class';
use source::encoding 'utf8';

our $VERSION = '0.01';

class Balance::JobStore {  ## no critic (Modules::RequireEndWithOne)
    use DBI ();

    field $db_path :param = '/artifacts/balance-jobs.db';
    field $log_dir :param = '/artifacts/jobs';
    field $_dbh;

    my method _init_db() {
        $_dbh->do(<<~'SQL');
            CREATE TABLE IF NOT EXISTS jobs (
                id          TEXT PRIMARY KEY,
                type        TEXT NOT NULL,
                status      TEXT NOT NULL DEFAULT 'queued',
                created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
                started_at  TEXT,
                finished_at TEXT
            )
        SQL
        return;
    }

    ADJUST {
        $_dbh = DBI->connect(
            "dbi:SQLite:dbname=$db_path", '', '',
            { RaiseError => 1, AutoCommit => 1, sqlite_unicode => 1 },
        ) or die "Cannot open job database $db_path: $DBI::errstr\n";
        $self->&_init_db();
    }

    # Insert a new job, guarded by BEGIN IMMEDIATE to prevent concurrent inserts
    # while a job is already running.  Dies if another job is running.
    # Returns $id.
    method insert_job($id, $type) {
        try {
            $_dbh->do('BEGIN IMMEDIATE');
            my $running = $_dbh->selectrow_arrayref(
                "SELECT id FROM jobs WHERE status = 'running' LIMIT 1"
            );
            if ($running) {
                die "A job is already running: $running->[0]\n";
            }
            $_dbh->do(
                "INSERT INTO jobs (id, type, status) VALUES (?, ?, 'queued')",
                {}, $id, $type,
            );
            $_dbh->do('COMMIT');
        }
        catch ($e) {
            try { $_dbh->do('ROLLBACK') } catch ($re) {}
            die $e;
        }
        return $id;
    }

    # Update mutable job fields (status, started_at, finished_at).
    method update_job($id, %fields) {
        my @allowed = qw(status started_at finished_at);
        my @cols    = grep { exists $fields{$_} } @allowed;
        return unless @cols;
        my $set  = join ', ', map { "$_ = ?" } @cols;
        my @vals = map { $fields{$_} } @cols;
        $_dbh->do("UPDATE jobs SET $set WHERE id = ?", {}, @vals, $id);
        return;
    }

    # Return a single job hashref, or undef if not found.
    method get_job($id) {
        return $_dbh->selectrow_hashref(
            'SELECT * FROM jobs WHERE id = ?', {}, $id
        );
    }

    # Return the N most recently created jobs (descending by created_at).
    method recent_jobs(%args) {
        my $limit = $args{limit} // 20;
        return $_dbh->selectall_arrayref(
            'SELECT * FROM jobs ORDER BY created_at DESC LIMIT ?',
            { Slice => {} }, $limit,
        );
    }

    # Return the filesystem path where a job's log is stored.
    method log_path($job_id) {
        return "$log_dir/$job_id.log";
    }
}

1;

__END__

=head1 NAME

Balance::JobStore - SQLite-backed job metadata store for Balance

=head1 DESCRIPTION

Persists job records (id, type, status, timestamps) to SQLite. Ensures only
one job runs at a time via C<BEGIN IMMEDIATE> locking on insert.

=head1 LICENSE

Copyright (C) 2026 Sam Robertson. This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
