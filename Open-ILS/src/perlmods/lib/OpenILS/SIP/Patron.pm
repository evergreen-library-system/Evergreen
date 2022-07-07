#
# 
# A Class for hiding the ILS's concept of the patron from the OpenSIP
# system
#

package OpenILS::SIP::Patron;

use strict;
use warnings;
use Exporter;

use Sys::Syslog qw(syslog);
use Data::Dumper;
use Digest::MD5 qw(md5_hex);

use OpenILS::SIP;
use OpenILS::Application::AppUtils;
use OpenILS::Application::Actor;
use OpenILS::Const qw/:const/;
use OpenILS::Utils::DateTime qw/:datetime/;
use DateTime::Format::ISO8601;
use OpenILS::Utils::Fieldmapper;
my $U = 'OpenILS::Application::AppUtils';

our (@ISA, @EXPORT_OK);

@ISA = qw(Exporter);

@EXPORT_OK = qw(invalid_patron);

my $INET_PRIVS;

sub new {
    my $class = shift;
    my $key   = shift;
    my $patron_id = shift;
    my %args = @_;

    if ($key ne 'usr' and $key ne 'barcode' and $key ne 'usrname') {
        syslog("LOG_ERROR", "Patron (card) lookup requested by illegeal key '$key'");
        return undef;
    }

    unless(defined $patron_id) {
        syslog("LOG_WARNING", "No patron ID provided to ILS::Patron->new");
        return undef;
    }

    my $type = ref($class) || $class;
    my $self = bless({}, $type);

    syslog("LOG_DEBUG", "OILS: new OpenILS Patron(%s => %s): searching...", $key, $patron_id);

    my $idl = OpenSRF::Utils::SettingsClient->new->config_value("IDL");
    Fieldmapper->import(IDL => $idl);

    my $e = OpenILS::SIP->editor();
    # Pass the authtoken, if any, to the editor so that we can use it
    # to fake a context org_unit for the csp.ignore_proximity in
    # flesh_user_penalties, below.
    unless ($e->authtoken()) {
        $e->authtoken($args{authtoken}) if ($args{authtoken});
    }

    my $usr_flesh = {
        flesh => 2,
        flesh_fields => {
            au => [
                "card",
                "addresses",
                "billing_address",
                "mailing_address",
                'profile',
                "stat_cat_entries",
            ],
            actscecm => [
                "stat_cat",
            ],
        }
    };

    # in some cases, we don't need all of this data.  Only fetch the user + barcode
    $usr_flesh = {flesh => 1, flesh_fields => {au => ['card']}} if $args{slim_user};

    my $user;
    if($key eq 'barcode') { # retrieve user by barcode

        $$usr_flesh{flesh} += 1;
        $$usr_flesh{flesh_fields}{ac} = ['usr'];

        my $card = $e->search_actor_card([{barcode => $patron_id}, $usr_flesh])->[0];

        if(!$card or !$U->is_true($card->active)) {
            syslog("LOG_WARNING", "No such patron barcode: $patron_id");
            return undef;
        }

        $user = $card->usr;

    } elsif ($key eq 'usrname') {
        $user = $e->search_actor_user([{usrname => $patron_id}, $usr_flesh])->[0];
    } else {
        $user = $e->retrieve_actor_user([$patron_id, $usr_flesh]);
    }

    if(!$user or $U->is_true($user->deleted)) {
        syslog("LOG_WARNING", "OILS: Unable to find patron %s => %s", $key, $patron_id);
        return undef;
    }

    if(!$U->is_true($user->active)) {
        syslog("LOG_WARNING", "OILS: Patron is inactive %s => %s", $key, $patron_id);
        return undef;
    }

    # now grab the user's penalties

    $self->flesh_user_penalties($user, $e) unless $args{slim_user};

    $self->{authtoken} = $args{authtoken} if $args{authtoken};
    $self->{editor} = $e;
    $self->{user}   = $user;
    $self->{id}     = ($key eq 'barcode') ? $patron_id : $user->card->barcode;   # The barcode IS the ID to SIP.  
    # We give back the passed barcode if the key was indeed a barcode, just to be safe.  Otherwise pull it from the card.

    syslog("LOG_DEBUG", "OILS: new OpenILS Patron(%s => %s): found patron : barred=%s, card:active=%s", 
        $key, $patron_id, $user->barred, $user->card->active );

    $U->log_user_activity($user->id, $self->get_act_who, 'verify');

    return $self;
}

sub get_act_who {
    my $self = shift;
    my $config = OpenILS::SIP->config();
    my $login = OpenILS::SIP->login_account();

    my $act_who = $config->{implementation_config}->{default_activity_who};
    my $force_who = $config->{implementation_config}->{force_activity_who};

    # 1. future: test sip extension for caller-provided ewho and !$force_who

    # 2. See if the login is tagged with an ewho
    return $login->{activity_who} if $login->{activity_who};

    # 3. if all else fails, see if there is an institution-wide ewho
    return $config->{activity_who} if $config->{activity_who};

    return undef;
}

