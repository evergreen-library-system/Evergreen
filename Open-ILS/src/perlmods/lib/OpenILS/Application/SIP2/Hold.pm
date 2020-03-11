package OpenILS::Application::SIP2::Hold;
use strict; use warnings;
use OpenSRF::Utils::Logger q/$logger/;
use OpenILS::Application::AppUtils;
use OpenILS::Application::SIP2::Common;
my $U = 'OpenILS::Application::AppUtils';
my $SC = 'OpenILS::Application::SIP2::Common';


sub cancel {
    my ($class, $session, $hold) = @_;

    my $details = {ok => 0};
    
    my $resp = $U->simplereq(
        'open-ils.circ',
        'open-ils.circ.hold.cancel', 
        $session->editor->authtoken, $hold->id, 7 # cancel via SIP
    );

    return $details unless $resp && !$U->event_code($resp);

    $details->{ok} = 1;

    return $details;
}

# Given a "representative" copy, finds a matching hold
sub hold_from_copy {
    my ($class, $session, $patron_details, $item_details) = @_;
    my $e = $session->editor;
    my $hold;

    my $copy = $item_details->{item};

    my $run_hold_query = sub {
        my %filter = @_;
        return $e->search_action_hold_request([
            {   usr => $patron_details->{patron}->id,
                cancel_time => undef,
                fulfillment_time => undef,
                %filter
            }, {
                flesh => 2,
                flesh_fields => {
                    ahr => ['current_copy'],
                    acp => ['call_number']
                },
                order_by => {ahr => 'request_time DESC'},
                limit => 1
            }
        ])->[0];
    };

    # first see if there is a match on current_copy
    return $hold if $hold = 
        $run_hold_query->(current_copy => $copy->id);

    # next, assume bib-level holds are the most common
    return $hold if $hold = $run_hold_query->(
        target => $copy->call_number->record->id, hold_type => 'T');

    # next try metarecord holds
    my $map = $e->search_metabib_metarecord_source_map(
        {source => $copy->call_number->record->id})->[0];

    return $hold if $hold = $run_hold_query->(
        target => $map->metarecord, hold_type => 'M');

    # volume holds
    return $hold if $hold = $run_hold_query->(
        target => $copy->call_number->id, hold_type => 'V');

    # copy holds
    return $run_hold_query->(
        target => $copy->id, hold_type => ['C', 'F', 'R']);
}

