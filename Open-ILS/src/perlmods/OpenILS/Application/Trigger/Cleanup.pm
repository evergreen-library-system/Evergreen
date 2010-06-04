package OpenILS::Application::Trigger::Cleanup;
use strict; use warnings;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenSRF::Utils::Logger qw/:logger/;

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

1;
