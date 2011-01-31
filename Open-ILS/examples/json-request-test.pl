#!/usr/bin/perl -w
use strict;
use lib '../src/perlmods/lib/';
use lib '../src/perlmods/lib/OpenILS/Utils/';

use OpenSRF::Utils::JSON;
use OpenSRF::System;
use OpenILS::Utils::ScriptRunner;
use OpenSRF::Utils::Logger;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::EX qw(:try);
use Fieldmapper (IDL => 'fm_IDL.xml');

unless (@ARGV > 1) {
	print <<USAGE;
Usage: $0 /openils-root-dir script.js
USAGE
}

my $root = shift(@ARGV);

OpenSRF::System->bootstrap_client( config_file => $root.'/conf/opensrf_core.xml');

try {
        OpenILS::Utils::ScriptRunner->add_path($root.'/var/web/opac/common/js/');
        OpenILS::Utils::ScriptRunner->add_path('../src/javascript/backend/libs/');
        OpenILS::Utils::ScriptRunner->add_path('./');

	print OpenSRF::Utils::JSON->perl2JSON( OpenILS::Utils::ScriptRunner->new( file => shift(@ARGV) )->run );
	#print OpenSRF::Utils::JSON->perl2JSON( OpenILS::Utils::ScriptRunner->new->run( shift(@ARGV) ) );

} otherwise {
        warn 'crap:'.shift();
};

