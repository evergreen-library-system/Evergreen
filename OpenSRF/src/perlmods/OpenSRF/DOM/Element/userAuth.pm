package OpenSRF::DOM::Element::userAuth;
use OpenSRF::DOM;
use OpenSRF::Utils::Logger qw/:level/;
use OpenSRF::Utils::Config;
use Digest::MD5 qw/md5_hex/;
use OpenSRF::DomainObject::oilsMethod;
use OpenSRF::DomainObject::oilsResponse;
#use OpenSRF::App::Auth;
use OpenSRF::EX qw/:try/;
use OpenSRF::Utils::Cache;

use base 'OpenSRF::DOM::Element';

my $log = 'OpenSRF::Utils::Logger';

=head1 NAME

OpenSRF::DOM::Element::userAuth

=over 4

User authentication data structure for use in oilsMessage objects.

=back

=head1 SYNOPSIS

 use OpenSRF::DOM::Element::userAuth;

 %auth_structure = ( userid   => '0123456789', secret => 'junko' );
 %auth_structure = ( username => 'miker',      secret => 'junko' );

 my $auth = OpenSRF::DOM::Element::userAuth->new( %auth_structure );

...

 my %server_auth = ( sysname	=> 'OPACServer',
                     secret	=> 'deadbeefdeadbeef' );

 my $auth = OpenSRF::DOM::Element::userAuth->new( %server_auth );

=cut

sub new {
	my $class = shift;
	$class = ref($class) || $class;

	my %args = @_;

	$args{hashseed} ||= int( rand( $$ ) );

	$args{secret} = md5_hex($args{secret});
	$args{secret} = md5_hex($args{hashseed}. $args{secret});

	return $class->SUPER::new( %args );
}

sub username {
	my $self = shift;
	return $self->getAttribute('username');
}

sub userid {
	my $self = shift;
	return $self->getAttribute('userid');
}

sub sysname {
	my $self = shift;
	return $self->getAttribute('sysname');
}

sub secret {
	my $self = shift;
	return $self->getAttribute('secret');
}

sub hashseed {
	my $self = shift;
	return $self->getAttribute('hashseed');
}

sub authenticate {
	my $self = shift;
	my $session = shift;
	my $u = $self->username ||
		$self->userid ||
		$self->sysname;
	$log->debug("Authenticating user [$u]",INFO);


	# We need to make sure that we are not the auth server.  If we are,
	# we don't want to send a request to ourselves.  Instead just call
	# the local auth method.
	my @params = ( $u, $self->secret, $self->hashseed );
	my $res;

	# ------------------------------
	# See if we can auth with the cache first
	$log->debug( "Attempting cache auth...", INTERNAL );
	my $cache = OpenSRF::Utils::Cache->current("user"); 
	my $value = $cache->get( $u );

	if( $value  and $value eq $self->secret ) {
		$log->debug( "User $u is cached and authenticated", INTERNAL );
		return 1;
	}
	# ------------------------------

	if( $session->service eq "auth" ) {
		$log->debug( "We are AUTH. calling local auth", DEBUG ); 
		my $meth = OpenSRF::App::Auth->method_lookup('authenticate', 1);
		$log->debug("Meth ref is $meth", INTERNAL);
		$res = $meth->run( 1, @params );

	} else { 
		$log->debug( "Calling AUTH server", DEBUG );	
		$res = _request_remote_auth( $session, @params ); 
	}


	if( $res and $res->class->isa('OpenSRF::DomainObject::oilsResult') and 
			$res->content and ($res->content->value eq "yes") ) {

		$log->debug( "User $u is authenticated", DEBUG );
		$log->debug( "Adding $u to cache", INTERNAL );

		# Add to the cache ------------------------------
		$cache->set( $u, $self->secret ); 

		return 1;

	} else { 
		return 0; 
	}
	
} 

sub _request_remote_auth {

	my $server_session = shift;
	my @params = @_;

	my $service = $server_session->service;

	my @server_auth = (sysname => OpenSRF::Utils::Config->current->$service->sysname,
			   secret  => OpenSRF::Utils::Config->current->$service->secret );

	my $session = OpenSRF::AppSession->create( "auth", @server_auth ); 

	$log->debug( "Sending request to auth server", INTERNAL );
	
	my $req; my $res;

	try {

		if( ! $session->connect() ) {
			throw OpenSRF::EX::CRITICAL ("Cannot communicate with auth server");
		}
		$req = $session->request( authenticate => @params );
		$req->wait_complete( OpenSRF::Utils::Config->current->client->connect_timeout );
		$res = $req->recv(); 

	} catch OpenSRF::DomainObject::oilsAuthException with {
		return 0;

	} finally {
		$req->finish() if $req;
		$session->finish() if $session;
	};

	return $res;

}



1;
