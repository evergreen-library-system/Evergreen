package OpenILS::Application::AppUtils;
use strict; use warnings;
use base qw/OpenSRF::Application/;
use OpenSRF::Utils::Cache;
use OpenSRF::EX qw(:try);
use OpenILS::Perm;
use OpenSRF::Utils::Logger;
use OpenILS::Utils::ModsParser;
use OpenILS::Event;
my $logger = "OpenSRF::Utils::Logger";


my $cache_client = "OpenSRF::Utils::Cache";

# ---------------------------------------------------------------------------
# Pile of utilty methods used accross applications.
# ---------------------------------------------------------------------------


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
	return $session;
}


# returns undef if user has all of the perms provided
# returns the first failed perm on failure
sub check_user_perms {
	my($self, $user_id, $org_id, @perm_types ) = @_;

	$logger->debug("Checking perms with user : $user_id , org: $org_id, @perm_types");

	throw OpenSRF::EX::ERROR ("Invalid call to check_user_perms()")
		unless( defined($user_id) and defined($org_id) and @perm_types); 

	my $session = OpenSRF::AppSession->create("open-ils.storage");
	for my $type (@perm_types) {
		my $req = $session->request(
			"open-ils.storage.permission.user_has_perm", 
			$user_id, $type, $org_id );
		my $resp = $req->gather(1);
		if(!$resp) { 
			$session->disconnect();
			return $type; 
		}
	}

	$session->disconnect();
	return undef;
}

# checks the list of user perms.  The first one that fails returns a new
# OpenILS::Perm object of that type.  Returns undef if all perms are allowed
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
		'open-ils.auth.session.retrieve', $user_session );


	if(! $content or $self->event_code($content)) {
		throw OpenSRF::EX::ERROR 
			("Session [$user_session] cannot be authenticated" );
	}

	$logger->debug("Fetch user session $user_session found user " . $content->id );

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
	my $response = $request->recv(30);

	$request->wait_complete;

	if(!$request->complete) {
		throw OpenSRF::EX::ERROR ("Call to $service for method $method with params @params" . 
				"\n did not complete successfully");
	}

	if(!$response) {
		warn "No response from $service for method $method with params @params";
	}

	if(UNIVERSAL::isa($response,"Error")) {
		throw $response ("Call to $service for method $method with params @params" . 
				"\n failed with exception: " . $response->stringify );
	}


	$request->finish();
	$session->finish();
	$session->disconnect();

	my $value;

	if($response) { $value = $response->content; }
	else { $value = undef; }

	return $value;
}





my $tree						= undef;
my $orglist					= undef;
my $org_typelist			= undef;
my $org_typelist_hash	= {};

sub get_org_tree {

	my $self = shift;
	if($tree) { return $tree; }

	# see if it's in the cache
	$tree = $cache_client->new()->get_cache('_orgtree');
	if($tree) { return $tree; }

	if(!$orglist) {
		warn "Retrieving Org Tree\n";
		$orglist = $self->simple_scalar_request( 
			"open-ils.storage", 
			"open-ils.storage.direct.actor.org_unit.retrieve.all.atomic" );
	}

	if( ! $org_typelist ) {
		warn "Retrieving org types\n";
		$org_typelist = $self->simple_scalar_request( 
			"open-ils.storage", 
			"open-ils.storage.direct.actor.org_unit_type.retrieve.all.atomic" );
		$self->build_org_type($org_typelist);
	}

	$tree = $self->build_org_tree($orglist,1);
	$cache_client->new()->put_cache('_orgtree', $tree);
	return $tree;

}

my $slimtree = undef;
sub get_slim_org_tree {

	my $self = shift;
	if($slimtree) { return $slimtree; }

	# see if it's in the cache
	$slimtree = $cache_client->new()->get_cache('slimorgtree');
	if($slimtree) { return $slimtree; }

	if(!$orglist) {
		warn "Retrieving Org Tree\n";
		$orglist = $self->simple_scalar_request( 
			"open-ils.storage", 
			"open-ils.storage.direct.actor.org_unit.retrieve.all.atomic" );
	}

	$slimtree = $self->build_org_tree($orglist);
	$cache_client->new->put_cache('slimorgtree', $slimtree);
	return $slimtree;

}


sub build_org_type { 
	my($self, $org_typelist)  = @_;
	for my $type (@$org_typelist) {
		$org_typelist_hash->{$type->id()} = $type;
	}
}



