package OpenSRF::DOM::Element::domainObjectCollection;
use base 'OpenSRF::DOM::Element';
use OpenSRF::DOM::Element::domainObjectAttr;
use OpenSRF::EX;

sub AUTOLOAD {
	my $self = CORE::shift;
	(my $name = $AUTOLOAD) =~ s/.*://;   # strip fully-qualified portion

	return  class($self) if ($name eq 'class');

	my @args = @_;
	my $meth = class($self).'::'.$name;

	### Check for recursion
	my $calling_method = (caller(1))[3];
	my @info = caller(1);

	if( @info ) {
		if ($info[0] =~ /AUTOLOAD/) { @info = caller(2); }
	}
	unless( @info ) { @info = caller(); }
		if( $calling_method  and $calling_method eq "OpenSRF::DOM::Element::domainObjectCollection::AUTOLOAD" ) {
		throw OpenSRF::EX::PANIC ( "RECURSION! Caller [ @info ] | Object [ ".ref($self)." ]\n ** Trying to call $name", ERROR );
	}
	### Check for recursion

	try {
		return $self->$meth(@args);;
	} catch Error with {
		my $e = shift;
		OpenSRF::Utils::Logger->error( $@ . $e);
		die $@;
	};

	return upcast($self)->$name(@_);
}

sub downcast {
	my $obj = CORE::shift;
	return bless $obj => 'XML::LibXML::Element';
}

sub upcast {
	my $self = CORE::shift;
	return bless $self => class($self);
}

sub new {
	my $class = CORE::shift;
	my $type = CORE::shift;
	my $obj = $class->SUPER::new( name => $type );
	while ( my $val = shift) {
		throw OpenSRF::EX::NotADomainObject
			if (ref $val and $val->nodeName !~ /^oils:domainObject/o);
		$obj->appendChild( $val );
	}
	return $obj;
}

sub class {
	my $self = shift;
	return 'OpenSRF::DomainObjectCollection::'.$self->getAttribute('name');
}

sub base_type {
	my $self = shift;
	return $self->getAttribute('name');
}

sub pop { 
	my $self = CORE::shift;
	return $self->removeChild( $self->lastChild )->upcast;
}

sub push { 
	my $self = CORE::shift;
	my @args = @_;
	for my $node (@args) {
		#throw OpenSRF::EX::NotADomainObject ( "$_ must be a oils:domainOjbect*, it's a ".$_->nodeName )
		#	unless ($_->nodeName =~ /^oils:domainObject/o);
		
		unless ($node->nodeName =~ /^oils:domainObject/o) {
			$node = OpenSRF::DomainObject::oilsScalar->new($node);
		}

		$self->appendChild( $node );
	}
}

sub shift { 
	my $self = CORE::shift;
	return $self->removeChild( $self->firstChild )->upcast;
}

sub unshift { 
	my $self = CORE::shift;
	my @args = @_;
	for (reverse @args) {
		throw OpenSRF::EX::NotADomainObject
			unless ($_->nodeName =~ /^oils:domainObject/o);
		$self->insertBefore( $_, $self->firstChild );
	}
}

sub first {
	my $self = CORE::shift;
	return $self->firstChild->upcast;
}

sub list {
	my $self = CORE::shift;
	return map {(bless($_ => 'OpenSRF::DomainObject::'.$_->getAttribute('name')))} $self->childNodes;
}

1;
