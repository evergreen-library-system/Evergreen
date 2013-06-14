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
    api_name    => 'open-ils.acq.claim.eligible.lineitem_detail',
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
        return => {
            desc => "The claim voucher events on success, Event on error",
            type => "object", class => "acrlid"
        }
    }
);

__PACKAGE__->register_method(
    method => 'claim_item',
    api_name    => 'open-ils.acq.claim.lineitem_detail',
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
            {   desc => q/
                    Optional: Claim Event Types.  If present, we bypass any policy configuration
                    and use the specified event types.  This is useful for manual claiming against
                    items that have no claim policy.
                /,
                type => 'array'
            }
        ],
        return => {
            desc => "The claim voucher events on success, Event on error",
            type => "object", class => "acrlid"
        }
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

    # if this claim occurs outside of a policy, allow the caller to specificy the event type
    my $claim_event_types = shift; 

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


    my $lids;
    if($self->api_name =~ /claim.lineitem_detail/) {

        $lids = $e->search_acq_lineitem_detail([
            {"id" => $object_id, "cancel_reason" => undef},
            $lid_flesh
        ]) or return $e->die_event;

    } elsif($self->api_name =~ /claim.lineitem/) {
        $lids = $e->search_acq_lineitem_detail([
            {"lineitem" => $object_id, "cancel_reason" => undef},
            $lid_flesh
        ]) or return $e->die_event;
    }

    foreach my $lid (@$lids) {
        return $evt if
            $evt = claim_lineitem_detail(
                $e, $lid, $claim, $claim_type, $policy_actions,
                $note, $claim_events, $claim_event_types
            );
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
    my($e, $lid, $claim, $claim_type, $policy_actions, $note, $claim_events, $claim_event_types) = @_;

    # Create the claim object
    unless($claim) {
        $claim = Fieldmapper::acq::claim->new;
        $claim->lineitem_detail($lid->id);
        $claim->type($claim_type->id);
        $e->create_acq_claim($claim) or return $e->die_event;
    }

    unless($claim_event_types) {
        # user did not specify explicit event types

        unless($policy_actions) {
            # user did not specifcy policy actions.  find all eligible.

            my $list = $e->json_query({
                select => {acrlid => ['claim_policy_action']},
                from => 'acrlid',
                where => {lineitem_detail => $lid->id}
            });
    
            $policy_actions = [map { $_->{claim_policy_action} } @$list];
        }

        # from the set of policy_action's, locate the related event types
        # IOW, the policy action's action
        $claim_event_types = [];
        for my $act_id (@$policy_actions) {
            my $action = $e->retrieve_acq_claim_policy_action($act_id) or return $e->die_event;
            push(@$claim_event_types, $action->action);
        }
    }

    # for each eligible (or chosen) policy actions, create a claim_event
    for my $event_type (@$claim_event_types) {
        my $event = Fieldmapper::acq::claim_event->new;
        $event->claim($claim->id);
        $event->type($event_type);
        $event->creator($e->requestor->id);
        $event->note($note);
        $e->create_acq_claim_event($event) or return $e->die_event;
        push(@{$claim_events->{events}}, $event);
        push(@{$claim_events->{trigger_stuff}}, [$event, $lid->lineitem->purchase_order->ordering_agency]);
    }

    return undef;
}


__PACKAGE__->register_method(
    method => "get_claim_voucher_by_lid",
    api_name => "open-ils.acq.claim.voucher.by_lineitem_detail",
    stream => 1,
    signature => {
        desc => q/Retrieve existing claim vouchers by lineitem detail ID/,
        params => [
            {desc => "Authentication token", type => "string"},
            {desc => "Lineitem detail ID", type => "number"}
        ],
        return => {
            desc => "Claim ready data", type => "object", class => "atev"
        }
    }
);

sub get_claim_voucher_by_lid {
    my ($self, $conn, $auth, $lid_id) = @_;

    my $e = new_editor("authtoken" => $auth);
    return $e->die_event unless $e->checkauth;

    my $lid = $e->retrieve_acq_lineitem_detail([
        $lid_id, {
            "flesh" => 2,
            "flesh_fields" => {
                "acqlid" => ["lineitem"], "jub" => ["purchase_order"]
            }
        }
    ]);

    return $e->die_event unless $e->allowed(
        "VIEW_PURCHASE_ORDER", $lid->lineitem->purchase_order->ordering_agency
    );

    my $id_list = $e->json_query({
        "select" => {"atev" => ["id"]},
        "from" => {
            "atev" => {
                "atevdef" => {"field" => "id", "fkey" => "event_def"},
                "acqcle" => {
                    "field" => "id", "fkey" => "target",
                    "join" => {
                        "acqcl" => {
                            "field" => "id", "fkey" => "claim",
                            "join" => {
                                "acqlid" => {
                                    "fkey" => "lineitem_detail",
                                    "field" => "id"
                                }
                            }
                        }
                    }
                }
            }
        },
        "where" => {
            "-and" => {
                "+atevdef" => {"hook" => "format.acqcle.html"},
                "+acqlid" => {"id" => $lid_id}
            }
        }
    }) or return $e->die_event;

    if ($id_list && @$id_list) {
        foreach (@$id_list) {
            $conn->respond(
                $e->retrieve_action_trigger_event([
                    $_->{"id"}, {
                        "flesh" => 1,
                        "flesh_fields" => {"atev" => ["template_output"]}
                    }
                ])
            );
        }
    }

    $e->disconnect;
    undef;
}

1;
