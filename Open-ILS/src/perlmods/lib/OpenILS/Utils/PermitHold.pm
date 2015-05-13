package OpenILS::Utils::PermitHold;
use strict; use warnings;
use OpenSRF::Utils;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Application::AppUtils;
use OpenILS::Event;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
my $U  = "OpenILS::Application::AppUtils";


# params within a hash are: copy, patron, 
# requestor, request_lib, title, title_descriptor
sub permit_copy_hold {
    my $params  = shift;
    return indb_hold_permit($params);
}

my $LEGACY_HOLD_EVENT_MAP = {
    'config.hold_matrix_test.holdable' => 'ITEM_NOT_HOLDABLE',
    'item.holdable' => 'ITEM_NOT_HOLDABLE',
    'location.holdable' => 'ITEM_NOT_HOLDABLE',
    'status.holdable' => 'ITEM_NOT_HOLDABLE',
    'transit_range' => 'ITEM_NOT_HOLDABLE',
    'no_matchpoint' => 'NO_POLICY_MATCHPOINT',
    'config.hold_matrix_test.max_holds' => 'MAX_HOLDS',
    'config.rule_age_hold_protect.prox' => 'ITEM_AGE_PROTECTED'
};

sub indb_hold_permit {
    my $params = shift;

    my $function = $$params{retarget} ? 'action.hold_retarget_permit_test' : 'action.hold_request_permit_test';
    my $patron_id = 
        ref($$params{patron}) ? $$params{patron}->id : $$params{patron_id};
    my $request_lib = 
        ref($$params{request_lib}) ? $$params{request_lib}->id : $$params{request_lib};

    my $HOLD_TEST = {
        from => [
            $function,
            $$params{pickup_lib}, 
            $request_lib,
            $$params{copy}->id, 
            $patron_id,
            $$params{requestor}->id 
        ]
    };

    my $e = new_editor(xact=>1);
    my $results = $e->json_query($HOLD_TEST);
    $e->rollback;

    unless($$params{show_event_list}) {
        return 1 if $U->is_true($results->[0]->{success});
        return 0;
    }

    return [
        new OpenILS::Event(
            "NO_POLICY_MATCHPOINT",
            "payload" => {"fail_part" => "no_matchpoint"}
        )
    ] unless @$results;

    return [] if $U->is_true($results->[0]->{success});

    return [
        map {
            my $event = new OpenILS::Event(
                $LEGACY_HOLD_EVENT_MAP->{$_->{"fail_part"}} || $_->{"fail_part"}
            );
            $event->{"payload"} = {"fail_part" => $_->{"fail_part"}};
            $event;
        } @$results
    ];
}


23;
