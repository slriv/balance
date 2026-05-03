use v5.38;
use Test::More;
use Test::Exception;
use Test::MockModule;
use JSON::PP ();

use Balance::Plex qw(resolve_library_id build_plan defaults);

{
    package Local::FakePlexLibrary;

    sub new ($class, %args) {
        return bless \%args, $class;
    }

    sub sections ($self) {
        my $impl = $self->{sections};
        return ref $impl eq 'CODE' ? $impl->() : $impl;
    }

    sub refresh_section ($self, @args) {
        my $impl = $self->{refresh_section};
        return ref $impl eq 'CODE' ? $impl->(@args) : 1;
    }

    sub empty_trash ($self, @args) {
        my $impl = $self->{empty_trash};
        return ref $impl eq 'CODE' ? $impl->(@args) : 1;
    }
}

{
    package Local::FakePlex;

    sub new ($class, $library) {
        return bless { library => $library }, $class;
    }

    sub library ($self) {
        return $self->{library};
    }
}

# Helper to build the Plex list_libraries() response shape
sub _libs {
    my @sections = @_;
    return { MediaContainer => { Directory => \@sections } };
}

# --- resolve_library_id ---

subtest 'resolve_library_id dies without libraries' => sub {
    dies_ok { resolve_library_id(path => '/mnt/tv', libraries => undef) }
        'dies on undef libraries';
};

subtest 'resolve_library_id returns undef for no match' => sub {
    my $libs = _libs({ key => '1', Location => { path => '/mnt/movies' } });
    is(resolve_library_id(path => '/mnt/tv/Show', libraries => $libs), undef, 'no match -> undef');
};

subtest 'resolve_library_id matches single-location library' => sub {
    my $libs = _libs(
        { key => '1', Location => { path => '/mnt/movies' } },
        { key => '2', Location => { path => '/mnt/tv' } },
    );
    is(resolve_library_id(path => '/mnt/tv/Show/S01', libraries => $libs), '2', 'matches tv library');
};

subtest 'resolve_library_id picks longest matching prefix' => sub {
    my $libs = _libs(
        { key => '1', Location => { path => '/mnt/tv' } },
        { key => '2', Location => { path => '/mnt/tv/anime' } },
    );
    is(
        resolve_library_id(path => '/mnt/tv/anime/Show/S01', libraries => $libs),
        '2',
        'longer prefix wins'
    );
};

subtest 'resolve_library_id handles multi-location library' => sub {
    my $libs = _libs(
        { key => '3', Location => [{ path => '/mnt/tv' }, { path => '/mnt/tv2' }] },
    );
    is(resolve_library_id(path => '/mnt/tv2/Show', libraries => $libs), '3', 'second location matches');
};

subtest 'resolve_library_id does not do partial dir name matches' => sub {
    my $libs = _libs({ key => '1', Location => { path => '/mnt/tv' } });
    is(resolve_library_id(path => '/mnt/tvseries/Show', libraries => $libs), undef, 'no partial match');
};

# --- build_plan ---

subtest 'build_plan returns arrayref' => sub {
    my $items = build_plan(records => [], path_map => []);
    is_deeply($items, [], 'empty records -> empty plan');
};

# --- defaults ---

subtest 'defaults returns hashref with required keys' => sub {
    my $d = defaults();
    ok(defined $d->{base_url},      'base_url present');
    ok(defined $d->{manifest_file}, 'manifest_file present');
    ok(defined $d->{path_map_file}, 'path_map_file present');
    ok(defined $d->{report_file},   'report_file present');
};

# --- Balance::Plex class construction ---

subtest 'new dies without base_url' => sub {
    dies_ok { Balance::Plex->new(token => 'tok') } 'dies without base_url';
};

subtest 'new dies without token' => sub {
    dies_ok { Balance::Plex->new(base_url => 'http://plex:32400') } 'dies without token';
};

subtest 'new dies on empty token' => sub {
    dies_ok { Balance::Plex->new(base_url => 'http://plex:32400', token => '') } 'dies on empty token';
};

# --- WebService::Plex-backed API methods (mocked) ---

my $mock_wsplex = Test::MockModule->new('WebService::Plex');

subtest 'list_libraries returns parsed response' => sub {
    my $payload = { MediaContainer => { Directory =>
        { key => '1', title => 'TV', type => 'show', Location => { path => '/mnt/tv' } }
    } };
    my $fake = Local::FakePlex->new(
        Local::FakePlexLibrary->new(sections => $payload)
    );
    $mock_wsplex->mock(new => sub { return $fake; });
    my $plex = Balance::Plex->new(base_url => 'http://plex:32400', token => 'tok');
    my $data = $plex->list_libraries();
    is($data->{MediaContainer}{Directory}{key}, '1', 'library key');
    $mock_wsplex->unmock('new');
};

