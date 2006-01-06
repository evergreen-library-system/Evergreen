package OpenILS::Utils::ScriptRunner;
use strict; use warnings;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::SpiderMonkey;

sub new {

	my $class = shift;
	my %params = @_;
	$class = ref($class) || $class;

	my $type = $params{type} || 'js';
	my $thingy = OpenILS::Utils::SpiderMonkey->new( %params ) if( $type =~ /js/i );

	if($thingy) { 
		$thingy->init; 
		return $thingy;

	} else { 
		$logger->error("Unknown script type in OpenILS::Utils::ScriptRunner"); 
	}
	return undef;
}

sub init {$logger->error("METHOD NOT DEFINED"); }

# the script context
sub context {$logger->error("METHOD NOT DEFINED"); }

# Retrieves a value based on key
sub retrieve {$logger->error("METHOD NOT DEFINED"); }

# generic insertion method - should work on arrays, 
# hashes, fieldmapper objects, and scalars
sub insert {$logger->error("METHOD NOT DEFINED"); }

# loads an external script
sub load { $logger->error("METHOD NOT DEFINED"); }

# Runs an external script.
# @return 1 on success, 0 on failure
sub run { $logger->error("METHOD NOT DEFINED"); }

# load an external library
sub load_lib { $logger->error("METHOD NOT DEFINED"); }

1;
