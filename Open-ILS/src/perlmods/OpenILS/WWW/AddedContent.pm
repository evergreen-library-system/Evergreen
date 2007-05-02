package OpenILS::WWW::AddedContent;
use strict; use warnings;

use lib qw(/usr/lib/perl5/Bundle/);

use CGI;
use Apache2 ();
use Apache2::Log;
use Apache2::Const -compile => qw(OK REDIRECT DECLINED NOT_FOUND :log);
use APR::Const    -compile => qw(:error SUCCESS);
use Apache2::RequestRec ();
use Apache2::RequestIO ();
use Apache2::RequestUtil;
use Data::Dumper;

use OpenSRF::EX qw(:try);
use OpenSRF::Utils::Cache;
use OpenSRF::System;
use OpenSRF::Utils::Logger qw/$logger/;
use XML::LibXML;


# set the bootstrap config when this module is loaded
my $bs_config;
my $handler;

sub import {
	my $self = shift;
	$bs_config = shift;
}


my $net_timeout;
my $cache;
sub child_init {

	OpenSRF::System->bootstrap_client( config_file => $bs_config );

	my $sclient = OpenSRF::Utils::SettingsClient->new();
	my $ac_data = $sclient->config_value("added_content");

    return unless $ac_data;

    $cache = OpenSRF::Utils::Cache->new;

	my $ac_handler = $ac_data->{module};
    $net_timeout = $ac_data->{timeout} || 3;
    
	return unless $ac_handler;

	$logger->debug("Attempting to load Added Content handler: $ac_handler");

	eval "use $ac_handler";

	if($@) {	
		$logger->error("Unable to load Added Content handler [$ac_handler]: $@"); 
		return; 
	}

	$handler = $ac_handler->new($ac_data);
	$logger->debug("added content loaded handler: $handler");
}


sub handler {

	my $r		= shift;
	my $cgi	= CGI->new;
	my $path = $r->path_info;

	child_init() unless $handler; # why isn't apache doing this for us?
	return Apache2::Const::NOT_FOUND unless $handler;

    # if this memcache key is set, added content lookups are disabled
	if( $cache->get_cache('ac.no_lookup') ) {
        $logger->info("added content lookup disabled");
	    return Apache2::Const::NOT_FOUND;
    }


	my( undef, $data, $format, $key ) = split(/\//, $r->path_info);

	my $err;
	my $success;
	my $method = "${data}_${format}";

	try {
		$success = $handler->$method($key);
	} catch Error with {
		my $err = shift;
		$logger->error("added content handler failed: $method($key) => $err");
	};

	return Apache2::Const::NOT_FOUND if $err or !$success;
	return Apache2::Const::OK;
}



# generic GET call
sub get_url {
	my( $self, $url ) = @_;
	$logger->info("added content getting [timeout=$net_timeout] URL = $url");
	my $agent = LWP::UserAgent->new(timeout => $net_timeout);
	my $res = $agent->get($url);
	die "added content request failed: " . $res->status_line ."\n" unless $res->is_success;
	return $res->content;
}






1;

