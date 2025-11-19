package OpenILS::Application::AppUtils;
use strict; use warnings;
use MARC::Record;
use MARC::File::XML (BinaryEncoding => 'utf8', RecordFormat => 'USMARC');
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
use DateTime;
use DateTime::Format::ISO8601;
use List::MoreUtils qw/uniq/;
use Digest::MD5 qw(md5_hex);

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
    return $evt->{ilsevent} if $self->is_event($evt);
    return undef;
}

# some events, in particular auto-generated events, don't have an 
# ilsevent key.  treat hashes with a 'textcode' key as events.
sub is_event {
    my ($self, $evt) = @_;
    return (
        ref($evt) eq 'HASH' and (
            defined $evt->{ilsevent} or
            defined $evt->{textcode}
        )
    );
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

# retrieves a provisional user session awaiting MFA upgrade
sub check_provisional_session {
    my( $self, $user_session ) = @_;

    my $content = $self->simplereq( 
        'open-ils.auth_internal', 
        'open-ils.auth_internal.session.retrieve_provisional', $user_session);

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
          flesh_fields => { bre => [ 'fixed_fields' ],
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
        'open-ils.cstore.direct.action.hold_transit_copy.search', { hold => $holdid, cancel_time => undef } );

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
            current_copy        => $copyid , 
            capture_time        => { "!=" => undef }, 
            fulfillment_time    => undef,
            cancel_time         => undef,
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
        'open-ils.cstore.direct.asset.copy_location.search.atomic', { id => { '!=' => undef }, deleted => 'f' });
}

