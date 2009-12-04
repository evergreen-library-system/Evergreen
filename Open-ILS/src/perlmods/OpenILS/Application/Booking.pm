package OpenILS::Application::Booking;

use strict;
use warnings;

use OpenILS::Application;
use base qw/OpenILS::Application/;

use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
my $U = "OpenILS::Application::AppUtils";

use OpenSRF::Utils::Logger qw/$logger/;

sub prepare_new_brt {
    my ($record_id, $owning_lib, $mvr) = @_;

    my $brt = new Fieldmapper::booking::resource_type;
    $brt->isnew(1);
    $brt->name($mvr->title);
    $brt->record($record_id);
    $brt->catalog_item('t');
    $brt->owner($owning_lib);

    return $brt;
}

sub get_existing_brt {
    my ($e, $record_id, $owning_lib, $mvr) = @_;
    my $results = $e->search_booking_resource_type(
        {name => $mvr->title, owner => $owning_lib, record => $record_id}
    );

    return $results->[0] if (length @$results > 0);
    return undef;
}

sub get_mvr {
    return $U->simplereq(
        'open-ils.search',
        'open-ils.search.biblio.record.mods_slim.retrieve.authoritative',
        shift # record id
    );
}

sub get_unique_owning_libs {
    my %hash = ();
    $hash{$_->call_number->owning_lib} = 1 foreach (@_);    # @_ are copies
    return keys %hash;
}

sub fetch_copies_by_ids {
    my ($e, $copy_ids) = @_;
    my $results = $e->search_asset_copy([
        {id => $copy_ids},
        {flesh => 1, flesh_fields => {acp => ['call_number']}}
    ]);
    return $results if ref($results) eq 'ARRAY';
    return [];
}

sub get_single_record_id {
    my $record_id = undef;
    foreach (@_) {  # @_ are copies
        return undef if
            (defined $record_id && $record_id != $_->call_number->record);
        $record_id = $_->call_number->record;
    }
    return $record_id;
}

__PACKAGE__->register_method(
    method   => "create_brt_and_brsrc",
    api_name => "open-ils.booking.create_brt_and_brsrc_from_copies",
    signature => {
        params => [
            {type => 'string', desc => 'Authentication token'},
            {type => 'array', desc => 'Copy IDs'},
        ],
        return => { desc => "A two-element hash. The 'brt' element " .
            "is a list of created booking resource types described by " .
            "id/copyid pairs.  The 'brsrc' element is a similar " .
            "list of created booking resources described by copy/recordid " .
            "pairs"}
    }
);

sub create_brt_and_brsrc {
    my ($self, $conn, $authtoken, $copy_ids) = @_;
    my (@created_brt, @created_brsrc);
    my %brt_table = ();

    my $e = new_editor(xact => 1, authtoken => $authtoken);
    return $e->die_event unless $e->checkauth;

    my @copies = @{fetch_copies_by_ids($e, $copy_ids)};
    my $record_id = get_single_record_id(@copies) or return $e->die_event;
    my $mvr = get_mvr($record_id) or return $e->die_event;

    foreach (get_unique_owning_libs(@copies)) {
        $brt_table{$_} = get_existing_brt($e, $record_id, $_, $mvr) ||
            prepare_new_brt($record_id, $_, $mvr);
    }

    while (my ($owning_lib, $brt) = each %brt_table) {
        if ($brt->isnew) {
            if ($e->allowed('CREATE_BOOKING_RESOURCE_TYPE', $owning_lib)) {
                # We can/should abort if this creation fails, because the
                # logic isn't going to be trying to create any redundnat
                # brt's, therefore any error will be more serious than
                # that.  See the different take on creating brsrc's below.
                return $e->die_event unless (
                    #    v-- Important: assignment modifies original hash
                    $brt = $e->create_booking_resource_type($brt)
                );
            }
            push @created_brt, [$brt->id, $brt->record];
        }
    }

    foreach (@copies) {
        if (
            $e->allowed('CREATE_BOOKING_RESOURCE', $_->call_number->owning_lib)
        ) {
            my $brsrc = new Fieldmapper::booking::resource;
            $brsrc->isnew(1);
            $brsrc->type($brt_table{$_->call_number->owning_lib}->id);
            $brsrc->owner($_->call_number->owning_lib);
            $brsrc->barcode($_->barcode);

            # We don't want to abort the transaction or do anything dramatic if
            # this fails, because quite possibly a user selected many copies on
            # which to perform this "create booking resource" operation, and
            # among those copies there may be some that we still need to
            # create, and some that we don't.  So we just do what we can.
            push @created_brsrc, [$brsrc->id, $_->id] if
                ($brsrc = $e->create_booking_resource($brsrc));
            #           ^--- Important: assignment.
        }
    }

    $e->commit and
        return {brt => \@created_brt, brsrc => \@created_brsrc} or
        return $e->die_event;
}

1;
