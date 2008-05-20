package OpenILS::Application::Acq::Picklist;
use base qw/OpenILS::Application/;
use strict; use warnings;

use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Const qw/:const/;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Event;
use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';


__PACKAGE__->register_method(
	method => 'create_picklist',
	api_name	=> 'open-ils.acq.picklist.create',
	signature => {
        desc => 'Creates a new picklist',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Picklist object to create', type => 'object'}
        ],
        return => {desc => 'The ID of the new picklist'}
    }
);

sub create_picklist {
    my($self, $conn, $auth, $picklist) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('CREATE_PICKLIST');
    return OpenILS::Event->new('BAD_PARAMS')
        unless $e->requestor->id == $picklist->owner;
    $e->create_acq_picklist($picklist) or return $e->die_event;
    $e->commit;
    return $picklist->id;
}


__PACKAGE__->register_method(
	method => 'update_picklist',
	api_name	=> 'open-ils.acq.picklist.update',
	signature => {
        desc => 'Updates a new picklist',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Picklist object to update', type => 'object'}
        ],
        return => {desc => '1 on success, Event on error'}
    }
);

sub update_picklist {
    my($self, $conn, $auth, $picklist) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    # don't let them change the owner
    my $o_picklist = $e->retrieve_acq_picklist($picklist->id)
        or return $e->die_event;
    return OpenILS::Event->new('BAD_PARAMS') if (
        $o_picklist->owner != $picklist->owner or
        $picklist->owner != $e->requestor->id );

    $e->update_acq_picklist($picklist) or return $e->die_event;
    $e->commit;
    return 1;
}

__PACKAGE__->register_method(
	method => 'retrieve_picklist',
	api_name	=> 'open-ils.acq.picklist.retrieve',
	signature => {
        desc => 'Retrieves a picklist',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Picklist ID to retrieve', type => 'number'},
            {desc => 'Options hash, including "flesh_lineitem_count" to get the count of attached entries', type => 'hash'},
        ],
        return => {desc => 'Picklist object on success, Event on error'}
    }
);

sub retrieve_picklist {
    my($self, $conn, $auth, $picklist_id, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;

    my $picklist = $e->retrieve_acq_picklist($picklist_id)
        or return $e->event;

    $picklist->entry_count(retrieve_lineitem_count($e, $picklist_id))
        if $$options{flesh_lineitem_count};

    if($e->requestor->id != $picklist->owner) {
        return $e->event unless 
            $e->allowed('VIEW_PICKLIST', undef, $picklist);
    }

    $picklist->owner($e->retrieve_actor_user($picklist->owner)->usrname) 
        if($$options{flesh_username});

    return $picklist;
}


# Returns the number of entries associated with this picklist
sub retrieve_lineitem_count {
    my($e, $picklist_id) = @_;
    my $count = $e->json_query({
        select => { 
            jub => [{transform => 'count', column => 'id', alias => 'count'}]
        }, 
        from => 'jub', 
        where => {picklist => $picklist_id}}
    );
    return $count->[0]->{count};
}



__PACKAGE__->register_method(
	method => 'retrieve_picklist_name',
	api_name	=> 'open-ils.acq.picklist.name.retrieve',
	signature => {
        desc => 'Retrieves a picklist by name.  Owner is implied by the caller',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Picklist name to retrieve', type => 'strin'},
        ],
        return => {desc => 'Picklist object on success, null on not found'}
    }
);

sub retrieve_picklist_name {
    my($self, $conn, $auth, $name) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->search_acq_picklist(
        {name => $name, owner => $e->requestor->id})->[0];
}



__PACKAGE__->register_method(
	method => 'retrieve_user_picklist',
	api_name	=> 'open-ils.acq.picklist.user.retrieve',
    stream => 1,
	signature => {
        desc => 'Retrieves a  user\'s picklists',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Options, including "idlist", whch forces the return
                of a list of IDs instead of objects', type => 'hash'},
        ],
        return => {desc => 'Picklist object on success, Event on error'}
    }
);

