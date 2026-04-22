package Balance::ConfigStore;

use v5.38;
use utf8;
use DBI;

sub new ($class, %args) {
    my $db_path = $args{db_path} or die "db_path required\n";
    my $dbh = DBI->connect("dbi:SQLite:$db_path", '', '', {
        RaiseError => 1,
        AutoCommit => 1,
    });
    $dbh->do(<<'SQL');
CREATE TABLE IF NOT EXISTS config (
    key TEXT PRIMARY KEY,
    value TEXT,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
)
SQL
    return bless { dbh => $dbh }, $class;
}

sub _dbh ($self) { return $self->{dbh} }

sub get ($self, $key) {
    my $row = $self->_dbh->selectrow_hashref('SELECT value FROM config WHERE key = ?', {}, $key);
    return $row ? $row->{value} : undef;
}

sub get_all ($self) {
    my $rows = $self->_dbh->selectall_arrayref('SELECT key, value FROM config ORDER BY key', { Slice => {} });
    return { map { $_->{key} => $_->{value} } @$rows };
}

sub set ($self, $key, $value) {
    die "key required\n" unless defined $key && length $key;
    $self->_dbh->do(
        'INSERT OR REPLACE INTO config (key, value, updated_at) VALUES (?, ?, CURRENT_TIMESTAMP)',
        {}, $key, $value,
    );
    return 1;
}

sub set_bulk ($self, $values) {
    die "values must be a hash ref\n" unless ref $values eq 'HASH';
    my $dbh = $self->_dbh;
    for my $key (keys %$values) {
        $dbh->do(
            'INSERT OR REPLACE INTO config (key, value, updated_at) VALUES (?, ?, CURRENT_TIMESTAMP)',
            {}, $key, $values->{$key},
        );
    }
    return 1;
}

sub delete ($self, $key) {
    $self->_dbh->do('DELETE FROM config WHERE key = ?', {}, $key);
    return 1;
}

1;
