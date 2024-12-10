package OpenILS::OpenAPI::Controller::course;
use OpenILS::OpenAPI::Controller;
use OpenILS::Utils::CStoreEditor q/new_editor/;
use OpenILS::Application::AppUtils;

our $VERSION = 1;
our $U = "OpenILS::Application::AppUtils";

sub get_active_courses {
    my ($c, $ses, $orgs) = @_;

    my $search = {is_archived => 'f'};
    if ($orgs) {
        if (ref($orgs) and ref($orgs) eq 'ARRAY') {
            $orgs = [grep {/^\d+$/} @$orgs]; # just IDs, please
            $$search{owning_lib} = $orgs if (@$orgs);
        }
    }

    return new_editor(personality=>'open-ils.pcrud', authtoken=>$ses)->search_asset_course_module_course($search);
}

sub get_course_detail {
    my ($c, $ses, $c_id) = @_;

    my $course = new_editor(personality=>'open-ils.pcrud', authtoken=>$ses)->retrieve_asset_course_module_course([
        $c_id, {
            flesh => 1,
            flesh_fields => {
                acmc => [qw/owning_lib terms_map members/],
                acmcu => [qw/usr_role/],
                acmtcm => [qw/term/]
            }
        }
    ]);

    $course->members( [grep {$U->is_true($_->usr_role->is_public)} @{$course->members}] ); # only return is_public roles, if anything

    return $course;
}

sub get_course_materials {
    my ($c, $c_id) = @_;

    return $U->simplereq(
        'open-ils.courses',
        'open-ils.courses.course_materials.retrieve.fleshed.atomic',
        { course => $c_id }
    );
}

sub get_all_course_public_roles {
    return $U->simplereq( # so close! param-mapped literal must be a scalar, for now, so we have to wrap this call
        'open-ils.courses',
        'open-ils.courses.course_users.retrieve',
        { '!=' => undef }
    );
}

1;
