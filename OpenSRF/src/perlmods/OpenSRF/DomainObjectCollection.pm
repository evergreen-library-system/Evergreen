package OpenSRF::DomainObjectCollection;
use base 'OpenSRF::DOM::Element::domainObjectCollection';
use OpenSRF::DOM;
use OpenSRF::Utils::Logger qw(:level);
my $logger = "OpenSRF::Utils::Logger";

=head1 NAME

OpenSRF::DomainObjectCollection

=head1 SYNOPSIS

OpenSRF::DomainObjectCollection is an abstract base class.  It
should not be used directly.  See C<OpenSRF::DomainObjectCollection::*>
for details.

=cut

sub new {
	my $class = shift;
	$class = ref($class) || $class;

	my @args = shift;

	(my $type = $class) =~ s/^.+://o;

	my $doc = OpenSRF::DOM->createDocument;
	my $dO = OpenSRF::DOM::Element::domainObjectCollection->new( $type, @args );

	$doc->documentElement->appendChild($dO);

	return $dO;
}

1;
