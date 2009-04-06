package OpenILS::Application::Acq::Financials;
use base qw/OpenILS::Application/;
use strict; use warnings;

use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Const qw/:const/;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Event;
use OpenILS::Application::AppUtils;
use OpenILS::Application::Acq::Lineitem;
my $U = 'OpenILS::Application::AppUtils';

# ----------------------------------------------------------------------------
# Funding Sources
# ----------------------------------------------------------------------------

__PACKAGE__->register_method(
	method => 'create_funding_source',
	api_name	=> 'open-ils.acq.funding_source.create',
	signature => {
        desc => 'Creates a new funding_source',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'funding source object to create', type => 'object'}
        ],
        return => {desc => 'The ID of the new funding_source'}
    }
);

sub create_funding_source {
    my($self, $conn, $auth, $funding_source) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('ADMIN_FUNDING_SOURCE', $funding_source->owner);
    $e->create_acq_funding_source($funding_source) or return $e->die_event;
    $e->commit;
    return $funding_source->id;
}


__PACKAGE__->register_method(
	method => 'delete_funding_source',
	api_name	=> 'open-ils.acq.funding_source.delete',
	signature => {
        desc => 'Deletes a funding_source',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'funding source ID', type => 'number'}
        ],
        return => {desc => '1 on success, Event on failure'}
    }
);

sub delete_funding_source {
    my($self, $conn, $auth, $funding_source_id) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    my $funding_source = $e->retrieve_acq_funding_source($funding_source_id) or return $e->die_event;
    return $e->die_event unless $e->allowed('ADMIN_FUNDING_SOURCE', $funding_source->owner, $funding_source);
    $e->delete_acq_funding_source($funding_source) or return $e->die_event;
    $e->commit;
    return 1;
}

__PACKAGE__->register_method(
	method => 'retrieve_funding_source',
	api_name	=> 'open-ils.acq.funding_source.retrieve',
	signature => {
        desc => 'Retrieves a new funding_source',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'funding source ID', type => 'number'}
        ],
        return => {desc => 'The funding_source object on success, Event on failure'}
    }
);

sub retrieve_funding_source {
    my($self, $conn, $auth, $funding_source_id, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    $options ||= {};

    my $flesh = {flesh => 1, flesh_fields => {acqfs => []}};
    push(@{$flesh->{flesh_fields}->{acqfs}}, 'credits') if $$options{flesh_credits};
    push(@{$flesh->{flesh_fields}->{acqfs}}, 'allocations') if $$options{flesh_allocations};

    my $funding_source = $e->retrieve_acq_funding_source([$funding_source_id, $flesh]) or return $e->event;

    return $e->event unless $e->allowed(
        ['ADMIN_FUNDING_SOURCE','MANAGE_FUNDING_SOURCE', 'VIEW_FUNDING_SOURCE'], 
        $funding_source->owner, $funding_source); 

    $funding_source->summary(retrieve_funding_source_summary_impl($e, $funding_source))
        if $$options{flesh_summary};
    return $funding_source;
}

__PACKAGE__->register_method(
	method => 'retrieve_org_funding_sources',
	api_name	=> 'open-ils.acq.funding_source.org.retrieve',
    stream => 1,
	signature => {
        desc => 'Retrieves all the funding_sources associated with an org unit that the requestor has access to see',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'List of org Unit IDs.  If no IDs are provided, this method returns the 
                full set of funding sources this user has permission to view', type => 'number'},
            {desc => q/Limiting permission.  this permission is used find the work-org tree from which  
                the list of orgs is generated if no org ids are provided.  
                The default is ADMIN_FUNDING_SOURCE/, type => 'string'},
        ],
        return => {desc => 'The funding_source objects on success, empty array otherwise'}
    }
);

