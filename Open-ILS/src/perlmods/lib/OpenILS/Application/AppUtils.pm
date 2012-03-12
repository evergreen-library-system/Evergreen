package OpenILS::Application::AppUtils;
# vim:noet:ts=4
use strict; use warnings;
use OpenILS::Application;
use base qw/OpenILS::Application/;
use OpenSRF::Utils::Cache;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::ModsParser;
use OpenSRF::EX qw(:try);
use OpenILS::Event;
use Data::Dumper;
use OpenILS::Utils::CStoreEditor;
use OpenILS::Const qw/:const/;
use Unicode::Normalize;
use OpenSRF::Utils::SettingsClient;
use UUID::Tiny;
use Encode;

# ---------------------------------------------------------------------------
# Pile of utilty methods used accross applications.
# ---------------------------------------------------------------------------
my $cache_client = "OpenSRF::Utils::Cache";


# ---------------------------------------------------------------------------
# on sucess, returns the created session, on failure throws ERROR exception
# ---------------------------------------------------------------------------
sub start_db_session {

	my $self = shift;
	my $session = OpenSRF::AppSession->connect( "open-ils.storage" );
	my $trans_req = $session->request( "open-ils.storage.transaction.begin" );

	my $trans_resp = $trans_req->recv();
	if(ref($trans_resp) and UNIVERSAL::isa($trans_resp,"Error")) { throw $trans_resp; }
	if( ! $trans_resp->content() ) {
		throw OpenSRF::ERROR 
			("Unable to Begin Transaction with database" );
	}
	$trans_req->finish();

	$logger->debug("Setting global storage session to ".
		"session: " . $session->session_id . " : " . $session->app );

	return $session;
}

sub set_audit_info {
	my $self = shift;
	my $session = shift;
	my $authtoken = shift;
	my $user_id = shift;
	my $ws_id = shift;
	
	my $audit_req = $session->request( "open-ils.storage.set_audit_info", $authtoken, $user_id, $ws_id );
	my $audit_resp = $audit_req->recv();
	$audit_req->finish();
}

my $PERM_QUERY = {
    select => {
        au => [ {
            transform => 'permission.usr_has_perm',
            alias => 'has_perm',
            column => 'id',
            params => []
        } ]
    },
    from => 'au',
    where => {},
};


# returns undef if user has all of the perms provided
# returns the first failed perm on failure
sub check_user_perms {
	my($self, $user_id, $org_id, @perm_types ) = @_;
	$logger->debug("Checking perms with user : $user_id , org: $org_id, @perm_types");

	for my $type (@perm_types) {
	    $PERM_QUERY->{select}->{au}->[0]->{params} = [$type, $org_id];
		$PERM_QUERY->{where}->{id} = $user_id;
		return $type unless $self->is_true(OpenILS::Utils::CStoreEditor->new->json_query($PERM_QUERY)->[0]->{has_perm});
	}
	return undef;
}

# checks the list of user perms.  The first one that fails returns a new
sub check_perms {
	my( $self, $user_id, $org_id, @perm_types ) = @_;
	my $t = $self->check_user_perms( $user_id, $org_id, @perm_types );
	return OpenILS::Event->new('PERM_FAILURE', ilsperm => $t, ilspermloc => $org_id ) if $t;
	return undef;
}



# ---------------------------------------------------------------------------
# commits and destroys the session
# ---------------------------------------------------------------------------
sub commit_db_session {
	my( $self, $session ) = @_;

	my $req = $session->request( "open-ils.storage.transaction.commit" );
	my $resp = $req->recv();

	if(!$resp) {
		throw OpenSRF::EX::ERROR ("Unable to commit db session");
	}

	if(UNIVERSAL::isa($resp,"Error")) { 
		throw $resp ($resp->stringify); 
	}

	if(!$resp->content) {
		throw OpenSRF::EX::ERROR ("Unable to commit db session");
	}

	$session->finish();
	$session->disconnect();
	$session->kill_me();
}

sub rollback_db_session {
	my( $self, $session ) = @_;

	my $req = $session->request("open-ils.storage.transaction.rollback");
	my $resp = $req->recv();
	if(UNIVERSAL::isa($resp,"Error")) { throw $resp;  }

	$session->finish();
	$session->disconnect();
	$session->kill_me();
}


# returns undef it the event is not an ILS event
# returns the event code otherwise
sub event_code {
	my( $self, $evt ) = @_;
	return $evt->{ilsevent} if( ref($evt) eq 'HASH' and defined($evt->{ilsevent})) ;
	return undef;
}

# ---------------------------------------------------------------------------
# Checks to see if a user is logged in.  Returns the user record on success,
# throws an exception on error.
# ---------------------------------------------------------------------------
sub check_user_session {
	my( $self, $user_session ) = @_;

	my $content = $self->simplereq( 
		'open-ils.auth', 
		'open-ils.auth.session.retrieve', $user_session);

    return undef if (!$content) or $self->event_code($content);
	return $content;
}

# generic simple request returning a scalar value
sub simplereq {
	my($self, $service, $method, @params) = @_;
	return $self->simple_scalar_request($service, $method, @params);
}


sub simple_scalar_request {
	my($self, $service, $method, @params) = @_;

	my $session = OpenSRF::AppSession->create( $service );

	my $request = $session->request( $method, @params );

	my $val;
	my $err;
	try  {

		$val = $request->gather(1);	

	} catch Error with {
		$err = shift;
	};

	if( $err ) {
		warn "received error : service=$service : method=$method : params=".Dumper(\@params) . "\n $err";
		throw $err ("Call to $service for method $method \n failed with exception: $err : " );
	}

	return $val;
}

sub build_org_tree {
	my( $self, $orglist ) = @_;

	return $orglist unless ref $orglist; 
    return $$orglist[0] if @$orglist == 1;

	my @list = sort { 
		$a->ou_type <=> $b->ou_type ||
		$a->name cmp $b->name } @$orglist;

	for my $org (@list) {

		next unless ($org);
        next if (!defined($org->parent_ou) || $org->parent_ou eq "");

		my ($parent) = grep { $_->id == $org->parent_ou } @list;
		next unless $parent;
		$parent->children([]) unless defined($parent->children); 
		push( @{$parent->children}, $org );
	}

	return $list[0];
}

sub fetch_closed_date {
	my( $self, $cd ) = @_;
	my $evt;
	
	$logger->debug("Fetching closed_date $cd from cstore");

	my $cd_obj = $self->simplereq(
		'open-ils.cstore',
		'open-ils.cstore.direct.actor.org_unit.closed_date.retrieve', $cd );

	if(!$cd_obj) {
		$logger->info("closed_date $cd not found in the db");
		$evt = OpenILS::Event->new('ACTOR_USER_NOT_FOUND');
	}

	return ($cd_obj, $evt);
}

sub fetch_user {
	my( $self, $userid ) = @_;
	my( $user, $evt );
	
	$logger->debug("Fetching user $userid from cstore");

	$user = $self->simplereq(
		'open-ils.cstore',
		'open-ils.cstore.direct.actor.user.retrieve', $userid );

	if(!$user) {
		$logger->info("User $userid not found in the db");
		$evt = OpenILS::Event->new('ACTOR_USER_NOT_FOUND');
	}

	return ($user, $evt);
}

sub checkses {
	my( $self, $session ) = @_;
	my $user = $self->check_user_session($session) or 
        return (undef, OpenILS::Event->new('NO_SESSION'));
    return ($user);
}


# verifiese the session and checks the permissions agains the
# session user and the user's home_ou as the org id
sub checksesperm {
	my( $self, $session, @perms ) = @_;
	my $user; my $evt; my $e; 
	$logger->debug("Checking user session $session and perms @perms");
	($user, $evt) = $self->checkses($session);
	return (undef, $evt) if $evt;
	$evt = $self->check_perms($user->id, $user->home_ou, @perms);
	return ($user, $evt);
}


