#
# ILS.pm: Test ILS interface module
#

package OpenILS::SIP;
use warnings; use strict;

use Sys::Syslog qw(syslog);
use Time::HiRes q/time/;

use OpenILS::SIP::Item;
use OpenILS::SIP::Patron;
use OpenILS::SIP::Transaction;
use OpenILS::SIP::Transaction::Checkout;
use OpenILS::SIP::Transaction::Checkin;
use OpenILS::SIP::Transaction::Renew;
use OpenILS::SIP::Transaction::RenewAll;
use OpenILS::SIP::Transaction::FeePayment;
use OpenILS::SIP::Transaction::Hold;

use OpenSRF::System;
use OpenSRF::AppSession;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::DateTime qw/:datetime/;
use DateTime::Format::ISO8601;

my $U = 'OpenILS::Application::AppUtils';

my $editor;
my $config;
my $login_account;
my $target_encoding;    # FIXME: this is configured at the institution level. 

use Digest::MD5 qw(md5_hex);

# Copied from Sip::Constants
use constant {
    SIP_DATETIME => "%Y%m%d    %H%M%S",
};

sub disconnect {
     OpenSRF::Transport::PeerHandle->retrieve->disconnect
}

sub new {
    my ($class, $institution, $login, $state) = @_;
    my $type = ref($class) || $class;
    my $self = {};

    $self->{login} = $login_account = $login;

    $config = $institution;
    syslog("LOG_DEBUG", "OILS: new ILS '%s'", $institution->{id});
    $self->{institution} = $institution;

    my $bsconfig     = $institution->{implementation_config}->{bootstrap};
    $target_encoding = $institution->{implementation_config}->{encoding} || 'ascii';

    syslog('LOG_DEBUG', "OILS: loading bootstrap config: $bsconfig");

    # ingress will persist throughout
    OpenSRF::AppSession->ingress('sip2');
    
    local $/ = "\n";    # why?
    OpenSRF::System->bootstrap_client(config_file => $bsconfig);
    syslog('LOG_DEBUG', "OILS: bootstrap loaded..");

    $self->{osrf_config} = OpenSRF::Utils::SettingsClient->new;

    Fieldmapper->import($self->{osrf_config}->config_value('IDL'));

    bless( $self, $type );

    return undef unless 
        $self->login( $login->{id}, $login->{password}, $state );

    return $self;
}

sub fetch_session {
    my $self = shift;

    my $ses = $U->simplereq( 
        'open-ils.auth',
        'open-ils.auth.session.retrieve',  $self->{authtoken});

    return undef if $U->event_code($ses); # auth timed out
    return $self->{login_session} = $ses;
}

sub verify_session {
    my $self = shift;

    return 1 if $self->fetch_session;

    syslog('LOG_INFO', "OILS: Logging back after session timeout as user ".$self->{login}->{id});
    return $self->login( $self->{login}->{id}, $self->{login}->{password} );
}

sub editor {
    return $editor = make_editor();
}

sub config {
    return $config;
}
sub login_account {
    return $login_account;
}

sub get_option_value {
    my($self, $option) = @_;
    my $ops = $config->{implementation_config}->{options}->{option};
    $ops = [$ops] unless ref $ops eq 'ARRAY';
    my @vals = grep { $_->{name} eq $option } @$ops;
    return @vals ? $vals[0]->{value} : undef;
}


# Creates the global editor object
my $cstore_init = 1; # call init on first use
sub make_editor {
    OpenILS::Utils::CStoreEditor::init() if $cstore_init;
    $cstore_init = 0;
    return OpenILS::Utils::CStoreEditor->new;
}

my %org_sn_cache;
sub shortname_from_id {
    my $id = shift or return;
    return $id->shortname if ref $id;
    return $org_sn_cache{$id} if $org_sn_cache{$id};
    return $org_sn_cache{$id} = editor()->retrieve_actor_org_unit($id)->shortname;
}
sub patron_barcode_from_id {
    my $id = shift or return;
    return editor()->search_actor_card({ usr => $id, active => 't' })->[0]->barcode;
}

