package OpenILS::WWW::EGCatLoader;
use strict; use warnings;
use Apache2::Const -compile => qw(OK FORBIDDEN HTTP_INTERNAL_SERVER_ERROR);
use OpenSRF::Utils::Logger qw/$logger/;
use OpenSRF::Utils::JSON;
use OpenSRF::Utils qw/:datetime/;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::Cache;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Event;
use Data::Dumper;
use LWP::UserAgent;
use DateTime;
use Digest::MD5 qw(md5_hex);
use Time::HiRes qw(time);

$Data::Dumper::Indent = 0;
my $U = 'OpenILS::Application::AppUtils';

my $update_type = 'register';

my @api_fields_renew = (
    {name => 'vendor_username', required => 1},
    {name => 'vendor_password', required => 1},
    {name => 'email', class => 'au'},
    {name => 'day_phone', class => 'au', required => 1},
    {name => 'evening_phone', class => 'au'},
    {name => 'other_phone', class => 'au'},
    {name => 'home_ou', class => 'au'},
    {name => 'pref_first_given_name', class => 'au'},
    {name => 'pref_second_given_name', class => 'au'},
    {name => 'pref_family_name', class => 'au'},
    {name => 'pref_prefix', class => 'au'},
    {name => 'pref_suffix', class => 'au'},
    {name => 'usrname', class => 'au'},
    {name => 'expire_date', class => 'au'},
    {name => 'passwd', class => 'au'},
    {name => 'locale', class => 'au'},
    {name => 'physical_id', class => 'aua'},
    {name => 'physical_street1', class => 'aua'},
    {name => 'physical_street1_name'},
    {name => 'physical_street2', class => 'aua'},
    {name => 'physical_city', class => 'aua'},
    {name => 'physical_post_code', class => 'aua'},
    {name => 'physical_county', class => 'aua'},
    {name => 'physical_state', class => 'aua'},
    {name => 'physical_country', class => 'aua'},
    {name => 'mailing_id', class => 'aua'},
    {name => 'mailing_street1', class => 'aua'},
    {name => 'mailing_street1_name'},
    {name => 'mailing_street2', class => 'aua'},
    {name => 'mailing_city', class => 'aua'},
    {name => 'mailing_post_code', class => 'aua'},
    {name => 'mailing_county', class => 'aua'},
    {name => 'mailing_state', class => 'aua'},
    {name => 'mailing_country', class => 'aua'},
    {name => 'voter_registration', class => 'asvr'}
);

my @api_fields_register = (
    {name => 'vendor_username', required => 1},
    {name => 'vendor_password', required => 1},
    {name => 'first_given_name', class => 'au', required => 1},
    {name => 'second_given_name', class => 'au'},
    {name => 'family_name', class => 'au', required => 1},
    {name => 'suffix', class => 'au'},
    {name => 'email', class => 'au', required => 1},
    {name => 'passwd', class => 'au', required => 1},
    {name => 'day_phone', class => 'au', required => 0},
    {name => 'dob', class => 'au', required => 1},
    {name => 'home_ou', class => 'au', required => 1},
    {name => 'profile', class => 'au', required => 0},
    {name => 'expire_date', class => 'au', required => 0},
    {name => 'ident_type', class => 'au', required => 0},
    {name => 'ident_value', class => 'au', required => 0},
    {name => 'guardian',
     class => 'au', 
     notes => "AKA parent/guardian",
     required_if => ''
    },
    {name => 'guardian_email', class => 'au', required => 0},
    {name => 'pref_first_given_name', class => 'au'},
    {name => 'pref_second_given_name', class => 'au'},
    {name => 'pref_family_name', class => 'au'},
    {name => 'pref_suffix', class => 'au'},
    {name => 'physical_street1', class => 'aua', required => 1},
    {name => 'physical_street1_name'},
    {name => 'physical_street2', class => 'aua'},
    {name => 'physical_city', class => 'aua', required => 1},
    {name => 'physical_post_code', class => 'aua', required => 1},
    {name => 'physical_county', class => 'aua', required => 1},
    {name => 'physical_state', class => 'aua', required => 1},
    {name => 'physical_country', class => 'aua', required => 1},
    {name => 'mailing_street1', class => 'aua', required => 1},
    {name => 'mailing_street1_name'},
    {name => 'mailing_street2', class => 'aua'},
    {name => 'mailing_city', class => 'aua', required => 1},
    {name => 'mailing_post_code', class => 'aua', required => 1},
    {name => 'mailing_county', class => 'aua', required => 1},
    {name => 'mailing_state', class => 'aua', required => 1},
    {name => 'mailing_country', class => 'aua', required => 1},
    {name => 'voter_registration', class => 'asvr', required => 0},
    {name => 'in_house_registration', required => 0},
);

# Sets the values for Quipu ecard settings in the context ($ctx)
sub _set_ecard_context {
    my $self = shift;
    my $ctx = $self->ctx;
    my $ctx_org = $ctx->{physical_loc} || $self->_get_search_lib();

    $ctx->{ecard} = {};
    $ctx->{ecard}->{enabled} = $U->is_true($U->ou_ancestor_setting_value(
        $ctx_org, 'opac.ecard_registration_enabled'
    ));
    $ctx->{ecard}->{renew_enabled} = $U->is_true($U->ou_ancestor_setting_value(
        $ctx_org, 'opac.ecard_renewal_enabled'
    ));
    $ctx->{ecard}->{quipu_id} = $U->ou_ancestor_setting_value(
        $ctx_org, 'vendor.quipu.ecard.account_id'
    ) || 0;
    $ctx->{ecard}->{hostname} = $U->ou_ancestor_setting_value(
        $ctx_org, 'vendor.quipu.ecard.hostname'
    ) || 'ecard.quipugroup.net';
    $logger->debug(
        "ECARD: context = " . OpenSRF::Utils::JSON->perl2JSON( $ctx->{ecard} ));
}

sub load_ecard_form {
    my $self = shift;
    my $ctx = $self->ctx;
    $self->_set_ecard_context;
    return Apache2::Const::OK;
}

sub load_ecard_renew {
    my $self = shift;
    my $ctx = $self->ctx;
    $self->_set_ecard_context;
    return Apache2::Const::OK;
}

