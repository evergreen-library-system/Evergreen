package OpenSRF::DomainObject::oilsMethod;
use OpenSRF::DOM::Element::params;
#use OpenSRF::DOM::Element::param;
use JSON;
use base 'OpenSRF::DomainObject';

=head1 NAME

OpenSRF::DomainObject::oilsMethod

=head1 SYNOPSIS

use OpenSRF::DomainObject::oilsMethod;

my $method = OpenSRF::DomainObject::oilsMethod->new( method => 'search' );

$method->return_type( 'mods' );

$method->params( 'title:harry potter' );

$client->send( 'REQUEST', $method );

=head1 METHODS

=head2 OpenSRF::DomainObject::oilsMethod->method( [$new_method_name] )

=over 4

Sets or gets the method name that will be called on the server.  As above,
this can be specified as a build attribute as well as added to a prebuilt
oilsMethod object.

=back

=cut

sub method {
	my $self = shift;
	return $self->_attr_get_set( method => shift );
}

=head2 OpenSRF::DomainObject::oilsMethod->return_type( [$new_return_type] )

=over 4

Sets or gets the return type for this method call.  This can also be supplied as
a build attribute.

This option does not require that the server return the type you request.  It is
used as a suggestion when more than one return type or format is possible.

=back

=cut


sub return_type {
	my $self = shift;
	return $self->_attr_get_set( return_type => shift );
}

=head2 OpenSRF::DomainObject::oilsMethod->params( [@new_params] )

=over 4

Sets or gets the parameters for this method call.  Just pass in either text
parameters, or DOM nodes of any type.

=back

=cut


sub params {
	my $self = shift;
	my @args = @_;

	my ($old_params) = $self->getChildrenByTagName('oils:params');

	my $params;
	if (@args) {

		$self->removeChild($old_params) if ($old_params);

		my $params = OpenSRF::DOM::Element::params->new;
		$self->appendChild($params);
		$params->appendTextNode( JSON->perl2JSON( \@args ) );

		$old_params = $params unless ($old_params);
	}

	if ($old_params) {
		$params = JSON->JSON2perl( $old_params->textContent );
		return @$params;
	}

	return @args;
}

1;
