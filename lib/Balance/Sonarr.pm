package Balance::Sonarr;

use strict;
use warnings;
use Exporter 'import';
use HTTP::Tiny;
use JSON::PP ();
use Getopt::Long qw(GetOptionsFromArray Configure);
use Balance::Config qw(service_defaults load_env_file);
use Balance::Reconcile ();

our @EXPORT_OK = qw(get_series rescan_series refresh_series update_series_path resolve_series_id apply_plan);

sub defaults {
    return service_defaults('sonarr');
}

sub build_plan {
    my ($class, %args) = @_;
    return Balance::Reconcile::build_plan(service => 'sonarr', %args);
}

sub write_report {
    my ($class, $path, $items) = @_;
    Balance::Reconcile::write_report($path, service => 'sonarr', items => $items);
}

# --- Sonarr HTTP API ---

sub _api_get {
    my ($base_url, $api_key, $path) = @_;
    my $resp = HTTP::Tiny->new(timeout => 15)->get("$base_url$path", {
        headers => { 'X-Api-Key' => $api_key, 'Accept' => 'application/json' },
    });
    return $resp;
}

sub _api_post {
    my ($base_url, $api_key, $path, $body) = @_;
    my $json = JSON::PP::encode_json($body);
    my $resp = HTTP::Tiny->new(timeout => 15)->post("$base_url$path", {
        headers => {
            'X-Api-Key'    => $api_key,
            'Content-Type' => 'application/json',
            'Accept'       => 'application/json',
        },
        content => $json,
    });
    return $resp;
}

sub _api_put {
    my ($base_url, $api_key, $path, $body) = @_;
    my $json = JSON::PP::encode_json($body);
    my $resp = HTTP::Tiny->new(timeout => 30)->put("$base_url$path", {
        headers => {
            'X-Api-Key'    => $api_key,
            'Content-Type' => 'application/json',
            'Accept'       => 'application/json',
        },
        content => $json,
    });
    return $resp;
}

sub get_series {
    my (%args) = @_;
    my $base_url = $args{base_url} or die "base_url is required\n";
    my $api_key  = $args{api_key}  or die "api_key is required\n";
    my $resp = _api_get($base_url, $api_key, '/api/v3/series');
    die "Sonarr API error: $resp->{status} $resp->{reason}\n" unless $resp->{success};
    return JSON::PP::decode_json($resp->{content});
}

sub rescan_series {
    my (%args) = @_;
    my $base_url = $args{base_url} or die "base_url is required\n";
    my $api_key  = $args{api_key}  or die "api_key is required\n";
    my $series_id = $args{series_id} // die "series_id is required\n";
    my $resp = _api_post($base_url, $api_key, '/api/v3/command',
        { name => 'RescanSeries', seriesId => int($series_id) });
    die "Sonarr API error: $resp->{status} $resp->{reason}\n" unless $resp->{success};
    return JSON::PP::decode_json($resp->{content});
}

sub refresh_series {
    my (%args) = @_;
    my $base_url = $args{base_url} or die "base_url is required\n";
    my $api_key  = $args{api_key}  or die "api_key is required\n";
    my $series_id = $args{series_id} // die "series_id is required\n";
    my $resp = _api_post($base_url, $api_key, '/api/v3/command',
        { name => 'RefreshSeries', seriesIds => [int($series_id)] });
    die "Sonarr API error: $resp->{status} $resp->{reason}\n" unless $resp->{success};
    return JSON::PP::decode_json($resp->{content});
}

# GET series/{id}, update path, PUT back. Returns updated series object.
sub update_series_path {
    my (%args) = @_;
    my $base_url  = $args{base_url}  or die "base_url is required\n";
    my $api_key   = $args{api_key}   or die "api_key is required\n";
    my $series_id = $args{series_id} // die "series_id is required\n";
    my $new_path  = $args{path}      or die "path is required\n";

    my $get = _api_get($base_url, $api_key, "/api/v3/series/$series_id");
    die "Sonarr API error getting series: $get->{status} $get->{reason}\n" unless $get->{success};
    my $series = JSON::PP::decode_json($get->{content});
    $series->{path} = $new_path;
    my $put = _api_put($base_url, $api_key, "/api/v3/series/$series_id", $series);
    die "Sonarr API error updating series: $put->{status} $put->{reason}\n" unless $put->{success};
    return JSON::PP::decode_json($put->{content});
}