sub format_date {
    my $class = shift;
    my $date = shift;
    my $type = shift || '';

    return "" unless $date;

    my $dt = DateTime::Format::ISO8601->new->
        parse_datetime(clean_ISO8601($date));

    # actor.usr.dob stores dates without time/timezone, which causes
    # DateTime to assume the date is stored as UTC.  Tell DateTime
    # to use the local time zone, instead.
    # Other dates will have time zones and should be parsed as-is.
    $dt->set_time_zone('local') if $type eq 'dob';

    my @time = localtime($dt->epoch);

    my $year   = $time[5]+1900;
    my $mon    = $time[4]+1;
    my $day    = $time[3];
    my $hour   = $time[2];
    my $minute = $time[1];
    my $second = $time[0];
  
    $date = sprintf("%04d%02d%02d", $year, $mon, $day);

    # Due dates need hyphen separators and time of day as well
    if ($type eq 'due') {

        my $use_sdf = $class->get_option_value('use_sip_date_format') || '';

        if ($use_sdf =~ /true/i) {
            $date = $dt->strftime(SIP_DATETIME);

        } else {
            $date = sprintf("%04d-%02d-%02d %02d:%02d:%02d", 
                $year, $mon, $day, $hour, $minute, $second);
        }
    }

    syslog('LOG_DEBUG', "OILS: formatted date [type=$type]: $date");
    return $date;
}



sub login {
    my( $self, $username, $password, $state ) = @_;
    syslog('LOG_DEBUG', "OILS: Logging in with username $username");


    if ($state and ref $state and $$state{authtoken}) {
        $self->{authtoken} = $$state{authtoken};
        return $self->{authtoken} if ($self->fetch_session); # fetch the session
    }

    my $nonce = rand($$);

    my $seed = $U->simplereq(
        'open-ils.auth',
        'open-ils.auth.authenticate.init', $username, $nonce );

    my $opts =
        {
            username => $username,
            password => md5_hex($seed . md5_hex($password)),
            type     => 'opac',
            nonce    => $nonce
        };

    if ($self->{login}->{location}) {
        $opts->{workstation} = $self->{login}->{location};
    }

    my $response = $U->simplereq(
        'open-ils.auth',
        'open-ils.auth.authenticate.complete',
        $opts
    );

    if( my $code = $U->event_code($response) ) {
        my $txt = $response->{textcode};
        syslog('LOG_WARNING', "OILS: Login failed for $username.  $txt:$code");
        return undef;
    }

    my $key = $response->{payload}->{authtoken};
    syslog('LOG_INFO', "OILS: Login succeeded for $username : authkey = $key");

    $self->{authtoken} = $key;

    $self->fetch_session; # to cache the login

    return $key;
}

sub state {
    my $self = shift;
    return { authtoken => $self->{authtoken} };
}

sub get_ou_setting {
    my $self = shift;
    my $setting = shift;
    my $sess = $self->fetch_session;
    my $ou = (ref($sess->home_ou)) ? $sess->home_ou->id : $sess->home_ou;
    if ($sess->ws_ou) {
        $ou = (ref($sess->ws_ou)) ? $sess->ws_ou->id : $sess->ws_ou;
    }
    return $U->ou_ancestor_setting_value($ou, $setting);
}

sub get_barcode_regex {
    my $self = shift;
    if (!defined($self->{bc_regex})) {
        $self->{bc_regex} = $self->get_ou_setting('opac.barcode_regex');
        $self->{bc_regex} = '^\d' unless ($self->{bc_regex});
    }
    return $self->{bc_regex};
}

#
# find_patron($barcode);
# find_patron(barcode => $barcode);   # same as above
# find_patron(usr => $id);
# find_patron(usrname => $usrname);

sub find_patron {
    my $self = shift;
    my $key  =  (@_ > 1) ? shift : 'barcode';  # if we have multiple args, the first is the key index (default barcode)
    my $patron_id = shift;
    # want_patron_ok is per-login depending on the needs of your selfcheck or PC management systems.
    my $want_patron_ok = ( $self->{login}->{want_patron_ok} && $self->{login}->{want_patron_ok} =~ /true|yes|enabled/i );

    my $use_username = 
        $self->get_option_value('support_patron_username_login') || '';

    if (to_bool($use_username)) {
        # Check for usrname or barcode in the same, simple way that the OPAC does.
        my $bc_regex = $self->get_barcode_regex();
        if ($key eq 'barcode' && $patron_id !~ /$bc_regex/) {
            $key = 'usrname';
        }
    }

    $self->verify_session;
    return OpenILS::SIP::Patron->new($key => $patron_id, authtoken => $self->{authtoken}, want_ok => $want_patron_ok, @_);
}


