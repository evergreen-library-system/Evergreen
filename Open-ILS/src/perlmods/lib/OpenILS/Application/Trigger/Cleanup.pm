package OpenILS::Application::Trigger::Cleanup;
use strict; use warnings;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenILS::Utils::Fieldmapper;

sub fourty_two { return 42 }
sub NOOP_True { return 1 }
sub NOOP_False { return 0 }

sub DeleteTempBiblioBucket {
    my($self, $env) = @_;
    my $e = new_editor(xact => 1);
    my $buckets = $env->{target};

    for my $bucket (@$buckets) {

        foreach my $item (@{ $bucket->items }) {
            $e->delete_container_biblio_record_entry_bucket_item($item);
        }

        $e->delete_container_biblio_record_entry_bucket($bucket);
    }

    $e->commit or $e->die_event;

    return 1;
}

# This is really more of an auxillary reactor
sub CreateHoldNotification {
    my ($self, $env) = @_;
    my $e = new_editor(xact => 1);
    my $holds = $env->{target};

    my $event_def = (ref $env->{event} eq 'ARRAY') ?
        $env->{event}->[0]->event_def : # event_def is grouped
        $env->{event}->event_def;

    for my $hold (@$holds) {

        my $notify = Fieldmapper::action::hold_notification->new;
        $notify->hold($hold->id);
        $notify->method($event_def->reactor);

        unless($e->create_action_hold_notification($notify)) {
            $e->rollback;
            return 0;
        }
    }

    return 1 if $e->commit;
    $e->rollback;
    return 0;
}

1;
