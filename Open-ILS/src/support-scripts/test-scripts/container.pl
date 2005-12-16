#!/usr/bin/perl

#----------------------------------------------------------------
# Code for testing the container API
#----------------------------------------------------------------

require '../oils_header.pl';

my $config		= shift; 
my $username	= shift || 'admin';
my $password	= shift || 'open-ils';

osrf_connect($config);
oils_login($username, $password);
oils_fetch_session($authtoken);

my %types;
my $meth = 'open-ils.storage.direct.container';
$types{'biblio'} = "biblio_record_entry_bucket";
$types{'callnumber'} = "call_number_bucket";
$types{'copy'} = "copy_bucket";
$types{'user'} = "user_bucket";

my %containers;

containers_create();
containers_delete();


sub containers_create {

	for my $type ( keys %types ) {
		my $bucket = "Fieldmapper::container::" . $types{$type};
		$bucket = $bucket->new;
		$bucket->owner($user->id);
		$bucket->name("TestBucket");
		$bucket->btype("TestType");
	
		my $resp = simplereq($ACTOR, 
			'open-ils.actor.container.bucket.create',
			$authtoken, $type, $bucket );
	
		oils_event_die($resp);
		printl("Created new $type bucket with id $resp");
		$containers{$type} = $resp;
	}
}

sub containers_delete {
	for my $type (keys %containers) {
		my $id = $containers{$type};

		my $resp = simplereq( $ACTOR,
			'open-ils.actor.container.bucket.delete',
			$authtoken, $type, $id );

		oils_event_die($resp);
		printl("Deleted bucket $id");
	}
}
	

