package OpenILS::Application::Acq::Claims;
use base qw/OpenILS::Application/;
use strict; use warnings;

use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Application::AppUtils;
use OpenILS::Event;
my $U = 'OpenILS::Application::AppUtils';


__PACKAGE__->register_method(
	method => 'claim_ready_items',
	api_name	=> 'open-ils.acq.claim.eligible.lineitem_detail',
    stream => 1,
	signature => {
        desc => q/Locates lineitem_details that are eligible for claiming/,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {   desc => q/
                    Filter object.  Filter keys include 
                    purchase_order
                    lineitem
                    lineitem_detail
                    claim_policy_action
                    ordering_agency
                /, 
                type => 'object'
            },
            {   desc => q/
                    Flesh fields.  Which fields to flesh on the response object.  
                    For valid options, see the filter object
                q/, 
                type => 'array'
            }
        ],
        return => {desc => 'Claim ready data', type => 'object', class => 'acrlid'}
    }
);

sub claim_ready_items {
    my($self, $conn, $auth, $filters, $flesh_fields, $limit, $offset) = @_;

    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;

    $filters ||= {};
    $flesh_fields ||= [];
    $limit ||= 50;
    $offset ||= 0;

    if(defined $filters->{ordering_agency}) {
        return $e->event unless $e->allowed('VIEW_PURCHASE_ORDER', $filters->{ordering_agency});
    } else {
        $filters->{ordering_agency} = $U->user_has_work_perm_at($e, 'VIEW_PURCHASE_ORDER', {descendants => 1});
    }

    my $items = $e->search_acq_claim_ready_lineitem_detail([$filters, {limit => $limit, offset => $offset}]);

    my %cache;
    for my $item (@$items) {

        # flesh from the flesh fields, using the cache when we can
        foreach (@$flesh_fields) {
            my $retrieve = "retrieve_acq_${_}";
            $cache{$_} = {} unless $cache{$_};
            $item->$_( 
                $cache{$_}{$item->$_} || 
                ($cache{$_}{$item->$_} = $e->$retrieve($item->$_))
            );
        }

        $conn->respond($item);
    }

    return undef;
}

__PACKAGE__->register_method(
    method => "claim_item",
    api_name => "open-ils.acq.claim.lineitem",
    stream => 1,
    signature => {
        desc => q/Initiates a claim for a lineitem/,
        params => [
            {desc => "Authentication token", type => "string"},
            {desc => "Lineitem ID", type => "number"},
            {desc => q/Claim (acqcl) ID.  If defined, attach new claim
                events to this existing claim object/, type => "number"},
            {desc => q/Claim Type (acqclt) ID.  If defined (and no claim is
                defined), create a new claim with this type/, type => "number"},
            {desc => "Note for the claim event", type => "string"},
            {desc => q/Optional: Claim Policy Actions.  If not present,
                claim events for all eligible claim policy actions will be
                created.  This is an array of acqclpa IDs./,
                type => "array"},
        ],
        return => {desc => "The claim events on success, Event on error",
            type => "object", class => "acrlid"}
    }
);

__PACKAGE__->register_method(
	method => 'claim_item',
	api_name	=> 'open-ils.acq.claim.lineitem_detail',
    stream => 1,
	signature => {
        desc => q/Initiates a claim for an individual lineitem_detail/,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Lineitem Detail ID', type => 'number'},
            {desc => 'Claim (acqcl) ID.  If defined, attach new claim events to this existing claim object', type => 'number'},
            {desc => 'Claim Type (acqclt) ID.  If defined (and no claim is defined), create a new claim with this type', type => 'number'},
            {desc => "Note for the claim event", type => "string"},
            {   desc => q/
                
                    Optional: Claim Policy Actions.  If not present, claim events 
                    for all eligible claim policy actions will be created.  This is
                    an array of acqclpa ID's.
                /, 
                type => 'array'
            },
        ],
        return => {desc => 'The claim events on success, Event on error', type => 'object', class => 'acrlid'}
    }
);

sub claim_item {
    my $self = shift;
    my $conn = shift;
    my $auth = shift;
    my $object_id = shift;
    my $claim_id = shift;
    my $claim_type_id = shift;
    my $note = shift;
    my $policy_actions = shift;
#   my $only_eligible = shift; # so far unused

    my $e = new_editor(xact => 1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    my $evt;
    my $claim;
    my $claim_type;
    my $claim_events = {
        events => [],
        trigger_stuff => []
    };

    my $lid_flesh = {
        "flesh" => 2,
        "flesh_fields" => {
            "acqlid" => ["lineitem"], "jub" => ["purchase_order"],
        }
    };

    if($claim_id) {
        $claim = $e->retrieve_acq_claim($claim_id) or return $e->die_event;
    } elsif($claim_type_id) {
        $claim_type = $e->retrieve_acq_claim_type($claim_type_id) or return $e->die_event;
    } else {
        $e->rollback;
        return OpenILS::Event->new('BAD_PARAMS');
    }

    if($self->api_name =~ /claim.lineitem_detail/) {

        my $lid = $e->retrieve_acq_lineitem_detail([$object_id, $lid_flesh]) or
            return $e->die_event;
        return $evt if 
            $evt = claim_lineitem_detail(
                $e, $lid, $claim, $claim_type, $policy_actions, $note, $claim_events); 

    } elsif($self->api_name =~ /claim.lineitem/) {
        my $lids = $e->search_acq_lineitem_detail([
            {"lineitem" => $object_id, "cancel_reason" => undef},
            $lid_flesh
        ]) or return $e->die_event;

        foreach my $lid (@$lids) {
            return $evt if
                $evt = claim_lineitem_detail(
                    $e, $lid, $claim, $claim_type, $policy_actions,
                    $note, $claim_events
                );
        }
    }

    $e->commit;

    # create related A/T events
    $U->create_events_for_hook('claim_event.created', $_->[0], $_->[1]) for @{$claim_events->{trigger_stuff}};

    # do voucher rendering and return result
    $conn->respond($U->fire_object_event(
        undef, "format.acqcle.html", $_->[0], $_->[1], "print-on-demand"
    )) foreach @{$claim_events->{trigger_stuff}};
    return undef;
}

sub claim_lineitem_detail {
    my($e, $lid, $claim, $claim_type, $policy_actions, $note, $claim_events) = @_;

    # Create the claim object
    unless($claim) {
        $claim = Fieldmapper::acq::claim->new;
        $claim->lineitem_detail($lid->id);
        $claim->type($claim_type->id);
        $e->create_acq_claim($claim) or return $e->die_event;
    }

    # find all eligible policy actions if none are provided
    unless($policy_actions) {
        my $list = $e->json_query({
            select => {acrlid => ['claim_policy_action']},
            from => 'acrlid',
            where => {lineitem_detail => $lid->id}
        });

        $policy_actions = [map { $_->{claim_policy_action} } @$list];
    }

    # for each eligible (or chosen) policy actions, create a claim_event
    for my $act_id (@$policy_actions) {
        my $action = $e->retrieve_acq_claim_policy_action($act_id) or return $e->die_event;
        my $event = Fieldmapper::acq::claim_event->new;
        $event->claim($claim->id);
        $event->type($action->action);
        $event->creator($e->requestor->id);
        $event->note($note);
        $e->create_acq_claim_event($event) or return $e->die_event;
        push(@{$claim_events->{events}}, $event);
        push(@{$claim_events->{trigger_stuff}}, [$event, $lid->lineitem->purchase_order->ordering_agency]);
    }

    return undef;
}



1;
