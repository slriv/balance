use v5.38;
use Test::More;
use Test::Exception;
use File::Temp qw(tempfile);
use JSON::PP ();

use Balance::Reconcile qw(build_plan write_report);

# --- build_plan ---

my $path_map = [
    { from => '/nas/tv', to => '/mnt/tv' },
];

subtest 'build_plan dies without service' => sub {
    dies_ok { build_plan(records => []) } 'dies without service';
};

subtest 'build_plan returns empty list for empty records' => sub {
    my $items = build_plan(service => 'sonarr', records => [], path_map => $path_map);
    is_deeply($items, [], 'empty records -> empty plan');
};

subtest 'build_plan sets planned status when path translates' => sub {
    my $records = [
        { from_path => '/nas/tv/Show/S01', to_path => '/nas/tv/Show/S02', title => 'Show' },
    ];
    my $items = build_plan(service => 'sonarr', records => $records, path_map => $path_map);
    is(scalar @{$items}, 1, 'one item');
    my $item = $items->[0];
    is($item->{reconcile_status},   'planned',          'status planned');
    is($item->{service},            'sonarr',           'service set');
    is($item->{remote_from_path},   '/mnt/tv/Show/S01', 'remote_from translated');
    is($item->{remote_to_path},     '/mnt/tv/Show/S02', 'remote_to translated');
    ok(!exists $item->{reason},                          'no reason when planned');
};

subtest 'build_plan sets pending + reason when no path map match' => sub {
    my $records = [
        { from_path => '/unmapped/path', to_path => '/also/unmapped', title => 'X' },
    ];
    my $items = build_plan(service => 'sonarr', records => $records, path_map => $path_map);
    my $item = $items->[0];
    is($item->{reconcile_status}, 'pending',          'status pending');
    is($item->{reason},           'no_path_mapping',  'reason set');
};

subtest 'build_plan preserves original record fields' => sub {
    my $records = [
        { from_path => '/nas/tv/A', to_path => '/nas/tv/B', series_id => 42, title => 'A' },
    ];
    my $items = build_plan(service => 'sonarr', records => $records, path_map => $path_map);
    is($items->[0]{series_id}, 42, 'original fields preserved');
    is($items->[0]{title},     'A', 'title preserved');
};

# --- write_report ---

subtest 'write_report dies on bad path' => sub {
    dies_ok { write_report('/nonexistent/dir/report.json', service => 's', items => []) }
        'dies on unwritable path';
};

subtest 'write_report writes valid JSON with expected keys' => sub {
    my ($fh, $path) = tempfile(SUFFIX => '.json', UNLINK => 1);
    close $fh;

    my $items = [
        { reconcile_status => 'planned' },
        { reconcile_status => 'planned' },
        { reconcile_status => 'pending' },
    ];
    write_report($path, service => 'sonarr', items => $items);

    open my $rfh, '<', $path or die $!;
    my $json = do { local $/; <$rfh> };
    close $rfh;

    my $data = JSON::PP::decode_json($json);
    is($data->{service},          'sonarr',  'service field');
    is($data->{counts}{planned},  2,         'planned count');
    is($data->{counts}{pending},  1,         'pending count');
    is(scalar @{$data->{items}},  3,         'items preserved');
    like($data->{generated_at}, qr/^\d{4}-\d{2}-\d{2}/, 'generated_at timestamp');
};

done_testing;
