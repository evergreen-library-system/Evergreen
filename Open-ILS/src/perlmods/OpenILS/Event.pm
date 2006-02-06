package OpenILS::Event;
use strict; use warnings;
use XML::LibXML;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Logger;
my $logger = "OpenSRF::Utils::Logger";


# Creates a new Event object.  
# The first param is the event name
# Following the first param is an optional hash of params:
#		perm => the name of the permission error for permimssion errors
#		permloc => the location of the permission error for permission errors
#		payload => the payload to be returned on successfull events


my $events = undef;
sub new {
	my( $class, $event, %params ) = @_;

	_load_events() unless $events;

	if( $event ne 'SUCCESS' ) {
		$logger->info("Returning non-success event object: $event ");  
	}

	my $e = $events->{$event};
	throw OpenSRF::EX 
		("No event defined with textcode: $event") unless defined $e;

	my( $m, $f, $l ) = caller(0);
	my( $mm, $ff, $ll ) = caller(1);

	return { ilsevent => $e, textcode => $event, 
		stacktrace => "$f:$l, $ff:$ll", %params };
}

sub _load_events {
	my $settings_client = OpenSRF::Utils::SettingsClient->new();
	my $eventsxml =  $settings_client->config_value( "ils_events" );

	if(!$eventsxml) { 
		throw OpenSRF::EX ("No ils_events file found in settings config"); 
	}

	$logger->info("Loading events xml file $eventsxml");

	my $doc = XML::LibXML->new->parse_file($eventsxml);

	my @nodes = $doc->documentElement->findnodes('//event');
	for my $node (@nodes) {
		$events->{$node->getAttribute('textcode')} = 
			$node->getAttribute('code');
	}
}

1;
