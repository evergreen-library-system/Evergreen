package OpenILS::WWW::EGCatLoader;
use strict; use warnings;
use Apache2::Const -compile => qw(OK FORBIDDEN HTTP_INTERNAL_SERVER_ERROR);
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Event;
use List::MoreUtils qw/uniq/;
use Data::Dumper;
$Data::Dumper::Indent = 0;
my $U = 'OpenILS::Application::AppUtils';

# We will construct DOB from the individual components
sub construct_dob {
    my $self = shift;
    return $self->cgi->param('dob-year') . '-' . $self->cgi->param('dob-month') . '-' . $self->cgi->param('dob-day');
}

sub load_patron_reg {
    my $self = shift;
    my $ctx = $self->ctx;
    my $cgi = $self->cgi;
    $ctx->{register} = {};
    $self->collect_register_validation_settings;
    $self->collect_requestor_info;

    # in the home org unit selector, we only want to present 
    # org units to the patron which support self-registration.
    # all other org units will be disabled
    $ctx->{register}{valid_orgs} = 
        $self->setting_is_true_for_orgs('opac.allow_pending_user');

    $self->collect_opt_in_settings;

    # just loading the form
    return Apache2::Const::OK
        unless $cgi->request_method eq 'POST';

    my $user = Fieldmapper::staging::user_stage->new;
    my $addr = Fieldmapper::staging::mailing_address_stage->new;

    # user
    foreach (grep /^stgu\./, $cgi->param) {
        my $val = $cgi->param($_);
        if ($_ eq 'stgu.dob') { $val = $self->construct_dob(); }
        $self->inspect_register_value($_, $val);
        s/^stgu\.//g;
        $user->$_($val);
    }

    # requestor is logged in, capture who is making this request
    $user->requesting_usr($ctx->{user}->id) if $ctx->{user};

    # make sure the selected home org unit is in the list 
    # of valid orgs.  This can happen if the selector 
    # defaults to CONS, for example.
    $ctx->{register}{invalid}{bad_home_ou} = 1 unless
        grep {$_ eq $user->home_ou} @{$ctx->{register}{valid_orgs}};

    # address
    my $has_addr = 0;
    foreach (grep /^stgma\./, $cgi->param) {
        my $val = $cgi->param($_);
        $self->inspect_register_value($_, $val);
        s/^stgma\.//g;
        $addr->$_($val);
        $has_addr = 1;
    }

    # if the form contains no address fields, do not 
    # attempt to create a pending address
    $addr = undef unless $has_addr;

    # opt-in settings
    my $settings = [];
    foreach (grep /^stgs\./, $cgi->param) {
        my $val = $cgi->param($_);
        next unless $val; # opt-in settings are always Boolean,
                          # so just skip if not set
        $self->inspect_register_value($_, $val);
        s/^stgs.//g;
        my $setting = Fieldmapper::staging::setting_stage->new;
        $setting->setting($_);
        $setting->value('true');
        push @$settings, $setting;
    }

    # At least one value was invalid. Exit early and re-render.
    return Apache2::Const::OK if $ctx->{register}{invalid};

    $self->test_requested_username($user);

    # user.stage.create will generate a temporary usrname and 
    # link the user and address objects via this username in the DB.
    my $resp = $U->simplereq(
        'open-ils.actor', 
        'open-ils.actor.user.stage.create',
        $user, $addr, undef, [], $settings
    );

    if (!$resp or ref $resp) {

        $logger->warn("Patron self-reg failed ".Dumper($resp));
        $ctx->{register}{error} = 1;

    } else {

        $logger->info("Patron self-reg success; usrname $resp");
        $ctx->{register}{success} = 1;
    }

    return Apache2::Const::OK;
}

# if the pending account is requested by an existing user account,
# load the existing user's data to pre-populate some fields.
sub collect_requestor_info {
    my $self = shift;
    return unless $self->ctx->{user};

    my $user = $self->editor->retrieve_actor_user([
        $self->ctx->{user}->id,
        {flesh => 1, flesh_fields => {
            au => [qw/mailing_address billing_address/]}
        }
    ]);


    my $vhash = $self->ctx->{register}{values} = {};
    my $addr = $user->mailing_address || $user->billing_address;
    $vhash->{stgu}{home_ou} = $user->home_ou;

    if ($addr) {
        $vhash->{stgma}{city} = $addr->city;
        $vhash->{stgma}{county} = $addr->county;
        $vhash->{stgma}{state} = $addr->state;
        $vhash->{stgma}{post_code} = $addr->post_code;
    }
}

sub collect_opt_in_settings {
    my $self = shift;
    my $e = $self->editor;

    # Get the valid_orgs and their ancestors, because the event def
    # may be owned higher up the tree.
    my @opt_orgs = ();
    for my $orgs (map { $U->get_org_ancestors($_) } @{ $self->ctx->{register}{valid_orgs} }) {
        push(@opt_orgs, @{$orgs});
    }

    my $types = $e->json_query({
        select => {cust => ['name']},
        from => {atevdef => 'cust'},
        transform => 'distinct',
        where => {
            '+atevdef' => {
                owner => [ uniq @opt_orgs ],
                active => 't'
            }
        }
    });
    $self->ctx->{register}{opt_in_settings} =
        $e->search_config_usr_setting_type({name => [map {$_->{name}} @$types]});
}