# TODO: wrap the following in a check for a library setting as to whether or not
# to require emailed verification

# Random 6-character alpha-numeric code that avoids look-alike characters
# https://ux.stackexchange.com/questions/53341/are-there-any-letters-numbers-that-should-be-avoided-in-an-id
# Also exclude vowels to avoid creating any real (potentially offensive) words.
my @code_chars = ('C','D','F','H','J'..'N','P','R','T','V','W','X','3','4','7','9');
sub generate_verify_code {
    my $string = '';
    $string .= $code_chars[rand @code_chars] for 1..6;
    return $string;
}

# only if we're verifying the card via email
sub load_ecard_verify {
    my $self = shift;
    $self->collect_header_footer;

    # Loading the form.
    return Apache2::Const::OK if $self->cgi->request_method eq 'GET';

    #$self->verify_ecard;
    return Apache2::Const::OK;
}

sub verify_ecard {
    my $self = shift;
    my $ctx = $self->ctx;
    $self->log_params;

    my $ctx_org = $ctx->{physical_loc} || $self->_get_search_lib();
    my $verify_code = $ctx->{verify_code} = $self->cgi->param('verification_code');
    my $barcode = $ctx->{barcode} = $self->cgi->param('barcode');

    $ctx->{verify_failed} = 1;

    my $e = new_editor();

    my $perm_grp = $U->ou_ancestor_setting_value(
        $ctx_org,
        # there's an edge case here where the ctx_org and the patron's home_ou could have different values for this setting :-/
        # It's also possible for Quipu to override the setting and select a different profile.
        'vendor.quipu.ecard.patron_profile'
    );

    my $au = $e->search_actor_user({
        profile => $perm_grp,
        # ident_type => $ECARD_VERIFY_IDENT, # I think this is a good idea, if we can keep staff from using this ident type by accident
        ident_value2 => $verify_code
    })->[0];

    my $verified_perm_grp = $U->ou_ancestor_setting_value(
        $au->home_ou, # Let's let home_ou trump $ctx_org, just in case
        'vendor.quipu.ecard.patron_profile.verified'
    ) || $perm_grp;

    if (!$au) {
        $logger->warn(
            "ECARD: No provisional ecard found with code $verify_code");
        sleep 2; # Mitigate brute-force attacks
        return;
    }

    my $card = $e->search_actor_card({
        usr => $au->id,
        barcode => $barcode
    })->[0];

    if (!$card) {
        $logger->warn("ECARD: Failed to match verify code ".
            "($verify_code) with provided barcode ($barcode)");
        sleep 2; # Mitigate brute-force attacks
        return;
    }

    # Verification looks good.  Update the account.

    my $grp = new_editor()->retrieve_permission_grp_tree($verified_perm_grp);

    $au->profile($grp->id);
    $au->expire_date(
        $self->cgi->param('expire_date') ||
        DateTime->now(time_zone => 'local')->add(
            seconds => interval_to_seconds($grp->perm_interval))->iso8601()
    );

    $e->xact_begin;

    unless ($e->update_actor_user($au)) {
        $logger->error("ECARD update failed for $barcode: " . $e->die_event);
        return;
    }

    $e->commit;
    $logger->info("ECARD: Update to full ecard succeeded for $barcode");

    $ctx->{verify_success} = 1;
    $ctx->{verify_failed} = 0;

    return;
}

sub verify_ecard_token {
    my ($self, $token, $shared_secret) = @_;

    $logger->debug("ECARD: Working with raw token = $token");
    $logger->debug("ECARD: and shared_secret = $shared_secret");

    my ($timestamp, $signature) = split ':', $token;
    $logger->debug("ECARD: Split into timestamp=$timestamp signature=$signature");

    my $now = int(time()); # Time::HiRes gives us milliseconds
    $timestamp = int($timestamp); # let's ensure integer comparison, though
    $logger->debug("ECARD: Cast to integers, timestamp=$timestamp now=$now");

    # Check if token is not too old (e.g., within last 6 minutes)
    my $historic_date = $now - 360*1000;
    if ($timestamp < $historic_date) {
        $logger->debug("ECARD: $timestamp less than $historic_date, too old");
        return 0;
    }
    # Check if token is too much from the future (1 minute)
    my $futuristic_date = $now + 60*1000;
    if ($timestamp > $futuristic_date) {
        $logger->debug("ECARD: $timestamp greater than $futuristic_date, too far into the future");
        return 0;
    }

    my $expected_signature = $self->generate_ecard_signature($timestamp, $shared_secret);
    $logger->debug("ECARD: signature = $signature, expected signature = $expected_signature");
    return $signature eq $expected_signature;
}

sub generate_ecard_signature {
    my ($self, $timestamp, $shared_secret) = @_;
    return md5_hex($timestamp . $shared_secret);
}

sub check_ecard_token {
    my $self = shift;
    my $ctx = $self->ctx;
    my $ctx_org = $ctx->{physical_loc} || $self->_get_search_lib();

    my $token = $self->cgi->param('security_token');
    $logger->debug("ECARD: Received security_token = $token");
    my $shared_secret = $ctx->{get_org_setting}->($ctx_org, 'vendor.quipu.ecard.shared_secret');
    $logger->debug("ECARD: shared_secret = $shared_secret");

    return 0 unless $token and $shared_secret;

    return $self->verify_ecard_token($token, $shared_secret);
}

sub log_params {
    my $self = shift;
    my @params = $self->cgi->param;

    my $msg = '';
    for my $p (@params) {
        next if $p =~ /pass/;
        $msg .= "|" if $msg; 
        $msg .= "$p=".$self->cgi->param($p);
    }

    $logger->info("ECARD: Submit params: $msg");
}

sub handle_testmode_api {
    my $self = shift;
    my $ctx = $self->ctx;

    # Strip data we don't want to publish.
    my @doc_fields;
    for my $field_info (@api_fields_register) {
        my $doc_info = {};
        for my $info_key (keys %$field_info) {
            $doc_info->{$info_key} = $field_info->{$info_key} 
                unless $info_key eq 'class';
        }
        push(@doc_fields, $doc_info);
    }

    $ctx->{response}->{messages} = [fields => \@doc_fields];
    $ctx->{response}->{status} = 'API_OK';

    return $self->compile_response;
}

