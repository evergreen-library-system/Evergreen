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

# ---------------------------------------------------------------
# Returns a list containing the current org id plus the IDs of 
# any descendents
# ---------------------------------------------------------------
sub org_descendants {
    my($e, $org_id) = @_;

    my $org = $e->retrieve_actor_org_unit(
        [$org_id, {flesh=>1, flesh_fields=>{aou=>['ou_type']}}]) or return $e->event;

    my $org_list = $U->simplereq(
        'open-ils.storage',
        'open-ils.storage.actor.org_unit.descendants.atomic',
        $org_id, $org->ou_type->depth);

    my @org_ids;
    push(@org_ids, $_->id) for @$org_list;
    return \@org_ids;
}



__PACKAGE__->register_method(
	method => 'create_fund',
	api_name	=> 'open-ils.acq.fund.create',
	signature => {
        desc => 'Creates a new fund',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Fund object to create', type => 'object'}
        ],
        return => {desc => 'The ID of the new fund'}
    }
);

sub create_fund {
    my($self, $conn, $auth, $fund) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('CREATE_FUND', $fund->owner);
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
            {desc => 'Fund ID', type => 'number'}
        ],
        return => {desc => '1 on success, Event on failure'}
    }
);

sub delete_fund {
    my($self, $conn, $auth, $fund_id) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    my $fund = $e->retrieve_acq_fund($fund_id) or return $e->die_event;
    return $e->die_event unless $e->allowed('DELETE_FUND', $fund->owner);
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
            {desc => 'Fund ID', type => 'number'}
        ],
        return => {desc => 'The fund object on success, Event on failure'}
    }
);

sub retrieve_fund {
    my($self, $conn, $auth, $fund_id) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    my $fund = $e->retrieve_acq_fund($fund_id) or return $e->event;
    return $e->event unless $e->allowed('VIEW_FUND', $fund->owner);
    return $fund;
}

__PACKAGE__->register_method(
	method => 'retrieve_org_funds',
	api_name	=> 'open-ils.acq.fund.org.retrieve',
	signature => {
        desc => 'Retrieves all the funds associated with an org unit',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Org Unit ID', type => 'number'},
            {desc => 'Hash or options, including "children", which, if true,  
                includes funds for descendant orgs in addition to the requested org', 
            type => 'hash'},
        ],
        return => {desc => 'The fund objects on success, Event on failure'}
    }
);

sub retrieve_org_funds {
    my($self, $conn, $auth, $org_id, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('VIEW_FUND', $org_id);

    my $search = {owner => $org_id};
    $search = {owner => org_descendents($e, $org_id)} if $$options{children};
    my $funds = $e->search_acq_fund($search) or return $e->event;

    return $funds; 
}

# ---------------------------------------------------------------
# Budgets
# ---------------------------------------------------------------

__PACKAGE__->register_method(
	method => 'create_budget',
	api_name	=> 'open-ils.acq.budget.create',
	signature => {
        desc => 'Creates a new budget',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Budget object to create', type => 'object'}
        ],
        return => {desc => 'The ID of the newly created budget object'}
    }
);

sub create_budget {
    my($self, $conn, $auth, $budget) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('CREATE_BUDGET', $budget->org);
    $e->create_acq_budget($budget) or return $e->die_event;
    $e->commit;
    return $budget->id;
}


__PACKAGE__->register_method(
	method => 'delete_budget',
	api_name	=> 'open-ils.acq.budget.delete',
	signature => {
        desc => 'Deletes a budget',
        params => {
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Budget ID', type => 'number'}
        },
        return => {desc => '1 on success, Event on failure'}
    }
);

sub delete_budget {
    my($self, $conn, $auth, $budget_id) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    my $budget = $e->retrieve_acq_budget($budget_id) or return $e->die_event;
    return $e->die_event unless $e->allowed('DELETE_BUDGET', $budget->org);
    $e->delete_acq_budget($budget) or return $e->die_event;
    $e->commit;
    return 1;
}

