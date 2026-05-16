package Balance::Web::Controller::Files;

use v5.42;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use source::encoding 'utf8';
use JSON::PP ();
use Mojo::Util qw(xml_escape);

our $VERSION = '0.01';

# GET /files
sub index ($c) {
    my $index  = $c->file_index;
    my $mounts = $index->all_mounts();
    my $selected_mount = $c->param('mount_id') // ($mounts->[0]{id} // '');

    # Find the mount object to get its path
    my ($mount) = grep { $_->{id} == $selected_mount } @$mounts if $selected_mount;

    $c->stash(
        mounts         => $mounts,
        selected_mount => $selected_mount,
        mount          => $mount,
        total_files    => scalar($index->count_files()),
    );
    $c->render(template => 'files/index');
}

# GET /files/dirs   (HTMX top-level dir list fragment)
sub dirs ($c) {
    my $index      = $c->file_index;
    my $mount_id   = $c->param('mount_id') // '';
    my $mounts     = $index->all_mounts();
    my ($mount)    = grep { $_->{id} == $mount_id } @$mounts if $mount_id;

    my $top_dirs = ($mount)
        ? $index->list_top_dirs($mount->{id}, $mount->{path})
        : [];

    $c->stash(
        top_dirs   => $top_dirs,
        mount      => $mount,
        mount_id   => $mount_id,
    );
    $c->render(template => 'files/_dir_list');
}

# GET /files/data   (HTMX table fragment)
sub data ($c) {
    my $index = $c->file_index;

    my $result = $index->list_files(
        mount_id  => $c->param('mount_id'),
        filter    => $c->param('q'),
        extension => $c->param('ext'),
        file_type => $c->param('type'),
        sort_col  => $c->param('sort'),
        sort_dir  => $c->param('dir'),
        page      => $c->param('page'),
        per_page  => $c->param('per'),
    );

    my $mount_id = $c->param('mount_id') // '';
    my $exts = $index->distinct_extensions($mount_id || undef);

    $c->stash(
        result       => $result,
        exts         => $exts,
        current_sort => $c->param('sort') // 'name',
        current_dir  => $c->param('dir')  // 'asc',
        mount_id     => $mount_id,
        filter       => $c->param('q')    // '',
        ext_filter   => $c->param('ext')  // '',
        type_filter  => $c->param('type') // '',
        per_page     => $c->param('per')  // 100,
    );
    $c->render(template => 'files/_table');
}

# GET /files/:id/meta  (inline read or edit display)
sub get_meta ($c) {
    my $index = $c->file_index;
    my $id    = $c->param('id');

    my $file = $index->get_file($id);
    unless ($file) {
        $c->render(text => 'Not found', status => 404);
        return;
    }

    $c->stash(file => $file);
    if ($c->param('_edit')) {
        $c->render(template => 'files/_meta_edit');
    }
    else {
        $c->render(template => 'files/_meta_cell');
    }
}

