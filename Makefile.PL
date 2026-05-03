use strict;
use warnings;
use ExtUtils::MakeMaker;
use File::ShareDir::Install;

install_share 'share';

WriteMakefile(
    NAME             => 'App::Balance',
    VERSION_FROM     => 'lib/Balance/Core.pm',
    ABSTRACT         => 'Rebalance media across mounts, syncing Sonarr and Plex',
    AUTHOR           => 'Sam Robertson <samr@slriv.com>',
    LICENSE          => 'perl',
    MIN_PERL_VERSION => '5.042',
    EXE_FILES        => [qw(
        bin/balance
        bin/sonarr_reconcile.pl
        bin/plex_reconcile.pl
        bin/balance_web.pl
    )],
    PREREQ_PM => {
        'Mojolicious'        => '9.0',
        'DBI'                => '1.643',
        'DBD::SQLite'        => '1.70',
        'File::ShareDir'     => '1.118',
        'WebService::Plex'   => '0.01',
        'LWP::UserAgent'     => '6.0',
        'JSON::XS'           => '4.0',
        'HTTP::Tiny'         => '0.070',
        'JSON::PP'           => '4.0',
    },
    TEST_REQUIRES => {
        'Test::More'         => '1.302',
        'Test::Exception'    => '0.43',
        'Test::MockModule'   => '0.177',
    },
    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources => {
            repository => {
                type => 'git',
                url  => 'https://github.com/slriv/balance.git',
                web  => 'https://github.com/slriv/balance',
            },
            bugtracker => {
                web => 'https://github.com/slriv/balance/issues',
            },
        },
    },
);

package MY;  ## no critic (Modules::ProhibitMultiplePackages)
sub postamble {
    my $self = shift;
    my $custom = <<'MAKE';
# Override TEST_FILES to discover tests recursively under t/.
# GNU Make ($(shell ...)) is required; this project targets Linux/Docker.
TEST_FILES = $(shell find t -name '*.t' | sort)
lint:
	find lib bin -type f -print0 | xargs -0 perl -Mstrict -Mwarnings -c
	find lib bin -type f -print0 | xargs -0 perlcritic --severity 4

cpan-build:
	perl Makefile.PL && perl -MExtUtils::Manifest -e 'ExtUtils::Manifest::mkmanifest()' && perl Makefile.PL && make dist

cpan-test: cpan-build
	cpanm --test-only App-Balance-*.tar.gz

MAKE
    return $custom . File::ShareDir::Install::postamble($self);
}
