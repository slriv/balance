package Balance::ReconcileApp;

use strict;
use warnings;
use Exporter 'import';
use Getopt::Long qw(GetOptionsFromArray);
use Balance::Manifest qw(read_manifest successful_apply_records);
use Balance::PathMap qw(load_path_map);

our @EXPORT_OK = qw(run);

sub run {
    my (%args) = @_;
    my $service_name   = $args{service_name}   or die "service_name is required\n";
    my $service_module = $args{service_module} or die "service_module is required\n";

    eval "require $service_module; 1" or die $@;
    my $defaults = $service_module->defaults;

    my $manifest_file = $defaults->{manifest_file};
    my $path_map_file = $defaults->{path_map_file};
    my $report_file   = $defaults->{report_file};
    my $limit;
    my $help = 0;
    my @argv = @{ $args{argv} || [] };

    GetOptionsFromArray(
        \@argv,
        'manifest-file=s' => \$manifest_file,
        'path-map-file=s' => \$path_map_file,
        'report-file=s'   => \$report_file,
        'limit=i'         => \$limit,
        'help|h'          => \$help,
    ) or _usage($service_name, 2, 'Invalid options.');

    _usage($service_name, 0) if $help;
    die "Manifest file not found: $manifest_file\nRun an APPLY job first, or pass --manifest-file=...\n"
        unless -f $manifest_file;
    die "Path map file not found: $path_map_file\n"
        unless -f $path_map_file;

    my $records = successful_apply_records(read_manifest($manifest_file));
    if (defined $limit && $limit >= 0 && @$records > $limit) {
        @$records = @$records[0 .. $limit - 1] if $limit > 0;
        @$records = () if $limit == 0;
    }

    my $path_map = load_path_map($path_map_file);
    my $items = $service_module->build_plan(records => $records, path_map => $path_map);
    $service_module->write_report($report_file, $items);

    my $planned = scalar grep { ($_->{reconcile_status} // '') eq 'planned' } @$items;
    my $pending = scalar grep { ($_->{reconcile_status} // '') eq 'pending' } @$items;

    print ucfirst($service_name), " reconcile plan created\n";
    print "  manifest: $manifest_file\n";
    print "  path map: $path_map_file\n";
    print "  report:   $report_file\n";
    print "  records:  ", scalar(@$items), " total ($planned planned, $pending pending)\n";
    return 0;
}

sub _usage {
    my ($service_name, $exit_code, $error) = @_;
    print STDERR "$error\n\n" if defined $error && length $error;
    print STDERR <<"USAGE";
Usage: ${service_name}_reconcile.pl [options]

Build a reconciliation plan for $service_name from the apply manifest.

Options:
  --manifest-file=/path  Manifest JSONL input (default service-specific)
  --path-map-file=/path  Path mapping file (default service-specific)
  --report-file=/path    JSON report output (default service-specific)
  --limit=N              Limit records processed (for testing)
  --help, -h             Show this help message and exit
USAGE
    exit $exit_code;
}

1;