sub checkrequestor {
	my( $self, $staffobj, $userid, @perms ) = @_;
	my $user; my $evt;
	$userid = $staffobj->id unless defined $userid;

	$logger->debug("checkrequestor(): requestor => " . $staffobj->id . ", target => $userid");

	if( $userid ne $staffobj->id ) {
		($user, $evt) = $self->fetch_user($userid);
		return (undef, $evt) if $evt;
		$evt = $self->check_perms( $staffobj->id, $user->home_ou, @perms );

	} else {
		$user = $staffobj;
	}

	return ($user, $evt);
}

sub checkses_requestor {
	my( $self, $authtoken, $targetid, @perms ) = @_;
	my( $requestor, $target, $evt );

	($requestor, $evt) = $self->checkses($authtoken);
	return (undef, undef, $evt) if $evt;

	($target, $evt) = $self->checkrequestor( $requestor, $targetid, @perms );
	return( $requestor, $target, $evt);
}

sub fetch_copy {
	my( $self, $copyid ) = @_;
	my( $copy, $evt );

	$logger->debug("Fetching copy $copyid from cstore");

	$copy = $self->simplereq(
		'open-ils.cstore',
		'open-ils.cstore.direct.asset.copy.retrieve', $copyid );

	if(!$copy) { $evt = OpenILS::Event->new('ASSET_COPY_NOT_FOUND'); }

	return( $copy, $evt );
}


# retrieves a circ object by id
sub fetch_circulation {
	my( $self, $circid ) = @_;
	my $circ; my $evt;
	
	$logger->debug("Fetching circ $circid from cstore");

	$circ = $self->simplereq(
		'open-ils.cstore',
		"open-ils.cstore.direct.action.circulation.retrieve", $circid );

	if(!$circ) {
		$evt = OpenILS::Event->new('ACTION_CIRCULATION_NOT_FOUND', circid => $circid );
	}

	return ( $circ, $evt );
}

sub fetch_record_by_copy {
	my( $self, $copyid ) = @_;
	my( $record, $evt );

	$logger->debug("Fetching record by copy $copyid from cstore");

	$record = $self->simplereq(
		'open-ils.cstore',
		'open-ils.cstore.direct.asset.copy.retrieve', $copyid,
		{ flesh => 3,
		  flesh_fields => {	bre => [ 'fixed_fields' ],
					acn => [ 'record' ],
					acp => [ 'call_number' ],
				  }
		}
	);

	if(!$record) {
		$evt = OpenILS::Event->new('BIBLIO_RECORD_ENTRY_NOT_FOUND');
	} else {
		$record = $record->call_number->record;
	}

	return ($record, $evt);
}

# turns a record object into an mvr (mods) object
sub record_to_mvr {
	my( $self, $record ) = @_;
	return undef unless $record and $record->marc;
	my $u = OpenILS::Utils::ModsParser->new();
	$u->start_mods_batch( $record->marc );
	my $mods = $u->finish_mods_batch();
	$mods->doc_id($record->id);
   $mods->tcn($record->tcn_value);
	return $mods;
}

sub fetch_hold {
	my( $self, $holdid ) = @_;
	my( $hold, $evt );

	$logger->debug("Fetching hold $holdid from cstore");

	$hold = $self->simplereq(
		'open-ils.cstore',
		'open-ils.cstore.direct.action.hold_request.retrieve', $holdid);

	$evt = OpenILS::Event->new('ACTION_HOLD_REQUEST_NOT_FOUND', holdid => $holdid) unless $hold;

	return ($hold, $evt);
}


sub fetch_hold_transit_by_hold {
	my( $self, $holdid ) = @_;
	my( $transit, $evt );

	$logger->debug("Fetching transit by hold $holdid from cstore");

	$transit = $self->simplereq(
		'open-ils.cstore',
		'open-ils.cstore.direct.action.hold_transit_copy.search', { hold => $holdid } );

	$evt = OpenILS::Event->new('ACTION_HOLD_TRANSIT_COPY_NOT_FOUND', holdid => $holdid) unless $transit;

	return ($transit, $evt );
}

# fetches the captured, but not fulfilled hold attached to a given copy
sub fetch_open_hold_by_copy {
	my( $self, $copyid ) = @_;
	$logger->debug("Searching for active hold for copy $copyid");
	my( $hold, $evt );

	$hold = $self->cstorereq(
		'open-ils.cstore.direct.action.hold_request.search',
		{ 
			current_copy		=> $copyid , 
			capture_time		=> { "!=" => undef }, 
			fulfillment_time	=> undef,
			cancel_time			=> undef,
		} );

	$evt = OpenILS::Event->new('ACTION_HOLD_REQUEST_NOT_FOUND', copyid => $copyid) unless $hold;
	return ($hold, $evt);
}

sub fetch_hold_transit {
	my( $self, $transid ) = @_;
	my( $htransit, $evt );
	$logger->debug("Fetching hold transit with hold id $transid");
	$htransit = $self->cstorereq(
		'open-ils.cstore.direct.action.hold_transit_copy.retrieve', $transid );
	$evt = OpenILS::Event->new('ACTION_HOLD_TRANSIT_COPY_NOT_FOUND', id => $transid) unless $htransit;
	return ($htransit, $evt);
}

sub fetch_copy_by_barcode {
	my( $self, $barcode ) = @_;
	my( $copy, $evt );

	$logger->debug("Fetching copy by barcode $barcode from cstore");

	$copy = $self->simplereq( 'open-ils.cstore',
		'open-ils.cstore.direct.asset.copy.search', { barcode => $barcode, deleted => 'f'} );
		#'open-ils.storage.direct.asset.copy.search.barcode', $barcode );

	$evt = OpenILS::Event->new('ASSET_COPY_NOT_FOUND', barcode => $barcode) unless $copy;

	return ($copy, $evt);
}

sub fetch_open_billable_transaction {
	my( $self, $transid ) = @_;
	my( $transaction, $evt );

	$logger->debug("Fetching open billable transaction $transid from cstore");

	$transaction = $self->simplereq(
		'open-ils.cstore',
		'open-ils.cstore.direct.money.open_billable_transaction_summary.retrieve',  $transid);

	$evt = OpenILS::Event->new(
		'MONEY_OPEN_BILLABLE_TRANSACTION_SUMMARY_NOT_FOUND', transid => $transid ) unless $transaction;

	return ($transaction, $evt);
}



my %buckets;
$buckets{'biblio'} = 'biblio_record_entry_bucket';
$buckets{'callnumber'} = 'call_number_bucket';
$buckets{'copy'} = 'copy_bucket';
$buckets{'user'} = 'user_bucket';

sub fetch_container {
	my( $self, $id, $type ) = @_;
	my( $bucket, $evt );

	$logger->debug("Fetching container $id with type $type");

	my $e = 'CONTAINER_CALL_NUMBER_BUCKET_NOT_FOUND';
	$e = 'CONTAINER_BIBLIO_RECORD_ENTRY_BUCKET_NOT_FOUND' if $type eq 'biblio';
	$e = 'CONTAINER_USER_BUCKET_NOT_FOUND' if $type eq 'user';
	$e = 'CONTAINER_COPY_BUCKET_NOT_FOUND' if $type eq 'copy';

	my $meth = $buckets{$type};
	$bucket = $self->simplereq(
		'open-ils.cstore',
		"open-ils.cstore.direct.container.$meth.retrieve", $id );

	$evt = OpenILS::Event->new(
		$e, container => $id, container_type => $type ) unless $bucket;

	return ($bucket, $evt);
}


sub fetch_container_e {
	my( $self, $editor, $id, $type ) = @_;

	my( $bucket, $evt );
	$bucket = $editor->retrieve_container_copy_bucket($id) if $type eq 'copy';
	$bucket = $editor->retrieve_container_call_number_bucket($id) if $type eq 'callnumber';
	$bucket = $editor->retrieve_container_biblio_record_entry_bucket($id) if $type eq 'biblio';
	$bucket = $editor->retrieve_container_user_bucket($id) if $type eq 'user';

	$evt = $editor->event unless $bucket;
	return ($bucket, $evt);
}

sub fetch_container_item_e {
	my( $self, $editor, $id, $type ) = @_;

	my( $bucket, $evt );
	$bucket = $editor->retrieve_container_copy_bucket_item($id) if $type eq 'copy';
	$bucket = $editor->retrieve_container_call_number_bucket_item($id) if $type eq 'callnumber';
	$bucket = $editor->retrieve_container_biblio_record_entry_bucket_item($id) if $type eq 'biblio';
	$bucket = $editor->retrieve_container_user_bucket_item($id) if $type eq 'user';

	$evt = $editor->event unless $bucket;
	return ($bucket, $evt);
}





