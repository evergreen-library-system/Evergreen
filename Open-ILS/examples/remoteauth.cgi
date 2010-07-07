#!/usr/bin/perl
#use strict;
use warnings;

use CGI;
use Digest::MD5 qw(md5_hex);

use OpenSRF::EX qw(:try);
use OpenSRF::System;


my $bootstrap = '/openils/conf/opensrf_core.xml';
my $cgi = new CGI;
my $u = $cgi->param('user');
my $p = $cgi->param('passwd');

print $cgi->header(-type=>'text/html', -expires=>'-1d');

OpenSRF::System->bootstrap_client( config_file => $bootstrap );

if (!$u || !$p) {
	print "+INCOMPLETE";
} else {
	my $nametype = 'username';
	$nametype = 'barcode' if ($u =~ /^\d+$/o);
	my $seed = OpenSRF::AppSession
		->create("open-ils.auth")
		->request( 'open-ils.auth.authenticate.init', $u )
		->gather(1);
	if ($seed) {
		my $response = OpenSRF::AppSession
			->create("open-ils.auth")
			->request( 'open-ils.auth.authenticate.complete', { $nametype => $u, password => md5_hex($seed . md5_hex($p)), type => 'temp' })
			->gather(1);
		if ($response->{payload}->{authtoken}) {
			my $user = OpenSRF::AppSession
				->create("open-ils.auth")
				->request( "open-ils.auth.session.retrieve", $response->{payload}->{authtoken} )
				->gather(1);
			if (ref($user) eq 'HASH' && $user->{ilsevent} == 1001) {
				print "+NO";
			} else {
				print "+VALID";
			}
		} else {
			print "+NO";
		}
	} else {
		print "+BACKEND_ERROR";
	}

}

1;
