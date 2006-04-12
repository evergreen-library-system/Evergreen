#!/usr/bin/perl
require '../oils_header.pl';
use vars qw/ $user $authtoken /;
use strict; use warnings;
use Time::HiRes qw/time/;
use Data::Dumper;
use JSON;

#-----------------------------------------------------------------------------
# Does a checkout, renew, and checkin 
#-----------------------------------------------------------------------------

err("usage: $0 <config> <username> <password> <patronid> <title> <text>") unless $ARGV[5];

my $config		= shift; # - bootstrap config
my $username	= shift; # - oils login username
my $password	= shift; # - oils login password
my $patronid	= shift;
my $title		= shift;
my $text			= shift;


sub go {
	osrf_connect($config);
	oils_login($username, $password);
	create_note();
	retrieve_notes();
	oils_logout();
}
go();



#-----------------------------------------------------------------------------
# 
#-----------------------------------------------------------------------------
sub create_note {

	my $note = Fieldmapper::actor::usr_note->new;

	$note->usr($patronid);
	$note->title($title);
	$note->value($text);
	$note->pub(0);

	my $id = simplereq(
		'open-ils.actor', 
		'open-ils.actor.note.create', $authtoken, $note );

	oils_event_die($id);
	printl("created new note...");
	return $id;
}

sub retrieve_notes {

	my $notes = simplereq(
		'open-ils.actor',
		'open-ils.actor.note.retrieve.all', $authtoken, $patronid );

	oils_event_die($notes);

	for my $n (@$notes) {
		printl("received note:");
		printl("\t". $n->creator);
		printl("\t". $n->usr);
		printl("\t". $n->title);
		printl("\t". $n->value);
	}
}
