package Balance::Web::Controller::Dashboard;

use v5.38;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use Balance::Core qw(discover_default_mounts dir_size_kb fmt pct_fmt);

sub index ($c) {
    my @mounts = discover_default_mounts();
    my (%vol, @sizes);
    for my $m (@mounts) {
        my $used_kb = dir_size_kb($m);
        $vol{$m} = { used_kb => $used_kb, fmt => fmt($used_kb, 1024 * 1024) };
    }
    my $jobs = $c->job_store->recent_jobs(limit => 10);
    $c->render(
        template => 'dashboard/index',
        mounts   => \@mounts,
        vol      => \%vol,
        jobs     => $jobs,
    );
    return;
}

1;