sub find_item {
    my $self = shift;
    $self->verify_session;
    return OpenILS::SIP::Item->new(@_);
}


sub institution {
    my $self = shift;
    return $self->{institution}->{id};  # consider making this return the whole institution
}

sub institution_id {
    my $self = shift;
    return $self->{institution}->{id};  # then use this for just the ID
}

sub supports {
    my ($self, $op) = @_;
    my ($i) = grep { $_->{name} eq $op }  
        @{$config->{implementation_config}->{supports}->{item}};
    return to_bool($i->{value});
}

sub check_inst_id {
    my ($self, $id, $whence) = @_;
    if ($id ne $self->{institution}->{id}) {
        syslog("LOG_WARNING", "OILS: %s: received institution '%s', expected '%s'", $whence, $id, $self->{institution}->{id});
        # Just an FYI check, we don't expect the user to change location from that in SIPconfig.xml
    }
}


sub to_bool {
    my $bool = shift;
    # If it's defined, and matches a true sort of string, or is
    # a non-zero number, then it's true.
    defined($bool) or return;                   # false
    ($bool =~ /true|y|yes/i) and return 1;      # true
    return ($bool =~ /^\d+$/ and $bool != 0);   # true for non-zero numbers, false otherwise
}

sub checkout_ok {
    return to_bool($config->{policy}->{checkout});
}

sub checkin_ok {
    return to_bool($config->{policy}->{checkin});
}

sub renew_ok {
    return to_bool($config->{policy}->{renewal});
}

sub status_update_ok {
    return to_bool($config->{policy}->{status_update});
}

sub offline_ok {
    return to_bool($config->{policy}->{offline});
}



##
## Checkout(patron_id, item_id, sc_renew, fee_ack):
##    patron_id & item_id are the identifiers send by the terminal
##    sc_renew is the renewal policy configured on the terminal
## returns a status opject that can be queried for the various bits
## of information that the protocol (SIP or NCIP) needs to generate
## the response.
##    fee_ack is the fee_acknowledged field (BO) sent from the sc
## when doing chargeable loans.
##

sub checkout {
    my ($self, $patron_id, $item_id, $sc_renew, $fee_ack) = @_;
    # In order to allow renewals the selfcheck AND the config have to say they are allowed
    $sc_renew = (chr($sc_renew) eq 'Y' && $self->renew_ok());

    $self->verify_session;

    syslog('LOG_DEBUG', "OILS: OpenILS::Checkout attempt: patron=$patron_id, item=$item_id");

    my $xact   = OpenILS::SIP::Transaction::Checkout->new( authtoken => $self->{authtoken} );
    my $patron = $self->find_patron($patron_id);
    my $item   = $self->find_item($item_id);

    $xact->patron($patron);
    $xact->item($item);

    if (!$patron) {
        $xact->screen_msg("Invalid Patron Barcode '$patron_id'");
        return $xact;
    }

    if (!$patron->charge_ok) {
        $xact->screen_msg("Patron Blocked");
        return $xact;
    }

    if( !$item ) {
        $xact->screen_msg("Invalid Item Barcode: '$item_id'");
        return $xact;
    }

    syslog('LOG_DEBUG', "OILS: OpenILS::Checkout data loaded OK, checking out...");

    if ($item->{patron} && ($item->{patron} eq $patron_id)) {
        $xact->renew_ok(1); # So that accept/reject responses have the correct value later
        if($sc_renew) {
            syslog('LOG_INFO', "OILS: OpenILS::Checkout data loaded OK, doing renew...");
        } else {
            syslog('LOG_INFO', "OILS: OpenILS::Checkout appears to be renew, but renewal disallowed...");
            $xact->screen_msg("Renewals not permitted");
            $xact->ok(0);
            return $xact; # Don't attempt later
        }
    } elsif ($item->{patron} && ($item->{patron} ne $patron_id)) {
        # I can't deal with this right now
        # XXX check in then check out?
        $xact->screen_msg("Item checked out to another patron");
        $xact->ok(0);
        return $xact; # Don't wipe out the screen message later
    } else {
        $sc_renew = 0;
    } 

    # Check for fee and $fee_ack. If there is a fee, and $fee_ack
    # is 'Y', we proceed, otherwise we reject the checkout.
    if ($item->fee > 0.0) {
        $xact->fee_amount($item->fee);
        $xact->sip_fee_type($item->sip_fee_type);
        $xact->sip_currency($item->fee_currency);
        if ($fee_ack && $fee_ack eq 'Y') {
            $xact->fee_ack(1);
        } else {
            $xact->screen_msg('Fee required');
            $xact->ok(0);
            return $xact;
        }
    }

    $xact->do_checkout($sc_renew);
    $xact->desensitize(!$item->magnetic);

    if( $xact->ok ) {
        #editor()->commit;
        syslog("LOG_DEBUG", "OILS: OpenILS::Checkout: " .
            "patron %s checkout %s succeeded", $patron_id, $item_id);
    } else {
        #editor()->xact_rollback;
        syslog("LOG_DEBUG", "OILS: OpenILS::Checkout: " .
            "patron %s checkout %s FAILED, rolling back xact...", $patron_id, $item_id);
    }

    return $xact;
}


