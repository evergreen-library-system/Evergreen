package OpenSRF::DOM::Element::searchCriteria;
use base 'OpenSRF::DOM::Element';
use OpenSRF::DOM;
use OpenSRF::DOM::Element::searchCriterium;

sub new {
	my $self = shift;
	my $class = ref($self) || $self;

	if (@_ == 3 and !ref($_[1])) {
		my @crit = @_;
		@_ = ('AND', \@crit);
	}

	my ($joiner,@crits) = @_;

	unless (@crits) {
		push @crits, $joiner;
		$joiner = 'AND';
	}

	my $collection = $class->SUPER::new(joiner => $joiner);

	for my $crit (@crits) {
		if (ref($crit) and ref($crit) =~ /ARRAY/) {
			if (ref($$crit[1])) {
				$collection->appendChild( $class->new(@$crit) );
			} else {
				$collection->appendChild( OpenSRF::DOM::Element::searchCriterium->new( @$crit ) );
			}
		} else {
			$collection->appendChild($crit);
		}
	}
	return $collection;
}

sub toSQL {
	my $self = shift;

	my @parts = ();
	for my $kid ($self->childNodes) {
		push @parts, $kid->toSQL;
	}
	return '(' . join(' '.$self->getAttribute('joiner').' ', @parts) . ')';
}

1;