sub handle_datamode_api {
    my $self = shift;
    my $datamode = shift;
    my $ctx = $self->ctx;

    $ctx->{response}->{messages} = [ {} ];

    if ($datamode eq 'all') {
        $datamode = 'org_units|ident_types|sms_carriers';
    }

    if ($datamode =~ /org_units/) {
        my $orgs = new_editor()->search_actor_org_unit({opac_visible => 't'});
        my $org_list = [
            map { 
                {name => $_->name, id => $_->id, parent_ou => $_->parent_ou} 
            } @$orgs
        ];
        $ctx->{response}->{messages}->[0]->{org_units} = $org_list;
    }

    if ($datamode =~ /ident_types/) {
        my $ident_types = new_editor()->search_config_identification_type({id => {'!=' => -1}});
        my $itype_list = [
            map { 
                {name => $_->name, id => $_->id}
            } @$ident_types
        ];
        $ctx->{response}->{messages}->[0]->{ident_types} = $itype_list;
    }

    if ($datamode =~ /sms_carriers/) {
        my $sms_carriers = new_editor()->search_config_sms_carrier({id => {'!=' => -1}});
        my $carrier_list = [
            map { 
                {name => $_->name, id => $_->id, email_gateway => $_->email_gateway, active => $_->active }
            } @$sms_carriers
        ];
        $ctx->{response}->{messages}->[0]->{sms_carriers} = $carrier_list;
    }

    $ctx->{response}->{status} = 'DATA_OK';

    return $self->compile_response;
}

sub load_ecard_submit {
    my $self = shift;
    my $ctx = $self->ctx;

    #determine whether this is a new registration or a renewal
    if ($self->cgi->param('patron_id') > 1) {
        $update_type = 'renew';
    } else {
        $update_type = 'register';
    }
    $logger->debug(
        "ECARD: update_type = $update_type");

    #If this is a renewal, double-check that they are eligible to renew
    my $cache = OpenSRF::Utils::Cache->new('global');
    my $key = 'account_renew_ok_' . $self->cgi->param('patron_id');
    my $account_renew_ok = $cache->get_cache($key);
    if ($update_type eq 'renew') {
        if ($ctx->{ecard}->{renew_enabled} && defined $account_renew_ok && $account_renew_ok eq 'true') {
        } else {
            $logger->error('ECARD: ERENEW - User not in correct status to renew account');
            $logger->error("ECARD: ERENEW - renew_enabled = $ctx->{ecard}->{renew_enabled}");
            $logger->error("ECARD: ERENEW - cache key = $key");
            if (defined $account_renew_ok) {
                $logger->error("ECARD: ERENEW - account_renew_ok = $account_renew_ok");
            } else {
                $logger->error('ECARD: ERENEW - account_renew_ok = undef');
            }
            return $self->compile_response;
        }
    }

    $self->log_params;

    my $testmode = $self->cgi->param('testmode') || '';
    my $datamode = $self->cgi->param('datamode') || '';

    $logger->debug(
        "ECARD: testmode = $testmode, datamode = $datamode");

    my $e = $ctx->{editor} = new_editor();
    $ctx->{response} = {messages => []};

    if ($testmode eq 'CONNECT') {
        $ctx->{response}->{status} = 'CONNECT_OK';
        return $self->compile_response;
    }

    my $forbidden_reason;

    if ($self->cgi->request_method ne 'POST') {
        $forbidden_reason = "Invalid request method: " . $self->cgi->request_method;
    } elsif (!$self->verify_vendor_host) {
        $forbidden_reason = "Failed vendor host verification";
    } elsif (!$self->login_vendor) {
        $forbidden_reason = "Failed vendor login";
    } elsif (!$self->check_ecard_token) {
        $forbidden_reason = "Invalid or expired security token";
    }

    if ($forbidden_reason) {
        $logger->error("ECARD: Access forbidden - $forbidden_reason");
        return Apache2::Const::FORBIDDEN;
    }

    if ($testmode eq 'AUTH') {
        # If we got this far, the caller is authorized.
        $ctx->{response}->{status} = 'AUTH_OK';
        return $self->compile_response;
    }

    return $self->handle_testmode_api if $testmode eq 'API';
    return $self->handle_datamode_api($datamode) if $datamode;

    # Accommodate reg vs renew
    if ($update_type eq 'register') {
        $logger->debug( "ECARD: make_user" );
        return $self->compile_response unless $self->make_user;
        $logger->debug( "ECARD: add_addresses" );
        return $self->compile_response unless $self->add_addresses;
        $logger->debug( "ECARD: check_username" );
        return $self->compile_response unless $self->check_username;
        $logger->debug( "ECARD: check_dupes" );
        return $self->compile_response unless $self->check_dupes;
        $logger->debug( "ECARD: add_card" );
        return $self->compile_response unless $self->add_card;
        $logger->debug( "ECARD: add_survey_responses" );
        return $self->compile_response unless $self->add_survey_responses;
        $logger->debug( "ECARD: add_stat_cats" );
        return $self->compile_response unless $self->add_stat_cats;
        $logger->debug( "ECARD: save_user" );
        return $self->compile_response unless $self->save_user;
        $logger->debug( "ECARD: add_usr_settings" );
        return $self->compile_response unless $self->add_usr_settings;
        $logger->debug( "ECARD: response->status = $ctx->{response}->{status}" );
        return $self->compile_response if $ctx->{response}->{status};

        $logger->debug( "ECARD: au.create.ecard" );
        $U->create_events_for_hook(
            'au.create.ecard', $ctx->{user}, $ctx->{user}->home_ou);
    } else {
        $logger->debug( "ECARD: update_user" );
        return $self->compile_response unless $self->update_user;
        $logger->debug( "ECARD: update_addresses" );
        return $self->compile_response unless $self->update_addresses;
        $logger->debug( "ECARD: check_username_for_renewal" );
        return $self->compile_response unless $self->check_username_for_renewal;
        $logger->debug( "ECARD: add_survey_responses" );
        return $self->compile_response unless $self->add_survey_responses;
        $logger->debug( "ECARD: add_stat_cats" );
        return $self->compile_response unless $self->add_stat_cats; # TODO: test
        $logger->debug( "ECARD: save_user" );
        return $self->compile_response unless $self->save_user;
        $logger->debug( "ECARD: add_usr_settings" );
        return $self->compile_response unless $self->add_usr_settings;
        $logger->debug( "ECARD: response->status = $ctx->{response}->{status}" );
        return $self->compile_response if $ctx->{response}->{status};

        $logger->debug( "ECARD: ERENEW - au.erenewal" );
        $U->create_events_for_hook(
            'au.erenewal', $ctx->{user}, $ctx->{user}->home_ou);
    }

    # Add extra info to response message
    $logger->debug( "ECARD: OK" );
    $ctx->{response}->{status} = 'OK';

    if ($update_type eq 'renew') {
        $logger->debug( "ECARD: renew" );
        #New expiration date
        $ctx->{response}->{expire_date} = $ctx->{user}->expire_date;
        #Mark whether this is a temporary renewal or not
        my $findpenalty_temp = $e->search_config_standing_penalty({name => 'PATRON_TEMP_RENEWAL'})->[0];
        my $searchpenalty_temp = $e->search_actor_user_standing_penalty({
            usr => $self->cgi->param('patron_id'),
            standing_penalty => $findpenalty_temp->id,
            '-or' => [
                {stop_date => undef},
                {stop_date => {'>' => 'now'}}
            ]
        });
        if (@$searchpenalty_temp) {
            $ctx->{response}->{temp_renew} = 1;
        } else {
            $ctx->{response}->{temp_renew} = 0;
        }
        #set renewal flag in cache to false to prevent user from refreshing the page and submitting again
        #$cache->put_cache('account_renew_ok_' . $self->cgi->param('patron_id'),'false',3600);
    } else {
        $logger->debug( "ECARD: register" );
        $ctx->{response}->{patron_id} = $ctx->{user}->id;
        $ctx->{response}->{barcode} = $ctx->{user}->card->barcode;
        $ctx->{response}->{expiration_date} = substr($ctx->{user}->expire_date, 0, 10);
    }

    $logger->debug(
        "ECARD: response = " . OpenSRF::Utils::JSON->perl2JSON( $ctx->{response} ));
    return $self->compile_response;
}