__PACKAGE__->register_method(
	method => 'retrieve_budget',
	api_name	=> 'open-ils.acq.budget.retrieve',
	signature => {
        desc => 'Retrieves a new budget',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Budget ID', type => 'number'}
        ],
        return => {desc => 'The budget object on success, Event on failure'}
    }
);

sub retrieve_budget {
    my($self, $conn, $auth, $budget_id) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    my $budget = $e->retrieve_acq_budget($budget_id) or return $e->event;
    return $e->event unless $e->allowed('VIEW_BUDGET', $budget->org);
    return $budget;
}

__PACKAGE__->register_method(
	method => 'retrieve_org_budgets',
	api_name	=> 'open-ils.acq.budget.org.retrieve',
	signature => {
        desc => 'Retrieves all the budgets associated with an org unit',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Org Unit ID', type => 'number'},
            {desc => 
                'Options.  Options include "children", which includes
                budgets for descendant orgs in addition to the requested org', 
            type => 'hash'},
        ],
        return => {desc => 'The budget objects on success, Event on failure'}
    }
);

sub retrieve_org_budgets {
    my($self, $conn, $auth, $org_id, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('VIEW_BUDGET', $org_id);

    my $search = {org => $org_id};
    $search = {org => org_descendents($e, $org_id)} if $$options{children};
    my $budgets = $e->search_acq_budget($search) or return $e->event;

    return $budgets; 
}

# ---------------------------------------------------------------
# Budget Allocations
# ---------------------------------------------------------------

__PACKAGE__->register_method(
	method => 'create_budget_alloc',
	api_name	=> 'open-ils.acq.budget_allocation.create',
	signature => {
        desc => 'Creates a new budget_allocation',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Budget allocation object to create', type => 'object'}
        ],
        return => {desc => 'The ID of the new budget_allocation'}
    }
);

sub create_budget_alloc {
    my($self, $conn, $auth, $budget_alloc) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    my $budget = $e->retrieve_acq_budget($budget_alloc->budget) or return $e->die_event;
    return $e->die_event unless $e->allowed('CREATE_BUDGET_ALLOCATION', $budget->org);

    $budget_alloc->allocator($e->requestor->id);
    $e->create_acq_budget_allocation($budget_alloc) or return $e->die_event;
    $e->commit;
    return $budget_alloc->id;
}


__PACKAGE__->register_method(
	method => 'delete_budget_alloc',
	api_name	=> 'open-ils.acq.budget_allocation.delete',
	signature => {
        desc => 'Deletes a budget_allocation',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Budget Alocation ID', type => 'number'}
        ],
        return => {desc => '1 on success, Event on failure'}
    }
);

sub delete_budget_alloc {
    my($self, $conn, $auth, $budget_alloc_id) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    my $budget_alloc = $e->retrieve_acq_budget_allocation($budget_alloc_id) or return $e->die_event;
    my $budget = $e->retrieve_acq_budget($budget_alloc->budget) or return $e->die_event;
    return $e->die_event unless $e->allowed('DELETE_BUDGET_ALLOCATION', $budget->org);

    $e->delete_acq_budget_allocation($budget_alloc) or return $e->die_event;
    $e->commit;
    return 1;
}

__PACKAGE__->register_method(
	method => 'retrieve_budget_alloc',
	api_name	=> 'open-ils.acq.budget_allocation.retrieve',
	signature => {
        desc => 'Retrieves a new budget_allocation',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Budget Allocation ID', type => 'number'}
        ],
        return => {desc => 'The budget allocation object on success, Event on failure'}
    }
);

sub retrieve_budget_alloc {
    my($self, $conn, $auth, $budget_alloc_id) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    my $budget_alloc = $e->retrieve_acq_budget_allocation($budget_alloc_id) or return $e->event;
    my $budget = $e->retrieve_acq_budget($budget_alloc->budget) or return $e->event;
    return $e->event unless $e->allowed('VIEW_BUDGET_ALLOCATION', $budget->org);
    return $budget_alloc;
}


1;
