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
use OpenILS::Event;

use OpenSRF::Utils::Logger qw/$logger/;

use OpenSRF::EX qw(:try);

my $utils = "OpenILS::Application::Cat::Utils";
my $apputils = "OpenILS::Application::AppUtils";
my $U = $apputils;

use OpenILS::Utils::ModsParser;
use Data::Dumper;

my $output = "USMARC"; # only support output for now
my $host;
my $port;
my $database;
my $tcnattr;
my $isbnattr;
my $username;
my $password;
my $defserv;

my $settings_client;

sub initialize {
	$settings_client = OpenSRF::Utils::SettingsClient->new();

	$defserv		= $settings_client->config_value("z3950", "default" );

	( $host, $port, $database, $username, $password ) = _load_settings($defserv);
	$tcnattr		= $settings_client->config_value("z3950", $defserv, "tcnattr");
	$isbnattr	= $settings_client->config_value("z3950", $defserv, "isbnattr");

	$logger->info("z3950: Loading Defaults: service=$defserv, host=$host, port=$port, ".
		"db=$database, tcnattr=$tcnattr, isbnattr=$isbnattr, username=$username, password=$password" );
}

sub _load_settings {
	my $service = shift;

	if( $service eq $defserv and $host ) {
		return ( $host, $port, $database, $username, $password );
	}

	return (
		$settings_client->config_value("z3950", $service, "host"),
		$settings_client->config_value("z3950", $service, "port"),
		$settings_client->config_value("z3950", $service, "db"),
		$settings_client->config_value("z3950", $service, "username"),
		$settings_client->config_value("z3950", $service, "password"),
	);
}


__PACKAGE__->register_method(
	method	=> "marcxml_to_brn",
	api_name	=> "open-ils.search.z3950.marcxml_to_brn",
);

sub marcxml_to_brn {
	my( $self, $client, $marcxml ) = @_;

	my $tree;
	my $err;

	# Strip the namespace info from the <collection> node and shove it into
	# the <record> node, if the collection node exists
	my ($ns) = ( $marcxml =~ /<collection(.*)?>/og );
	$logger->info("marcxml_to_brn extracted namespace info: $ns") if $ns;
	$marcxml =~ s/<collection(.*)?>//og;
	$marcxml =~ s/<\/collection>//og;
	$marcxml =~ s/<record>/<record $ns>/og if $ns;

	my $flat = OpenILS::Utils::FlatXML->new( xml => $marcxml ); 
	my $doc = $flat->xml_to_doc();

	$logger->debug("z3950: Turning doc into a nodeset...");

	try {
		my $nodes = OpenILS::Utils::FlatXML->new->xmldoc_to_nodeset($doc);
		$logger->debug("z3950: turning nodeset into tree");
		$tree = $utils->nodeset2tree( $nodes->nodeset );
	} catch Error with {
		$err = shift;
	};

	if($err) {
		$logger->error("z3950: Error turning doc into nodeset/node tree: $err");
		return undef;
	} else {
		return $tree;
	}
}

__PACKAGE__->register_method(
	method	=> "z39_search_by_string",
	api_name	=> "open-ils.search.z3950.raw_string",
);

sub z39_search_by_string {

	my( $self, $connection, $authtoken, $params ) = @_;
	my( $hst, $prt, $db, $usr, $pw );


	my( $requestor, $evt ) = $U->checksesperm($authtoken, 'REMOTE_Z3950_QUERY');
	return $evt if $evt;
	my $service = $$params{service};
	my $search	= $$params{search};

	if( $service ) {
		($hst, $prt, $db, $usr, $pw ) = _load_settings($$params{service});
	} else {
		$hst	= $$params{host};
		$prt	= $$params{prt};
		$db	= $$params{db};
		$usr	= $$params{username};
		$pw	= $$params{password};
		$service = "(custom)";
	}


	$logger->info("z3950:  Search App connecting:  service=$service, ".
		"host=$hst, port=$prt, db=$db, username=$usr, password=$pw, search=$search" );

	return OpenILS::Event->new('BAD_PARAMS') unless ($hst and $prt and $db);

	$usr ||= ""; $pw	||= "";

	my $conn = new Net::Z3950::Connection(
		$hst, $prt, 
		databaseName				=> $db, 
		user							=> $usr,
		password						=> $pw,
		preferredRecordSyntax	=> $output, 
	);


	my $rs = $conn->search( $search );
	return OpenILS::Event->new('Z3950_SEARCH_FAILED') unless $rs;

	# We want nice full records
	$rs->option(elementSetName => "f");

	my $records = [];
	my $hash = {};

	$hash->{count} =  $rs->size();
	$logger->info("z3950: Search recovered " . $hash->{count} . " records");

	# until there is a more graceful way to handle this
	if($hash->{count} > 20) { return $hash; }

	for( my $x = 0; $x != $hash->{count}; $x++ ) {
		$logger->debug("z3950: Churning on z39 record count $x");

		my $rec = $rs->record($x+1);
		my $marc = MARC::Record->new_from_usmarc($rec->rawdata());

		my $marcxml = $marc->as_xml();
		my $mods;
			
		my $u = OpenILS::Utils::ModsParser->new();
		$u->start_mods_batch( $marcxml );
		$mods = $u->finish_mods_batch();

		push @$records, { 'mvr' => $mods, 'marcxml' => $marcxml };
	}

	$logger->debug("z3950: got here near the end with " . scalar(@$records) . " records." );

	$hash->{records} = $records;
	return $hash;

}


__PACKAGE__->register_method(
	method	=> "tcn_search",
	api_name	=> "open-ils.search.z3950.tcn",
);

sub tcn_search {
	my($self, $connection, $authtoken, $tcn, $service) = @_;

	my( $requestor, $evt ) = $U->checksesperm($authtoken, 'REMOTE_Z3950_QUERY');
	return $evt if $evt;
	$service ||= $defserv;

	my $attr = $settings_client->config_value("z3950", $service, "tcnattr");

	$logger->info("z3950: Searching for TCN $tcn");

	return $self->z39_search_by_string(
		$connection, $authtoken, {
			search => "\@attr 1=$attr \"$tcn\"", 
			service => $service });
}


__PACKAGE__->register_method(
	method	=> "isbn_search",
	api_name	=> "open-ils.search.z3950.isbn",
);

sub isbn_search {
	my( $self, $connection, $authtoken, $isbn, $service ) = @_;

	my( $requestor, $evt ) = $U->checksesperm($authtoken, 'REMOTE_Z3950_QUERY');
	return $evt if $evt;
	$service ||= $defserv;

	my $attr = $settings_client->config_value("z3950", $service, "isbnattr");

	$logger->info("z3950: Performing ISBN search : $isbn");

	return $self->z39_search_by_string(
		$connection, $authtoken, {
			search => "\@attr 1=$attr \"$isbn\"", 
			service => $service });
}


__PACKAGE__->register_method(
	method	=> "query_interfaces",
	api_name	=> "open-ils.search.z3950.services.retrieve",
);

sub query_interfaces {
	my( $self, $client, $authtoken ) = @_;
	my( $requestor, $evt ) = $U->checksesperm($authtoken, 'REMOTE_Z3950_QUERY');

	my $services = $settings_client->config_value("z3950");
	$services = { $services } unless ref($services);

	return [ grep { $_ ne 'default' } keys %$services ];
}





1;
