package OpenSRF::Utils::Cache;
use strict; use warnings;
use base qw/Cache::Memcached OpenSRF/;
use Cache::Memcached;
use OpenSRF::Utils::Config;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::EX qw(:try);
use JSON;


=head OpenSRF::Utils::Cache

This class just subclasses Cache::Memcached.
see Cache::Memcached for more options.

The value passed to the call to current is the cache type
you wish to access.  The below example sets/gets data
from the 'user' cache.

my $cache = OpenSRF::Utils::Cache->current("user");
$cache->set( "key1", "value1" [, $expire_secs ] );
my $val = $cache->get( "key1" );


=cut

sub DESTROY {}

my %caches;

# ------------------------------------------------------
# Persist methods and method names
# ------------------------------------------------------
my $persist_add_slot; 
my $persist_push_stack;
my $persist_peek_stack;
my $persist_destroy_slot;
my $persist_slot_get_expire;
my $persist_slot_find;

my $max_persist_time					= 86400;
my $persist_add_slot_name			= "opensrf.persist.slot.create_expirable";
my $persist_push_stack_name		= "opensrf.persist.stack.push";
my $persist_peek_stack_name		= "opensrf.persist.stack.peek";
my $persist_destroy_slot_name		= "opensrf.persist.slot.destroy";
my $persist_slot_get_expire_name = "opensrf.persist.slot.get_expire";
my $persist_slot_find_name			= "opensrf.persist.slot.find";;

# ------------------------------------------------------


# return a named cache if it exists
sub current { 
	my ( $class, $c_type )  = @_;
	return undef unless $c_type;
	return $caches{$c_type} if exists $caches{$c_type};
	return $caches{$c_type} = $class->new( $c_type );
}


# create a new named memcache object.
sub new {

	my( $class, $cache_type, $persist ) = @_;
	$cache_type ||= 'global';
	$class = ref( $class ) || $class;

	return $caches{$cache_type} 
		if (defined $caches{$cache_type});

	my $conf = OpenSRF::Utils::SettingsClient->new;
	my $servers = $conf->config_value( cache => $cache_type => servers => 'server' );
	my $expire_time = $conf->config_value( cache => $cache_type => 'max_cache_time' );

	if(!ref($servers)){
		$servers = [ $servers ];
	}

	my $self = {};
	$self->{persist} = $persist || 0;
	$self->{memcache} = Cache::Memcached->new( { servers => $servers } ); 
	if(!$self->{memcache}) {
		throw OpenSRF::EX::PANIC ("Unable to create a new memcache object for $cache_type");
	}

	bless($self, $class);
	$caches{$cache_type} = $self;
	return $self;
}



sub put_cache {
	my($self, $key, $value, $expiretime ) = @_;
	return undef unless( defined $key and defined $value );

	$value = JSON->perl2JSON($value);

	if($self->{persist}){ _load_methods(); }

	$expiretime ||= $max_persist_time;

	$self->{memcache}->set( $key, $value, $expiretime ) ||
		throw OpenSRF::EX::ERROR ("Unable to store $key => $value in memcached server" );;

	if($self->{"persist"}) {

		my ($slot) = $persist_add_slot->run("_CACHEVAL_$key", $expiretime . "s");

		if(!$slot) {
			# slot may already exist
			($slot) = $persist_slot_find->run("_CACHEVAL_$key");
			if(!defined($slot)) {
				throw OpenSRF::EX::ERROR ("Unable to create cache slot $key in persist server" );
			} else {
				#XXX destroy the slot and rebuild it to prevent DOS
			}
		}

		($slot) = $persist_push_stack->run("_CACHEVAL_$key", $value);

		if(!$slot) {
			throw OpenSRF::EX::ERROR ("Unable to push data onto stack in persist slot _CACHEVAL_$key" );
		}
	}

	return $key;
}

sub delete_cache {
	my( $self, $key ) = @_;
	if(!$key) { return undef; }
	if($self->{persist}){ _load_methods(); }
	$self->{memcache}->delete($key);
	if( $self->{persist} ) {
		$persist_destroy_slot->run("_CACHEVAL_$key");
	}
	return $key; 
}

sub get_cache {
	my($self, $key ) = @_;

	my $val = $self->{memcache}->get( $key );
	return $val if defined($val);

	if($self->{persist}){ _load_methods(); }

	# if not in memcache but we are persisting, the put it into memcache
	if( $self->{"persist"} ) {
		$val = $persist_peek_stack->( "_CACHEVAL_$key" );
		if(defined($val)) {
			my ($expire) = $persist_slot_get_expire->run("_CACHEVAL_$key");
			if($expire)	{
				$self->{memcache}->set( $key, $val, $expire);
			} else {
				$self->{memcache}->set( $key, $val, $max_persist_time);
			}
			return JSON->JSON2perl($val);
		} 
	}
	return undef;
} 




sub _load_methods {

	if(!$persist_add_slot) {
		$persist_add_slot = 
			OpenSRF::Application->method_lookup($persist_add_slot_name);
		if(!ref($persist_add_slot)) {
			throw OpenSRF::EX::PANIC ("Unable to retrieve method $persist_add_slot_name");
		}
	}

	if(!$persist_push_stack) {
		$persist_push_stack = 
			OpenSRF::Application->method_lookup($persist_push_stack_name);
		if(!ref($persist_push_stack)) {
			throw OpenSRF::EX::PANIC ("Unable to retrieve method $persist_push_stack_name");
		}
	}

	if(!$persist_peek_stack) {
		$persist_peek_stack = 
			OpenSRF::Application->method_lookup($persist_peek_stack_name);
		if(!ref($persist_peek_stack)) {
			throw OpenSRF::EX::PANIC ("Unable to retrieve method $persist_peek_stack_name");
		}
	}

	if(!$persist_destroy_slot) {
		$persist_destroy_slot = 
			OpenSRF::Application->method_lookup($persist_destroy_slot_name);
		if(!ref($persist_destroy_slot)) {
			throw OpenSRF::EX::PANIC ("Unable to retrieve method $persist_destroy_slot_name");
		}
	}
	if(!$persist_slot_get_expire) {
		$persist_slot_get_expire = 
			OpenSRF::Application->method_lookup($persist_slot_get_expire_name);
		if(!ref($persist_slot_get_expire)) {
			throw OpenSRF::EX::PANIC ("Unable to retrieve method $persist_slot_get_expire_name");
		}
	}
	if(!$persist_slot_find) {
		$persist_slot_find = 
			OpenSRF::Application->method_lookup($persist_slot_find_name);
		if(!ref($persist_slot_find)) {
			throw OpenSRF::EX::PANIC ("Unable to retrieve method $persist_slot_find_name");
		}
	}
}







1;