sub fetch_container_item {
	my( $self, $id, $type ) = @_;
	my( $bucket, $evt );

	$logger->debug("Fetching container item $id with type $type");

	my $meth = $buckets{$type} . "_item";

	$bucket = $self->simplereq(
		'open-ils.cstore',
		"open-ils.cstore.direct.container.$meth.retrieve", $id );


	my $e = 'CONTAINER_CALL_NUMBER_BUCKET_ITEM_NOT_FOUND';
	$e = 'CONTAINER_BIBLIO_RECORD_ENTRY_BUCKET_ITEM_NOT_FOUND' if $type eq 'biblio';
	$e = 'CONTAINER_USER_BUCKET_ITEM_NOT_FOUND' if $type eq 'user';
	$e = 'CONTAINER_COPY_BUCKET_ITEM_NOT_FOUND' if $type eq 'copy';

	$evt = OpenILS::Event->new(
		$e, itemid => $id, container_type => $type ) unless $bucket;

	return ($bucket, $evt);
}


sub fetch_patron_standings {
	my $self = shift;
	$logger->debug("Fetching patron standings");	
	return $self->simplereq(
		'open-ils.cstore', 
		'open-ils.cstore.direct.config.standing.search.atomic', { id => { '!=' => undef } });
}


sub fetch_permission_group_tree {
	my $self = shift;
	$logger->debug("Fetching patron profiles");	
	return $self->simplereq(
		'open-ils.actor', 
		'open-ils.actor.groups.tree.retrieve' );
}

sub fetch_permission_group_descendants {
    my( $self, $profile ) = @_;
    my $group_tree = $self->fetch_permission_group_tree();
    my $start_here;
    my @groups;

    # FIXME: okay, so it's not an org tree, but it is compatible
    $self->walk_org_tree($group_tree, sub {
        my $g = shift;
        if ($g->id == $profile) {
            $start_here = $g;
        }
    });

    $self->walk_org_tree($start_here, sub {
        my $g = shift;
        push(@groups,$g->id);
    });

    return \@groups;
}

sub fetch_patron_circ_summary {
	my( $self, $userid ) = @_;
	$logger->debug("Fetching patron summary for $userid");
	my $summary = $self->simplereq(
		'open-ils.storage', 
		"open-ils.storage.action.circulation.patron_summary", $userid );

	if( $summary ) {
		$summary->[0] ||= 0;
		$summary->[1] ||= 0.0;
		return $summary;
	}
	return undef;
}


sub fetch_copy_statuses {
	my( $self ) = @_;
	$logger->debug("Fetching copy statuses");
	return $self->simplereq(
		'open-ils.cstore', 
		'open-ils.cstore.direct.config.copy_status.search.atomic', { id => { '!=' => undef } });
}

sub fetch_copy_location {
	my( $self, $id ) = @_;
	my $evt;
	my $cl = $self->cstorereq(
		'open-ils.cstore.direct.asset.copy_location.retrieve', $id );
	$evt = OpenILS::Event->new('ASSET_COPY_LOCATION_NOT_FOUND') unless $cl;
	return ($cl, $evt);
}

sub fetch_copy_locations {
	my $self = shift; 
	return $self->simplereq(
		'open-ils.cstore', 
		'open-ils.cstore.direct.asset.copy_location.search.atomic', { id => { '!=' => undef } });
}

sub fetch_copy_location_by_name {
	my( $self, $name, $org ) = @_;
	my $evt;
	my $cl = $self->cstorereq(
		'open-ils.cstore.direct.asset.copy_location.search',
			{ name => $name, owning_lib => $org } );
	$evt = OpenILS::Event->new('ASSET_COPY_LOCATION_NOT_FOUND') unless $cl;
	return ($cl, $evt);
}

sub fetch_callnumber {
	my( $self, $id, $flesh, $e ) = @_;

	$e ||= OpenILS::Utils::CStoreEditor->new;

	my $evt = OpenILS::Event->new( 'ASSET_CALL_NUMBER_NOT_FOUND', id => $id );
	return( undef, $evt ) unless $id;

	$logger->debug("Fetching callnumber $id");

    my $cn = $e->retrieve_asset_call_number([
        $id,
        { flesh => $flesh, flesh_fields => { acn => [ 'prefix', 'suffix', 'label_class' ] } },
    ]);

	return ( $cn, $e->event );
}

my %ORG_CACHE; # - these rarely change, so cache them..
sub fetch_org_unit {
	my( $self, $id ) = @_;
	return undef unless $id;
	return $id if( ref($id) eq 'Fieldmapper::actor::org_unit' );
	return $ORG_CACHE{$id} if $ORG_CACHE{$id};
	$logger->debug("Fetching org unit $id");
	my $evt = undef;

	my $org = $self->simplereq(
		'open-ils.cstore', 
		'open-ils.cstore.direct.actor.org_unit.retrieve', $id );
	$evt = OpenILS::Event->new( 'ACTOR_ORG_UNIT_NOT_FOUND', id => $id ) unless $org;
	$ORG_CACHE{$id}  = $org;

	return ($org, $evt);
}

sub fetch_stat_cat {
	my( $self, $type, $id ) = @_;
	my( $cat, $evt );
	$logger->debug("Fetching $type stat cat: $id");
	$cat = $self->simplereq(
		'open-ils.cstore', 
		"open-ils.cstore.direct.$type.stat_cat.retrieve", $id );

	my $e = 'ASSET_STAT_CAT_NOT_FOUND';
	$e = 'ACTOR_STAT_CAT_NOT_FOUND' if $type eq 'actor';

	$evt = OpenILS::Event->new( $e, id => $id ) unless $cat;
	return ( $cat, $evt );
}

sub fetch_stat_cat_entry {
	my( $self, $type, $id ) = @_;
	my( $entry, $evt );
	$logger->debug("Fetching $type stat cat entry: $id");
	$entry = $self->simplereq(
		'open-ils.cstore', 
		"open-ils.cstore.direct.$type.stat_cat_entry.retrieve", $id );

	my $e = 'ASSET_STAT_CAT_ENTRY_NOT_FOUND';
	$e = 'ACTOR_STAT_CAT_ENTRY_NOT_FOUND' if $type eq 'actor';

	$evt = OpenILS::Event->new( $e, id => $id ) unless $entry;
	return ( $entry, $evt );
}

sub fetch_stat_cat_entry_default {
    my( $self, $type, $id ) = @_;
    my( $entry_default, $evt );
    $logger->debug("Fetching $type stat cat entry default: $id");
    $entry_default = $self->simplereq(
        'open-ils.cstore', 
        "open-ils.cstore.direct.$type.stat_cat_entry_default.retrieve", $id );

    my $e = 'ASSET_STAT_CAT_ENTRY_DEFAULT_NOT_FOUND';
    $e = 'ACTOR_STAT_CAT_ENTRY_DEFAULT_NOT_FOUND' if $type eq 'actor';

    $evt = OpenILS::Event->new( $e, id => $id ) unless $entry_default;
    return ( $entry_default, $evt );
}

sub fetch_stat_cat_entry_default_by_stat_cat_and_org {
    my( $self, $type, $stat_cat, $orgId ) = @_;
    my $entry_default;
    $logger->info("### Fetching $type stat cat entry default with stat_cat $stat_cat owned by org_unit $orgId");
    $entry_default = $self->simplereq(
        'open-ils.cstore', 
        "open-ils.cstore.direct.$type.stat_cat_entry_default.search.atomic", 
        { stat_cat => $stat_cat, owner => $orgId } );

    $entry_default = $entry_default->[0];
    return ($entry_default, undef) if $entry_default;

    my $e = 'ASSET_STAT_CAT_ENTRY_DEFAULT_NOT_FOUND';
    $e = 'ACTOR_STAT_CAT_ENTRY_DEFAULT_NOT_FOUND' if $type eq 'actor';
    return (undef, OpenILS::Event->new($e) );
}

