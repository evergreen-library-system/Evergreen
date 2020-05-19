package OpenILS::Application::Trigger::Reactor::CurbsideSlot;
use base 'OpenILS::Application::Trigger::Reactor';
use strict; use warnings;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Application::AppUtils;
my $U = "OpenILS::Application::AppUtils";

$Data::Dumper::Indent = 0;


sub ABOUT {
    return <<ABOUT;
    
    Creates a curbside appointment slot at the hold pickup library when
    a hold becomes ready for pickup, if one does not exist.

ABOUT
}

sub handler {
    my $self = shift;
    my $env = shift;
    my $e = new_editor(xact => 1);

    my $h = $$env{target};

    # see if there's an undelivered appointment in the future
    my $slot = $e->search_action_curbside({
        patron => $h->usr,
        org => $h->pickup_lib,
        delivered => undef
    });

    if (!@$slot) {
        $slot = Fieldmapper::action::curbside->new;
        $slot->org($h->pickup_lib);
        $slot->patron($h->usr);
        $e->create_action_curbside($slot);
        $e->commit;

        my $ses = OpenSRF::AppSession->create('open-ils.trigger');
        $ses->request('open-ils.trigger.event.autocreate', 'hold.offer_curbside', $h, $h->pickup_lib);

    } else {
        $e->rollback;
    }

    return 1;
}

1;