sub retrieve_org_funding_sources {
    my($self, $conn, $auth, $org_id_list, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    $options ||= {};

    my $limit_perm = ($$options{limit_perm}) ? $$options{limit_perm} : 'ADMIN_FUNDING_SOURCE';
    return OpenILS::Event->new('BAD_PARAMS') 
        unless $limit_perm =~ /(ADMIN|MANAGE|VIEW)_FUNDING_SOURCE/;

    my $org_ids = ($org_id_list and @$org_id_list) ? $org_id_list :
        $U->user_has_work_perm_at($e, $limit_perm, {descendants =>1});

    return [] unless @$org_ids;
    my $sources = $e->search_acq_funding_source({owner => $org_ids});

    for my $source (@$sources) {
        $source->summary(retrieve_funding_source_summary_impl($e, $source))
            if $$options{flesh_summary};
        $conn->respond($source);
    }

    return undef;
}

sub retrieve_funding_source_summary_impl {
    my($e, $source) = @_;
    my $at = $e->search_acq_funding_source_allocation_total({funding_source => $source->id})->[0];
    my $b = $e->search_acq_funding_source_balance({funding_source => $source->id})->[0];
    my $ct = $e->search_acq_funding_source_credit_total({funding_source => $source->id})->[0];
    return {
        allocation_total => ($at) ? $at->amount : 0,
        balance => ($b) ? $b->amount : 0,
        credit_total => ($ct) ? $ct->amount : 0,
    };
}


__PACKAGE__->register_method(
	method => 'create_funding_source_credit',
	api_name	=> 'open-ils.acq.funding_source_credit.create',
	signature => {
        desc => 'Create a new funding source credit',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'funding source credit object', type => 'object'}
        ],
        return => {desc => 'The ID of the new funding source credit on success, Event on failure'}
    }
);

sub create_funding_source_credit {
    my($self, $conn, $auth, $fs_credit) = @_;
    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->event unless $e->checkauth;

    my $fs = $e->retrieve_acq_funding_source($fs_credit->funding_source)
        or return $e->die_event;
    return $e->die_event unless $e->allowed(['MANAGE_FUNDING_SOURCE'], $fs->owner, $fs); 

    $e->create_acq_funding_source_credit($fs_credit) or return $e->die_event;
    $e->commit;
    return $fs_credit->id;
}


# ---------------------------------------------------------------
# funds
# ---------------------------------------------------------------

__PACKAGE__->register_method(
	method => 'create_fund',
	api_name	=> 'open-ils.acq.fund.create',
	signature => {
        desc => 'Creates a new fund',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'fund object to create', type => 'object'}
        ],
        return => {desc => 'The ID of the newly created fund object'}
    }
);

sub create_fund {
    my($self, $conn, $auth, $fund) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('ADMIN_FUND', $fund->org);
    $e->create_acq_fund($fund) or return $e->die_event;
    $e->commit;
    return $fund->id;
}


__PACKAGE__->register_method(
	method => 'delete_fund',
	api_name	=> 'open-ils.acq.fund.delete',
	signature => {
        desc => 'Deletes a fund',
        params => {
            {desc => 'Authentication token', type => 'string'},
            {desc => 'fund ID', type => 'number'}
        },
        return => {desc => '1 on success, Event on failure'}
    }
);

sub delete_fund {
    my($self, $conn, $auth, $fund_id) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    my $fund = $e->retrieve_acq_fund($fund_id) or return $e->die_event;
    return $e->die_event unless $e->allowed('ADMIN_FUND', $fund->org, $fund);
    $e->delete_acq_fund($fund) or return $e->die_event;
    $e->commit;
    return 1;
}

__PACKAGE__->register_method(
	method => 'retrieve_fund',
	api_name	=> 'open-ils.acq.fund.retrieve',
	signature => {
        desc => 'Retrieves a new fund',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'fund ID', type => 'number'}
        ],
        return => {desc => 'The fund object on success, Event on failure'}
    }
);

sub retrieve_fund {
    my($self, $conn, $auth, $fund_id, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    $options ||= {};

    my $flesh = {flesh => 2, flesh_fields => {acqf => []}};
    push(@{$flesh->{flesh_fields}->{acqf}}, 'debits') if $$options{flesh_debits};
    push(@{$flesh->{flesh_fields}->{acqf}}, 'allocations') if $$options{flesh_allocations};
    push(@{$flesh->{flesh_fields}->{acqfa}}, 'funding_source') if $$options{flesh_allocation_sources};

    my $fund = $e->retrieve_acq_fund([$fund_id, $flesh]) or return $e->event;
    return $e->event unless $e->allowed(['ADMIN_FUND','MANAGE_FUND', 'VIEW_FUND'], $fund->org, $fund);
    $fund->summary(retrieve_fund_summary_impl($e, $fund))
        if $$options{flesh_summary};
    return $fund;
}

__PACKAGE__->register_method(
	method => 'retrieve_org_funds',
	api_name	=> 'open-ils.acq.fund.org.retrieve',
    stream => 1,
	signature => {
        desc => 'Retrieves all the funds associated with an org unit',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'List of org Unit IDs.  If no IDs are provided, this method returns the 
                full set of funding sources this user has permission to view', type => 'number'},
            {desc => q/Options hash.  
                "limit_perm" -- this permission is used find the work-org tree from which  
                the list of orgs is generated if no org ids are provided.  The default is ADMIN_FUND.
                "flesh_summary" -- if true, the summary field on each fund is fleshed
                The default is ADMIN_FUND/, type => 'string'},
        ],
        return => {desc => 'The fund objects on success, Event on failure'}
    }
);

