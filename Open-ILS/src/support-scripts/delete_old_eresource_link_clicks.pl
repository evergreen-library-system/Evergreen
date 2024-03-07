#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long;
use OpenSRF::System;
use OpenILS::Utils::CStoreEditor;
use Carp;

my $osrf_config = '/openils/conf/opensrf_core.xml';
my $days = 365;
my $help;

my $ops = GetOptions(
    'osrf-config=s' => \$osrf_config,
    'days=i'        => \$days,
    'help'          => \$help
);

sub help {
    print <<'END_HELP';


    Usage:
        --osrf-config [/openils/conf/opensrf_core.xml]

        --days <number-of-days>
            How many days of clicks to keep.  For example, --days 7
            will keep only the most recent week of clicks.  The default
            is 365 days.

        --help
            Show this message.
END_HELP
    exit 0;
}

help() if $help || !$ops;

OpenSRF::System->bootstrap_client(config_file => $osrf_config);
OpenILS::Utils::CStoreEditor::init();
my $e = OpenILS::Utils::CStoreEditor->new;
$e->json_query(
    {'from' => ['action.delete_old_eresource_link_clicks', $days]}
) or croak('Deletion failed, ' . $e->event);

1;
