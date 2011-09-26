package OpenILS::Application::JustInTime;

use strict;
use warnings;

use OpenILS::Application;
use base qw/OpenILS::Application/;
use OpenILS::Application::AppUtils;
my $U = "OpenILS::Application::AppUtils";

sub revalidate_events {
    my ($self, $conn, $event_id_list) = @_;

    return $U->simplereq(
        "open-ils.trigger",
        "open-ils.trigger.event_group.revalidate.test",
        $event_id_list
    );
}

__PACKAGE__->register_method(
    method   => "revalidate_events",
    api_name => "open-ils.justintime.events.revalidate",
    argc     => 1,
    signature=> {
        params => [
            {type => "array", desc => "list of action_trigger.event IDs"},
        ],
        return => { desc => "A list of equal length as the input list telling us whether events validated" }
    }
);

1;
