#!/usr/bin/perl

#----------------------------------------------------------------
# Code for testing the container API
#----------------------------------------------------------------

require '../oils_header.pl';
use vars qw/ $apputils $memcache $user $authtoken $authtime /;
use strict; use warnings;

#----------------------------------------------------------------
err("\nusage: $0 <config> <oils_login_username> ".
	" <oils_login_password> <name> <org>\n".
	"Where <name> is the copy location name and <org> is the \n".
	"org that houses the new location object\n") unless $ARGV[4];
#----------------------------------------------------------------

my $config		= shift; 
my $username	= shift;
my $password	= shift;
my $name			= shift;
my $org			= shift;

sub go {
	osrf_connect($config);
	oils_login($username, $password);
	my $cl =create_cl($name, $org);
	update_cl($cl);
#	print_cl($org);
	delete_cl($cl);
}

go();

#----------------------------------------------------------------

sub create_cl {
	my( $name, $org ) = @_;

	my $cl = Fieldmapper::asset::copy_location->new;
	$cl->owning_lib($org);
	$cl->name($name);
	$cl->circulate(0);
	$cl->opac_visible(0);
	$cl->holdable(0);

	my $resp = simplereq(
		CIRC(), 'open-ils.circ.copy_location.create', $authtoken, $cl );

	oils_event_die($resp);
	printl("Copy location $name successfully created");
	$cl->id($resp);
	return $cl;
}

sub print_cl {
	my( $org ) = @_;
	debug( simplereq(
		CIRC(), 'open-ils.circ.copy_location.retrieve.all', $authtoken, $org ) );
}

sub update_cl {
	my $cl = shift;
	$cl->name( 'test_' . $cl->name );
	my $resp = simplereq(
		CIRC(), 'open-ils.circ.copy_location.update', $authtoken, $cl );
	oils_event_die($resp);
	printl("Successfully set copy location name to ".$cl->name);
}

sub delete_cl {
	my $cl = shift;
	my $resp = simplereq(
		CIRC(), 'open-ils.circ.copy_location.delete', $authtoken, $cl->id );
	oils_event_die($resp);
	printl("Copy location successfully deleted");
}