# if the username is in use by an actor.usr OR a 
# pending user treat it as taken and warn the user.
sub test_requested_username {
    my ($self, $user) = @_;
    my $uname = $user->usrname || return;
    my $e = $self->editor;

    my $taken = $e->search_actor_user(
        {usrname => $uname, deleted => 'f'}, 
        {idlist => 1}
    )->[0];

    $taken = $e->search_staging_user_stage(
        {usrname => $uname}, 
        {idlist => 1}
    )->[0] unless $taken;

    if ($taken) {
        $self->ctx->{register}{username_taken} = 1;
        $user->clear_usrname;
    }
}

sub collect_register_validation_settings {
    my $self = shift;
    my $ctx = $self->ctx;
    my $e = new_editor();
    my $ctx_org = $ctx->{physical_loc} || $self->_get_search_lib;
    my $shash = $self->{register}{settings} = {};

    # retrieve the org unit setting types and values
    # that are relevant to our validation tasks.

    my $settings = $e->json_query({
        select => {coust => ['name']},
        from => 'coust',
        where => {name => {like => 'ui.patron.edit.%.%.%'}}
    });

    # load org setting values for all of the regex, 
    # example, show, and require settings
    for my $set (@$settings) {
        $set = $set->{name};
        next unless $set =~ /regex$|show$|require$|example$/;

        my $val = $ctx->{get_org_setting}->($ctx_org, $set);
        next unless defined($val); # no configured org setting

        # extract the field class, name, and 
        # setting type from the setting name
        my (undef, undef, undef, $cls, $field, $type) = split(/\./, $set);

        # translate classes into stage classes
        my $scls = ($cls eq 'au') ? 'stgu' : 'stgma';

        $shash->{$scls}{$field}{$type} = $val;
    }

    # Should be the letters M, D, and Y in some order.
    $shash->{dob_order} = $ctx->{get_org_setting}->($ctx_org, 'opac.self_register.dob_order');

    # use the generic phone settings where none are provided for day_phone.

    $shash->{stgu}{day_phone}{example} =
        $ctx->{get_org_setting}->($ctx_org, 'ui.patron.edit.phone.example')
        unless $shash->{stgu}{day_phone}{example};

    $shash->{stgu}{day_phone}{regex} =
        $ctx->{get_org_setting}->($ctx_org, 'ui.patron.edit.phone.regex')
        unless $shash->{stgu}{day_phone}{regex};

    # The regex OUS for username does not match the format of the other 
    # org settings.  Wrangle it into place.
    $shash->{stgu}{usrname}{regex} = 
        $ctx->{get_org_setting}->($ctx_org, 'opac.username_regex');

    # Speaking of usrname, some libraries want to hide it. I'll follow the show/require
    # pattern in case someone wants to genericize it for any field. However this one
    # would only make sense for the patron self-registration interface, so I'm going
    # to change the prefix from ui to opac.
    $shash->{stgu}{usrname}{hide} = 
        $ctx->{get_org_setting}->($ctx_org, 'opac.patron.edit.au.usrname.hide');

    # some fields are assumed to be visible / required even without the            
    # presence of org unit settings.  E.g. we obviously want the user to 
    # enter a name, since a name is required for ultimately creating a user 
    # account.  We can mimic that by forcing some org unit setting values
    
    $shash->{stgu}{first_given_name}{require} = 1
        unless defined $shash->{stgu}{first_given_name}{require};
    $shash->{stgu}{second_given_name}{show} = 1
        unless defined $shash->{stgu}{second_given_name}{show};
    $shash->{stgu}{family_name}{require} = 1
        unless defined $shash->{stgu}{family_name}{require};
    $shash->{stgma}{street1}{require} = 1
        unless defined $shash->{stgma}{street1}{require};
    $shash->{stgma}{street2}{show} = 1
        unless defined $shash->{stgma}{street2}{show};
    $shash->{stgma}{city}{require} = 1
        unless defined $shash->{stgma}{city}{require};
    $shash->{stgma}{post_code}{require} = 1
        unless defined $shash->{stgma}{post_code}{require};
    $shash->{stgu}{usrname}{show} = 1
        unless defined $shash->{stgu}{usrname}{show};

    $ctx->{register}{settings} = $shash;

    # laod the page timeout setting
    $shash->{refresh_timeout} = 
        $ctx->{get_org_setting}->($ctx_org, 'opac.self_register.timeout');
}

# inspects each value and determines, based on org unit settings, 
# if the value is invalid.  Invalid is defined as not providing 
# a value when one is required or not matching the configured regex.
sub inspect_register_value {
    my ($self, $field_path, $value) = @_;
    my $ctx = $self->ctx;
    my ($scls, $field) = split(/\./, $field_path, 2);

    if ($scls eq 'stgs') {
        my $found = 0;
        foreach my $type (@{ $self->ctx->{register}{opt_in_settings} }) {
            if ($field eq $type->name) {
                $found = 1;
            }
        }
        if (!$found) {
            $ctx->{register}{invalid}{$scls}{$field}{invalid} = 1;
            $logger->info("patron register: trying to set an opt-in ".
                          "setting $field that is not allowed.");
        }
        return;
    }

    if (!$value) {

        if ($self->{register}{settings}{$scls}{$field}{require}) {
            $ctx->{register}{invalid}{$scls}{$field}{require} = 1;

            $logger->info("patron register field $field ".
                "requires a value, but none was entered");
        }
        return;
    }

    my $regex = $self->{register}{settings}{$scls}{$field}{regex};
    return if !$regex or $value =~ /$regex/; # field is valid

    $logger->info("invalid value was provided for patron ".
        "register field=$field; pattern=$regex; value=$value");

    $ctx->{register}{invalid}{$scls}{$field}{regex} = 1;

    return;
}



