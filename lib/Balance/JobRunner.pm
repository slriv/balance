package Balance::JobRunner;

use v5.42;
use experimental 'class';
use source::encoding 'utf8';
use File::Path ();
use POSIX ();

our $VERSION = '0.01';

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

        my $on_exit;
        if (@cmd && ref($cmd[-1]) eq 'CODE') {
            $on_exit = pop @cmd;
        }

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
            exec { $cmd[0] } @cmd or POSIX::_exit(127);
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
            my $wait_status = 0;
            if ($pid) {
                waitpid($pid, 0);
                $wait_status = $?;
            }
            $on_exit->({
                success   => (($wait_status >> 8) == 0 && ($wait_status & 127) == 0),
                exit_code => ($wait_status >> 8),
                signal    => ($wait_status & 127),
            }) if $on_exit;
            delete $_watchers->{$job_id};
            delete $_children->{$job_id};
        });

        $stream->start;
        return;
    }

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

__END__

=head1 NAME

Balance::JobRunner - Async job execution for the Balance web UI

=head1 DESCRIPTION

Forks and exec's Balance CLI commands inside the Mojo::IOLoop event loop,
streaming stdout/stderr to a log file and to registered WebSocket watchers
in real time. Used by L<Balance::Web::Controller::Jobs>.

=head1 LICENSE

Copyright (C) 2026 Sam Robertson. GNU General Public License v3 or later.

=cut
