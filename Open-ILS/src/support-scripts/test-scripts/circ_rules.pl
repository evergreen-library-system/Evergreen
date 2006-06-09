#/usr/bin/perl
use strict; use warnings;
use lib q|../../../perlmods/|;
use OpenILS::Utils::ScriptRunner;
require '../oils_header.pl';
use vars qw/ $user $authtoken $apputils /;


# ---------------------------------------------------------------------
# SCRIPT VARS
# ----------------------------------------------------------------------
my $patronid					= 4;
my $copyid						= 8000107;
my $patron_items_out			= 11;
my $patron_overdue_count	= 11;
my $patron_fines				= 20;

# these are not currently tested in the scripts
my $is_renewal					= 0;
my $is_non_cat					= 0;
my $is_hold						= 0;
my $non_cat_type				= 1;
# ---------------------------------------------------------------------




my $bsconfig = shift;
my $script = shift;
my $path;

($path, $script) = ($script =~ m#(/.*/)(.*)#);

osrf_connect($bsconfig);

my $evt				= 'environment';
my $fatal_events	= 'result.fatalEvents';
my $info_events	= 'result.infoEvents';
my $events			= 'result.events';

my $runner = load_runner();
$runner->add_path($path);



# ---------------------------------------------------------------------
# Run the script
# ---------------------------------------------------------------------
print "\nLoading script: $script\n";
print "\n" . '-'x70 . "\n";

$runner->load($script);
$runner->run or die "Script died: $@";



# ---------------------------------------------------------------------
# Print out any events that occurred
# ---------------------------------------------------------------------
print "\n" . '-'x70 . "\n";

show_events( 'events', $runner->retrieve($events));
show_events( 'fatal_events', $runner->retrieve($fatal_events));
show_events( 'info_events', $runner->retrieve($info_events));


sub show_events {
	my $t = shift;
	my $e = shift;
	my @e;

	if($e and @e = split(/,/, $e)) {
		print "$t : $_\n" for @e;

	} else {
		print "No $t occurred\n";
	} 
}

print "\n";



# ---------------------------------------------------------------------
# Fetch data and build the script runner
# ---------------------------------------------------------------------

sub load_runner {

	my( $patron, $copy, $org, $e );


	($patron, $e) = $apputils->fetch_user($patronid);
	oils_event_die($e);

	($org, $e) = $apputils->fetch_org_unit($patron->home_ou);	
	oils_event_die($e);

	$patron->home_ou($org);

	($copy, $e) = $apputils->fetch_copy($copyid);
	oils_event_die($e);

	my $groups = $apputils->fetch_permission_group_tree();
	$patron->profile( _get_patron_profile($patron, $groups));

	my $cp_stats = $apputils->fetch_copy_statuses();
	$copy->status( _get_copy_status($copy, $cp_stats) );

	my $runner = OpenILS::Utils::ScriptRunner->new;
	
	$runner->insert( "$evt.patronOverdueCount", $patron_overdue_count );
	$runner->insert( "$evt.patronItemsOut", $patron_items_out );
	$runner->insert( "$evt.patronFines", $patron_fines );
	$runner->insert( "$evt.isRenewal", $is_renewal );
	$runner->insert( "$evt.isNonCat", $is_non_cat );
	$runner->insert( "$evt.isHold", $is_hold );
	$runner->insert( "$evt.nonCatType", $non_cat_type );
	$runner->insert( "$evt.patron", $patron );
	$runner->insert( "$evt.copy", $copy );
	$runner->insert( $fatal_events, [] );
	$runner->insert( $info_events, [] );
	$runner->insert( $events, [] );

	# ---------------------------------------------------------------------
	# Override the default log functions for convenience
	# ---------------------------------------------------------------------
	$runner->insert(log_activity	=> sub { print "@_\n"; return 1;} );
	$runner->insert(log_error		=> sub { print "@_\n"; return 1;} );
	$runner->insert(log_warn		=> sub { print "@_\n"; return 1;} );
	$runner->insert(log_info		=> sub { print "@_\n"; return 1;} );
	$runner->insert(log_debug		=> sub { print "@_\n"; return 1;} );
	$runner->insert(log_internal	=> sub { print "@_\n"; return 1;} );
	
	return $runner;
}


# ---------------------------------------------------------------------
# Utility code for fleshing objects
# ---------------------------------------------------------------------
sub _get_patron_profile { 
	my( $patron, $group_tree ) = @_;
	return $group_tree if ($group_tree->id eq $patron->profile);
	return undef unless ($group_tree->children);
	for my $child (@{$group_tree->children}) {
		my $ret = _get_patron_profile( $patron, $child );
		return $ret if $ret;
	}
	return undef;
}


sub _get_copy_status {
	my( $copy, $cstatus ) = @_;
	my $s = undef;
	for my $status (@$cstatus) {
		$s = $status if( $status->id eq $copy->status )
	}
	return $s;
}


		
