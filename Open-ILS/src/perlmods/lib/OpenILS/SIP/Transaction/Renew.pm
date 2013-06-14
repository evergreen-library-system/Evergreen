#
# Status of a Renew Transaction
#

package OpenILS::SIP::Transaction::Renew;
use warnings; use strict;

use Sys::Syslog qw(syslog);
use OpenILS::SIP;
use OpenILS::SIP::Transaction;
use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';

our @ISA = qw(OpenILS::SIP::Transaction);

my %fields = (
          renewal_ok => 0,
          );

sub new {
    my $class = shift;;
    my $self = $class->SUPER::new(@_);

    $self->{_permitted}->{$_} = $fields{$_} for keys %fields;
    @{$self}{keys %fields} = values %fields;

    return bless $self, $class;
}

sub do_renew {
    my $self = shift;

    my $resp = $U->simplereq(
        'open-ils.circ',
        'open-ils.circ.renew', $self->{authtoken},
        { barcode => $self->item->id, patron_barcode => $self->patron->id });

    if( my $code = $U->event_code($resp) ) {
        syslog('LOG_INFO', "OILS: Renewal failed with event $code : " . $resp->{textcode});
        $self->renewal_ok(0);
        $self->ok(0);
        return $self;
    }

    $self->item->{due_date} = $resp->{payload}->{circ}->due_date;
    syslog('LOG_INFO', "OILS: Renewal succeeded with due_date = " . $self->item->{due_date});

    $self->renewal_ok(1);
    $self->ok(1);

    return $self;
}


1;
