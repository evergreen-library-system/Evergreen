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
    authoritative => 1,
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
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'fund ID', type => 'number'}
        ],
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
    authoritative => 1,
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
    if ($options->{"flesh_tags"}) {
        push @{$flesh->{"flesh_fields"}->{"acqf"}}, "tags";
        $flesh->{"flesh_fields"}->{"acqftm"} = ["tag"];
    }
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

__PACKAGE__->register_method(
	method => 'retrieve_org_funds',
	api_name	=> 'open-ils.acq.fund.org.years.retrieve');


sub retrieve_org_funds {
    my($self, $conn, $auth, $filter, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    $filter ||= {};
    $options ||= {};

    my $limit_perm = ($$options{limit_perm}) ? $$options{limit_perm} : 'ADMIN_FUND';
    return OpenILS::Event->new('BAD_PARAMS') 
        unless $limit_perm =~ /(ADMIN|MANAGE|VIEW)_(ACQ_)?FUND/;

    $filter->{org}  = $filter->{org} || 
        $U->user_has_work_perm_at($e, $limit_perm, {descendants =>1});
    return undef unless @{$filter->{org}};

    my $query = [
        $filter,
        {
            limit => $$options{limit} || 50,
            offset => $$options{offset} || 0,
            order_by => $$options{order_by} || {acqf => 'name'}
        }
    ];

    if($self->api_name =~ /years/) {
        # return the distinct set of fund years covered by the selected funds
        my $data = $e->json_query({
            select => {
                acqf => [{column => 'year', transform => 'distinct'}]
            }, 
            from => 'acqf', 
            where => $filter}
        );

        return [map { $_->{year} } @$data];
    }

    my $funds = $e->search_acq_fund($query);

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
    authoritative => 1,
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

__PACKAGE__->register_method(
	method => 'transfer_money_between_funds',
	api_name	=> 'open-ils.acq.funds.transfer_money',
	signature => {
        desc => 'Method for transfering money between funds',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Originating fund ID', type => 'number'},
            {desc => 'Amount of money to transfer away from the originating fund, in the same currency as said fund', type => 'number'},
            {desc => 'Destination fund ID', type => 'number'},
            {desc => 'Amount of money to transfer to the destination fund, in the same currency as said fund.  If null, uses the same amount specified with the Originating Fund, and attempts a currency conversion if appropriate.', type => 'number'},
            {desc => 'Transfer Note', type => 'string'}
        ],
        return => {desc => '1 on success, Event on failure'}
    }
);

sub transfer_money_between_funds {
    my($self, $conn, $auth, $ofund_id, $ofund_amount, $dfund_id, $dfund_amount, $note) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    my $ofund = $e->retrieve_acq_fund($ofund_id) or return $e->event;
    return $e->die_event unless $e->allowed(['ADMIN_FUND','MANAGE_FUND'], $ofund->org, $ofund);
    my $dfund = $e->retrieve_acq_fund($dfund_id) or return $e->event;
    return $e->die_event unless $e->allowed(['ADMIN_FUND','MANAGE_FUND'], $dfund->org, $dfund);

    if (!defined $dfund_amount) {

        if ($ofund->currency_type ne $dfund->currency_type) {

            $dfund_amount = $e->json_query({
                from => [
                    'acq.exchange_ratio',
                    $ofund->currency_type,
                    $dfund->currency_type,
                    $ofund_amount
                ]
            })->[0]->{'acq.exchange_ratio'};

        } else {

            $dfund_amount = $ofund_amount;
        }

    } else {
        return $e->die_event unless $e->allowed("ACQ_XFER_MANUAL_DFUND_AMOUNT");
    }

    $e->json_query({
        from => [
            'acq.transfer_fund',
            $ofund_id, $ofund_amount, $dfund_id, $dfund_amount, $e->requestor->id, $note
        ]
    });

    $e->commit;

    return 1;
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
    authoritative => 1,
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
    authoritative => 1,
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
            $e, $li->marc); #$rec->bib_source

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
        method    => 'retrieve_purchase_order',
        api_name  => 'open-ils.acq.purchase_order.retrieve',
        stream    => 1,
        signature => {
                      desc      => 'Retrieves a purchase order',
                      params    => [
                                    {desc => 'Authentication token', type => 'string'},
                                    {desc => 'purchase_order to retrieve', type => 'number'},
                                    {desc => q/Options hash.  flesh_lineitems, to get the lineitems and lineitem_attrs;
                clear_marc, to clear the MARC data from the lineitem (for reduced bandwidth)
                li_limit : number of lineitems to return if fleshing line items;
                li_offset : lineitem offset if fleshing line items
                li_order_by : lineitem sort definition if fleshing line items,
                flesh_po_items : po_item objects
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

    $po_id = [ $po_id ] unless ref $po_id;
    for ( @{$po_id} ) {
        my $rv;
        if ( po_perm_failure($e, $_) )
          { $rv = $e->event }
        else
          { $rv =  retrieve_purchase_order_impl($e, $_, $options) }

        $conn->respond($rv);
    }

    return undef;
}


# if the user does not have permission to perform actions on this PO, return the perm failure event
sub po_perm_failure {
    my($e, $po_id, $fund_id) = @_;
    my $po = $e->retrieve_acq_purchase_order($po_id) or return $e->event;
    return $e->event unless $e->allowed('VIEW_PURCHASE_ORDER', $po->ordering_agency, $po);
    return undef;
}

sub build_price_summary {
    my ($e, $po_id) = @_;

    # TODO: Add summary value for estimated amount (pre-encumber)

    # fetch the fund debits for this purchase order
    my $debits = $e->json_query({
        "select" => {"acqfdeb" => [qw/encumbrance amount/]},
        "from" => {
            "acqlid" => {
                "jub" => {
                    "fkey" => "lineitem",
                    "field" => "id",
                    "join" => {
                        "acqpo" => {
                            "fkey" => "purchase_order", "field" => "id"
                        }
                    }
                },
                "acqfdeb" => {"fkey" => "fund_debit", "field" => "id"}
            }
        },
        "where" => {"+acqpo" => {"id" => $po_id}}
    });

    # add any debits for non-bib po_items
    push(@$debits, @{
        $e->json_query({
            "select" => {"acqfdeb" => [qw/encumbrance amount/]},
            "from" => {acqpoi => 'acqfdeb'},
            "where" => {"+acqpoi" => {"purchase_order" => $po_id}}
        })
    });

    my ($enc, $spent) = (0, 0);
    for my $deb (@$debits) {
        if($U->is_true($deb->{encumbrance})) {
            $enc += $deb->{amount};
        } else {
            $spent += $deb->{amount};
        }
    }
    ($enc, $spent);
}


sub retrieve_purchase_order_impl {
    my($e, $po_id, $options) = @_;

    my $flesh = {"flesh" => 1, "flesh_fields" => {"acqpo" => []}};

    $options ||= {};
    unless ($options->{"no_flesh_cancel_reason"}) {
        push @{$flesh->{"flesh_fields"}->{"acqpo"}}, "cancel_reason";
    }
    if ($options->{"flesh_notes"}) {
        push @{$flesh->{"flesh_fields"}->{"acqpo"}}, "notes";
    }
    if ($options->{"flesh_provider"}) {
        push @{$flesh->{"flesh_fields"}->{"acqpo"}}, "provider";
    }

    push (@{$flesh->{flesh_fields}->{acqpo}}, 'po_items') if $options->{flesh_po_items};

    my $args = (@{$flesh->{"flesh_fields"}->{"acqpo"}}) ?
        [$po_id, $flesh] : $po_id;

    my $po = $e->retrieve_acq_purchase_order($args)
        or return $e->event;

    if($$options{flesh_lineitems}) {

        my $flesh_fields = { jub => ['attributes'] };
        $flesh_fields->{jub}->[1] = 'lineitem_details' if $$options{flesh_lineitem_details};
        $flesh_fields->{acqlid} = ['fund_debit'] if $$options{flesh_fund_debit};

        my $items = $e->search_acq_lineitem([
            {purchase_order => $po_id},
            {
                flesh => 3,
                flesh_fields => $flesh_fields,
                limit => $$options{li_limit} || 50,
                offset => $$options{li_offset} || 0,
                order_by => {jub => $$options{li_order_by} || 'create_time'}
            }
        ]);

        if($$options{clear_marc}) {
            $_->clear_marc for @$items;
        }

        $po->lineitems($items);
        $po->lineitem_count(scalar(@$items));

    } elsif( $$options{flesh_lineitem_ids} ) {
        $po->lineitems($e->search_acq_lineitem({purchase_order => $po_id}, {idlist => 1}));

    } elsif( $$options{flesh_lineitem_count} ) {

        my $items = $e->search_acq_lineitem({purchase_order => $po_id}, {idlist=>1});
        $po->lineitem_count(scalar(@$items));
    }

    if($$options{flesh_price_summary}) {
        my ($enc, $spent) = build_price_summary($e, $po_id);
        $po->amount_encumbered($enc);
        $po->amount_spent($spent);
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

__PACKAGE__->register_method(
	method => 'format_lineitem',
	api_name	=> 'open-ils.acq.lineitem.format'
);

sub format_lineitem {
    my($self, $conn, $auth, $li_id, $format, $user_data) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;

    my $li = $e->retrieve_acq_lineitem($li_id) or return $e->event;

    my $context_org;
    if (defined $li->purchase_order) {
        my $po = $e->retrieve_acq_purchase_order($li->purchase_order) or return $e->die_event;
        return $e->event unless $e->allowed('VIEW_PURCHASE_ORDER', $po->ordering_agency);
        $context_org = $po->ordering_agency;
    } else {
        my $pl = $e->retrieve_acq_picklist($li->picklist) or return $e->die_event;
        if($e->requestor->id != $pl->owner) {
            return $e->event unless
                $e->allowed('VIEW_PICKLIST', $pl->org_unit, $pl);
        }
        $context_org = $pl->org_unit;
    }

    my $hook = "format.acqli.$format";
    return $U->fire_object_event(undef, $hook, $li, $context_org, 'print-on-demand', $user_data);
}

__PACKAGE__->register_method (
    method        => 'po_events',
    api_name    => 'open-ils.acq.purchase_order.events.owner',
    stream      => 1,
    signature => q/
        Retrieve EDI-related purchase order events (format.po.jedi), by default those which are pending.
        @param authtoken Login session key
        @param owner Id or array of id's for the purchase order Owner field.  Filters the events to just those pertaining to PO's meeting this criteria.
        @param options Object for tweaking the selection criteria and fleshing options.
    /
);

__PACKAGE__->register_method (
    method        => 'po_events',
    api_name    => 'open-ils.acq.purchase_order.events.ordering_agency',
    stream      => 1,
    signature => q/
        Retrieve EDI-related purchase order events (format.po.jedi), by default those which are pending.
        @param authtoken Login session key
        @param owner Id or array of id's for the purchase order Ordering Agency field.  Filters the events to just those pertaining to PO's meeting this criteria.
        @param options Object for tweaking the selection criteria and fleshing options.
    /
);

__PACKAGE__->register_method (
    method        => 'po_events',
    api_name    => 'open-ils.acq.purchase_order.events.id',
    stream      => 1,
    signature => q/
        Retrieve EDI-related purchase order events (format.po.jedi), by default those which are pending.
        @param authtoken Login session key
        @param owner Id or array of id's for the purchase order Id field.  Filters the events to just those pertaining to PO's meeting this criteria.
        @param options Object for tweaking the selection criteria and fleshing options.
    /
);

sub po_events {
    my($self, $conn, $auth, $search_value, $options) = @_;
    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    (my $search_field = $self->api_name) =~ s/.*\.([_a-z]+)$/$1/;
    my $obj_type = 'acqpo';

    if ($search_field eq 'ordering_agency') {
        $search_value = $U->get_org_descendants($search_value);
    }

    my $query = {
        "select"=>{"atev"=>["id"]}, 
        "from"=>"atev", 
        "where"=>{
            "target"=>{
                "in"=>{
                    "select"=>{$obj_type=>["id"]}, 
                    "from"=>$obj_type,
                    "where"=>{$search_field=>$search_value}
                }
            }, 
            "event_def"=>{
                "in"=>{
                    "select"=>{atevdef=>["id"]},
                    "from"=>"atevdef",
                    "where"=>{
                        "hook"=>"format.po.jedi"
                    }
                }
            },
            "state"=>"pending" 
        },
        "order_by"=>[{"class"=>"atev", "field"=>"run_time", "direction"=>"desc"}]
    };

    if ($options && defined $options->{state}) {
        $query->{'where'}{'state'} = $options->{state}
    }

    if ($options && defined $options->{start_time}) {
        $query->{'where'}{'start_time'} = $options->{start_time};
    }

    if ($options && defined $options->{order_by}) {
        $query->{'order_by'} = $options->{order_by};
    }
    my $po_events = $e->json_query($query);

    my $flesh_fields = { 'atev' => [ 'event_def' ] };
    my $flesh_depth = 1;

    for my $id (@$po_events) {
        my $event = $e->retrieve_action_trigger_event([
            $id->{id},
            {flesh => $flesh_depth, flesh_fields => $flesh_fields}
        ]);
        if (! $event) { next; }

        my $po = retrieve_purchase_order_impl(
            $e,
            $event->target(),
            {flesh_lineitem_count=>1,flesh_price_summary=>1}
        );

        if ($e->allowed( ['CREATE_PURCHASE_ORDER','VIEW_PURCHASE_ORDER'], $po->ordering_agency() )) {
            $event->target( $po );
            $conn->respond($event);
        }
    }

    return undef;
}

__PACKAGE__->register_method (
	method		=> 'update_po_events',
    api_name    => 'open-ils.acq.purchase_order.event.cancel.batch',
    stream      => 1,
);
__PACKAGE__->register_method (
	method		=> 'update_po_events',
    api_name    => 'open-ils.acq.purchase_order.event.reset.batch',
    stream      => 1,
);

sub update_po_events {
    my($self, $conn, $auth, $event_ids) = @_;
    my $e = new_editor(xact => 1, authtoken => $auth);
    return $e->die_event unless $e->checkauth;

    my $x = 1;
    for my $id (@$event_ids) {

        # do a little dance to determine what libraries we are ultimately affecting
        my $event = $e->retrieve_action_trigger_event([
            $id,
            {   flesh => 2,
                flesh_fields => {atev => ['event_def'], atevdef => ['hook']}
            }
        ]) or return $e->die_event;

        my $po = retrieve_purchase_order_impl(
            $e,
            $event->target(),
            {}
        );

        return $e->die_event unless $e->allowed( ['CREATE_PURCHASE_ORDER','VIEW_PURCHASE_ORDER'], $po->ordering_agency() );

        if($self->api_name =~ /cancel/) {
            $event->state('invalid');
        } elsif($self->api_name =~ /reset/) {
            $event->clear_start_time;
            $event->clear_update_time;
            $event->state('pending');
        }

        $e->update_action_trigger_event($event) or return $e->die_event;
        $conn->respond({maximum => scalar(@$event_ids), progress => $x++});
    }

    $e->commit;
    return {complete => 1};
}


__PACKAGE__->register_method (
	method		=> 'process_fiscal_rollover',
    api_name    => 'open-ils.acq.fiscal_rollover.combined',
    stream      => 1,
	signature => {
        desc => q/
            Performs a combined fiscal fund rollover process.

            Creates a new series of funds for the following year, copying the old years 
            funds that are marked as propagable. They apply to the funds belonging to 
            either an org unit or to an org unit and all of its dependent org units. 
            The procedures may be run repeatedly; if any fund has already been propagated, 
            both the old and the new funds will be left alone.

            Closes out any applicable funds (by org unit or by org unit and dependents) 
            that are marked as propagable. If such a fund has not already been propagated 
            to the new year, it will be propagated at closing time.

            If a fund is marked as subject to rollover, any unspent balance in the old year's 
            fund (including money encumbered but not spent) is transferred to the new year's 
            fund. Otherwise it is deallocated back to the funding source(s).

            In either case, any encumbrance debits are transferred to the new fund, along 
            with the corresponding lineitem details. The old year's fund is marked as inactive 
            so that new debits may not be charged to it.
        /,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Fund Year to roll over', type => 'integer'},
            {desc => 'Org unit ID', type => 'integer'},
            {desc => 'Include Descendant Orgs (boolean)', type => 'integer'},
            {desc => 'Option hash: limit, offset, encumb_only', type => 'object'},
        ],
        return => {desc => 'Returns a stream of all related funds for the next year including fund summary for each'}
    }

);

__PACKAGE__->register_method (
	method		=> 'process_fiscal_rollover',
    api_name    => 'open-ils.acq.fiscal_rollover.combined.dry_run',
    stream      => 1,
	signature => {
        desc => q/
            @see open-ils.acq.fiscal_rollover.combined
            This is the dry-run version.  The action is performed,
            new fund information is returned, then all changes are rolled back.
        /
    }

);

__PACKAGE__->register_method (
	method		=> 'process_fiscal_rollover',
    api_name    => 'open-ils.acq.fiscal_rollover.propagate',
    stream      => 1,
	signature => {
        desc => q/
            @see open-ils.acq.fiscal_rollover.combined
            This version performs fund propagation only.  I.e, creation of
            the following year's funds.  It does not rollover over balances, encumbrances, 
            or mark the previous year's funds as complete.
        /
    }
);

__PACKAGE__->register_method (
	method		=> 'process_fiscal_rollover',
    api_name    => 'open-ils.acq.fiscal_rollover.propagate.dry_run',
    stream      => 1,
	signature => { desc => q/ 
        @see open-ils.acq.fiscal_rollover.propagate 
        This is the dry-run version.  The action is performed,
        new fund information is returned, then all changes are rolled back.
    / }
);



sub process_fiscal_rollover {
    my( $self, $conn, $auth, $year, $org_id, $descendants, $options ) = @_;

    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('ADMIN_FUND', $org_id);
    $options ||= {};

    my $combined = ($self->api_name =~ /combined/); 
    my $encumb_only = $U->is_true($options->{encumb_only}) ? 't' : 'f';

    my $org_ids = ($descendants) ? 
        [   
            map 
            { $_->{id} } # fetch my descendants
            @{$e->json_query({from => ['actor.org_unit_descendants', $org_id]})}
        ]
        : [$org_id];

    # Create next year's funds
    # Note, it's safe to run this more than once.
    # IOW, it will not create duplicate new funds.
    $e->json_query({
        from => [
            ($descendants) ? 
                'acq.propagate_funds_by_org_tree' :
                'acq.propagate_funds_by_org_unit',
            $year, $e->requestor->id, $org_id
        ]
    });

    if($combined) {

        # Roll the uncumbrances over to next year's funds
        # Mark the funds for $year as inactive

        $e->json_query({
            from => [
                ($descendants) ? 
                    'acq.rollover_funds_by_org_tree' :
                    'acq.rollover_funds_by_org_unit',
                $year, $e->requestor->id, $org_id, $encumb_only
            ]
        });
    }

    # Fetch all funds for the specified org units for the subsequent year
    my $fund_ids = $e->search_acq_fund(
        [{  year => int($year) + 1, 
            org => $org_ids,
            propagate => 't' }], 
        {idlist => 1}
    );

    foreach (@$fund_ids) {
        my $fund = $e->retrieve_acq_fund($_) or return $e->die_event;
        $fund->summary(retrieve_fund_summary_impl($e, $fund));

        my $amount = 0;
        if($combined and $U->is_true($fund->rollover)) {
            # see how much money was rolled over

            my $sum = $e->json_query({
                select => {acqftr => [{column => 'dest_amount', transform => 'sum'}]}, 
                from => 'acqftr', 
                where => {dest_fund => $fund->id, note => { like => 'Rollover%' } }
            })->[0];

            $amount = $sum->{dest_amount} if $sum;
        }

        $conn->respond({fund => $fund, rollover_amount => $amount});
    }

    $self->api_name =~ /dry_run/ and $e->rollback or $e->commit;
    return undef;
}


1;