sub fetch_copy_location_by_name {
    my( $self, $name, $org ) = @_;
    my $evt;
    my $cl = $self->cstorereq(
        'open-ils.cstore.direct.asset.copy_location.search',
            { name => $name, owning_lib => $org, deleted => 'f' } );
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

sub find_org_by_shortname {
    my( $self, $org_tree, $shortname )  = @_;
    return undef unless $org_tree and defined $shortname;
    return $org_tree if ( $org_tree->shortname eq $shortname );
    return undef unless ref($org_tree->children);
    for my $c (@{$org_tree->children}) {
        my $o = $self->find_org_by_shortname($c, $shortname);
        return $o if $o;
    }
    return undef;
}

sub find_lasso_by_name {
    my( $self, $name )  = @_;
    return $self->simplereq(
        'open-ils.cstore', 
        'open-ils.cstore.direct.actor.org_lasso.search.atomic', { name => $name } )->[0];
}

sub fetch_lasso_org_maps {
    my( $self, $lasso )  = @_;
    return $self->simplereq(
        'open-ils.cstore', 
        'open-ils.cstore.direct.actor.org_lasso_map.search.atomic', { lasso => $lasso } );
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
        { target_copy => $copyid, dest_recv_time => undef, cancel_time => undef });
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

    my $copy        = $params{copy} || die "update_copy(): copy required";
    my $editor  = $params{editor} || die "update_copy(): copy editor required";
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

    my $reservation = $params{reservation}  || die "update_reservation(): reservation required";
    my $editor      = $params{editor} || die "update_reservation(): copy editor required";
    my $session     = $params{session};

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
    my $id  = shift;
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
###############################################################################
# Price Parsing Utilities
#
# MARC 020 $c (Terms of availability) may contain a price, currency symbol,
# currency code, parenthetical qualifiers, multiple prices, or non-price
# statements (e.g. "Rental material", "For sale ($450.00) or rent ($45.00)").
# The acquisition workflows want an estimated_unit_price when a numeric value
# can be reliably extracted.  Historically, the raw $c value was stored as a
# lineitem attribute string and applying it directly caused BAD_PARAMS errors
# when currency symbols or other text were present (LP#2078503).
#
# extract_marc_price($raw)
#   Returns the first numeric price found in the string as a normalized
#   decimal (thousands separators removed). Returns undef when no numeric
#   value is present. Accepts leading currency symbols (Unicode Sc) or simple
#   alphabetic currency codes (e.g. Rs, CAD) immediately preceding the number.
#   Examples:
#     "$19.95"            -> 19.95
#     "Rs15.76 ($5.60 U.S.)" -> 15.76 (first price wins)
#     "For sale ($450.00) or rent ($45.00)" -> 450.00
#     "Rental material"    -> undef
#     "Free"               -> undef
###############################################################################
sub extract_marc_price {
    my ($class, $raw) = @_;
    return undef unless defined $raw;

    # Trim whitespace
    $raw =~ s/^\s+|\s+$//g;

    # Remove trailing punctuation that may follow the price
    # but avoid stripping decimals (e.g. '19.95.')
    $raw =~ s/[\.;:,]+$//;

    # Find first occurrence of a number (with optional currency symbol/code)
    # Number pattern: digits with optional thousands separators and optional decimal part.
    # Match either: number with thousands separators OR plain number (any length)
    if ($raw =~ /(?:[A-Z]{1,3}|\p{Sc})?\s*([0-9]{1,3}(?:,[0-9]{3})+(?:\.[0-9]+)?|[0-9]+(?:\.[0-9]+)?)/) {
        my $num = $1;
        $num =~ s/,//g; # remove thousands separators
        return $num; # return as numeric string; caller may numify
    }

    return undef;
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

    if ($auth) {
        my $coust = $e->retrieve_config_org_unit_setting_type([
            $name, {flesh => 1, flesh_fields => {coust => ['view_perm']}}
        ]);
        return undef unless defined $coust;
        if ($coust->view_perm) {
            return undef unless $self->ou_ancestor_setting_perm_check($orgid, $coust->view_perm->code, $e, $auth);
        }
    }

    my $query = {from => ['actor.org_unit_ancestor_setting', $name, $orgid]};
    my $setting = $e->json_query($query)->[0];
    return undef unless $setting;
    return {org => $setting->{org_unit}, value => OpenSRF::Utils::JSON->JSON2perl($setting->{value})};
}

# Returns the org id if the requestor has the permissions required
# to view the ou setting.
sub ou_ancestor_setting_perm_check {
    my( $self, $orgid, $view_perm, $e, $auth ) = @_;
    $e = $e || OpenILS::Utils::CStoreEditor->new(
        (defined $auth) ? (authtoken => $auth) : ()
    );

    # And you can't have permission if you don't have a valid session.
    return undef if not $e->checkauth;
    # And now that we know you MIGHT have permission, we check it.
    if ($view_perm) {
        return undef unless $e->allowed($view_perm, $orgid);
    }

    return $orgid;
}

sub ou_ancestor_setting_log {
    my ( $self, $orgid, $name, $e, $auth ) = @_;
    $e = $e || OpenILS::Utils::CStoreEditor->new(
        (defined $auth) ? (authtoken => $auth, xact => 1) : ()
    );
    my $coust;

    if ($auth) {
        $coust = $e->retrieve_config_org_unit_setting_type([
            $name, {flesh => 1, flesh_fields => {coust => ['view_perm']}}
        ]);

        my $perm_code = $coust->view_perm ? $coust->view_perm->code : undef;
        my $qorg = $self->ou_ancestor_setting_perm_check(
            $orgid,
            $perm_code,
            $e,
            $auth
        );
        my $sort = { order_by => { coustl => 'date_applied DESC' } };
        return $e->json_query({
            from => 'coustl',
            where => {
                field_name => $name,
                org => $qorg
            },
            $sort
        });
    };
}

# This fetches a set of OU settings in one fell swoop,
# which can be significantly faster than invoking
# $U->ou_ancestor_setting() one setting at a time.
# As the "_insecure" implies, however, callers are
# responsible for ensuring that the settings to be
# fetch do not need view permission checks.
sub ou_ancestor_setting_batch_insecure {
    my( $self, $orgid, $names ) = @_;

    my %result = map { $_ => undef } @$names;
    my $query = {
        from => [
            'actor.org_unit_ancestor_setting_batch',
            $orgid,
            '{' . join(',', @$names) . '}'
        ]
    };
    my $e = OpenILS::Utils::CStoreEditor->new();
    my $settings = $e->json_query($query);
    foreach my $setting (@$settings) {
        $result{$setting->{name}} = {
            org => $setting->{org_unit},
            value => OpenSRF::Utils::JSON->JSON2perl($setting->{value})
        };
    }
    return %result;
}

# Returns a hash of hashes like so:
# { 
#   $lookup_org_id => {org => $context_org, value => $setting_value},
#   $lookup_org_id2 => {org => $context_org2, value => $setting_value2},
#   $lookup_org_id3 => {} # example of no setting value exists
#   ...
# }
sub ou_ancestor_setting_batch_by_org_insecure {
    my ($self, $org_ids, $name, $e) = @_;

    $e ||= OpenILS::Utils::CStoreEditor->new();
    my %result = map { $_ => {value => undef} } @$org_ids;

    my $query = {
        from => [
            'actor.org_unit_ancestor_setting_batch_by_org',
            $name, '{' . join(',', @$org_ids) . '}'
        ]
    };

    # DB func returns an array of settings matching the order of the
    # list of org unit IDs.  If the setting does not contain a valid
    # ->id value, then no setting value exists for that org unit.
    my $settings = $e->json_query($query);
    for my $idx (0 .. $#$org_ids) {
        my $setting = $settings->[$idx];
        my $org_id = $org_ids->[$idx];

        next unless $setting->{id}; # null ID means no value is present.

        $result{$org_id}->{org} = $setting->{org_unit};
        $result{$org_id}->{value} = 
            OpenSRF::Utils::JSON->JSON2perl($setting->{value});
    }

    return %result;
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
    $ORG_TREE{$locale} = $tree; # make sure to populate the process-local cache
    return $tree if $tree;

    my $ses = OpenILS::Utils::CStoreEditor->new;
    $ses->session->session_locale($locale);
    $tree = $ses->search_actor_org_unit( 
        [
            {"parent_ou" => undef },
            {
                flesh               => -1,
                flesh_fields    => { aou =>  ['children'] },
                order_by            => { aou => 'name'}
            }
        ]
    )->[0];

    $ORG_TREE{$locale} = $tree;
    $cache->put_cache("orgtree.$locale", $tree);
    return $tree;
}

sub get_global_flag {
    my($self, $flag) = @_;
    return undef unless ($flag);
    return OpenILS::Utils::CStoreEditor->new->retrieve_config_global_flag($flag);
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

sub get_grp_ancestors {
    my($self, $grp_id, $use_cache) = @_;

    my ($cache, $grps);

    if ($use_cache) {
        $cache = OpenSRF::Utils::Cache->new("global", 0);
        $grps = $cache->get_cache("grp.ancestors.$grp_id");
        return $grps if $grps;
    }

    my $grp_list = OpenILS::Utils::CStoreEditor->new->json_query({
        select => {
            pgt => [{
                transform => 'permission.grp_ancestors',
                column => 'id',
                result_field => 'id',
                params => []
            }],
        },
        from => 'pgt',
        where => {id => $grp_id}
    });

    $grps = [ map { $_->{id} } @$grp_list ];

    $cache->put_cache("grp.ancestors.$grp_id", $grps) if $use_cache;
    return $grps;
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

# returns the ID of the org unit ancestor at the specified distance
sub get_org_unit_ancestor_at_distance {
    my ($class, $org_id, $distance) = @_;
    my $ancestors = OpenILS::Utils::CStoreEditor->new->json_query(
        { from => ['actor.org_unit_ancestors_distance', $org_id] });
    my @match = grep { $_->{distance} == $distance } @{$ancestors};
    return (@match) ? $match[0]->{id} : undef;
}

# returns the ID of the org unit parent
sub get_org_unit_parent {
    my ($class, $org_id) = @_;
    return $class->get_org_unit_ancestor_at_distance($org_id, 1);
}

# Returns the proximity value between two org units.
sub get_org_unit_proximity {
    my ($class, $e, $from_org, $to_org) = @_;
    $e = OpenILS::Utils::CStoreEditor->new unless ($e);
    my $r = $e->json_query(
        {
            select => {aoup => ['prox']},
            from => 'aoup',
            where => {from_org => $from_org, to_org => $to_org}
        }
    );
    if (ref($r) eq 'ARRAY' && @$r) {
        return $r->[0]->{prox};
    }
    return undef;
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

    my $min_price = $self->ou_ancestor_setting_value($owner, OILS_SETTING_MIN_ITEM_PRICE);
    my $max_price = $self->ou_ancestor_setting_value($owner, OILS_SETTING_MAX_ITEM_PRICE);
    my $charge_on_0 = $self->ou_ancestor_setting_value($owner, OILS_SETTING_CHARGE_LOST_ON_ZERO, $e);
    my $primary_field = $self->ou_ancestor_setting_value($owner, OILS_SETTING_PRIMARY_ITEM_VALUE_FIELD, $e);
    my $backup_field = $self->ou_ancestor_setting_value($owner, OILS_SETTING_SECONDARY_ITEM_VALUE_FIELD, $e);

    my $price = defined $primary_field && $primary_field eq 'cost'
        ? $copy->cost
        : $copy->price;

    # set the default price if needed
    if (!defined $price or ($price == 0 and $charge_on_0)) {
        if (defined $backup_field && $backup_field eq 'cost') {
            $price = $copy->cost;
        } elsif (defined $backup_field && $backup_field eq 'price') {
            $price = $copy->price;
        }
    }
    # possible fallthrough to original default item price behavior
    if (!defined $price or ($price == 0 and $charge_on_0)) {
        # set to default price
        $price = $self->ou_ancestor_setting_value(
            $owner, OILS_SETTING_DEF_ITEM_PRICE, $e) || 0;
    }

    # adjust to min/max range if needed
    if (defined $max_price and $price > $max_price) {
        $price = $max_price;
    } elsif (defined $min_price and $price < $min_price
        and ($price != 0 or $charge_on_0 or !defined $charge_on_0)) {
        # default to raising the price to the minimum,
        # but let 0 fall through if $charge_on_0 is set and is false
        $price = $min_price;
    }

    return $price;
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
            {hook => $hook, owner => $org_id, active => 't'})->[0];

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
    my $sum = $e->json_query({from => ['action.summarize_all_circ_chain', $circ_id]})->[0];
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
    return [ map { shift @$_ } @{$search_result->{ids}} ];
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
    my $id_list = [ map { shift @$_ } @{$search_result->{ids}} ];

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
    ], {substream => 1});

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
            acp => ['id', 'barcode', 'circ_lib', 'create_date', 'active_date',
                    'age_protect', 'holdable', 'copy_number', 'circ_modifier'],
            acpl => [
                {column => 'name', alias => 'copy_location'},
                {column => 'holdable', alias => 'location_holdable'},
                {column => 'url', alias => 'location_url'}
            ],
            ccs => [
                {column => 'id', alias => 'status_code'},
                {column => 'name', alias => 'copy_status'},
                {column => 'holdable', alias => 'status_holdable'},
                {column => 'is_available', alias => 'is_available'}
            ],
            acn => [
                {column => 'label', alias => 'call_number_label'},
                {column => 'id', alias => 'call_number'},
                {column => 'owning_lib', alias => 'call_number_owning_lib'}
            ],
            circ => ['due_date',{column => 'circ_lib', alias => 'circ_circ_lib'}],
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
            ($staff ? (erfcc => ['circ_count']) : ()),
            crahp => [
                {column => 'name', alias => 'age_protect_label'}
            ],
            ($iss_id ? (sitem => ["issuance"]) : ())
        },

        from => {
            acp => [
                {acn => { # 0
                    join => {
                        acnp => { fkey => 'prefix' },
                        acns => { fkey => 'suffix' }
                    },
                    filter => [
                        {deleted => 'f'},
                        ($rec_id ? {record => $rec_id} : ())
                    ],
                }},
                'aou', # 1
                {circ => { # 2 If the copy is circulating, retrieve the open circ
                    type => 'left',
                    filter => {checkin_time => undef}
                }},
                {acpl => { # 3
                    filter => {
                        deleted => 'f',
                        ($staff ? () : ( opac_visible => 't' )),
                    },
                }},
                {ccs => { # 4
                    ($staff ? () : (filter => { opac_visible => 't' }))
                }},
                {acpm => { # 5
                    type => 'left',
                    join => {
                        bmp => { type => 'left', filter => { deleted => 'f' } }
                    }
                }},
                {'crahp' => { # 6
                    type => 'left'
                }},
                ($iss_id ? { # 7
                    sitem => {
                        fkey => 'id',
                        field => 'unit',
                        filter => {issuance => $iss_id},
                        join => {
                            sstr => { }
                        }
                    }
                } : ()),
                ($staff ? {
                    erfcc => {
                        fkey => 'id',
                        field => 'id'
                    }
                }: ()),
            ]
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
            {class => 'acn', field => 'label_sortkey'},
            {class => 'acns', field => 'label_sortkey'},
            {class => 'bmp', field => 'label_sortkey'},
            {class => 'acp', field => 'copy_number'},
            {class => 'acp', field => 'barcode'}
        ],

        limit => $copy_limit,
        offset => $copy_offset
    };
}

