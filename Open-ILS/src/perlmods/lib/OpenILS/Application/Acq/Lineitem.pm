package OpenILS::Application::Acq::Lineitem;
use base qw/OpenILS::Application/;
use strict; use warnings;

use OpenILS::Event;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Const qw/:const/;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Application::AppUtils;
use OpenILS::Application::Acq::Financials;
use OpenILS::Application::Cat::BibCommon;
use OpenILS::Application::Cat::AssetCommon;
my $U = 'OpenILS::Application::AppUtils';


__PACKAGE__->register_method(
    method    => 'create_lineitem',
    api_name  => 'open-ils.acq.lineitem.create',
    signature => {
        desc   => 'Creates a lineitem',
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


    if($li->picklist) {
        my $picklist = $e->retrieve_acq_picklist($li->picklist)
            or return $e->die_event;

        if($picklist->owner != $e->requestor->id) {
            return $e->die_event unless 
                $e->allowed('CREATE_PICKLIST', $picklist->org_unit, $picklist);
        }
    
        # indicate the picklist was updated
        $picklist->edit_time('now');
        $picklist->editor($e->requestor->id);
        $e->update_acq_picklist($picklist) or return $e->die_event;
    }

    if($li->purchase_order) {
        my $po = $e->retrieve_acq_purchase_order($li->purchase_order)
            or return $e->die_event;
        return $e->die_event unless 
            $e->allowed('MANAGE_PROVIDER', $po->ordering_agency, $po);

        $li->provider($po->provider) unless defined $li->provider;
    }

    $li->selector($e->requestor->id);
    $e->create_acq_lineitem($li) or return $e->die_event;

    $e->commit;
    return $li->id;
}


__PACKAGE__->register_method(
    method    => 'retrieve_lineitem',
    api_name  => 'open-ils.acq.lineitem.retrieve',
    authoritative => 1,
    signature => {
        desc   => 'Retrieves a lineitem',
        params => [
            {desc => 'Authentication token',    type => 'string'},
            {desc => 'lineitem ID to retrieve', type => 'number'},
            {options => q/Hash of options, including:
flesh_attrs         : for attributes,
flesh_notes         : for notes,
flesh_cancel_reason : for cancel reason,
flesh_li_details    : for order details objects,
clear_marc          : to clear marcxml from lineitem/, type => 'hash'},
        ],
        return => {desc => 'lineitem object on success, Event on error'}
    }
);


sub retrieve_lineitem {
    my($self, $conn, $auth, $li_id, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    return retrieve_lineitem_impl($e, $li_id, $options);
}

sub retrieve_lineitem_impl {
    my ($e, $li_id, $options, $no_auth) = @_;   # no_auth needed for EDI scripts
    $options ||= {};

    my $flesh = {
        flesh => 3,
        flesh_fields => {
            jub => ['purchase_order', 'picklist'], # needed for permission check
            acqlid => [],
            acqlin => []
        }
    };

    my $fields = $flesh->{flesh_fields};

    push(@{$fields->{jub}   },    'attributes') if $$options{flesh_attrs};
    push(@{$fields->{jub}   },'lineitem_notes') if $$options{flesh_notes};
    push(@{$fields->{acqlin}},    'alert_text') if $$options{flesh_notes};
    push(@{$fields->{jub}   }, 'order_summary') if $$options{flesh_order_summary};
    push(@{$fields->{jub}   }, 'cancel_reason') if $$options{flesh_cancel_reason};

    if($$options{flesh_li_details}) {
        push(@{$fields->{jub}   }, 'lineitem_details');
        push(@{$fields->{acqlid}}, 'fund'         ) if $$options{flesh_fund};
        push(@{$fields->{acqlid}}, 'fund_debit'   ) if $$options{flesh_fund_debit};
        push(@{$fields->{acqlid}}, 'cancel_reason') if $$options{flesh_cancel_reason};
    }

    if($$options{clear_marc}) { # avoid fetching marc blob
        my @fields = grep { $_ ne 'marc' } Fieldmapper::acq::lineitem->new->real_fields;
        $flesh->{select} = {jub => [@fields]};
    }

    my $li = $e->retrieve_acq_lineitem([$li_id, $flesh]) or return $e->event;

    # collect the # of lids
    if($$options{flesh_li_details}) {
        $li->item_count(scalar(@{$li->lineitem_details}));
    } else {
        my $details = $e->search_acq_lineitem_detail({lineitem => $li_id}, {idlist=>1});
        $li->item_count(scalar(@$details));
    }

    # attach claims to LIDs
    if($$options{flesh_li_details}) {
        foreach (@{$li->lineitem_details}) {
            $_->claims(
                $e->search_acq_claim([
                    {"lineitem_detail", $_->id}, {
                        "flesh" => 1, "flesh_fields" => {"acqcl" => ["type"]}
                    }
                ])
            );
        }
    }

    return $e->event unless ((
        $li->purchase_order and 
            ($no_auth or $e->allowed(['VIEW_PURCHASE_ORDER', 'CREATE_PURCHASE_ORDER'], 
                $li->purchase_order->ordering_agency, $li->purchase_order))
        ) or (
        $li->picklist and !$li->purchase_order and # user doesn't have view_po perms
            ($no_auth or $e->allowed(['VIEW_PICKLIST', 'CREATE_PICKLIST'], 
                $li->picklist->org_unit, $li->picklist))
    ));

    unless ($$options{flesh_po}) {
        $li->purchase_order(
            $li->purchase_order ? $li->purchase_order->id : undef
        );
    }
    unless ($$options{flesh_pl}) {
        $li->picklist($li->picklist ? $li->picklist->id : undef);
    }
    return $li;
}



__PACKAGE__->register_method(
    method    => 'delete_lineitem',
    api_name  => 'open-ils.acq.lineitem.delete',
    signature => {
        desc   => 'Deletes a lineitem',
        params => [
            {desc => 'Authentication token',  type => 'string'},
            {desc => 'lineitem ID to delete', type => 'number'},
        ],
        return => {desc => '1 on success, Event on error'}
    }
);

__PACKAGE__->register_method(
    method    => 'delete_lineitem',
    api_name  => 'open-ils.acq.purchase_order.lineitem.delete',
    signature => {
        desc   => 'Deletes a lineitem from a purchase order',
        params => [
            {desc => 'Authentication token',  type => 'string'},
            {desc => 'lineitem ID to delete', type => 'number'},
        ],
        return => {desc => '1 on success, Event on error'}
    }
);

__PACKAGE__->register_method(
    method    => 'delete_lineitem',
    api_name  => 'open-ils.acq.picklist.lineitem.delete',
    signature => {
        desc   => 'Deletes a lineitem from a picklist',
        params => [
            {desc => 'Authentication token',  type => 'string'},
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

    # XXX check state

    if($li->picklist) {
        my $picklist = $e->retrieve_acq_picklist($li->picklist)
            or return $e->die_event;
        return OpenILS::Event->new('BAD_PARAMS') 
            if $picklist->owner != $e->requestor->id;
    } else {
        # check PO perms
    }

    # once a LI is attached to a PO, deleting it
    # from a picklist means *detaching* it from the picklist
    if ($self->api_name =~ /picklist/ && $li->purchase_order) {
        $li->clear_picklist;
        my $evt = update_lineitem_impl($e, $li);
        return $evt if $evt;
        $e->commit;
        return 1;
    }

    # delete the attached lineitem_details
    my $lid_ids = $e->search_acq_lineitem_detail(
        {lineitem => $li_id}, {idlist=>1});

    for my $lid_id (@$lid_ids) {
        $e->delete_acq_lineitem_detail(
            $e->retrieve_acq_lineitem_detail($lid_id))
            or return $e->die_event;
    }

    $e->delete_acq_lineitem($li) or return $e->die_event;
    $e->commit;
    return 1;
}


__PACKAGE__->register_method(
    method    => 'update_lineitem',
    api_name  => 'open-ils.acq.lineitem.update',
    signature => {
        desc   => 'Update one or many lineitems',
        params => [
            {desc => 'Authentication token',   type => 'string'},
            {desc => 'lineitem object update', type => 'object'}
        ],
        return => {desc => '1 on success, Event on error'}
    }
);

sub update_lineitem {
    my($self, $conn, $auth, $li) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    $li = [$li] unless ref $li eq "ARRAY";
    foreach (@$li) {
        my $evt = update_lineitem_impl($e, $_);
        return $evt if $evt;
    }

    $e->commit;
    return 1;
}

sub update_lineitem_impl {
    my($e, $li) = @_;

    my $orig_li = $e->retrieve_acq_lineitem([
        $li->id,
        {   flesh => 1, # grab the lineitem with picklist attached
            flesh_fields => {jub => ['picklist', 'purchase_order']}
        }
    ]) or return $e->die_event;

    # the marc may have been cleared on retrieval...
    $li->marc($orig_li->marc) unless $li->marc;

    $li->editor($e->requestor->id);
    $li->edit_time('now');
    $e->update_acq_lineitem($li) or return $e->die_event;
    return undef;
}

__PACKAGE__->register_method(
	method => 'lineitem_search',
	api_name => 'open-ils.acq.lineitem.search',
    stream => 1,
	signature => {
        desc => 'Searches lineitems',
        params => [
            {desc => 'Authentication token',       type => 'string'},
            {desc => 'Search definition',          type => 'object'},
            {desc => 'Options hash.  idlist=true', type => 'object'},
            {desc => 'List of lineitems',          type => 'object/number'},
        ]
    }
);

sub lineitem_search {
    my($self, $conn, $auth, $search, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('CREATE_PICKLIST');
    # XXX needs permissions consideration
    my $lis = $e->search_acq_lineitem($search, {idlist=>1});
    for my $li_id (@$lis) {
        if($$options{idlist}) {
            $conn->respond($li_id);
        } else {
            my $res = retrieve_lineitem($self, $conn, $auth, $li_id, $options);
            $conn->respond($res) unless $U->event_code($res);
        }
    }
    return undef;
}

__PACKAGE__->register_method (
    method    => 'lineitems_related_by_bib',
    api_name  => 'open-ils.acq.lineitems_for_bib.by_bib_id',
    stream    => 1,
    signature => q/
        Retrieves lineitems attached to same bib record, subject to the PO ordering agency.  This variant takes the bib id.
        @param authtoken Login session key
        @param bib_id Id for the pertinent bib record.
        @param options Object for tweaking the selection criteria and fleshing options.
    /
);

__PACKAGE__->register_method (
    method    => 'lineitems_related_by_bib',
    api_name  => 'open-ils.acq.lineitems_for_bib.by_lineitem_id',
    stream    => 1,
    signature => q/
        Retrieves lineitems attached to same bib record, subject to the PO ordering agency.  This variant takes the id for any of the pertinent lineitems.
        @param authtoken Login session key
        @param bib_id Id for a pertinent lineitem.
        @param options Object for tweaking the selection criteria and fleshing options.
    /
);

__PACKAGE__->register_method (
    method    => 'lineitems_related_by_bib',
    api_name  => 'open-ils.acq.lineitems_for_bib.by_lineitem_id.count',
    stream    => 1,
    signature => q/See open-ils.acq.lineitems_for_bib.by_lineitem_id. This version returns numbers of lineitems only (XXX may count lineitems we don't actually have permission to retrieve)/
);

sub lineitems_related_by_bib {
    my($self, $conn, $auth, $test_value, $options) = @_;
    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    my $perm_orgs = $U->user_has_work_perm_at($e, 'VIEW_PURCHASE_ORDER', {descendants =>1}, $e->requestor->id);

    my $query = {
        "select"=>{"jub"=>["id"]},
        "from"=>{"jub" => {"acqpo" => {type => 'left'}, "acqpl" => {type => 'left'}}}, 
        "where"=>{
            '-or' => [
                { "+acqpo"=>{ "ordering_agency" => $perm_orgs } },
                { '+acqpl' => { org_unit => $perm_orgs } }
            ]
        },
        "order_by"=>[{"class"=>"jub", "field"=>"create_time", "direction"=>"desc"}]
    };

    # Be sure we just return the original LI if no related bibs
    if ($self->api_name =~ /by_lineitem_id/) {
        my $orig = retrieve_lineitem($self, $conn, $auth, $test_value) or
            return $e->die_event;
        if ($test_value = $orig->eg_bib_id) {
            $query->{"where"}->{"eg_bib_id"} = $test_value;
        } else {
            $query->{"where"}->{"id"} = $orig->id;
        }
    } elsif ($test_value) {
        $query->{"where"}->{"eg_bib_id"} = $test_value;
    } else {
        $e->disconnect;
        return new OpenILS::Event("BAD_PARAMS", "Null bib id");
    }

    if ($options && defined $options->{lineitem_state}) {
        $query->{'where'}{'jub'}{'state'} = $options->{lineitem_state};
    }

    if ($options && defined $options->{po_state}) {
        $query->{'where'}{'+acqpo'}{'state'} = $options->{po_state};
    }

    if ($options && defined $options->{order_by}) {
        $query->{'order_by'} = $options->{order_by};
    }

    my $results = $e->json_query($query);
    if ($self->api_name =~ /count$/) {
        return scalar(@$results);
    } else {
        for my $result (@$results) {
            # retrieve_lineitem takes care of POs and PLs and also handles
            # options like flesh_notes and permissions checking.
            $conn->respond(
                retrieve_lineitem($self, $conn, $auth, $result->{"id"}, $options)
            );
        }
    }

    return undef;
}


__PACKAGE__->register_method(
    method    => "lineitem_search_by_attributes",
    api_name  => "open-ils.acq.lineitem.search.by_attributes",
    stream    => 1,
    signature => {
        desc   => "Performs a search against lineitem_attrs",
        params => [
            {desc => "Authentication token", type => "string"},
            {   desc => q/
Search definition:
    attr_value_pairs : list of pairs of (attr definition ID, attr value) where value can be scalar (fuzzy match) or array (exact match)
    li_states        : list of lineitem states
    po_agencies      : list of purchase order ordering agencies (org) ids

At least one of these search terms is required.
                /,
                type => "object"},
            {   desc => q/
Options hash:
    idlist      : if set, only return lineitem IDs
    clear_marc  : if set, strip the MARC xml from the lineitem before delivery
    flesh_attrs : flesh lineitem attributes;
                /,
                type => "object"}
        ]
    }
);

__PACKAGE__->register_method(
    method    => "lineitem_search_by_attributes",
    api_name  => "open-ils.acq.lineitem.search.by_attributes.ident",
    stream    => 1,
    signature => {
        desc => "Performs a search against lineitem_attrs where ident is true.  ".
            "See open-ils.acq.lineitem.search.by_attributes for params."
    }
);

sub lineitem_search_by_attributes {
    my ($self, $conn, $auth, $search, $options) = @_;

    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;
    # XXX needs permissions consideration

    return [] unless $search;
    my $attr_value_pairs = $search->{attr_value_pairs};
    my $li_states = $search->{li_states};
    my $po_agencies = $search->{po_agencies}; # XXX if none, base it on perms

    my $query = {
        "select" => {"acqlia" =>
            [{"column" => "lineitem", "transform" => "distinct"}]
        },
        "from" => {
            "acqlia" => {
                "acqliad" => {"field" => "id", "fkey" => "definition"},
                "jub" => {
                    "field" => "id",
                    "fkey" => "lineitem",
                    "join" => {
                        "acqpo" => {
                            "type" => "left",
                            "field" => "id",
                            "fkey" => "purchase_order"
                        }
                    }
                }
            }
        }
    };

    my $where = {};
    $where->{"+acqliad"} = {"ident" => "t"}
        if $self->api_name =~ /\.ident/;

    my $searched_for_something = 0;

    if (ref $attr_value_pairs eq "ARRAY") {
        $where->{"-or"} = [];
        foreach (@$attr_value_pairs) {
            next if @$_ != 2;
            my ($def, $value) = @$_;
            push @{$where->{"-or"}}, {
                "-and" => {
                    "attr_value" => (ref $value) ?
                        $value : {"ilike" => "%" . $value . "%"},
                    "definition" => $def
                }
            };
        }
        $searched_for_something = 1;
    }

    if ($li_states and @$li_states) {
        $where->{"+jub"} = {"state" => $li_states};
        $searched_for_something = 1;
    }

    if ($po_agencies and @$po_agencies) {
        $where->{"+acqpo"} = {"ordering_agency" => $po_agencies};
        $searched_for_something = 1;
    }

    if (not $searched_for_something) {
        $e->rollback;
        return new OpenILS::Event(
            "BAD_PARAMS", note => "You have provided no search terms."
        );
    }

    $query->{"where"} = $where;
    my $lis = $e->json_query($query);

    for my $li_id_obj (@$lis) {
        my $li_id = $li_id_obj->{"lineitem"};
        if($options->{"idlist"}) {
            $conn->respond($li_id);
        } else {
            $conn->respond(
                retrieve_lineitem($self, $conn, $auth, $li_id, $options)
            );
        }
    }
    undef;
}


__PACKAGE__->register_method(
	method    => 'lineitem_search_ident',
	api_name  => 'open-ils.acq.lineitem.search.ident',
    stream    => 1,
	signature => {
        desc => 'Performs a search against lineitem_attrs where ident is true',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {   desc => q/Search definition. Options are:
                   attr_values : list of attribute values (required)
                   li_states : list of lineitem states
                   po_agencies : list of purchase order ordering agencies (org) ids
                /,
                type => 'object',
            },
            {   desc => q/
                    Options hash.  Options are:
                        idlist : if set, only return lineitem IDs
                        clear_marc : if set, strip the MARC xml from the lineitem before delivery
                        flesh_attrs : flesh lineitem attributes; 
                /,
                type => 'object',
            }
        ]
    }
);

my $LI_ATTR_SEARCH = {
    select => { acqlia => ['lineitem'] },
    from   => {
        acqlia => {
            acqliad => {
                field => 'id',
                fkey  => 'definition'
            },
            jub => {
                field => 'id',
                fkey  => 'lineitem',
                join  => {
                    acqpo => {
                        field => 'id',
                        fkey  => 'purchase_order'
                    }
                }
            }
        }
    }
};

sub lineitem_search_ident {
    my($self, $conn, $auth, $search, $options) = @_;
    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->event unless $e->checkauth;
    # XXX needs permissions consideration

    return [] unless $search;
    my $attr_values = $search->{attr_values};
    my $li_states = $search->{li_states};
    my $po_agencies = $search->{po_agencies}; # XXX if none, base it on perms

    my $where_clause = {
        '-or' => [],
        '+acqlia' => {
            '+acqliad' => {ident => 't'},
        }
    };

    push(@{$where_clause->{'-or'}}, {attr_value => {ilike => "%$_%"}}) for @$attr_values;

    $where_clause->{'+jub'} = {state => {in => $li_states}}
        if $li_states and @$li_states;

    $where_clause->{'+acqpo'} = {ordering_agency => $po_agencies} 
        if $po_agencies and @$po_agencies;

    $LI_ATTR_SEARCH->{where} = $where_clause;

    my $lis = $e->json_query($LI_ATTR_SEARCH);

    for my $li_id_obj (@$lis) {
        my $li_id = $li_id_obj->{lineitem};
        if($$options{idlist}) {
            $conn->respond($li_id);
        } else {
            my $li;
            if($$options{flesh_attrs}) {
                $li = $e->retrieve_acq_lineitem([
                    $li_id, {flesh => 1, flesh_fields => {jub => ['attributes']}}])
            } else {
                $li = $e->retrieve_acq_lineitem($li_id);
            }
            $li->clear_marc if $$options{clear_marc};
            $conn->respond($li);
        }
    }
    return undef;
}


__PACKAGE__->register_method(
    method    => 'retrieve_lineitem_detail',
    api_name  => 'open-ils.acq.lineitem_detail.retrieve',
    authoritative => 1,
    signature => {
        desc   => q/Updates a lineitem detail/,
        params => [
            { desc => 'Authentication token',              type => 'string' },
            { desc => 'id of lineitem_detail to retrieve', type => 'number' },
        ],
        return => { desc => 'object on success, Event on failure' }
    }
);
sub retrieve_lineitem_detail {
    my($self, $conn, $auth, $li_detail_id) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;

    my $li_detail = $e->retrieve_acq_lineitem_detail($li_detail_id)
        or return $e->event;

    if($li_detail->fund) {
        my $fund = $e->retrieve_acq_fund($li_detail->fund) or return $e->event;
        return $e->event unless 
            $e->allowed('MANAGE_FUND', $fund->org, $fund);
    }

    # XXX check lineitem perms
    return $li_detail;
}


__PACKAGE__->register_method(
    method    => 'approve_lineitem',
    api_name  => 'open-ils.acq.lineitem.approve',
    signature => {
        desc   => 'Mark a lineitem as approved',
        params => [
            { desc => 'Authentication token', type => 'string' },
            { desc => 'lineitem ID',          type => 'number' }
        ],
        return => { desc => '1 on success, Event on error' }
    }
);
sub approve_lineitem {
    my($self, $conn, $auth, $li_id) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    # XXX perm checks for each lineitem detail

    my $li = $e->retrieve_acq_lineitem($li_id)
        or return $e->die_event;

    return OpenILS::Event->new('ACQ_LINEITEM_APPROVED', payload => $li_id)
        if $li->state eq 'approved';

    my $details = $e->search_acq_lineitem_detail({lineitem => $li_id});
    return OpenILS::Event->new('ACQ_LINEITEM_NO_COPIES', payload => $li_id)
        unless scalar(@$details) > 0;

    for my $detail (@$details) {
        return OpenILS::Event->new('ACQ_LINEITEM_DETAIL_NO_FUND', payload => $detail->id)
            unless $detail->fund;

        return OpenILS::Event->new('ACQ_LINEITEM_DETAIL_NO_ORG', payload => $detail->id)
            unless $detail->owning_lib;
    }
    
    $li->state('approved');
    $li->edit_time('now');
    $e->update_acq_lineitem($li) or return $e->die_event;

    $e->commit;
    return 1;
}



__PACKAGE__->register_method(
    method    => 'set_lineitem_attr',
    api_name  => 'open-ils.acq.lineitem_usr_attr.set',
    signature => {
        desc   => 'Sets a lineitem_usr_attr value',
        params => [
            { desc => 'Authentication token', type => 'string' },
            { desc => 'Lineitem ID',          type => 'number' },
            { desc => 'Attr name',            type => 'string' },
            { desc => 'Attr value',           type => 'string' }
        ],
        return => { desc => '1 on success, Event on error' }
    }
);

__PACKAGE__->register_method(
    method    => 'set_lineitem_attr',
    api_name  => 'open-ils.acq.lineitem_local_attr.set',
    signature => {
        desc   => 'Sets a lineitem_local_attr value',
        params => [
            { desc => 'Authentication token', type => 'string' },
            { desc => 'Lineitem ID',          type => 'number' },
            { desc => 'Attr name',            type => 'string' },
            { desc => 'Attr value',           type => 'string' }
        ],
        return => { desc => 'ID of the attr object on success, Event on error' }
    }
);


sub set_lineitem_attr {
    my($self, $conn, $auth, $li_id, $attr_name, $attr_value) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    # XXX perm

    my $attr_type = $self->api_name =~ /local_attr/ ?
        'lineitem_local_attr_definition' : 'lineitem_usr_attr_definition';

    my $attr = $e->search_acq_lineitem_attr({
        lineitem => $li_id, 
        attr_type => $attr_type,
        attr_name => $attr_name})->[0];

    my $find = "search_acq_$attr_type";

    if($attr) {
        $attr->attr_value($attr_value);
        $e->update_acq_lineitem_attr($attr) or return $e->die_event;
    } else {
        $attr = Fieldmapper::acq::lineitem_attr->new;
        $attr->lineitem($li_id);
        $attr->attr_type($attr_type);
        $attr->attr_name($attr_name);
        $attr->attr_value($attr_value);

        my $attr_def_id = $e->$find({code => $attr_name}, {idlist=>1})->[0] 
            or return $e->die_event;
        $attr->definition($attr_def_id);
        $e->create_acq_lineitem_attr($attr) or return $e->die_event;
    }

    $e->commit;
    return $attr->id;
}

__PACKAGE__->register_method(
    method    => 'get_lineitem_attr_defs',
    api_name  => 'open-ils.acq.lineitem_attr_definition.retrieve.all',
    authoritative => 1,
    signature => {
        desc   => 'Retrieve lineitem attr definitions',
        params => [ { desc => 'Authentication token', type => 'string' }, ],
        return => { desc => 'List of attr definitions' }
    }
);

sub get_lineitem_attr_defs {
    my($self, $conn, $auth) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    my %results;
    for my $type (qw/generated marc local usr provider/) {
        my $call = "retrieve_all_acq_lineitem_${type}_attr_definition";
        $results{$type} = $e->$call;
    }
    return \%results;
}


__PACKAGE__->register_method(
    method    => 'lineitem_note_CUD_batch',
    api_name  => 'open-ils.acq.lineitem_note.cud.batch',
    stream    => 1,
    signature => {
        desc   => q/Manage lineitem notes/,
        params => [
            { desc => 'Authentication token',             type => 'string' },
            { desc => 'List of lineitem_notes to manage', type => 'array'  },
        ],
        return =>
          { desc => 'Streaming response of current position in the array' }
    }
);

sub lineitem_note_CUD_batch {
    my($self, $conn, $auth, $li_notes) = @_;

    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    # XXX perms

    my $total = @$li_notes;
    my $count = 0;

    for my $note (@$li_notes) {

        $note->editor($e->requestor->id);
        $note->edit_time('now');

        if($note->isnew) {
            $note->creator($e->requestor->id);
            $note = $e->create_acq_lineitem_note($note) or return $e->die_event;

        } elsif($note->isdeleted) {
            $e->delete_acq_lineitem_note($note) or return $e->die_event;

        } elsif($note->ischanged) {
            $e->update_acq_lineitem_note($note) or return $e->die_event;
        }

        if(!$note->isdeleted) {
            $note = $e->retrieve_acq_lineitem_note([
                $note->id, {
                    "flesh" => 1, "flesh_fields" => {"acqlin" => ["alert_text"]}
                }
            ]);
        }

        $conn->respond({maximum => $total, progress => ++$count, note => $note});
    }

    $e->commit;
    return {complete => 1};
}

__PACKAGE__->register_method(
    method => 'ranged_line_item_alert_text',
    api_name => 'open-ils.acq.line_item_alert_text.ranged.retrieve.all');   # TODO: signature

sub ranged_line_item_alert_text {
    my($self, $conn, $auth, $org_id, $depth) = @_;
    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('ADMIN_ACQ_LINEITEM_ALERT_TEXT', $org_id);
    return $e->search_acq_lineitem_alert_text(
        {owning_lib => $U->get_org_full_path($org_id, $depth)});
}


__PACKAGE__->register_method(
    method => "retrieve_lineitem_by_copy_id",
    api_name => "open-ils.acq.lineitem.retrieve.by_copy_id",
    authoritative => 1,
    signature => {
        desc => q/Manage lineitem notes/,
        params => [
            {desc => "Authentication token", type => "string"},
            {desc => "Evergreen internal copy ID", type => "number"},
            {desc => "Hash of options (see open-ils.acq.lineitem.retrieve",
                type => "object"}
        ],
        return => {
            desc => "Lineitem associated with given copy",
            type => "object", class => "jub"
        }
    }
);

sub retrieve_lineitem_by_copy_id {
    my ($self, $conn, $auth, $object_id, $options) = @_;

    my $e = new_editor("authtoken" => $auth);
    return $e->die_event unless $e->checkauth;

    my $result = $e->json_query({
        "select" => {"acqlid" => ["lineitem"]},
        "from" => "acqlid",
        "where" => {"eg_copy_id" => $object_id}
    })->[0] or do {
        $e->disconnect;
        return new OpenILS::Event("ACQ_LINEITEM_NOT_FOUND");
    };

    my $li = retrieve_lineitem_impl($e, $result->{"lineitem"}, $options) or
        return $e->die_event;

    $e->disconnect;
    return $li;
}

1;