sub retrieve_org_funds {
    my($self, $conn, $auth, $org_id_list, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    $options ||= {};

    my $limit_perm = ($$options{limit_perm}) ? $$options{limit_perm} : 'ADMIN_FUND';
    return OpenILS::Event->new('BAD_PARAMS') 
        unless $limit_perm =~ /(ADMIN|MANAGE|VIEW)_FUND/;

    my $org_ids = ($org_id_list and @$org_id_list) ? $org_id_list :
        $U->user_has_work_perm_at($e, $limit_perm, {descendants =>1});
    return undef unless @$org_ids;
    my $funds = $e->search_acq_fund({org => $org_ids});

    for my $fund (@$funds) {
        $fund->summary(retrieve_fund_summary_impl($e, $fund))
            if $$options{flesh_summary};
        $conn->respond($fund);
    }

    return undef;
}

__PACKAGE__->register_method(
	method => 'retrieve_fund_summary',
	api_name	=> 'open-ils.acq.fund.summary.retrieve',
	signature => {
        desc => 'Returns a summary of credits/debits/encumbrances for a fund',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'fund id', type => 'number' }
        ],
        return => {desc => 'A hash of summary information, Event on failure'}
    }
);

sub retrieve_fund_summary {
    my($self, $conn, $auth, $fund_id) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    my $fund = $e->retrieve_acq_fund($fund_id) or return $e->event;
    return $e->event unless $e->allowed('MANAGE_FUND', $fund->org, $fund);
    return retrieve_fund_summary_impl($e, $fund);
}


sub retrieve_fund_summary_impl {
    my($e, $fund) = @_;

    my $at = $e->search_acq_fund_allocation_total({fund => $fund->id})->[0];
    my $dt = $e->search_acq_fund_debit_total({fund => $fund->id})->[0];
    my $et = $e->search_acq_fund_encumbrance_total({fund => $fund->id})->[0];
    my $st = $e->search_acq_fund_spent_total({fund => $fund->id})->[0];
    my $cb = $e->search_acq_fund_combined_balance({fund => $fund->id})->[0];
    my $sb = $e->search_acq_fund_spent_balance({fund => $fund->id})->[0];

    return {
        allocation_total => ($at) ? $at->amount : 0,
        debit_total => ($dt) ? $dt->amount : 0,
        encumbrance_total => ($et) ? $et->amount : 0,
        spent_total => ($st) ? $st->amount : 0,
        combined_balance => ($cb) ? $cb->amount : 0,
        spent_balance => ($sb) ? $sb->amount : 0,
    };
}


# ---------------------------------------------------------------
# fund Allocations
# ---------------------------------------------------------------

__PACKAGE__->register_method(
	method => 'create_fund_alloc',
	api_name	=> 'open-ils.acq.fund_allocation.create',
	signature => {
        desc => 'Creates a new fund_allocation',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'fund allocation object to create', type => 'object'}
        ],
        return => {desc => 'The ID of the new fund_allocation'}
    }
);

sub create_fund_alloc {
    my($self, $conn, $auth, $fund_alloc) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    # this action is equivalent to both debiting a funding source and crediting a fund

    my $source = $e->retrieve_acq_funding_source($fund_alloc->funding_source)
        or return $e->die_event;
    return $e->die_event unless $e->allowed('MANAGE_FUNDING_SOURCE', $source->owner);

    my $fund = $e->retrieve_acq_fund($fund_alloc->fund) or return $e->die_event;
    return $e->die_event unless $e->allowed('MANAGE_FUND', $fund->org, $fund);

    $fund_alloc->allocator($e->requestor->id);
    $e->create_acq_fund_allocation($fund_alloc) or return $e->die_event;
    $e->commit;
    return $fund_alloc->id;
}


