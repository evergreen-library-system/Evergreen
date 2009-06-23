package OpenILS::Application::Actor::Stage;
use strict; use warnings;
use base 'OpenILS::Application';
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenSRF::Utils::Logger q/$logger/;
use OpenILS::Utils::Fieldmapper;
my $U = "OpenILS::Application::AppUtils";


__PACKAGE__->register_method (
	method		=> 'create_user_stage',
	api_name    => 'open-ils.actor.user.stage.create',
);

sub create_user_stage {
    my($self, $conn, $user, $mail_addr, $bill_addr) = @_; # more?

    return 0 unless $U->ou_ancestor_setting_value('opac.allow_pending_user');
    return OpenILS::Event->new('BAD_PARAMS') unless $user;

    my $e = new_editor(xact => 1);

    my $uname = $U->create_uuid_string;
    $user->usrname($uname);

    $e->create_staging_user_stage($user) or return $e->die_event;

    if($mail_addr) {
        $mail_addr->usrname($uname);
        $e->create_staging_mailing_address_stage($mail_addr) or return $e->die_event;
    }

    if($bill_addr) {
        $bill_addr->usrname($uname);
        $e->create_staging_billing_address_stage($bill_addr) or return $e->die_event;
    }

    $e->commit;
    $conn->respond_complete($uname);

    $U->create_trigger_event('stgu.create', $user, $user->home_ou);
    return undef;
}

__PACKAGE__->register_method (
	method		=> 'user_stage_by_org',
	api_name    => 'open-ils.actor.user.stage.retrieve.by_org',
    stream      => 1
);

sub user_stage_by_org {
    my($self, $conn, $auth, $org_id, $limit, $offset) = @_;

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;
    $org_id ||= $e->requestor->ws_ou;
    return $e->event unless $e->allowed('VIEW_USER_STAGE', $org_id);

    $limit ||= 100;
    $offset ||= 0;

    my $stage_ids = $e->search_staging_user_stage(
        [
            {   home_ou => $org_id}, 
            {   limit => $limit, 
                offset => $offset, 
                order_by => {stgu => 'row_id'}
            }
        ],
        {idlist => 1}
    );

    $conn->respond(flesh_user_stage($e, $_)) for @$stage_ids;
    return undef;
}

sub flesh_user_stage {
    my($e, $row_id) = @_;
    my $user = $e->retrieve_staging_user_stage($row_id);
    return {
        user => $user,
        billing_address => $e->search_staging_billing_address_stage({usrname => $user->usrname})->[0],
        mailing_address => $e->search_staging_mailing_address_stage({usrname => $user->usrname})->[0],
        card => $e->search_staging_card_stage({usrname => $user->usrname})->[0],
        statcat => $e->search_staging_statcat_stage({usrname => $user->usrname})->[0],
    };
}

1;