sub find_org {
	my( $self, $org_tree, $orgid )  = @_;
    return undef unless $org_tree and defined $orgid;
	return $org_tree if ( $org_tree->id eq $orgid );
	return undef unless ref($org_tree->children);
	for my $c (@{$org_tree->children}) {
		my $o = $self->find_org($c, $orgid);
		return $o if $o;
	}
	return undef;
}

sub fetch_non_cat_type_by_name_and_org {
	my( $self, $name, $orgId ) = @_;
	$logger->debug("Fetching non cat type $name at org $orgId");
	my $types = $self->simplereq(
		'open-ils.cstore',
		'open-ils.cstore.direct.config.non_cataloged_type.search.atomic',
		{ name => $name, owning_lib => $orgId } );
	return ($types->[0], undef) if($types and @$types);
	return (undef, OpenILS::Event->new('CONFIG_NON_CATALOGED_TYPE_NOT_FOUND') );
}

sub fetch_non_cat_type {
	my( $self, $id ) = @_;
	$logger->debug("Fetching non cat type $id");
	my( $type, $evt );
	$type = $self->simplereq(
		'open-ils.cstore', 
		'open-ils.cstore.direct.config.non_cataloged_type.retrieve', $id );
	$evt = OpenILS::Event->new('CONFIG_NON_CATALOGED_TYPE_NOT_FOUND') unless $type;
	return ($type, $evt);
}

sub DB_UPDATE_FAILED { 
	my( $self, $payload ) = @_;
	return OpenILS::Event->new('DATABASE_UPDATE_FAILED', 
		payload => ($payload) ? $payload : undef ); 
}

sub fetch_booking_reservation {
	my( $self, $id ) = @_;
	my( $res, $evt );

	$res = $self->simplereq(
		'open-ils.cstore', 
		'open-ils.cstore.direct.booking.reservation.retrieve', $id
	);

	# simplereq doesn't know how to flesh so ...
	if ($res) {
		$res->usr(
			$self->simplereq(
				'open-ils.cstore', 
				'open-ils.cstore.direct.actor.user.retrieve', $res->usr
			)
		);

		$res->target_resource_type(
			$self->simplereq(
				'open-ils.cstore', 
				'open-ils.cstore.direct.booking.resource_type.retrieve', $res->target_resource_type
			)
		);

		if ($res->current_resource) {
			$res->current_resource(
				$self->simplereq(
					'open-ils.cstore', 
					'open-ils.cstore.direct.booking.resource.retrieve', $res->current_resource
				)
			);

			if ($self->is_true( $res->target_resource_type->catalog_item )) {
				$res->current_resource->catalog_item( $self->fetch_copy_by_barcode( $res->current_resource->barcode ) );
			}
		}

		if ($res->target_resource) {
			$res->target_resource(
				$self->simplereq(
					'open-ils.cstore', 
					'open-ils.cstore.direct.booking.resource.retrieve', $res->target_resource
				)
			);

			if ($self->is_true( $res->target_resource_type->catalog_item )) {
				$res->target_resource->catalog_item( $self->fetch_copy_by_barcode( $res->target_resource->barcode ) );
			}
		}

	} else {
		$evt = OpenILS::Event->new('RESERVATION_NOT_FOUND');
	}

	return ($res, $evt);
}

sub fetch_circ_duration_by_name {
	my( $self, $name ) = @_;
	my( $dur, $evt );
	$dur = $self->simplereq(
		'open-ils.cstore', 
		'open-ils.cstore.direct.config.rules.circ_duration.search.atomic', { name => $name } );
	$dur = $dur->[0];
	$evt = OpenILS::Event->new('CONFIG_RULES_CIRC_DURATION_NOT_FOUND') unless $dur;
	return ($dur, $evt);
}

sub fetch_recurring_fine_by_name {
	my( $self, $name ) = @_;
	my( $obj, $evt );
	$obj = $self->simplereq(
		'open-ils.cstore', 
		'open-ils.cstore.direct.config.rules.recurring_fine.search.atomic', { name => $name } );
	$obj = $obj->[0];
	$evt = OpenILS::Event->new('CONFIG_RULES_RECURRING_FINE_NOT_FOUND') unless $obj;
	return ($obj, $evt);
}

sub fetch_max_fine_by_name {
	my( $self, $name ) = @_;
	my( $obj, $evt );
	$obj = $self->simplereq(
		'open-ils.cstore', 
		'open-ils.cstore.direct.config.rules.max_fine.search.atomic', { name => $name } );
	$obj = $obj->[0];
	$evt = OpenILS::Event->new('CONFIG_RULES_MAX_FINE_NOT_FOUND') unless $obj;
	return ($obj, $evt);
}

sub fetch_hard_due_date_by_name {
	my( $self, $name ) = @_;
	my( $obj, $evt );
	$obj = $self->simplereq(
		'open-ils.cstore', 
		'open-ils.cstore.direct.config.hard_due_date.search.atomic', { name => $name } );
	$obj = $obj->[0];
	$evt = OpenILS::Event->new('CONFIG_RULES_HARD_DUE_DATE_NOT_FOUND') unless $obj;
	return ($obj, $evt);
}

sub storagereq {
	my( $self, $method, @params ) = @_;
	return $self->simplereq(
		'open-ils.storage', $method, @params );
}

sub storagereq_xact {
	my($self, $method, @params) = @_;
	my $ses = $self->start_db_session();
	my $val = $ses->request($method, @params)->gather(1);
	$self->rollback_db_session($ses);
    return $val;
}

sub cstorereq {
	my( $self, $method, @params ) = @_;
	return $self->simplereq(
		'open-ils.cstore', $method, @params );
}

sub event_equals {
	my( $self, $e, $name ) =  @_;
	if( $e and ref($e) eq 'HASH' and 
		defined($e->{textcode}) and $e->{textcode} eq $name ) {
		return 1 ;
	}
	return 0;
}

sub logmark {
	my( undef, $f, $l ) = caller(0);
	my( undef, undef, undef, $s ) = caller(1);
	$s =~ s/.*:://g;
	$f =~ s/.*\///g;
	$logger->debug("LOGMARK: $f:$l:$s");
}

# takes a copy id 
sub fetch_open_circulation {
	my( $self, $cid ) = @_;
	$self->logmark;

	my $e = OpenILS::Utils::CStoreEditor->new;
    my $circ = $e->search_action_circulation({
        target_copy => $cid, 
        stop_fines_time => undef, 
        checkin_time => undef
    })->[0];
    
    return ($circ, $e->event);
}

my $copy_statuses;
sub copy_status_from_name {
	my( $self, $name ) = @_;
	$copy_statuses = $self->fetch_copy_statuses unless $copy_statuses;
	for my $status (@$copy_statuses) { 
		return $status if( $status->name =~ /$name/i );
	}
	return undef;
}

sub copy_status_to_name {
	my( $self, $sid ) = @_;
	$copy_statuses = $self->fetch_copy_statuses unless $copy_statuses;
	for my $status (@$copy_statuses) { 
		return $status->name if( $status->id == $sid );
	}
	return undef;
}


sub copy_status {
	my( $self, $arg ) = @_;
	return $arg if ref $arg;
	$copy_statuses = $self->fetch_copy_statuses unless $copy_statuses;
	my ($stat) = grep { $_->id == $arg } @$copy_statuses;
	return $stat;
}

sub fetch_open_transit_by_copy {
	my( $self, $copyid ) = @_;
	my($transit, $evt);
	$transit = $self->cstorereq(
		'open-ils.cstore.direct.action.transit_copy.search',
		{ target_copy => $copyid, dest_recv_time => undef });
	$evt = OpenILS::Event->new('ACTION_TRANSIT_COPY_NOT_FOUND') unless $transit;
	return ($transit, $evt);
}

sub unflesh_copy {
	my( $self, $copy ) = @_;
	return undef unless $copy;
	$copy->status( $copy->status->id ) if ref($copy->status);
	$copy->location( $copy->location->id ) if ref($copy->location);
	$copy->circ_lib( $copy->circ_lib->id ) if ref($copy->circ_lib);
	return $copy;
}