# Compare two dates, date1 and date2. If date2 is not defined, then
# DateTime->now will be used. Assumes dates are in ISO8601 format as
# supported by DateTime::Format::ISO8601. (A future enhancement might
# be to support other formats.)
#
# Returns -1 if $date1 < $date2
# Returns 0 if $date1 == $date2
# Returns 1 if $date1 > $date2
sub datecmp {
    my $self = shift;
    my $date1 = shift;
    my $date2 = shift;

    # Check for timezone offsets and limit them to 2 digits:
    if ($date1 && $date1 =~ /(?:-|\+)\d\d\d\d$/) {
        $date1 = substr($date1, 0, length($date1) - 2);
    }
    if ($date2 && $date2 =~ /(?:-|\+)\d\d\d\d$/) {
        $date2 = substr($date2, 0, length($date2) - 2);
    }

    # check date1:
    unless (UNIVERSAL::isa($date1, "DateTime")) {
        $date1 = DateTime::Format::ISO8601->parse_datetime($date1);
    }

    # Check for date2:
    unless ($date2) {
        $date2 = DateTime->now;
    } else {
        unless (UNIVERSAL::isa($date2, "DateTime")) {
            $date2 = DateTime::Format::ISO8601->parse_datetime($date2);
        }
    }

    return DateTime->compare($date1, $date2);
}