sub retrieve_user_picklist {
    my($self, $conn, $auth, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    # don't grab the PL with name == "", because that is the designated temporary picklist
    my $list = $e->search_acq_picklist(
        {owner=>$e->requestor->id, name=>{'!='=>''}},
        {idlist=>1}
    );

    for my $id (@$list) {
        if($$options{idlist}) {
            $conn->respond($id);
        } else {
            my $pl = $e->retrieve_acq_picklist($id);
            $pl->entry_count(retrieve_lineitem_count($e, $id)) if $$options{flesh_lineitem_count};
            $pl->owner($e->retrieve_actor_user($pl->owner)->usrname) if $$options{flesh_username};
            $conn->respond($pl);
        }
    }

    return undef;
}


__PACKAGE__->register_method(
	method => 'retrieve_all_user_picklist',
	api_name	=> 'open-ils.acq.picklist.user.all.retrieve',
    stream => 1,
	signature => {
        desc => 'Retrieves all of the picklists a user is allowed to see',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Options, including "idlist", whch forces the return
                of a list of IDs instead of objects', type => 'hash'},
        ],
        return => {desc => 'Picklist objects on success, Event on error'}
    }
);

sub retrieve_all_user_picklist {
    my($self, $conn, $auth, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;

    my $my_list = $e->search_acq_picklist(
        {owner=>$e->requestor->id, name=>{'!='=>''}}, {idlist=>1});

    my $picklist_ids = $e->objects_allowed('VIEW_PICKLIST', 'acqpl');

    return undef unless @$my_list or @$picklist_ids;

    if($$options{idlist}) {
        return [@$my_list, @$picklist_ids];
    }

    for my $pl (@$my_list, @$picklist_ids) {
        my $picklist = $e->retrieve_acq_picklist($pl) or return $e->event;
        $picklist->entry_count(retrieve_lineitem_count($e, $picklist->id))
            if($$options{flesh_lineitem_count});
        $picklist->owner($e->retrieve_actor_user($picklist->owner)->usrname)
            if $$options{flesh_username};
        $conn->respond($picklist);
    }

    return undef;
}


__PACKAGE__->register_method(
	method => 'delete_picklist',
	api_name	=> 'open-ils.acq.picklist.delete',
	signature => {
        desc => q/Deletes a picklist.  It also deletes any lineitems in the "new" state.  
            Other attached lineitems are detached'/,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Picklist ID to delete', type => 'number'}
        ],
        return => {desc => '1 on success, Event on error'}
    }
);

sub delete_picklist {
    my($self, $conn, $auth, $picklist_id) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    my $picklist = $e->retrieve_acq_picklist($picklist_id)
        or return $e->die_event;
    # don't let anyone delete someone else's picklist
    return OpenILS::Event->new('BAD_PARAMS')
        if $picklist->owner != $e->requestor->id;

    # delete all 'new' lineitems
    my $lis = $e->search_acq_lineitem({picklist => $picklist->id, state => 'new'});
    for my $li (@$lis) {
        $e->delete_acq_lineitem($li) or return $e->die_event;
    }

    # detach all non-'new' lineitems
    $lis = $e->search_acq_lineitem({picklist => $picklist->id, state => {'!=' => 'new'}});
    for my $li (@$lis) {
        $li->clear_picklist;
        $e->update_acq_lineitem($li) or return $e->die_event;
    }

    # remove any picklist-specific object perms
    my $ops = $e->search_permission_usr_object_perm_map({object_type => 'acqpl', object_id => $picklist->id});
    for my $op (@$ops) {
        $e->delete_usr_object_perm_map($op) or return $e->die_event;
    }


    $e->delete_acq_picklist($picklist) or return $e->die_event;
    $e->commit;
    return 1;
}


# ----------------------------------------------------------------
# Picklist Entries
# ----------------------------------------------------------------

__PACKAGE__->register_method(
	method => 'create_lineitem',
	api_name	=> 'open-ils.acq.lineitem.create',
	signature => {
        desc => 'Creates a lineitem',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'The lineitem object to create', type => 'object'},
        ],
        return => {desc => 'ID of newly created lineitem on success, Event on error'}
    }
);

sub create_lineitem {
    my($self, $conn, $auth, $li) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('CREATE_PICKLIST');

    if($li->picklist) {
        my $picklist = $e->retrieve_acq_picklist($li->picklist)
            or return $e->die_event;
        return OpenILS::Event->new('BAD_PARAMS') 
            unless $picklist->owner == $e->requestor->id;
    
        # indicate the picklist was updated
        $picklist->edit_time('now');
        $e->update_acq_picklist($picklist) or return $e->die_event;
    }

    $li->selector($e->requestor->id);
    $e->create_acq_lineitem($li) or return $e->die_event;

    $e->commit;
    return $li->id;
}


