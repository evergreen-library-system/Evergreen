use strict; use warnings;
package OpenILS::Application::Auth;
use OpenSRF::Application;
use base qw/OpenSRF::Application/;
use OpenSRF::Utils::Cache;
use Digest::MD5 qw(md5_hex);
use OpenSRF::Utils::Logger qw(:level);

# memcache handle
my $cache_handle;



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
sub initialize {

	my $config_client = OpenSRF::Utils::SettingsClient->new();
	my $memcache_servers = 
		$config_client->config_value( "apps","open-ils.auth", "app_settings","memcache" );

	if( !$memcache_servers ) {
		throw OpenSRF::EX::Config ("No Memcache servers specified for open-ils.auth!");
	}

	if(!ref($memcache_servers)) {
		$memcache_servers = [$memcache_servers];
	}
	$cache_handle = OpenSRF::Utils::Cache->new( "open-ils.auth", $memcache_servers );
}



# -------------------------------------------------------------
# We build a random hash and put the hash along with the 
# username into memcache (so that any backend may fulfill the
# auth request).
# -------------------------------------------------------------
sub init_authenticate {
	my( $self, $client, $username ) = @_;
	my $seed = md5_hex( time() . $$ . rand() . $username );
	$cache_handle->set( "_open-ils_seed_$username", $seed, 300 );
	return $seed;
}

# -------------------------------------------------------------
# The temporary hash is removed from memcache.  
# We retrieve the password from storage and verify
# their password hash against our re-hashed version of the 
# password. If all goes well, we return the session id. 
# Otherwise, we return "0"
# -------------------------------------------------------------
sub complete_authenticate {
	my( $self, $client, $username, $passwdhash ) = @_;

	my $name = "open-ils.storage.actor.user.retrieve.username";
	my $method = $self->method_lookup( $name );

	my $password = undef;
	if(!$method) {
		throw OpenSRF::EX::PANIC ("Could not lookup method $name");
	}

	my ($user) = $method->run($username);
	if(!$user) {
		throw OpenSRF::EX::ERROR ("No user for $username");
	}

	$password = $user->{passwd};
	if(!$password) {
		throw OpenSRF::EX::ERROR ("No password exists for $username", ERROR);
	}

	my $current_seed = $cache_handle->get("_open-ils_seed_$username");

	unless($current_seed) {
		throw OpenILS::EX::User 
			("User must call open-ils.auth.init_authenticate first (or respond faster)");
	}

	my $hash = md5_hex($current_seed . $password);
	$cache_handle->delete( "_open-ils_seed_$username" );

	if( $hash eq $passwdhash ) {

		my $session_id = md5_hex( time() . $$ . rand() ); 
		$cache_handle->set( $session_id, $username, 28800 );
		return $session_id;

	} else {

		return 0;
	}
}

sub retrieve_session {
	my( $self, $client, $sessionid ) = @_;
	return $cache_handle->get($sessionid);
}

sub delete_session {
	my( $self, $client, $sessionid ) = @_;
	return $cache_handle->delete($sessionid);
}


1;