sub build_org_tree {

	my( $self, $orglist, $add_types ) = @_;

	return $orglist unless ( 
			ref($orglist) and @$orglist > 1 );

	my @list = sort { 
		$a->ou_type <=> $b->ou_type ||
		$a->name cmp $b->name } @$orglist;

	for my $org (@list) {

		next unless ($org);

		if(!ref($org->ou_type()) and $add_types) {
			$org->ou_type( $org_typelist_hash->{$org->ou_type()});
		}

		next unless (defined($org->parent_ou));

		my ($parent) = grep { $_->id == $org->parent_ou } @list;
		next unless $parent;
		$parent->children([]) unless defined($parent->children); 
		push( @{$parent->children}, $org );
	}

	return $list[0];

}

sub fetch_user {
	my( $self, $userid ) = @_;
	my( $user, $evt );

	$logger->debug("Fetching user $userid from storage");

	$user = $self->simplereq(
		'open-ils.storage',
		'open-ils.storage.direct.actor.user.retrieve', $userid );

	if(!$user) {
		$logger->info("User $userid not found in the db");
		$evt = OpenILS::Event->new('USER_NOT_FOUND');
	}

	return ($user, $evt);
}

sub checkses {
	my( $self, $session ) = @_;
	my $user; my $evt; my $e; 

	$logger->debug("Checking user session $session");

	try {
		$user = $self->check_user_session($session);
	} catch Error with { $e = 1; };

	if( $e or !$user ) { $evt = OpenILS::Event->new('NO_SESSION'); }
	return ( $user, $evt );
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
	return ($user, $evt) if $evt;
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

	$logger->debug("Fetching copy $copyid from storage");

	$copy = $self->simplereq(
		'open-ils.storage',
		'open-ils.storage.direct.asset.copy.retrieve', $copyid );

	if(!$copy) { $evt = OpenILS::Event->new('COPY_NOT_FOUND'); }

	return( $copy, $evt );
}


# retrieves a circ object by id
sub fetch_circulation {
	my( $self, $circid ) = @_;
	my $circ; my $evt;
	
	$logger->debug("Fetching circ $circid from storage");

	$circ = $self->simplereq(
		'open-ils.storage',
		"open-ils.storage.direct.action.circulation.retrieve", $circid );

	if(!$circ) {
		$evt = OpenILS::Event->new('CIRCULATION_NOT_FOUND', circid => $circid );
	}

	return ( $circ, $evt );
}

sub fetch_record_by_copy {
	my( $self, $copyid ) = @_;
	my( $record, $evt );

	$logger->debug("Fetching record by copy $copyid from storage");

	$record = $self->simplereq(
		'open-ils.storage',
		'open-ils.storage.fleshed.biblio.record_entry.retrieve_by_copy', $copyid );

	if(!$record) {
		$evt = OpenILS::Event->new('BIBLIO_RECORD_NOT_FOUND');
	}

	return ($record, $evt);
}

# turns a record object into an mvr (mods) object
sub record_to_mvr {
	my( $self, $record ) = @_;
	my $u = OpenILS::Utils::ModsParser->new();
	$u->start_mods_batch( $record->marc );
	my $mods = $u->finish_mods_batch();
	$mods->doc_id($record->id);
	return $mods;
}

sub fetch_hold {
	my( $self, $holdid ) = @_;
	my( $hold, $evt );

	$logger->debug("Fetching hold $holdid from storage");

	$hold = $self->simplereq(
		'open-ils.storage',
		'open-ils.storage.direct.action.hold_request.retrieve', $holdid);

	$evt = OpenILS::Event->new('HOLD_NOT_FOUND', holdid => $holdid) unless $hold;

	return ($hold, $evt);
}


sub fetch_hold_transit_by_hold {
	my( $self, $holdid ) = @_;
	my( $transit, $evt );

	$logger->debug("Fetching transit by hold $holdid from storage");

	$transit = $self->simplereq(
		'open-ils.storage',
		'open-ils.storage.direct.action.hold_transit_copy.search.hold', $holdid );

	$evt = OpenILS::Event->new('TRANSIT_NOT_FOUND', holdid => $holdid) unless $transit;

	return ($transit, $evt );
}


sub fetch_copy_by_barcode {
	my( $self, $barcode ) = @_;
	my( $copy, $evt );

	$logger->debug("Fetching copy by barcode $barcode from storage");

	$copy = $self->simplereq( 'open-ils.storage',
		'open-ils.storage.direct.asset.copy.search.barcode', $barcode );

	$evt = OpenILS::Event->new('COPY_NOT_FOUND', barcode => $barcode) unless $copy;

	return ($copy, $evt);
}