# marcdoc is an XML::LibXML document
# updates the doc and returns the entityized MARC string
sub strip_marc_fields {
    my ($class, $e, $marcdoc, $grps) = @_;
    
    my $orgs = $class->get_org_ancestors($e->requestor->ws_ou);

    my $query = {
        select  => {vibtf => ['field']},
        from    => {vibtf => 'vibtg'},
        where   => {'+vibtg' => {owner => $orgs}},
        distinct => 1
    };

    # give me always-apply groups plus any selected groups
    if ($grps and @$grps) {
        $query->{where}->{'+vibtg'}->{'-or'} = [
            {id => $grps},
            {always_apply => 't'}
        ];

    } else {
        $query->{where}->{'+vibtg'}->{always_apply} = 't';
    }

    my $fields = $e->json_query($query);

    for my $field (@$fields) {
        my $tag = $field->{field};
        for my $node ($marcdoc->findnodes('//*[@tag="'.$tag.'"]')) {
            $node->parentNode->removeChild($node);
        }
    }

    return $class->entityize($marcdoc->documentElement->toString);
}

# marcdoc is an XML::LibXML document
# updates the document and returns the entityized MARC string.
sub set_marc_905u {
    my ($class, $marcdoc, $username) = @_;

    # Look for existing 905$u subfields. If any exist, do nothing.
    my @nodes = $marcdoc->findnodes('//*[@tag="905"]/*[@code="u"]');
    unless (@nodes) {
        # We create a new 905 and the subfield u to that.
        my $parentNode = $marcdoc->createElement('datafield');
        $parentNode->setAttribute('tag', '905');
        $parentNode->setAttribute('ind1', '');
        $parentNode->setAttribute('ind2', '');
        $marcdoc->documentElement->addChild($parentNode);
        my $node = $marcdoc->createElement('subfield');
        $node->setAttribute('code', 'u');
        $node->appendTextNode($username);
        $parentNode->addChild($node);

    }

    return $class->entityize($marcdoc->documentElement->toString);
}

