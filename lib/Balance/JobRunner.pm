package Balance::JobRunner;

use v5.38;
use feature qw(class);
no warnings qw(experimental::class);  ## no critic (TestingAndDebugging::ProhibitNoWarnings)
use utf8;
use File::Path ();
use POSIX ();

class Balance::JobRunner {  ## no critic (Modules::RequireEndWithOne)

    field $log_dir :param = '/artifacts/jobs';
    field $_watchers = {};   # job_id => [ @callbacks ]
    field $_children = {};   # job_id => child pid

    # Return the log file path for a job.
    method log_path($job_id) {
        return "$log_dir/$job_id.log";
    }

    # Start a job: fork+exec @cmd, capture stdout+stderr via a pipe, wrap it
    # with Mojo::IOLoop::Stream so output is streamed to the log file and to any
    # registered watchers without blocking the event loop.
    #
    # The caller must have Mojo::IOLoop running (e.g. inside a Mojolicious app).
    method start_job($job_id, @cmd) {
        require Mojo::IOLoop;
        require Mojo::IOLoop::Stream;

        File::Path::make_path($log_dir) unless -d $log_dir;

        my $log_path = $self->log_path($job_id);
        open(my $log_fh, '>', $log_path) or die "Cannot open log $log_path: $!\n";

        # Fork and pipe stdout+stderr from child to parent.
        pipe(my $reader, my $writer) or die "Cannot create pipe: $!\n";
        my $pid = fork() // die "Cannot fork: $!\n";

        if ($pid == 0) {
            # Child: redirect stdout and stderr to write end of pipe.
            close $reader;
            open(STDOUT, '>&', $writer) or POSIX::_exit(1);
            open(STDERR, '>&', $writer) or POSIX::_exit(1);
            close $writer;
            exec { $cmd[0] } @cmd;
            POSIX::_exit(127);
        }

        # Parent: read from the read end of the pipe.
        close $writer;
        $_children->{$job_id} = $pid;

        my $stream = Mojo::IOLoop::Stream->new($reader);
        Mojo::IOLoop->singleton->stream($stream);

        $stream->on(read => sub {
            my (undef, $bytes) = @_;
            print $log_fh $bytes;
            $_->($bytes) for @{ $_watchers->{$job_id} // [] };
        });

        $stream->on(close => sub {
            close $log_fh;
            waitpid($pid, 0) if $pid;
            delete $_watchers->{$job_id};
            delete $_children->{$job_id};
        });

        $stream->start;
        return;
    }

    # Register a callback to receive live output bytes for a job.
    # Also replays the existing log file so reconnects see prior output.
    method watch_job($job_id, $cb) {
        my $log = $self->log_path($job_id);
        if (-f $log) {
            open my $fh, '<', $log or die "Cannot read log $log: $!\n";
            local $/;
            my $content = <$fh>;
            close $fh;
            $cb->($content) if length($content // '');
        }
        push @{ $_watchers->{$job_id} }, $cb;
        return;
    }

    # Remove a previously registered callback for a job.
    method unwatch_job($job_id, $cb) {
        my $list = $_watchers->{$job_id} // [];
        $_watchers->{$job_id} = [ grep { $_ != $cb } @{$list} ];
        return;
    }

    # Send SIGTERM to a running job's child process.
    method cancel_job($job_id) {
        if (my $pid = $_children->{$job_id}) {
            kill 'TERM', $pid;
        }
        return;
    }
}

1;
