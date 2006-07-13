use strict; use warnings;
package OpenILS::Application::Auth;
use OpenSRF::Application;
use base qw/OpenSRF::Application/;
use OpenSRF::Utils::Cache;
use Digest::MD5 qw(md5_hex);
use OpenSRF::Utils::Logger qw(:level);
use OpenILS::Utils::Fieldmapper;
use OpenSRF::EX qw(:try);
use OpenILS::Application::AppUtils;
use OpenILS::Perm;
use OpenILS::Application::AppUtils;

# memcache handle
my $cache_handle;
my $apputils = "OpenILS::Application::AppUtils";


# ----------------------------------------------------------------------------
#
# XXX This module is deprecated.  Use the oils_auth.so C module.
#
# ----------------------------------------------------------------------------











# -------------------------------------------------------------
# Methods
# -------------------------------------------------------------
# -------------------------------------------------------------

__PACKAGE__->register_method(
	method	=> "init_authenticate",
	api_name	=> "open-ils.auth.authenticate.init",
	argc		=> 1, #(username) 
	note		=>	<<TEXT,
Generates a random seed and returns it.  The client
must then perform md5_hex( \$seed . \$password ) and use that
as the passwordhash to open-ils.auth.authenticate.complete
TEXT
);

__PACKAGE__->register_method(
	method	=> "complete_authenticate",
	api_name	=> "open-ils.auth.authenticate.complete",
	argc		=> 2, #( barcode, passwdhash )
	note		=> <<TEXT,
Client provides the username and passwordhash (see 
open-ils.auth.authenticate.init).  If their password hash is 
correct for the given username, a session id is returned, 
if not, "0" is returned
TEXT
);

__PACKAGE__->register_method(
	method	=> "retrieve_session",
	api_name	=> "open-ils.auth.session.retrieve",
	argc		=> 1, #( sessionid )
	note		=> <<TEXT,
Pass in a sessionid and this returns the username associated with it
TEXT
);

__PACKAGE__->register_method(
	method	=> "delete_session",
	api_name	=> "open-ils.auth.session.delete",
	argc		=> 1, #( sessionid )
	note		=> <<TEXT,
Pass in a sessionid and this delete it from the cache 
TEXT
);


# -------------------------------------------------------------
# Implementation
# -------------------------------------------------------------
# -------------------------------------------------------------


# -------------------------------------------------------------
# connect to the memcache server
# -------------------------------------------------------------
sub child_init {
	$cache_handle = OpenSRF::Utils::Cache->new('global');
}


# -------------------------------------------------------------
# We build a random hash and put the hash along with the 
# username into memcache (so that any backend may fulfill the
# auth request).
# -------------------------------------------------------------
sub init_authenticate {
	my( $self, $client, $username ) = @_;
	my $seed = md5_hex( time() . $$ . rand() . $username );
	$cache_handle->put_cache( "_open-ils_seed_$username", $seed, 30 );
	warn "init happened with seed $seed\n";
	return $seed;
}

# -------------------------------------------------------------
# The temporary hash is removed from memcache.  
# We retrieve the password from storage and verify
# their password hash against our re-hashed version of the 
# password. If all goes well, we return the session id. 
# Otherwise, we return "0"
# If type is set to 'opac', then this is an opac login,
# otherwise, it's a staff login
# -------------------------------------------------------------
sub complete_authenticate {
	my( $self, $client, $username, $passwdhash, $type ) = @_;

	my $name = "open-ils.cstore.direct.actor.user.search.atomic";

	warn "Completing Authentication\n";

	warn "Retrieving user from cstore..\n";
	my $user_list = OpenILS::Application::AppUtils->simple_scalar_request(
			"open-ils.cstore", $name, { usrname => $username } );

	unless(ref($user_list)) {
		return { ilsevent => 1000 };
	}

	warn "We have the user from cstore with usrname $username\n";

	my $user = $user_list->[0];
	

	if(!$user or !ref($user) ) {
		return { ilsevent => 1000 };
	}

	my $password = $user->passwd();
	warn "user passwd is $password\n";

	if(!$password) {
		throw OpenSRF::EX::ERROR ("No password exists for $username", ERROR);
	}

	warn "we have a password\n";

	my $current_seed = $cache_handle->get_cache("_open-ils_seed_$username");
	$cache_handle->delete_cache( "_open-ils_seed_$username" );

	warn "Removed tmp data from cache\n";

	unless($current_seed) {
		throw OpenSRF::EX::User 
			("User must call open-ils.auth.init_authenticate first (or respond faster)");
	}

	my $hash = md5_hex($current_seed . $password);

	if( $hash eq $passwdhash ) {
		# password is correct... do they have permission to login here?

		my $timeout = 28800; #staff login timeout - different for opac?
		my $opactimeout = 604800; # 14 days

		if($type eq "opac") {
			# 1 is the top level org unit (we should probably load the tree and get id from it)
			warn "Checking user perms for OPAC login\n";
			if($apputils->check_user_perms($user->id(), 1, "OPAC_LOGIN")) {
				return OpenILS::Perm->new("OPAC_LOGIN");
			}

		} else {
			# 1 is the top level org unit (we should probably load the tree and get id from it)
			warn "Checking user perms for Staff login\n";
			if($apputils->check_user_perms($user->id(), 1, "STAFF_LOGIN")) {
				return OpenILS::Perm->new("STAFF_LOGIN");
			}
		}

		my $session_id = md5_hex(time() . $$ . rand()); 
		$cache_handle->put_cache( $session_id, $user, $timeout );
		#return $session_id;
		return { ilsevent => 0, authtoken => $session_id };

	} else {

		warn "User password is incorrect...\n"; # send exception
		return { ilsevent => 1000 };
	}
}

sub retrieve_session {
	my( $self, $client, $sessionid ) = @_;
	my $user =  $cache_handle->get_cache($sessionid);
	if(!$user) {
		warn "No User returned from retrieve_session $sessionid\n";
	}
	if($user) {$user->clear_passwd();}
	return $user;
}

sub delete_session {
	my( $self, $client, $sessionid ) = @_;
	return $cache_handle->delete_cache($sessionid);
}


1;
