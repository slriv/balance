package Balance::ConfigStore;

use v5.38;
use utf8;
use feature qw(class try);
no warnings qw(experimental::class experimental::try);
use DBI ();

class Balance::ConfigStore {  ## no critic (Modules::RequireEndWithOne)
    field $db_path :param;
    field $dbh;

    ADJUST {
        $dbh = DBI->connect("dbi:SQLite:$db_path", '', '', {
            RaiseError => 1,
            AutoCommit => 1,
            sqlite_unicode => 1,
        }) or die "Cannot open config database $db_path: $DBI::errstr\n";
        $dbh->do(<<'SQL');
CREATE TABLE IF NOT EXISTS config (
    key        TEXT PRIMARY KEY,
    value      TEXT,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
)
SQL
    }

    method get ($key) {
        my $row = $dbh->selectrow_hashref(
            'SELECT value FROM config WHERE key = ?', {}, $key
        );
        return $row ? $row->{value} : undef;
    }

    method get_all () {
        my $rows = $dbh->selectall_arrayref(
            'SELECT key, value FROM config ORDER BY key', { Slice => {} }
        );
        return { map { $_->{key} => $_->{value} } @$rows };
    }

    method set ($key, $value) {
        die "key required\n" unless defined $key && length $key;
        $dbh->do(
            'INSERT OR REPLACE INTO config (key, value, updated_at) VALUES (?, ?, CURRENT_TIMESTAMP)',
            {}, $key, $value,
        );
        return 1;
    }

    method set_bulk ($values) {
        die "values must be a hash ref\n" unless ref $values eq 'HASH';
        for my $key (keys %$values) {
            $dbh->do(
                'INSERT OR REPLACE INTO config (key, value, updated_at) VALUES (?, ?, CURRENT_TIMESTAMP)',
                {}, $key, $values->{$key},
            );
        }
        return 1;
    }

    method delete ($key) {
        $dbh->do('DELETE FROM config WHERE key = ?', {}, $key);
        return 1;
    }
}

1;
