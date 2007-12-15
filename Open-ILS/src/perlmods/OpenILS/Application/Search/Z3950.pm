package OpenILS::Application::Search::Z3950;
use strict; use warnings;
use base qw/OpenSRF::Application/;

use OpenILS::Utils::ZClient;
use MARC::Record;
use MARC::File::XML;
use Unicode::Normalize;
use XML::LibXML;
use Data::Dumper;

use OpenILS::Event;
use OpenSRF::EX qw(:try);
use OpenILS::Utils::ModsParser;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Application::AppUtils;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::Editor q/:funcs/;

my $output	= "USMARC"; 

my $sclient;
my %services;
my $default_service;


__PACKAGE__->register_method(
	method		=> 'do_class_search',
	api_name		=> 'open-ils.search.z3950.search_class',
	signature	=> q/
		Performs a class based Z search.  The classes available
		are defined by the 'attr' fields in the config for the
		requested service.
		@param auth The login session key
		@param shash The search hash : { attr : value, attr2: value, ...}
		@param service The service to connect to
		@param username The username to use when connecting to the service
		@param password The password to use when connecting to the service
	/
);

__PACKAGE__->register_method(
	method		=> 'do_service_search',
	api_name		=> 'open-ils.search.z3950.search_service',
	signature	=> q/
		@param auth The login session key
		@param query The Z3950 search string to use
		@param service The service to connect to
		@param username The username to use when connecting to the service
		@param password The password to use when connecting to the service
	/
);


__PACKAGE__->register_method(
	method		=> 'do_service_search',
	api_name		=> 'open-ils.search.z3950.search_raw',
	signature	=> q/
		@param auth The login session key
		@param args An object of search params which must include:
			host, port, db and query.  
			optional fields include username and password
	/
);


__PACKAGE__->register_method(
	method	=> "query_services",
	api_name	=> "open-ils.search.z3950.retrieve_services",
	signature	=> q/
		Returns a list of service names that we have config
		data for
	/
);



# -------------------------------------------------------------------
# What services do we have config info for?
# -------------------------------------------------------------------
sub query_services {
	my( $self, $client, $auth ) = @_;
	my $e = new_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('REMOTE_Z3950_QUERY');
	return $sclient->config_value('z3950', 'services');
}



# -------------------------------------------------------------------
# Load the pre-defined Z server configs
# -------------------------------------------------------------------
sub initialize {
	$sclient = OpenSRF::Utils::SettingsClient->new();
	$default_service = $sclient->config_value("z3950", "default" );
	my $servs = $sclient->config_value("z3950", "services" );
	$services{$_} = $$servs{$_} for keys %$servs;
}


# -------------------------------------------------------------------
# High-level class based search. 
# -------------------------------------------------------------------
sub do_class_search {

	my $self			= shift;
	my $conn			= shift;
	my $auth			= shift;
	my $args			= shift;

	if (ref($$args{service}) =~ /ARRAY/o) {
		$$args{service} = [$$args{service}];
		$$args{username} = [$$args{username}];
		$$args{password} = [$$args{password}];
	}

	$$args{async} = 1;

	$$args{query} = 
		compile_query('and', $$args{service}, $$args{search});

	my @results;
	for (my $i = 0; $i < @{$$args{service}}; $i++) {
		my %tmp_args = %$args;
		$tmp_args{service} = $$args{service}[$i];
		$tmp_args{username} = $$args{username}[$i];
		$tmp_args{password} = $$args{password}[$i];
		$results[$i] = $self->do_service_search( $conn, $auth, \%tmp_args );
	}

	my @records;
	while ((my $index = OpenILS::Utils::ZClient::event( \@results )) != 0) {
		my $ev = $results[$index - 1]->last_event();
		if ($ev == OpenILS::Utils::ZClient::Event::END) {
			my $munged = process_results( $results[$index - 1], ($$args{limit} || 10), ($$args{offset} || 0) );
			$$munged{service} = $$args{service}[$index];
			$conn->respond($munged);
		}
	}
}


# -------------------------------------------------------------------
# This handles the host settings, but expects a fully formed z query
# -------------------------------------------------------------------
sub do_service_search {

	my $self			= shift;
	my $conn			= shift;
	my $auth			= shift;
	my $args			= shift;
	
	my $info = $services{$$args{service}};

	$$args{host}	= $$info{host},
	$$args{port}	= $$info{port},
	$$args{db}		= $$info{db},

	return $self->do_search( $conn, $auth, $args );
}



