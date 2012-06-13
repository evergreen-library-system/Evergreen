package OpenILS::Application::Circ::Transit;
use base 'OpenILS::Application';
use strict; use warnings;
use OpenSRF::EX qw(:try);
use Data::Dumper;
use OpenSRF::Utils;
use OpenSRF::Utils::Cache;
use Digest::MD5 qw(md5_hex);
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Application::AppUtils;
use OpenILS::Application::Circ::Holds;
use OpenSRF::Utils::Logger qw(:logger);
use OpenSRF::AppSession;
use OpenILS::Const qw/:const/;

my $U							= "OpenILS::Application::AppUtils";
my $holdcode				= "OpenILS::Application::Circ::Holds";
$Data::Dumper::Indent	= 0;



__PACKAGE__->register_method(
	method	=> "copy_transit_receive",
	api_name	=> "open-ils.circ.copy_transit.receive",
	notes		=> q/
		Closes out a copy transit
		Requestor needs the COPY_TRANSIT_RECEIVE permission
		@param authtoken The login session key
		@param params An object of named params including
			copyid - the id of the copy in quest
			barcode - the barcode of the copy in question 
				If copyid is not sent, this is used.
		@return A ROUTE_ITEM if the copy is destined for a different location.
			A SUCCESS event on success. Other events on error.
	/);

sub copy_transit_receive {
	my( $self, $client, $authtoken, $params ) = @_;
	my %params = %$params;
	my( $evt, $copy, $requestor );
	($requestor, $evt) = $U->checksesperm($authtoken, 'COPY_TRANSIT_RECEIVE');
	return $evt if $evt;
	($copy, $evt) = $U->fetch_copy($params{copyid});
	($copy, $evt) = $U->fetch_copy_by_barcode($params{barcode}) unless $copy;
	return $evt if $evt;
	my $session = $U->start_db_session();
	$U->set_audit_info($session, $authtoken, $requestor->id, $requestor->wsid);
	$evt = transit_receive( $self, $copy, $requestor, $session );
	$U->commit_db_session($session) if $U->event_equals($evt,'SUCCESS');
	return $evt;
}

# ------------------------------------------------------------------------------
# If the transit destination is different than the requestor's lib,
# a ROUTE_TO event is returned with the org set.
# If 
# ------------------------------------------------------------------------------
sub transit_receive {
	my ( $class, $copy, $requestor, $session ) = @_;
	$U->logmark;

	my( $transit, $evt );
	my $copyid = $copy->id;

	my $status_name = $U->copy_status_to_name($copy->status);
	$logger->debug("Attempting transit receive on copy $copyid. Copy status is $status_name");

	# fetch the transit
	($transit, $evt) = $U->fetch_open_transit_by_copy($copyid);
	return $evt if $evt;

	if( $transit->dest != $requestor->home_ou ) {
		$logger->activity("Fowarding transit on copy which is destined ".
			"for a different location. copy=$copyid,current ".
			"location=".$requestor->home_ou.",destination location=".$transit->dest);

		return OpenILS::Event->new('ROUTE_ITEM', org => $transit->dest );
	}

	# The transit is received, set the receive time
	$transit->dest_recv_time('now');
	my $r = $session->request(
		'open-ils.storage.direct.action.transit_copy.update', $transit )->gather(1);
	return $U->DB_UPDATE_FAILED($transit) unless $r;

	my $ishold	= 0;
	my ($ht)		= $U->fetch_hold_transit( $transit->id );
	if($ht) {
		$logger->info("Hold transit found in transit receive...");
		$ishold	= 1;
	}

	$logger->info("Recovering original copy status in transit: ".$transit->copy_status);
	$copy->status( $transit->copy_status );
	return $evt if ( $evt = 
		$U->update_copy( copy => $copy, editor => $requestor->id, session => $session ));

	return OpenILS::Event->new('SUCCESS', ishold => $ishold, 
		payload => { transit => $transit, holdtransit => $ht } );
}





