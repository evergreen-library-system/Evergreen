#!/usr/bin/perl
package OpenILS::Application::Search::Z3950;
use strict; use warnings;
use base qw/OpenSRF::Application/;


use Net::Z3950;
use MARC::Record;
use MARC::File::XML;
use OpenSRF::Utils::SettingsClient;

use OpenILS::Utils::FlatXML;
use OpenILS::Application::Cat::Utils;
use OpenILS::Application::AppUtils;

use OpenSRF::EX qw(:try);

my $utils = "OpenILS::Application::Cat::Utils";
my $apputils = "OpenILS::Application::AppUtils";

use OpenILS::Utils::ModsParser;
use Data::Dumper;

my $output = "USMARC"; # only support output for now
my $host;
my $port;
my $database;
my $attr;
my $username;
my $password;

my $settings_client;

sub initialize {
	$settings_client = OpenSRF::Utils::SettingsClient->new();
	$host			= $settings_client->config_value("z3950", "oclc", "host");
	$port			= $settings_client->config_value("z3950", "oclc", "port");
	$database	= $settings_client->config_value("z3950", "oclc", "db");
	$attr			= $settings_client->config_value("z3950", "oclc", "attr");
	$username	= $settings_client->config_value("z3950", "oclc", "username");
	$password	= $settings_client->config_value("z3950", "oclc", "password");
}


__PACKAGE__->register_method(
	method	=> "z39_search_by_string",
	api_name	=> "open-ils.search.z3950.raw_string",
);

sub z39_search_by_string {

	my( $self, $client, $server, 
			$port, $db, $search, $user, $pw ) = @_;

	throw OpenSRF::EX::InvalidArg unless( 
			$server and $port and $db and $search);


	warn "Z39.50 search for $search\n";

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
	if(!$rs) {
		throw OpenSRF::EX::ERROR ("z39 search failed"); 
	}

	my $records = [];
	my $hash = {};

	$hash->{count} =  $rs->size();
	warn "Z3950 Search recovered " . $hash->{count} . " records\n";

	# until there is a more graceful way to handle this
	if($hash->{count} > 20) { return $hash; }


	for( my $x = 0; $x != $hash->{count}; $x++ ) {
		warn "Churning on z39 record count $x\n";

		my $rec = $rs->record($x+1);
		my $marc = MARC::Record->new_from_usmarc($rec->rawdata());

		my $marcxml = $marc->as_xml();
		my $flat = OpenILS::Utils::FlatXML->new( xml => $marcxml ); 
		my $doc = $flat->xml_to_doc();


		if( $doc->documentElement->nodeName =~ /collection/io ) {
			$doc->setDocumentElement( $doc->documentElement->firstChild );
			$doc->documentElement->setNamespace(
					"http://www.loc.gov/MARC21/slim", undef, 1);
		}

		warn "Z3950 XML doc:\n" . $doc->toString . "\n";

		warn "Turning doc into a nodeset...\n";

		my $tree;
		my $err;

		try {
			my $nodes = OpenILS::Utils::FlatXML->new->xmldoc_to_nodeset($doc);
			#use Data::Dumper;
			#warn Dumper $nodes;
			warn "turning nodeset into tree\n";
			$tree = $utils->nodeset2tree( $nodes->nodeset );
		} catch Error with {
			$err = shift;
		};

		if($err) {
			warn "Error turning doc into nodeset/node tree: $err\n";
		} else {
			push @$records, $tree;
		}

	}

	use Data::Dumper;
	warn "Returning marc tree " . Dumper($records) . "\n";

	$hash->{records} = $records;
	return $hash;

}


__PACKAGE__->register_method(
	method	=> "import_search",
	api_name	=> "open-ils.search.z3950.import",
);

sub import_search {
	my($self, $client, $user_session, $string) = @_;

	my $user_obj = 
		$apputils->check_user_session( $user_session ); #throws EX on error

	return $self->z39_search_by_string(
		$client, $host, $port, $database, 
			"\@attr 1=$attr \"$string\"", $username, $password );
}




1;
