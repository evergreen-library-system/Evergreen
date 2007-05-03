#!/usr/bin/perl
use strict; use warnings;

use OpenSRF::AppSession;
use OpenSRF::System;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Cache;

my $config = shift;
my $command = shift;
die <<USAGE

    Enables/disables added content lookups in apache.  This does not (currently)
    include jacket image lookups, which are Apache rewrites

    usage: perl $0 <bootstrap_config> [enable|disable]

USAGE
    unless $command;

OpenSRF::System->bootstrap_client(config_file => $config);

my $cache = OpenSRF::Utils::Cache->new;
$cache->put_cache('ac.no_lookup', 1) if $command eq 'disable';
$cache->delete_cache('ac.no_lookup') if $command eq 'enable';