__PACKAGE__->register_method(
	method	=> "copy_transit_create",
	api_name	=> "open-ils.circ.copy_transit.create",
	notes		=> q/
		Creates a new copy transit.  Requestor must have the 
		CREATE_COPY_TRANSIT permission.
		@param authtoken The login session key
		@param params A param object containing the following keys:
			copyid		- the copy id
			destination	- the id of the org destination.  If not defined,
				defaults to the copy's circ_lib
		@return SUCCESS event on success, other event on error
	/);

sub copy_transit_create {

	my( $self, $client, $authtoken, $params ) = @_;
	my %params = %$params;

	my( $requestor, $evt ) = 
		$U->checksesperm( $authtoken, 'CREATE_COPY_TRANSIT' );
	return $evt if $evt;

	my $copy;
	($copy,$evt) = $U->fetch_copy($params{copyid});
	return $evt if $evt;

	my $session		= $params{session} || $U->start_db_session();
	my $source		= $requestor->home_ou;
	my $dest			= $params{destination} || $copy->circ_lib;
	my $transit		= Fieldmapper::action::transit_copy->new;
	$U->set_audit_info($session, $authtoken, $requestor->id, $requestor->wsid);

	$logger->activity("User ". $requestor->id ." creating a ".
		" new copy transit for copy ".$copy->id." to org $dest");

	$transit->source($source);
	$transit->dest($dest);
	$transit->target_copy($copy->id);
	$transit->source_send_time("now");
	$transit->copy_status($copy->status);
	
	$logger->debug("Creating new copy_transit in DB");

	my $s = $session->request(
		"open-ils.storage.direct.action.transit_copy.create", $transit )->gather(1);
	return $U->DB_UPDATE_FAILED($transit) unless $s;
	
	my $stat = $U->copy_status_from_name('in transit');

	$copy->status($stat->id); 
	return $evt if ($evt = $U->update_copy(
		copy => $copy, editor => $requestor->id, session => $session ));

	$U->commit_db_session($session) unless $params{session};

	return OpenILS::Event->new('SUCCESS', 
		payload => { copy => $copy, transit => $transit } );
}


__PACKAGE__->register_method(
	method => 'abort_transit',
	api_name	=> 'open-ils.circ.transit.abort',
	signature	=> q/
		Deletes a cleans up a transit
	/
);

sub abort_transit {
	my( $self, $conn, $authtoken, $params ) = @_;

	my $copyid		= $$params{copyid};
	my $barcode		= $$params{barcode};
	my $transitid	= $$params{transitid};

	my $copy;
	my $transit;
	my $evt;

	my $e = new_editor(xact => 1, authtoken => $authtoken);
	return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('ABORT_TRANSIT');

	# ---------------------------------------------------------------------
	# Find the related copy and/or transit based on whatever data we have
	if( $barcode ) {
		$copy = $e->search_asset_copy({barcode=>$barcode, deleted => 'f'})->[0];
		return $e->event unless $copy;

	} elsif( $copyid ) {
		$copy = $e->retrieve_asset_copy($copyid) or return $e->event;
	}

	if( $transitid ) {
		$transit = $e->retrieve_action_transit_copy($transitid)
			or return $e->event;

	} elsif( $copy ) {

		$transit = $e->search_action_transit_copy(
			{ target_copy => $copy->id, dest_recv_time => undef })->[0];
		return $e->event unless $transit;
	}

	if($transit and !$copy) {
		$copy = $e->retrieve_asset_copy($transit->target_copy)
			or return $e->event;
	}
	# ---------------------------------------------------------------------

	return __abort_transit( $e, $transit, $copy );
}