# E-card vendor is not a regular account.  They must have an entry in 
# the password table with password type ecard_vendor.
sub login_vendor {
    my $self = shift;
    my $username = $self->cgi->param('vendor_username');
    my $password = $self->cgi->param('vendor_password');
    my $home_ou = $self->cgi->param('home_ou');

    my $e = new_editor();
    my $vendor = $e->search_actor_user({usrname => $username})->[0];
    return 0 unless $vendor;

    return unless $U->verify_user_password(
        $e, $vendor->id, $password, 'ecard_vendor');

    # Auth checks out OK.  Manually create an authtoken
    my %admin_settings = $U->ou_ancestor_setting_batch_insecure(
        $home_ou,
        [
            'vendor.quipu.ecard.admin_usrname',
            'vendor.quipu.ecard.admin_org_unit'
        ]
    );
    my $admin_usr = $e->search_actor_user({usrname => $admin_settings{'vendor.quipu.ecard.admin_usrname'}->{'value'}})->[0]
        || $vendor;
    my $admin_org = $admin_settings{'vendor.quipu.ecard.admin_org_unit'}->{'value'} || 1;
    my $auth = $U->simplereq(
        'open-ils.auth_internal',
        'open-ils.auth_internal.session.create',
        {user_id => $admin_usr->id(), org_unit => $admin_org, login_type => 'temp'}
    );

    return unless $auth && $auth->{textcode} eq 'SUCCESS';

    $self->ctx->{vendor_authtoken} = $auth->{payload}->{authtoken};

    return 1;
}

sub verify_vendor_host {
    my $self = shift;
    # TODO
    # Confirm calling host matches AOUS ecard.vendor.host
    # NOTE: we may not have that information inside the firewall.
    return 1;
}

sub compile_response {
    my $self = shift;
    my $ctx = $self->ctx;

    $self->apache->content_type("application/json; charset=utf-8");
    $ctx->{response} = OpenSRF::Utils::JSON->perl2JSON($ctx->{response});
    $logger->info("ECARD responding with " . $ctx->{response});

    return Apache2::Const::OK;
}

