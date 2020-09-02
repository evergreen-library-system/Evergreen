package OpenILS::Application::Courses;

use strict;
use warnings;

use OpenSRF::AppSession;
use OpenILS::Application;
use base qw/OpenILS::Application/;

use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
my $U = "OpenILS::Application::AppUtils";

use OpenSRF::Utils::Logger qw/$logger/;

__PACKAGE__->register_method(
    method          => 'attach_electronic_resource_to_course',
    api_name        => 'open-ils.courses.attach.electronic_resource',
    signature => {
        desc => 'Attaches a bib record for an electronic resource to a course',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Record id', type => 'number'},
            {desc => 'Course id', type => 'number'},
            {desc => 'Relationship', type => 'string'}
        ],
        return => {desc => '1 on success, event on failure'}
    });
sub attach_electronic_resource_to_course {
    my ($self, $conn, $authtoken, $record, $course, $relationship) = @_;
    my $e = new_editor(authtoken=>$authtoken, xact=>1);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless
        $e->allowed('MANAGE_RESERVES');

    my $located_uris = $e->search_asset_call_number({
        record => $record,
        deleted => 'f',
        label => '##URI##' })->[0];
    my $bib = $e->retrieve_biblio_record_entry([
        $record, {
            flesh => 1,
            flesh_fields => {'bre' => ['source']}
        }
    ]);
    return $e->event unless (($bib->source && $bib->source->transcendant) || $located_uris);
    _attach_bib($e, $course, $record, $relationship, 0);

    return 1;
}

__PACKAGE__->register_method(
    method          => 'attach_brief_bib_to_course',
    api_name        => 'open-ils.courses.attach.biblio_record',
    signature => {
        desc => 'Creates a new bib record with the provided XML, and attaches it to a course',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'XML', type => 'string'},
            {desc => 'Course id', type => 'number'},
            {desc => 'Relationship', type => 'string'}
        ],
        return => {desc => '1 on success, event on failure'}
    });
sub attach_brief_bib_to_course {
    my ($self, $conn, $authtoken, $marcxml, $course, $relationship) = @_;
    my $e = new_editor(authtoken=>$authtoken, xact=>1);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('MANAGE_RESERVES');
    return $e->die_event unless $e->allowed('CREATE_MARC');

    my $bib_source_id = $U->ou_ancestor_setting_value($self->{ou}, 'circ.course_materials_brief_record_bib_source');
    my $bib_source_name;
    if ($bib_source_id) {
        $bib_source_name = $e->retrieve_config_bib_source($bib_source_id)->source;
    } else {
        # The default value from the seed data
        $bib_source_name = 'Course materials module';
    }

    my $bib_create = OpenSRF::AppSession
        ->create('open-ils.cat')
        ->request('open-ils.cat.biblio.record.xml.create',
            $authtoken, $marcxml, $bib_source_name)
        ->gather(1);
    _attach_bib($e, $course, $bib_create->id, $relationship, 1) if ($bib_create);
    return 1;
}

# Shared logic for both e-resources and brief bibs
sub _attach_bib {
    my ($e, $course, $record, $relationship, $temporary) = @_;
    my $acmcm = Fieldmapper::asset::course_module_course_materials->new;
    $acmcm->course($course);
    $acmcm->record($record);
    $acmcm->relationship($relationship);
    $acmcm->temporary_record($temporary);
    $e->create_asset_course_module_course_materials( $acmcm ) or return $e->die_event;
    $e->commit;
}

__PACKAGE__->register_method(
    method          => 'fetch_course_materials',
    autoritative    => 1,
    stream          => 1,
    api_name        => 'open-ils.courses.course_materials.retrieve',
    signature       => q/
        Returns an array of course materials.
        @params args     : Supplied object to filter search.
    /);

__PACKAGE__->register_method(
    method          => 'fetch_course_materials',
    autoritative    => 1,
    stream          => 1,
    api_name        => 'open-ils.courses.course_materials.retrieve.fleshed',
    signature       => q/
        Returns an array of course materials, each fleshed out with information
        from the item and the course_material object.
        @params args     : Supplied object to filter search.
    /);

sub fetch_course_materials {
    my ($self, $conn, $args) = @_;
    my $e = new_editor();
    my $materials;

    if ($self->api_name =~ /\.fleshed/) {
        my $fleshing = {
            'flesh' => 2, 'flesh_fields' => {
                'acmcm' => ['item', 'record', 'original_circ_modifier',
                    'original_location', 'original_status'],
                'acp' => ['call_number', 'circ_lib', 'location', 'status'],
                'bre' => ['wide_display_entry'],
            }
        };
        $materials = $e->search_asset_course_module_course_materials([$args, $fleshing]);
    } else {
        $materials = $e->search_asset_course_module_course_materials($args);
    }
    $conn->respond($_) for @$materials;
    return undef;
}

__PACKAGE__->register_method(
    method          => 'fetch_courses',
    autoritative    => 1,
    api_name        => 'open-ils.courses.courses.retrieve',
    signature       => q/
        Returns an array of course materials.
        @params course_id: The id of the course we want to retrieve
    /);

sub fetch_courses {
    my ($self, $conn, @course_ids) = @_;
    my $e = new_editor();

    return unless @course_ids;
    my $targets = ();
    foreach my $course_id (@course_ids) {
        my $target = $e->retrieve_asset_course_module_course($course_id);
        push @$targets, $target;
    }

    return $targets;
}

