use v5.38;
use Test::More;
use Test::Exception;
use File::Temp qw(tempfile);

use Balance::PathMap qw(load_path_map translate_path);

# --- load_path_map ---

subtest 'load_path_map dies on missing file' => sub {
    dies_ok { load_path_map('/nonexistent/path-map.conf') } 'dies on missing';
};

subtest 'load_path_map dies if no valid entries' => sub {
    my ($fh, $path) = tempfile(UNLINK => 1);
    print {$fh} "# only comments\n\n";
    close $fh;
    dies_ok { load_path_map($path) } 'dies on no usable entries';
};

subtest 'load_path_map dies on non-absolute path' => sub {
    my ($fh, $path) = tempfile(UNLINK => 1);
    print {$fh} "relative/path = /dest\n";
    close $fh;
    dies_ok { load_path_map($path) } 'dies on relative source';
};

subtest 'load_path_map parses key=value entries' => sub {
    my ($fh, $path) = tempfile(UNLINK => 1);
    print {$fh} "/nas/tv = /mnt/tv\n";
    print {$fh} "# comment\n";
    print {$fh} "/nas/movies = /mnt/movies  # inline comment\n";
    close $fh;
    my $maps = load_path_map($path);
    is(scalar @{$maps}, 2, 'two mappings');
    # longer prefix first (longest-match sorting)
    is($maps->[0]{from}, '/nas/movies', 'first by length desc');
};

subtest 'load_path_map strips trailing slashes from paths' => sub {
    my ($fh, $path) = tempfile(UNLINK => 1);
    print {$fh} "/nas/tv/ = /mnt/tv/\n";
    close $fh;
    my $maps = load_path_map($path);
    is($maps->[0]{from}, '/nas/tv',  'from stripped');
    is($maps->[0]{to},   '/mnt/tv',  'to stripped');
};

# --- translate_path ---

my $maps = [
    { from => '/nas/tv/dramas', to => '/mnt/shows/dramas' },
    { from => '/nas/tv',        to => '/mnt/shows' },
];

subtest 'translate_path returns undef for undef input' => sub {
    is(translate_path($maps, undef), undef, 'undef path -> undef');
};

subtest 'translate_path uses longest prefix match' => sub {
    is(
        translate_path($maps, '/nas/tv/dramas/Show/S01'),
        '/mnt/shows/dramas/Show/S01',
        'longer prefix matched first'
    );
};

subtest 'translate_path falls back to shorter prefix' => sub {
    is(
        translate_path($maps, '/nas/tv/comedy/Show/S01'),
        '/mnt/shows/comedy/Show/S01',
        'falls back to shorter prefix'
    );
};

subtest 'translate_path does not match partial directory name' => sub {
    # /nas/tvseries should NOT match /nas/tv
    is(
        translate_path($maps, '/nas/tvseries/Show'),
        undef,
        'no partial dir name match'
    );
};

subtest 'translate_path returns undef for no match' => sub {
    is(translate_path($maps, '/other/path'), undef, 'no match -> undef');
};

subtest 'translate_path handles empty maps' => sub {
    is(translate_path([], '/nas/tv/show'), undef, 'empty maps -> undef');
};

done_testing;
