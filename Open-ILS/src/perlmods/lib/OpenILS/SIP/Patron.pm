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
use OpenSRF::Utils qw/:datetime/;
use DateTime::Format::ISO8601;
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

    if ($key ne 'usr' and $key ne 'barcode') {
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

    my $e = OpenILS::SIP->editor();

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

    $user->standing_penalties(
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

                        # at this point, there is no concept of "here", so fetch penalties 
                        # for the patron's home lib plus ancestors
                        where => {id => $user->home_ou}, 
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
        ])
    );
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
    return OpenILS::SIP::clean_text(
        sprintf('%s %s %s', 
            ($u->first_given_name || ''),
            ($u->second_given_name || ''),
            ($u->family_name || '')));
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
    my $return = OpenILS::SIP::clean_text(
        join( ' ', map {$_ || ''} (
            $addr->street1,
            $addr->street2,
            $addr->city . ',',
            $addr->county,
            $addr->state,
            $addr->country,
            $addr->post_code
            )
        )
    );
    $return =~ s/\s+/ /sg;     # Compress any run of of whitespace to one space
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
    return OpenILS::SIP::clean_text($self->{user}->email);
}

sub home_phone {
    my $self = shift;
    return $self->{user}->day_phone;
}

sub sip_birthdate {
    my $self = shift;
    my $dob = OpenILS::SIP->format_date($self->{user}->dob);
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

    return OpenILS::SIP::clean_text($self->{user}->profile->name);
}

sub language {
    my $self = shift;
    return '000'; # Unspecified
}

# How much more detail do we need to check here?
# sec: adding logic to return false if user is barred, has a circulation block
# or an expired card
sub charge_ok {
    my $self = shift;
    my $u = $self->{user};

    # compute expiration date for borrowing privileges
    my $expire = DateTime::Format::ISO8601->new->parse_datetime(cleanse_ISO8601($u->expire_date));

    # determine whether patron should be allowed to circulate materials:
    # not barred, doesn't owe too much wrt fines/fees, privileges haven't
    # expired
    my $circ_is_blocked = 
        (($u->barred eq 't') or
         ($u->standing_penalties and @{$u->standing_penalties}) or
         (CORE::time > $expire->epoch));

    return
        !$circ_is_blocked and
        $u->active eq 't' and
        $u->card->active eq 't';
}



# How much more detail do we need to check here?
sub renew_ok {
    my $self = shift;
    return $self->charge_ok;
}

sub recall_ok {
    my $self = shift;
    return 0;
}

sub hold_ok {
    my $self = shift;
    return $self->charge_ok;
}

# return true if the card provided is marked as lost
sub card_lost {
    my $self = shift;
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
    return md5_hex($pwd) eq $self->{user}->passwd;
}

sub currency {              # not really implemented
    my $self = shift;
    syslog('LOG_DEBUG', 'OILS: Patron->currency()');
    return 'USD';
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
    my $expire = DateTime::Format::ISO8601->new->parse_datetime(cleanse_ISO8601($u->expire_date));
    return $b if CORE::time > $expire->epoch;

    return 'OK';
}

sub print_line {            # not implemented
    my $self = shift;
    return '';
}

sub too_many_charged {      # not implemented
    my $self = shift;
    return 0;
}

