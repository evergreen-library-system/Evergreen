#!/usr/bin/perl -w
use strict;
use OpenSRF::EX qw/:try/;
use OpenSRF::System;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::FlatXML;
use Time::HiRes;
use Getopt::Long;

my ($config, $userid, $sourceid, $wormize) = ('/pines/conf/bootstrap.conf', 1, 2);

GetOptions (	
	"file=s"	=> \$config,
	"wormize"	=> \$wormize,
	"sourceid"	=> \$sourceid,
	"userid=i"	=> \$userid,
);

OpenSRF::System->bootstrap_client( config_file => $config );
my $st_server = OpenSRF::AppSession->new( 'storage' );
my $worm_server = OpenSRF::AppSession->new( 'worm' ) if ($wormize);

try {
	$st_server->connect;
	$worm_server->connect if ($wormize);
	throw OpenSRF::EX::PANIC ("I can't connect to the storage server!")
		unless ($st_server->connected);
} catch Error with {
	die shift;
};


while ( my $ns = OpenILS::Utils::FlatXML->new( xml => <STDIN> ) ) {

	my $doc = $ns->xml_to_doc;
	my $tcn = $doc->documentElement->findvalue( '/*/*[@tag="035"]' );
	
	my $req = $st_server->request(
		'open-ils.storage.biblio.record_entry.create',
			creator		=> $userid,
			editor		=> $userid,
			source		=> $sourceid,
			tcn_value	=> $tcn,
	);

	$req->wait_complete;

	my $resp = $req->recv;
	unless( $resp->content ) {
		throw OpenSRF::EX::ERROR ("Failed to create record for TCN [$tcn]!! -- $resp");
	}

	my $new_id = $resp->content;

	$req->finish;

	if ($new_id) {
		my $nodeset = $ns->xml_to_nodeset;
		
		$_->{owner_doc} = $new_id for (@$nodeset);
		
		$req = $st_server->request(
			'open-ils.storage.record_node.batch.create',
			@$nodeset,
		);

		$req->wait_complete;

		$resp = $req->recv;
		unless( $resp->content ) {
			throw OpenSRF::EX::ERROR
				("Failed to create record_nodes for TCN [$tcn]!! -- $resp");
		}


		if ($wormize) {
			my $worm_req = $worm_server->request(
				'open-ils.worm.record_data.digest',
				$new_id,
			);
		}

		$req->finish;
	} else {
		throw OpenSRF::EX::ERROR ("Failed to create record for TCN [$tcn]!! -- $resp");
	}
}





