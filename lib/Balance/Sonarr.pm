package Balance::Sonarr;
use v5.42;
use experimental 'class';
use source::encoding 'utf8';
use Balance::WebClient;

our $VERSION = '0.01';

class Balance::Sonarr :isa(Balance::WebClient) {  ## no critic (Modules::RequireEndWithOne)
    use Exporter 'import';
    use HTTP::Tiny;
    use JSON::PP ();
    use Getopt::Long qw(GetOptionsFromArray Configure);
    use Balance::Config ();
    use Balance::Reconcile ();
    use Balance::AuditSonarr ();  # called as Balance::AuditSonarr::* so mocks intercept

    our @EXPORT_OK = qw(resolve_series_id build_plan write_report defaults cli_main);

    field $api_key :param;

    ADJUST {
        die "api_key is required\n" unless length($api_key // '');
    }

    # --- Private HTTP helpers ---

    method _auth_headers() {
        return { 'X-Api-Key' => $api_key, 'Accept' => 'application/json' };
    }

    # _api_get is inherited from Balance::WebClient

    method _api_post($path, $body) {
        my $json = JSON::PP::encode_json($body);
        return $self->_http->post($self->base_url . $path, {
            headers => {
                'X-Api-Key'    => $api_key,
                'Content-Type' => 'application/json',
                'Accept'       => 'application/json',
            },
            content => $json,
        });
    }

    method _api_put($path, $body) {
        my $json = JSON::PP::encode_json($body);
        # 30s timeout: PUT /series sends the full series object back in the response
        # and Sonarr may take longer to process a path update than a simple GET.
        return HTTP::Tiny->new(timeout => 30)->put($self->base_url . $path, {
            headers => {
                'X-Api-Key'    => $api_key,
                'Content-Type' => 'application/json',
                'Accept'       => 'application/json',
            },
            content => $json,
        });
    }

    # --- Public API methods ---

    method get_series() {
        my $resp = $self->_api_get('/api/v3/series');
        die "Sonarr API error: $resp->{status} $resp->{reason}\n" unless $resp->{success};
        return JSON::PP::decode_json($resp->{content});
    }

    method rescan_series($series_id) {
        my $resp = $self->_api_post('/api/v3/command',
            { name => 'RescanSeries', seriesId => int($series_id) });
        die "Sonarr API error: $resp->{status} $resp->{reason}\n" unless $resp->{success};
        return JSON::PP::decode_json($resp->{content});
    }

    method refresh_series($series_id) {
        my $resp = $self->_api_post('/api/v3/command',
            { name => 'RefreshSeries', seriesIds => [int($series_id)] });
        die "Sonarr API error: $resp->{status} $resp->{reason}\n" unless $resp->{success};
        return JSON::PP::decode_json($resp->{content});
    }

    # GET series/{id}, update path, PUT back. Returns updated series object.
    method update_series_path($series_id, $new_path) {
        my $get = $self->_api_get("/api/v3/series/$series_id");
        die "Sonarr API error getting series: $get->{status} $get->{reason}\n" unless $get->{success};
        my $series = JSON::PP::decode_json($get->{content});
        $series->{path} = $new_path;
        my $put = $self->_api_put("/api/v3/series/$series_id", $series);
        die "Sonarr API error updating series: $put->{status} $put->{reason}\n" unless $put->{success};
        return JSON::PP::decode_json($put->{content});
    }

    # Return all Sonarr root folder objects (each has a 'path' field).
    method get_root_folders() {
        my $resp = $self->_api_get('/api/v3/rootfolder');
        die "Sonarr API error: $resp->{status} $resp->{reason}\n" unless $resp->{success};
        return JSON::PP::decode_json($resp->{content});
    }

    # Audit all series against disk.  Fetches series + root folders from Sonarr,
    # runs audit_series on each, and writes a JSON report (unless dry_run=>1).
    # Returns: { total => N, ok => N, missing => N, fixable => N, ambiguous => N }
    method audit(%args) {
        my $report_file = $args{report_file} or die "report_file is required\n";
        my $dry_run     = $args{dry_run} // 0;

        my $series_list  = $self->get_series();
        my $root_folders = $self->get_root_folders();
        my @roots        = map { $_->{path} } @{$root_folders};

        my @items;
        for my $s (@{$series_list}) {
            push @items, Balance::AuditSonarr::audit_series($s, \@roots);
        }

        Balance::AuditSonarr::write_audit_report($report_file, \@items) unless $dry_run;

        my %counts;
        $counts{$_->{status}}++ for @items;
        return { total => scalar @items, %counts, items => \@items };
    }

    # Read a fixable audit report and update Sonarr paths + rescan each series.
    # Pass dry_run=>1 to preview only.
    # Returns: { fixable => N, repaired => N }
    method repair(%args) {
        my $report_file = $args{report_file} or die "report_file is required\n";
        my $dry_run     = $args{dry_run} // 0;

        my $all_items = Balance::AuditSonarr::read_audit_report($report_file);
        my @fixable   = grep { ($_->{status} // '') eq 'fixable' } @{$all_items};

        my $repaired = 0;
        for my $item (@fixable) {
            my $id  = $item->{id};
            my $new = $item->{candidate_path};
            if ($dry_run) {
                print "DRY-RUN  update-path series=$id  to=$new\n";
                next;
            }
            $self->update_series_path($id, $new);
            $self->rescan_series($id);
            $repaired++;
        }

        return { fixable => scalar @fixable, repaired => $repaired };
    }

    # Read a sonarr reconcile plan JSON, update series paths and rescan for each
    # planned item. Pass dry_run=>1 to preview only.
    method apply_plan(%args) {
        my $report_file = $args{report_file} or die "report_file is required\n";
        my $dry_run     = $args{dry_run} // 0;

        open my $fh, '<', $report_file or die "Can't read report $report_file: $!\n";
        my $data = JSON::PP::decode_json(do { local $/; <$fh> });
        close $fh;

        my @planned = grep { ($_->{reconcile_status} // '') eq 'planned' } @{ $data->{items} // [] };
        return { planned => 0, updated => 0, rescanned => 0, skipped => 0 } unless @planned;

        my $series_list = $self->get_series();
        my ($updated, $rescanned, $skipped) = (0, 0, 0);

        for my $item (@planned) {
            my $from = $item->{remote_from_path} // '';
            my $to   = $item->{remote_to_path}   // '';
            my $id   = resolve_series_id(path => $from, series => $series_list);

            unless (defined $id) {
                warn "No series matched for path: $from - skipping\n";
                $skipped++; next;
            }

            if ($dry_run) {
                print "DRY-RUN  series=$id  from=$from\n";
                print "DRY-RUN  update-path series=$id  to=$to\n" if $to && $to ne $from;
                print "DRY-RUN  rescan series=$id\n";
            } else {
                if ($to && $to ne $from) {
                    $self->update_series_path($id, $to);
                    $updated++;
                }
                $self->rescan_series($id);
                $rescanned++;
            }
        }

        return { planned => scalar @planned, updated => $updated,
                 rescanned => $rescanned, skipped => $skipped };
    }

    # --- Stateless exports (Pattern A) ---

    # Given a NAS/remote path and the already-fetched get_series() array ref, return
    # the series ID whose path is the longest prefix match of the given path.
    sub resolve_series_id(%args) {
        my $path   = $args{path}   // '';
        my $series = $args{series} or die "series is required\n";
        my ($best_id, $best_len) = (undef, -1);
        for my $s (@$series) {
            my $sp = $s->{path} // '';
            next unless length $sp;
            (my $nsp = $sp) =~ s{/+$}{};
            next unless length $nsp;
            my $matches_prefix   = index($path, $nsp) == 0;
            my $matches_boundary = length($path) == length($nsp)
                || (length($path) > length($nsp) && substr($path, length($nsp), 1) eq '/');
            if ($matches_prefix && $matches_boundary && length($nsp) > $best_len) {
                $best_id  = $s->{id};
                $best_len = length $nsp;
            }
        }
        return $best_id;
    }

    sub build_plan(%args) {
        return Balance::Reconcile::build_plan(service => 'sonarr', %args);
    }

    sub write_report($path, $items) {
        Balance::Reconcile::write_report($path, service => 'sonarr', items => $items);
        return;
    }

    sub defaults() {
        return Balance::Config::service_defaults('sonarr');
    }

    # --- CLI ---

    sub cli_main(@argv) {
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
            unless grep { $_ eq $command } qw(series rescan refresh apply dry-run audit repair audit-dry-run repair-dry-run);

        my $defs = Balance::Config::service_defaults('sonarr');
        $base_url ||= $defs->{base_url};
        $api_key  ||= $defs->{credential_value};

        die "SONARR_BASE_URL is not set. Use --base-url\n" unless $base_url;
        die "SONARR_API_KEY is not set. Use --api-key\n"   unless $api_key;

        my $sonarr = Balance::Sonarr->new(base_url => $base_url, api_key => $api_key);

        if ($command eq 'series') {
            binmode(STDOUT, ':encoding(UTF-8)');
            my $list = $sonarr->get_series();
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
            my $r = $sonarr->rescan_series($series_id);
            printf "Rescan queued for series %s (command id=%s status=%s)\n",
                $series_id, $r->{id} // '?', $r->{status} // '?';
            return 0;
        }

        if ($command eq 'refresh') {
            _cli_usage(2, '--series-id is required for refresh') unless $series_id;
            my $r = $sonarr->refresh_series($series_id);
            printf "Refresh queued for series %s (command id=%s status=%s)\n",
                $series_id, $r->{id} // '?', $r->{status} // '?';
            return 0;
        }

        if ($command eq 'apply' || $command eq 'dry-run') {
            $report_file ||= $defs->{report_file};
            $dry_run = 1 if $command eq 'dry-run';
            die "Report file not found: $report_file\nRun 'make sonarr-plan' first.\n" unless -f $report_file;
            my $r = $sonarr->apply_plan(report_file => $report_file, dry_run => $dry_run);
            printf "%s\n",  $dry_run ? 'Sonarr apply dry-run' : 'Sonarr apply complete';
            printf "  planned:   %d\n", $r->{planned};
            printf "  updated:   %d\n", $r->{updated};
            printf "  rescanned: %d\n", $r->{rescanned};
            printf "  skipped:   %d\n", $r->{skipped};
            return 0;
        }

        if ($command eq 'audit' || $command eq 'audit-dry-run') {
            $report_file ||= $defs->{audit_report_file};
            $dry_run = 1 if $command eq 'audit-dry-run';
            my $r = $sonarr->audit(report_file => $report_file, dry_run => $dry_run);
            printf "%s\n", $dry_run ? 'Sonarr audit dry-run' : "Sonarr audit complete: $report_file";
            printf "  total:     %d\n", $r->{total}     // 0;
            printf "  ok:        %d\n", $r->{ok}        // 0;
            printf "  missing:   %d\n", $r->{missing}   // 0;
            printf "  fixable:   %d\n", $r->{fixable}   // 0;
            printf "  ambiguous: %d\n", $r->{ambiguous} // 0;
            return 0;
        }

        if ($command eq 'repair' || $command eq 'repair-dry-run') {
            $report_file ||= $defs->{audit_report_file};
            $dry_run = 1 if $command eq 'repair-dry-run';
            die "Audit report not found: $report_file\nRun 'sonarr audit' first.\n" unless -f $report_file;
            my $r = $sonarr->repair(report_file => $report_file, dry_run => $dry_run);
            printf "%s\n", $dry_run ? 'Sonarr repair dry-run' : 'Sonarr repair complete';
            printf "  fixable:   %d\n", $r->{fixable}  // 0;
            printf "  repaired:  %d\n", $r->{repaired} // 0;
            return 0;
        }

        return 0;
    }

    sub _cli_usage($exit_code, $error = undef) {
        print STDERR "$error\n\n" if defined $error && length $error;
        print STDERR <<'USAGE';
Usage: perl -Ilib lib/Balance/Sonarr.pm <command> [options]

Commands:
  series                 List all Sonarr series with IDs and paths
  rescan                 Trigger a disk rescan for a series
  refresh                Trigger a metadata refresh for a series
  apply                  Apply reconcile plan: update paths + rescan series
  dry-run                Preview apply without making API calls
    audit                  Audit Sonarr series paths against accessible roots
    audit-dry-run          Preview audit counts without writing the audit report
    repair                 Repair fixable audit entries and rescan updated series
    repair-dry-run         Preview repair actions without changing Sonarr

Options:
  --base-url=URL         Sonarr base URL
  --api-key=KEY          Sonarr API key
  --series-id=N          Series ID (required for rescan, refresh)
    --report-file=PATH     Reconcile plan JSON or audit report JSON
    --dry-run              Preview actions without calling Sonarr API
  --help, -h             Show this help

Examples:
  perl -Ilib lib/Balance/Sonarr.pm series
  perl -Ilib lib/Balance/Sonarr.pm rescan --series-id=123
  perl -Ilib lib/Balance/Sonarr.pm refresh --series-id=123
  perl -Ilib lib/Balance/Sonarr.pm apply --report-file=var/reconcile-plan.json
  perl -Ilib lib/Balance/Sonarr.pm dry-run --report-file=var/reconcile-plan.json
    perl -Ilib lib/Balance/Sonarr.pm audit --report-file=var/sonarr-audit-report.json
    perl -Ilib lib/Balance/Sonarr.pm repair-dry-run --report-file=var/sonarr-audit-report.json
USAGE
        exit $exit_code;
    }
}

unless (caller) {
    $SIG{PIPE} = sub { exit 0 };
    exit Balance::Sonarr::cli_main(@ARGV);
}

1;

__END__

=head1 NAME

Balance::Sonarr - Sonarr API client and reconciliation for Balance

=head1 SYNOPSIS

  use Balance::Sonarr;

  my $sonarr = Balance::Sonarr->new(
      base_url => 'http://sonarr:8989',
      api_key  => 'your-sonarr-api-key',
  );

  my $series = $sonarr->list_series();
  $sonarr->update_path($series_id, $new_path);
  $sonarr->apply_plan(report_file => 'var/sonarr-reconcile.json');

=head1 DESCRIPTION

C<Balance::Sonarr> provides a Sonarr v3 API client and reconciliation
workflow for the Balance media management tool. It reads a Balance reconcile
plan file and updates Sonarr series paths after media moves, with optional
dry-run preview and retry-queue support.

=head1 LICENSE

Copyright (C) 2026 Sam Robertson. This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
