package OpenILS::Application::Trigger::Reactor::ContainerCSV;
use base "OpenILS::Application::Trigger::Reactor";
use strict;
use warnings;
use OpenSRF::Utils::Logger qw/:logger/;
use Data::Dumper;
$Data::Dumper::Indent = 0;
my $U = "OpenILS::Application::AppUtils";

sub ABOUT {
    return q|

The ContainerCSV Reactor Module processes the configured template after
fetching the items from the bookbag refererred to in $env->{target}
by using the search api with the query in $env->{params}{search}.  It's
the event-creator's responsibility to build a correct search query and check
permissions and do that sort of thing.

open-ils.trigger is not a public service, so that should be ok.

The output, like all processed templates, is stored in the event_output table.

|;
}

sub handler {
    my ($self, $env) = @_;

    # get items for bookbags (bib containers of btype bookbag)
    if ($env->{user_data}{item_search}) {
        # Since the search is by default limited to 10, let's bump the limit
        # to 1,000 just for giggles. This oughta be a setting, either YAOUS
        # or YAUS.
        my $args = {limit => 1000};

        # use the search api for bib container items.  fetch record IDs only.
        my $items = $U->bib_container_items_via_search(
            $env->{target}->id, $env->{user_data}{item_search}, $args, 1
        ) or return 0;  # TODO build error output for db?

        $env->{items} = $items;
    } else {
        # XXX TODO If we're going to support other types of containers here,
        # we'll probably just want to flesh those containers' items directly,
        # not involve the search API.

        $logger->warn("ContainerCSV reactor used without item_search, doesn't know what to do."); # XXX
    }

    return 1 if $self->run_TT($env);
    return 0;
}

1;
