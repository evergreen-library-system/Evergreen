package OpenILS::Application::Acq::Picklist;
use base qw/OpenILS::Application/;
use strict; use warnings;

use OpenSRF::EX q/:try/;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Const qw/:const/;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Event;
use OpenILS::Application::AppUtils;
use OpenSRF::Utils::Cache;
use MARC::Record;
use MARC::Batch;
use MARC::File::XML (BinaryEncoding => 'UTF-8');
use MIME::Base64;
use Digest::MD5 qw/md5_hex/;
use OpenILS::Application::Acq::Financials;
use DateTime;

my $U = 'OpenILS::Application::AppUtils';


__PACKAGE__->register_method(
    method => 'create_picklist',
    api_name    => 'open-ils.acq.picklist.create',
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
    $picklist->creator($e->requestor->id);
    $picklist->editor($e->requestor->id);
    $picklist->org_unit($e->requestor->ws_ou) unless $picklist->org_unit;
    return $e->die_event unless $e->allowed('CREATE_PICKLIST', $picklist->org_unit);
    return OpenILS::Event->new('BAD_PARAMS')
        unless $e->requestor->id == $picklist->owner;
    $e->create_acq_picklist($picklist) or return $e->die_event;
    $e->commit;
    return $picklist->id;
}


__PACKAGE__->register_method(
    method => 'update_picklist',
    api_name    => 'open-ils.acq.picklist.update',
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
    if($o_picklist->owner != $e->requestor->id) {
        return $e->die_event unless 
            $e->allowed('UPDATE_PICKLIST', $o_picklist->org_unit);
    }
    return OpenILS::Event->new('BAD_PARAMS') unless $o_picklist->org_unit == $picklist->org_unit;

    $picklist->edit_time('now');
    $picklist->editor($e->requestor->id);
    $e->update_acq_picklist($picklist) or return $e->die_event;
    $e->commit;
    return 1;
}

__PACKAGE__->register_method(
    method => 'retrieve_picklist',
    api_name    => 'open-ils.acq.picklist.retrieve',
    authoritative => 1,
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

    return retrieve_picklist_impl($e, $picklist_id, $options);
}

sub retrieve_picklist_impl {
    my ($e, $picklist_id, $options) = @_;
    $options ||= {};

    my $picklist = $e->retrieve_acq_picklist($picklist_id)
        or return $e->event;

    $picklist->entry_count(retrieve_lineitem_count($e, $picklist_id))
        if $$options{flesh_lineitem_count};

    if($e->requestor->id != $picklist->owner) {
        return $e->event unless 
            $e->allowed('VIEW_PICKLIST', $picklist->org_unit, $picklist);
    }

    $picklist->owner($e->retrieve_actor_user($picklist->owner)) 
        if($$options{flesh_owner});
    $picklist->owner($e->retrieve_actor_user($picklist->owner)->usrname) 
        if($$options{flesh_username});
    $picklist->creator($e->retrieve_actor_user($picklist->creator))
        if($$options{flesh_creator});
    $picklist->editor($e->retrieve_actor_user($picklist->editor))
        if($$options{flesh_editor});

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
    api_name    => 'open-ils.acq.picklist.name.retrieve',
    authoritative => 1,
    signature => {
        desc => 'Retrieves a picklist by name.  Owner is implied by the caller',
        params => [
            {desc => 'Authentication token',      type => 'string'},
            {desc => 'Picklist name to retrieve', type => 'string'},
        ],
        return => {desc => 'Picklist object on success, null on not found'}
    }
);

sub retrieve_picklist_name {
    my($self, $conn, $auth, $name) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    my $picklist = $e->search_acq_picklist(
        {name => $name, owner => $e->requestor->id})->[0];
    if($e->requestor->id != $picklist->owner) {
        return $e->event unless 
            $e->allowed('VIEW_PICKLIST', $picklist->org_unit, $picklist);
    }
    return $picklist;
}