sub unflesh_reservation {
	my( $self, $reservation ) = @_;
	return undef unless $reservation;
	$reservation->usr( $reservation->usr->id ) if ref($reservation->usr);
	$reservation->target_resource_type( $reservation->target_resource_type->id ) if ref($reservation->target_resource_type);
	$reservation->target_resource( $reservation->target_resource->id ) if ref($reservation->target_resource);
	$reservation->current_resource( $reservation->current_resource->id ) if ref($reservation->current_resource);
	return $reservation;
}

# un-fleshes a copy and updates it in the DB
# returns a DB_UPDATE_FAILED event on error
# returns undef on success
sub update_copy {
	my( $self, %params ) = @_;

	my $copy		= $params{copy}	|| die "update_copy(): copy required";
	my $editor	= $params{editor} || die "update_copy(): copy editor required";
	my $session = $params{session};

	$logger->debug("Updating copy in the database: " . $copy->id);

	$self->unflesh_copy($copy);
	$copy->editor( $editor );
	$copy->edit_date( 'now' );

	my $s;
	my $meth = 'open-ils.storage.direct.asset.copy.update';

	$s = $session->request( $meth, $copy )->gather(1) if $session;
	$s = $self->storagereq( $meth, $copy ) unless $session;

	$logger->debug("Update of copy ".$copy->id." returned: $s");

	return $self->DB_UPDATE_FAILED($copy) unless $s;
	return undef;
}

sub update_reservation {
	my( $self, %params ) = @_;

	my $reservation	= $params{reservation}	|| die "update_reservation(): reservation required";
	my $editor		= $params{editor} || die "update_reservation(): copy editor required";
	my $session		= $params{session};

	$logger->debug("Updating copy in the database: " . $reservation->id);

	$self->unflesh_reservation($reservation);

	my $s;
	my $meth = 'open-ils.cstore.direct.booking.reservation.update';

	$s = $session->request( $meth, $reservation )->gather(1) if $session;
	$s = $self->cstorereq( $meth, $reservation ) unless $session;

	$logger->debug("Update of copy ".$reservation->id." returned: $s");

	return $self->DB_UPDATE_FAILED($reservation) unless $s;
	return undef;
}

sub fetch_billable_xact {
	my( $self, $id ) = @_;
	my($xact, $evt);
	$logger->debug("Fetching billable transaction %id");
	$xact = $self->cstorereq(
		'open-ils.cstore.direct.money.billable_transaction.retrieve', $id );
	$evt = OpenILS::Event->new('MONEY_BILLABLE_TRANSACTION_NOT_FOUND') unless $xact;
	return ($xact, $evt);
}

sub fetch_billable_xact_summary {
	my( $self, $id ) = @_;
	my($xact, $evt);
	$logger->debug("Fetching billable transaction summary %id");
	$xact = $self->cstorereq(
		'open-ils.cstore.direct.money.billable_transaction_summary.retrieve', $id );
	$evt = OpenILS::Event->new('MONEY_BILLABLE_TRANSACTION_NOT_FOUND') unless $xact;
	return ($xact, $evt);
}

sub fetch_fleshed_copy {
	my( $self, $id ) = @_;
	my( $copy, $evt );
	$logger->info("Fetching fleshed copy $id");
	$copy = $self->cstorereq(
		"open-ils.cstore.direct.asset.copy.retrieve", $id,
		{ flesh => 1,
		  flesh_fields => { acp => [ qw/ circ_lib location status stat_cat_entries / ] }
		}
	);
	$evt = OpenILS::Event->new('ASSET_COPY_NOT_FOUND', id => $id) unless $copy;
	return ($copy, $evt);
}


# returns the org that owns the callnumber that the copy
# is attached to
sub fetch_copy_owner {
	my( $self, $copyid ) = @_;
	my( $copy, $cn, $evt );
	$logger->debug("Fetching copy owner $copyid");
	($copy, $evt) = $self->fetch_copy($copyid);
	return (undef,$evt) if $evt;
	($cn, $evt) = $self->fetch_callnumber($copy->call_number);
	return (undef,$evt) if $evt;
	return ($cn->owning_lib);
}

sub fetch_copy_note {
	my( $self, $id ) = @_;
	my( $note, $evt );
	$logger->debug("Fetching copy note $id");
	$note = $self->cstorereq(
		'open-ils.cstore.direct.asset.copy_note.retrieve', $id );
	$evt = OpenILS::Event->new('ASSET_COPY_NOTE_NOT_FOUND', id => $id ) unless $note;
	return ($note, $evt);
}

sub fetch_call_numbers_by_title {
	my( $self, $titleid ) = @_;
	$logger->info("Fetching call numbers by title $titleid");
	return $self->cstorereq(
		'open-ils.cstore.direct.asset.call_number.search.atomic', 
		{ record => $titleid, deleted => 'f' });
		#'open-ils.storage.direct.asset.call_number.search.record.atomic', $titleid);
}

sub fetch_copies_by_call_number {
	my( $self, $cnid ) = @_;
	$logger->info("Fetching copies by call number $cnid");
	return $self->cstorereq(
		'open-ils.cstore.direct.asset.copy.search.atomic', { call_number => $cnid, deleted => 'f' } );
		#'open-ils.storage.direct.asset.copy.search.call_number.atomic', $cnid );
}

sub fetch_user_by_barcode {
	my( $self, $bc ) = @_;
	my $cardid = $self->cstorereq(
		'open-ils.cstore.direct.actor.card.id_list', { barcode => $bc } );
	return (undef, OpenILS::Event->new('ACTOR_CARD_NOT_FOUND', barcode => $bc)) unless $cardid;
	my $user = $self->cstorereq(
		'open-ils.cstore.direct.actor.user.search', { card => $cardid } );
	return (undef, OpenILS::Event->new('ACTOR_USER_NOT_FOUND', card => $cardid)) unless $user;
	return ($user);
	
}

sub fetch_bill {
	my( $self, $billid ) = @_;
	$logger->debug("Fetching billing $billid");
	my $bill = $self->cstorereq(
		'open-ils.cstore.direct.money.billing.retrieve', $billid );
	my $evt = OpenILS::Event->new('MONEY_BILLING_NOT_FOUND') unless $bill;
	return($bill, $evt);
}

sub walk_org_tree {
	my( $self, $node, $callback ) = @_;
	return unless $node;
	$callback->($node);
	if( $node->children ) {
		$self->walk_org_tree($_, $callback) for @{$node->children};
	}
}

sub is_true {
	my( $self, $item ) = @_;
	return 1 if $item and $item !~ /^f$/i;
	return 0;
}


sub patientreq {
    my ($self, $client, $service, $method, @params) = @_;
    my ($response, $err);

    my $session = create OpenSRF::AppSession($service);
    my $request = $session->request($method, @params);

    my $spurt = 10;
    my $give_up = time + 1000;

    try {
        while (time < $give_up) {
            $response = $request->recv("timeout" => $spurt);
            last if $request->complete;

            $client->status(new OpenSRF::DomainObject::oilsContinueStatus);
        }
    } catch Error with {
        $err = shift;
    };

    if ($err) {
        warn "received error : service=$service : method=$method : params=".Dumper(\@params) . "\n $err";
        throw $err ("Call to $service for method $method \n failed with exception: $err : " );
    }

    return $response->content;
}

# This logic now lives in storage
sub __patron_money_owed {
	my( $self, $patronid ) = @_;
	my $ses = OpenSRF::AppSession->create('open-ils.storage');
	my $req = $ses->request(
		'open-ils.storage.money.billable_transaction.summary.search',
		{ usr => $patronid, xact_finish => undef } );

	my $total = 0;
	my $data;
	while( $data = $req->recv ) {
		$data = $data->content;
		$total += $data->balance_owed;
	}
	return $total;
}

sub patron_money_owed {
	my( $self, $userid ) = @_;
	my $ses = $self->start_db_session();
	my $val = $ses->request(
		'open-ils.storage.actor.user.total_owed', $userid)->gather(1);
	$self->rollback_db_session($ses);
	return $val;
}

