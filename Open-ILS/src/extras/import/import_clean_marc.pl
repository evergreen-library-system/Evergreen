#!/usr/bin/perl -w
use strict;
use lib '../../perlmods/';
use lib '../../../../OpenSRF/src/perlmods/';
use OpenSRF::EX qw/:try/;
use OpenSRF::System;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::FlatXML;
use OpenILS::Utils::Fieldmapper;
use Time::HiRes;
use Getopt::Long;
use Data::Dumper;

my ($config, $userid, $sourceid, $wormize) = ('/pines/conf/bootstrap.conf', 1, 2);

GetOptions (	
	"file=s"	=> \$config,
	"wormize"	=> \$wormize,
	"sourceid"	=> \$sourceid,
	"userid=i"	=> \$userid,
);

OpenSRF::System->bootstrap_client( config_file => $config );
my $st_server = OpenSRF::AppSession->create( 'open-ils.storage' );
my $worm_server = OpenSRF::AppSession->create( 'open-ils.worm' ) if ($wormize);

try {

	throw OpenSRF::EX::PANIC ("I can't connect to the storage server!")
		if (!$st_server->connect);

#	throw OpenSRF::EX::PANIC ("I can't connect to the worm server!")
#		if ($wormize && !$worm_server->connect);

} catch Error with {
	die shift;
};


while ( my $xml = <> ) {
	chomp $xml;

	my $new_id;

	my $ns = OpenILS::Utils::FlatXML->new( xml => $xml );

	next unless ($ns->xml);

	my $doc = $ns->xml_to_doc;
	my $tcn = $doc->documentElement->findvalue( '/*/*[@tag="035"]' );

	$tcn =~ s/^.*?(\w+)$/$1/go;

	warn "Adding record for TCN $tcn\n";

	#$ns->xml_to_nodeset;
	#next;

	warn "  ==> Starting transaction...\n";

	my $xact = $st_server->request( 'open-ils.storage.transaction.begin' );
	$xact->wait_complete;

	my $r = $xact->recv;
	die $r unless (UNIVERSAL::can($r, 'content'));
	die "Couldn't start transaction!" unless ($r);
	
	warn "  ==> Transaction ".$xact->session->session_id." started\n";

	try {
		my $fe = new Fieldmapper::biblio::record_entry;
		$fe->editor( $userid );
		$fe->creator( $userid );
		$fe->source( $sourceid );
		$fe->tcn_value( $tcn );

		my $req = $st_server->request( 'open-ils.storage.biblio.record_entry.create' => $fe );

		$req->wait_complete;

		my $resp = $req->recv;
		unless( $resp && $resp->can('content') ) {
			throw OpenSRF::EX::ERROR ("Failed to create record for TCN [$tcn].  Got an exception!! -- ".$resp->toString);
		}

		$new_id = $resp->content;
		warn "    (new record_entry id is $new_id)\n";

		$req->finish;

		if ($new_id) {

			#$ns->xml_to_nodeset;
			#my $nodeset = $ns->nodeset;
			#$_->owner_doc( $new_id ) for (@$nodeset);

			my $rec = new Fieldmapper::biblio::record_marc;
			$rec->id( $new_id );
			$rec->marc( $xml );

			$req = $st_server->request( 'open-ils.storage.biblio.record_marc.create', $rec );

			$req->wait_complete;

			$resp = $req->recv;
			unless( $resp && $resp->can('content') ) {
				throw OpenSRF::EX::ERROR ("Failed to create record_nodes for TCN [$tcn].  Got an exception!! -- $resp");
			}


			$req->finish;
		} else {
			throw OpenSRF::EX::ERROR ("Failed to create record for TCN [$tcn].  Got no new ID !! -- ".$resp->toString);
		}
	} catch Error with {
		warn "  !!> Rolling back transaction\n".shift();
		$xact = $st_server->request( 'open-ils.storage.transaction.rollback' );
		$xact->wait_complete;

		die $r unless (UNIVERSAL::can($r, 'content'));
		die "Couldn't rollback transaction!" unless ($r->content);

		$xact = undef;
	};

	if ($xact) {
		warn "  ==>Commiting addition of $tcn\n";
		$xact = $st_server->request( 'open-ils.storage.transaction.commit' );
		$xact->wait_complete;

		my $r = $xact->recv;
		die $r unless (UNIVERSAL::can($r, 'content'));
		die "Couldn't commit transaction!" unless ($r->content);

#		if ($wormize) {
#			$worm_server->full_request( 'open-ils.worm.wormize', $new_id,);
#			#$worm_server->disconnect;
#		}

	}
}





