#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;

use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Config;
use OpenSRF::Utils::SettingsParser;

# TODO: GetOpts to set these
my $config_file = '/openils/conf/opensrf_core.xml';
my $verbose = 0;

sub usage {
    return <<USAGE

    usage: $0 xpath/traversing/string

Reads $config_file and dumps the structure found at the element
located by the xpath argument.  Without argument, dumps whole <config>.

    example: $0 apps/open-ils.search/app_settings
USAGE
}

sub die_usage {
    @_ and print "ERROR: @_\n";
    print usage();
    exit 1;
}

my $load = OpenSRF::Utils::Config->load(
    config_file => $config_file
);
my $booty = $load->bootstrap();

my $conf   = OpenSRF::Utils::Config->current;
my $cfile  = $conf->bootstrap->settings_config;
my $parser = OpenSRF::Utils::SettingsParser->new();
$parser->initialize( $cfile );
$OpenSRF::Utils::SettingsClient::host_config = $parser->get_server_config($conf->env->hostname);

my $settings = OpenSRF::Utils::SettingsClient->new();
# scalar(@ARGV) or die_usage("Argument is required");
my @terms = scalar(@ARGV) ? split('/', shift) : ();
$verbose and print "Looking under: ", join(', ', map {"<$_>"} @terms), "\n";

my $target = $settings->config_value(@terms);
print Dumper($target);

# my $lines = $target->{callfile_lines};

