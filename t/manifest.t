use strict;
use warnings;
use Test::More;

eval { require Test::DistManifest };
if ($@) {
    plan skip_all => 'Test::DistManifest required for manifest test';
}

Test::DistManifest::manifest_ok();