sub too_many_overdue { 
    my $self = shift;
    return scalar( # PATRON_EXCEEDS_OVERDUE_COUNT
        grep { $_->standing_penalty == 2 } @{$self->{user}->standing_penalties}
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

# not relevant, handled by fines/fees
sub too_many_lost {
    my $self = shift;
    return 0;
}

sub excessive_fines { 
    my $self = shift;
    return scalar( # PATRON_EXCEEDS_FINES
        grep { $_->standing_penalty == 1 } @{$self->{user}->standing_penalties}
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
    my ($self, $start, $end) = @_;
    syslog('LOG_DEBUG', 'OILS: Patron->hold_items()');

     my $holds = $self->{editor}->search_action_hold_request(
        { usr => $self->{user}->id, fulfillment_time => undef, cancel_time => undef }
     );

    my @holds;
    push( @holds, OpenILS::SIP::clean_text($self->__hold_to_title($_)) ) for @$holds;

    return (defined $start and defined $end) ? 
        [ $holds[($start-1)..($end-1)] ] : 
        \@holds;
}

sub __hold_to_title {
    my $self = shift;
    my $hold = shift;
    my $e = $self->{editor};

    my( $id, $mods, $title, $volume, $copy );

    return __copy_to_title($e, 
        $e->retrieve_asset_copy($hold->target)) 
        if $hold->hold_type eq 'C' or $hold->hold_type eq 'F' or $hold->hold_type eq 'R';

    return __volume_to_title($e, 
        $e->retrieve_asset_call_number($hold->target))
        if $hold->hold_type eq 'V';

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


sub __volume_to_title {
    my( $e, $volume ) = @_;
    #syslog('LOG_DEBUG', "OILS: volume_to_title(%s)", $volume->id);
    return __record_to_title($e, $volume->record);
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
    my ($self, $start, $end) = @_;

    $self->__patron_items_info();
    my @overdues = @{$self->{item_info}->{overdue}};
    #$overdues[$_] = __circ_to_title($self->{editor}, $overdues[$_]) for @overdues;

    my @o;
    syslog('LOG_DEBUG', "OILS: overdue_items() fleshing circs @overdues");

    my $return_datatype = OpenILS::SIP->get_option_value('msg64_summary_datatype') || '';
    
    for my $circid (@overdues) {
        next unless $circid;
        if($return_datatype eq 'barcode') {
            push( @o, __circ_to_barcode($self->{editor}, $circid));
        } else {
            push( @o, OpenILS::SIP::clean_text(__circ_to_title($self->{editor}, $circid)));
        }
    }
    @overdues = @o;

    return (defined $start and defined $end) ? 
        [ $overdues[($start-1)..($end-1)] ] : \@overdues;
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
    my ($self, $start, $end) = shift;

    $self->__patron_items_info();

    my @charges = (
        @{$self->{item_info}->{out}},
        @{$self->{item_info}->{overdue}}
        );

    #$charges[$_] = __circ_to_title($self->{editor}, $charges[$_]) for @charges;

    my @c;
    syslog('LOG_DEBUG', "OILS: charged_items() fleshing circs @charges");

    my $return_datatype = OpenILS::SIP->get_option_value('msg64_summary_datatype') || '';

    for my $circid (@charges) {
        next unless $circid;
        if($return_datatype eq 'barcode') {
            push( @c, __circ_to_barcode($self->{editor}, $circid));
        } else {
            push( @c, OpenILS::SIP::clean_text(__circ_to_title($self->{editor}, $circid)));
        }
    }

    @charges = @c;

    return (defined $start and defined $end) ? 
        [ $charges[($start-1)..($end-1)] ] : 
        \@charges;
}

sub fine_items {
    my ($self, $start, $end) = @_;
    my @fines;
    eval {
       my $xacts = $U->simplereq('open-ils.actor', 'open-ils.actor.user.transactions.history.have_balance', $self->{authtoken}, $self->{user}->id);
       foreach my $xact (@{$xacts}) {
           my $line = $xact->balance_owed . " " . $xact->last_billing_type . " ";
           if ($xact->xact_type eq 'circulation') {
               my $mods = $U->simplereq('open-ils.circ', 'open-ils.circ.circ_transaction.find_title', $self->{authtoken}, $xact->id);
               $line .= $mods->title . ' / ' . $mods->author;
           } else {
               $line .= $xact->last_billing_note;
           }
           push @fines, OpenILS::SIP::clean_text($line);
       }
    };
    my $log_status = $@ ? 'ERROR: ' . $@ : 'OK';
    syslog('LOG_DEBUG', 'OILS: Patron->fine_items() ' . $log_status);
    return (defined $start and defined $end) ? 
        [ $fines[($start-1)..($end-1)] ] : \@fines;
}

# not currently supported
sub recall_items {
    my ($self, $start, $end) = @_;
    return [];
}

sub unavail_holds {
     my ($self, $start, $end) = @_;
     syslog('LOG_DEBUG', 'OILS: Patron->unavail_holds()');

     my $ids = $self->{editor}->json_query({
        select => {ahr => ['id']},
        from => 'ahr',
        where => {
            usr => $self->{user}->id,
            fulfillment_time => undef,
            cancel_time => undef,
            '-or' => [
                {current_shelf_lib => undef},
                {current_shelf_lib => {'!=' => {'+ahr' => 'pickup_lib'}}}
            ]
        }
    });
 
     my @holds_sip_output;
     @holds_sip_output = map {
        OpenILS::SIP::clean_text($self->__hold_to_title($_))
     } @{
        $self->{editor}->search_action_hold_request(
            {id => [map {$_->{id}} @$ids]}
        )
     } if (@$ids > 0);
 
     return (defined $start and defined $end) ?
         [ @holds_sip_output[($start-1)..($end-1)] ] :
         \@holds_sip_output;
}

sub block {
    my ($self, $card_retained, $blocked_card_msg) = @_;
    $blocked_card_msg ||= '';

    my $e = $self->{editor};
    my $u = $self->{user};

    syslog('LOG_INFO', "OILS: Blocking user %s", $u->card->barcode );

    return $self if $u->card->active eq 'f';

    $e->xact_begin;    # connect and start a new transaction

    $u->card->active('f');
    if( ! $e->update_actor_card($u->card) ) {
        syslog('LOG_ERR', "OILS: Block card update failed: %s", $e->event->{textcode});
        $e->rollback; # rollback + disconnect
        return $self;
    }

    # retrieve the un-fleshed user object for update
    $u = $e->retrieve_actor_user($u->id);
    my $note = OpenILS::SIP::clean_text($u->alert_message) || "";
    $note = "<sip> CARD BLOCKED BY SELF-CHECK MACHINE. $blocked_card_msg</sip>\n$note"; # XXX Config option
    $note =~ s/\s*$//;  # kill trailng whitespace
    $u->alert_message($note);

    if( ! $e->update_actor_user($u) ) {
        syslog('LOG_ERR', "OILS: Block: patron alert update failed: %s", $e->event->{textcode});
        $e->rollback; # rollback + disconnect
        return $self;
    }

    # stay in synch
    $self->{user}->alert_message( $note );

    $e->commit; # commits and disconnects
    return $self;
}

# Testing purposes only
sub enable {
    my ($self, $card_retained) = @_;
    $self->{screen_msg} = "All privileges restored.";

    # Un-mark card as inactive, grep out the patron alert
    my $e = $self->{editor};
    my $u = $self->{user};

    syslog('LOG_INFO', "OILS: Unblocking user %s", $u->card->barcode );

    return $self if $u->card->active eq 't';

    $e->xact_begin;    # connect and start a new transaction

    $u->card->active('t');
    if( ! $e->update_actor_card($u->card) ) {
        syslog('LOG_ERR', "OILS: Unblock card update failed: %s", $e->event->{textcode});
        $e->rollback; # rollback + disconnect
        return $self;
    }

    # retrieve the un-fleshed user object for update
    $u = $e->retrieve_actor_user($u->id);
    my $note = OpenILS::SIP::clean_text($u->alert_message) || "";
    $note =~ s#<sip>.*</sip>##;
    $note =~ s/^\s*//;  # kill leading whitespace
    $note =~ s/\s*$//;  # kill trailng whitespace
    $u->alert_message($note);

    if( ! $e->update_actor_user($u) ) {
        syslog('LOG_ERR', "OILS: Unblock: patron alert update failed: %s", $e->event->{textcode});
        $e->rollback; # rollback + disconnect
        return $self;
    }

    # stay in synch
    $self->{user}->alert_message( $note );

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
    my $name = OpenILS::SIP::clean_text($level->name);
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
