package OpenILS::Application::Acq::Picklist;
use base qw/OpenILS::Application::Acq/;
use strict; use warnings;

use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Const qw/:const/;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Event;

my $BAD_PARAMS = OpenILS::Event->new('BAD_PARAMS');


__PACKAGE__->register_method(
	method => 'create_picklist',
	api_name	=> 'open-ils.acq.picklist.create',
	signature => q/
        Creates a new picklist
		@param authtoken
		@pararm picklist
	/
);

sub create_picklist {
    my($self, $conn, $auth, $picklist) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('CREATE_PICKLIST');
    return $BAD_PARAMS unless $e->requestor->id == $picklist->owner;
    $e->create_acq_picklist($picklist) or return $e->die_event;
    $e->commit;
    return $picklist->id;
}

sub update_picklist {
    my($self, $conn, $auth, $picklist) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    # don't let them change the owner
    my $o_picklist = $e->retrieve_acq_picklist($picklist->id)
        or return $e->die_event;
    return $BAD_PARAMS if (
        $o_picklist->owner != $picklist->owner or
        $picklist->owner != $e->requestor->owner );

    $e->update_acq_picklist($picklist) or return $e->die_event;
    $e->commit;
    return 1;
}

sub retrieve_picklist {
    my($self, $conn, $auth, $picklist_id) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    my $picklist = $e->retrieve_acq_picklist($picklist_id)
        or return $e->die_event;
    return $BAD_PARAMS unless $e->requestor->id == $picklist->owner;
    return $picklist;
}


sub delete_picklist {
    my($self, $conn, $auth, $picklist_id) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    # don't let them delete someone else's picklist
    my $picklist = $e->retrieve_acq_picklist($picklist_id)
        or return $e->die_event;
    return $BAD_PARAMS if $picklist->owner != $e->requestor->owner;

    $e->delete_acq_picklist($picklist) or return $e->die_event;
    $e->commit;
    return 1;
}

sub create_picklist_entry {
    my($self, $conn, $auth, $picklist_id, $marc_xml, $bibid) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    # XXX data extraction ...

    my $entry = Fieldmaper::acq::picklist_entry->new;
    $entry->picklist($picklist_id);
    $entry->marc($marc_xml);
    $entry->eg_bib_id($bibid);
    $e->create_acq_picklist_entry($entry) or return $e->die_event;

    # XXX create entry attributes from the extracted data

    $e->commit;
    return $entry->id;
}