# Given a NAS/remote path and the already-fetched get_series() array ref, return
# the series ID whose path is the longest prefix match of the given path.
# Exact match on series root directory is the expected common case.
sub resolve_series_id {
    my (%args) = @_;
    my $path   = $args{path}   // '';
    my $series = $args{series} or die "series is required\n";
    my ($best_id, $best_len) = (undef, -1);
    for my $s (@$series) {
        my $sp = $s->{path} // '';
        next unless length $sp;
        # Normalize: strip trailing slash for comparison
        (my $nsp = $sp) =~ s{/+$}{};
        my $matches_prefix   = index($path, $nsp) == 0;
        my $matches_boundary = length($path) == length($nsp)
            || substr($path, length($nsp), 1) eq '/';
        if ($matches_prefix && $matches_boundary && length($nsp) > $best_len) {
            $best_id  = $s->{id};
            $best_len = length $nsp;
        }
    }
    return $best_id;
}

# Read a sonarr reconcile plan JSON, update series paths and rescan for each
# planned item. Pass dry_run=>1 to preview only.
sub apply_plan {
    my (%args) = @_;
    my $base_url    = $args{base_url}    or die "base_url is required\n";
    my $api_key     = $args{api_key}     or die "api_key is required\n";
    my $report_file = $args{report_file} or die "report_file is required\n";
    my $dry_run     = $args{dry_run}     // 0;

    open my $fh, '<', $report_file or die "Can't read report $report_file: $!\n";
    my $data = JSON::PP::decode_json(do { local $/; <$fh> });
    close $fh;

    my @planned = grep { ($_->{reconcile_status} // '') eq 'planned' } @{ $data->{items} // [] };
    return { planned => 0, updated => 0, rescanned => 0, skipped => 0 } unless @planned;

    my $series_list = get_series(base_url => $base_url, api_key => $api_key);
    my ($updated, $rescanned, $skipped) = (0, 0, 0);

    for my $item (@planned) {
        my $from = $item->{remote_from_path} // '';
        my $to   = $item->{remote_to_path}   // '';
        my $id   = resolve_series_id(path => $from, series => $series_list);

        unless (defined $id) {
            warn "No series matched for path: $from — skipping\n";
            $skipped++; next;
        }

        if ($dry_run) {
            print "DRY-RUN  series=$id  from=$from\n";
            print "DRY-RUN  update-path series=$id  to=$to\n" if $to && $to ne $from;
            print "DRY-RUN  rescan series=$id\n";
        } else {
            if ($to && $to ne $from) {
                update_series_path(base_url => $base_url, api_key => $api_key,
                                   series_id => $id, path => $to);
                $updated++;
            }
            rescan_series(base_url => $base_url, api_key => $api_key, series_id => $id);
            $rescanned++;
        }
    }

    return { planned => scalar @planned, updated => $updated,
             rescanned => $rescanned, skipped => $skipped };
}

# --- CLI entrypoint (runs only when executed directly, not when used as a module) ---

unless (caller) {
    $SIG{PIPE} = sub { exit 0 };
    exit _cli_main(@ARGV);
}

sub _cli_main {
    my @argv = @_;

    my $env_file    = '.env';
    my $base_url    = '';
    my $api_key     = '';
    my $series_id   = '';
    my $new_path    = '';
    my $report_file = '';
    my $dry_run     = 0;
    my $help        = 0;

    Configure('pass_through');
    GetOptionsFromArray(
        \@argv,
        'env-file=s'     => \$env_file,
        'base-url=s'     => \$base_url,
        'api-key=s'      => \$api_key,
        'series-id=s'    => \$series_id,
        'path=s'         => \$new_path,
        'report-file=s'  => \$report_file,
        'dry-run'        => \$dry_run,
        'help|h'         => \$help,
    ) or _cli_usage(2, 'Invalid options.');
    Configure('no_pass_through');

    my $command = shift @argv // '';

    _cli_usage(0) if $help || !$command;
    _cli_usage(2, "Unknown command: $command")
        unless grep { $_ eq $command } qw(series rescan refresh apply dry-run);

    load_env_file($env_file);
    my $defaults = service_defaults('sonarr');
    $base_url ||= $defaults->{base_url};
    $api_key  ||= $defaults->{credential_value};

    die "SONARR_BASE_URL is not set. Use --base-url or set it in $env_file\n" unless $base_url;
    die "SONARR_API_KEY is not set. Use --api-key or set it in $env_file\n"   unless $api_key;

    if ($command eq 'series') {
        binmode(STDOUT, ':utf8');
        my $list = get_series(base_url => $base_url, api_key => $api_key);
        printf "%-6s  %-50s  %s\n", 'ID', 'Title', 'Path';
        print  '-' x 100, "\n";
        for my $s (sort { ($a->{sortTitle}//'') cmp ($b->{sortTitle}//'') } @$list) {
            printf "%-6s  %-50s  %s\n",
                $s->{id} // '', substr($s->{title} // '', 0, 50), $s->{path} // '';
        }
        return 0;
    }

    if ($command eq 'rescan') {
        _cli_usage(2, '--series-id is required for rescan') unless $series_id;
        my $r = rescan_series(base_url => $base_url, api_key => $api_key, series_id => $series_id);
        printf "Rescan queued for series %s (command id=%s status=%s)\n",
            $series_id, $r->{id} // '?', $r->{status} // '?';
        return 0;
    }

    if ($command eq 'refresh') {
        _cli_usage(2, '--series-id is required for refresh') unless $series_id;
        my $r = refresh_series(base_url => $base_url, api_key => $api_key, series_id => $series_id);
        printf "Refresh queued for series %s (command id=%s status=%s)\n",
            $series_id, $r->{id} // '?', $r->{status} // '?';
        return 0;
    }

    if ($command eq 'apply' || $command eq 'dry-run') {
        $report_file ||= $defaults->{report_file};
        $dry_run = 1 if $command eq 'dry-run';
        die "Report file not found: $report_file\nRun 'make sonarr-plan' first.\n" unless -f $report_file;
        my $r = apply_plan(base_url => $base_url, api_key => $api_key,
                           report_file => $report_file, dry_run => $dry_run);
        printf "%s\n",  $dry_run ? 'Sonarr apply dry-run' : 'Sonarr apply complete';
        printf "  planned:   %d\n", $r->{planned};
        printf "  updated:   %d\n", $r->{updated};
        printf "  rescanned: %d\n", $r->{rescanned};
        printf "  skipped:   %d\n", $r->{skipped};
        return 0;
    }
}

sub _cli_usage {
    my ($exit_code, $error) = @_;
    print STDERR "$error\n\n" if defined $error && length $error;
    print STDERR <<'USAGE';
Usage: perl -Ilib lib/Balance/Sonarr.pm <command> [options]

Commands:
  series                 List all Sonarr series with IDs and paths
  rescan                 Trigger a disk rescan for a series
  refresh                Trigger a metadata refresh for a series
  apply                  Apply reconcile plan: update paths + rescan series
  dry-run                Preview apply without making API calls

Options:
  --env-file=PATH        Env file to load (default: .env)
  --base-url=URL         Override SONARR_BASE_URL
  --api-key=KEY          Override SONARR_API_KEY
  --series-id=N          Series ID (required for rescan, refresh)
  --report-file=PATH     Reconcile plan JSON (default: from env/config)
  --dry-run              Preview apply actions without calling Sonarr API
  --help, -h             Show this help

Examples:
  perl -Ilib lib/Balance/Sonarr.pm series
  perl -Ilib lib/Balance/Sonarr.pm rescan --series-id=2319
  perl -Ilib lib/Balance/Sonarr.pm dry-run --report-file=artifacts/sonarr-reconcile-plan.json
  perl -Ilib lib/Balance/Sonarr.pm apply
USAGE
    exit $exit_code;
}

1;
