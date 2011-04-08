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
use Net::IP;

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

         my ($shortname, $ip1, $ip2, $skin, $domain) = split(/\s+/, $data);
         next unless ($shortname and $ip1 and $ip2);

         $lib_ips_hash->{$shortname} = [] unless $lib_ips_hash->{$shortname};
         push( @{$lib_ips_hash->{$shortname}}, [ $ip1, $ip2, $skin, $domain ] );
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


	my $skin = $apache_obj->dir_config('OILSRedirectSkin') || 'default';
	my $depth = $apache_obj->dir_config('OILSRedirectDepth');
	my $locale = $apache_obj->dir_config('OILSRedirectLocale') || 'en-US';

	my $hostname = $cgi->server_name();
	my $port		= $cgi->server_port();

	my $proto = "http";
	if($cgi->https) { $proto = "https"; }

	my $url = "$proto://$hostname:$port/opac/$locale/skin/$skin/xml/index.xml";
	my $path = $apache_obj->path_info();

	$logger->debug("Apache client connecting from $user_ip");

	my ($shortname, $nskin, $nhostname) = redirect_libs($user_ip);
	if ($shortname) {

		if ($nskin =~ m/[^\s]/) { $skin = $nskin; }
		if ($nhostname =~ m/[^\s]/) { $hostname = $nhostname; }

		$logger->info("Apache redirecting $user_ip to $shortname with skin $skin and host $hostname");
		my $session = OpenSRF::AppSession->create("open-ils.actor");

		$url = "$proto://$hostname:$port/opac/$locale/skin/$skin/xml/index.xml";

		my $org = $session->request(
            'open-ils.actor.org_unit.retrieve_by_shortname',
			 $shortname)->gather(1);

		if($org) { 
            $url .= "?ol=" . $org->id; 
            $url .= "&d=$depth" if defined $depth;
        }
	}

	print "Location: $url\n\n"; 
	return Apache2::Const::REDIRECT;

	return print_page($url);
}

sub redirect_libs {
	my $source_ip = new Net::IP (shift) or return 0;

	# do this the linear way for now...
	for my $shortname (keys %$lib_ips_hash) {

        for my $block (@{$lib_ips_hash->{$shortname}}) {

            $logger->debug("Checking whether " . $source_ip->ip() . " is in the range " . $block->[0] . " to " . $block->[1]);
            if(defined($block->[0]) && defined($block->[1]) ) {
                my $range = new Net::IP( $block->[0] . ' - ' . $block->[1] );
                if( $source_ip->overlaps($range)==$IP_A_IN_B_OVERLAP ||
                    $source_ip->overlaps($range)==$IP_IDENTICAL ) {
                    return ($shortname, $block->[2], $block->[3]);
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