subtest 'list_libraries dies on API error' => sub {
    my $fake = Local::FakePlex->new(
        Local::FakePlexLibrary->new(sections => sub { die "HTTP error: 401 Unauthorized\n" })
    );
    $mock_wsplex->mock(new => sub { return $fake; });
    my $plex = Balance::Plex->new(base_url => 'http://plex:32400', token => 'tok');
    dies_ok { $plex->list_libraries() } 'dies on API error';
    $mock_wsplex->unmock('new');
};

subtest 'scan_path calls API and returns 1' => sub {
    my @calls;
    my $fake = Local::FakePlex->new(
        Local::FakePlexLibrary->new(
            refresh_section => sub (@args) { push @calls, \@args; return 1; },
        )
    );
    $mock_wsplex->mock(new => sub { return $fake; });
    my $plex = Balance::Plex->new(base_url => 'http://plex:32400', token => 'tok');
    is($plex->scan_path('2', '/mnt/tv/Show'), 1, 'returns 1');
    is_deeply($calls[0], ['2', path => '/mnt/tv/Show'], 'refresh_section called with library id and path');
    $mock_wsplex->unmock('new');
};

subtest 'empty_trash calls API and returns 1' => sub {
    my @calls;
    my $fake = Local::FakePlex->new(
        Local::FakePlexLibrary->new(
            empty_trash => sub (@args) { push @calls, \@args; return 1; },
        )
    );
    $mock_wsplex->mock(new => sub { return $fake; });
    my $plex = Balance::Plex->new(base_url => 'http://plex:32400', token => 'tok');
    is($plex->empty_trash('2'), 1, 'returns 1');
    is_deeply($calls[0], ['2'], 'empty_trash called with library id');
    $mock_wsplex->unmock('new');
};

# --- apply_plan ---

subtest 'apply_plan dry-run prints actions and returns counts' => sub {
    use File::Temp qw(tempfile);
    my $plan = {
        items => [
            { reconcile_status => 'planned',
              remote_from_path => '/mnt/tv/Show A',
              remote_to_path   => '/mnt/tv/Show A moved' },
            { reconcile_status => 'ok',
              remote_from_path => '/mnt/tv/Show B',
              remote_to_path   => '/mnt/tv/Show B moved' },
        ],
    };
    my ($fh, $path) = tempfile(SUFFIX => '.json', UNLINK => 1);
    print {$fh} JSON::PP::encode_json($plan);
    close $fh;

    my $plex = Balance::Plex->new(base_url => 'http://plex:32400', token => 'tok');
    my $mock_plex = Test::MockModule->new('Balance::Plex');
    $mock_plex->mock('list_libraries', sub {
        return { MediaContainer => { Directory =>
            { key => '2', title => 'TV', type => 'show', Location => { path => '/mnt/tv' } }
        } };
    });
    my $out = '';
    open my $save_out, '>&', \*STDOUT or die;
    close STDOUT;
    open STDOUT, '>>', \$out or die;
    my $r = $plex->apply_plan(report_file => $path, dry_run => 1);
    close STDOUT;
    open STDOUT, '>&', $save_out or die;

    is($r->{planned}, 1, 'one planned item');
    is($r->{skipped}, 0, 'none skipped');
    is(scalar @{$r->{trash_emptied}}, 1, 'one library queued for trash');
    like($out, qr/DRY-RUN.*lib=2/i, 'dry-run output mentions library id');
    $mock_plex->unmock('list_libraries');
};

subtest 'apply_plan skips items with no matching library' => sub {
    use File::Temp qw(tempfile);
    my $plan = {
        items => [
            { reconcile_status => 'planned',
              remote_from_path => '/mnt/nowhere/Show X',
              remote_to_path   => '/mnt/nowhere2/Show X' },
        ],
    };
    my ($fh, $path) = tempfile(SUFFIX => '.json', UNLINK => 1);
    print {$fh} JSON::PP::encode_json($plan);
    close $fh;

    my $plex = Balance::Plex->new(base_url => 'http://plex:32400', token => 'tok');
    my $mock_plex = Test::MockModule->new('Balance::Plex');
    $mock_plex->mock('list_libraries', sub {
        return { MediaContainer => { Directory =>
            { key => '2', title => 'TV', type => 'show', Location => { path => '/mnt/tv' } }
        } };
    });
    my $r = $plex->apply_plan(report_file => $path, dry_run => 1);
    is($r->{planned}, 1, 'one planned item');
    is($r->{skipped}, 1, 'unmatched item skipped');
    $mock_plex->unmock('list_libraries');
};

subtest 'apply_plan returns zero counts on empty plan' => sub {
    use File::Temp qw(tempfile);
    my $plan = { items => [] };
    my ($fh, $path) = tempfile(SUFFIX => '.json', UNLINK => 1);
    print {$fh} JSON::PP::encode_json($plan);
    close $fh;

    my $plex = Balance::Plex->new(base_url => 'http://plex:32400', token => 'tok');
    my $r = $plex->apply_plan(report_file => $path, dry_run => 1);
    is($r->{planned}, 0, 'zero planned');
};

done_testing;
