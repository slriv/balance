package Balance::Web::Controller::Config;

use v5.42;
use Mojo::Base 'Mojolicious::Controller', -signatures;

our $VERSION = '0.01';
use Balance::Core qw(validate_media_path);

sub index ($self) {
    my $ac = $self->balance_config;

    $self->stash(config => {
        media_paths                => $ac->media_paths,
        balance_manifest_file      => $ac->manifest_file,
        balance_job_db             => $ac->job_db,
        balance_job_log_dir        => $ac->job_log_dir,
        sonarr_url                 => $ac->sonarr_url,
        sonarr_api_key             => $ac->sonarr_api_key,
        sonarr_audit_report_file   => $ac->sonarr_audit_report_file,
        sonarr_path_map_file       => $ac->sonarr_path_map_file,
        sonarr_report_file         => $ac->sonarr_report_file,
        sonarr_retry_queue_file    => $ac->sonarr_retry_queue_file,
        plex_url                   => $ac->plex_url,
        plex_token                 => $ac->plex_token,
        plex_path_map_file         => $ac->plex_path_map_file,
        plex_report_file           => $ac->plex_report_file,
        plex_retry_queue_file      => $ac->plex_retry_queue_file,
        plex_library_ids           => $ac->plex_library_ids,
    });
    $self->render(template => 'config/index');
    return;
}