__PACKAGE__->register_method(
	method => 'delete_fund_alloc',
	api_name	=> 'open-ils.acq.fund_allocation.delete',
	signature => {
        desc => 'Deletes a fund_allocation',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'fund Alocation ID', type => 'number'}
        ],
        return => {desc => '1 on success, Event on failure'}
    }
);

sub delete_fund_alloc {
    my($self, $conn, $auth, $fund_alloc_id) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    my $fund_alloc = $e->retrieve_acq_fund_allocation($fund_alloc_id) or return $e->die_event;

    my $source = $e->retrieve_acq_funding_source($fund_alloc->funding_source)
        or return $e->die_event;
    return $e->die_event unless $e->allowed('MANAGE_FUNDING_SOURCE', $source->owner, $source);

    my $fund = $e->retrieve_acq_fund($fund_alloc->fund) or return $e->die_event;
    return $e->die_event unless $e->allowed('MANAGE_FUND', $fund->org, $fund);

    $e->delete_acq_fund_allocation($fund_alloc) or return $e->die_event;
    $e->commit;
    return 1;
}

__PACKAGE__->register_method(
	method => 'retrieve_fund_alloc',
	api_name	=> 'open-ils.acq.fund_allocation.retrieve',
	signature => {
        desc => 'Retrieves a new fund_allocation',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'fund Allocation ID', type => 'number'}
        ],
        return => {desc => 'The fund allocation object on success, Event on failure'}
    }
);

sub retrieve_fund_alloc {
    my($self, $conn, $auth, $fund_alloc_id) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    my $fund_alloc = $e->retrieve_acq_fund_allocation($fund_alloc_id) or return $e->event;

    my $source = $e->retrieve_acq_funding_source($fund_alloc->funding_source)
        or return $e->die_event;
    return $e->die_event unless $e->allowed('MANAGE_FUNDING_SOURCE', $source->owner, $source);

    my $fund = $e->retrieve_acq_fund($fund_alloc->fund) or return $e->die_event;
    return $e->die_event unless $e->allowed('MANAGE_FUND', $fund->org, $fund);

    return $fund_alloc;
}


__PACKAGE__->register_method(
	method => 'retrieve_funding_source_allocations',
	api_name	=> 'open-ils.acq.funding_source.allocations.retrieve',
	signature => {
        desc => 'Retrieves a new fund_allocation',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'fund Allocation ID', type => 'number'}
        ],
        return => {desc => 'The fund allocation object on success, Event on failure'}
    }
);

sub retrieve_funding_source_allocations {
    my($self, $conn, $auth, $fund_alloc_id) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    my $fund_alloc = $e->retrieve_acq_fund_allocation($fund_alloc_id) or return $e->event;

    my $source = $e->retrieve_acq_funding_source($fund_alloc->funding_source)
        or return $e->die_event;
    return $e->die_event unless $e->allowed('MANAGE_FUNDING_SOURCE', $source->owner, $source);

    my $fund = $e->retrieve_acq_fund($fund_alloc->fund) or return $e->die_event;
    return $e->die_event unless $e->allowed('MANAGE_FUND', $fund->org, $fund);

    return $fund_alloc;
}

# ----------------------------------------------------------------------------
# Currency
# ----------------------------------------------------------------------------

__PACKAGE__->register_method(
	method => 'retrieve_all_currency_type',
	api_name	=> 'open-ils.acq.currency_type.all.retrieve',
    stream => 1,
	signature => {
        desc => 'Retrieves all currency_type objects',
        params => [
            {desc => 'Authentication token', type => 'string'},
        ],
        return => {desc => 'List of currency_type objects', type => 'list'}
    }
);

sub retrieve_all_currency_type {
    my($self, $conn, $auth, $fund_alloc_id) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('GENERAL_ACQ');
    $conn->respond($_) for @{$e->retrieve_all_acq_currency_type()};
}