# grab patron penalties.  Only grab non-archived penalties that are for fines,
# excessive overdues, or otherwise block circluation activity
sub flesh_user_penalties {
    my ($self, $user, $e) = @_;

    # Use the ws_ou or home_ou of the authsession user, if any, as a
    # context org_unit for the penalties and the csp.ignore_proximity.
    my $here;
    if ($e->authtoken()) {
        my $auth_usr = $e->checkauth();
        if ($auth_usr) {
            $here = $auth_usr->ws_ou() || $auth_usr->home_ou();
        }
    }

    # Get the "raw" list of user's penalties and flesh the
    # standing_penalty field, so we can filter them based on
    # csp.ignore_proximity.
    my $raw_penalties =
        $e->search_actor_user_standing_penalty([
            {
                usr => $user->id,
                '-or' => [

                    # ignore "archived" penalties
                    {stop_date => undef},
                    {stop_date => {'>' => 'now'}}
                ],

                org_unit => {
                    in  => {
                        select => {
                            aou => [{
                                column => 'id',
                                transform => 'actor.org_unit_ancestors',
                                result_field => 'id'
                            }]
                        },
                        from => 'aou',

                        # Use "here" or user's home_ou.
                        where => {id => ($here) ? $here : $user->home_ou},
                        distinct => 1
                    }
                },

                # in addition to fines and excessive overdue penalties,
                # we only care about penalties that result in blocks
                standing_penalty => {
                    in => {
                        select => {csp => ['id']},
                        from => 'csp',
                        where => {
                            '-or' => [
                                {id => [1,2]}, # fines / overdues
                                {block_list => {'!=' => undef}}
                            ]
                        },
                    }
                }
            },
            {
                flesh => 1,
                flesh_fields => {ausp => ['standing_penalty']}
            }
        ]);
    # We filter the raw penalties that apply into this array.
    my $applied_penalties = [];
    if (ref($raw_penalties) eq 'ARRAY' && @$raw_penalties) {
        my $here_prox = ($here) ? $U->get_org_unit_proximity($e, $here, $user->home_ou())
            : undef;
        # Filter out those that do not apply
        $applied_penalties = [map
            { $_->standing_penalty }
                grep {
                    !defined($_->standing_penalty->ignore_proximity())
                    || ((defined($here_prox))
                        ? $_->standing_penalty->ignore_proximity() < $here_prox
                        : $_->standing_penalty->ignore_proximity() <
                            $U->get_org_unit_proximity($e, $_->org_unit(), $user->home_ou()))
                } @$raw_penalties];
    }
    $user->standing_penalties($applied_penalties);
}

sub id {
    my $self = shift;
    return $self->{id};
}

sub name {
    my $self = shift;
    return format_name($self->{user});
}

sub format_name {
    my $u = shift;
    return sprintf('%s %s %s',
                   ($u->pref_first_given_name || $u->first_given_name || ''),
                   ($u->pref_second_given_name || $u->second_given_name || ''),
                   ($u->pref_family_name || $u->family_name || ''));
}

sub home_library {
    my $self = shift;
    my $lib = OpenILS::SIP::shortname_from_id($self->{user}->home_ou);
    syslog('LOG_DEBUG', "OILS: Patron->home_library() = $lib");
    return $lib;
}

sub __addr_string {
    my $addr = shift;
    return "" unless $addr;
    my $return = join( ' ', map {$_ || ''}
                           (
                               $addr->street1,
                               $addr->street2,
                               $addr->city . ',',
                               $addr->county,
                               $addr->state,
                               $addr->country,
                               $addr->post_code
                           )
                       );
    $return =~ s/\s+/ /sg; # Compress any run of of whitespace to one space
    return $return;
}

sub internal_id {
    my $self = shift;
    return $self->{user}->id;
}

sub address {
    my $self = shift;
    my $u    = $self->{user};
    my $str  = __addr_string($u->billing_address || $u->mailing_address);
    syslog('LOG_DEBUG', "OILS: Patron address: $str");
    return $str;
}

sub email_addr {
    my $self = shift;
    return $self->{user}->email;
}

sub home_phone {
    my $self = shift;
    return $self->{user}->day_phone;
}

sub sip_birthdate {
    my $self = shift;
    my $dob = OpenILS::SIP->format_date($self->{user}->dob, 'dob');
    syslog('LOG_DEBUG', "OILS: Patron DOB = $dob");
    return $dob;
}

sub sip_expire {
    my $self = shift;
    my $expire = OpenILS::SIP->format_date($self->{user}->expire_date);
    syslog('LOG_DEBUG', "OILS: Patron Expire = $expire");
    return $expire;
}

