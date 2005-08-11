package OpenSRF::DomainObject::oilsMethod;

use JSON;
JSON->register_class_hint(hint => 'osrfMethod', class => 'OpenSRF::DomainObject::oilsMethod');

sub toString {
	my $self = shift;
	my $pretty = shift;
	return JSON->perl2prettyJSON($self) if ($pretty);
	return JSON->perl2JSON($self);
}


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
	my $val = shift;
	$self->{method} = $val if (defined $val);
	return $self->{method};
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
	my $val = shift;
	$self->{return_type} = $val if (defined $val);
	return $self->{return_type};
}

=head2 OpenSRF::DomainObject::oilsMethod->params( @new_params )

=over 4

Sets or gets the parameters for this method call.  Just pass in either text
parameters, or DOM nodes of any type.

=back

=cut


sub params {
	my $self = shift;
	my @args = @_;
	$self->{params} = \@args if (@args);
	return @{ $self->{params} };
}

1;