sub __abort_transit {

	my( $e, $transit, $copy, $no_reset_hold, $no_commit ) = @_;

	my $evt;
	my $hold;

	if( ($transit->copy_status == OILS_COPY_STATUS_LOST and !$e->allowed('ABORT_TRANSIT_ON_LOST')) or
		($transit->copy_status == OILS_COPY_STATUS_MISSING and !$e->allowed('ABORT_TRANSIT_ON_MISSING')) ) {
		$e->rollback;
		return OpenILS::Event->new('TRANSIT_ABORT_NOT_ALLOWED', copy_status => $transit->copy_status);
	}


	if( $transit->dest != $e->requestor->ws_ou 
		and $transit->source != $e->requestor->ws_ou ) {
		return $e->die_event unless $e->allowed('ABORT_REMOTE_TRANSIT', $e->requestor->ws_ou);
	}

	# recover the copy status
	$copy->status( $transit->copy_status );
	$copy->editor( $e->requestor->id );
	$copy->edit_date('now');

	my $holdtransit = $e->retrieve_action_hold_transit_copy($transit->id);

	if( $holdtransit ) {
		$logger->info("setting copy to reshelving on hold transit abort");
		$copy->status( OILS_COPY_STATUS_RESHELVING );
	}

	return $e->die_event unless $e->delete_action_transit_copy($transit);
	return $e->die_event unless $e->update_asset_copy($copy);

	$e->commit unless $no_commit;

	# if this is a hold transit, un-capture/un-target the hold
	if($holdtransit and !$no_reset_hold) {
		$hold = $e->retrieve_action_hold_request($holdtransit->hold) 
            or return $e->die_event;
		$evt = $holdcode->_reset_hold( $e->requestor, $hold );
		return $evt if $evt;
	}

	return 1;
}


__PACKAGE__->register_method(
	method		=> 'get_open_copy_transit',
	api_name		=> 'open-ils.circ.open_copy_transit.retrieve',
	signature	=> q/
		Retrieves the open transit object for a given copy
		@param auth The login session key
		@param copyid The id of the copy
		@return Transit object
 /
);

sub get_open_copy_transit {
	my( $self, $conn, $auth, $copyid ) = @_;	
	my $e = new_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('VIEW_USER'); # XXX rely on editor perms
	my $t = $e->search_action_transit_copy(
		{ target_copy => $copyid, dest_recv_time => undef });
	return $e->event unless @$t;
	return $$t[0];
}



__PACKAGE__->register_method(
	method => 'fetch_transit_by_copy',
	api_name => 'open-ils.circ.fetch_transit_by_copy',
);

sub fetch_transit_by_copy {
	my( $self, $conn, $auth, $copyid ) = @_;
	my $e = new_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;
	my $t = $e->search_action_transit_copy(
		{
			target_copy => $copyid,
			dest_recv_time => undef
		}
	)->[0];
	return $e->event unless $t;
	my $ht = $e->retrieve_action_hold_transit_copy($t->id);
	return { atc => $t, ahtc => $ht };
}



__PACKAGE__->register_method(
	method => 'transits_by_lib',
	api_name => 'open-ils.circ.transit.retrieve_by_lib',
);


# start_date and end_date are optional endpoints for the transit creation date
sub transits_by_lib {
	my( $self, $conn, $auth, $orgid, $start_date, $end_date ) = @_;
	my $e = new_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('VIEW_CIRCULATIONS'); # eh.. basically the same permission

    my $order_by = {order_by => { atc => 'source_send_time' }};
    my $search = { dest_recv_time => undef };

    if($end_date) {
        if($start_date) {
            $search->{source_send_time} = {between => [$start_date, $end_date]};
        } else {
            $search->{source_send_time} = {'<=' => $end_date};
        }
    } elsif($start_date) {
        $search->{source_send_time} = {'>=' => $start_date};
    }

    $search->{dest} = $orgid;

	my $tos = $e->search_action_transit_copy([ $search, $order_by ], {idlist=>1});

    delete $$search{dest};
    $search->{source} = $orgid;

	my $froms = $e->search_action_transit_copy([ $search, $order_by ], {idlist=>1});

	return { from => $froms, to => $tos };
}



__PACKAGE__->register_method(
	method => 'fetch_transit',
	api_name => 'open-ils.circ.transit.retrieve',
);
sub fetch_transit {
	my( $self, $conn, $auth, $transid ) = @_;
	my $e = new_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('VIEW_CIRCULATIONS'); # eh.. basically the same permission

	my $ht = $e->retrieve_action_hold_transit_copy($transid);
	return $ht if $ht;

	my $t = $e->retrieve_action_transit_copy($transid)
		or return $e->event;
	return $t;
}

	




1;
