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

    my $org_ids = [];
    push(@$org_ids, $_->id) for @$org_list;
    return $org_ids;
}



__PACKAGE__->register_method(
	method => 'create_fund',
	api_name	=> 'open-ils.acq.fund.create',
	signature => q/
        Creates a new fund
		@param auth Authentication token
		@param fund
	/
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
	signature => q/
        Creates a new fund
		@param auth Authentication token
		@param fund
	/
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
	signature => q/
        Retrieves a fund by ID
		@param auth Authentication token
		@param fund_id
	/
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
	signature => q/
        Retrieves all the funds associated with an org unit
		@param auth Authentication token
		@param org_id
        @param options Hash of options.  Options include "children", 
            which includes the funds for the requested org and
            all descendant orgs.
	/
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
	signature => q/
        Creates a new budget
		@param auth Authentication token
		@param budget
	/
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
	signature => q/
        Creates a new budget
		@param auth Authentication token
		@param budget
	/
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
	signature => q/
        Retrieves a budget by ID
		@param auth Authentication token
		@param budget_id
	/
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
	signature => q/
        Retrieves all the budgets associated with an org unit
		@param auth Authentication token
		@param org_id
        @param options Hash of options.  Options include "children", 
            which includes the budgets for the requested org and
            all descendant orgs.
	/
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


1;