# Create actor.usr perl object and populate column data (for new registration)
sub make_user {
    $logger->debug( "ECARD: making user..." );
    my $self = shift;
    my $ctx = $self->ctx;

    my $au = Fieldmapper::actor::user->new;
    my $in_house = $self->cgi->param('in_house_registration');

    $au->isnew(1);
    $au->net_access_level(1); # Filtered
    $au->name_keywords($in_house ? 'quipu_inhouse' : 'quipu_remote');

    my $home_ou = $self->cgi->param('home_ou');
    $logger->debug( "ECARD: home_ou = $home_ou" );

    my $default_ident_type = new_editor()->search_config_identification_type({id => {'!=' => -1}})->[0]->id;
    # these can get overridden, but they're required
    $au->ident_type( $default_ident_type );
    $au->ident_type2( $default_ident_type );

    if ($U->ou_ancestor_setting_value(
        $home_ou,
        'opac.ecard_verification_enabled'
    )) {
        $logger->debug( "ECARD: ecard_verification_enabled" );
        # TODO: give ident_type2 some thought
        $au->ident_value2( generate_verify_code() );
        $logger->warn( "ECARD: verify code generated " );
    }

    my $top_of_perm_tree = new_editor()->search_permission_grp_tree({parent => undef})->[0];
    my $perm_grp = $top_of_perm_tree->id; # "just in case" default
    my $perm_grp_setting = $U->ou_ancestor_setting_value( $home_ou, 'vendor.quipu.ecard.patron_profile');
    if ($perm_grp_setting) {
        if (ref $perm_grp_setting) { # not sure what to expect yet
            $perm_grp = $perm_grp_setting->id;
        } else {
            $perm_grp = $perm_grp_setting;
        }
    }
    my $profile = $self->cgi->param('profile');
    if ($profile) {
        if ($profile =~ /^\d+$/) {
            my $profile_search_by_id = new_editor()->retrieve_permission_grp_tree($profile);
            if ($profile_search_by_id) {
                $perm_grp = $profile_search_by_id->id;
            }
        } else {
            my $profile_search_by_name = new_editor()->search_permission_grp_tree({name => $profile});
            if (scalar(@{ $profile_search_by_name }) > 0) {
                $perm_grp = $profile_search_by_name->[0]->id;
            }
        }
    }
    $logger->debug( "ECARD: perm_grp = $perm_grp" );

    my $grp = new_editor()->retrieve_permission_grp_tree($perm_grp);
    if (!$grp) {
        $logger->error("ECARD: bad user profile ($perm_grp), defaulting to $top_of_perm_tree->name");
        $grp = $top_of_perm_tree;
    }
    $au->profile($grp->id);

    $au->expire_date(
        DateTime->now(time_zone => 'local')->add(
            seconds => interval_to_seconds($grp->perm_interval))->iso8601()
    );

    # more defaults
    
   
    # provided fields
    $logger->debug( "ECARD: looping through register fields..." );
    for my $field_info (@api_fields_register) {
        my $field = $field_info->{name};
        next unless $field_info->{class} eq 'au';

        my $val = $self->cgi->param($field);

        $au->juvenile(1) if $field eq 'guardian' && $val;
        $au->day_phone(undef) if $field eq 'day_phone' && $val eq '--';

        if ($field_info->{required} && !$val) {
            my $msg = "Value required for field: '$field'";
            $ctx->{response}->{status} = 'INVALID_PARAMS';
            push(@{$ctx->{response}->{messages}}, $msg);
            $logger->error("ECARD: error = $msg");
        }

        $self->verify_dob($val) if $field eq 'dob' && $val;

        $au->$field($val);
    }

    # TODO: fix patron editor so that guardian_email shows up; temporary kludge until then
    #if ($self->cgi->param('guardian_email')) {
    #    $logger->debug( "ECARD: email, guardian_email concatenation kludge" );
    #    my $email = $self->cgi->param('email')
    #        ? $self->cgi->param('email') . ',' . $self->cgi->param('guardian_email')
    #        : $self->cgi->param('guardian_email');
    #    $au->email($email);
    #}
    $logger->debug( "ECARD: finished looping through register fields..." );
    $logger->debug( "ECARD: response->status = $ctx->{response}->{status}" );

    return undef if $ctx->{response}->{status}; 
    $logger->debug(
        "ECARD: user = " . OpenSRF::Utils::JSON->perl2JSON( $au ));
    $ctx->{user} = $au;
    return $ctx->{user};
}

# If existing account, update instead of create
sub update_user {

    my $self = shift;
    my @extra_flesh = @_;
    my $e = $self->editor;
    my $ctx = $self->ctx;

    # Grab user id, retrieve patron info from db and create patron object
    my $patron_id = $self->cgi->param('patron_id');

    my $au = $self->editor->retrieve_actor_user([$patron_id, 
        {
            flesh => 1,
            flesh_fields => {
                au => ['billing_address', 'mailing_address', 'groups', 'permissions', 'standing_penalties', 'settings']
            }
        }
    ]);
    #indicate that this is an update, not a new record
    $au->isnew(0);
    
    # Replace values in patron object with new data

    # Need to append new keyword for use in reports later
    my $orig_kw = $au->name_keywords;
    my $dt = DateTime->now;
    my $dty = $dt->year;
    my $dtm = $dt->month;
    if ($orig_kw ne '') {
        $au->name_keywords("$orig_kw quipu_renew_$dty$dtm");
    } else {
        $au->name_keywords("quipu_renew_$dty$dtm");
    }

    my $temp_renewal = $self->cgi->param('temp_renewal');
    my $grp = new_editor()->retrieve_permission_grp_tree($au->profile);

    if ($temp_renewal eq '1') {
        # Add temp renewal standing penalty to account
        $self->apply_temp_renewal_penalty;

        $au->expire_date(
            DateTime->now(time_zone => 'local')->add(
                seconds => interval_to_seconds($grp->temporary_perm_interval || '30 days'))->iso8601()
        );
    } else {
        $au->expire_date(
            DateTime->now(time_zone => 'local')->add(
                seconds => interval_to_seconds($grp->perm_interval))->iso8601()
        );
    }

    # loop through fields submitted by quipu
    for my $field_info (@api_fields_renew) {
        my $field = $field_info->{name};
        next unless $field_info->{class} eq 'au';

        my $val = $self->cgi->param($field);

        if ($field_info->{required} && !$val) {
            my $msg = "Value required for field: '$field'";
            $ctx->{response}->{status} = 'INVALID_PARAMS';
            push(@{$ctx->{response}->{messages}}, $msg);
            $logger->error("E-RENEW $msg");
        }

        $val = undef if $field eq 'day_phone' && $val eq '--';
        $val = undef if $field eq 'evening_phone' && $val eq '--';
        $val = undef if $field eq 'other_phone' && $val eq '--';
        $val = $au->home_ou if $field eq 'home_ou' && $val eq '';

        if ($field eq 'expire_date') {
            if (!$val) {
                next; # don't change expire_date if not explicitly passed
            }
        }

        # avoid emptying the password
        next if $field eq 'passwd' && !$val;

        $au->$field($val);
    }

    return $ctx->{user} = $au;
}

# Card generation must occur after the user is saved in the DB.
sub add_card {
    my $self = shift;
    my $ctx = $self->ctx;
    my $user = $ctx->{user};
    my $home_ou = $self->cgi->param('home_ou');

    my %settings = $U->ou_ancestor_setting_batch_insecure(
        $home_ou,
        [
            'vendor.quipu.ecard.barcode_prefix',
            'vendor.quipu.ecard.barcode_length',
            'vendor.quipu.ecard.calculate_checkdigit'
        ]
    );
    my $prefix = $settings{'vendor.quipu.ecard.barcode_prefix'}->{'value'}
        || 'AUTO';
    my $length = $settings{'lib.card_barcode_length'}->{'value'}
        || 14;
    my $cd = $settings{'vendor.quipu.ecard.calculate_checkdigit'}->{'value'}
        || 0;

    my $barcode = $U->generate_barcode(
        $prefix,
        $length,
        $U->is_true($cd),
        'actor.auto_barcode_ecard_seq'
    );

    $logger->info("ECARD using generated barcode: $barcode");

    my $card = Fieldmapper::actor::card->new;
    $card->id(-1);
    $card->isnew(1);
    $card->usr($user->id);
    $card->barcode($barcode);

    $user->usrname($self->cgi->param('usrname') || $barcode);
    $user->card($card);
    $user->cards([$card]);

    return 1;
}

