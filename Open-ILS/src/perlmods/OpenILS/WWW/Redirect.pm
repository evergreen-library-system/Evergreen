package OpenILS::WWW::Redirect;
use strict; use warnings;
use Socket;

use Apache2 ();
use Apache2::Log;
use Apache2::Const -compile => qw(OK REDIRECT :log);
use APR::Const    -compile => qw(:error SUCCESS);
use Template;
use Apache2::RequestRec ();
use Apache2::RequestIO ();
use CGI ();

use OpenSRF::AppSession;
use OpenSRF::System;
use OpenILS::Utils::Fieldmapper;

use vars '$lib_ips_hash';

my $bootstrap_config_file;
sub import {
	my( $self, $config ) = @_;
	$bootstrap_config_file = $config;
}

sub init {
	OpenSRF::System->bootstrap_client( config_file => $bootstrap_config_file );
}


sub handler {

	my $user_ip = $ENV{REMOTE_ADDR};
	my $apache_obj = shift;
	my $cgi = CGI->new( $apache_obj );

	my $hostname = $cgi->server_name();
	my $port		= $cgi->server_port();

	my $proto = "http";
	if($cgi->https) { $proto = "https"; }

	my $url = "$proto://$hostname:$port/opac/skin/en-US/default/xml/index.xml";

	my $path = $apache_obj->path_info();

	warn "Client connecting from $user_ip\n";

	if( my $lib_data = redirect_libs( $user_ip ) ) {
		my $region = $lib_data->[0];
		my $library = $lib_data->[1];

		warn "Will redirect to $region / $library\n";
		my $session = OpenSRF::AppSession->create("open-ils.storage");
		my $shortname = "$region-$library";

		my $org = $session->request(
			"open-ils.storage.direct.actor.org_unit.search.shortname",
			 $shortname)->gather(1);

		if($org) { $url .= "?location=" . $org->id; }

	}

	print "Location: $url\n\n"; 
	return Apache2::Const::REDIRECT;

	return print_page($url);
}

sub redirect_libs {
	my $source_ip = shift;
	my $aton_binary = inet_aton( $source_ip );

	if( ! $aton_binary ) { return 0; }

	# do this the linear way for now...
	for my $reg (keys %$lib_ips_hash) {

		for my $lib( keys %{$lib_ips_hash->{$reg}} ) {

			for my $block (@{$lib_ips_hash->{$reg}->{$lib}}) {

				if(defined($block->[0]) && defined($block->[1]) ) {
					my $start_binary	= inet_aton( $block->[0] );
					my $end_binary		= inet_aton( $block->[1] );
					unless( $start_binary and $end_binary ) { next; }
					if( $start_binary le $aton_binary and
							$end_binary ge $aton_binary ) {
						return [ $reg, $lib ];
					}
				}
			}
		}
	}
	return 0;
}


sub print_page {

	my $url = shift;

	print "Content-type: text/html; charset=utf-8\n\n";
	print <<"	HTML";
	<html>
		<head>
			<meta HTTP-EQUIV='Refresh' CONTENT="0; URL=$url"/> 
			<style  TYPE="text/css">
				.loading_div {
					text-align:center;
					margin-top:30px;
				font-weight:bold;
						background: lightgrey;
					color:black;
					width:100%;
				}
			</style>
		</head>
		<body>
			<br/><br/>
			<div class="loading_div">
				<h4>Loading...</h4>
			</div>
			<br/><br/>
			<center><img src='/opac/images/main_logo.jpg'/></center>
		</body>
	</html>
	HTML

	return Apache2::Const::OK;
}


1;
