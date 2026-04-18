use v5.38;
use Test::More;
use Test::Exception;
use File::Temp qw(tempdir);
use Mojo::IOLoop;

use Balance::JobRunner;

my $tmp = tempdir(CLEANUP => 1);

# --- log_path ---

subtest 'log_path returns correct path' => sub {
    my $runner = Balance::JobRunner->new(log_dir => '/logs');
    is($runner->log_path('abc'), '/logs/abc.log', 'path correct');
};

# --- start_job: output written to log ---

subtest 'start_job writes command output to log file' => sub {
    my $runner = Balance::JobRunner->new(log_dir => $tmp);
    $runner->start_job('job-echo', 'echo', 'hello from job');

    Mojo::IOLoop->timer(2 => sub { Mojo::IOLoop->stop });
    Mojo::IOLoop->start;

    my $log = "$tmp/job-echo.log";
    ok(-f $log, 'log file created');
    open my $fh, '<', $log or die "no log: $!";
    my $content = do { local $/; <$fh> };
    close $fh;
    like($content, qr/hello from job/, 'log contains job output');
};

subtest 'start_job invokes on_exit callback with success result' => sub {
    my $runner = Balance::JobRunner->new(log_dir => $tmp);
    my $result;
    $runner->start_job('job-exit', 'echo', 'done', sub ($r) { $result = $r });

    Mojo::IOLoop->timer(2 => sub { Mojo::IOLoop->stop });
    Mojo::IOLoop->start;

    ok($result->{success}, 'success reported');
    is($result->{exit_code}, 0, 'exit code recorded');
    is($result->{signal}, 0, 'no signal recorded');
};

# --- watch_job: watcher receives live output ---

subtest 'watch_job callback receives output' => sub {
    my $runner = Balance::JobRunner->new(log_dir => $tmp);
    my @received;
    $runner->watch_job('job-watch', sub { push @received, @_ });
    $runner->start_job('job-watch', 'echo', 'watched output');

    Mojo::IOLoop->timer(2 => sub { Mojo::IOLoop->stop });
    Mojo::IOLoop->start;

    like(join('', @received), qr/watched output/, 'watcher received output');
};

# --- watch_job: replays existing log on register ---

subtest 'watch_job replays existing log content' => sub {
    my $log = "$tmp/job-replay.log";
    open my $fh, '>', $log; print $fh "prior output\n"; close $fh;

    my $runner  = Balance::JobRunner->new(log_dir => $tmp);
    my @replayed;
    $runner->watch_job('job-replay', sub { push @replayed, @_ });

    like(join('', @replayed), qr/prior output/, 'prior log content replayed');
};

# --- unwatch_job: removes callback ---

subtest 'unwatch_job removes the callback' => sub {
    my $runner  = Balance::JobRunner->new(log_dir => $tmp);
    my @got;
    my $cb = sub { push @got, @_ };
    $runner->watch_job('job-unwatch', $cb);
    $runner->unwatch_job('job-unwatch', $cb);
    $runner->start_job('job-unwatch', 'echo', 'should not be received');

    Mojo::IOLoop->timer(2 => sub { Mojo::IOLoop->stop });
    Mojo::IOLoop->start;

    is(scalar @got, 0, 'unregistered callback not called');
};

# --- cancel_job: terminates running job ---

subtest 'cancel_job terminates slow job cleanly' => sub {
    my $runner = Balance::JobRunner->new(log_dir => $tmp);
    $runner->start_job('job-cancel', 'sleep', '30');

    # Cancel after the next event loop tick
    Mojo::IOLoop->next_tick(sub { $runner->cancel_job('job-cancel') });
    Mojo::IOLoop->timer(3 => sub { Mojo::IOLoop->stop });
    Mojo::IOLoop->start;

    pass('cancel did not hang');
};

done_testing;
