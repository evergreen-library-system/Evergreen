package OpenILS::WWW::Redirect;
use strict; use warnings;

use Socket;
use Apache2::Log;
use Apache2::Const -compile => qw(OK REDIRECT :log);
use APR::Const    -compile => qw(:error SUCCESS);
use Apache2::RequestRec ();
use Apache2::RequestIO ();
use CGI ();

use OpenSRF::AppSession;
use OpenSRF::System;
use OpenSRF::Utils::Logger qw/$logger/;

use vars '$lib_ips_hash';
my $lib_ips_hash;

my $bootstrap_config_file;
sub import {
	my( $self, $config ) = @_;
	$bootstrap_config_file = $config;
}

sub init {
	OpenSRF::System->bootstrap_client( config_file => $bootstrap_config_file );
}

sub parse_ips_file {
    my $class = shift;
    my $ips_file = shift;

    if( open(F, $ips_file) ) {

       while( my $data = <F> ) {
         chomp($data);

         my( $shortname, $ip1, $ip2 ) = split(/\s+/, $data);
         next unless ($shortname and $ip1 and $ip2);

         $lib_ips_hash->{$shortname} = [] unless $lib_ips_hash->{$shortname};
         push( @{$lib_ips_hash->{$shortname}}, [ $ip1, $ip2 ] );
       }

       close(F);

    } else {
        $logger->error("Unable to open lib IP redirector file $ips_file");
    }
}


sub handler {

	my $user_ip = $ENV{REMOTE_ADDR};
	my $apache_obj = shift;
	my $cgi = CGI->new( $apache_obj );

	my $hostname = $cgi->server_name();
	my $port		= $cgi->server_port();

	my $proto = "http";
	if($cgi->https) { $proto = "https"; }

	my $url = "$proto://$hostname:$port/opac/en-US/skin/default/xml/index.xml";

	my $path = $apache_obj->path_info();

	$logger->debug("Apache client connecting from $user_ip");

	if(my $shortname = redirect_libs($user_ip)) {

		$logger->info("Apache redirecting $user_ip to $shortname");
		my $session = OpenSRF::AppSession->create("open-ils.actor");

		my $org = $session->request(
            'open-ils.actor.org_unit.retrieve_by_shorname',
			 $shortname)->gather(1);

		if($org) { $url .= "?ol=" . $org->id; }
	}

	print "Location: $url\n\n"; 
	return Apache2::Const::REDIRECT;

	return print_page($url);
}

sub redirect_libs {
	my $source_ip = shift;
	my $aton_binary = inet_aton( $source_ip );

    return 0 unless $aton_binary;

	# do this the linear way for now...
	for my $shortname (keys %$lib_ips_hash) {

        for my $block (@{$lib_ips_hash->{$shortname}}) {

            if(defined($block->[0]) && defined($block->[1]) ) {
                my $start_binary	= inet_aton( $block->[0] );
                my $end_binary		= inet_aton( $block->[1] );
                next unless( $start_binary and $end_binary );
                if( $start_binary le $aton_binary and
                        $end_binary ge $aton_binary ) {
                    return $shortname;
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