__PACKAGE__->register_method(
    method => 'retrieve_user_picklist',
    api_name    => 'open-ils.acq.picklist.user.retrieve',
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
    $options ||= {};

    # don't grab the PL with name == "", because that is the designated temporary picklist
    my $list = $e->search_acq_picklist([
            {
                owner => $e->requestor->id, 
                name => {'!=' => ''}
            }, {
                order_by => $$options{order_by} || {acqpl => 'edit_time DESC'},
                limit => $$options{limit} || 10,
                offset => $$options{offset} || 0,
            }
        ],
        {idlist=>1}
    );

    for my $id (@$list) {
        if($$options{idlist}) {
            $conn->respond($id);
        } else {
            my $pl = $e->retrieve_acq_picklist($id);
            $pl->entry_count(retrieve_lineitem_count($e, $id)) if $$options{flesh_lineitem_count};
            $pl->owner($e->retrieve_actor_user($pl->owner)) if $$options{flesh_owner};
            $pl->owner($e->retrieve_actor_user($pl->owner)->usrname) if $$options{flesh_username};
            $conn->respond($pl);
        }
    }

    return undef;
}


__PACKAGE__->register_method(
    method => 'retrieve_all_user_picklist',
    api_name    => 'open-ils.acq.picklist.user.all.retrieve',
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
    my $p_orgs = $U->user_has_work_perm_at($e, 'VIEW_PICKLIST', {descendants =>1});
    my $picklist_ids_2 = $e->search_acq_picklist(
        {name=>{'!='=>''}, org_unit => $p_orgs}, {idlist=>1});

    return undef unless @$my_list or @$picklist_ids or @$picklist_ids_2;

    my @list = (@$my_list, @$picklist_ids, @$picklist_ids_2);
    my %dedup;
    $dedup{$_} = 1 for @list;
    @list = keys %dedup;

    return \@list if $$options{idlist};

    for my $pl (@list) {
        my $picklist = $e->retrieve_acq_picklist($pl) or return $e->event;
        $picklist->entry_count(retrieve_lineitem_count($e, $picklist->id))
            if($$options{flesh_lineitem_count});
        $picklist->owner($e->retrieve_actor_user($picklist->owner))
            if $$options{flesh_owner};
        $picklist->owner($e->retrieve_actor_user($picklist->owner)->usrname)
            if $$options{flesh_username};
        $conn->respond($picklist);
    }

    return undef;
}

__PACKAGE__->register_method(
    method => 'retrieve_pl_lineitem',
    api_name    => 'open-ils.acq.lineitem.picklist.retrieve',
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
                "flesh_notes", flesh lineitem notes
                "flesh_cancel_reason", flesh cancel_reason
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
    for my $entry (@$entries) {
        push(@ids, $entry->{id}) unless grep { $_ eq $entry->{id} } @ids;
    }

    for my $id (@ids) {
        if($$options{idlist}) {
            $conn->respond($id);
            next;
        } 

        my $entry;
        my $flesh = {};
        if($$options{flesh_attrs} or $$options{flesh_notes} or $$options{flesh_cancel_reason}) {
            $flesh = {flesh => 2, flesh_fields => {jub => []}};
            if($$options{flesh_notes}) {
                push(@{$flesh->{flesh_fields}->{jub}}, 'lineitem_notes');
                $flesh->{flesh_fields}->{acqlin} = ['alert_text'];
            }
            push(@{$flesh->{flesh_fields}->{jub}}, 'attributes') if $$options{flesh_attrs};
            push @{$flesh->{flesh_fields}->{jub}}, 'cancel_reason' if $$options{flesh_cancel_reason};
        }

        $entry = $e->retrieve_acq_lineitem([$id, $flesh]);
        my $details = $e->search_acq_lineitem_detail({lineitem => $id}, {idlist=>1});
        $entry->item_count(scalar(@$details));
        $entry->clear_marc if $$options{clear_marc};
        $conn->respond($entry);
    }

    return undef;
}

=head1 comment

request open-ils.cstore open-ils.cstore.json_query.atomic {"select":{"jub":[{"transform":"count", "attregate":1, "column":"id","alias":"count"}]}, "from":"jub","where":{"picklist":1}}

=cut



__PACKAGE__->register_method(
    method    => "record_distribution_formula_application",
    api_name  => "open-ils.acq.distribution_formula.record_application",
    signature => {
        desc  => "Record the application (which actually happens on the " .
            "client side) of a distribution formula to a PO or a PL",
        params => [
            {desc => "Authentication token", type => "string"},
            {desc => "Formulae applied", "type" => "array"},
            {desc => "Lineitem ID", "type" => "number"}
        ],
        return => {desc => "acqdfa IDs on success; event on failure"}
    }
);

