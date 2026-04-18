package Balance::Config;

use v5.38;
use feature qw(signatures try);
no warnings qw(experimental::try);  ## no critic (TestingAndDebugging::ProhibitNoWarnings)
use utf8;
use Exporter 'import';

our @EXPORT_OK = qw(load_env_file service_defaults redact_value);

sub load_env_file($path) {
    return 0 unless defined $path && -f $path;

    open my $fh, '<', $path or die "Can't read env file $path: $!\n";
    while (my $line = <$fh>) {
        chomp $line;
        $line =~ s/^\s+|\s+$//g;
        next unless length $line;
        next if $line =~ /^#/;
        my ($key, $value) = split /\s*=\s*/, $line, 2;
        next unless defined $key && length $key;
        next unless defined $value;
        $value =~ s/^(['"])(.*?)\1$/$2/;
        $ENV{$key} = $value unless exists $ENV{$key};
    }
    close $fh;
    return 1;
}

sub service_defaults($service) {
    die "service is required\n" unless defined $service && length $service;

    my %common = (
        manifest_file => $ENV{BALANCE_MANIFEST_FILE} || '/artifacts/balance-apply-manifest.jsonl',
    );

    return {
        %common,
        base_url         => $ENV{SONARR_BASE_URL} || '',
        credential_name  => 'SONARR_API_KEY',
        credential_value => $ENV{SONARR_API_KEY} || '',
        audit_report_file => $ENV{SONARR_AUDIT_REPORT_FILE} || '/artifacts/sonarr-audit-report.json',
        path_map_file    => $ENV{SONARR_PATH_MAP_FILE} || '/config/sonarr-path-map.example',
        report_file      => $ENV{SONARR_REPORT_FILE} || '/artifacts/sonarr-reconcile-plan.json',
        retry_queue_file => $ENV{SONARR_RETRY_QUEUE_FILE} || '/artifacts/sonarr-retry-queue.jsonl',
    } if $service eq 'sonarr';

    return {
        %common,
        base_url         => $ENV{PLEX_BASE_URL} || '',
        credential_name  => 'PLEX_TOKEN',
        credential_value => $ENV{PLEX_TOKEN} || '',
        path_map_file    => $ENV{PLEX_PATH_MAP_FILE} || '/config/plex-path-map.example',
        report_file      => $ENV{PLEX_REPORT_FILE} || '/artifacts/plex-reconcile-plan.json',
        retry_queue_file => $ENV{PLEX_RETRY_QUEUE_FILE} || '/artifacts/plex-retry-queue.jsonl',
        library_ids      => $ENV{PLEX_LIBRARY_IDS} || '',
    } if $service eq 'plex';

    die "Unknown service: $service\n";
}

sub redact_value($value) {
    return '(unset)' unless defined $value && length $value;
    return '****' if length($value) <= 4;
    return substr($value, 0, 2) . ('*' x (length($value) - 4)) . substr($value, -2);
}

1;
