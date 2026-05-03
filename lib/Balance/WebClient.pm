package Balance::WebClient;
use v5.42;
use experimental 'class';
use HTTP::Tiny;

our $VERSION = '0.01';

class Balance::WebClient {  ## no critic (Modules::RequireEndWithOne)

    field $base_url :param :reader;
    field $_http    :reader;

    ADJUST {
        die "base_url is required\n" unless length($base_url // '');
        $_http = HTTP::Tiny->new(timeout => 15);
    }

    # Template method: subclasses override to supply service-specific auth headers.
    method _auth_headers() { {} }

    # GET helper shared by all subclasses.
    method _api_get($path) {
        return $_http->get("$base_url$path", { headers => $self->_auth_headers() });
    }
}

1;

__END__

=head1 NAME

Balance::WebClient - HTTP client base class for Balance service integrations

=head1 DESCRIPTION

Base class providing a shared L<HTTP::Tiny> instance and a C<_api_get>
template method. Subclassed by L<Balance::Sonarr>; L<Balance::Plex> now
delegates to L<WebService::Plex> directly and no longer inherits from this.

=head1 LICENSE

Copyright (C) 2026 Sam Robertson. This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
