package Balance::Web::Controller::Config;

use v5.42;
use Mojo::Base 'Mojolicious::Controller', -signatures;

our $VERSION = '0.01';
use Balance::ConfigStore;

sub index ($self) {
    my $config_store = $self->config_store;
    my $config = $config_store->get_all;
    
    # Get environment variables as defaults
    my $env_config = {
        tv_path_1        => $ENV{TV_PATH_1} || '/srv/tv',
        tv_path_2        => $ENV{TV_PATH_2} || '/srv/tv2',
        tv_path_3        => $ENV{TV_PATH_3} || '/srv/tv3',
        tv_path_4        => $ENV{TV_PATH_4} || '/srv/tvnas2',
        sonarr_url       => $ENV{SONARR_BASE_URL} || '',
        sonarr_api_key   => $ENV{SONARR_API_KEY} || '',
        plex_url         => $ENV{PLEX_BASE_URL} || '',
        plex_token       => $ENV{PLEX_TOKEN} || '',
        plex_library_ids => $ENV{PLEX_LIBRARY_IDS} || '1',
    };
    
    # Merge database config (overrides env)
    for my $key (keys %$env_config) {
        if (defined $config->{$key}) {
            $env_config->{$key} = $config->{$key};
        }
    }
    
    $self->stash(config => $env_config);
    $self->render(template => 'config/index');
    return;
}

sub _validate_url ($url) {
    return 0 unless $url =~ m{^https?://}i;
    return 0 if $url =~ m{//(?:localhost|127\.|10\.|192\.168\.|169\.254\.|::1)}i;
    return 1;
}

sub update ($self) {
    my $config_store = $self->config_store;

    my @keys = qw(tv_path_1 tv_path_2 tv_path_3 tv_path_4
                  sonarr_url sonarr_api_key plex_url plex_token plex_library_ids);
    my $p = $self->req->json // { map { $_ => scalar $self->param($_) } @keys };

    my %update = (
        tv_path_1        => $p->{tv_path_1}        // '',
        tv_path_2        => $p->{tv_path_2}        // '',
        tv_path_3        => $p->{tv_path_3}        // '',
        tv_path_4        => $p->{tv_path_4}        // '',
        sonarr_url       => $p->{sonarr_url}       // '',
        plex_url         => $p->{plex_url}         // '',
        plex_library_ids => $p->{plex_library_ids} // '1',
    );

    # Only update credentials when explicitly provided (avoids overwriting with blank)
    $update{sonarr_api_key} = $p->{sonarr_api_key} if $p->{sonarr_api_key};
    $update{plex_token}     = $p->{plex_token}     if $p->{plex_token};
    
    $config_store->set_bulk(\%update);
    
    # Also update ENV for current session
    $ENV{TV_PATH_1}        = $update{tv_path_1}        if $update{tv_path_1};
    $ENV{TV_PATH_2}        = $update{tv_path_2}        if $update{tv_path_2};
    $ENV{TV_PATH_3}        = $update{tv_path_3}        if $update{tv_path_3};
    $ENV{TV_PATH_4}        = $update{tv_path_4}        if $update{tv_path_4};
    $ENV{SONARR_BASE_URL}  = $update{sonarr_url}       if $update{sonarr_url};
    $ENV{SONARR_API_KEY}   = $update{sonarr_api_key}   if $update{sonarr_api_key};
    $ENV{PLEX_BASE_URL}    = $update{plex_url}         if $update{plex_url};
    $ENV{PLEX_TOKEN}       = $update{plex_token}       if $update{plex_token};
    $ENV{PLEX_LIBRARY_IDS} = $update{plex_library_ids} if $update{plex_library_ids};
    
    $self->render(json => {
        success => \1,
        message => 'Configuration updated successfully'
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
settings via L<Balance::ConfigStore>, and live connectivity testing.

=head1 LICENSE

Copyright (C) 2026 Sam Robertson. GNU General Public License v3 or later.

=cut
