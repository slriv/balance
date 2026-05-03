package Balance::Config;

use v5.42;
use experimental 'class';
use source::encoding 'utf8';
use JSON::PP;
use DBI ();

our $VERSION = '0.01';

class Balance::Config {  ## no critic (Modules::RequireEndWithOne)

    field $db_path :param = '/artifacts/balance-jobs.db';
    field $_dbh;
    field %_cfg;

    ADJUST {
        die "db_path required\n" unless length($db_path // '');
        $_dbh = DBI->connect("dbi:SQLite:$db_path", '', '', {
            RaiseError    => 1,
            AutoCommit    => 1,
            sqlite_unicode => 1,
        }) or die "Cannot open $db_path: $DBI::errstr\n";

        $_dbh->do(<<'SQL');
CREATE TABLE IF NOT EXISTS config (
    key        TEXT PRIMARY KEY,
    value      TEXT,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
)
SQL

        %_cfg = %{ $self->_read_all };
    }

    # --- Generic key/value API (hash-like) ---

    method get($key, $default = undef) {
        die "key required\n" unless defined $key && length $key;
        return exists $_cfg{$key} ? $_cfg{$key} : $default;
    }

    method set($key, $value) {
        die "key required\n" unless defined $key && length $key;
        $_dbh->do(
            'INSERT OR REPLACE INTO config (key, value, updated_at) VALUES (?, ?, CURRENT_TIMESTAMP)',
            {}, $key, $value,
        );
        $_cfg{$key} = $value;
        return $self;
    }

    method set_bulk($values) {
        die "values must be a hash ref\n" unless ref $values eq 'HASH';
        for my $key (keys %$values) {
            $_dbh->do(
                'INSERT OR REPLACE INTO config (key, value, updated_at) VALUES (?, ?, CURRENT_TIMESTAMP)',
                {}, $key, $values->{$key},
            );
        }
        @_cfg{ keys %$values } = values %$values;
        return $self;
    }

    method delete($key) {
        die "key required\n" unless defined $key && length $key;
        $_dbh->do('DELETE FROM config WHERE key = ?', {}, $key);
        delete $_cfg{$key};
        return $self;
    }

    method exists($key) {
        die "key required\n" unless defined $key && length $key;
        return exists $_cfg{$key};
    }

    method all() {
        return { %_cfg };
    }

    method reload() {
        %_cfg = %{ $self->_read_all };
        return $self;
    }

    method value($key, @maybe_value) {
        return @maybe_value ? do {
            $self->set($key, $maybe_value[0]);
            $maybe_value[0];
        } : $self->get($key);
    }

    # --- Media paths ---

    method media_paths() {
        my $json = $self->get('media_paths');
        return [] unless defined $json && length $json;

        my $paths = eval { JSON::PP->new->utf8->decode($json) };
        if ($@) {
            warn "Invalid media_paths JSON in config store: $@";
            return [];
        }
        unless (ref $paths eq 'ARRAY') {
            warn "media_paths in config store is not an array; ignoring\n";
            return [];
        }
        return $paths;
    }

    method set_media_paths($paths) {
        die "media_paths must be an array ref\n" unless ref $paths eq 'ARRAY';
        for my $entry (@$paths) {
            die "media_paths entries must be hash refs\n" unless ref $entry eq 'HASH';
            die "media_paths entries require a path\n"
                unless defined $entry->{path} && length $entry->{path};
        }

        my $json = JSON::PP->new->utf8->encode($paths);
        $self->set('media_paths', $json);
        return $self;
    }

    method delete_media_paths() {
        $self->delete('media_paths');
        return $self;
    }

    method media_mounts() {
        return map { $_->{path} }
               grep { defined $_->{path} && length $_->{path} }
               @{ $self->media_paths };
    }

    # --- Sonarr convenience ---

    method sonarr_url()               { $self->get('sonarr_url', '') }
    method sonarr_api_key()           { $self->get('sonarr_api_key', '') }
    method sonarr_report_file()       { my $v = $self->get('sonarr_report_file');       return (defined $v && length $v) ? $v : '/artifacts/sonarr-reconcile-plan.json'; }
    method sonarr_audit_report_file() { my $v = $self->get('sonarr_audit_report_file'); return (defined $v && length $v) ? $v : '/artifacts/sonarr-audit-report.json'; }
    method sonarr_path_map_file()     { my $v = $self->get('sonarr_path_map_file');     return (defined $v && length $v) ? $v : '/config/sonarr-path-map.example'; }
    method sonarr_retry_queue_file()  { my $v = $self->get('sonarr_retry_queue_file');  return (defined $v && length $v) ? $v : '/artifacts/sonarr-retry-queue.jsonl'; }

    method has_sonarr() {
        return length($self->sonarr_url) && length($self->sonarr_api_key);
    }

    # --- Plex convenience ---

    method plex_url()              { $self->get('plex_url', '') }
    method plex_token()            { $self->get('plex_token', '') }
    method plex_report_file()      { my $v = $self->get('plex_report_file');      return (defined $v && length $v) ? $v : '/artifacts/plex-reconcile-plan.json'; }
    method plex_path_map_file()    { my $v = $self->get('plex_path_map_file');    return (defined $v && length $v) ? $v : '/config/plex-path-map.example'; }
    method plex_retry_queue_file() { my $v = $self->get('plex_retry_queue_file'); return (defined $v && length $v) ? $v : '/artifacts/plex-retry-queue.jsonl'; }
    method plex_library_ids()      { my $v = $self->get('plex_library_ids');      return (defined $v && length $v) ? $v : ''; }

    method has_plex() {
        return length($self->plex_url) && length($self->plex_token);
    }

    # --- Runtime convenience ---

    method job_db()        { my $v = $self->get('balance_job_db');        return (defined $v && length $v) ? $v : '/artifacts/balance-jobs.db'; }
    method job_log_dir()   { my $v = $self->get('balance_job_log_dir');   return (defined $v && length $v) ? $v : '/artifacts/jobs'; }
    method manifest_file() { my $v = $self->get('balance_manifest_file'); return (defined $v && length $v) ? $v : '/artifacts/balance-apply-manifest.jsonl'; }

    method _read_all() {
        my $rows = $_dbh->selectall_arrayref('SELECT key, value FROM config ORDER BY key', { Slice => {} });
        return { map { $_->{key} => $_->{value} } @$rows };
    }
}

sub service_defaults($service) {
    die "service is required\n" unless defined $service && length $service;

    my %common = (
        manifest_file => '/artifacts/balance-apply-manifest.jsonl',
    );

    return {
        %common,
        base_url         => '',
        credential_name  => 'SONARR_API_KEY',
        credential_value => '',
        audit_report_file => '/artifacts/sonarr-audit-report.json',
        path_map_file    => '/config/sonarr-path-map.example',
        report_file      => '/artifacts/sonarr-reconcile-plan.json',
        retry_queue_file => '/artifacts/sonarr-retry-queue.jsonl',
    } if $service eq 'sonarr';

    return {
        %common,
        base_url         => '',
        credential_name  => 'PLEX_TOKEN',
        credential_value => '',
        path_map_file    => '/config/plex-path-map.example',
        report_file      => '/artifacts/plex-reconcile-plan.json',
        retry_queue_file => '/artifacts/plex-retry-queue.jsonl',
        library_ids      => '',
    } if $service eq 'plex';

    die "Unknown service: $service\n";
}

sub redact_value($value) {
    return '(unset)' unless defined $value && length $value;
    return '****' if length($value) <= 4;
    return substr($value, 0, 2) . ('*' x (length($value) - 4)) . substr($value, -2);
}

1;

__END__

=head1 NAME

Balance::Config - Configuration defaults for Balance services

=head1 SYNOPSIS

    use Balance::Config;

    my $cfg = Balance::Config->new(db_path => '/path/to/config.db');

    # Generic hash-like API
    $cfg->set('sonarr_url', 'http://sonarr:8989');
    my $url = $cfg->get('sonarr_url');

    my $defs = Balance::Config::service_defaults('sonarr');
    my $safe = Balance::Config::redact_value($defs->{credential_value});

=head1 DESCRIPTION

Single persisted configuration module for Balance. Stores key/value state in
SQLite and exposes both generic key-based access and convenience methods.

=head1 LICENSE

Copyright (C) 2026 Sam Robertson. This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
