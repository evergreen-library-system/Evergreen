package OpenILS::Application::Actor::ClosedDates;
use base 'OpenSRF::Application';
use strict; use warnings;
use OpenSRF::EX qw(:try);
use OpenILS::Utils::Editor q/:funcs/;

sub initialize { return 1; }

__PACKAGE__->register_method( 
	method => 'fetch_dates',
	api_name	=> 'open-ils.actor.org_unit.closed.retrieve.all',
	signature	=> q/
		Retrieves a list of closed date object IDs
	/
);

sub fetch_dates {
	my( $self, $conn, $auth, $args ) = @_;

	my $e = new_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;

	my $org = $$args{orgid} || $e->requestor->ws_ou;
	my @date = localtime;
	my $start = $$args{start_date} ||  #default to today 
		($date[5] + 1900) .'-'. ($date[4] + 1) .'-'. $date[3];
	my $end = $$args{end_date} || '3000-01-01'; # Y3K, here I come..

	return $e->search_actor_org_unit_closed_date( 
		{ 
			close_start => { ">=" => $start }, 
			close_end => { "<=" => $end }
		}, {idlist => 1} );
}

__PACKAGE__->register_method( 
	method => 'fetch_date',
	api_name	=> 'open-ils.actor.org_unit.closed.retrieve',
	signature	=> q/
		Retrieves a single date object
	/
);

sub fetch_date {
	my( $self, $conn, $auth, $id ) = @_;
	my $e = new_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;
	my $date = $e->retrieve_actor_org_unit_closed_date($id) or return $e->event;
	return $date;
}


__PACKAGE__->register_method( 
	method => 'create_date',
	api_name	=> 'open-ils.actor.org_unit.closed.create',
	signature	=> q/
		Creates a new org closed data
	/
);

sub create_date {
	my( $self, $conn, $auth, $date ) = @_;

	my $e = new_editor(authtoken=>$auth, xact =>1);
	return $e->event unless $e->checkauth;
	
	return $e->event unless $e->allowed( # rely on the editor perm eventually
		'actor.org_unit.closed_date.create', $date->org_unit);

	$e->create_actor_org_unit_closed_date($date) or return $e->event;

	my $newobj = $e->retrieve_actor_org_unit_closed_date($date->id)
		or return $e->event;

	$e->commit;
	return $newobj;
}




1;
