package OpenSRF::DomainObject;
use base 'OpenSRF::DOM::Element::domainObject';
use OpenSRF::DOM;
use OpenSRF::Utils::Logger qw(:level);
use OpenSRF::DomainObject::oilsPrimitive;
my $logger = "OpenSRF::Utils::Logger";

=head1 NAME

OpenSRF::DomainObject

=head1 SYNOPSIS

OpenSRF::DomainObject is an abstract base class.  It
should not be used directly.  See C<OpenSRF::DomainObject::*>
for details.

=cut

my $tmp_doc;

sub object_castor {
	my $self = shift;
	my $node = shift;

	return unless (defined $node);

	if (ref($node) eq 'HASH') {
		return new OpenSRF::DomainObject::oilsHash (%$node);
	} elsif (ref($node) eq 'ARRAY') {
		return new OpenSRF::DomainObject::oilsArray (@$node);
	}

	return $node;
}

sub native_castor {
	my $self = shift;
	my $node = shift;

	return unless (defined $node);

	if ($node->nodeType == 3) {
		return $node->nodeValue;
	} elsif ($node->nodeName =~ /domainObject/o) {
		return $node->tie_me if ($node->class->can('tie_me'));
	}
	return $node;
}

sub new {
	my $class = shift;
	$class = ref($class) || $class;

	(my $type = $class) =~ s/^.+://o;

	$tmp_doc ||= OpenSRF::DOM->createDocument;
	my $dO = OpenSRF::DOM::Element::domainObject->new( $type, @_ );

	$tmp_doc->documentElement->appendChild($dO);

	return $dO;
}

sub _attr_get_set {
	my $self = shift;
	my $part = shift;

	$logger->debug( "DomainObject:_attr_get_set: ". $self->toString, INTERNAL );

	my $node = $self->attrNode($part);

	$logger->debug( "DomainObject:_attr_get_set " . $node->toString(), INTERNAL ) if ($node);


	if (defined(my $new_value = shift)) {
		if (defined $node) {
			my $old_val = $node->getAttribute( "value" );
			$node->setAttribute(value => $new_value);
			return $old_val;
		} else {
			$self->addAttr( $part => $new_value );
			return $new_value;
		}
	} elsif ( $node ) {
		return $node->getAttribute( "value" );
	}
}

1;
