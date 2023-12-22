package OpenILS::Utils::BadContact;

use warnings;
use strict;

use OpenILS::Event;
use OpenILS::Utils::CStoreEditor;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;

my $U = "OpenILS::Application::AppUtils";

our $PENALTY_NAME_MAP = {
    email => "INVALID_PATRON_EMAIL_ADDRESS",
    day_phone => "INVALID_PATRON_DAY_PHONE",
    evening_phone => "INVALID_PATRON_EVENING_PHONE",
    other_phone => "INVALID_PATRON_OTHER_PHONE"
};

sub mark_users_contact_invalid {
    my (
        $class, $editor, $contact_type, $howfind,
        $addl_note, $penalty_ou, $staff_id
    ) = @_;

    if (not ref $howfind eq "HASH") {
        return new OpenILS::Event(
            "BAD_PARAMS", note => "howfind argument must be hash"
        );
    }

    if (not exists $PENALTY_NAME_MAP->{$contact_type}) {
        return new OpenILS::Event(
            "BAD_PARAMS", note => "contact_type argument invalid"
        );
    }

    my $penalty_name = $PENALTY_NAME_MAP->{$contact_type};

    # we can find either user-by-id, or user(s)-by-contact-info
    my $users;

    if (exists $howfind->{usr}) {
        # just the specified patron

        $users = $editor->search_actor_user({
            id => $howfind->{usr}, deleted => "f"
        }) or return $editor->die_event;

    } elsif (exists $howfind->{$contact_type}) {
        # all users with matching contact data

        $users = $editor->search_actor_user({
            $contact_type => $howfind->{$contact_type}, deleted => "f"
        }) or return $editor->die_event;
    }

    # waste no more time if no users collected
    return $editor->die_event(new OpenILS::Event("ACTOR_USER_NOT_FOUND"))
        unless $users and @$users;

    # we'll need this to apply user penalties
    my $penalty = $editor->search_config_standing_penalty({
        name => $penalty_name
    });

    return $editor->die_event unless $penalty and @$penalty;
    $penalty = $penalty->[0];

    if ($penalty_ou) {
        $penalty_ou = $U->org_unit_ancestor_at_depth(
            $penalty_ou, $penalty->org_depth) 
            if defined $penalty->org_depth;

    } else {
        # Fallback to using top of org tree if no penalty_ou provided. This
        # possibly makes sense in most cases anyway.

        my $results = $editor->json_query({
            "select" => {"aou" => ["id"]},
            "from" => {"aou" => {}},
            "where" => {"parent_ou" => undef}
        }) or return $editor->die_event;

        $penalty_ou = $results->[0]->{"id"};
    }

    my $last_xact_id_map = {};
    my $clear_meth = "clear_$contact_type";

    foreach (@$users) {
        if ($editor->requestor) {
            next unless $editor->allowed("UPDATE_USER", $_->home_ou);
        }

        my $usr_penalty = new Fieldmapper::actor::user_standing_penalty;
        $usr_penalty->usr($_->id);
        $usr_penalty->org_unit($penalty_ou);
        $usr_penalty->standing_penalty($penalty->id);
        $usr_penalty->staff($staff_id);

        my $message = $_->$contact_type;
        if (defined($addl_note) && $addl_note !~ /^\s*$/) {
            $message .= ' ' . $addl_note;
        }

        my ($result) = $U->simplereq('open-ils.actor', 'open-ils.actor.user.note.apply',
            $editor->authtoken,
            $usr_penalty,
            { message => $message }
        );

        # FIXME: this perpetuates a bug; the patron editor UI doesn't handle these error states well
        if ($result && ref $result eq 'HASH') {
            $editor->rollback;
            return $result;
        }

        $_->$clear_meth;
        $editor->update_actor_user($_) or return $editor->die_event;

        my $updated = $editor->retrieve_actor_user($editor->data);
        $last_xact_id_map->{$_->id} = $updated->last_xact_id;
    }

    $editor->commit or return $editor->die_event;

    return new OpenILS::Event(
        "SUCCESS", payload => {last_xact_id => $last_xact_id_map}
    );
}

1;