sub currency_conversion_impl {
    my($src_currency, $dest_currency, $amount) = @_;
    my $result = new_editor()->json_query({
        select => {
            acqct => [{
                params => [$dest_currency, $amount],
                transform => 'acq.exchange_ratio',
                column => 'code',
                alias => 'value'
            }]
        },
        where => {code => $src_currency},
        from => 'acqct'
    });

    return $result->[0]->{value};
}


# ----------------------------------------------------------------------------
# Purchase Orders
# ----------------------------------------------------------------------------

__PACKAGE__->register_method(
	method => 'create_purchase_order',
	api_name	=> 'open-ils.acq.purchase_order.create',
	signature => {
        desc => 'Creates a new purchase order',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'purchase_order to create', type => 'object'}
        ],
        return => {desc => 'The purchase order id, Event on failure'}
    }
);

sub create_purchase_order {
    my($self, $conn, $auth, $po, $args) = @_;
    $args ||= {};

    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('CREATE_PURCHASE_ORDER', $po->ordering_agency);

    # create the PO
    $po->ordering_agency($e->requestor->ws_ou);
    my $evt = create_purchase_order_impl($e, $po);
    return $evt if $evt;

    my $progress = 0;
    my $total_debits = 0;
    my $total_copies = 0;

    my $respond = sub {
        $conn->respond({
            @_,
            progress => ++$progress, 
            total_debits => $total_debits,
            total_copies => $total_copies,
        });
    };

    if($$args{lineitems}) {

        for my $li_id (@{$$args{lineitems}}) {

            my $li = $e->retrieve_acq_lineitem([
                $li_id,
                {flesh => 1, flesh_fields => {jub => ['attributes']}}
            ]) or return $e->die_event;

            # point the lineitems at the new PO
            $li->provider($po->provider);
            $li->purchase_order($po->id);
            $li->editor($e->requestor->id);
            $li->edit_time('now');
            $e->update_acq_lineitem($li) or return $e->die_event;
            $respond->(action => 'update_lineitem');
        
            # create the bibs/volumes/copies in the Evergreen database
            if($$args{create_assets}) {
                # args = {circ_modifier => code}
                my ($count, $evt) = create_lineitem_assets_impl($e, $li_id, $args);
                return $evt if $evt;
                $total_copies+= $count;
                $respond->(action => 'create_assets');
            }

            # create the debits
            if($$args{create_debits}) {
                # args = {encumberance => true}
                my ($total, $evt) = create_li_debit_impl($e, $li, $args);
                return $evt if $evt;
                $total_debits += $total;
                $respond->(action => 'create_debit');
            }
        }
    }

    $e->commit;
    $respond->(complete => 1, purchase_order => $po->id);
    return undef;
}


__PACKAGE__->register_method(
	method => 'create_po_assets',
	api_name	=> 'open-ils.acq.purchase_order.assets.create',
	signature => {
        desc => q/Creates assets for each lineitem in the purchase order/,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'The purchase order id', type => 'number'},
            {desc => q/Options hash./}
        ],
        return => {desc => 'Streams a total versus completed counts object, event on error'}
    }
);

sub create_po_assets {
    my($self, $conn, $auth, $po_id, $options) = @_;
    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;

    my $po = $e->retrieve_acq_purchase_order($po_id) or return $e->event;
    return $e->die_event unless 
        $e->allowed('CREATE_PURCHASE_ORDER', $po->ordering_agency);

    my $li_ids = $e->search_acq_lineitem({purchase_order=>$po_id},{idlist=>1});
    my $total = @$li_ids;
    my $count = 0;

    for my $li_id (@$li_ids) {
        my ($num, $evt) = create_lineitem_assets_impl($e, $li_id);
        return $evt if $evt;
        $conn->respond({total=>$count, progress=>++$count});
    }

    $po->edit_time('now');
    $e->update_acq_purchase_order($po) or return $e->die_event;
    $e->commit;

    return {complete=>1};
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
    my ($count, $resp) = create_lineitem_assets_impl($e, $li_id, $options);
    return $resp if $resp;
    $e->commit;
    return $count;
}

