package OpenILS::Event;
# vim:noet:ts=4
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
my $descs = undef;

sub new {
	my( $class, $event, %params ) = @_;
	_load_events() unless $events;

	throw OpenSRF::EX ("Bad event name: $event") unless $event;
	my $e = $events->{$event} || -1;

	my( $m, $f, $l ) = caller(0);
	my( $mm, $ff, $ll ) = caller(1);
	my( $mmm, $fff, $lll ) = caller(2);

	$f  ||= "";
	$l  ||= "";
	$ff ||= "";
	$ll ||= "";
	$fff ||= "";
	$lll ||= "";

	my $lang = 'en-US'; # assume english for now

	my $t = CORE::localtime();

	return { 
		ilsevent		=> $e, 
		textcode		=> $event, 
		stacktrace	=> "$f:$l $ff:$ll $fff:$lll", 
		desc			=> $descs->{$lang}->{$e} || '',
		servertime	=> $t,
		pid			=> $$, %params };
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

	$descs = {};
	my @desc = $doc->documentElement->findnodes('//desc');
	for my $d (@desc) {
		my $lang = $d->getAttributeNS('http://www.w3.org/XML/1998/namespace', 'lang');
		my $code = $d->parentNode->getAttribute('code');
		unless ($descs && $lang && exists $descs->{$lang}) {
			$descs->{$lang} = {};
			if (!$descs) {
				$logger->error("No error description nodes found in $eventsxml.");
			}
			if (!$lang) {
				$logger->error("No xml:lang attribute found for node in $eventsxml.");
			}
		}
		$descs->{$lang}->{$code} = $d->textContent;
	}
}




1;
