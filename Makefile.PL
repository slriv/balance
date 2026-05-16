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
        script/balance
        script/balance_sonarr
        script/balance_plex
        script/balance_web
    )],
    PREREQ_PM => {
        'Mojolicious'        => '9.0',
        'DBI'                => '1.643',
        'DBD::SQLite'        => '1.70',
        'File::ShareDir'     => '1.118',
        'WebService::Plex'   => '0.01',
        'WebService::Arr'    => '0.001',
        'LWP::UserAgent'     => '6.0',
        'JSON::XS'           => '4.0',
        'HTTP::Tiny'         => '0.070',
        'JSON::PP'           => '4.0',
        # Optional: real-time inotify file watching (falls back to polling)
        # 'Linux::Inotify2'  => '2.3',
        # Optional: media metadata extraction from video/audio files
        # 'Image::ExifTool'  => '12.0',
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
sub clean {
    my $self = shift;
    my $text = $self->SUPER::clean(@_);
    # Do not rename Makefile to Makefile.old during 'make clean'; that's for 'make realclean'
    $text =~ s/\t- \$\(MV\) \$\(FIRST_MAKEFILE\) \$\(MAKEFILE_OLD\) \$\(DEV_NULL\)\n//;
    return $text;
}

sub top_targets {
    my $self = shift;
    my $text = $self->SUPER::top_targets(@_);
    my $help = <<'HELP';
help :
	@echo "App::Balance -- available make targets"
	@echo ""
	@echo "  Build and install:"
	@echo "    make                   Build (same as make all)"
	@echo "    make install           Install to site Perl"
	@echo "    make uninstall         Remove installed files"
	@echo ""
	@echo "  Distribution:"
	@echo "    make cpan-build        Build .tar.gz for CPAN upload"
	@echo "    make dist              Build .tar.gz distribution"
	@echo "    make distcheck         Verify MANIFEST matches files on disk"
	@echo ""
	@echo "  Development:"
	@echo "    make lint              Check code style and Perl syntax"
	@echo ""
	@echo "  Clean:"
	@echo "    make clean             Remove build artifacts"
	@echo "    make realclean         Remove build artifacts and generated Makefile"

HELP
    $text =~ s/^help\b[^\n]*\n\t[^\n]*\n/$help/m;
    return $text;
}

sub postamble {
    my $self = shift;
    my $custom = <<'MAKE';
lint:
	find lib bin -type f -print0 | xargs -0 perl -Mstrict -Mwarnings -c
	find lib bin -type f -print0 | xargs -0 perlcritic --severity 4

cpan-build:
	perl Makefile.PL && perl -MExtUtils::Manifest -e 'ExtUtils::Manifest::mkmanifest()' && perl Makefile.PL && make dist

# When INSTALL_BASE is used, these variables must be redirected to the
# install-base paths so `make uninstall` removes the correct packlist.
UNINSTALL := $(ABSPERLRUN) -MExtUtils::Install -e 'uninstall(shift,1,0);' --
SITEARCHEXP := $(INSTALLSITEARCH)
VENDORARCHEXP := $(INSTALLVENDORARCH)
PERL_ARCHLIB := $(INSTALLPRIVLIB)

MAKE
    return $custom . File::ShareDir::Install::postamble($self);
}
