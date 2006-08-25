#!/usr/bin/perl
# ---------------------------------------------------------------------
# Generic databse object dumper.
# ./object_dumper.pl <bootstrap_config> <type>, <type>, ...
# ./object_dumper.pl /openils/conf/bootstrap.conf permission.grp_tree
# ---------------------------------------------------------------------

use strict; 
use warnings;
use JSON;
use OpenSRF::System;

my $config = shift || die "bootstrap config required\n";

OpenSRF::System->bootstrap_client( config_file => $config );

my $r = OpenSRF::AppSession
		->create( 'open-ils.storage' )
		->request( 'open-ils.storage.action.hold_request.copy_targeter' => '24h' );

while (!$r->complete) { $r->recv };

