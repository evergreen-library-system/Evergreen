package OpenSRF::DOM::Element::domainObject;
use strict; use warnings;
use base 'OpenSRF::DOM::Element';
use OpenSRF::DOM;
use OpenSRF::DOM::Element::domainObjectAttr;
use OpenSRF::Utils::Logger qw(:level);
use OpenSRF::EX;
use Carp;
#use OpenSRF::DomainObject::oilsPrimitive;
#use OpenSRF::DomainObject::oilsResponse;
use vars qw($AUTOLOAD);

sub AUTOLOAD {
	my $self = shift;
	(my $name = $AUTOLOAD) =~ s/.*://;   # strip fully-qualified portion

	return class($self) if ($name eq 'class');
	if ($self->can($name)) {
		return $self->$name(@_);
	}

	if (1) {
		### Check for recursion
		my $calling_method = (caller(1))[3];
		my @info = caller(1);

		if( @info ) {
			if ($info[0] =~ /AUTOLOAD/) { @info = caller(2); }
		}
		unless( @info ) { @info = caller(); }

		if( $calling_method  and $calling_method eq "OpenSRF::DOM::Element::domainObject::AUTOLOAD" ) {
			warn Carp::cluck;
			throw OpenSRF::EX::PANIC ( "RECURSION! Caller [ @info[0..2] ] | Object [ ".ref($self)." ]\n ** Trying to call $name", ERROR );
		}
		### Check for recursion
	}

        my @args = @_;
	my $meth = class($self).'::'.$name;

	try {
		return $self->$meth(@args);
	} catch Error with {
		my $e = shift;
		if( $e ) {
			OpenSRF::Utils::Logger->error( $@ . $e);
		} else {
			OpenSRF::Utils::Logger->error( $@ );
		}
		die $@;
	};


	my $node = OpenSRF::DOM::Element::domainObject::upcast($self);
	OpenSRF::Utils::Logger->debug( "Autoloaded to: ".ref($node), INTERNAL );

	return $node->$name(@_);
}

sub downcast {
	my $obj = shift;
	return bless $obj => 'XML::LibXML::Element';
}

sub upcast {
	my $self = shift;
	return bless $self => class($self);
}

sub new {
	my $class = shift;
	my $type = shift;
	my $obj = $class->SUPER::new( name => $type );
	while (@_) {
		my ($attr,$val) = (shift,shift);
		last unless ($attr and $val);
		$obj->addAttr( $attr, $val );
		#$obj->appendChild( OpenSRF::DOM::Element::domainObjectAttr->new($attr, $val) );
	}
	return $obj;
}

sub class {
	my $self = shift;
	return 'OpenSRF::DomainObject::'.$self->getAttribute('name');
}

sub base_type {
	my $self = shift;
        return $self->getAttribute('name');
}

sub addAttr {
	my $self = shift;
	$self->appendChild( $_ ) for OpenSRF::DOM::Element::domainObjectAttr->new(@_);
	return $self;
}

sub attrNode {
	my $self = shift;
	my $type = shift;
	return (grep { $_->getAttribute('name') eq $type } $self->getChildrenByTagName("oils:domainObjectAttr"))[0];
}

sub attrHash {
	my $self = shift;
	my %attrs = map { ( $_->getAttribute('name') => $_->getAttribute('value') ) } $self->getChildrenByTagName('oils:domainObjectAttr');

	return \%attrs;
}

sub attrValue {
	my $self = shift;
	return $self->attrHash->{shift};
}

1;
