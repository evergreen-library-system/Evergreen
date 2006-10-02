package OpenILS::Reporter::Proxy;
use strict; use warnings;

use Apache2 ();
use Apache2::Log;
use Apache2::Const -compile => qw(OK BAD_REQUEST NOT_FOUNE DECLINED :log);
use APR::Const    -compile => qw(:error SUCCESS);
use CGI;
use Data::Dumper;

use OpenSRF::EX qw(:try);
use OpenSRF::System;


# set the bootstrap config and template include directory when 
# this module is loaded
my $bootstrap;

sub import {
	my $self = shift;
	$bootstrap = shift;
}


sub child_init {
	OpenSRF::System->bootstrap_client( config_file => $bootstrap );
}

sub handler {
	my $apache = shift;
	my $cgi = new CGI;
	my $auth_ses = $cgi->cookie('ses');

	my $user = verify_user($auth_ses);
	return Apache2::Const::BAD_REQUEST unless ($user);

	my $failures = OpenSRF::AppSession
		->create('open-ils.actor')
		->request('open-ils.actor.user.perm.check', $token, $user->id, 1, ['RUN_REPORTS'])
		->gather(1);

	return Apache2::Const::BAD_REQUEST if (@$failures > 0);

	# they're good, let 'em through
	return Apache2::Const::DECLINED if (-e $apache->filename);

	# oops, file not found
	return Apache2::Const::NOT_FOUND;
}

# returns the user object if the session is valid, 0 otherwise
sub verify_login {
	my $auth_token = shift;
	return 0 unless $auth_token;

	my $session = OpenSRF::AppSession
		->create("open-ils.auth")
		->request( "open-ils.auth.session.retrieve", $auth_token )
		->gather(1);

	if (ref($user) eq 'HASH' && $user->{ilsevent} == 1001) {
		return undef;
	}

	return $user if ref($user);
	return undef;
}



1;
