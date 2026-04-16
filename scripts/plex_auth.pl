#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long qw(GetOptions Configure);
use LWP::UserAgent;
use JSON;
use Data::GUID;
use IO::Socket::SSL;

my $app_name      = 'balance';
my $poll_interval = 2;
my $timeout       = 300;
my $help          = 0;

GetOptions(
    'app-name=s'      => \$app_name,
    'poll-interval=i' => \$poll_interval,
    'timeout=i'       => \$timeout,
    'help|h'          => \$help,
) or _usage(2);

_usage(0) if $help;

sub _usage {
    my ($exit) = @_;
    print STDERR <<"USAGE";
Usage: plex_auth.pl [options]

Authenticate with Plex.tv via the PIN flow and print your access token.
Open the URL shown in a browser, sign in, then wait for the token to appear.

Options:
  --app-name=NAME       App name shown in Plex device list (default: balance)
  --poll-interval=N     Seconds between auth checks (default: 2)
  --timeout=N           Max seconds to wait for auth (default: 300)
  --help, -h            Show this help message and exit
USAGE
    exit $exit;
}

my $client_id = Data::GUID->new->as_string;
my $ua = LWP::UserAgent->new;
$ua->ssl_opts(verify_hostname => 0, SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE);

# 1. Generate PIN
my $pin_res = $ua->post('https://plex.tv/api/v2/pins',
    'accept'       => 'application/json',
    'Content-Type' => 'application/x-www-form-urlencoded',
    Content => [
        strong                     => 'true',
        'X-Plex-Product'           => $app_name,
        'X-Plex-Client-Identifier' => $client_id,
    ]
);
die "PIN request failed: " . $pin_res->status_line . "\n" unless $pin_res->is_success;

my $pin = decode_json($pin_res->content);
my ($pin_id, $pin_code) = @{$pin}{qw(id code)};

# 2. Send user to auth URL
my $auth_url = "https://app.plex.tv/auth#?clientID=$client_id&code=$pin_code&context%5Bdevice%5D%5Bproduct%5D=$app_name";
print "Open this URL in your browser:\n$auth_url\n\n";
print "Waiting for authentication (timeout: ${timeout}s)";

# 3. Poll for token
my $token;
my $elapsed = 0;
while (!$token) {
    die "\nTimed out after ${timeout}s waiting for Plex authentication.\n" if $elapsed >= $timeout;
    sleep $poll_interval;
    $elapsed += $poll_interval;
    print ".";
    my $check = $ua->get("https://plex.tv/api/v2/pins/$pin_id",
        'accept'                   => 'application/json',
        'X-Plex-Client-Identifier' => $client_id,
    );
    next unless $check->is_success;
    my $data = decode_json($check->content);
    $token = $data->{authToken} if $data->{authToken};
}

print "\n\nPLEX_TOKEN=$token\n";
