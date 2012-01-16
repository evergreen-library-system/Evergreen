#!/usr/bin/perl

#    This CGI script might be useful for providing an easy way for EZproxy to authenticate
#    users against an Evergreen instance.
#    
#    For example, if you modify your eg.conf by adding this:
#    Alias "/cgi-bin/ezproxy/" "/openils/var/cgi-bin/ezproxy/"
#    <Directory "/openils/var/cgi-bin/ezproxy">
#        AddHandler cgi-script .pl
#        AllowOverride None
#        Options +ExecCGI
#        allow from all
#    </Directory>
#    
#    and make that directory and copy remoteauth.cgi to it:
#    mkdir /openils/var/cgi-bin/ezproxy/
#    cp remoteauth.cgi /openils/var/cgi-bin/ezproxy/
#    
#    Then you could add a line like this to the users.txt of your EZproxy instance:
#    
#    ::external=https://hostname/cgi-bin/ezproxy/remoteauth.cgi,post=user=^u&passwd=^p
#

#use strict;
use warnings;

use CGI;
use Digest::MD5 qw(md5_hex);

use OpenSRF::EX qw(:try);
use OpenSRF::System;
use OpenSRF::AppSession;

my $bootstrap = '/openils/conf/opensrf_core.xml';
my $cgi = new CGI;
my $u = $cgi->param('user');
my $usrname = $cgi->param('usrname');
my $barcode = $cgi->param('barcode');
my $agent = $cgi->param('agent'); # optional, but preferred
my $p = $cgi->param('passwd');

print $cgi->header(-type=>'text/html', -expires=>'-1d');

OpenSRF::AppSession->ingress('remoteauth');
OpenSRF::System->bootstrap_client( config_file => $bootstrap );

if (!($u || $usrname || $barcode) || !$p) {
	print '+INCOMPLETE';
} else {
	my $nametype;
    if ($usrname) {
        $u = $usrname;
	    $nametype = 'username';
    } elsif ($barcode) {
        $u = $barcode;
        $nametype = 'barcode';
    } else {
	    $nametype = 'username';
        my $regex_response = OpenSRF::AppSession
            ->create('open-ils.actor')
            ->request('open-ils.actor.ou_setting.ancestor_default', 1, 'opac.barcode_regex')
            ->gather(1);
        if ($regex_response) {
            my $regexp = $regex_response->{'value'};
            $nametype = 'barcode' if ($u =~ qr/$regexp/);
        }
    }
	my $seed = OpenSRF::AppSession
		->create('open-ils.auth')
		->request( 'open-ils.auth.authenticate.init', $u )
		->gather(1);
	if ($seed) {
		my $response = OpenSRF::AppSession
			->create('open-ils.auth')
			->request( 'open-ils.auth.authenticate.verify', 
				{ $nametype => $u, password => md5_hex($seed . md5_hex($p)), type => 'opac', agent => $agent })
			->gather(1);
		if ($response) {
			if ($response->{ilsevent} == 0) {
				print '+VALID';
			} else {
				print '+NO';
			}
		} else {
			print '+BACKEND_ERROR';
		}
	} else {
		print '+BACKEND_ERROR';
	}
}

1;