sub ptype {
    my $self = shift;

    my $use_code = OpenILS::SIP->get_option_value('patron_type_uses_code') || '';

    # should we use the no_i18n version of patron profile name (as a 'code')?
    return $self->{editor}->retrieve_permission_grp_tree(
        [$self->{user}->profile->id, {no_i18n => 1}])->name
        if $use_code =~ /true/io;

    return $self->{user}->profile->name;
}

sub language {
    my $self = shift;
    return '000'; # Unspecified
}

# method to check to see if charge_ok, renew_ok, and
# lost_card should be coerced to return a status indicating
# that the patron should be allowed to circulate; this
# implements a workaround further described in
# https://bugs.launchpad.net/evergreen/+bug/1853363
sub patron_status_always_permit_loans_set {
    my $self = shift;

    my $login = OpenILS::SIP->login_account();

    return (
                OpenILS::SIP::to_bool($login->{patron_status_always_permit_loans}) //
                OpenILS::SIP::to_bool(OpenILS::SIP->get_option_value('patron_status_always_permit_loans'))
           ) ||
           0;
}

# How much more detail do we need to check here?
# sec: adding logic to return false if user is barred, has a circulation block
# or an expired card
sub charge_ok {
    my $self = shift;
    my $u = $self->{user};
    my $circ_is_blocked = 0;

    return 1 if $self->patron_status_always_permit_loans_set();

    # compute expiration date for borrowing privileges
    my $expire = DateTime::Format::ISO8601->new->parse_datetime(clean_ISO8601($u->expire_date));

    $circ_is_blocked =
        (($u->barred eq 't') or
          (@{$u->standing_penalties} and grep { ( $_->block_list // '') =~ /CIRC/ } @{$u->standing_penalties}) or
          (CORE::time > $expire->epoch));

    return
        !$circ_is_blocked &&
        $u->active eq 't' &&
        $u->card->active eq 't';
}

sub renew_ok {
    my $self = shift;
    my $u = $self->{user};
    my $renew_is_blocked = 0;

    return 1 if $self->patron_status_always_permit_loans_set();

    # compute expiration date for borrowing privileges
    my $expire = DateTime::Format::ISO8601->new->parse_datetime(clean_ISO8601($u->expire_date));

    $renew_is_blocked =
        (($u->barred eq 't') or
         (@{$u->standing_penalties} and grep { ( $_->block_list // '') =~ /RENEW/ } @{$u->standing_penalties}) or
         (CORE::time > $expire->epoch));

    return
        !$renew_is_blocked &&
        $u->active eq 't' &&
        $u->card->active eq 't';
}

sub recall_ok {
    my $self = shift;
    return $self->charge_ok if 
        OpenILS::SIP->get_option_value('patron_calculate_recal_ok');
    return 0;
}

sub hold_ok {
    my $self = shift;
    my $u = $self->{user};
    my $hold_is_blocked = 0;

    # compute expiration date for borrowing privileges
    my $expire = DateTime::Format::ISO8601->new->parse_datetime(clean_ISO8601($u->expire_date));

    $hold_is_blocked =
        (($u->barred eq 't') or
         (@{$u->standing_penalties} and grep { ( $_->block_list // '') =~ /HOLD/ } @{$u->standing_penalties}) or
         (CORE::time > $expire->epoch));

    return
        !$hold_is_blocked &&
        $u->active eq 't' &&
        $u->card->active eq 't';
}

# return true if the card provided is marked as lost
sub card_lost {
    my $self = shift;

    return 0 if $self->patron_status_always_permit_loans_set();

    return $self->{user}->card->active eq 'f';
}

sub recall_overdue {        # not implemented
    my $self = shift;
    return 0;
}

sub check_password {
    my ($self, $pwd) = @_;
    syslog('LOG_DEBUG', 'OILS: Patron->check_password()');
    return 0 unless (defined $pwd and $self->{user});
    return $U->verify_migrated_user_password(
        $self->{editor},$self->{user}->id, $pwd);
}

sub currency {
    my $self = shift;
    syslog('LOG_DEBUG', 'OILS: Patron->currency()');
    return OpenILS::SIP->config()->{implementation_config}->{currency} || 'USD';
}

sub fee_amount {
    my $self = shift;
    syslog('LOG_DEBUG', 'OILS: Patron->fee_amount()');
    my $user_id = $self->{user}->id;

    my $e = $self->{editor};
    $e->xact_begin;
    my $summary = $e->retrieve_money_open_user_summary($user_id);
    $e->rollback; # xact_rollback + disconnect

    my $total = ($summary) ? $summary->balance_owed : 0;
    syslog('LOG_INFO', "User ".$self->{id} .":$user_id has a fee amount of \$$total");
    return $total;
}

sub screen_msg {
    my $self = shift;
    my $u = $self->{user};

    return 'barred' if $u->barred eq 't';

    my $b = 'blocked';

    return $b if $u->active eq 'f';
    return $b if $u->card->active eq 'f';

    # if we have any penalties at this point, they are blocking penalties
    return $b if $u->standing_penalties and @{$u->standing_penalties};

    # has the patron account expired?
    my $expire = DateTime::Format::ISO8601->new->parse_datetime(clean_ISO8601($u->expire_date));
    return $b if CORE::time > $expire->epoch;

    return '';
}

sub print_line {            # not implemented
    my $self = shift;
    return '';
}

sub too_many_charged {
    my $self = shift;
    return scalar(
        grep { $_->id == OILS_PENALTY_PATRON_EXCEEDS_CHECKOUT_COUNT } @{$self->{user}->standing_penalties}
    );
}

sub too_many_overdue {
    my $self = shift;
    return scalar( # PATRON_EXCEEDS_OVERDUE_COUNT || PATRON_EXCEEDS_LONGOVERDUE_COUNT
        grep { $_->id == OILS_PENALTY_PATRON_EXCEEDS_OVERDUE_COUNT
           || $_->id == OILS_PENALTY_PATRON_EXCEEDS_LONGOVERDUE_COUNT } @{$self->{user}->standing_penalties}
    );
}

# not completely sure what this means
sub too_many_renewal {
    my $self = shift;
    return 0;
}

# not relevant, handled by fines/fees
sub too_many_claim_return {
    my $self = shift;
    return 0;
}

sub too_many_lost {
    my $self = shift;
    return scalar(
        grep { $_->id == OILS_PENALTY_PATRON_EXCEEDS_LOST_COUNT } @{$self->{user}->standing_penalties}
    );
}

sub excessive_fines { 
    my $self = shift;
    return scalar( # PATRON_EXCEEDS_FINES
        grep { $_->id == OILS_PENALTY_PATRON_EXCEEDS_FINES } @{$self->{user}->standing_penalties}
    );
}

# Until someone suggests otherwise, fees and fines are the same

sub excessive_fees {
    my $self = shift;
    return $self->excessive_fines;
}

# not relevant, handled by fines/fees
sub too_many_billed {
    my $self = shift;
    return 0;
}



#
# List of outstanding holds placed
#
sub hold_items {
    my ($self, $start, $end, $ids_only) = @_;
    syslog('LOG_DEBUG', 'OILS: Patron->hold_items()');

    # all of my open holds
    my $holds_query = {
        usr => $self->{user}->id,
        fulfillment_time => undef,
        cancel_time => undef
    };
    if (OpenILS::SIP->get_option_value('msg64_hold_items_available')) {
        # Limit to available holds.
        $holds_query->{current_shelf_lib} = {'=' => {'+ahr' => 'pickup_lib'}};
    }
    my $holds = $self->{editor}->search_action_hold_request($holds_query);

    return $holds if $ids_only;
    return $self->__format_holds($holds, $start, $end);
}

sub unavail_holds {
     my ($self, $start, $end, $ids_only) = @_;
     syslog('LOG_DEBUG', 'OILS: Patron->unavail_holds()');

     my $holds = $self->{editor}->search_action_hold_request({
        usr => $self->{user}->id,
        fulfillment_time => undef,
        cancel_time => undef,
        '-or' => [
            {current_shelf_lib => undef},
            {current_shelf_lib => {'!=' => {'+ahr' => 'pickup_lib'}}}
        ]
    });

    return $holds if $ids_only;
    return $self->__format_holds($holds, $start, $end);
}



sub __format_holds {
    my ($self, $holds, $start, $end) = @_;

    return [] unless @$holds;

    my $return_datatype = 
        OpenILS::SIP->get_option_value('msg64_hold_datatype') || '';

    my @response;

    for my $hold (@$holds) {

        if ($return_datatype eq 'barcode') {

            if (my $copy = $self->find_copy_for_hold($hold)) {
                push(@response, $copy->barcode);

            } else {
                syslog('LOG_WARNING', 
                    'OILS: No representative copy found for hold ' . $hold->id);
            }

        } else {
            push(@response, 
                $self->__hold_to_title($hold));
        }
    }

    return (defined $start and defined $end) ? 
        [ @response[($start-1)..($end-1)] ] :
        \@response;
}

# Finds a representative copy for the given hold.
# If no copy exists at all, undef is returned.
# The only limit placed on what constitutes a 
# "representative" copy is that it cannot be deleted.
# Otherwise, any copy that allows us to find the hold
# later is good enough.
sub find_copy_for_hold {
    my ($self, $hold) = @_;
    my $e = $self->{editor};

    return $e->retrieve_asset_copy($hold->current_copy)
        if $hold->current_copy; 

    return $e->retrieve_asset_copy($hold->target)
        if $hold->hold_type =~ /C|R|F/;

    return $e->search_asset_copy([
        {call_number => $hold->target, deleted => 'f'}, 
        {limit => 1}])->[0] if $hold->hold_type eq 'V';

    return $e->json_query(
        {
            select => { acp => ['id'] },
            from => {
                acp => {
                    acpm => {
                        field => 'target_copy',
                        fkey => 'id',
                        filter => { part => $hold->target }
                    }
                }
           },
           where => { '+acp' => { deleted => 'f' } },
           limit => 1
       })->[0]->{id} if $hold->hold_type eq 'P';


    return $e->json_query(
        {
            select => { acp => ['id'] },
            from => {
                acp => {
                    sitem => {
                        field => 'unit',
                        fkey => 'id',
                        filter => { issuance => $hold->target }
                    }
                }
           },
           where => { '+acp' => { deleted => 'f' } },
           limit => 1
       })->[0]->{id} if $hold->hold_type eq 'I';


    my $bre_ids = [$hold->target];

    if ($hold->hold_type eq 'M') {
        # find all of the bibs that link to the target metarecord
        my $maps = $e->search_metabib_metarecord_source_map(
            {metarecord => $hold->target});
        $bre_ids = [map {$_->record} @$maps];
    }

    my $vol_ids = $e->search_asset_call_number( 
        {record => $bre_ids, deleted => 'f'}, 
        {idlist => 1}
    );

    return $e->search_asset_copy([
        {call_number => $vol_ids, deleted => 'f'}, 
        {limit => 1}
    ])->[0];
}

# Given a "representative" copy, finds a matching hold
sub find_hold_from_copy {
    my ($self, $barcode) = @_;
    my $e = $self->{editor};
    my $hold;

    my $copy = $e->search_asset_copy([
        {barcode => $barcode, deleted => 'f'},
        {flesh => 1, flesh_fields => {acp => ['call_number']}}
    ])->[0];

    return undef unless $copy;

    my $run_hold_query = sub {
        my %filter = @_;
        return $e->search_action_hold_request([
            {   usr => $self->{user}->id,
                cancel_time => undef,
                fulfillment_time => undef,
                %filter
            }, {
                limit => 1,
                order_by => {ahr => 'request_time DESC'}
            }
        ])->[0];
    };

    # first see if there is a match on current_copy
    return $hold if $hold = 
        $run_hold_query->(current_copy => $copy->id);

    # next, assume bib-level holds are the most common
    return $hold if $hold = $run_hold_query->(
        target => $copy->call_number->record, hold_type => 'T');

    # next try metarecord holds
    my $map = $e->search_metabib_metarecord_source_map(
        {source => $copy->call_number->record})->[0];

    return $hold if $hold = $run_hold_query->(
        target => $map->metarecord, hold_type => 'M');


    # part holds
    my $part = $e->search_asset_copy_part_map(
        { target_copy => $copy->id })->[0];

    if ($part) {
        return $hold if $hold = $run_hold_query->(
            target => $part->id, hold_type => 'P');
    }

    # issuance holds
    my $iss = $e->search_serial_item(
        { unit => $copy->id })->[0];

    if ($iss) {
        return $hold if $hold = $run_hold_query->(
            target => $iss->id, hold_type => 'I');
    }

    # volume holds
    return $hold if $hold = $run_hold_query->(
        target => $copy->call_number->id, hold_type => 'V');

    # copy holds
    return $run_hold_query->(
        target => $copy->id, hold_type => ['C', 'F', 'R']);
}

sub __hold_to_title {
    my $self = shift;
    my $hold = shift;
    my $e = $self->{editor};

    my( $id, $mods, $title, $volume, $copy );

    return __copy_to_title($e, 
        $e->retrieve_asset_copy($hold->target)) 
        if $hold->hold_type eq 'C' or $hold->hold_type eq 'F' or $hold->hold_type eq 'R';

    return __part_to_title($e,
        $e->retrieve_biblio_monograph_part($hold->target))
        if $hold->hold_type eq 'P';

    return __volume_to_title($e, 
        $e->retrieve_asset_call_number($hold->target))
        if $hold->hold_type eq 'V';

    return __issuance_to_title(
        $e, $hold->target) # starts with the issuance id because there's more involved for I holds.
        if $hold->hold_type eq 'I';

    return __record_to_title(
        $e, $hold->target) if $hold->hold_type eq 'T';

    return __metarecord_to_title(
        $e, $hold->target) if $hold->hold_type eq 'M';
}

sub __copy_to_title {
    my( $e, $copy ) = @_;
    #syslog('LOG_DEBUG', "OILS: copy_to_title(%s)", $copy->id);
    return $copy->dummy_title if $copy->call_number == -1;    

    my $vol = (ref $copy->call_number) ?
        $copy->call_number :
        $e->retrieve_asset_call_number($copy->call_number);

    return __volume_to_title($e, $vol);
}

sub __part_to_title {
    my( $e, $part ) = @_;
    #syslog('LOG_DEBUG', "OILS: part_to_title(%s)", $part->id);

    return __record_to_title($e, $part->record);
}

sub __volume_to_title {
    my( $e, $volume ) = @_;
    #syslog('LOG_DEBUG', "OILS: volume_to_title(%s)", $volume->id);
    return __record_to_title($e, $volume->record);
}

sub __issuance_to_title {
    my( $e, $issuance_id ) = @_;
    my $bre_id = $e->json_query(
    {
        select => { ssub => ['record_entry'] },
        from => {
            ssub => {
                siss => {
                    field => 'subscription',
                    fkey => 'id',
                    filter => { id => $issuance_id }
                }
            }
        }
    })->[0]->{record_entry};

    return __record_to_title($e, $bre_id);
}


sub __record_to_title {
    my( $e, $title_id ) = @_;
    #syslog('LOG_DEBUG', "OILS: record_to_title($title_id)");
    my $mods = $U->simplereq(
        'open-ils.search',
        'open-ils.search.biblio.record.mods_slim.retrieve', $title_id );
    return ($mods) ? $mods->title : "";
}

sub __metarecord_to_title {
    my( $e, $m_id ) = @_;
    #syslog('LOG_DEBUG', "OILS: metarecord_to_title($m_id)");
    my $mods = $U->simplereq(
        'open-ils.search',
        'open-ils.search.biblio.metarecord.mods_slim.retrieve', $m_id);
    return ($U->event_code($mods)) ? "<unknown>" : $mods->title;
}


#
# remove the hold on item item_id from my hold queue.
# return true if I was holding the item, false otherwise.
# 
sub drop_hold {
    my ($self, $item_id) = @_;
    return 0;
}

sub __patron_items_info {
    my $self = shift;
    return if $self->{item_info};
    $self->{item_info} = 
        OpenILS::Application::Actor::_checked_out(
            0, $self->{editor}, $self->{user}->id);;
}



sub overdue_items {
    my ($self, $start, $end, $ids_only) = @_;

    $self->__patron_items_info();
    my @overdues = @{$self->{item_info}->{overdue}};
    #$overdues[$_] = __circ_to_title($self->{editor}, $overdues[$_]) for @overdues;

    return \@overdues if $ids_only;

    my @o;
    syslog('LOG_DEBUG', "OILS: overdue_items() fleshing circs @overdues");

    my $return_datatype = OpenILS::SIP->get_option_value('msg64_summary_datatype') || '';
    
    for my $circid (@overdues) {
        next unless $circid;
        if($return_datatype eq 'barcode') {
            push( @o, __circ_to_barcode($self->{editor}, $circid));
        } else {
            push( @o, __circ_to_title($self->{editor}, $circid));
        }
    }
    @overdues = @o;

    return (defined $start and defined $end) ? 
        [ @overdues[($start-1)..($end-1)] ] : \@overdues;
}

sub __circ_to_barcode {
    my ($e, $circ) = @_;
    return unless $circ;
    $circ = $e->retrieve_action_circulation($circ);
    my $copy = $e->retrieve_asset_copy($circ->target_copy);
    return $copy->barcode;
}

sub __circ_to_title {
    my( $e, $circ ) = @_;
    return unless $circ;
    $circ = $e->retrieve_action_circulation($circ);
    return __copy_to_title( $e, 
        $e->retrieve_asset_copy($circ->target_copy) );
}

sub charged_items {
    my ($self, $start, $end, $ids_only) = shift;
    return $self->charged_items_impl($start, $end, undef, $ids_only);
}

# implementation method
# force_bc -- return barcode data regardless of msg64_summary_datatype;
#             this is used by the renew-all code
sub charged_items_impl {
    my ($self, $start, $end, $force_bc, $ids_only) = shift;

    $self->__patron_items_info();

    my @charges = (
        @{$self->{item_info}->{out}},
        @{$self->{item_info}->{overdue}}
        );

    #$charges[$_] = __circ_to_title($self->{editor}, $charges[$_]) for @charges;

    return \@charges if $ids_only;

    my @c;
    syslog('LOG_DEBUG', "OILS: charged_items() fleshing circs @charges");

    my $return_datatype = OpenILS::SIP->get_option_value('msg64_summary_datatype') || '';

    for my $circid (@charges) {
        next unless $circid;
        if($return_datatype eq 'barcode' or $force_bc) {
            push( @c, __circ_to_barcode($self->{editor}, $circid));
        } else {
            push( @c, __circ_to_title($self->{editor}, $circid));
        }
    }

    @charges = @c;

    return (defined $start and defined $end) ? 
        [ @charges[($start-1)..($end-1)] ] :
        \@charges;
}

sub fine_items {
    my ($self, $start, $end, $ids_only) = @_;
    my @fines;

    my $login = OpenILS::SIP->login_account();
    my $AV_format = lc($login->{av_format}) || 'eg_legacy';

    # Do a prescan for validity and default to eg_legacy
    if ($AV_format ne "swyer_a" &&
        $AV_format ne "swyer_b" &&
        $AV_format ne "eg_legacy" &&
        $AV_format ne "3m") {

        syslog('LOG_WARNING',
            "OILS: Unknown value for AV_format: ". $login->{av_format});
        $AV_format = "eg_legacy";
    }

    my $xacts = $U->simplereq('open-ils.actor',
        'open-ils.actor.user.transactions.history.have_balance',
        $self->{authtoken}, $self->{user}->id);

    my $line;
    foreach my $xact (@{$xacts}) {

        if ($ids_only) {
            push @fines, $xact->id;
            next;
        }

        # fine item details requested

        my $title;
        my $author;
        my $line;

        my $fee_type;

        if ($xact->last_billing_type =~ /^Lost/) {
            $fee_type = 'LOST';
        } elsif ($xact->last_billing_type =~ /^Overdue/) {
            $fee_type = 'FINE';
        } else {
            $fee_type = 'FEE';
        }

        if ($xact->xact_type eq 'circulation') {
            my $e = OpenILS::SIP->editor();
            my $circ = $e->retrieve_action_circulation([
                $xact->id, {
                    flesh => 2,
                    flesh_fields => {
                        circ => ['target_copy'],
                        acp => ['call_number']
                    }
                }
            ]);

            my $displays = $e->search_metabib_flat_display_entry({
                source => $circ->target_copy->call_number->record,
                name => ['title', 'author']
            });

            ($title) = map {$_->value} grep {$_->name eq 'title'} @$displays;
            ($author) = map {$_->value} grep {$_->name eq 'author'} @$displays;

            # Scrub "/" chars since they are used in some cases 
            # to delineate title/author.
            if ($title) {
                $title =~ s/\///g;
            } else {
                $title = '';
            }

            if ($author) {
                $author =~ s/\///g;
            } else {
                $author = '';
            }
        }

        if ($AV_format eq "eg_legacy") {

            $line = $xact->balance_owed . " " . $xact->last_billing_type . " ";

            if ($xact->xact_type eq 'circulation') {
                $line .= "$title / $author";
            } else {
                $line .= $xact->last_billing_note;
            }

        } elsif ($AV_format eq "3m" or $AV_format eq "swyer_a") {

            $line = $xact->id . ' $' . $xact->balance_owed . " \"$fee_type\" ";

            if ($xact->xact_type eq 'circulation') {
                $line .= "$title";
            } else {
                $line .= $xact->last_billing_note;
            }

        } elsif ($AV_format eq "swyer_b") {

            $line =   "Charge-Number: " . $xact->id;
            $line .=  ", Amount-Due: "  . $xact->balance_owed;
            $line .=  ", Fine-Type: $fee_type";

            if ($xact->xact_type eq 'circulation') {
                $line .= ", Title: $title";
            } else {
                $line .= ", Title: " . $xact->last_billing_note;
            }
        }

        push @fines, $line;
    }

    my $log_status = $@ ? 'ERROR: ' . $@ : 'OK';
    syslog('LOG_DEBUG', 'OILS: Patron->fine_items() ' . $log_status);
    return (defined $start and defined $end) ? 
        [ @fines[($start-1)..($end-1)] ] : \@fines;
}

# not currently supported
sub recall_items {
    my ($self, $start, $end, $ids_only) = @_;
    return [];
}

sub block {
    my ($self, $card_retained, $blocked_card_msg) = @_;
    $blocked_card_msg ||= '';

    my $e = $self->{editor};
    my $u = $self->{user};

    syslog('LOG_INFO', "OILS: Blocking user %s", $u->card->barcode );

    return $self if $u->card->active eq 'f'; # TODO: don't think this will ever be true

    $e->xact_begin;    # connect and start a new transaction

    $u->card->active('f');
    if( ! $e->update_actor_card($u->card) ) {
        syslog('LOG_ERR', "OILS: Block card update failed: %s", $e->event->{textcode});
        $e->rollback; # rollback + disconnect
        return $self;
    }

    # Use the ws_ou or home_ou of the authsession user, if any, as a
    # context org_unit for the created penalty
    my $here;
    if ($e->authtoken()) {
        my $auth_usr = $e->checkauth();
        if ($auth_usr) {
            $here = $auth_usr->ws_ou() || $auth_usr->home_ou();
        }
    }

    my $penalty = Fieldmapper::actor::user_standing_penalty->new;
    $penalty->usr( $u->id );
    $penalty->org_unit( $here );
    $penalty->set_date('now');
    $penalty->staff( $e->checkauth()->id() );
    $penalty->standing_penalty(20); # ALERT_NOTE

    my $note = "<sip> CARD BLOCKED BY SELF-CHECK MACHINE. $blocked_card_msg</sip>\n"; # XXX Config option
    my $msg = {
      title => 'SIP',
      message => $note
    };
    my $penalty_result = $U->simplereq(
      'open-ils.actor',
      'open-ils.actor.user.penalty.apply', $e->authtoken, $penalty, $msg);
    if( my $result_code = $U->event_code($penalty_result) ) {
        my $textcode = $penalty_result->{textcode};
        syslog('LOG_ERR', "OILS: Block: patron penalty failed: %s", $textcode);
        $e->rollback; # rollback + disconnect
        return $self;
    }

    $e->commit;
    return $self;
}

# Testing purposes only
sub enable {
    # TODO: we never actually enter this sub if the patron's card is not active
    # For now, to test the removal of the SIP penalties, manually activate the card first
    my ($self, $card_retained) = @_;
    $self->{screen_msg} = "All privileges restored.";

    # Un-mark card as inactive, grep out the patron alert
    my $e = $self->{editor};
    my $u = $self->{user};

    syslog('LOG_INFO', "OILS: Unblocking user %s", $u->card->barcode );

    $e->xact_begin;    # connect and start a new transaction

    if ($u->card->active eq 'f') {
        $u->card->active('t');
        if( ! $e->update_actor_card($u->card) ) {
            syslog('LOG_ERR', "OILS: Unblock card update failed: %s", $e->event->{textcode});
            $e->rollback; # rollback + disconnect
            return $self;
        }
    }

    # look for sip related penalties
    my $sip_penalties = $e->search_actor_usr_message_penalty({ usr => $u->id, title => 'SIP', stop_date => undef });

    if (scalar(@{ $sip_penalties }) == 0) {
        syslog('LOG_INFO', 'OILS: Unblock: no SIP penalties to archive');
    }

    foreach my $aump (@{ $sip_penalties }) {
        my $penalty = $e->retrieve_actor_user_standing_penalty( $aump->ausp_id() );
        $penalty->stop_date('now');
        if ( ! $e->update_actor_user_standing_penalty($penalty) ) {
            syslog('LOG_ERR', "OILS: Unblock: patron alert update failed: %s", $e->event->{textcode});
            $e->rollback; # rollback + disconnect
            return $self;
        }
    }

    $e->commit; # commits and disconnects
    return $self;
}

#
# Messages
#

sub invalid_patron {
    return "Please contact library staff";
}

sub charge_denied {
    return "Please contact library staff";
}

sub inet_privileges {
    my( $self ) = @_;
    my $e = OpenILS::SIP->editor();
    $INET_PRIVS = $e->retrieve_all_config_net_access_level() unless $INET_PRIVS;
    my ($level) = grep { $_->id eq $self->{user}->net_access_level } @$INET_PRIVS;
    my $name = $level->name;
    syslog('LOG_DEBUG', "OILS: Patron inet_privs = $name");
    return $name;
}

sub extra_fields {
    my( $self ) = @_;
    my $extra_fields = {};
    my $u = $self->{user};
    foreach my $stat_cat_entry (@{$u->stat_cat_entries}) {
        my $stat_cat = $stat_cat_entry->stat_cat;
        next unless ($stat_cat->sip_field);
        my $value = $stat_cat_entry->stat_cat_entry;
        if(defined $stat_cat->sip_format && length($stat_cat->sip_format) > 0) { # Has a format string?
            if($stat_cat->sip_format =~ /^\|(.*)\|$/) { # Regex match?
                if($value =~ /($1)/) { # If we have a match
                    if(defined $2) { # Check to see if they embedded a capture group
                        $value = $2; # If so, use it
                    }
                    else { # No embedded capture group?
                        $value = $1; # Use our outer one
                    }
                }
                else { # No match?
                    $value = ''; # Empty string. Will be checked for below.
                }
            }
            else { # Not a regex match - Try sprintf match (looking for a %s, if any)
                $value = sprintf($stat_cat->sip_format, $value);
            }
        }
        next unless length($value) > 0; # No value = no export
        $value =~ s/\|//g; # Remove all lingering pipe chars for sane output purposes
        $extra_fields->{ $stat_cat->sip_field } = [] unless (defined $extra_fields->{$stat_cat->sip_field});
        push(@{$extra_fields->{ $stat_cat->sip_field}}, $value);
    }
    return $extra_fields;
}

1;
