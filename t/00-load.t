use strict;
use warnings;
use Test::More;

my @modules = qw(
    Balance::Core
    Balance::Config
    Balance::ConfigStore
    Balance::Manifest
    Balance::DiskProbe
    Balance::FuzzyName
    Balance::PathMap
    Balance::JobRunner
    Balance::JobStore
    Balance::Sonarr
    Balance::Plex
    Balance::Reconcile
    Balance::ReconcileApp
    Balance::AuditSonarr
    Balance::WebClient
    Balance::Web::App
    Balance::Web::Controller::Dashboard
    Balance::Web::Controller::Jobs
    Balance::Web::Controller::Config
    Balance::Web::Controller::Sonarr
    Balance::Web::Controller::Plex
);

plan tests => scalar @modules;

use_ok($_) for @modules;
