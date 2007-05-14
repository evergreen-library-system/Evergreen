#!/usr/bin/perl

#----------------------------------------------------------------
# Simple example
#----------------------------------------------------------------

require '../oils_header.pl';
use vars qw/ $apputils $memcache $user $authtoken $authtime /;
use strict; use warnings;
use JSON;
use Time::HiRes qw/time/;
use OpenILS::Utils::Fieldmapper;

my $config = $ARGV[0];
err( "usage: $0 <bootstrap_config>" ) unless $config;
osrf_connect($config);

my $p = Fieldmapper::actor::user->new;
my $sr = Fieldmapper::action::survey_response->new;
$sr->answer_date('now');
$p->survey_responses( [ $sr ] );
my $c = $p->clone;
$p->clear_survey_responses;
debug($p);
debug($c);


exit;


my $s = time;
my( $user, $evt );
my $str = '';
#for(0..100) {
for(0..0) {
	( $user, $evt ) = simplereq( STORAGE(), 'open-ils.storage.direct.actor.user.retrieve', 1 );
	oils_event_die($evt); # this user was not found / not all methods return events..
	$str .= JSON->perl2JSON($user);
}
print "\ntime: " . (time - $s) . "\n";
print length($str) . "\n";



