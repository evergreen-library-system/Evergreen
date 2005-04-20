#!/usr/bin/perl
package OpenILS::Application::Search::Z3950;
use strict; use warnings;
use base qw/OpenSRF::Application/;


use Net::Z3950;
use MARC::Record;
use MARC::File::XML;

use OpenILS::Utils::ModsParser;

my $output = "USMARC"; # only support output for now



__PACKAGE__->register_method(
	method	=> "z39_search_by_string",
	api_name	=> "open-ils.search.z3950.raw_string",
	argc		=> 1, 
	note		=> "z3950 search by raw query string",
);


sub z39_search_by_string {

	my( $self, $client, $server, 
			$port, $db, $search, $user, $pw ) = @_;

	throw OpenSRF::EX::InvalidArg unless( 
			$server and $port and $db and $search);

	$user ||= "";
	$pw	||= "";

	my $conn = new Net::Z3950::Connection(
		$server, $port, 
		databaseName				=> $db, 
		user							=> $user,
		password						=> $pw,
		preferredRecordSyntax	=> $output, 
	);


	my $rs = $conn->search( $search );

	my $records = [];
	my $hash = {};

	$hash->{count} =  $rs->size();
	warn "Z3950 Search recovered " . $hash->{count} . " records\n";

	for( my $x = 0; $x != $hash->{count}; $x++ ) {
		my $rec = $rs->record($x+1);
		my $marc = MARC::Record->new_from_usmarc($rec->rawdata());

		my $u = OpenILS::Utils::ModsParser->new();
		$u->start_mods_batch($marc->as_xml());
		my $mods = $u->finish_mods_batch();

		push @$records, $mods;
	}

	$hash->{records} = $records;
	return $hash;

}


1;
