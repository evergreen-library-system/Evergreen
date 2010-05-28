#!/usr/bin/perl
#----------------------------------------------------------------
# Print AHR
#----------------------------------------------------------------

require '../oils_header.pl';
use vars qw/$apputils/;
use strict;
use Data::Dumper;
my $config		= shift; 
my $username	= shift || 'admin';
my $password	= shift || 'open-ils';
my $hold_id       = shift;
my $hook        = shift || 'ahr.format.history.print';
my $granularity        = shift || 'print-on-demand';

osrf_connect($config);
oils_login($username, $password);
my $e = OpenILS::Utils::CStoreEditor->new;

my $hold = $e->retrieve_action_hold_request($hold_id) or oils_event_die($e->event);
print "hook = $hook, gran = $granularity, hold = $hold, request_lib = " . $hold->request_lib . "\n";

# args = $self, $event_def, $hook, $object, $context_org, $granularity, $user_data
my $result = $apputils->fire_object_event(
    undef,
    $hook,
    [ $hold ],
    $hold->request_lib,
    $granularity,
    [] 
);

print Dumper($result) . "\n";

