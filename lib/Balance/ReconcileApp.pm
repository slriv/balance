package Balance::ReconcileApp;

use v5.38;
use feature qw(signatures try);
no warnings qw(experimental::try);  ## no critic (TestingAndDebugging::ProhibitNoWarnings)
use utf8;
use Exporter 'import';
use FindBin qw($Bin);
use Getopt::Long qw(GetOptionsFromArray Configure);
use Balance::Config qw(load_env_file redact_value);
use Balance::Manifest qw(read_manifest successful_apply_records);
use Balance::PathMap qw(load_path_map);

our @EXPORT_OK = qw(run);

sub run(%args) {
    my $service_name   = $args{service_name}   or die "service_name is required\n";
    my $service_module = $args{service_module} or die "service_module is required\n";
    my $env_file = "$Bin/../.env";
    my $show_config = 0;
    my $limit;
    my $help = 0;
    my $manifest_file;
    my $path_map_file;
    my $report_file;
    my @argv = @{ $args{argv} || [] };

    Configure('pass_through');
    GetOptionsFromArray(
        \@argv,
        'env-file=s'       => \$env_file,
        'show-config'      => \$show_config,
        'limit=i'          => \$limit,
        'help|h'           => \$help,
    ) or _usage($service_name, 2, 'Invalid options.');
    Configure('no_pass_through');

    load_env_file($env_file);

    die "Invalid service_module name: $service_module\n"
        unless $service_module =~ /\A[A-Za-z][A-Za-z0-9]*(?:::[A-Za-z][A-Za-z0-9]*)*\z/;
    (my $module_path = $service_module) =~ s{::}{/}g;
    require "$module_path.pm";  ## no critic (Modules::RequireBarewordIncludes)
    my $defaults = $service_module->defaults;

    $manifest_file = $defaults->{manifest_file};
    $path_map_file = $defaults->{path_map_file};
    $report_file   = $defaults->{report_file};

    GetOptionsFromArray(
        \@argv,
        'manifest-file=s' => \$manifest_file,
        'path-map-file=s' => \$path_map_file,
        'report-file=s'   => \$report_file,
    ) or _usage($service_name, 2, 'Invalid options.');

    _usage($service_name, 0) if $help;
    if ($show_config) {
        _print_config($service_name, $env_file, $defaults, $manifest_file, $path_map_file, $report_file);
        return 0;
    }
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

sub _usage($service_name, $exit_code, $error = undef) {
    print STDERR "$error\n\n" if defined $error && length $error;
    print STDERR <<"USAGE";
Usage: ${service_name}_reconcile.pl [options]

Build a reconciliation plan for $service_name from the apply manifest.

Options:
    --env-file=/path       Optional env file to load before defaults (.env)
    --show-config          Print resolved config with redacted credentials
  --manifest-file=/path  Manifest JSONL input (default service-specific)
  --path-map-file=/path  Path mapping file (default service-specific)
  --report-file=/path    JSON report output (default service-specific)
  --limit=N              Limit records processed (for testing)
  --help, -h             Show this help message and exit
USAGE
    exit $exit_code;
}

sub _print_config($service_name, $env_file, $defaults, $manifest_file, $path_map_file, $report_file) {
    print ucfirst($service_name), " config\n";
    print "  env file:    $env_file\n";
    print "  base url:    ", (($defaults->{base_url} || '') || '(unset)'), "\n";
    print "  credential:  $defaults->{credential_name}=", redact_value($defaults->{credential_value}), "\n"
        if $defaults->{credential_name};
    print "  manifest:    $manifest_file\n";
    print "  path map:    $path_map_file\n";
    print "  report:      $report_file\n";
    print "  retry queue: $defaults->{retry_queue_file}\n" if $defaults->{retry_queue_file};
    print "  library ids: $defaults->{library_ids}\n" if exists $defaults->{library_ids};
    return;
}

1;
