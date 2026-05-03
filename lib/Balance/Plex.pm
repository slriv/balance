package Balance::Plex;
use v5.42;
use experimental 'class';
use feature 'signatures';
use source::encoding 'utf8';

our $VERSION = '0.01';

class Balance::Plex {  ## no critic (Modules::RequireEndWithOne)
    use Exporter 'import';
    use JSON::PP ();
    use Getopt::Long qw(GetOptionsFromArray Configure);
    use WebService::Plex;
    use Balance::Config ();
    use Balance::Reconcile ();

    our @EXPORT_OK = qw(resolve_library_id build_plan write_report defaults cli_main);

    field $base_url :param;
    field $token    :param;
    field $_plex;

    ADJUST {
        die "base_url is required\n" unless length($base_url // '');
        die "token is required\n"    unless length($token    // '');
        $_plex = WebService::Plex->new(baseurl => $base_url, token => $token);
    }

    # --- Public API methods ---

    method list_libraries() {
        return $_plex->library->sections();
    }

    method scan_library($library_id) {
        $_plex->library->refresh_section($library_id);
        return 1;
    }

    method scan_path($library_id, $path) {
        $_plex->library->refresh_section($library_id, path => $path);
        return 1;
    }

    method empty_trash($library_id) {
        $_plex->library->empty_trash($library_id);
        return 1;
    }

    # Read a plex reconcile plan JSON, scan from/to paths for each planned item,
    # then empty trash for each affected library. Pass dry_run=>1 to preview only.
    method apply_plan(%args) {
        my $report_file = $args{report_file} or die "report_file is required\n";
        my $dry_run     = $args{dry_run} // 0;

        open my $fh, '<', $report_file or die "Can't read report $report_file: $!\n";
        my $data = JSON::PP::decode_json(do { local $/; <$fh> });
        close $fh;

        my @planned = grep { ($_->{reconcile_status} // '') eq 'planned' } @{ $data->{items} // [] };
        return { planned => 0, scanned => 0, skipped => 0, trash_emptied => [] } unless @planned;

        my $libraries = $self->list_libraries();
        my (%affected);
        my ($scanned, $skipped) = (0, 0);

        for my $item (@planned) {
            my $to   = $item->{remote_to_path}   // '';
            my $from = $item->{remote_from_path} // '';
            my $lib  = resolve_library_id(path => $to, libraries => $libraries);
            unless (defined $lib) {
                warn "No library matched for path: $to - skipping\n";
                $skipped++; next;
            }
            if ($dry_run) {
                print "DRY-RUN  scan-path lib=$lib to=$to\n";
                print "DRY-RUN  scan-path lib=$lib from=$from\n" if $from;
            } else {
                $self->scan_path($lib, $to);
                $self->scan_path($lib, $from) if $from;
            }
            $affected{$lib} = 1;
            $scanned++;
        }

        for my $lib (sort keys %affected) {
            $dry_run ? print "DRY-RUN  empty-trash lib=$lib\n"
                     : $self->empty_trash($lib);
        }

        return { planned => scalar @planned, scanned => $scanned, skipped => $skipped,
                 trash_emptied => [sort keys %affected] };
    }

    # --- Stateless exports ---

    # Given a Plex path and the already-fetched list_libraries() result, return the
    # section ID whose root path is the longest prefix of the given path.
    sub resolve_library_id(%args) {
        my $path      = $args{path}      // '';
        my $libraries = $args{libraries} or die "libraries is required\n";
        my $sections  = $libraries->{MediaContainer}{Directory} // [];
        $sections = [$sections] unless ref $sections eq 'ARRAY';
        my ($best_id, $best_len) = (undef, -1);
        for my $s (@$sections) {
            my @locs = ref($s->{Location}) eq 'ARRAY' ? @{$s->{Location}} : ($s->{Location} // ());
            for my $loc (@locs) {
                my $lp = $loc->{path} // '';
                next unless length $lp;
                my $matches_prefix   = index($path, $lp) == 0;
                my $matches_boundary = length($path) == length($lp)
                    || (length($path) > length($lp) && substr($path, length($lp), 1) eq '/');
                if ($matches_prefix && $matches_boundary && length($lp) > $best_len) {
                    $best_id  = $s->{key};
                    $best_len = length $lp;
                }
            }
        }
        return $best_id;
    }

    sub build_plan(%args) {
        return Balance::Reconcile::build_plan(service => 'plex', %args);
    }

    sub write_report($path, $items) {
        Balance::Reconcile::write_report($path, service => 'plex', items => $items);
        return;
    }

    sub defaults() {
        return Balance::Config::service_defaults('plex');
    }

    # --- CLI ---

    sub cli_main(@argv) {
        my $base_url    = '';
        my $token       = '';
        my $library_id  = '';
        my $path        = '';
        my $report_file = '';
        my $dry_run     = 0;
        my $help        = 0;

        Configure('pass_through');
        GetOptionsFromArray(
            \@argv,
            'base-url=s'     => \$base_url,
            'token=s'        => \$token,
            'library-id=s'   => \$library_id,
            'path=s'         => \$path,
            'report-file=s'  => \$report_file,
            'dry-run'        => \$dry_run,
            'help|h'         => \$help,
        ) or _cli_usage(2, 'Invalid options.');
        Configure('no_pass_through');

        my $command = shift @argv // '';

        _cli_usage(0) if $help || !$command;
        _cli_usage(2, "Unknown command: $command")
            unless grep { $_ eq $command } qw(libraries scan scan-path apply dry-run empty-trash);

        my $defs = Balance::Config::service_defaults('plex');
        $base_url ||= $defs->{base_url};
        $token    ||= $defs->{credential_value};

        die "PLEX_BASE_URL is not set. Use --base-url\n" unless $base_url;
        die "PLEX_TOKEN is not set. Use --token\n"       unless $token;

        my $plex = Balance::Plex->new(base_url => $base_url, token => $token);

        if ($command eq 'libraries') {
            my $data     = $plex->list_libraries();
            my $sections = $data->{MediaContainer}{Directory} // [];
            $sections = [$sections] unless ref $sections eq 'ARRAY';
            printf "%-6s  %-10s  %-30s  %s\n", 'ID', 'Type', 'Title', 'Path(s)';
            print  '-' x 72, "\n";
            for my $s (@$sections) {
                my @locs  = ref($s->{Location}) eq 'ARRAY' ? @{$s->{Location}} : ($s->{Location} // ());
                my $paths = join(', ', map { $_->{path} // '' } @locs);
                printf "%-6s  %-10s  %-30s  %s\n",
                    $s->{key} // '', $s->{type} // '', $s->{title} // '', $paths;
            }
            return 0;
        }

        if ($command eq 'scan') {
            _cli_usage(2, '--library-id is required for scan') unless $library_id;
            $plex->scan_library($library_id);
            print "Scan triggered for library $library_id (runs async on Plex server)\n";
            return 0;
        }

        if ($command eq 'scan-path') {
            _cli_usage(2, '--library-id is required for scan-path') unless $library_id;
            _cli_usage(2, '--path is required for scan-path')       unless $path;
            $plex->scan_path($library_id, $path);
            print "Partial scan triggered: library=$library_id path=$path\n";
            return 0;
        }

        if ($command eq 'apply' || $command eq 'dry-run') {
            $report_file ||= $defs->{report_file};
            $dry_run = 1 if $command eq 'dry-run';
            die "Report file not found: $report_file\nRun 'make plex-plan' first.\n" unless -f $report_file;
            my $r = $plex->apply_plan(report_file => $report_file, dry_run => $dry_run);
            printf "%s\n",  $dry_run ? 'Plex apply dry-run' : 'Plex apply complete';
            printf "  planned:       %d\n", $r->{planned};
            printf "  scanned:       %d\n", $r->{scanned};
            printf "  skipped:       %d\n", $r->{skipped};
            printf "  trash emptied: %s\n", @{$r->{trash_emptied}} ? join(', ', @{$r->{trash_emptied}}) : 'none';
            return 0;
        }

        if ($command eq 'empty-trash') {
            _cli_usage(2, '--library-id is required for empty-trash') unless $library_id;
            $plex->empty_trash($library_id);
            print "Trash emptied for library $library_id\n";
            return 0;
        }

        return 0;
    }

    sub _cli_usage($exit_code, $error = undef) {
        print STDERR "$error\n\n" if defined $error && length $error;
        print STDERR <<'USAGE';
Usage: plex_reconcile <command> [options]

Commands:
  libraries              List all Plex library sections with IDs and paths
  scan                   Trigger a full scan of a library section
  scan-path              Trigger a partial scan of a specific folder
  apply                  Apply reconcile plan: scan moved paths + empty trash
  dry-run                Preview apply without making API calls
  empty-trash            Empty trash for a library section

Options:
  --base-url=URL         Plex base URL
  --token=TOKEN          Plex token
  --library-id=N         Library section ID (required for scan, scan-path, empty-trash)
  --path=PATH            Folder path to scan (required for scan-path)
  --report-file=PATH     Reconcile plan JSON
  --dry-run              Preview apply actions without calling Plex API
  --help, -h             Show this help

Examples:
  plex_reconcile libraries
  plex_reconcile scan --library-id=2
  plex_reconcile scan-path --library-id=2 --path=/data/TV/Show
  plex_reconcile apply --report-file=var/reconcile-plan.json
  plex_reconcile dry-run --report-file=var/reconcile-plan.json
  plex_reconcile empty-trash --library-id=2
USAGE
        exit $exit_code;
    }
}

unless (caller) {
    $SIG{PIPE} = sub { exit 0 };
    exit Balance::Plex::cli_main(@ARGV);
}

1;

__END__

=head1 NAME

Balance::Plex - Plex Media Server reconciliation for Balance

=head1 SYNOPSIS

  use Balance::Plex;

  my $plex = Balance::Plex->new(
      base_url => 'http://plex:32400',
      token    => 'your-plex-token',
  );

  my $libs = $plex->list_libraries();
  $plex->scan_path(2, '/tv/ShowName');
  $plex->empty_trash(2);
  $plex->apply_plan(report_file => 'var/plex-reconcile.json');

=head1 DESCRIPTION

C<Balance::Plex> provides Plex library reconciliation for the Balance
media management tool. It delegates all HTTP communication to
L<WebService::Plex> and adds Balance-specific orchestration: reading
reconcile plan files, scanning affected paths, and emptying library trash.

=head1 CONSTRUCTOR

=head2 new(%args)

  my $plex = Balance::Plex->new(
      base_url => 'http://localhost:32400',
      token    => 'xxxx',
  );

=head1 METHODS

=head2 list_libraries

Returns the decoded Plex C</library/sections> response.

=head2 scan_library($library_id)

Triggers a full async scan of C<$library_id>.

=head2 scan_path($library_id, $path)

Triggers a partial scan limited to C<$path> within C<$library_id>.

=head2 empty_trash($library_id)

Empties trash for C<$library_id>.

=head2 apply_plan(%args)

Reads a Balance reconcile plan JSON (C<report_file>) and scans moved paths,
then empties trash for each affected library. Pass C<dry_run =E<gt> 1> to
preview without making API calls.

=head1 EXPORTS

C<resolve_library_id>, C<build_plan>, C<write_report>, C<defaults>,
C<cli_main> are available for export on request.

=head1 LICENSE

Copyright (C) 2026 Sam Robertson. This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
