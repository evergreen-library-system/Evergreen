#
# An object to handle checkin status
#

package OpenILS::SIP::Transaction::Checkin;

use warnings;
use strict;

use POSIX qw(strftime);

use OpenILS::SIP;
use OpenILS::SIP::Transaction;
use Data::Dumper;

use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';

our @ISA = qw(OpenILS::SIP::Transaction);

my %fields = (
	      magnetic => 0,
	      sort_bin => undef,
	      );

sub new {
    my $class = shift;;
    my $self = $class->SUPER::new(@_);
    my $element;

	foreach $element (keys %fields) {
		$self->{_permitted}->{$element} = $fields{$element};
	}

    @{$self}{keys %fields} = values %fields;

    return bless $self, $class;
}

sub resensitize {
    my $self = shift;
    return !$self->{item}->magnetic;
}


sub do_checkin {
	my $self = shift;

	my $resp = $U->simplereq( 
		'open-ils.circ', 
		'open-ils.circ.checkin', 
		$self->{authtoken}, { barcode => $self->{item}->id } );


	my $circ = $resp->{payload}->{circ};

	if(!$circ) {
		warn 'CHECKIN: ' . Dumper($resp) . "\n";
		$self->ok(0);
		return 0;
	}

	$self->{item}->{patron} = $self->editor->search_actor_card(
		{ usr => $circ->usr, active => 't' } )->[0]->barcode;

	$self->ok(1);

	return 1;
}


1;
