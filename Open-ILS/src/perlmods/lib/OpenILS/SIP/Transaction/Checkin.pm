package OpenILS::SIP::Transaction::Checkin;
use warnings; use strict;

use POSIX qw(strftime);
use Sys::Syslog qw(syslog);
use Data::Dumper;
use Time::HiRes q/time/;

use OpenILS::SIP;
use OpenILS::SIP::Transaction;
use OpenILS::Const qw/:const/;
use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';

use base qw(OpenILS::SIP::Transaction);

my $debug = 0;

my %fields = (
    magnetic => 0,
    sort_bin => undef,
    # 3M extensions: (most of the data is stored under Item)
#   collection_code  => undef,
#   call_number      => undef,
    alert_type       => undef,  # 00,01,02,03,04 or 99
#   hold_patron_id   => undef,
#   hold_patron_name => "",
#   hold             => undef,
);

my $hold_as_transit = 0;

sub new {
    my $class = shift;;
    my $self = $class->SUPER::new(@_);              # start with an Transaction object

    foreach (keys %fields) {
        $self->{_permitted}->{$_} = $fields{$_};    # overlaying _permitted
    }

    @{$self}{keys %fields} = values %fields;        # copying defaults into object

    $self->load_override_events;

    $hold_as_transit = OpenILS::SIP->config->{implementation_config}->{checkin_hold_as_transit};

    return bless $self, $class;
}

sub resensitize {
    my $self = shift;
    return 0 if !$self->{item};
    return !$self->{item}->magnetic;
}

my %override_events;
sub load_override_events {
    return if %override_events;
    my $override = OpenILS::SIP->config->{implementation_config}->{checkin_override};
    return unless $override;
    my $events = $override->{event};
    $events = [$events] unless ref $events eq 'ARRAY';
    $override_events{$_} = 1 for @$events;
}