sub fetch_open_billable_transaction {
	my( $self, $transid ) = @_;
	my( $transaction, $evt );

	$logger->debug("Fetching open billable transaction $transid from storage");

	$transaction = $self->simplereq(
		'open-ils.storage',
		'open-ils.storage.direct.money.open_billable_transaction_summary.retrieve',  $transid);

	$evt = OpenILS::Event->new(
		'TRANSACTION_NOT_FOUND', transid => $transid ) unless $transaction;

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

	my $meth = $buckets{$type};
	$bucket = $self->simplereq(
		'open-ils.storage',
		"open-ils.storage.direct.container.$meth.retrieve", $id );

	$evt = OpenILS::Event->new(
		'CONTAINER_NOT_FOUND', container => $id, 
			container_type => $type ) unless $bucket;

	return ($bucket, $evt);
}


sub fetch_container_item {
	my( $self, $id, $type ) = @_;
	my( $bucket, $evt );

	$logger->debug("Fetching container item $id with type $type");

	my $meth = $buckets{$type} . "_item";

	$bucket = $self->simplereq(
		'open-ils.storage',
		"open-ils.storage.direct.container.$meth.retrieve", $id );

	$evt = OpenILS::Event->new(
		'CONTAINER_ITEM_NOT_FOUND', itemid => $id, 
			container_type => $type ) unless $bucket;

	return ($bucket, $evt);
}


sub fetch_patron_standings {
	my $self = shift;
	$logger->debug("Fetching patron standings");	
	return $self->simplereq(
		'open-ils.storage', 
		'open-ils.storage.direct.config.standing.retrieve.all.atomic');
}


sub fetch_permission_group_tree {
	my $self = shift;
	$logger->debug("Fetching patron profiles");	
	return $self->simplereq(
		'open-ils.actor', 
		'open-ils.actor.groups.tree.retrieve' );
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
		'open-ils.storage', 
		'open-ils.storage.direct.config.copy_status.retrieve.all.atomic' );
}

sub fetch_copy_locations {
	my $self = shift; 
	return $self->simplereq(
		'open-ils.storage', 
		'open-ils.storage.direct.asset.copy_location.retrieve.all.atomic');
}

sub fetch_callnumber {
	my( $self, $id ) = @_;
	my $evt = undef;
	$logger->debug("Fetching callnumber $id");

	my $cn = $self->simplereq(
		'open-ils.storage',
		'open-ils.storage.direct.asset.call_number.retrieve', $id );
	$evt = OpenILS::Event->new( 'VOLUME_NOT_FOUND', id => $id ) unless $cn;

	return ( $cn, $evt );
}

sub fetch_org_unit {
	my( $self, $id ) = @_;
	$logger->debug("Fetching org unit $id");
	my $evt = undef;

	my $org = $self->simplereq(
		'open-ils.storage', 
		'open-ils.storage.direct.actor.org_unit.retrieve', $id );
	$evt = OpenILS::Event->new( 'ORG_UNIT_NOT_FOUND', id => $id ) unless $org;

	return ($org, $evt);
}

sub fetch_stat_cat {
	my( $self, $type, $id ) = @_;
	my( $cat, $evt );
	$logger->debug("Fetching $type stat cat: $id");
	$cat = $self->simplereq(
		'open-ils.storage', 
		"open-ils.storage.direct.$type.stat_cat.retrieve", $id );
	$evt = OpenILS::Event->new( 'STAT_CAT_NOT_FOUND', id => $id ) unless $cat;
	return ( $cat, $evt );
}

sub fetch_stat_cat_entry {
	my( $self, $type, $id ) = @_;
	my( $entry, $evt );
	$logger->debug("Fetching $type stat cat entry: $id");
	$entry = $self->simplereq(
		'open-ils.storage', 
		"open-ils.storage.direct.$type.stat_cat_entry.retrieve", $id );
	$evt = OpenILS::Event->new( 'STAT_CAT_ENTRY_NOT_FOUND', id => $id ) unless $entry;
	return ( $entry, $evt );
}


sub find_org {
	my( $self, $org_tree, $orgid )  = @_;
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
		'open-ils.storage',
		'open-ils.storage.direct.config.non_cataloged_type.search_where.atomic',
		{ name => $name, owning_lib => $orgId } );
	return ($types->[0], undef) if($types and @$types);
	return (undef, OpenILS::Event->new('NON_CAT_TYPE_NOT_FOUND') );
}

sub fetch_non_cat_type {
	my( $self, $id ) = @_;
	$logger->debug("Fetching non cat type $id");
	my( $type, $evt );
	$type = $self->simplereq(
		'open-ils.storage', 
		'open-ils.storage.direct.config.non_cataloged_type.retrieve', $id );
	$evt = OpenILS::Event->new('NON_CAT_TYPE_NOT_FOUND') unless $type;
	return ($type, $evt);
}

sub DB_UPDATE_FAILED { 
	my( $self, $payload ) = @_;
	return OpenILS::Event->new('DATABASE_UPDATE_FAILED', 
		payload => ($payload) ? $payload : undef ); 
}

1;