sub patron_total_items_out {
	my( $self, $userid ) = @_;
	my $ses = $self->start_db_session();
	my $val = $ses->request(
		'open-ils.storage.actor.user.total_out', $userid)->gather(1);
	$self->rollback_db_session($ses);
	return $val;
}




#---------------------------------------------------------------------
# Returns  ($summary, $event) 
#---------------------------------------------------------------------
sub fetch_mbts {
	my $self = shift;
	my $id	= shift;
	my $e = shift || OpenILS::Utils::CStoreEditor->new;
	$id = $id->id if ref($id);
    
    my $xact = $e->retrieve_money_billable_transaction_summary($id)
	    or return (undef, $e->event);

    return ($xact);
}


#---------------------------------------------------------------------
# Given a list of money.billable_transaction objects, this creates
# transaction summary objects for each
#--------------------------------------------------------------------
sub make_mbts {
	my $self = shift;
    my $e = shift;
	my @xacts = @_;
	return () if (!@xacts);
    return @{$e->search_money_billable_transaction_summary({id => [ map { $_->id } @xacts ]})};
}
		
		
sub ou_ancestor_setting_value {
    my($self, $org_id, $name, $e) = @_;
    $e = $e || OpenILS::Utils::CStoreEditor->new;
    my $set = $self->ou_ancestor_setting($org_id, $name, $e);
    return $set->{value} if $set;
    return undef;
}


# If an authentication token is provided AND this org unit setting has a
# view_perm, then make sure the user referenced by the auth token has
# that permission.  This means that if you call this method without an
# authtoken param, you can get whatever org unit setting values you want.
# API users beware.
#
# NOTE: If you supply an editor ($e) arg AND an auth token arg, the editor's
# authtoken is checked, but the $auth arg is NOT checked.  To say that another
# way, be sure NOT to pass an editor argument if you want your token checked.
# Otherwise the auth arg is just a flag saying "check the editor".  

sub ou_ancestor_setting {
    my( $self, $orgid, $name, $e, $auth ) = @_;
    $e = $e || OpenILS::Utils::CStoreEditor->new(
        (defined $auth) ? (authtoken => $auth) : ()
    );
    my $coust = $e->retrieve_config_org_unit_setting_type([
        $name, {flesh => 1, flesh_fields => {coust => ['view_perm']}}
    ]);

    if ($auth && $coust && $coust->view_perm) {
        # And you can't have permission if you don't have a valid session.
        return undef if not $e->checkauth;
        # And now that we know you MIGHT have permission, we check it.
        return undef if not $e->allowed($coust->view_perm->code, $orgid);
    }

    my $query = {from => ['actor.org_unit_ancestor_setting', $name, $orgid]};
    my $setting = $e->json_query($query)->[0];
    return undef unless $setting;
    return {org => $setting->{org_unit}, value => OpenSRF::Utils::JSON->JSON2perl($setting->{value})};
}	
		

# returns the ISO8601 string representation of the requested epoch in GMT
sub epoch2ISO8601 {
    my( $self, $epoch ) = @_;
    my ($sec,$min,$hour,$mday,$mon,$year) = gmtime($epoch);
    $year += 1900; $mon += 1;
    my $date = sprintf(
        '%s-%0.2d-%0.2dT%0.2d:%0.2d:%0.2d-00',
        $year, $mon, $mday, $hour, $min, $sec);
    return $date;
}
			
sub find_highest_perm_org {
	my ( $self, $perm, $userid, $start_org, $org_tree ) = @_;
	my $org = $self->find_org($org_tree, $start_org );

	my $lastid = -1;
	while( $org ) {
		last if ($self->check_perms( $userid, $org->id, $perm )); # perm failed
		$lastid = $org->id;
		$org = $self->find_org( $org_tree, $org->parent_ou() );
	}

	return $lastid;
}


# returns the org_unit ID's 
sub user_has_work_perm_at {
    my($self, $e, $perm, $options, $user_id) = @_;
    $options ||= {};
    $user_id = (defined $user_id) ? $user_id : $e->requestor->id;

    my $func = 'permission.usr_has_perm_at';
    $func = $func.'_all' if $$options{descendants};

    my $orgs = $e->json_query({from => [$func, $user_id, $perm]});
    $orgs = [map { $_->{ (keys %$_)[0] } } @$orgs];

    return $orgs unless $$options{objects};

    return $e->search_actor_org_unit({id => $orgs});
}

sub get_user_work_ou_ids {
    my($self, $e, $userid) = @_;
    my $work_orgs = $e->json_query({
        select => {puwoum => ['work_ou']},
        from => 'puwoum',
        where => {usr => $e->requestor->id}});

    return [] unless @$work_orgs;
    my @work_orgs;
    push(@work_orgs, $_->{work_ou}) for @$work_orgs;

    return \@work_orgs;
}


my $org_types;
sub get_org_types {
	my($self, $client) = @_;
	return $org_types if $org_types;
	return $org_types = OpenILS::Utils::CStoreEditor->new->retrieve_all_actor_org_unit_type();
}

my %ORG_TREE;
sub get_org_tree {
	my $self = shift;
	my $locale = shift || '';
	my $cache = OpenSRF::Utils::Cache->new("global", 0);
	my $tree = $ORG_TREE{$locale} || $cache->get_cache("orgtree.$locale");
	return $tree if $tree;

	my $ses = OpenILS::Utils::CStoreEditor->new;
	$ses->session->session_locale($locale);
	$tree = $ses->search_actor_org_unit( 
		[
			{"parent_ou" => undef },
			{
				flesh				=> -1,
				flesh_fields	=> { aou =>  ['children'] },
				order_by			=> { aou => 'name'}
			}
		]
	)->[0];

    $ORG_TREE{$locale} = $tree;
	$cache->put_cache("orgtree.$locale", $tree);
	return $tree;
}

sub get_org_descendants {
	my($self, $org_id, $depth) = @_;

	my $select = {
		transform => 'actor.org_unit_descendants',
		column => 'id',
		result_field => 'id',
	};
	$select->{params} = [$depth] if defined $depth;

	my $org_list = OpenILS::Utils::CStoreEditor->new->json_query({
		select => {aou => [$select]},
        from => 'aou',
		where => {id => $org_id}
	});
	my @orgs;
	push(@orgs, $_->{id}) for @$org_list;
	return \@orgs;
}

sub get_org_ancestors {
	my($self, $org_id, $use_cache) = @_;

    my ($cache, $orgs);

    if ($use_cache) {
        $cache = OpenSRF::Utils::Cache->new("global", 0);
        $orgs = $cache->get_cache("org.ancestors.$org_id");
        return $orgs if $orgs;
    }

	my $org_list = OpenILS::Utils::CStoreEditor->new->json_query({
		select => {
			aou => [{
				transform => 'actor.org_unit_ancestors',
				column => 'id',
				result_field => 'id',
				params => []
			}],
		},
		from => 'aou',
		where => {id => $org_id}
	});

	$orgs = [ map { $_->{id} } @$org_list ];

    $cache->put_cache("org.ancestors.$org_id", $orgs) if $use_cache;
	return $orgs;
}

sub get_org_full_path {
	my($self, $org_id, $depth) = @_;

    my $query = {
        select => {
			aou => [{
				transform => 'actor.org_unit_full_path',
				column => 'id',
				result_field => 'id',
			}],
		},
		from => 'aou',
		where => {id => $org_id}
	};

    $query->{select}->{aou}->[0]->{params} = [$depth] if defined $depth;
	my $org_list = OpenILS::Utils::CStoreEditor->new->json_query($query);
    return [ map {$_->{id}} @$org_list ];
}

# returns the ID of the org unit ancestor at the specified depth
sub org_unit_ancestor_at_depth {
    my($class, $org_id, $depth) = @_;
    my $resp = OpenILS::Utils::CStoreEditor->new->json_query(
        {from => ['actor.org_unit_ancestor_at_depth', $org_id, $depth]})->[0];
    return ($resp) ? $resp->{id} : undef;
}

