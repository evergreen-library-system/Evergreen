#!/usr/bin/perl
#----------------------------------------------------------------
# Print CIRC
#----------------------------------------------------------------

require '../oils_header.pl';
use vars qw/$apputils/;
use strict;
use Data::Dumper;
my $config		= shift; 
my $username	= shift || 'admin';
my $password	= shift || 'open-ils';
my $circ_id       = shift;
my $hook        = shift || 'circ.format.history.print';
my $granularity        = shift || 'print-on-demand';

osrf_connect($config);
oils_login($username, $password);
my $e = OpenILS::Utils::CStoreEditor->new;

my $circ = $e->retrieve_action_circulation($circ_id) or oils_event_die($e->event);
print "hook = $hook, gran = $granularity, circ = $circ, circ_lib = " . $circ->circ_lib . "\n";

# args = $self, $event_def, $hook, $object, $context_org, $granularity, $user_data
my $result = $apputils->fire_object_event(
    undef,
    $hook,
    [ $circ ],
    $circ->circ_lib,
    $granularity,
    [] 
);

print Dumper($result) . "\n";