# Returns 1 on success, undef on error.
sub verify_dob {
    my $self = shift;
    my $dob = shift;
    my $ctx = $self->ctx;

    my @parts = split(/-/, $dob);
    my $dob_date;

    eval { # avoid dying on funky dates
        $dob_date = DateTime->new(
            year => $parts[0], month => $parts[1], day => $parts[2]);
    };

    if (!$dob_date || $dob_date > DateTime->now) {
        my $msg = "Invalid dob: '$dob'";
        $ctx->{response}->{status} = 'INVALID_PARAMS';
        push(@{$ctx->{response}->{messages}}, $msg);
        $logger->error("ECARD $msg");
        return undef;
    }

    # Check if guardian required for underage patrons.
    # TODO: Add our own setting for this.
    my $guardian_required = $U->ou_ancestor_setting_value(
        $self->cgi->param('home_ou'),
        'ui.patron.edit.guardian_required_for_juv'
    );

    my $comp_date = DateTime->now;
    $comp_date->set_hour(0);
    $comp_date->set_minute(0);
    $comp_date->set_second(0);
    # The juvenile age should be configurable.
    $comp_date->subtract(years => 18); # juv age

    if ($U->is_true($guardian_required)
        && $dob_date > $comp_date
        && !$self->cgi->param('guardian')) {

        my $msg = "Parent/Guardian (guardian) is required for patrons ".
            "under 18 years of age. dob=$dob";
        $ctx->{response}->{status} = 'INVALID_PARAMS';
        push(@{$ctx->{response}->{messages}}, $msg);
        $logger->error("ECARD $msg");
        return undef;
    }

    return 1;
}

sub add_addresses {
    my $self = shift;
    my $ctx = $self->ctx;
    my $e = $ctx->{editor};
    my $user = $ctx->{user};

    my $physical_addr = Fieldmapper::actor::user_address->new;
    $physical_addr->isnew(1);
    $physical_addr->usr($user->id);
    $physical_addr->address_type('PHYSICAL');
    $physical_addr->within_city_limits('f');

    my $mailing_addr = Fieldmapper::actor::user_address->new;
    $mailing_addr->isnew(1);
    $mailing_addr->usr($user->id);
    $mailing_addr->address_type('MAILING');
    $mailing_addr->within_city_limits('f');

   # Use as both billing and mailing via virtual ID.
    $physical_addr->id(-1);
    $mailing_addr->id(-2);
    $user->billing_address(-1);
    $user->mailing_address(-2);

    # Confirm we have values for all of the required fields.
    # Apply values to our in-progress address object.
    for my $field_info (@api_fields_register) {
        my $field = $field_info->{name};
        next unless $field =~ /physical|mailing/;
        next if $field =~ /street1_/;

        my $val = $self->cgi->param($field);

        if ($field_info->{required} && !$val) {
            my $msg = "Value required for field: '$field'";
            $ctx->{response}->{status} = 'INVALID_PARAMS';
            push(@{$ctx->{response}->{messages}}, $msg);
            $logger->error("ECARD $msg");
        }

        if ($field =~ /physical/) {
            (my $col_field = $field) =~ s/physical_//g;
            $physical_addr->$col_field($val) if $val;
        } else {
            (my $col_field = $field) =~ s/mailing_//g;
            $mailing_addr->$col_field($val) if $val;
        }

    }

    # exit if there were any errors above.
    return undef if $ctx->{response}->{status}; 

    $user->billing_address($physical_addr);
    $user->mailing_address($mailing_addr);
    $user->addresses([$physical_addr, $mailing_addr]);

    return 1;
}

sub update_addresses {
    my $self = shift;
    my $ctx = $self->ctx;
    my $e = $ctx->{editor};
    my $user = $ctx->{user};

    my $physical_addr = Fieldmapper::actor::user_address->new;
    $physical_addr->id($user->billing_address->id);
    $physical_addr->usr($user->id);
    $physical_addr->address_type('PHYSICAL');
    $physical_addr->within_city_limits($user->billing_address->within_city_limits);
    $physical_addr->valid('t');
    $physical_addr->pending('f');

    my $mailing_addr = Fieldmapper::actor::user_address->new;
    $mailing_addr->id($user->mailing_address->id);
    $mailing_addr->usr($user->id);
    $mailing_addr->address_type('MAILING');
    $mailing_addr->within_city_limits($user->mailing_address->within_city_limits);
    $mailing_addr->valid('t');
    $mailing_addr->pending('f');

    # Confirm we have values for all of the required fields.
    # Apply values to our in-progress address object.
    for my $field_info (@api_fields_renew) {
        my $field = $field_info->{name};
        next unless $field =~ /physical|mailing/;
        next if $field =~ /street1_/;

        my $val = $self->cgi->param($field);

        if ($field_info->{required} && !$val) {
            my $msg = "Value required for field: '$field'";
            $ctx->{response}->{status} = 'INVALID_PARAMS';
            push(@{$ctx->{response}->{messages}}, $msg);
            $logger->error("E-RENEW $msg");
        }

        if ($field =~ /physical/) {
            (my $col_field = $field) =~ s/physical_//g;
            $physical_addr->$col_field($val) if $val;
        } else {
            (my $col_field = $field) =~ s/mailing_//g;
            $mailing_addr->$col_field($val) if $val;
        }
    }

    # Determine what exactly to do with addresses
    if ($physical_addr->id eq $mailing_addr->id && $physical_addr->street1 eq $mailing_addr->street1) {
        # if one address & stays at one address, just update it (don't need to do both physical & mailing)
        $mailing_addr->isnew(0);
        $mailing_addr->ischanged(1);
    } elsif ($physical_addr->id eq $mailing_addr->id && $physical_addr->street1 ne $mailing_addr->street1) {
        # if one address splitting to two addresses, update the first and create a second address entry
        $physical_addr->isnew(0);
        $physical_addr->ischanged(1);
        $mailing_addr->isnew(1);
        $mailing_addr->id(-1);
    } elsif ($physical_addr->id ne $mailing_addr->id && $physical_addr->street1 eq $mailing_addr->street1) {
        # if there were previously 2 addresses, but there is only one address now, use the updated single address entry for both
        $physical_addr->isnew(0);
        $physical_addr->ischanged(1);
        $mailing_addr->isnew(0);
        $mailing_addr->ischanged(1);
        $mailing_addr->id($physical_addr->id);
    } else {
        # otherwise, update existing entries
        $physical_addr->isnew(0);
        $physical_addr->ischanged(1);
        $mailing_addr->isnew(0);
        $mailing_addr->ischanged(1);
    }

    # exit if there were any errors above.
    return undef if $ctx->{response}->{status}; 

    $user->billing_address($physical_addr);
    $user->mailing_address($mailing_addr);
    $user->addresses([$physical_addr, $mailing_addr]);

    return 1;
}