# returns the user's configured locale as a string.  Defaults to en-US if none is configured.
sub get_user_locale {
	my($self, $user_id, $e) = @_;
	$e ||= OpenILS::Utils::CStoreEditor->new;

	# first, see if the user has an explicit locale set
	my $setting = $e->search_actor_user_setting(
		{usr => $user_id, name => 'global.locale'})->[0];
	return OpenSRF::Utils::JSON->JSON2perl($setting->value) if $setting;

	my $user = $e->retrieve_actor_user($user_id) or return $e->event;
	return $self->get_org_locale($user->home_ou, $e);
}

# returns org locale setting
sub get_org_locale {
	my($self, $org_id, $e) = @_;
	$e ||= OpenILS::Utils::CStoreEditor->new;

	my $locale;
	if(defined $org_id) {
		$locale = $self->ou_ancestor_setting_value($org_id, 'global.default_locale', $e);
		return $locale if $locale;
	}

	# system-wide default
	my $sclient = OpenSRF::Utils::SettingsClient->new;
	$locale = $sclient->config_value('default_locale');
    return $locale if $locale;

	# if nothing else, fallback to locale=cowboy
	return 'en-US';
}


# xml-escape non-ascii characters
sub entityize { 
    my($self, $string, $form) = @_;
	$form ||= "";

	# If we're going to convert non-ASCII characters to XML entities,
	# we had better be dealing with a UTF8 string to begin with
	$string = decode_utf8($string);

	if ($form eq 'D') {
		$string = NFD($string);
	} else {
		$string = NFC($string);
	}

	# Convert raw ampersands to entities
	$string =~ s/&(?!\S+;)/&amp;/gso;

	# Convert Unicode characters to entities
	$string =~ s/([\x{0080}-\x{fffd}])/sprintf('&#x%X;',ord($1))/sgoe;

	return $string;
}

# x0000-x0008 isn't legal in XML documents
# XXX Perhaps this should just go into our standard entityize method
sub strip_ctrl_chars {
	my ($self, $string) = @_;

	$string =~ s/([\x{0000}-\x{0008}])//sgoe; 
	return $string;
}

sub get_copy_price {
	my($self, $e, $copy, $volume) = @_;

	$copy->price(0) if $copy->price and $copy->price < 0;

	return $copy->price if $copy->price and $copy->price > 0;


	my $owner;
	if(ref $volume) {
		if($volume->id == OILS_PRECAT_CALL_NUMBER) {
			$owner = $copy->circ_lib;
		} else {
			$owner = $volume->owning_lib;
		}
	} else {
		if($copy->call_number == OILS_PRECAT_CALL_NUMBER) {
			$owner = $copy->circ_lib;
		} else {
			$owner = $e->retrieve_asset_call_number($copy->call_number)->owning_lib;
		}
	}

	my $default_price = $self->ou_ancestor_setting_value(
		$owner, OILS_SETTING_DEF_ITEM_PRICE, $e) || 0;

	return $default_price unless defined $copy->price;

	# price is 0.  Use the default?
    my $charge_on_0 = $self->ou_ancestor_setting_value(
        $owner, OILS_SETTING_CHARGE_LOST_ON_ZERO, $e) || 0;

	return $default_price if $charge_on_0;
	return 0;
}

# given a transaction ID, this returns the context org_unit for the transaction
sub xact_org {
    my($self, $xact_id, $e) = @_;
    $e ||= OpenILS::Utils::CStoreEditor->new;
    
    my $loc = $e->json_query({
        "select" => {circ => ["circ_lib"]},
        from     => "circ",
        "where"  => {id => $xact_id},
    });

    return $loc->[0]->{circ_lib} if @$loc;

    $loc = $e->json_query({
        "select" => {bresv => ["request_lib"]},
        from     => "bresv",
        "where"  => {id => $xact_id},
    });

    return $loc->[0]->{request_lib} if @$loc;

    $loc = $e->json_query({
        "select" => {mg => ["billing_location"]},
        from     => "mg",
        "where"  => {id => $xact_id},
    });

    return $loc->[0]->{billing_location};
}


sub find_event_def_by_hook {
    my($self, $hook, $context_org, $e) = @_;

    $e ||= OpenILS::Utils::CStoreEditor->new;

    my $orgs = $self->get_org_ancestors($context_org);

    # search from the context org up
    for my $org_id (reverse @$orgs) {

        my $def = $e->search_action_trigger_event_definition(
            {hook => $hook, owner => $org_id})->[0];

        return $def if $def;
    }

    return undef;
}



# If an event_def ID is not provided, use the hook and context org to find the 
# most appropriate event.  create the event, fire it, then return the resulting
# event with fleshed template_output and error_output
sub fire_object_event {
    my($self, $event_def, $hook, $object, $context_org, $granularity, $user_data, $client) = @_;

    my $e = OpenILS::Utils::CStoreEditor->new;
    my $def;

    my $auto_method = "open-ils.trigger.event.autocreate.by_definition";

    if($event_def) {
        $def = $e->retrieve_action_trigger_event_definition($event_def)
            or return $e->event;

        $auto_method .= '.include_inactive';

    } else {

        # find the most appropriate event def depending on context org
        $def = $self->find_event_def_by_hook($hook, $context_org, $e) 
            or return $e->event;
    }

    my $final_resp;

    if($def->group_field) {
        # we have a list of objects
        $object = [$object] unless ref $object eq 'ARRAY';

        my @event_ids;
        $user_data ||= [];
        for my $i (0..$#$object) {
            my $obj = $$object[$i];
            my $udata = $$user_data[$i];
            my $event_id = $self->simplereq(
                'open-ils.trigger', $auto_method, $def->id, $obj, $context_org, $udata);
            push(@event_ids, $event_id);
        }

        $logger->info("EVENTS = " . OpenSRF::Utils::JSON->perl2JSON(\@event_ids));

        my $resp;
        if (not defined $client) {
            $resp = $self->simplereq(
                'open-ils.trigger',
                'open-ils.trigger.event_group.fire',
                \@event_ids);
        } else {
            $resp = $self->patientreq(
                $client,
                "open-ils.trigger", "open-ils.trigger.event_group.fire",
                \@event_ids
            );
        }

        if($resp and $resp->{events} and @{$resp->{events}}) {

            $e->xact_begin;
            $final_resp = $e->retrieve_action_trigger_event([
                $resp->{events}->[0]->id,
                {flesh => 1, flesh_fields => {atev => ['template_output', 'error_output']}}
            ]);
            $e->rollback;
        }

    } else {

        $object = $$object[0] if ref $object eq 'ARRAY';

        my $event_id;
        my $resp;

        if (not defined $client) {
            $event_id = $self->simplereq(
                'open-ils.trigger',
                $auto_method, $def->id, $object, $context_org, $user_data
            );

            $resp = $self->simplereq(
                'open-ils.trigger',
                'open-ils.trigger.event.fire',
                $event_id
            );
        } else {
            $event_id = $self->patientreq(
                $client,
                'open-ils.trigger',
                $auto_method, $def->id, $object, $context_org, $user_data
            );

            $resp = $self->patientreq(
                $client,
                'open-ils.trigger',
                'open-ils.trigger.event.fire',
                $event_id
            );
        }
        
        if($resp and $resp->{event}) {
            $e->xact_begin;
            $final_resp = $e->retrieve_action_trigger_event([
                $resp->{event}->id,
                {flesh => 1, flesh_fields => {atev => ['template_output', 'error_output']}}
            ]);
            $e->rollback;
        }
    }

    return $final_resp;
}


sub create_events_for_hook {
    my($self, $hook, $obj, $org_id, $granularity, $user_data, $wait) = @_;
    my $ses = OpenSRF::AppSession->create('open-ils.trigger');
    my $req = $ses->request('open-ils.trigger.event.autocreate', 
        $hook, $obj, $org_id, $granularity, $user_data);
    return undef unless $wait;
    my $resp = $req->recv;
    return $resp->content if $resp;
}

sub create_uuid_string {
    return create_UUID_as_string();
}

sub create_circ_chain_summary {
    my($class, $e, $circ_id) = @_;
    my $sum = $e->json_query({from => ['action.summarize_circ_chain', $circ_id]})->[0];
    return undef unless $sum;
    my $obj = Fieldmapper::action::circ_chain_summary->new;
    $obj->$_($sum->{$_}) for keys %$sum;
    return $obj;
}