__PACKAGE__->register_method(
	method => 'create_lineitem_assets',
	api_name	=> 'open-ils.acq.lineitem.assets.create',
	signature => {
        desc => q/Creates the bibliographic data, volume, and copies associated with a lineitem./,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'The lineitem id', type => 'number'},
            {desc => q/Options hash./}
        ],
        return => {desc => 'ID of newly created bib record, Event on error'}
    }
);

sub create_lineitem_assets {
    my($self, $conn, $auth, $li_id, $options) = @_;
    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;

    my $li = $e->retrieve_acq_lineitem([
        $li_id,
        {   flesh => 1,
            flesh_fields => {jub => ['purchase_order']}
        }
    ]) or return $e->die_event;

    return OpenILS::Event->new('BAD_PARAMS') # make this perm-based, not owner-based
        unless $li->purchase_order->owner == $e->requestor->id;

    # -----------------------------------------------------------------
    # first, create the bib record if necessary
    # -----------------------------------------------------------------
    unless($li->eg_bib_id) {
        my $record = $U->simplereq(
            'open-ils.cat', 
            'open-ils.cat.biblio.record.xml.import',
            $auth, $li->marc, $li->source_label);

        if($U->event_code($record)) {
            $e->rollback;
            return $record;
        }

        $li->eg_bib_id($record->id);
        $e->update_acq_lineitem($li) or return $e->die_event;
    }

    my $li_details = $e->search_acq_lineitem_detail({lineitem => $li_id}, {idlist=>1});

    # -----------------------------------------------------------------
    # for each lineitem_detail, create the volume if necessary, create 
    # a copy, and link them all together.
    # -----------------------------------------------------------------
    my %volcache;
    for my $li_detail_id (@{$li_details}) {

        my $li_detail = $e->retrieve_acq_lineitem_detail($li_detail_id)
            or return $e->die_event;

        my $volume = $volcache{$li_detail->cn_label};
        unless($volume and $volume->owning_lib == $li_detail->owning_lib) {
            my $vol_id = $U->simplereq(
                'open-ils.cat',
                'open-ils.cat.call_number.find_or_create',
                $auth, $li_detail->cn_label, $li->eg_bib_id, $li_detail->owning_lib);
            $volume = $e->retrieve_asset_call_number($vol_id) or return $e->die_event;
            $volcache{$vol_id} = $volume;
        }

        if($U->event_code($volume)) {
            $e->rollback;
            return $volume;
        }

        my $copy = Fieldmapper::asset::copy->new;
        $copy->isnew(1);
        $copy->loan_duration(2);
        $copy->fine_level(2);
        $copy->status(OILS_COPY_STATUS_ON_ORDER);
        $copy->barcode($li_detail->barcode);
        $copy->location($li_detail->location);
        $copy->call_number($volume->id);
        $copy->circ_lib($volume->owning_lib);

        my $stat = $U->simplereq(
            'open-ils.cat',
            'open-ils.cat.asset.copy.fleshed.batch.update', $auth, [$copy]);

        if($U->event_code($stat)) {
            $e->rollback;
            return $stat;
        }

        my $new_copy = $e->search_asset_copy({deleted=>'f', barcode=>$copy->barcode})->[0]
            or return $e->die_event;

        $li_detail->eg_copy_id($new_copy->id);
        $e->update_acq_lineitem_detail($li_detail) or return $e->die_event;
    }

    $e->commit;
    return 1;
}



__PACKAGE__->register_method(
	method => 'retrieve_lineitem',
	api_name	=> 'open-ils.acq.lineitem.retrieve',
	signature => {
        desc => 'Retrieves a lineitem',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'lineitem ID to retrieve', type => 'number'},
            {options => q/Hash of options, including 
                "flesh_attrs", which fleshes the attributes; 
                "flesh_li_details", which fleshes the order details objects/, type => 'hash'},
        ],
        return => {desc => 'lineitem object on success, Event on error'}
    }
);


