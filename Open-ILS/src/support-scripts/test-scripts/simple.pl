#!/usr/bin/perl

#----------------------------------------------------------------
# Simple example
#----------------------------------------------------------------

require '../oils_header.pl';
use vars qw/ $apputils $memcache $user $authtoken $authtime /;
use strict; use warnings;

my $config = $ARGV[0];
err( "usage: $0 <bootstrap_config>" ) unless $config;
osrf_connect($config);

my( $user, $evt ) = simplereq( STORAGE(), 'open-ils.storage.direct.actor.user.retrieve', 1 );
oils_event_die($evt); # this user was not found / not all methods return events..
print debug($user);

