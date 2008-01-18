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
        $picklist->owner != $e->requestor->id );

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
            {desc => 'Picklist ID to retrieve', type => 'number'},
        ],
        return => {desc => 'Picklist object on success, Event on error'}
    }
);

sub retrieve_picklist {
    my($self, $conn, $auth, $picklist_id, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;

    my $picklist = $e->retrieve_acq_picklist($picklist_id)
        or return $e->event;

    return $BAD_PARAMS unless $e->requestor->id == $picklist->owner;
    return $picklist;
}

__PACKAGE__->register_method(
	method => 'retrieve_picklist_name',
	api_name	=> 'open-ils.acq.picklist.name.retrieve',
	signature => {
        desc => 'Retrieves a picklist by name.  Owner is implied by the caller',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Picklist name to retrieve', type => 'strin'},
        ],
        return => {desc => 'Picklist object on success, null on not found'}
    }
);

sub retrieve_picklist_name {
    my($self, $conn, $auth, $name) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->search_acq_picklist(
        {name => $name, owner => $e->requestor->id})->[0];
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
    return $BAD_PARAMS if $picklist->owner != $e->requestor->id;

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
            {desc => 'The picklist_entry object to create', type => 'object'},
        ],
        return => {desc => 'ID of newly created picklist_entry on success, Event on error'}
    }
);

sub create_picklist_entry {
    my($self, $conn, $auth, $entry) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('CREATE_PICKLIST');

    my $picklist = $e->retrieve_acq_picklist($entry->picklist)
        or return $e->die_event;
    return $BAD_PARAMS unless $picklist->owner == $e->requestor->id;

    # indicate the picklist was updated
    $picklist->edit_time('now');
    $e->update_acq_picklist($picklist) or return $e->die_event;

    $e->create_acq_picklist_entry($entry) or return $e->die_event;

    $e->commit;
    return $entry->id;
}


__PACKAGE__->register_method(
	method => 'retrieve_picklist_entry',
	api_name	=> 'open-ils.acq.picklist_entry.retrieve',
	signature => {
        desc => 'Retrieves a picklist_entry',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Picklist entry ID to retrieve', type => 'number'},
            {options => 'Hash of options, including "flesh", which fleshes the attributes', type => 'hash'},
        ],
        return => {desc => 'Picklist entry object on success, Event on error'}
    }
);

sub retrieve_picklist_entry {
    my($self, $conn, $auth, $pl_entry_id, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    my $pl_entry;
    if($$options{flesh}) {
        $pl_entry = $e->retrieve_acq_picklist_entry([
            $pl_entry_id, {flesh => 1, flesh_fields => {acqple => ['attributes']}}])
            or return $e->event;
    } else {
        $pl_entry = $e->retrieve_acq_picklist_entry($pl_entry_id)
            or return $e->event;
    }

    my $picklist = $e->retrieve_acq_picklist($pl_entry->picklist)
        or return $e->event;

    return $BAD_PARAMS if $picklist->owner != $e->requestor->id;
    return $pl_entry;
}



__PACKAGE__->register_method(
	method => 'delete_picklist_entry',
	api_name	=> 'open-ils.acq.picklist_entry.delete',
	signature => {
        desc => 'Deletes a picklist_entry',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Picklist entry ID to delete', type => 'number'}
        ],
        return => {desc => '1 on success, Event on error'}
    }
);

sub delete_picklist_entry {
    my($self, $conn, $auth, $pl_entry_id) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    my $pl_entry = $e->retrieve_acq_picklist_entry($pl_entry_id)
        or return $e->die_event;

    my $picklist = $e->retrieve_acq_picklist($pl_entry->picklist)
        or return $e->die_event;

    # don't let anyone delete someone else's picklist entry
    return $BAD_PARAMS if $picklist->owner != $e->requestor->id;

    $e->delete_acq_picklist_entry($pl_entry) or return $e->die_event;
    $e->commit;
    return 1;
}


__PACKAGE__->register_method(
	method => 'retrieve_pl_picklist_entry',
	api_name	=> 'open-ils.acq.picklist_entry.picklist.retrieve',
	signature => {
        desc => 'Retrieves picklist_entry objects according to picklist',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Picklist ID whose entries to retrieve', type => 'number'},
            {desc => q/Options, including 
                "sort_attr", which defines the attribute to sort on; 
                "sort_attr_type", which defines the attribute type sort on; 
                "sort_dir", which defines the sort order between "asc" and "desc";
                "limit", retrieval limit;
                "offset", retrieval offset;
                "idlist", return a list of IDs instead of objects
                "flesh", additionaly return the list of flattened attributes
                "clear_marc", discards the raw MARC data to reduce data size
                /, 
                type => 'hash'}
        ],
        return => {desc => 'Array of picklist entry objects or IDs,  on success, Event on error'}
    }
);


# some defaults are filled in for reference
my $PL_ENTRY_JSON_QUERY = {
    select => {acqple => ['id']}, # display fields
    from => {
        acqple => { # selecting from picklist_entry_attr
            acqplea => {field => 'picklist_entry', fkey => 'id'}
        }
    },
    where => {
        '+acqple' => {picklist => 1},
        '+acqplea' => { # grab attr rows with the requested type and name for sorting
            'attr_type' => 'picklist_marc_attr_definition',
            'attr_name' => 'title'
        }
    },
    'order_by' => {
        acqplea => {
            'attr_value' => {direction => 'asc'}
        }
    },
    limit => 10,
    offset => 0
};

sub retrieve_pl_picklist_entry {
    my($self, $conn, $auth, $picklist_id, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    # collect the retrieval options
    my $sort_attr = $$options{sort_attr} || 'title';
    my $sort_attr_type = $$options{sort_attr_type} || 'picklist_marc_attr_definition';
    my $sort_dir = $$options{sort_dir} || 'asc';
    my $limit = $$options{limit} || 10;
    my $offset = $$options{offset} || 0;

    $PL_ENTRY_JSON_QUERY->{where}->{'+acqple'}->{picklist} = $picklist_id;
    $PL_ENTRY_JSON_QUERY->{where}->{'+acqplea'}->{attr_name} = $sort_attr;
    $PL_ENTRY_JSON_QUERY->{where}->{'+acqplea'}->{attr_type} = $sort_attr_type;
    $PL_ENTRY_JSON_QUERY->{order_by}->{acqplea}->{attr_value}->{direction} = $sort_dir;
    $PL_ENTRY_JSON_QUERY->{limit} = $limit;
    $PL_ENTRY_JSON_QUERY->{offset} = $offset;

    my $entries = $e->json_query($PL_ENTRY_JSON_QUERY);
    return [] unless $entries and @$entries;

    my @ids;
    push(@ids, $_->{id}) for @$entries;
    return \@ids if $$options{idlist};

    if($$options{flesh}) {
        $entries = $e->search_acq_picklist_entry([
            {id => \@ids},
            {flesh => 1, flesh_fields => {acqple => ['attributes']}}
        ]);
    } else {
        $entries = $e->batch_retrieve_acq_picklist_entry(\@ids);
    }

    if($$options{clear_marc}) {
        $_->clear_marc for @$entries;
    }

    return $entries;
}


1;