sub _validate_url ($url) {
    return 0 unless $url =~ m{^https?://}i;
    return 0 if $url =~ m{//(?:localhost|127\.|10\.|192\.168\.|169\.254\.|::1)}i;
    return 1;
}

sub update ($self) {
    my $config = $self->balance_config;

    my $p = $self->req->json;
    if (!$p) {
        my @paths  = $self->every_param('media_path[]');
        my @labels = $self->every_param('media_label[]');
        my @media_paths;

        for my $i (0..$#paths) {
            push @media_paths, {
                path  => $paths[$i],
                label => $labels[$i] // '',
            };
        }
        $p = {
            media_paths                 => [grep { defined $_->{path} && length $_->{path} } @media_paths],
            balance_manifest_file       => scalar $self->param('balance_manifest_file'),
            balance_job_db              => scalar $self->param('balance_job_db'),
            balance_job_log_dir         => scalar $self->param('balance_job_log_dir'),
            sonarr_url                  => scalar $self->param('sonarr_url'),
            sonarr_api_key              => scalar $self->param('sonarr_api_key'),
            sonarr_audit_report_file    => scalar $self->param('sonarr_audit_report_file'),
            sonarr_path_map_file        => scalar $self->param('sonarr_path_map_file'),
            sonarr_report_file          => scalar $self->param('sonarr_report_file'),
            sonarr_retry_queue_file     => scalar $self->param('sonarr_retry_queue_file'),
            plex_url                    => scalar $self->param('plex_url'),
            plex_token                  => scalar $self->param('plex_token'),
            plex_library_ids            => scalar $self->param('plex_library_ids'),
            plex_path_map_file          => scalar $self->param('plex_path_map_file'),
            plex_report_file            => scalar $self->param('plex_report_file'),
            plex_retry_queue_file       => scalar $self->param('plex_retry_queue_file'),
        };
    }

    my $media_paths = $p->{media_paths} // [];
    unless (ref $media_paths eq 'ARRAY') {
        return $self->render(json => { success => \0, error => 'media_paths must be an array' });
    }

    my @errors;
    if (@$media_paths < 2) {
        push @errors, 'At least 2 media paths are required';
    }

    my @normalized_paths;
    for my $entry (@$media_paths) {
        unless (ref $entry eq 'HASH') {
            push @errors, 'Each media path entry must be an object';
            next;
        }
        my $path = $entry->{path} // '';
        unless (validate_media_path($path)) {
            push @errors, "Invalid media path: $path";
            next;
        }
        push @normalized_paths, {
            path   => $path,
            label  => $entry->{label} // '',
            source => 'ui',
        };
    }

    if (@errors) {
        return $self->render(json => { success => \0, error => join('; ', @errors) });
    }

    my %update = (
        balance_manifest_file    => $p->{balance_manifest_file}    // '',
        balance_job_db           => $p->{balance_job_db}           // '',
        balance_job_log_dir      => $p->{balance_job_log_dir}      // '',
        sonarr_url               => $p->{sonarr_url}               // '',
        sonarr_audit_report_file => $p->{sonarr_audit_report_file} // '',
        sonarr_path_map_file     => $p->{sonarr_path_map_file}     // '',
        sonarr_report_file       => $p->{sonarr_report_file}       // '',
        sonarr_retry_queue_file  => $p->{sonarr_retry_queue_file}  // '',
        plex_url                 => $p->{plex_url}                 // '',
        plex_path_map_file       => $p->{plex_path_map_file}       // '',
        plex_report_file         => $p->{plex_report_file}         // '',
        plex_retry_queue_file    => $p->{plex_retry_queue_file}    // '',
        plex_library_ids         => $p->{plex_library_ids}         // '1',
    );

    $update{sonarr_api_key} = $p->{sonarr_api_key} if defined $p->{sonarr_api_key} && length $p->{sonarr_api_key};
    $update{plex_token}     = $p->{plex_token}     if defined $p->{plex_token}     && length $p->{plex_token};

    try {
        $config->set_media_paths(
            [ map { { path => $_->{path}, label => $_->{label}, source => $_->{source} } } @normalized_paths ]
        );
        $config->set_bulk(\%update);
    }
    catch ($e) {
        return $self->render(json => { success => \0, error => "Failed to save configuration: $e" });
    }

    $self->render(json => {
        success => \1,
        message => 'Configuration updated successfully',
        media_paths => [ map { { path => $_->{path}, label => $_->{label} } } @normalized_paths ],
    });
    return;
}

sub test_sonarr ($self) {
    my $p       = $self->req->json // {};
    my $url     = $p->{url}     || $self->param('url')     || '';
    my $api_key = $p->{api_key} || $self->param('api_key') || '';
    
    return $self->render(json => {
        success => \0,
        error => 'URL and API key required'
    }) unless $url && $api_key;

    return $self->render(json => {
        success => \0,
        error => 'Invalid or disallowed URL'
    }) unless _validate_url($url);

    my $ua = $self->ua;
    my $test_url = "$url/api/v3/system/status";

    my $tx;
    try { $tx = $ua->get($test_url => { 'X-Api-Key' => $api_key }) }
    catch ($e) {
        return $self->render(json => { success => \0, error => "Connection failed: $e" });
    }

    my $result = $tx->result;
    if ($result->is_success) {
        my $data = $result->json || {};
        $self->render(json => {
            success => \1,
            message => 'Connected to Sonarr' . ($data->{version} ? " v$data->{version}" : ''),
        });
        return;
    }

    my $code = $result->code // '000';
    my $message = $result->message // 'Unknown error';
    $self->render(json => {
        success => \0,
        error => "HTTP $code: $message"
    });
    return;
}

sub test_plex ($self) {
    my $p     = $self->req->json // {};
    my $url   = $p->{url}   || $self->param('url')   || '';
    my $token = $p->{token} || $self->param('token') || '';

    return $self->render(json => {
        success => \0,
        error => 'URL and token required'
    }) unless $url && $token;

    return $self->render(json => {
        success => \0,
        error => 'Invalid or disallowed URL'
    }) unless _validate_url($url);

    my $ua = $self->ua;

    my $tx;
    try { $tx = $ua->get("$url/identity" => { 'X-Plex-Token' => $token }) }
    catch ($e) {
        return $self->render(json => { success => \0, error => "Connection failed: $e" });
    }

    my $result = $tx->result;
    if ($result->is_success) {
        my $data = $result->json || {};
        my $name = $data->{friendlyName} || 'Plex';
        $self->render(json => {
            success => \1,
            message => "Connected to $name"
        });
        return;
    }

    my $code = $result->code // '000';
    my $message = $result->message // 'Unknown error';
    $self->render(json => {
        success => \0,
        error => "HTTP $code: $message"
    });
    return;
}

1;

__END__

=head1 NAME

Balance::Web::Controller::Config - Balance configuration UI controller

=head1 DESCRIPTION

Handles the configuration page: reading/writing Sonarr and Plex connection
settings via L<Balance::Config>, and live connectivity testing.

=head1 LICENSE

Copyright (C) 2026 Sam Robertson. This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
