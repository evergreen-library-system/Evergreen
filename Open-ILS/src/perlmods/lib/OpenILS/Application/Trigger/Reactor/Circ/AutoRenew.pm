package OpenILS::Application::Trigger::Reactor::Circ::AutoRenew;
use strict; use warnings;
use Error qw/:try/;
use Data::Dumper;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Application::Trigger::Reactor;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Application::AppUtils;
my $AppUtils = 'OpenILS::Application::AppUtils';

use Encode;
$Data::Dumper::Indent = 0;

use base 'OpenILS::Application::Trigger::Reactor';

my $log = 'OpenSRF::Utils::Logger';

sub ABOUT {
    return <<ABOUT;
This Autorenew reactor will auto renew a circulation on the day it is due.
ABOUT
}

sub handler {
    my $self = shift;
    my $env = shift;

    # 1. get a session token for circ user

    my $circs = $env->{target};
    my $svc = "open-ils.auth_internal";
    my $api = $svc . '.session.create';

    my $auth_internal_svc = OpenSRF::AppSession->create($svc);

    my $userid = $circs->[0]->usr();
    # fetch user
    my $userObj = new_editor()->retrieve_actor_user($userid);
    my %args = 
        ( 
            user_id => $userid,
            org_unit => $userObj->home_ou(), # all autorenewals occur from patron's Home OU.
            login_type => "opac"
        );

    my $token = $auth_internal_svc->request($api, \%args)->gather(1)->{payload}->{authtoken};

    # 2. carry out renewal:
    for (@$circs){

        $logger->info( "AUTORENEW: circ.target_copy: " . Dumper($_->target_copy()) );
        my $evt = $AppUtils->simplereq(
            'open-ils.circ',
            'open-ils.circ.renew',
            $token,
            {
                patron_id => $_->usr(),
                copy_id => $_->target_copy(),
                auto_renewal => 1
            }
        );

        $evt = $evt->[0] if ref($evt) eq "ARRAY";  # we got two resp events, likely renewal errors, grab the first.
        my $is_renewed = $evt->{textcode} eq 'SUCCESS' ? 1 : 0;

        my $new_circ_due = $is_renewed ? $evt->{payload}->{circ}->due_date : '';
        my $total_remaining = $is_renewed ? $evt->{payload}->{circ}->renewal_remaining : $_->renewal_remaining;
        my $auto_remaining = $is_renewed ? $evt->{payload}->{circ}->auto_renewal_remaining : $_->auto_renewal_remaining;
        # Check for negative renewal remaining. It can happen with an override renewal:
        $total_remaining = ($total_remaining < 0) ? 0 : $total_remaining;
        $auto_remaining = ($auto_remaining < 0) ? 0 : $auto_remaining; # Just making sure....

        my %user_data = (
            copy => $_->target_copy(),
            is_renewed => $is_renewed,
            reason => !$is_renewed ? $evt->{desc} : '',
            new_due_date => $is_renewed ? $evt->{payload}->{circ}->due_date : '',
            old_due_date => !$is_renewed ? $_->due_date() : '',
            textcode => $evt->{textcode},
            total_renewal_remaining => $total_remaining,
            auto_renewal_remaining => ($auto_remaining < $total_remaining) ? $auto_remaining : $total_remaining,
        );

        # Create the event from the source circ instead of the
        # new circ, since the renewal may have failed.
        # Fire and do not forget so we don't flood A/T.
        $AppUtils->simplereq(
            'open-ils.trigger',
            'open-ils.trigger.event.autocreate',
            'autorenewal', $_, $_->circ_lib, undef, \%user_data
        );
    }

    return 1;
}

1;