# Given a list of PostgreSQL arrays of numbers,
# unnest the numbers and return a unique set, skipping any list elements
# that are just '{NULL}'.
sub unique_unnested_numbers {
    my $class = shift;

    no warnings 'numeric';

    return undef unless ( scalar @_ );

    return uniq(
        map(
            int,
            map { $_ eq 'NULL' ? undef : (split /,/, $_) }
                map { substr($_, 1, -1) } @_
        )
    );
}

# Given a list of numbers, turn them into a PG array, skipping undef's
sub intarray2pgarray {
    my $class = shift;
    no warnings 'numeric';

    return '{' . join( ',', map(int, grep { defined && /^\d+$/ } @_) ) . '}';
}

# Check if a transaction should be left open or closed. Close the
# transaction if it should be closed or open it otherwise. Returns
# undef on success or a failure event.
sub check_open_xact {
    my( $self, $editor, $xactid, $xact ) = @_;

    # Grab the transaction
    $xact ||= $editor->retrieve_money_billable_transaction($xactid);
    return $editor->event unless $xact;
    $xactid ||= $xact->id;

    # grab the summary and see how much is owed on this transaction
    my ($summary) = $self->fetch_mbts($xactid, $editor);

    # grab the circulation if it is a circ;
    my $circ = $editor->retrieve_action_circulation($xactid);

    # If nothing is owed on the transaction but it is still open
    # and this transaction is not an open circulation, close it
    if(
        ( $summary->balance_owed == 0 and ! $xact->xact_finish ) and
        ( !$circ or $circ->stop_fines )) {

        $logger->info("closing transaction ".$xact->id. ' because balance_owed == 0');
        $xact->xact_finish('now');
        $editor->update_money_billable_transaction($xact)
            or return $editor->event;
        return undef;
    }

    # If money is owed or a refund is due on the xact and xact_finish
    # is set, clear it (to reopen the xact) and update
    if( $summary->balance_owed != 0 and $xact->xact_finish ) {
        $logger->info("re-opening transaction ".$xact->id. ' because balance_owed != 0');
        $xact->clear_xact_finish;
        $editor->update_money_billable_transaction($xact)
            or return $editor->event;
        return undef;
    }
    return undef;
}