sub retrieve_lineitem {
    my($self, $conn, $auth, $li_id, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    $options ||= {};

    # XXX finer grained perms...

    my $li;

    if($$options{flesh_attrs}) {
        $li = $e->retrieve_acq_lineitem([
            $li_id, {flesh => 1, flesh_fields => {jub => ['attributes']}}])
            or return $e->event;
    } else {
        $li = $e->retrieve_acq_lineitem($li_id) or return $e->event;
    }

    if($$options{flesh_li_details}) {
        my $ops = {
            flesh => 1,
            flesh_fields => {acqlid => []}
        };
        push(@{$ops->{flesh_fields}->{acqlid}}, 'fund') if $$options{flesh_fund};
        push(@{$ops->{flesh_fields}->{acqlid}}, 'fund_debit') if $$options{flesh_fund_debit};
        my $details = $e->search_acq_lineitem_detail([{lineitem => $li_id}, $ops]);
        $li->lineitem_details($details);
    }

    my $picklist = $e->retrieve_acq_picklist($li->picklist)
        or return $e->event;

    if($picklist->owner != $e->requestor->id) {
        return $e->event unless 
            $e->allowed('VIEW_PICKLIST', undef, $picklist);
    }

    $li->clear_marc if $$options{clear_marc};

    return $li;
}



__PACKAGE__->register_method(
	method => 'delete_lineitem',
	api_name	=> 'open-ils.acq.lineitem.delete',
	signature => {
        desc => 'Deletes a lineitem',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'lineitem ID to delete', type => 'number'},
        ],
        return => {desc => '1 on success, Event on error'}
    }
);

sub delete_lineitem {
    my($self, $conn, $auth, $li_id) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    my $li = $e->retrieve_acq_lineitem($li_id)
        or return $e->die_event;

    my $picklist = $e->retrieve_acq_picklist($li->picklist)
        or return $e->die_event;

    # don't let anyone delete someone else's lineitem
    return OpenILS::Event->new('BAD_PARAMS') 
        if $picklist->owner != $e->requestor->id;

    $e->delete_acq_lineitem($li) or return $e->die_event;
    $e->commit;
    return 1;
}


__PACKAGE__->register_method(
	method => 'update_lineitem',
	api_name	=> 'open-ils.acq.lineitem.update',
	signature => {
        desc => 'Update a lineitem',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'lineitem object update', type => 'object'}
        ],
        return => {desc => '1 on success, Event on error'}
    }
);

sub update_lineitem {
    my($self, $conn, $auth, $li) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    my $orig_li = $e->retrieve_acq_lineitem([
        $li->id,
        {   flesh => 1, # grab the lineitem with picklist attached
            flesh_fields => {jub => ['picklist']}
        }
    ]) or return $e->die_event;

    # don't let anyone update someone else's lineitem
    return OpenILS::Event->new('BAD_PARAMS') 
        if $orig_li->picklist->owner != $e->requestor->id;

    $e->update_acq_lineitem($li) or return $e->die_event;
    $e->commit;
    return 1;
}

__PACKAGE__->register_method(
	method => 'retrieve_pl_lineitem',
	api_name	=> 'open-ils.acq.lineitem.picklist.retrieve',
    stream => 1,
	signature => {
        desc => 'Retrieves lineitem objects according to picklist',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Picklist ID whose entries to retrieve', type => 'number'},
            {desc => q/Options, including 
                "sort_attr", which defines the attribute to sort on; 
                "sort_attr_type", which defines the attribute type sort on; 
                "sort_dir", which defines the sort order between "asc" and "desc";
                "limit", retrieval limit;
                "offset", retrieval offset;
                "idlist", return a list of IDs instead of objects
                "flesh_attrs", additionaly return the list of flattened attributes
                "clear_marc", discards the raw MARC data to reduce data size
                /, 
                type => 'hash'}
        ],
        return => {desc => 'Array of lineitem objects or IDs,  on success, Event on error'}
    }
);


my $PL_ENTRY_JSON_QUERY = {
    select => {jub => ["id"], "acqlia" => ["attr_value"]},
    "from" => {
        "jub" => {
            "acqlia" => {
                "fkey" => "id", 
                "field" => "lineitem", 
                "type" => "left", 
                "filter" => {
                    "attr_type" => "lineitem_marc_attr_definition", 
                    "attr_name" => "author" 
                }
            }
        }
    }, 
    "order_by" => {"acqlia" => {"attr_value" => {"direction"=>"asc"}}}, 
    "limit" => 10,
    "where" => {"+jub" => {"picklist"=>2}},
    "offset" => 0
};

