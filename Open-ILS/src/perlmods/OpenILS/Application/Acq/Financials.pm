package OpenILS::Application::Acq::Financials;
use base qw/OpenILS::Application::Acq/;
use strict; use warnings;

use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Const qw/:const/;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Event;
use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';

my $BAD_PARAMS = OpenILS::Event->new('BAD_PARAMS');


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
    my $flesh = {flesh => 1, flesh_fields => {acqfs => []}};
    push(@{$flesh->{flesh_fields}->{acqfs}}, 'credits') if $$options{flesh_credits};
    push(@{$flesh->{flesh_fields}->{acqfs}}, 'allocations') if $$options{flesh_allocations};
    my $funding_source = $e->retrieve_acq_funding_source([$funding_source_id, $flesh]) or return $e->event;
    return $e->event unless $e->allowed(
        ['ADMIN_FUNDING_SOURCE','MANAGE_FUNDING_SOURCE'], $funding_source->owner, $funding_source); 
    $funding_source->summary(retrieve_funding_source_summary_impl($e, $funding_source))
        if $$options{flesh_summary};
    return $funding_source;
}

__PACKAGE__->register_method(
	method => 'retrieve_org_funding_sources',
	api_name	=> 'open-ils.acq.funding_source.org.retrieve',
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

    my $limit_perm = ($$options{limit_perm}) ? $$options{limit_perm} : 'ADMIN_FUNDING_SOURCE';

    my $org_ids = ($org_id_list and @$org_id_list) ? $org_id_list :
        $U->find_highest_work_orgs($e, $limit_perm, {descendants =>1});

    return [] unless @$org_ids;
    my $sources = $e->search_acq_funding_source({owner => $org_ids});

    if($$options{flesh_summary}) {
        for my $source (@$sources) {
            $source->summary(retrieve_funding_source_summary_impl($e, $source));
        }
    }

    return $sources;
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

    my $flesh = {flesh => 1, flesh_fields => {acqf => []}};
    push(@{$flesh->{flesh_fields}->{acqf}}, 'debits') if $$options{flesh_debits};
    push(@{$flesh->{flesh_fields}->{acqf}}, 'allocations') if $$options{flesh_allocations};

    my $fund = $e->retrieve_acq_fund([$fund_id, $flesh]) or return $e->event;
    return $e->event unless $e->allowed(['ADMIN_FUND','MANAGE_FUND'], $fund->org, $fund);
    $fund->summary(retrieve_fund_summary_impl($e, $fund))
        if $$options{flesh_summary};
    return $fund;
}

__PACKAGE__->register_method(
	method => 'retrieve_org_funds',
	api_name	=> 'open-ils.acq.fund.org.retrieve',
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

    my $limit_perm = ($$options{limit_perm}) ? $$options{limit_perm} : 'ADMIN_FUND';

    my $org_ids = ($org_id_list and @$org_id_list) ? $org_id_list :
        $U->find_highest_work_orgs($e, $limit_perm, {descendants =>1});
    return [] unless @$org_ids;
    my $funds = $e->search_acq_fund({org => $org_ids});

    if($$options{flesh_summary}) {
        for my $fund (@$funds) {
            $fund->summary(retrieve_fund_summary_impl($e, $fund));
        }
    }

    return $funds;
}

__PACKAGE__->register_method(
	method => 'retrieve_fund_summary',
	api_name	=> 'open-ils.acq.fund.summary.retrieve',
	signature => {
        desc => 'Returns a summary of credits/debits/encumberances for a fund',
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
    my $et = $e->search_acq_fund_encumberance_total({fund => $fund->id})->[0];
    my $st = $e->search_acq_fund_spent_total({fund => $fund->id})->[0];
    my $cb = $e->search_acq_fund_combined_balance({fund => $fund->id})->[0];
    my $sb = $e->search_acq_fund_spent_balance({fund => $fund->id})->[0];

    return {
        allocation_total => ($at) ? $at->amount : 0,
        debit_total => ($dt) ? $dt->amount : 0,
        encumberance_total => ($et) ? $et->amount : 0,
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




# ----------------------------------------------------------------------------
# Currency
# ----------------------------------------------------------------------------

__PACKAGE__->register_method(
	method => 'retrieve_all_currency_type',
	api_name	=> 'open-ils.acq.currency_type.all.retrieve',
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
    return $e->retrieve_all_acq_currency_type();
}


1;