sub checkin {
    my ($self, $item_id, $inst_id, $trans_date, $return_date,
        $current_loc, $item_props, $cancel) = @_;

    my $start_time = time();

    $self->verify_session;

    syslog('LOG_DEBUG', "OILS: OpenILS::Checkin of item=$item_id (to $inst_id)");
    
    my $xact = OpenILS::SIP::Transaction::Checkin->new(authtoken => $self->{authtoken});
    my $item = OpenILS::SIP::Item->new($item_id);

    unless ( $xact->item($item) ) {
        $xact->ok(0);
        # $circ->alert(1); $circ->alert_type(99);
        $xact->screen_msg("Invalid Item Barcode: '$item_id'");
        syslog('LOG_INFO', "OILS: Checkin failed.  " . $xact->screen_msg() );
        return $xact;
    }

    $xact->do_checkin( $self, $inst_id, $trans_date, $return_date, $current_loc, $item_props );
    
    if ($xact->ok) {
        $xact->patron($self->find_patron(usr => $xact->{circ_user_id}, slim_user => 1)) if $xact->{circ_user_id};
        delete $item->{patron};
        delete $item->{due_date};
        syslog('LOG_INFO', "OILS: Checkin succeeded");
    } else {
        syslog('LOG_WARNING', "OILS: Checkin failed");
    }

    syslog('LOG_INFO', "OILS: SIP Checkin request took %0.3f seconds", (time() - $start_time));
    return $xact;
}

## If the ILS caches patron information, this lets it free it up.
## Also, this could be used for centrally logging session duration.
## We don't do anything with it.
sub end_patron_session {
    my ($self, $patron_id) = @_;
    return (1, 'Thank you!', '');
}


sub pay_fee {
    my ($self, $patron_id, $patron_pwd, $fee_amt, $fee_type,
    $pay_type, $fee_id, $trans_id, $currency) = @_;

    $self->verify_session;

    my $xact = OpenILS::SIP::Transaction::FeePayment->new(authtoken => $self->{authtoken});
    my $patron = $self->find_patron($patron_id);

    if (!$patron) {
        $xact->screen_msg("Invalid Patron Barcode '$patron_id'");
        $xact->ok(0);
        return $xact;
    }

    $xact->patron($patron);
    $xact->sip_currency($currency);
    $xact->fee_amount($fee_amt);
    $xact->sip_fee_type($fee_type);
    $xact->transaction_id($trans_id);
    $xact->fee_id($fee_id);
    $xact->sip_payment_type($pay_type);
    # We don't presently use this, but we might in the future.
    $xact->patron_password($patron_pwd);

    $xact->do_fee_payment();

    return $xact;
}

