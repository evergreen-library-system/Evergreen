package OpenILS::SIP::Transaction::Hold;
use warnings; use strict;

use Sys::Syslog qw(syslog);
use OpenILS::SIP;
use OpenILS::SIP::Transaction;
use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';

our @ISA = qw(OpenILS::SIP::Transaction);

my %fields = (
    cancel_ok => 0,
    hold => undef
);

sub new {
    my $class = shift;;
    my $self = $class->SUPER::new(@_);

    $self->{_permitted}->{$_} = $fields{$_} for keys %fields;
    @{$self}{keys %fields} = values %fields;

    return bless $self, $class;
}

sub do_hold_cancel {
    my $self = shift;
    my $sip  = shift;

    my $resp = $U->simplereq(
        'open-ils.circ',
        'open-ils.circ.hold.cancel', $self->{authtoken},
        $self->hold->id, 7 # cancel via SIP
    );

    if( my $code = $U->event_code($resp) ) {
        syslog('LOG_INFO', "OILS: Hold cancel failed with event $code : " . $resp->{textcode});
        $self->cancel_ok(0);
        $self->ok(0);
        return $self;
    }

    syslog('LOG_INFO', "OILS: Hold cancellation succeeded for hold " . $self->hold->id);

    $self->cancel_ok(1);
    $self->ok(1);

    # Safely resolve current_copy (ID) to a copy object to fetch the barcode
    if ($self->hold->current_copy) {
        my $copy = $U->simplereq(
            'open-ils.cstore',
            'open-ils.cstore.direct.asset.copy.retrieve',
            $self->hold->current_copy
        );
        if ($copy && !$U->event_code($copy) && $copy->barcode) {
            $self->item($sip->find_item($copy->barcode));
        }
    }

    return $self;
}

sub queue_position {
    # cancelled holds have no queue position
    return undef;
}

sub pickup_location {
    # cancelled holds have no pickup location
    return undef;
}

sub expiration_date {
    # cancelled holds have no pickup location
    return undef;
}




1;
