package OpenSRF::DOM::Element::searchTargetValue;
use base 'OpenSRF::DOM::Element';

sub new {
	my $self = shift;
	my $class = ref($self) || $self;
	my @args = @_;

	my @values = ();
	for my $val (@args) {
		next unless ($val);
		if (ref($val)) {
			push @values, $class->new(@$val);
		} else {
			push @values, $class->SUPER::new( value => $val );
		}
		
	}
	return $values[0] if (!wantarray);
	return @values;
}

1;