# Because floating point math has rounding issues, and Dyrcona gets
# tired of typing out the code to multiply floating point numbers
# before adding and subtracting them and then dividing the result by
# 100 each time, he wrote this little subroutine for subtracting
# floating point values.  It can serve as a model for the other
# operations if you like.
#
# It takes a list of floating point values as arguments.  The rest are
# all subtracted from the first and the result is returned.  The
# values are all multiplied by 100 before being used, and the result
# is divided by 100 in order to avoid decimal rounding errors inherent
# in floating point math.
#
# XXX shifting using multiplication/division *may* still introduce
# rounding errors -- better to implement using string manipulation?
sub fpdiff {
    my ($class, @args) = @_;
    my $result = shift(@args) * 100;
    while (my $arg = shift(@args)) {
        $result -= $arg * 100;
    }
    return $result / 100;
}

sub fpsum {
    my ($class, @args) = @_;
    my $result = shift(@args) * 100;
    while (my $arg = shift(@args)) {
        $result += $arg * 100;
    }
    return $result / 100;
}

# Non-migrated passwords can be verified directly in the DB
# with any extra hashing.
sub verify_user_password {
    my ($class, $e, $user_id, $passwd, $pw_type) = @_;

    $pw_type ||= 'main'; # primary login password

    my $verify = $e->json_query({
        from => [
            'actor.verify_passwd', 
            $user_id, $pw_type, $passwd
        ]
    })->[0];

    return $class->is_true($verify->{'actor.verify_passwd'});
}