# TODO: The code in add_usr_settings is totally arbitrary and should
# be modified to look up settings in the database.
sub add_usr_settings {
    my $self = shift;
    my $ctx = $self->ctx;
    my $user = $ctx->{user};

    # defaults
    my %settings =(
        'opac.hold_notify' => 'email', # default
        'opac.default_pickup_location' => $user->home_ou,
        'opac.default_phone' => $user->day_phone
    );

    # existing settings if any, and they need to be deserialized I think
    foreach my $setting (@{$user->settings}) {
        if ($setting->name =~ qr/opac.hold_notify|opac.default_pickup_location|opac.default_phone/) {
            $settings{$setting->name} = OpenSRF::Utils::JSON->JSON2perl($setting->value);
        }
    }

    # quipu overrides if any
    my $opac_hold_notify = $self->cgi->param('opac.hold_notify');
    if ($opac_hold_notify && $opac_hold_notify =~ /^(?!.*?(email|sms|phone).*?\1)(email|sms|phone)(:(?2))*$/) {
        $settings{'opac.hold_notify'} = $opac_hold_notify;
    }
    my $opac_default_pickup_location = $self->cgi->param('opac.default_pickup_location');
    if ($opac_default_pickup_location) {
        $settings{'opac.default_pickup_location'} = $opac_default_pickup_location;
    }
    my $opac_default_phone = $self->cgi->param('opac.default_phone');
    if ($opac_default_phone) {
        $settings{'opac.default_phone'} = $opac_default_phone;
    }
    my $opac_default_sms_notify = $self->cgi->param('opac.default_sms_notify');
    if ($opac_default_sms_notify) {
        $settings{'opac.default_sms_notify'} = $opac_default_sms_notify;
    }
    my $opac_default_sms_carrier = $self->cgi->param('opac.default_sms_carrier');
    if ($opac_default_sms_carrier) {
        $settings{'opac.default_sms_carrier'} = $opac_default_sms_carrier;
    }

    $U->simplereq(
        'open-ils.actor',
        'open-ils.actor.patron.settings.update',
        $self->ctx->{vendor_authtoken}, $user->id, \%settings);

    return 1;
}

sub add_survey_responses {
    my $self = shift;
    my $user = $self->ctx->{user};

    my @survey_responses = ();

    eval {
        foreach my $asvr_param ($self->cgi->param('asvr')) {
            my ($survey_id, $question_id, $answer_id) = split ':', $asvr_param;

            # Skip if we don't have all three required IDs
            next unless $survey_id && $question_id && $answer_id;

            my $survey_response = Fieldmapper::action::survey_response->new;

            $survey_response->id(-1);
            $survey_response->isnew(1);
            $survey_response->survey($survey_id);
            $survey_response->question($question_id);
            $survey_response->answer($answer_id);

            push @survey_responses, $survey_response;
        }
    };
    if ($@) {
        $logger->debug( "ECARD: add_survey_responses, error" );
        $logger->error( "ECARD: add_survey_responses, error  = " . OpenSRF::Utils::JSON->perl2JSON( $@ ));
        return 0;
    }

    $user->survey_responses(\@survey_responses);
    return 1;
}

sub add_stat_cats { # or rather: actor.stat_cat_entry_usr_map
    my $self = shift;
    my $user = $self->ctx->{user};
    my $e = new_editor();

    my @statcats = ();

    eval {
        foreach my $asceum_param ($self->cgi->param('asceum')) {
            my ($asc_id, $asce_id) = split ':', $asceum_param;
            my $entry_value = $asce_id;  # default to using the provided value
            $logger->debug("ECARD: stat cat ID $asce_id paired with entry $asce_id");

            # If $asce_id looks like an integer, try to look up the actual value
            if ($asce_id =~ /^\d+$/) {
                my $stat_cat_entry = $e->retrieve_actor_stat_cat_entry($asce_id);
                if ($stat_cat_entry) {
                    $entry_value = $stat_cat_entry->value;
                    $logger->debug("ECARD: entry ID mapped to $entry_value");
                } else {
                    $logger->info("ECARD: Could not find stat_cat_entry for ID $asce_id, using as-is");
                }
            }

            my $sc_entry_usr_map;
            my $results;
            if ($user->id) {
                # search for existing stat cat entry user map if any
                my $search = {
                    stat_cat => $asc_id,
                    target_usr => $user->id
                };
                $logger->debug("ECARD: searching for existing stat cat entry user map with criteria: "
                  . OpenSRF::Utils::JSON->perl2JSON($search));
                $results = $e->search_actor_stat_cat_entry_user_map($search);
                $logger->debug("ECARD: search results: " . OpenSRF::Utils::JSON->perl2JSON($results));
            }
            # alternative? my $found_statcat = ( $e->search_actor_stat_cat_entry_user_map($search)->@* )[0];
            if ($results && ref($results) eq 'ARRAY' && @$results) {
              $sc_entry_usr_map = $results->[0];
              $logger->debug("ECARD: search for existing stat cat entry user map found a match");
              $sc_entry_usr_map->ischanged(1);
            } else {
              $sc_entry_usr_map = Fieldmapper::actor::stat_cat_entry_user_map->new;
              $sc_entry_usr_map->id(-1);
              $sc_entry_usr_map->isnew(1);
              $sc_entry_usr_map->stat_cat($asc_id);
              $logger->debug("ECARD: no matching stat cat entry user map found, creating a new one");
            }
            $sc_entry_usr_map->stat_cat_entry($entry_value);

            push @statcats, $sc_entry_usr_map;
            $logger->info("ECARD: Added stat cat mapping " . OpenSRF::Utils::JSON->perl2JSON($sc_entry_usr_map));
        }
    };
    if ($@) {
        $logger->debug("ECARD: add_stat_cats, error");
        $logger->error("ECARD: add_stat_cats, error = " . OpenSRF::Utils::JSON->perl2JSON($@));
        return 0;
    }

    $user->stat_cat_entries(\@statcats);
    return 1;
}

