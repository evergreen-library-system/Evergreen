#!/usr/bin/perl -w
use strict;
use lib '../../perlmods/';
use lib '../../../../OpenSRF/src/perlmods/';
use OpenSRF::EX qw/:try/;
use OpenSRF::System;
use OpenILS::Utils::Fieldmapper;
use XML::LibXML;
use Time::HiRes;
use Getopt::Long;
use Data::Dumper;

my ($config, $userid) = ('/pines/conf/bootstrap.conf', 1);

GetOptions (	
	"file=s"	=> \$config,
	"userid=i"	=> \$userid,
);

OpenSRF::System->bootstrap_client( config_file => $config );
my $st_server = OpenSRF::AppSession->create( 'open-ils.storage' );

try {

	throw OpenSRF::EX::PANIC ("I can't connect to the storage server!")
		if (!$st_server->connect);

} catch Error with {
	die shift;
};


while ( my $xml = <> ) {
	chomp $xml;

	my $new_id;

	next unless ($xml);

	my $doc = XML::LibXML->new()->parse_string($xml);
	my $tcn = $doc->documentElement->findvalue( '/*/*[@tag="035"]' );

	$tcn =~ s/^.*?(\w+)$/$1/go;

	warn "Adding holdings for TCN $tcn\n";

	warn "  ==> Starting transaction...\n";

	my $xact = $st_server->request( 'open-ils.storage.transaction.begin' );
	$xact->wait_complete;

	my $r = $xact->recv;
	die $r unless (UNIVERSAL::can($r, 'content'));
	die "Couldn't start transaction!" unless ($r);
	
	warn "  ==> Transaction ".$xact->session->session_id." started\n";

	for my $node ($doc->documentElement->findnodes('/*/*[@tag="999"]')) {
		try {
			my $req = $st_server->request( 'open-ils.storage.biblio.record_entry.search.tcn_value' => $tcn );

			$req->wait_complete;

			my $resp = $req->recv;
			$req->finish;

			if( $resp && !$resp->can('content') ) {
				throw OpenSRF::EX::ERROR ("Failed to retrieve record for TCN [$tcn].  Got an exception!! -- ".$resp->toString);
			} elsif (!$resp) {
				next;
			}

			my $rec = $resp->content;
			if (@$rec) {
				warn "    (record_entry id is ".$rec->[0]->id.")\n";

				my $label = $node->findvalue( '*[@code="a"]' );
				my $owning_lib = $node->findvalue( '*[@code="m"]' );

				my $cn_req = $st_server->request( 'open-ils.storage.asset.call_number.search' =>
									{ owning_lib	=> $owning_lib,
									  label		=> $label}
				);
				$cn_req->wait_complete;

				my $cn_resp = $cn_req->recv;
				$cn_req->finish;

				my $cn;
				if( $cn_resp && !$cn_resp->can('content') ) {
					throw OpenSRF::EX::ERROR ("Failed to retrieve call_number for $owning_lib:$label.  Got an exception!! -- ".$cn_resp->toString);
				} elsif (!$cn_resp) {
					$cn = new Fieldmapper::asset::call_number;
					$cn->editor( $userid );
					$cn->creator( $userid );
					$cn->record( $rec->[0]->id );
					$cn->label( $label );
					$cn->owning_lib( $owning_lib );
					$cn_req = $st_server->request( 'open-ils.storage.asset.call_number.create' => $cn );
					$cn_req->wait_complete;

					$cn_resp = $cn_req->recv;
					unless( $cn_resp && $cn_resp->can('content') && $cn_resp->content ) {
						throw OpenSRF::EX::ERROR ("Failed to create call_number for $owning_lib:$label.  Got an exception!! -- ".$cn_resp->toString);
					}
					$cn->id($cn_resp->content);
				} else {
					$cn = $cn_resp->content;
				}
				
				my $cp = new Fieldmapper::asset::copy;
				$cp->editor( $userid );
				$cp->creator( $userid );
				$cp->call_number( $cn->id );

				my $barcode = $node->findvalue( '*[@code="i"]' );
				my $price = $node->findvalue( '*[@code="p"]' );
				my $genre = $node->findvalue( '*[@code="x"]' );
				my $audience = $node->findvalue( '*[@code="z"]' );
				my $home_lib = $node->findvalue( '*[@code="l"]' );
				my $status = $node->findvalue( '*[@code="k"]' );
				my $copy_number = $node->findvalue( '*[@code="c"]' );

				$cp->barcode( $barcode );
				$cp->price( $price );
				$cp->genre( $genre );
				$cp->audience( $audience );
				$cp->home_lib( $home_lib );
				$cp->status( $status );
				$cp->copy_number( $copy_number );

				$cp->loan_duration( 2 );
				$cp->fine_level( 2 );
				$cp->ref( 0 );
				$cp->circulate( 1 );
				$cp->deposit( '0.00' );
				$cp->opac_visible( 1 );
				$cp->shelving_loc( 'stacks');

				my $cp_req = $st_server->request( 'open-ils.storage.asset.copy.create' => $cp );
				$cp_req->wait_complete;

				my $cp_resp = $cp_req->recv;
				unless( $cp_resp && $cp_resp->can('content') && $cp_resp->content ) {
					throw OpenSRF::EX::ERROR ("Failed to create copy for $barcode.  Got an exception!! -- ".$cp_resp->toString);
				}

			} else {
				next;
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

		}
	}
}