sub record_distribution_formula_application {
    my ($self, $conn, $auth, $formulae, $li_id) = @_;

    my $e = new_editor("authtoken" => $auth, "xact" => 1);
    return $e->die_event unless $e->checkauth;

    # We need this to determine relevant OU for testing permissions...
    my $li = $e->retrieve_acq_lineitem([
        $li_id, {
            "flesh" => 1,
            "flesh_fields" => {"jub" => [qw/purchase_order picklist/]}
        }
    ]) or return $e->die_event;

    # ... which we do here.
    my $ou;
    if ($li->purchase_order) {
        $ou = $li->purchase_order->ordering_agency;
    } elsif ($li->picklist) {
        $ou = $li->picklist->org_unit;
    } else {
        $e->rollback;
        return new OpenILS::Event("BAD_PARAMS");
    }

    return $e->die_event unless $e->allowed("CREATE_PURCHASE_ORDER", $ou);

    # Just deal with it if $formulate is a scalar instead of an array.
    $formulae = [ $formulae ] if not ref $formulae;

    my @results = ();
    foreach (@{$formulae}) {
        my $acqdfa = new Fieldmapper::acq::distribution_formula_application;

        $acqdfa->creator($e->requestor->id);
        $acqdfa->formula($_);
        $acqdfa->lineitem($li_id);

        $acqdfa = $e->create_acq_distribution_formula_application($acqdfa)
            or return $e->die_event;
        push @results, $acqdfa->id;
    }

    $e->commit or return $e->die_event;
    \@results;
}


__PACKAGE__->register_method(
    method => 'ranged_distrib_formulas',
    api_name    => 'open-ils.acq.distribution_formula.ranged.retrieve',
    stream => 1,
    signature => {
        desc => 'Ranged distribution formulas, fleshed with entries',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => "offset", type => "number"},
            {desc => "limit", type => "number"}
        ],
        return => {desc => 'List of distribution formulas'}
    }
);

sub ranged_distrib_formulas {
    my ($self, $conn, $auth, $offset, $limit) = @_;

    $offset ||= 0;
    $limit ||= 10;

    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    my $orgs = $U->user_has_work_perm_at($e, 'CREATE_PICKLIST', {descendants =>1});

    my $forms = $e->search_acq_distribution_formula([
        {owner => $orgs},
        {
            flesh => 1, 
            flesh_fields => {acqdf => ['entries']},
            order_by => {acqdf => "name"},
            limit => $limit,
            offset => $offset
        }
    ]) or return $e->die_event;

    for (@$forms) {

        # how many times has this DF been used
        my $count = $e->json_query({
            select => {acqdfa => [{column => 'formula', aggregate => 1, transform => 'count', alias => 'count'}]}, 
            from => 'acqdfa', 
            where => {formula => $_->id}
        })->[0];

        $_->use_count($count->{count});
        $conn->respond($_);
    }

    return undef;
}

__PACKAGE__->register_method(
    method => "ranged_distrib_formula_applications",
    api_name => "open-ils.acq.distribution_formula_application.ranged.retrieve",
    stream => 1,
    signature => {
        desc => "Ranged distribution formulas applications, fleshed with formulas and users",
        params => [
            {desc => "Authentication token", type => "string"},
            {desc => "Lineitem Id", type => "number"}
        ],
        return => {desc => "List of distribution formula applications"}
    }
);

sub ranged_distrib_formula_applications {
    my ($self, $conn, $auth, $li_id) = @_;

    my $e = new_editor("authtoken" => $auth);
    return $e->event unless $e->checkauth;

    my $li = $e->retrieve_acq_lineitem([
        $li_id, {
            "flesh" => 1,
            "flesh_fields" => {"jub" => [qw/purchase_order picklist/]}
        }
    ]) or return $e->die_event;

    if ($li->picklist) {
        return $e->die_event unless $e->allowed(
            "VIEW_PICKLIST", $li->picklist->org_unit
        );
    } elsif ($li->purchase_order) {
        return $e->die_event unless $e->allowed(
            "VIEW_PURCHASE_ORDER", $li->purchase_order->ordering_agency
        );
    } else {
        # For the moment no use cases are forseen for using this
        # method with LIs that don't belong to a PL or a PO.
        $e->disconnect;
        return new OpenILS::Event("BAD_PARAMS", "note" => "Freestanding LI");
    }

    my $dfa = $e->search_acq_distribution_formula_application([
        {"lineitem" => $li_id},
        {"flesh" => 1, "flesh_fields" => {"acqdfa" => [qw/formula creator/]}}
    ]);

    $conn->respond($_) foreach (@$dfa);

    $e->disconnect;
    undef;
}

1;