my %org_sn_cache;
sub do_checkin {
    my $self = shift;
    my ($sip_handler, $inst_id, $trans_date, $return_date, $current_loc, $item_props) = @_; # most unused

    unless($self->{item}) {
        $self->ok(0);
        return undef;
    }

    $inst_id ||= '';

    # physical location defaults to ws ou of the logged in sip user,
    # which currently defaults to home_ou, since ws's aren't used.
    my $phys_location = $sip_handler->{login_session}->ws_ou;

    my $args = {barcode => $self->{item}->id};
    $args->{hold_as_transit} = 1 if $hold_as_transit;

    if($return_date) {
        # SIP date format is YYYYMMDD.  Translate to ISO8601
        $return_date =~ s/(\d{4})(\d{2})(\d{2}).*/$1-$2-$3/;
        syslog('LOG_INFO', "Checking in with backdate $return_date");
        $args->{backdate} = $return_date;
    }

    if($current_loc) { # SIP client specified a physical location

        my $org_id = (defined $org_sn_cache{$current_loc}) ? 
            $org_sn_cache{$current_loc} :
            OpenILS::SIP->editor()->search_actor_org_unit({shortname => $current_loc}, {idlist => 1})->[0];

        $org_sn_cache{$current_loc} = $org_id;

        # if the caller specifies a physical location, use it as the checkin circ lib
        $args->{circ_lib} = $phys_location = $org_id if defined $org_id;
    }

    my $override = 0;
    my ($resp, $txt, $code);

    while(1) {

        my $method = 'open-ils.circ.checkin';
        $method .= '.override' if $override;

        my $start_time = time();
        $resp = $U->simplereq('open-ils.circ', $method, $self->{authtoken}, $args);
        syslog('LOG_INFO', "OILS: Checkin API call took %0.3f seconds", (time() - $start_time));

        if ($debug) {
            my $s = Dumper($resp);
            $s =~ s/\n//mog;
            syslog('LOG_INFO', "OILS: Checkin response: $s");
        }

        # In oddball cases, we can receive an array of events.
        # The first event received should be treated as the main result.
        $resp = $$resp[0] if ref($resp) eq 'ARRAY';
        $code = $U->event_code($resp);
        $txt  = (defined $code) ? $resp->{textcode} : '';

        last if $override;

        if ( $override_events{$txt} ) {
            $override = 1;
        } else {
            last;
        }
    }

    syslog('LOG_INFO', "OILS: Checkin resulted in event: $txt, phys_location: $phys_location");

    $resp->{org} &&= OpenILS::SIP::shortname_from_id($resp->{org}); # Convert id to shortname

    $self->item->destination_loc($resp->{org}) if $resp->{org};

    if ($txt eq 'ROUTE_ITEM') {
        # Note, this alert_type will be overridden below if this is a hold transit
        $self->alert_type('04'); # send to other branch

    } elsif ($txt and $txt ne 'NO_CHANGE' and $txt ne 'SUCCESS') {
        syslog('LOG_WARNING', "OILS: Checkin returned unexpected event $code : $txt");
        $self->alert_type('00'); # unknown
    }
    
    my $payload = $resp->{payload} || {};

    my ($circ, $copy);

    if(ref $payload eq 'HASH') {

        # Two places to look for hold data.  These are more important and more definitive than above.
        if ($payload->{remote_hold}) {
            # actually only used for checkin at non-owning branch w/ hold at same branch
            $self->item->hold($payload->{remote_hold});     

        } elsif ($payload->{hold}) {
            $self->item->hold($payload->{hold});
        }

        $circ = $resp->{payload}->{circ} || '';
        $copy = $resp->{payload}->{copy} || '';
    }

    if ($copy) {
        # Checkin of floating copies changes the circ lib.
        # Update our SIP "item" to reflect the change.

        if ($copy->circ_lib != $self->item->{copy}->circ_lib->id) {
            syslog('LOG_INFO', "OILS: updating copy circ lib after checkin");

            $self->item->{copy}->circ_lib(
                OpenILS::SIP->editor()
                    ->retrieve_actor_org_unit($copy->circ_lib)
            );
        }
    }

    if ($self->item->hold) {
        my ($pickup_lib_id, $pickup_lib_sn);

        my $holder = OpenILS::SIP->editor()->retrieve_actor_user(
            [$self->item->hold->usr, {flesh => 1, flesh_fields => {au => ['card']}}]);

        my $holder_name = OpenILS::SIP::Patron::format_name($holder);

        if (ref $self->item->hold->pickup_lib) {
            $pickup_lib_id = $self->item->hold->pickup_lib->id;
            $pickup_lib_sn = $self->item->hold->pickup_lib->shortname;

        } else {
            $pickup_lib_id = $self->item->hold->pickup_lib;
            $pickup_lib_sn = OpenILS::SIP::shortname_from_id($pickup_lib_id);
        }

        $self->item->hold_patron_bcode( ($holder->card) ? $holder->card->barcode : '');
        $self->item->hold_patron_name($holder_name);
        $self->item->destination_loc($pickup_lib_sn); 

        my $atype = ($pickup_lib_id == $phys_location) ? '01' : '02';
        $self->alert_type($atype);
    }

    $self->alert(1) if defined $self->alert_type;  # alert_type could be "00", hypothetically

    if ( $circ ) {
        $self->{circ_user_id} = $circ->usr;
        $self->ok(1);
    } elsif ($txt eq 'NO_CHANGE' or $txt eq 'SUCCESS' or $txt eq 'ROUTE_ITEM') {
        $self->ok(1); # NO_CHANGE means it wasn't checked out anyway, no problem
    } else {
        $self->alert(1);
        $self->alert_type('00') unless $self->alert_type; # wasn't checked out, but *something* changed
        # $self->ok(0); # maybe still ok?
    }
}

1;
__END__

Successful Checkin event payload includes:
    $payload->{copy}   (unfleshed)
    $payload->{record} 
    $payload->{circ}   
    $payload->{transit}
    $payload->{cancelled_hold_transit}
    $payload->{hold}   
    $payload->{patron} 

Some EVENT strings:
    SUCCESS                => ,
    ASSET_COPY_NOT_FOUND   => ,
    NO_CHANGE              => ,
    PERM_FAILURE           => ,
    CIRC_CLAIMS_RETURNED   => ,
    COPY_ALERT_MESSAGE     => ,
    COPY_STATUS_LOST       => ,
    COPY_STATUS_MISSING    => ,
    COPY_BAD_STATUS        => ,
    ITEM_DEPOSIT_PAID      => ,
    ROUTE_ITEM             => ,
    DATABASE_UPDATE_FAILED => ,
    DATABASE_QUERY_FAILED  => ,

# alert_type:
#   00 - Unknown
#   01 - hold in local library
#   02 - hold for other branch
#   03 - hold for ILL (not used in EG)
#   04 - send to other branch (no hold)
#   99 - Other
