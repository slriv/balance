package Balance::WebClient;
use v5.38;
use feature 'class';
no warnings 'experimental::class';  ## no critic (TestingAndDebugging::ProhibitNoWarnings)
use HTTP::Tiny;

class Balance::WebClient {  ## no critic (Modules::RequireEndWithOne)

    field $base_url :param;
    field $_http;

    ADJUST {
        die "base_url is required\n" unless length($base_url // '');
        $_http = HTTP::Tiny->new(timeout => 15);
    }

    # Accessors for subclasses (fields are private to the declaring class)
    method base_url() { $base_url }
    method _http()    { $_http }

    # Template method: subclasses override to supply service-specific auth headers.
    method _auth_headers() { {} }

    # GET helper shared by all subclasses.
    method _api_get($path) {
        return $_http->get("$base_url$path", { headers => $self->_auth_headers() });
    }
}

1;
