package Balance::Web::Controller::Jobs;

use v5.38;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use POSIX qw(strftime);

sub show ($c) {
    my $job_id = $c->param('id');
    my $job    = $c->job_store->get_job($job_id);
    return $c->reply->not_found unless defined $job;
    $c->render(template => 'jobs/show', job => $job);
    return;
}

sub cancel ($c) {
    my $job_id = $c->param('id');
    $c->job_runner->cancel_job($job_id);
    $c->job_store->update_job($job_id,
        status      => 'cancelled',
        finished_at => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime),
    );
    $c->redirect_to("/jobs/$job_id");
    return;
}

# WebSocket endpoint: replay existing log then stream live output.
sub stream ($c) {
    $c->inactivity_timeout(3600);

    my $job_id = $c->param('id');
    my $cb     = sub ($bytes) { $c->send($bytes) };  ## no critic

    $c->job_runner->watch_job($job_id, $cb);

    $c->on(finish => sub {
        $c->job_runner->unwatch_job($job_id, $cb);
    });
    return;
}

1;
