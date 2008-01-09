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

    if($$options{children}) {
        # grab the descendent orgs
        my $org = $e->retrieve_actor_org_unit(
            [$org_id, {flesh=>1, flesh_fields=>{aou=>['ou_type']}}]) or return $e->event;
        my $org_list = $U->simplereq(
            'open-ils.storage',
            'open-ils.storage.actor.org_unit.descendants.atomic',
            $org_id, $org->ou_type->depth);

        my $org_ids = [];
        push(@$org_ids, $_->id) for @$org_list;
        $search = {owner => $org_ids};
    }

    my $funds = $e->search_acq_fund($search) or return $e->event;
    return $funds; 
}


1;
