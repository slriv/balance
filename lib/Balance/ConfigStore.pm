package Balance::ConfigStore;

use v5.42;
use experimental 'class';
use source::encoding 'utf8';
use DBI ();

our $VERSION = '0.01';

class Balance::ConfigStore {  ## no critic (Modules::RequireEndWithOne)

    field $db_path :param;
    field $_dbh;

    ADJUST {
        die "db_path required\n" unless length($db_path // '');
        $_dbh = DBI->connect("dbi:SQLite:$db_path", '', '', {
            RaiseError => 1,
            AutoCommit => 1,
        }) or die "Cannot open $db_path: $DBI::errstr\n";
        $_dbh->do(<<'SQL');
CREATE TABLE IF NOT EXISTS config (
    key TEXT PRIMARY KEY,
    value TEXT,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
)
SQL
    }

    method get($key) {
        my $row = $_dbh->selectrow_hashref('SELECT value FROM config WHERE key = ?', {}, $key);
        return $row ? $row->{value} : undef;
    }

    method get_all() {
        my $rows = $_dbh->selectall_arrayref('SELECT key, value FROM config ORDER BY key', { Slice => {} });
        return { map { $_->{key} => $_->{value} } @$rows };
    }

    method set($key, $value) {
        die "key required\n" unless defined $key && length $key;
        $_dbh->do(
            'INSERT OR REPLACE INTO config (key, value, updated_at) VALUES (?, ?, CURRENT_TIMESTAMP)',
            {}, $key, $value,
        );
        return 1;
    }

    method set_bulk($values) {
        die "values must be a hash ref\n" unless ref $values eq 'HASH';
        for my $key (keys %$values) {
            $_dbh->do(
                'INSERT OR REPLACE INTO config (key, value, updated_at) VALUES (?, ?, CURRENT_TIMESTAMP)',
                {}, $key, $values->{$key},
            );
        }
        return 1;
    }

    method delete($key) {
        $_dbh->do('DELETE FROM config WHERE key = ?', {}, $key);
        return 1;
    }
}

1;

__END__

=head1 NAME

Balance::ConfigStore - SQLite-backed persistent configuration store

=head1 DESCRIPTION

Stores key/value configuration in a SQLite database shared with
L<Balance::JobStore>. Used by the web UI to persist Sonarr/Plex
connection settings between container restarts.

=head1 LICENSE

Copyright (C) 2026 Sam Robertson. GNU General Public License v3 or later.

=cut