# Passwords migrated from the original MD5 scheme are passed through 2
# extra layers of MD5 hashing for backwards compatibility with the
# MD5 passwords of yore and the MD5-based chap-style authentication.  
# Passwords are stored in the DB like this:
# CRYPT( MD5( pw_salt || MD5(real_password) ), pw_salt )
#
# If 'as_md5' is true, the password provided has already been
# MD5 hashed.
sub verify_migrated_user_password {
    my ($class, $e, $user_id, $passwd, $as_md5) = @_;

    # 'main' is the primary login password. This is the only password 
    # type that requires the additional MD5 hashing.
    my $pw_type = 'main';

    # Sometimes we have the bare password, sometimes the MD5 version.
    my $md5_pass = $as_md5 ? $passwd : md5_hex($passwd);

    my $salt = $e->json_query({
        from => [
            'actor.get_salt', 
            $user_id, 
            $pw_type
        ]
    })->[0];

    $salt = $salt->{'actor.get_salt'};

    return $class->verify_user_password(
        $e, $user_id, md5_hex($salt . $md5_pass), $pw_type);
}

# Calculate a barcode check digit using the Luhn algorithm:
# https://en.wikipedia.org/wiki/Luhn_algorithm
# Takes a string of digits and returns the checkdigit.
# -1 is returned if the string contains any characters other than digits.
sub calculate_luhn_checkdigit {
    my ($class, $input) = @_;
    return -1 unless ($input =~ /^\d+$/);
    my @bc = reverse(split(//, $input));
    my $mult = 2;
    my $sum = 0;
    for (my $i = 0; $i < @bc; $i++) {
        my $v = $bc[$i] * $mult;
        $v -= 9 if ($v > 9);
        $sum += $v;
        $mult = ($mult == 2) ? 1 : 2;
    }
    return ($sum % 10) ? 10 - ($sum % 10) : 0;
}

# Generate a barcode using a combination of:
# $prefix : A prefix sequence for the barcode.
# $length : The total lenght for the generated barcode, including
#           length of the prefix and checkdigit (if any).
# $checkdigit: A boolean, whether or not to calculate a check digit.
# $sequence: A database sequence to use as a source of the main digit
#            sequence for the barcode.
# $e : An optional CStoreEditor to use for queries.  If not provided,
#      a new one will be created and used.
#
# Returns the new barcode or undef on failure.
sub generate_barcode {
    my ($class, $prefix, $length, $checkdigit, $sequence, $e) = @_;
    $e = OpenILS::Utils::CStoreEditor->new() unless($e);
    # Don't do checkdigit if prefix is not all numbers.
    if ($prefix !~ /^\d+$/) {
        $checkdigit = 0;
    }
    $length = $length - length($prefix);
    $length -= 1 if ($checkdigit);
    if ($length > 0) {
        my $barcode;
        do {
            my $r = $e->json_query(
                {from => [
                    'actor.generate_barcode',
                    $prefix,
                    $length,
                    $sequence
                ]});
            if ($r && $r->[0] && $r->[0]->{'actor.generate_barcode'}) {
                $barcode = $r->[0]->{'actor.generate_barcode'};
                if ($checkdigit) {
                    $barcode .= $class->calculate_luhn_checkdigit($barcode);
                }
                # Check for duplication.
                my $x = $e->json_query(
                    {
                        select => {ac => ['id']},
                        from => 'ac',
                        where => {
                            barcode => $barcode
                        }
                    }
                );
                undef($barcode) if ($x && $x->[0]);
            } else {
                return undef;
            }
        } until ($barcode);
        return $barcode;
    }
    return undef;
}

# generate a MARC XML document from a MARC XML string
sub marc_xml_to_doc {
    my ($class, $xml) = @_;
    my $marc_doc = XML::LibXML->new->parse_string($xml);
    $marc_doc->documentElement->setNamespace(MARC_NAMESPACE, 'marc', 1);
    $marc_doc->documentElement->setNamespace(MARC_NAMESPACE);
    return $marc_doc;
}



1;