#sub add_hold {
#    my ($self, $patron_id, $patron_pwd, $item_id, $title_id,
#    $expiry_date, $pickup_location, $hold_type, $fee_ack) = @_;
#    my ($patron, $item);
#    my $hold;
#    my $trans;
#
#
#    $trans = new ILS::Transaction::Hold;
#
#    # BEGIN TRANSACTION
#    $patron = new ILS::Patron $patron_id;
#    if (!$patron
#    || (defined($patron_pwd) && !$patron->check_password($patron_pwd))) {
#    $trans->screen_msg("Invalid Patron.");
#
#    return $trans;
#    }
#
#    $item = new ILS::Item ($item_id || $title_id);
#    if (!$item) {
#    $trans->screen_msg("No such item.");
#
#    # END TRANSACTION (conditionally)
#    return $trans;
#    } elsif ($item->fee && ($fee_ack ne 'Y')) {
#    $trans->screen_msg = "Fee required to place hold.";
#
#    # END TRANSACTION (conditionally)
#    return $trans;
#    }
#
#    $hold = {
#    item_id         => $item->id,
#    patron_id       => $patron->id,
#    expiration_date => $expiry_date,
#    pickup_location => $pickup_location,
#    hold_type       => $hold_type,
#    };
#
#    $trans->ok(1);
#    $trans->patron($patron);
#    $trans->item($item);
#    $trans->pickup_location($pickup_location);
#
#    push(@{$item->hold_queue}, $hold);
#    push(@{$patron->{hold_items}}, $hold);
#
#
#    # END TRANSACTION
#    return $trans;
#}
#

# Note: item_id in this context is the hold id
sub cancel_hold {
    my ($self, $patron_id, $patron_pwd, $item_id, $title_id) = @_;

    my $trans = OpenILS::SIP::Transaction::Hold->new(authtoken => $self->{authtoken});
    my $patron = $self->find_patron($patron_id);

    if (!$patron) {
        $trans->screen_msg("Invalid patron barcode.");
        $trans->ok(0);
        return $trans;
    }

    if (defined($patron_pwd) && !$patron->check_password($patron_pwd)) {
        $trans->screen_msg('Invalid patron password.');
        $trans->ok(0);
        return $trans;
    }

    $trans->patron($patron);
    my $hold = $patron->find_hold_from_copy($item_id);

    if (!$hold) {
        syslog('LOG_WARNING', "OILS: No hold found from copy $item_id");
        $trans->screen_msg("No such hold.");
        $trans->ok(0);
        return $trans;
    }

    if ($hold->usr ne $patron->{user}->id) {
        $trans->screen_msg("No such hold on patron record.");
        $trans->ok(0);
        return $trans;
    }

    $trans->hold($hold);
    $trans->do_hold_cancel($self);

    if ($trans->cancel_ok) {
        $trans->screen_msg("Hold Cancelled.");
    } else {
        $trans->screen_msg("Hold was not cancelled.");
    }

    # if the hold had no current_copy, use the representative
    # item as the item for the hold.  Without this, the SIP 
    # server gets angry.
    $trans->item($self->find_item($item_id)) unless $trans->item;

    return $trans;
}

#
## The patron and item id's can't be altered, but the
## date, location, and type can.
#sub alter_hold {
#    my ($self, $patron_id, $patron_pwd, $item_id, $title_id,
#    $expiry_date, $pickup_location, $hold_type, $fee_ack) = @_;
#    my ($patron, $item);
#    my $hold;
#    my $trans;
#
#    $trans = new ILS::Transaction::Hold;
#
#    # BEGIN TRANSACTION
#    $patron = new ILS::Patron $patron_id;
#    if (!$patron) {
#    $trans->screen_msg("Invalid patron barcode.");
#
#    return $trans;
#    }
#
#    foreach my $i (0 .. scalar @{$patron->{hold_items}}) {
#    $hold = $patron->{hold_items}[$i];
#
#    if ($hold->{item_id} eq $item_id) {
#        # Found it.  So fix it.
#        $hold->{expiration_date} = $expiry_date if $expiry_date;
#        $hold->{pickup_location} = $pickup_location if $pickup_location;
#        $hold->{hold_type} = $hold_type if $hold_type;
#
#        $trans->ok(1);
#        $trans->screen_msg("Hold updated.");
#        $trans->patron($patron);
#        $trans->item(new ILS::Item $hold->{item_id});
#        last;
#    }
#    }
#
#    # The same hold structure is linked into both the patron's
#    # list of hold items and into the queue of outstanding holds
#    # for the item, so we don't need to search the hold queue for
#    # the item, since it's already been updated by the patron code.
#
#    if (!$trans->ok) {
#    $trans->screen_msg("No such outstanding hold.");
#    }
#
#    return $trans;
#}