# Returns true if no dupes found, false if dupes are found.
sub check_dupes {
    my $self = shift;
    my $ctx  = $self->ctx;
    my $user = $ctx->{user};
    my $addr = $user->addresses->[0];
    my $e = new_editor();

    #TODO: This list of fields should be configurable so that code
    #changes are not required for different sites with different
    #criteria.
    my @dupe_patron_fields = 
        qw/first_given_name family_name dob/;

    my $search = {
        first_given_name => {value => $user->first_given_name, group => 0},
        family_name => {value => $user->family_name, group => 0},
        dob => {value => substr($user->dob, 0, 4), group => 0} # birth year
    };

    my $root_org = $e->search_actor_org_unit({parent_ou => undef})->[0];

    my $ids = $U->storagereq(
        "open-ils.storage.actor.user.crazy_search", 
        $search,
        1000,           # search limit
        undef,          # sort
        1,              # include inactive
        $root_org->id,  # ws_ou
        $root_org->id   # search_ou
    );

    return 1 if @$ids == 0;

    $logger->info("ECARD found potential duplicate patrons: @$ids");

    if (my $streetname = $self->cgi->param('physical_street1_name')) {
        # We found matching patrons.  Perform a secondary check on the
        # address street name only.

        $logger->info("ECARD secondary search on street name: $streetname");

        my $addr_ids = $e->search_actor_user_address(
            {   usr => $ids,
                street1 => {'~*' => "(^| )$streetname( |\$)"}
            }, {idlist => 1}
        );

        if (@$addr_ids) {
            # we don't really care what patrons match at this point,
            # only whether a match is found.
            $ids = [1];
            $logger->info("ECARD secondary address check match(es) ".
                "found on address(es) @$addr_ids");

        } else {
            $ids = [];
            $logger->info(
                "ECARD secondary address check found no matches");
        }

    } else {
        $ids = [];
        # unclear if this is a possibility -- err on the side of allowing
        # the registration.
        $logger->info("ECARD found possible patron match but skipping ".
            "secondary street name check -- no street name was provided");
    }

    return 1 if @$ids == 0;

    $ctx->{response}->{status} = 'DUPLICATE';
    $ctx->{response}->{messages} = ['first_given_name', 
        'family_name', 'dob_year', 'billing_street1_name'];
    return undef;
}

# Returns true if no username collision, false if username collision.
sub check_username {
    my $self = shift;
    my $ctx  = $self->ctx;
    my $user = $ctx->{user};
    my $addr = $user->addresses->[0];
    my $e = new_editor();

    my $usrname = $self->cgi->param('usrname');
    return 1 if !$usrname;

    my $search = $e->search_actor_user({usrname => $usrname});

    return 1 if @$search == 0;

    $logger->info("ECARD found colliding usrname with user $search->[0]");

    $ctx->{response}->{status} = 'USERNAME_TAKEN';
    return undef;
}

sub check_username_for_renewal {
    my $self = shift;
    my $ctx  = $self->ctx;
    my $user = $ctx->{user};
    my $addr = $user->addresses->[0];
    my $e = new_editor();

    my $usrname = $self->cgi->param('usrname');
    return 1 if !$usrname;

    return 1 if $usrname eq $user->usrname();

    my $search = $e->search_actor_user({usrname => $usrname});

    return 1 if @$search == 0;

    $logger->info("ECARD found colliding usrname with user $search->[0]");

    $ctx->{response}->{status} = 'USERNAME_TAKEN';
    return undef;
}

sub save_user {
    my $self = shift;
    my $ctx = $self->ctx;
    my $user = $ctx->{user};
    my $local_update_type = $user->isnew;

    my $resp = $U->simplereq(
        'open-ils.actor',
        'open-ils.actor.patron.update',
        $self->ctx->{vendor_authtoken}, $user
    );

    $resp = {textcode => 'UNKNOWN_ERROR'} unless $resp;

    if ($U->is_event($resp)) {
        my $msg = '';

        if ($local_update_type eq '1') {
            $msg = "Error creating user account: " . $resp->{textcode};
            $logger->error("ECARD: $msg");
            $ctx->{response}->{status} = 'CREATE_ERR';
        } else {
            $msg = "Error updating user account: " . $resp->{textcode};
            $logger->error("E-RENEW: $msg");
            $ctx->{response}->{status} = 'UPDATE_ERR';
        }

        $ctx->{response}->{messages} = [{msg => $msg, pid => $$}];

        return 0;
    }

    $ctx->{user} = $resp;
    return 1;
}

sub apply_temp_renewal_penalty {

    my $self = shift;
    my $ctx = $self->ctx;
    my $patron_id = $self->cgi->param('patron_id');

    my $e = new_editor(xact => 1);
    my $ptype = $e->search_config_standing_penalty({name => 'PATRON_TEMP_RENEWAL'})->[0];

    my $penalty = Fieldmapper::actor::user_standing_penalty->new;
    $penalty->usr($patron_id);
    $penalty->org_unit(1);
    $penalty->standing_penalty($ptype->id);

    my $aum = Fieldmapper::actor::usr_message->new;
    $aum->create_date('now');
    $aum->sending_lib(1);
    $aum->title('Temporary Account Renewal');
    $aum->usr($penalty->usr);
    $aum->message('Patron renewed online with an address change so was given a 30-day
    temporary account renewal. Please archive this message after the address is
    verified and the renewal date extended.');
    $aum->pub(0);

    $aum = $e->create_actor_usr_message($aum);
    unless($aum) {
        $e->rollback;
        return 0;
    }

    $penalty->usr_message($aum->id);

    unless($e->create_actor_user_standing_penalty($penalty)) {
        $e->rollback;
        return 0;
    }

    $e->commit;
    return 1;
}


1;

