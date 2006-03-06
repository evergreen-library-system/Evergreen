#!/usr/bin/perl

#----------------------------------------------------------------
# Code for testing the container API
#----------------------------------------------------------------

require '../oils_header.pl';
use vars qw/ $user $authtoken /;
use strict; use warnings;

my $config		= shift; 
my $copyid		= shift;
#my $copyid		= 1;
my $username	= shift || 'admin';
my $password	= shift || 'open-ils';

my $create_method		= 'open-ils.circ.copy_note.create';
my $retrieve_method	= 'open-ils.circ.copy_note.retrieve.all';
my $delete_method		= 'open-ils.circ.copy_note.delete';


sub go {
	osrf_connect($config);
	oils_login($username, $password);
	oils_fetch_session($authtoken);
	create_notes();
	retrieve_notes();
	delete_notes();
}
go();

#----------------------------------------------------------------

my @ids_created;
sub create_notes {

	for(0..5) {
		my $note = Fieldmapper::asset::copy_note->new;
	
		$note->owning_copy($copyid);
		$note->creator($user->id);
		$note->title("Test Note 1");
		$note->value("This copy needs to be fixed - $_");
		$note->pub(1);
	
		my $id = simplereq(
			'open-ils.circ', $create_method, $authtoken, $note );
		oils_event_die($id);
		push(@ids_created, $id);
		printl("Created copy note $id");
	}
}

sub retrieve_notes {
	my $notes = simplereq(
		'open-ils.circ', $retrieve_method, 
			{authtoken => $authtoken, itemid => $copyid});
	oils_event_die($notes);
	printl("Retrieved: [".$_->id."] ".$_->value) for @$notes;
}

sub delete_notes() {
	for my $id (@ids_created) {
		my $stat = simplereq(
			'open-ils.circ', $delete_method, $authtoken, $id);
		oils_event_die($stat);
		printl("Deleted note $id");
	}
}