sub renew {
    my ($self, $patron_id, $patron_pwd, $item_id, $title_id,
        $no_block, $nb_due_date, $third_party, $item_props, $fee_ack) = @_;

    $self->verify_session;

    my $trans = OpenILS::SIP::Transaction::Renew->new( authtoken => $self->{authtoken} );
    $trans->patron($self->find_patron($patron_id));
    $trans->item($self->find_item($item_id));

    if(!$trans->patron) {
        $trans->screen_msg("Invalid patron barcode.");
        $trans->ok(0);
        return $trans;
    }

    if(!$trans->patron->renew_ok) {
        $trans->screen_msg("Renewals not allowed.");
        $trans->ok(0);
        return $trans;
    }

    if(!$trans->item) {
        if( $title_id ) {
            $trans->screen_msg("Title ID renewal not supported.  Use item barcode.");
        } else {
            $trans->screen_msg("Invalid item barcode.");
        }
        $trans->ok(0);
        return $trans;
    }

    if(!$trans->item->{patron} or 
            $trans->item->{patron} ne $patron_id) {
        $trans->screen_msg("Item not checked out to " . $trans->patron->name);
        $trans->ok(0);
        return $trans;
    }

    # Perform the renewal
    $trans->do_renew();

    $trans->desensitize(0);    # It's already checked out
    $trans->item->{due_date} = $nb_due_date if $no_block eq 'Y';
    $trans->item->{sip_item_properties} = $item_props if $item_props;

    return $trans;
}


sub renew_all {
    my ($self, $patron_id, $patron_pwd, $fee_ack) = @_;

    $self->verify_session;

    my $trans = OpenILS::SIP::Transaction::RenewAll->new(authtoken => $self->{authtoken});
    $trans->patron($self->find_patron($patron_id));

    if(!$trans->patron) {
        $trans->screen_msg("Invalid patron barcode.");
        $trans->ok(0);
        return $trans;
    }

    if(!$trans->patron->renew_ok) {
        $trans->screen_msg("Renewals not allowed.");
        $trans->ok(0);
        return $trans;
    }

    $trans->do_renew_all($self);
    return $trans;
}


#
#sub renew_all {
#    my ($self, $patron_id, $patron_pwd, $fee_ack) = @_;
#    my ($patron, $item_id);
#    my $trans;
#
#    $trans = new ILS::Transaction::RenewAll;
#
#    $trans->patron($patron = new ILS::Patron $patron_id);
#    if (defined $patron) {
#    syslog("LOG_DEBUG", "ILS::renew_all: patron '%s': renew_ok: %s",
#           $patron->name, $patron->renew_ok);
#    } else {
#    syslog("LOG_DEBUG", "ILS::renew_all: Invalid patron id: '%s'",
#           $patron_id);
#    }
#
#    if (!defined($patron)) {
#    $trans->screen_msg("Invalid patron barcode.");
#    return $trans;
#    } elsif (!$patron->renew_ok) {
#    $trans->screen_msg("Renewals not allowed.");
#    return $trans;
#    } elsif (defined($patron_pwd) && !$patron->check_password($patron_pwd)) {
#    $trans->screen_msg("Invalid patron password.");
#    return $trans;
#    }
#
#    foreach $item_id (@{$patron->{items}}) {
#    my $item = new ILS::Item $item_id;
#
#    if (!defined($item)) {
#        syslog("LOG_WARNING",
#           "renew_all: Invalid item id associated with patron '%s'",
#           $patron->id);
#        next;
#    }
#
#    if (@{$item->hold_queue}) {
#        # Can't renew if there are outstanding holds
#        push @{$trans->unrenewed}, $item_id;
#    } else {
#        $item->{due_date} = time + (14*24*60*60); # two weeks hence
#        push @{$trans->renewed}, $item_id;
#    }
#    }
#
#    $trans->ok(1);
#
#    return $trans;
#}

1;
