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
	signature => {
        desc => 'Creates a new picklist',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Picklist object to create', type => 'object'}
        ],
        return => {desc => 'The ID of the new picklist'}
    }
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


__PACKAGE__->register_method(
	method => 'update_picklist',
	api_name	=> 'open-ils.acq.picklist.update',
	signature => {
        desc => 'Updates a new picklist',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Picklist object to update', type => 'object'}
        ],
        return => {desc => '1 on success, Event on error'}
    }
);

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

__PACKAGE__->register_method(
	method => 'retrieve_picklist',
	api_name	=> 'open-ils.acq.picklist.retrieve',
	signature => {
        desc => 'Retrieves a picklist',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Picklist ID to retrieve', type => 'object'},
            {desc => 'Options, including "flesh", which causes the picklist
                entries to be included', type => 'hash'}
        ],
        return => {desc => 'Picklist object on success, Event on error'}
    }
);

sub retrieve_picklist {
    my($self, $conn, $auth, $picklist_id, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    my $args = ($$options{flesh}) ?  # XXX
        { flesh => 1, flesh_fields => {XXX => ['entries']}} : undef;

    my $picklist = $e->retrieve_acq_picklist($picklist_id, $args)
        or return $e->die_event;

    return $BAD_PARAMS unless $e->requestor->id == $picklist->owner;
    return $picklist;
}

__PACKAGE__->register_method(
	method => 'retrieve_user_picklist',
	api_name	=> 'open-ils.acq.picklist.user.retrieve',
	signature => {
        desc => 'Retrieves a  user\'s picklists',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Options, including "idlist", whch forces the return
                of a list of IDs instead of objects', type => 'hash'},
        ],
        return => {desc => 'Picklist object on success, Event on error'}
    }
);

sub retrieve_user_picklist {
    my($self, $conn, $auth, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    return $e->search_acq_picklist({owner=>$e->requestor->id},{idlist=>$$options{idlist}});
}


__PACKAGE__->register_method(
	method => 'delete_picklist',
	api_name	=> 'open-ils.acq.picklist.delete',
	signature => {
        desc => 'Deletes a picklist',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Picklist ID to delete', type => 'number'}
        ],
        return => {desc => '1 on success, Event on error'}
    }
);

sub delete_picklist {
    my($self, $conn, $auth, $picklist_id) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    my $picklist = $e->retrieve_acq_picklist($picklist_id)
        or return $e->die_event;
    # don't let anyone delete someone else's picklist
    return $BAD_PARAMS if $picklist->owner != $e->requestor->owner;

    $e->delete_acq_picklist($picklist) or return $e->die_event;
    $e->commit;
    return 1;
}


# ----------------------------------------------------------------
# Picklist Entries
# ----------------------------------------------------------------

__PACKAGE__->register_method(
	method => 'create_picklist_entry',
	api_name	=> 'open-ils.acq.picklist_entry.create',
	signature => {
        desc => 'Creates a picklist entry',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'ID of Picklist to attach to', type => 'number'}
            {desc => 'MARC XML of picklist data', type => 'string'}
            {desc => 'Bib ID of exising biblio.record_entry if appropriate', type => 'string'}
        ],
        return => {desc => 'ID of newly created picklist_entry on success, Event on error'}
    }
);

sub create_picklist_entry {
    my($self, $conn, $auth, $picklist_id, $marc_xml, $bibid) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('CREATE_PICKLIST');

    my $picklist = $e->retrieve_acq_picklist($picklist_id)
        or return $e->die_event;
    return $BAD_PARAMS unless $picklist->owner == $e->requestor->id;

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


=head EXAMPLE JSON_QUERY
srfsh# request open-ils.cstore open-ils.cstore.json_query.atomic {"select" : { "acqple" : ["id"], "acqplea" : ["attr_value"] }, "from" : { "acqple" : { "acqplea" : { "field" : "picklist_entry", "fkey" : "id" } } }, "where" : { "+acqple" :{ "picklist" : 2 }, "+acqplea" : { "attr_type" : "picklist_marc_attr_definition", "attr_name" : "title" } }, "order_by" : { "acqplea" : { "attr_value" : { "direction" : "asc" } } } }
=cut



1;
