package OpenSRF::DOM::Element::domainObjectAttr;
use base 'OpenSRF::DOM::Element';

sub new {
	my $class = shift;
	my @nodes;
	while (@_) {
		my ($name,$val) = (shift,shift);
		push @nodes, $class->SUPER::new(name => $name, value => $val);
	}
	return @nodes if (wantarray);
	return $nodes[0];
}

1;
