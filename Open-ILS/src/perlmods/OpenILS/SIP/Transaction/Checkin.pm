#
# An object to handle checkin status
#

package OpenILS::SIP::Transaction::Checkin;

use warnings;
use strict;

use POSIX qw(strftime);
use Sys::Syslog qw(syslog);
use Data::Dumper;

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
    destination_loc  => undef,
    alert_type       => undef,  # 00,01,02,03,04 or 99
#   hold_patron_id   => undef,
#   hold_patron_name => "",
#   hold             => undef,
);

sub new {
    my $class = shift;;
    my $self = $class->SUPER::new(@_);              # start with an Transaction object

    foreach (keys %fields) {
        $self->{_permitted}->{$_} = $fields{$_};    # overlaying _permitted
    }

    @{$self}{keys %fields} = values %fields;        # copying defaults into object

    return bless $self, $class;
}

sub resensitize {
    my $self = shift;
    return 0 if !$self->{item};
    return !$self->{item}->magnetic;
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

    if($current_loc) { # SIP client specified a physical location

        my $org_id = (defined $org_sn_cache{$current_loc}) ? 
            $org_sn_cache{$current_loc} :
            OpenILS::SIP->editor()->search_actor_org_unit({shortname => $current_loc}, {idlist => 1})->[0];

        $org_sn_cache{$current_loc} = $org_id;

        # if the caller specifies a physical location, use it as the checkin circ lib
        $args->{circ_lib} = $phys_location = $org_id if defined $org_id;
    }

    my $resp = $U->simplereq(
        'open-ils.circ',
        'open-ils.circ.checkin',
        $self->{authtoken}, $args
    );

    if ($debug) {
        my $s = Dumper($resp);
        $s =~ s/\n//mog;
        syslog('LOG_INFO', "OILS: Checkin response: $s");
    }

    # In oddball cases, we can receive an array of events.
    # The first event received should be treated as the main result.
    $resp = $$resp[0] if ref($resp) eq 'ARRAY';

    my $code = $U->event_code($resp);
    my $txt  = (defined $code) ? $resp->{textcode} : '';

    syslog('LOG_INFO', "OILS: Checkin resulted in event: $txt");

    $resp->{org} &&= OpenILS::SIP::shortname_from_id($resp->{org}); # Convert id to shortname

    $self->destination_loc($resp->{org}) if $resp->{org};

    if ($txt eq 'ROUTE_ITEM') {
        # Note, this alert_type will be overridden below if this is a hold transit
        $self->alert_type('04'); # send to other branch

    } elsif ($txt and $txt ne 'NO_CHANGE' and $txt ne 'SUCCESS') {
        syslog('LOG_WARNING', "OILS: Checkin returned unexpected event $code : $txt");
        $self->alert_type('00'); # unknown
    }
    
    my $payload = $resp->{payload} || {};

    # Two places to look for hold data.  These are more important and more definitive than above.
    if ($payload->{remote_hold}) {
        # actually only used for checkin at non-owning branch w/ hold at same branch
        $self->item->hold($payload->{remote_hold});     

    } elsif ($payload->{hold}) {
        $self->item->hold($payload->{hold});
    }

    if ($self->item->hold) {
        my $holder = OpenILS::SIP->find_patron('usr' => $self->item->hold->usr) or
            syslog('LOG_WARNING', "OpenILS::SIP->find_patron cannot find hold usr => '" . $self->item->hold->usr . "'");

        $self->item->hold_patron_bcode( $holder->id   );
        $self->item->hold_patron_name(  $holder->name );     # Item already had the holder ID, we really just needed the name
        $self->item->destination_loc( OpenILS::SIP::shortname_from_id($self->item->hold->pickup_lib) );   # must use pickup_lib as method

        my $atype = ($self->item->hold->pickup_lib == $phys_location) ? '01' : '02';
        $self->alert_type($atype);
    }

    $self->alert(1) if defined $self->alert_type;  # alert_type could be "00", hypothetically

    my $circ = $resp->{payload}->{circ} || '';
    my $copy = $resp->{payload}->{copy} || '';

    if ( $circ ) {
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