__PACKAGE__->register_method(
    method          => 'fetch_course_users',
    autoritative    => 1,
    api_name        => 'open-ils.courses.course_users.retrieve',
    signature       => q/
        Returns an array of course users.
        @params course_id: The id of the course we want to retrieve from
    /);
__PACKAGE__->register_method(
    method          => 'fetch_course_users',
    autoritative    => 1,
    api_name        => 'open-ils.courses.course_users.retrieve.staff',
    signature       => q/
        Returns an array of course users.
        @params course_id: The id of the course we want to retrieve from
    /);

sub fetch_course_users {
    my ($self, $conn, $course_id) = @_;
    my $e = new_editor();
    my $filter = {};
    my $users = {};
    my %patrons;

    $filter->{course} = $course_id;
    $filter->{usr_role}->{is_public} = 't'
        unless ($self->api_name =~ /\.staff/) and $e->allowed('MANAGE_RESERVES');
 
 
    $users->{list} =  $e->search_asset_course_module_course_users($filter, {flesh => 1, flesh_fields => {acmcu => ['usr_role']}, order_by => {acmcu => 'id'}});
    for my $course_user (@{$users->{list}}) {
        my $patron = {};
        $patron->{id} = $course_user->id;
        $patron->{usr_role} = $course_user->usr_role;
        $patron->{patron_data} = $e->retrieve_actor_user($course_user->usr);
        $patrons{$course_user->usr} = $patron;
    }

    my $targets = ();
    for my $user (values %patrons) {
        my $final_user = {};
        $final_user->{id} = $user->{id};
        $final_user->{usr_role} = $user->{usr_role};
        $final_user->{patron_id} = $user->{patron_data}->id;
        $final_user->{first_given_name} = $user->{patron_data}->first_given_name;
        $final_user->{second_given_name} = $user->{patron_data}->second_given_name;
        $final_user->{family_name} = $user->{patron_data}->family_name;
        $final_user->{pref_first_given_name} = $user->{patron_data}->pref_first_given_name;
        $final_user->{pref_family_name} = $user->{patron_data}->pref_family_name;
        $final_user->{pref_second_given_name} = $user->{patron_data}->pref_second_given_name;
        $final_user->{pref_suffix} = $user->{patron_data}->pref_suffix;
        $final_user->{pref_prefix} = $user->{patron_data}->pref_prefix;

        push @$targets, $final_user;
    }

    return $targets;

}

__PACKAGE__->register_method(
    method          => 'detach_material',
    api_name        => 'open-ils.courses.detach_material',
    signature => {
        desc => 'Detaches a material from a course',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Course material id', type => 'number'},
        ],
        return => {desc => '1 on success, event on failure'}
    });
sub detach_material {
    my ($self, $conn, $authtoken, $acmcm_id) = @_;
    my $e = new_editor(authtoken=>$authtoken, xact=>1);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless
        $e->allowed('MANAGE_RESERVES');
    my $acmcm = $e->retrieve_asset_course_module_course_materials($acmcm_id)
        or return $e->die_event;
    my $bre_id_to_delete = $acmcm->temporary_record ? $acmcm->record : 0;
    if ($bre_id_to_delete) {
        # delete any attached located URIs
        my $located_uri_cn_ids = $e->search_asset_call_number(
            {record=>$bre_id_to_delete}, {idlist=>1});

        for my $cn_id (@$located_uri_cn_ids) {
            $e->delete_asset_call_number(
                $e->retrieve_asset_call_number($cn_id))
                or return $e->die_event;
        }
        OpenSRF::AppSession
            ->create('open-ils.cat')
            ->request('open-ils.cat.biblio.record_entry.delete',
                $authtoken, $bre_id_to_delete);
    }
    if ($acmcm->item) {
        _resetItemFields($e, $authtoken, $acmcm);
    } 

    $e->delete_asset_course_module_course_materials($acmcm) or return $e->die_event;
    $e->commit;
    return 1;
}

sub _resetItemFields {
    my ($e, $authtoken, $acmcm) = @_;
    my $cat_sess = OpenSRF::AppSession->connect('open-ils.cat');
    my $acp = $e->retrieve_asset_copy($acmcm->item);
    my $course_lib = $e->retrieve_asset_course_module_course($acmcm->course)->owning_lib;
    if ($acmcm->original_status) {
        $acp->status($acmcm->orginal_status);
    }
    if ($acmcm->original_circ_modifier) {
        $acp->status($acmcm->orginal_circ_modifier);
    }
    if ($acmcm->original_location) {
        $acp->status($acmcm->orginal_location);
    }
    $e->update_asset_copy($acmcm);
    if ($acmcm->original_callnumber) {
        my $existing_acn = $e->retrieve_asset_call_number($acp->call_number);
        # Let's attach to an existing call number, if one exists with the original label
        # and other appropriate specifications
        my $acn_id = cat_sess->request('open-ils.cat.call_number.find_or_create',
            $authtoken, $acmcm->original_callnumber,
            $existing_acn->record, $course_lib,
            $existing_acn->prefix, $existing_acn->suffix,
            $existing_acn->label_class)->acn_id;
        cat_sess->request('open-ils.cat.transfer_copies_to_volume',
            $authtoken, $acn_id, [$acp->id]);
    }
}



1;

