package OpenSRF::Utils::Cache;
use strict; use warnings;
use base qw/Cache::Memcached OpenSRF/;
use Cache::Memcached;
use OpenSRF::Utils::Config;


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


# return a named cache if it exists
sub current { 
	my ( $class, $c_type )  = @_;
	return undef unless $c_type;
	return $caches{$c_type} if exists $caches{$c_type};
	return $caches{$c_type} = $class->new( $c_type );
}


# create a new named memcache object.
sub new {

	my( $class, $cache_type, $servers ) = @_;
	return undef unless $cache_type;

	return $caches{$cache_type} if exists $caches{$cache_type};

	$class = ref( $class ) || $class;
	my $instance = Cache::Memcached->new( { servers => $servers } ); 
	$caches{$cache_type} = $instance;
	return bless( $instance, $class );
}


1;