# Returns "mra" attribute key/value pairs for a set of bre's
# Takes a list of bre IDs, returns a hash of hashes,
# {bre_id1 => {key1 => {code => value1, label => label1}, ...}...}
my $ccvm_cache;
sub get_bre_attrs {
    my ($class, $bre_ids, $e) = @_;
    $e = $e || OpenILS::Utils::CStoreEditor->new;

    my $attrs = {};
    return $attrs unless defined $bre_ids;
    $bre_ids = [$bre_ids] unless ref $bre_ids;

    my $mra = $e->json_query({
        select => {
            mra => [
                {
                    column => 'id',
                    alias => 'bre'
                }, {
                    column => 'attrs',
                    transform => 'each',
                    result_field => 'key',
                    alias => 'key'
                },{
                    column => 'attrs',
                    transform => 'each',
                    result_field => 'value',
                    alias => 'value'
                }
            ]
        },
        from => 'mra',
        where => {id => $bre_ids}
    });

    return $attrs unless $mra;

    $ccvm_cache = $ccvm_cache || $e->search_config_coded_value_map({id => {'!=' => undef}});

    for my $id (@$bre_ids) {
        $attrs->{$id} = {};
        for my $mra (grep { $_->{bre} eq $id } @$mra) {
            my $ctype = $mra->{key};
            my $code = $mra->{value};
            $attrs->{$id}->{$ctype} = {code => $code};
            if($code) {
                my ($ccvm) = grep { $_->ctype eq $ctype and $_->code eq $code } @$ccvm_cache;
                $attrs->{$id}->{$ctype}->{label} = $ccvm->value if $ccvm;
            }
        }
    }

    return $attrs;
}

# Shorter version of bib_container_items_via_search() below, only using
# the queryparser record_list filter instead of the container filter.
sub bib_record_list_via_search {
    my ($class, $search_query, $search_args) = @_;

    # First, Use search API to get container items sorted in any way that crad
    # sorters support.
    my $search_result = $class->simplereq(
        "open-ils.search", "open-ils.search.biblio.multiclass.query",
        $search_args, $search_query
    );

    unless ($search_result) {
        # empty result sets won't cause this, but actual errors should.
        $logger->warn("bib_record_list_via_search() got nothing from search");
        return;
    }

    # Throw away other junk from search, keeping only bib IDs.
    return [ map { pop @$_ } @{$search_result->{ids}} ];
}

# 'no_flesh' avoids fleshing the target_biblio_record_entry
sub bib_container_items_via_search {
    my ($class, $container_id, $search_query, $search_args, $no_flesh) = @_;

    # First, Use search API to get container items sorted in any way that crad
    # sorters support.
    my $search_result = $class->simplereq(
        "open-ils.search", "open-ils.search.biblio.multiclass.query",
        $search_args, $search_query
    );
    unless ($search_result) {
        # empty result sets won't cause this, but actual errors should.
        $logger->warn("bib_container_items_via_search() got nothing from search");
        return;
    }

    # Throw away other junk from search, keeping only bib IDs.
    my $id_list = [ map { pop @$_ } @{$search_result->{ids}} ];

    return [] unless @$id_list;

    # Now get the bib container items themselves...
    my $e = new OpenILS::Utils::CStoreEditor;
    unless ($e) {
        $logger->warn("bib_container_items_via_search() couldn't get cstoreeditor");
        return;
    }

    my @flesh_fields = qw/notes/;
    push(@flesh_fields, 'target_biblio_record_entry') unless $no_flesh;

    my $items = $e->search_container_biblio_record_entry_bucket_item([
        {
            "target_biblio_record_entry" => $id_list,
            "bucket" => $container_id
        }, {
            flesh => 1,
            flesh_fields => {"cbrebi" => \@flesh_fields}
        }
    ]);
    unless ($items) {
        $logger->warn(
            "bib_container_items_via_search() couldn't get bucket items: " .
            $e->die_event->{textcode}
        );
        return;
    }

    # ... and put them in the same order that the search API said they
    # should be in.
    my %ordering_hash = map { 
        ($no_flesh) ? $_->target_biblio_record_entry : $_->target_biblio_record_entry->id, 
        $_ 
    } @$items;

    return [map { $ordering_hash{$_} } @$id_list];
}

# returns undef on success, Event on error
sub log_user_activity {
    my ($class, $user_id, $who, $what, $e, $async) = @_;

    my $commit = 0;
    if (!$e) {
        $e = OpenILS::Utils::CStoreEditor->new(xact => 1);
        $commit = 1;
    }

    my $res = $e->json_query({
        from => [
            'actor.insert_usr_activity', 
            $user_id, $who, $what, OpenSRF::AppSession->ingress
        ]
    });

    if ($res) { # call returned OK

        $e->commit   if $commit and @$res;
        $e->rollback if $commit and !@$res;

    } else {
        return $e->die_event;
    }

    return undef;
}

# I hate to put this here exactly, but this code needs to be shared between
# the TPAC's mod_perl module and open-ils.serial.
#
# There is a reason every part of the query *except* those parts dealing
# with scope are moved here from the code's origin in TPAC.  The serials
# use case does *not* want the same scoping logic.
#
# Also, note that for the serials uses case, we may filter in OPAC visible
# status and copy/call_number deletedness, but we don't filter on any
# particular values for serial.item.status or serial.item.date_received.
# Since we're only using this *after* winnowing down the set of issuances
# that copies should be related to, I'm not sure we need any such serial.item
# filters.

sub basic_opac_copy_query {
    ######################################################################
    # Pass a defined value for either $rec_id OR ($iss_id AND $dist_id), #
    # not both.                                                          #
    ######################################################################
    my ($self,$rec_id,$iss_id,$dist_id,$copy_limit,$copy_offset,$staff) = @_;

    return {
        select => {
            acp => ['id', 'barcode', 'circ_lib', 'create_date',
                    'age_protect', 'holdable'],
            acpl => [
                {column => 'name', alias => 'copy_location'},
                {column => 'holdable', alias => 'location_holdable'}
            ],
            ccs => [
                {column => 'name', alias => 'copy_status'},
                {column => 'holdable', alias => 'status_holdable'}
            ],
            acn => [
                {column => 'label', alias => 'call_number_label'},
                {column => 'id', alias => 'call_number'}
            ],
            circ => ['due_date'],
            acnp => [
                {column => 'label', alias => 'call_number_prefix_label'},
                {column => 'id', alias => 'call_number_prefix'}
            ],
            acns => [
                {column => 'label', alias => 'call_number_suffix_label'},
                {column => 'id', alias => 'call_number_suffix'}
            ],
            bmp => [
                {column => 'label', alias => 'part_label'},
            ],
            ($iss_id ? (sitem => ["issuance"]) : ())
        },

        from => {
            acp => {
                ($iss_id ? (
                    sitem => {
                        fkey => 'id',
                        field => 'unit',
                        filter => {issuance => $iss_id},
                        join => {
                            sstr => { }
                        }
                    }
                ) : ()),
                acn => {
                    join => {
                        acnp => { fkey => 'prefix' },
                        acns => { fkey => 'suffix' }
                    },
                    filter => [
                        {deleted => 'f'},
                        ($rec_id ? {record => $rec_id} : ())
                    ],
                },
                circ => { # If the copy is circulating, retrieve the open circ
                    type => 'left',
                    filter => {checkin_time => undef}
                },
                acpl => {
                    ($staff ? () : (filter => { opac_visible => 't' }))
                },
                ccs => {
                    ($staff ? () : (filter => { opac_visible => 't' }))
                },
                aou => {},
                acpm => {
                    type => 'left',
                    join => {
                        bmp => { type => 'left' }
                    }
                }
            }
        },

        where => {
            '+acp' => {
                deleted => 'f',
                ($staff ? () : (opac_visible => 't'))
            },
            ($dist_id ? ( '+sstr' => { distribution => $dist_id } ) : ()),
            ($staff ? () : ( '+aou' => { opac_visible => 't' } ))
        },

        order_by => [
            {class => 'aou', field => 'name'},
            {class => 'acn', field => 'label'}
        ],

        limit => $copy_limit,
        offset => $copy_offset
    };
}

1;