sub create_lineitem_assets_impl {
    my($e, $li_id, $options) = @_;
    $options ||= {};
    my $evt;

    my $li = $e->retrieve_acq_lineitem([
        $li_id,
        {   flesh => 1,
            flesh_fields => {jub => ['purchase_order', 'attributes']}
        }
    ]) or return (undef, $e->die_event);

    # -----------------------------------------------------------------
    # first, create the bib record if necessary
    # -----------------------------------------------------------------
    unless($li->eg_bib_id) {

       my $record = OpenILS::Application::Cat::BibCommon->biblio_record_xml_import(
            $e, $li->marc, undef, undef, undef, 1); #$rec->bib_source

        if($U->event_code($record)) {
            $e->rollback;
            return (undef, $record);
        }

        $li->editor($e->requestor->id);
        $li->edit_time('now');
        $li->eg_bib_id($record->id);
        $e->update_acq_lineitem($li) or return (undef, $e->die_event);
    }

    my $li_details = $e->search_acq_lineitem_detail({lineitem => $li_id}, {idlist=>1});

    # -----------------------------------------------------------------
    # for each lineitem_detail, create the volume if necessary, create 
    # a copy, and link them all together.
    # -----------------------------------------------------------------
    my %volcache;
    for my $li_detail_id (@{$li_details}) {

        my $li_detail = $e->retrieve_acq_lineitem_detail($li_detail_id)
            or return (undef, $e->die_event);

        # Create the volume object if necessary
        my $volume = $volcache{$li_detail->cn_label};
        unless($volume and $volume->owning_lib == $li_detail->owning_lib) {
            ($volume, $evt) =
                OpenILS::Application::Cat::AssetCommon->find_or_create_volume(
                    $e, $li_detail->cn_label, $li->eg_bib_id, $li_detail->owning_lib);
            return (undef, $evt) if $evt;
            $volcache{$volume->id} = $volume;
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
        $copy->circ_modifier($$options{circ_modifier} || 'book');

        $evt = OpenILS::Application::Cat::AssetCommon->create_copy($e, $volume, $copy);
        return (undef, $evt) if $evt;
 
        $li_detail->eg_copy_id($copy->id);
        $e->update_acq_lineitem_detail($li_detail) or return (undef, $e->die_event);
    }

    return (scalar @{$li_details});
}




sub create_purchase_order_impl {
    my($e, $p_order) = @_;

    $p_order->creator($e->requestor->id);
    $p_order->editor($e->requestor->id);
    $p_order->owner($e->requestor->id);
    $p_order->edit_time('now');

    return $e->die_event unless 
        $e->allowed('CREATE_PURCHASE_ORDER', $p_order->ordering_agency);

    my $provider = $e->retrieve_acq_provider($p_order->provider)
        or return $e->die_event;
    return $e->die_event unless 
        $e->allowed('MANAGE_PROVIDER', $provider->owner, $provider);

    $e->create_acq_purchase_order($p_order) or return $e->die_event;
    return undef;
}


# returns (price, type), where type=1 is local, type=2 is provider, type=3 is marc
sub get_li_price {
    my $li = shift;
    my $attrs = $li->attributes;
    my ($marc_estimated, $local_estimated, $local_actual, $prov_estimated, $prov_actual);

    for my $attr (@$attrs) {
        if($attr->attr_name eq 'estimated_price') {
            $local_estimated = $attr->attr_value 
                if $attr->attr_type eq 'lineitem_local_attr_definition';
            $prov_estimated = $attr->attr_value 
                if $attr->attr_type eq 'lineitem_prov_attr_definition';
            $marc_estimated = $attr->attr_value
                if $attr->attr_type eq 'lineitem_marc_attr_definition';

        } elsif($attr->attr_name eq 'actual_price') {
            $local_actual = $attr->attr_value     
                if $attr->attr_type eq 'lineitem_local_attr_definition';
            $prov_actual = $attr->attr_value 
                if $attr->attr_type eq 'lineitem_prov_attr_definition';
        }
    }

    return ($local_actual, 1) if $local_actual;
    return ($prov_actual, 2) if $prov_actual;
    return ($local_estimated, 1) if $local_estimated;
    return ($prov_estimated, 2) if $prov_estimated;
    return ($marc_estimated, 3);
}


__PACKAGE__->register_method(
	method => 'create_purchase_order_debits',
	api_name	=> 'open-ils.acq.purchase_order.debits.create',
	signature => {
        desc => 'Creates debits associated with a PO',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'purchase_order whose debits to create', type => 'number'},
            {desc => 'arguments hash.  Options include: encumbrance=bool', type => 'object'},
        ],
        return => {desc => 'The total amount of all created debits, Event on error'}
    }
);