# PUT /files/:id/meta   (inline tag/notes edit)
sub update_meta ($c) {
    my $index = $c->file_index;
    my $id    = $c->param('id');

    my $file = $index->get_file($id);
    unless ($file) {
        $c->render(text => 'Not found', status => 404);
        return;
    }

    my %updates;

    if (defined(my $tags_raw = $c->param('tags'))) {
        # Accept comma-separated or JSON array
        my $tags;
        if ($tags_raw =~ /\A\s*\[/) {
            $tags = eval { JSON::PP->new->utf8->decode($tags_raw) } // [];
        }
        else {
            $tags = [ grep { length } split /\s*,\s*/, $tags_raw ];
        }
        $updates{tags} = JSON::PP->new->utf8->encode($tags);
    }

    if (defined(my $notes = $c->param('notes'))) {
        $updates{notes} = length($notes) ? $notes : undef;
    }

    $index->update_file_meta($id, %updates) if %updates;

    $file = $index->get_file($id);
    $c->stash(file => $file);
    $c->render(template => 'files/_meta_cell');
}

# GET /files/browse   (drill-through: files inside a specific directory)
sub browse ($c) {
    my $index    = $c->file_index;
    my $dir_path = $c->param('dir') // '';
    my $mount_id = $c->param('mount_id') // '';

    unless ($dir_path) {
        $c->redirect_to('/files');
        return;
    }

    my $result = $index->list_dir(
        $mount_id, $dir_path,
        sort_col => $c->param('sort'),
        sort_dir => $c->param('dir_order'),
        page     => $c->param('page'),
        per_page => $c->param('per'),
    );

    if ($c->req->headers->header('HX-Request')) {
        $c->stash(
            result       => $result,
            mount_id     => $mount_id,
            current_sort => $c->param('sort') // 'file_type',
            current_dir  => $c->param('dir_order') // 'asc',
            filter       => '',
            ext_filter   => '',
            type_filter  => '',
            per_page     => $c->param('per') // 200,
            browse_dir   => $dir_path,
        );
        $c->render(template => 'files/_table');
        return;
    }

    my $mounts = $index->all_mounts();
    $c->stash(
        mounts       => $mounts,
        mount_id     => $mount_id,
        browse_dir   => $dir_path,
        dir_name     => (split '/', $dir_path)[-1],
        result       => $result,
        current_sort => $c->param('sort') // 'file_type',
        current_dir  => $c->param('dir_order') // 'asc',
        per_page     => $c->param('per') // 200,
    );
    $c->render(template => 'files/browse');
}

# GET /files/dir-title   (lazy HTMX fragment: media title for one top-level dir)
sub dir_title ($c) {
    my $index    = $c->file_index;
    my $mount_id = $c->param('mount_id') // '';
    my $dir_path = $c->param('dir') // '';

    my $title = $index->dir_media_title($mount_id, $dir_path);
    if ($title) {
        $c->render(text => "<span class=\"text-gray-400 text-xs italic\">$title</span>");
    }
    else {
        $c->render(text => '');
    }
}

# POST /files/mounts/:id/toggle   (enable/disable a mount)
sub toggle_mount ($c) {
    my $index = $c->file_index;
    my $id    = $c->param('id');

    my $mount = $index->get_mount($id);
    unless ($mount) {
        $c->render(text => 'Not found', status => 404);
        return;
    }

    $index->set_mount_enabled($id, !$mount->{enabled});
    $c->stash(mounts => $index->all_mounts());
    $c->render(template => 'files/_scan_status');
}

# GET /files/tags   (JSON array of all distinct user-applied tags)
sub list_tags ($c) {
    my $tags = $c->file_index->distinct_tags();
    # Plain request → HTML <option> list for <datalist>; JSON accepted → JSON array
    if (($c->req->headers->accept // '') =~ m{application/json}) {
        $c->render(json => $tags);
        return;
    }
    my $html = join('', map { my $t = xml_escape($_); "<option value=\"$t\">" } @$tags);
    $c->render(text => $html, format => 'html');
}

# GET /files/export.csv
sub export_csv ($c) {
    my $index  = $c->file_index;
    my $result = $index->list_files(
        mount_id  => $c->param('mount_id'),
        filter    => $c->param('q'),
        extension => $c->param('ext'),
        file_type => $c->param('type'),
        sort_col  => 'path',
        sort_dir  => 'asc',
        per_page  => 50000,
    );

    my @cols = qw(path name dir extension size_bytes mtime file_type
                  media_title media_duration media_resolution media_codec tags notes);
    my @lines = (join(',', @cols));
    for my $row (@{ $result->{rows} }) {
        push @lines, join(',', map {
            my $v = $row->{$_} // '';
            $v =~ s/"/""/g;
            qq("$v");
        } @cols);
    }

    $c->res->headers->content_type('text/csv; charset=UTF-8');
    $c->res->headers->content_disposition('attachment; filename="files-export.csv"');
    $c->render(text => join("\n", @lines) . "\n");
}

# POST /files/bulk-tag
sub bulk_tag ($c) {
    my $index = $c->file_index;
    my @ids   = grep { /\A\d+\z/ } @{ $c->every_param('file_id') // [] };
    my $raw   = $c->param('bulk_tags') // '';
    my @tags  = grep { length } split /\s*,\s*/, $raw;

    if (@ids && @tags) {
        my $json = JSON::PP->new->utf8->encode(\@tags);
        $index->update_file_meta($_, tags => $json) for @ids;
    }

    my $mount_id = $c->param('mount_id') // '';
    my $result   = $index->list_files(
        mount_id  => $mount_id,
        filter    => $c->param('q'),
        extension => $c->param('ext'),
        file_type => $c->param('type'),
        sort_col  => $c->param('sort'),
        sort_dir  => $c->param('dir'),
        page      => $c->param('page'),
        per_page  => $c->param('per'),
    );
    $c->stash(
        result       => $result,
        current_sort => $c->param('sort') // 'name',
        current_dir  => $c->param('dir')  // 'asc',
        mount_id     => $mount_id,
        filter       => $c->param('q')   // '',
        ext_filter   => $c->param('ext') // '',
        type_filter  => $c->param('type') // '',
        per_page     => $c->param('per') // 100,
    );
    $c->render(template => 'files/_table');
}


sub scan_status ($c) {
    my $index  = $c->file_index;
    my $mounts = $index->all_mounts();
    $c->stash(mounts => $mounts);
    $c->render(template => 'files/_scan_status');
}

# POST /files/scan/start
sub scan_start ($c) {
    my $index   = $c->file_index;
    my $mount_param = $c->param('mount_id');

    my $mounts = defined $mount_param && length $mount_param
        ? [ grep { $_->{id} == $mount_param } @{ $index->all_mounts() } ]
        : $index->enabled_mounts();

    unless (@$mounts) {
        $c->render(text => 'No mounts configured', status => 422);
        return;
    }

    # Queue each mount for scanning in the app-level indexer
    for my $mount (@$mounts) {
        $c->app->_queue_indexer_scan($mount);
    }

    $c->stash(mounts => $index->all_mounts());
    $c->render(template => 'files/_scan_status');
}

# GET /files/scan/events   (SSE stream)
sub scan_events ($c) {
    $c->res->headers->content_type('text/event-stream');
    $c->res->headers->cache_control('no-cache');
    $c->res->headers->connection('keep-alive');

    my $ring   = $c->app->_indexer_event_ring;
    my $last   = $c->param('last_id') // 0;
    my $stream = $c->res->content->new_chunk_stream;

    # Send backlog of events since client's last-seen id
    my @pending = grep { $_->{id} > $last } @$ring;
    for my $ev (@pending) {
        $c->write("id: $ev->{id}\ndata: $ev->{data}\n\n");
    }

    # Register this client for future pushes
    my $client_id = $c->app->_indexer_add_sse_client($c);

    $c->on(finish => sub {
        $c->app->_indexer_remove_sse_client($client_id);
    });

    $c->render_later;
}

1;

__END__

=head1 NAME

Balance::Web::Controller::Files - File index browser controller for Balance

=head1 DESCRIPTION

Handles the /files section: sortable/filterable table, inline metadata
editing, scan status polling, manual scan trigger, and SSE scan progress.

=cut