sub retrieve_pl_lineitem {
    my($self, $conn, $auth, $picklist_id, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;

    # collect the retrieval options
    my $sort_attr = $$options{sort_attr} || 'title';
    my $sort_attr_type = $$options{sort_attr_type} || 'lineitem_marc_attr_definition';
    my $sort_dir = $$options{sort_dir} || 'asc';
    my $limit = $$options{limit} || 10;
    my $offset = $$options{offset} || 0;

    $PL_ENTRY_JSON_QUERY->{where}->{'+jub'}->{picklist} = $picklist_id;
    $PL_ENTRY_JSON_QUERY->{from}->{jub}->{acqlia}->{filter}->{attr_name} = $sort_attr;
    $PL_ENTRY_JSON_QUERY->{from}->{jub}->{acqlia}->{filter}->{attr_type} = $sort_attr_type;
    $PL_ENTRY_JSON_QUERY->{order_by}->{acqlia}->{attr_value}->{direction} = $sort_dir;
    $PL_ENTRY_JSON_QUERY->{limit} = $limit;
    $PL_ENTRY_JSON_QUERY->{offset} = $offset;

    my $entries = $e->json_query($PL_ENTRY_JSON_QUERY);

    my @ids;
    push(@ids, $_->{id}) for @$entries;

    for my $id (@ids) {
        if($$options{idlist}) {
            $conn->respond($id);
            next;
        } 

        my $entry;
        my $flesh = ($$options{flesh_attrs}) ? 
            {flesh => 1, flesh_fields => {jub => ['attributes']}} : {};

        $entry = $e->retrieve_acq_lineitem([$id, $flesh]);
        $entry->clear_marc if $$options{clear_marc};
        $conn->respond($entry);
    }

    return undef;
}

=head comment
request open-ils.cstore open-ils.cstore.json_query.atomic {"select":{"jub":[{"transform":"count", "attregate":1, "column":"id","alias":"count"}]}, "from":"jub","where":{"picklist":1}}
=cut

__PACKAGE__->register_method(
	method => 'zsearch',
	api_name => 'open-ils.acq.picklist.search.z3950',
    stream => 1,
	signature => {
        desc => 'Performs a z3950 federated search and creates a picklist and associated lineitems',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Search definition', type => 'object'},
            {desc => 'Picklist name, optional', type => 'string'},
        ]
    }
);

sub zsearch {
    my($self, $conn, $auth, $search, $name) = @_;
    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('CREATE_PICKLIST');

    $search->{limit} ||= 10;

    $name ||= '';
    my $picklist = $e->search_acq_picklist({owner=>$e->requestor->id, name=>$name})->[0];
    if($name eq '' and $picklist) {
        delete_picklist($self, $conn, $auth, $picklist->id);
        $picklist = undef;
    }

    unless($picklist) {
        $picklist = Fieldmapper::acq::picklist->new;
        $picklist->owner($e->requestor->id);
        $picklist->name($name);
        $e->create_acq_picklist($picklist) or return $e->die_event;
    }

    my $ses = OpenSRF::AppSession->create('open-ils.search');
    my $req = $ses->request('open-ils.search.z3950.search_class', $auth, $search);

    while(my $resp = $req->recv(timeout=>60)) {

        my $result = $resp->content;
        use Data::Dumper;
        $logger->info("results = ".Dumper($resp));
        my $count = $result->{count};
        my $total = (($count < $search->{limit}) ? $count : $search->{limit})+1;
        my $ctr = 0;
        $conn->respond({total=>$total, progress=>++$ctr});

        for my $rec (@{$result->{records}}) {
            my $li = Fieldmapper::acq::lineitem->new;
            $li->picklist($picklist->id);
            $li->source_label($result->{service});
            $li->selector($e->requestor->id);
            $li->marc($rec->{marcxml});
            $li->eg_bib_id($rec->{bibid}) if $rec->{bibid};
            $e->create_acq_lineitem($li) or return $e->die_event;
            $conn->respond({total=>$total, progress=>++$ctr});
        }
    }

    return {complete=>1, picklist_id=>$picklist->id};
}

__PACKAGE__->register_method(
	method => 'lineitem_search',
	api_name => 'open-ils.acq.lineitem.search',
    stream => 1,
	signature => {
        desc => 'Searches lineitems',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Search definition', type => 'object'},
            {desc => 'Optoins hash.  idlist=true', type => 'object'},
            {desc => 'List of lineitems', type => 'object/number'},
        ]
    }
);

sub lineitem_search {
    my($self, $conn, $auth, $search, $options) = @_;
    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('CREATE_PICKLIST');
    # XXX needs serious permissions consideration!
    my $pls = $e->search_acq_lineitem($search, {idlist=>$$options{idlist}});
    for my $pl (@$pls) {
        $pl->clear_marc if $$options{clear_marc};
        $conn->respond($_) for $pl;
    }
    return undef;
}




1;