sub create_purchase_order_debits {
    my($self, $conn, $auth, $po_id, $args) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    
    my $po = $e->retrieve_acq_purchase_order($po_id) or return $e->die_event;

    my $li_ids = $e->search_acq_lineitem(
        {purchase_order => $po_id},
        {idlist => 1}
    );

    for my $li_id (@$li_ids) {
        my $li = $e->retrieve_acq_lineitem([
            $li_id,
            {   flesh => 1,
                flesh_fields => {jub => ['attributes']},
            }
        ]);

        my ($total, $evt) = create_li_debit_impl($e, $li);
        return $evt if $evt;
    }
    $e->commit;
    return 1;
}

sub create_li_debit_impl {
    my($e, $li, $args) = @_;
    $args ||= {};

    my ($price, $ptype) = get_li_price($li);

    unless($price) {
        $e->rollback;
        return (undef, OpenILS::Event->new('ACQ_LINEITEM_NO_PRICE', payload => $li->id));
    }

    unless($li->provider) {
        $e->rollback;
        return (undef, OpenILS::Event->new('ACQ_LINEITEM_NO_PROVIDER', payload => $li->id));
    }

    my $lid_ids = $e->search_acq_lineitem_detail(
        {lineitem => $li->id}, 
        {idlist=>1}
    );

    my $total = 0;
    for my $lid_id (@$lid_ids) {

        my $lid = $e->retrieve_acq_lineitem_detail([
            $lid_id,
            {   flesh => 1, 
                flesh_fields => {acqlid => ['fund']}
            }
        ]);

        my $debit = Fieldmapper::acq::fund_debit->new;
        $debit->fund($lid->fund->id);
        $debit->origin_amount($price);

        if($ptype == 2) { # price from vendor
            $debit->origin_currency_type($li->provider->currency_type);
            $debit->amount(currency_conversion_impl(
                $li->provider->currency_type, $lid->fund->currency_type, $price));
        } else {
            $debit->origin_currency_type($lid->fund->currency_type);
            $debit->amount($price);
        }

        $debit->encumbrance($args->{encumbrance});
        $debit->debit_type('purchase');
        $e->create_acq_fund_debit($debit) or return (undef, $e->die_event);

        # point the lineitem detail at the fund debit object
        $lid->fund_debit($debit->id);
        $lid->fund($lid->fund->id);
        $e->update_acq_lineitem_detail($lid) or return (undef, $e->die_event);
        $total += $debit->amount;
    }

    return ($total);
}


__PACKAGE__->register_method(
	method => 'retrieve_all_user_purchase_order',
	api_name	=> 'open-ils.acq.purchase_order.user.all.retrieve',
    stream => 1,
	signature => {
        desc => 'Retrieves a purchase order',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'purchase_order to retrieve', type => 'number'},
            {desc => q/Options hash.  flesh_lineitems: to get the lineitems and lineitem_attrs; 
                clear_marc: to clear the MARC data from the lineitem (for reduced bandwidth);
                limit: number of items to return ,defaults to 50;
                offset: offset in the list of items to return
                order_by: sort the result, provide one or more colunm names, separated by commas,
                optionally followed by ASC or DESC as a single string 
                li_limit : number of lineitems to return if fleshing line items;
                li_offset : lineitem offset if fleshing line items
                li_order_by : lineitem sort definition if fleshing line items
                flesh_lineitem_detail_count : flesh lineitem_detail_count field
                /,
                type => 'hash'}
        ],
        return => {desc => 'The purchase order, Event on failure'}
    }
);