# -------------------------------------------------------------------
# This is the low level search method.  All config and query
# data must be provided to this method
# -------------------------------------------------------------------
sub do_search {

	my $self	= shift;
	my $conn	= shift;
	my $auth = shift;
	my $args = shift;

	my $host		= $$args{host} or return undef;
	my $port		= $$args{port} or return undef;
	my $db		= $$args{db}	or return undef;
	my $query	= $$args{query} or return undef;
	my $async	= $$args{async} || 0;

	my $limit	= $$args{limit} || 10;
	my $offset	= $$args{offset} || 0;

	my $username = $$args{username} || "";
	my $password = $$args{password} || "";

	my $editor = new_editor(authtoken => $auth);
	return $editor->event unless $editor->checkauth;
	return $editor->event unless $editor->allowed('REMOTE_Z3950_QUERY');

	my $connection = OpenILS::Utils::ZClient->new(
		$host, $port,
		databaseName				=> $db, 
		user							=> $username,
		async							=> $async,
		password						=> $password,
		preferredRecordSyntax	=> $output, 
	);

	if( ! $connection ) {
		$logger->error("z3950: Unable to connect to Z server: ".
			"$host:$port:$db:$username:$password");
		return OpenILS::Event->new('Z3950_LOGIN_FAILED') unless $connection;
	}

	my $start = time;
	my $results;
	my $err;

	$logger->info("z3950: query => $query");

	try {
		$results = $connection->search_pqf( $query );
	} catch Error with { $err = shift; };

	return OpenILS::Event->new(
		'Z3950_BAD_QUERY', payload => $query, debug => "$err") if $err;

	return OpenILS::Event->new('Z3950_SEARCH_FAILED', 
		debug => $connection->errcode." => ".$connection->errmsg." : query = $query") unless $results;

	$logger->info("z3950: search [$query] took ".(time - $start)." seconds");

	return $results if ($async);

	my $munged = process_results($results, $limit, $offset);
	$munged->{query} = $query;

	return $munged;
}


# -------------------------------------------------------------------
# Takes a result batch and returns the hitcount and a list of xml
# and mvr objects
# -------------------------------------------------------------------
sub process_results {
	my $results	= shift;
	my $limit	= shift;
	my $offset	= shift;

	$results->option(elementSetName => "FI"); # full records with no holdings

	my @records;
	my $res = {};
	my $count = $$res{count} = $results->size;

	$logger->info("z3950: search returned $count hits");

	my $tend = $limit + $offset;

	my $end = ($tend <= $count) ? $tend : $count;

	for($offset..$end - 1) {

		my $err;
		my $mods;
		my $marc;
		my $marcs;
		my $marcxml;

		$logger->info("z3950: fetching record $_");

		try {

			my $rec	= $results->record($_);
			$marc		= MARC::Record->new_from_usmarc($rec->raw());
			$marcs	= entityize($marc->as_xml_record);
			my $doc	= XML::LibXML->new->parse_string($marcs);
			$marcxml = entityize( $doc->documentElement->toString );
	
			my $u = OpenILS::Utils::ModsParser->new();
			$u->start_mods_batch( $marcxml );
			$mods = $u->finish_mods_batch();
	

		} catch Error with { $err = shift; };

		push @records, { 'mvr' => $mods, 'marcxml' => $marcxml } unless $err;
		$logger->error("z3950: bad XML : $err") if $err;

		if( $err ) {
			warn "\n\n$marcs\n\n";
		}
	}
	
	$res->{records} = \@records;
	return $res;
}



# -------------------------------------------------------------------
# Compiles the class based search query
# -------------------------------------------------------------------
sub compile_query {

	my $seperator	= shift;
	my $service		= shift;
	my $hash			= shift;

	my $count = scalar(keys %$hash);

	my $str = "";
	$str .= "\@$seperator " for (1..$count-1);
	
    # -------------------------------------------------------------------
    # "code" is the bib-1 "use attribute", "format" is the bib-1 
    # "structure attribute"
    # -------------------------------------------------------------------
	for( keys %$hash ) {
#		$str .= '@attr ' .
#			$services{$service}->{attrs}->{$_}->{format} . '=' .
#			$services{$service}->{attrs}->{$_}->{code} . " \"" . $$hash{$_} . "\" ";		
        $str .= 
            '@attr 1=' . $services{$service}->{attrs}->{$_}->{code} . # add the use attribute
            ' @attr 4=' . $services{$service}->{attrs}->{$_}->{format} . # add the structure attribute
            " \"" . $$hash{$_} . "\" "; # add the search term
	}
	return $str;
}



# -------------------------------------------------------------------
# Handles the unicode
# -------------------------------------------------------------------
sub entityize {
	my $stuff = shift;
	my $form = shift || "";
	
	if ($form eq 'D') {
		$stuff = NFD($stuff);
	} else {
		$stuff = NFC($stuff);
	}
	
	$stuff =~ s/([\x{0080}-\x{fffd}])/sprintf('&#x%X;',ord($1))/sgoe;

	# strip some other unfriendly chars that may leak in
   $stuff =~ s/([\x{0000}-\x{0008}])//sgoe; 

	return $stuff;
}


1;
