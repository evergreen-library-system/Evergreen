package OpenILS::OpenAPI::Controller::hold;
use OpenILS::OpenAPI::Controller;
use OpenILS::Utils::CStoreEditor q/new_editor/;
use OpenILS::Application::AppUtils;

our $VERSION = 1;
our $U = "OpenILS::Application::AppUtils";

sub open_holds {
    my ($c, $ses, $userid) = @_;
    return $U->simplereq(
        'open-ils.circ',
        'open-ils.circ.hold.details.batch.retrieve.atomic',
        $ses,
        $U->simplereq(
            'open-ils.circ',
            'open-ils.circ.holds.id_list.retrieve',
            $ses, $userid
        )
    );
}

sub cancel_user_hold {
    my ($c, $ses, $userid, $holdid, $reason) = @_;

    my $old_hold = new_editor()->retrieve_action_hold_request($holdid);
    if ($old_hold->usr ne $userid) {
        $c->res->message('Cannot update hold for a different patron');
        $c->res->code(403);
        return undef;
    }

    my $res = $U->simplereq('open-ils.circ', 'open-ils.circ.hold.cancel', $ses, $holdid, $reason);

    if ($res and !ref($res)) {
        $res = { errors => 0 };
    } else {
        $c->res->code(403);
    }

    return $res;
}

sub update_user_hold {
    my ($c, $ses, $userid, $holdid, $hold_patch) = @_;

    my $old_hold = new_editor()->retrieve_action_hold_request($holdid);
    if ($old_hold->usr ne $userid) {
        $c->res->message('Cannot update hold for a different patron');
        $c->res->code(403);
        return undef;
    }

    $$hold_patch{id} = $holdid;
    my $res = $U->simplereq('open-ils.circ', 'open-ils.circ.hold.update', $ses, undef, $hold_patch);

    if ($res and !ref($res)) {
        $res = { errors => 0 };
    } else {
        $c->res->code(403);
    }

    return $res;
}

sub request_hold {
    my ($c, $ses, $user_id, $hold_parts) = @_;

    if (!ref($hold_parts) or !($$hold_parts{bib} or $$hold_parts{copy}) or !$$hold_parts{pickup_lib}) {
        $c->res->message('Invalid hold request');
        $c->res->code(403);
        return undef;
    }

    my $type = $$hold_parts{bib} ? 'T' : 'C';
    my $new_hold = {
        patronid  => $user_id,
        hold_type => $type,
        pickup_lib => $$hold_parts{pickup_lib},
        expire_time => $$hold_parts{expire_time},
    };

    my $target = [ $$hold_parts{bib} || $$hold_parts{copy} ];
    my $result = $U->simplereq('open-ils.circ', 'open-ils.circ.holds.test_and_create.batch.override.atomic', $ses, $new_hold, $target)->[0];

    $$result{error} = (ref($result) && ref($$result{result})) ? 1 : 0;
    $c->res->code(403) if $$result{error};

    return $result;
}

sub fetch_user_hold {
    my ($controller, $ses, $usrid, $holdid) = @_;
    my $res = $U->simplereq(
        'open-ils.circ', 'open-ils.circ.hold.details.retrieve',
        $ses => $holdid
    );

    unless (ref($res) and $$res{hold} and $$res{hold}->usr == $usrid) {
        $controller->res->code(403);
        return undef;
    }
    return $res;
}

sub valid_hold_pickup_locations {
    my $e = new_editor();
    return $e->search_actor_org_unit({
        opac_visible => 't',
        ou_type      => $e->search_actor_org_unit_type(
            [{ can_have_vols => 't' }],
            { idlist => 1 }
        )
    });
}

1;