sub retrieve_all_user_purchase_order {
    my($self, $conn, $auth, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    $options ||= {};

    # grab purchase orders I have 
    my $perm_orgs = $U->user_has_work_perm_at($e, 'MANAGE_PROVIDER', {descendants =>1});
	return OpenILS::Event->new('PERM_FAILURE', ilsperm => 'MANAGE_PROVIDER')
        unless @$perm_orgs;
    my $provider_ids = $e->search_acq_provider({owner => $perm_orgs}, {idlist=>1});
    my $po_ids = $e->search_acq_purchase_order({provider => $provider_ids}, {idlist=>1});

    # grab my purchase orders
    push(@$po_ids, @{$e->search_acq_purchase_order({owner => $e->requestor->id}, {idlist=>1})});

    return undef unless @$po_ids;

    # now get the db to limit/sort for us
    $po_ids = $e->search_acq_purchase_order(
        [   {id => $po_ids}, {
                limit => $$options{limit} || 50,
                offset => $$options{offset} || 0,
                order_by => {acqpo => $$options{order_by} || 'create_time'}
            }
        ],
        {idlist => 1}
    );

    $conn->respond(retrieve_purchase_order_impl($e, $_, $options)) for @$po_ids;
    return undef;
}


__PACKAGE__->register_method(
	method => 'search_purchase_order',
	api_name	=> 'open-ils.acq.purchase_order.search',
    stream => 1,
	signature => {
        desc => 'Search for a purchase order',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => q/Search hash.  Search fields include id, provider/, type => 'hash'}
        ],
        return => {desc => 'A stream of POs'}
    }
);

sub search_purchase_order {
    my($self, $conn, $auth, $search, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    my $po_ids = $e->search_acq_purchase_order($search, {idlist=>1});
    for my $po_id (@$po_ids) {
        $conn->respond($e->retrieve_acq_purchase_order($po_id))
            unless po_perm_failure($e, $po_id);
    }

    return undef;
}



__PACKAGE__->register_method(
	method => 'retrieve_purchase_order',
	api_name	=> 'open-ils.acq.purchase_order.retrieve',
	signature => {
        desc => 'Retrieves a purchase order',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'purchase_order to retrieve', type => 'number'},
            {desc => q/Options hash.  flesh_lineitems, to get the lineitems and lineitem_attrs; 
                clear_marc, to clear the MARC data from the lineitem (for reduced bandwidth)
                li_limit : number of lineitems to return if fleshing line items;
                li_offset : lineitem offset if fleshing line items
                li_order_by : lineitem sort definition if fleshing line items
                /, 
                type => 'hash'}
        ],
        return => {desc => 'The purchase order, Event on failure'}
    }
);

sub retrieve_purchase_order {
    my($self, $conn, $auth, $po_id, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->event if po_perm_failure($e, $po_id);
    return retrieve_purchase_order_impl($e, $po_id, $options);
}


# if the user does not have permission to perform actions on this PO, return the perm failure event
sub po_perm_failure {
    my($e, $po_id, $fund_id) = @_;
    my $po = $e->retrieve_acq_purchase_order($po_id) or return $e->event;
    my $provider = $e->retrieve_acq_provider($po->provider) or return $e->event;
    return $e->event unless $e->allowed('MANAGE_PROVIDER', $provider->owner, $provider);
    if($fund_id) {
        my $fund = $e->retrieve_acq_fund($po->$fund_id);
        return $e->event unless $e->allowed('MANAGE_FUND', $fund->org, $fund);
    }
    return undef;
}

sub retrieve_purchase_order_impl {
    my($e, $po_id, $options) = @_;

    $options ||= {};
    my $po = $e->retrieve_acq_purchase_order($po_id) or return $e->event;

    if($$options{flesh_lineitems}) {
        my $items = $e->search_acq_lineitem([
            {purchase_order => $po_id},
            {
                flesh => 1,
                flesh_fields => {
                    jub => ['attributes']
                },
                limit => $$options{li_limit} || 50,
                offset => $$options{li_offset} || 0,
                order_by => {jub => $$options{li_order_by} || 'create_time'}
            }
        ]);

        if($$options{clear_marc}) {
            $_->clear_marc for @$items;
        }

        $po->lineitems($items);
    }

    if($$options{flesh_lineitem_count}) {
        my $items = $e->search_acq_lineitem({purchase_order => $po_id}, {idlist=>1});
        $po->lineitem_count(scalar(@$items));
    }

    return $po;
}


__PACKAGE__->register_method(
	method => 'format_po',
	api_name	=> 'open-ils.acq.purchase_order.format'
);

sub format_po {
    my($self, $conn, $auth, $po_id, $format) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;

    my $po = $e->retrieve_acq_purchase_order($po_id) or return $e->event;
    return $e->event unless $e->allowed('VIEW_PURCHASE_ORDER', $po->ordering_agency);

    my $hook = "format.po.$format";
    return $U->fire_object_event(undef, $hook, $po, $po->ordering_agency);
}


1;

