#!/usr/bin/perl
use strict;
use warnings;

use lib 'LIBDIR/perl5/';

use OpenSRF::System;
use OpenSRF::Application;
use OpenSRF::EX qw/:try/;
use OpenSRF::AppSession;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::Fieldmapper;
use Digest::MD5 qw/md5_hex/;

use Getopt::Long;

my ($od_length, $user, $password, $config) =
	('180 days', 'admin', 'open-ils', 'SYSCONFDIR/opensrf_core.xml');

GetOptions(
	'overdue=s'	=> \$od_length,
	'user=s'	=> \$user,
	'password=s'	=> \$password,
	'config=s'	=> \$config,
);

OpenSRF::System->bootstrap_client( config_file => $config );
Fieldmapper->import(IDL => OpenSRF::Utils::SettingsClient->new->config_value("IDL"));

my $auth = login($user,$password);

my $ses = OpenSRF::AppSession->create('open-ils.cstore');
my $req = $ses->request(
	'open-ils.cstore',
	'open-ils.cstore.json_query',
	{ select => { circ =>  [ qw/id/ ] }, from => circ => where => { due_date => { ">" => { transform => "age", value => "340 days" } } } }
);

while ( my $res = $req->recv( timeout => 120 ) ) {
	print $res->content->target_copy . "\n";
}

sub login {        
	my( $username, $password, $type ) = @_;

	$type |= "staff"; 

	my $seed = OpenILS::Application::AppUtils->simplereq(
		'open-ils.auth',
		'open-ils.auth.authenticate.init',
		$username
	);

	die("No auth seed. Couldn't talk to the auth server") unless $seed;

	my $response = OpenILS::Application::AppUtils->simplereq(
		'open-ils.auth',
		'open-ils.auth.authenticate.complete',
                {       username => $username,
                        password => md5_hex($seed . md5_hex($password)),
                        type => $type });

        die("No auth response returned on login.") unless $response;

        my $authtime = $response->{payload}->{authtime};
        my $authtoken = $response->{payload}->{authtoken};

	die("Login failed for user $username!") unless $authtoken;

        return $authtoken;
}       


