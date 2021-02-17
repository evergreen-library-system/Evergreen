package OpenILS::Application::SIP2::Admin;
use strict; use warnings;
use base 'OpenILS::Application';
use OpenILS::Event;
use OpenILS::Application;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Application::AppUtils;

my $U = 'OpenILS::Application::AppUtils';

__PACKAGE__->register_method(
    method    => 'delete_setting_group',
    api_name  => 'open-ils.sip2.setting_group.delete',
    api_level => 1,
    argc      => 2,
    signature => {
        desc     => q/
            Takes a SIP2 JSON message and handles the request/,
        params   => [{   
            name => 'auth',
            desc => 'Authtoken',
            type => 'string'
        }, {
            name => 'del_grp_id',
            desc => 'Setting group ID to delete',
            type => 'number',
        }, {
            name => 'xfer_grp_id',
            desc => q/Setting group ID to use as account transfer destination.
                    If no destination group is specified, defaults to setting
                    group ID 1 (Defaults)/,
            type => 'number',
        }],
        return => {
            desc => q/1 on success, Event on error/,
            type => 'number | object'
        }
    }
);

sub delete_setting_group {
    my ($self, $client, $auth, $del_grp_id, $xfer_grp_id) = @_;
    $xfer_grp_id ||= 1; # Defaults Group
    
    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('SIP_ADMIN');

    return $e->die_event unless
        my $grp = $e->retrieve_sip_setting_group($del_grp_id);

    my $accounts = $e->search_sip_account({setting_group => $del_grp_id});

    for my $acc (@$accounts) {
        $acc->setting_group($xfer_grp_id);
        return $e->die_event unless $e->update_sip_account($acc);
    }

    # note: sip.setting objects are deleted via cascade
    return $e->die_event 
        unless $e->delete_sip_setting_group($grp) && $e->commit;

    return 1;
}

__PACKAGE__->register_method(
    method    => 'account_cud',
    api_name  => 'open-ils.sip2.account.cud',
    api_level => 1,
    argc      => 2,
    signature => {
        desc     => q/Create, Update, Delete SIP accounts.  If a value is
            stored in the virtual sip_password field on the account, the
            value will be used as the new password for the account/,
        params   => [{   
            name => 'auth',
            desc => 'Authtoken',
            type => 'string'
        }, {
            name => 'account',
            desc => 'SIP account object',
            type => 'object'
        }],
        return => {
            desc => q/Account object on success, Event on error/,
            type => 'object'
        }
    }
);

sub account_cud {
    my ($self, $client, $auth, $account) = @_;

    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('SIP_ADMIN');

    if ($account->sip_password) {
        my $pw = $e->json_query({from => ['actor.change_password', 
            $account->usr, $account->sip_password, 'sip2']});

        return $e->die_event unless $pw;
    }

    if ($account->isnew) {
        return $e->die_event unless $e->create_sip_account($account);
        
    } elsif ($account->ischanged) {
        return $e->die_event unless $e->update_sip_account($account);

    } elsif ($account->isdeleted) {
        return $e->die_event unless $e->delete_sip_account($account);
    }

    $account = $e->retrieve_sip_account($account->id);

    return $e->die_event unless $e->commit;

    return $account;
}


1;
