package OpenSRF::DomainObject::oilsScalar;
use base 'OpenSRF::DomainObject';
use OpenSRF::DomainObject;

=head1 NAME

OpenSRF::DomainObject::oilsScalar

=head1 SYNOPSIS

  use OpenSRF::DomainObject::oilsScalar;

  my $text = OpenSRF::DomainObject::oilsScalar->new( 'a string or number' );
  $text->value( 'replacement value' );
  print "$text"; # stringify

   ...

  $text->value( 1 );
  if( $text ) { # boolify

   ...

  $text->value( rand() * 1000 );
  print 10 + $text; # numify

    Or, using the TIE interface:

  my $scalar;
  my $real_object = tie($scalar, 'OpenSRF::DomainObject::oilsScalar', "a string to store...");

  $scalar = "a new string";
  print $scalar . "\n";
  print $real_object->toString . "\n";

=head1 METHODS

=head2 OpenSRF::DomainObject::oilsScalar->value( [$new_value] )

=over 4

Sets or gets the value of the scalar.  As above, this can be specified
as a build attribute as well as added to a prebuilt oilsScalar object.

=back

=cut

use overload '""'   => sub { return ''.$_[0]->value };
use overload '0+'   => sub { return int($_[0]->value) };
use overload '<=>'   => sub { return int($_[0]->value) <=> $_[1] };
use overload 'bool' => sub { return 1 if ($_[0]->value); return 0 };

sub new {
	my $class = shift;
	$class = ref($class) || $class;

	my $value = shift;

	return $value
		if (	defined $value and
			ref $value and $value->can('base_type') and
			UNIVERSAL::isa($value->class, __PACKAGE__) and
			!scalar(@_)
		);

	my $self = $class->SUPER::new;

	if (ref($value) and ref($value) eq 'SCALAR') {
		$self->value($$value);
		tie( $$value, ref($self->upcast), $self);
	} else {
		$self->value($value) if (defined $value);
	}

	return $self;
}

sub TIESCALAR {
	return CORE::shift()->new(@_);
}

sub value {
	my $self = shift;
	my $value = shift;

	if ( defined $value ) {
		$self->removeChild($_) for ($self->childNodes);
		if (ref($value) && $value->isa('XML::LibXML::Node')) {
			#throw OpenSRF::EX::NotADomainObject
			#	unless ($value->nodeName =~ /^oils:domainObject/o);
			$self->appendChild($value);
		} elsif (defined $value) {
			$self->appendText( ''.$value );
		}

		return $value
	} else {
		$value = $self->firstChild;
		if ($value) {
			if ($value->nodeType == 3) {
				return $value->textContent;
			} else {
				return $value;
			}
		}
		return undef;
	}
}

sub FETCH { $_[0]->value }
sub STORE { $_[0]->value($_[1]) }

package OpenSRF::DomainObject::oilsPair;
use base 'OpenSRF::DomainObject::oilsScalar';

=head1 NAME

OpenSRF::DomainObject::oilsPair

=head1 SYNOPSIS

  use OpenSRF::DomainObject::oilsPair;

  my $pair = OpenSRF::DomainObject::oilsPair->new( 'key_for_pair' => 'a string or number' );

  $pair->key( 'replacement key' );
  $pair->value( 'replacement value' );

  print "$pair"; # stringify 'value'

   ...

  $pair->value( 1 );

  if( $pair ) { # boolify

   ...

  $pair->value( rand() * 1000 );

  print 10 + $pair; # numify 'value'

=head1 ABSTRACT

This class impliments a "named pair" object.  This is the basis for
hash-type domain objects.

=head1 METHODS

=head2 OpenSRF::DomainObject::oilsPair->value( [$new_value] )

=over 4

Sets or gets the value of the pair.  As above, this can be specified
as a build attribute as well as added to a prebuilt oilsPair object.

=back

=head2 OpenSRF::DomainObject::oilsPair->key( [$new_key] )

=over 4

Sets or gets the key of the pair.  As above, this can be specified
as a build attribute as well as added to a prebuilt oilsPair object.
This must be a perlish scalar; any string or number that is valid as the 
attribute on an XML node will work.

=back

=cut

use overload '""'   => sub { return ''.$_[0]->value };
use overload '0+'   => sub { return int($_[0]->value) };
use overload 'bool' => sub { return 1 if ($_[0]->value); return 0 };

sub new {
	my $class = shift;
	my ($key, $value) = @_;

	my $self = $class->SUPER::new($value);
	$self->setAttribute( key => $key);

	return $self;
}

sub key {
	my $self = shift;
	my $key = shift;

	$self->setAttribute( key => $key) if ($key);
	return $self->getAttribute( 'key' );
}

package OpenSRF::DomainObjectCollection::oilsArray;
use base qw/OpenSRF::DomainObjectCollection Tie::Array/;
use OpenSRF::DomainObjectCollection;

=head1 NAME

OpenSRF::DomainObjectCollection::oilsArray

=head1 SYNOPSIS

  use OpenSRF::DomainObject::oilsPrimitive;

  my $collection = OpenSRF::DomainObjectCollection::oilsArray->new( $domain_object, $another_domain_object, ...);

  $collection->push( 'appended value' );
  $collection->unshift( 'prepended vaule' );
  my $first = $collection->shift;
  my $last = $collection->pop;

   ...

  my @values = $collection->list;

    Or, using the TIE interface:

  my @array;
  my $real_object = tie(@array, 'OpenSRF::DomainObjectCollection::oilsArray', $domain, $objects, 'to', $store);

      or to tie an existing $collection object

  my @array;
  tie(@array, 'OpenSRF::DomainObjectCollection::oilsArray', $collection);

      or even....

  my @array;
  tie(@array, ref($collection), $collection);


  $array[2] = $DomainObject; # replaces 'to' (which is now an OpenSRF::DomainObject::oilsScalar) above
  delete( $array[3] ); # removes '$store' above.
  my $size = scalar( @array );

  print $real_object->toString;

=head1 ABSTRACT

This package impliments array-like domain objects.  A full tie interface
is also provided.  If elements are passed in as strings (or numbers) they
are turned into oilsScalar objects.  Any simple scalar or Domain Object may
be stored in the array.

=head1 METHODS

=head2 OpenSRF::DomainObjectCollection::oilsArray->list()

=over 4

Returns the array of 'OpenSRF::DomainObject's that this collection contains.

=back

=cut

sub tie_me {
	my $class = shift;
	$class = ref($class) || $class;
	my $node = shift;
	my @array;
	tie @array, $class, $node;
	return \@array;
}

# an existing DomainObjectCollection::oilsArray can now be tied
sub TIEARRAY {
	return CORE::shift()->new(@_);
}

sub new {
	my $class = CORE::shift;
	$class = ref($class) || $class;

	my $first = CORE::shift;

	return $first
		if (	defined $first and
			ref $first and $first->can('base_type') and
			UNIVERSAL::isa($first->class, __PACKAGE__) and
			!scalar(@_)
		);

	my $self = $class->SUPER::new;

	my @args = @_;
	if (ref($first) and ref($first) eq 'ARRAY') {
		push @args, @$first;
		tie( @$first, ref($self->upcast), $self);
	} else {
		unshift @args, $first if (defined $first);
	}

	$self->STORE($self->FETCHSIZE, $_) for (@args);
	return $self;
}

sub STORE {
	my $self = CORE::shift;
	my ($index, $value) = @_;

	$value = OpenSRF::DomainObject::oilsScalar->new($value)
		unless ( ref $value and $value->nodeName =~ /^oils:domainObject/o );

	$self->_expand($index) unless ($self->EXISTS($index));

	($self->childNodes)[$index]->replaceNode( $value );

	return $value->upcast;
}

sub push {
	my $self = CORE::shift;
	my @values = @_;
	$self->STORE($self->FETCHSIZE, $_) for (@values);
}

sub pop {
	my $self = CORE::shift;
	my $node = $self->SUPER::pop;
	if ($node) {
		if ($node->base_type eq 'oilsScalar') {
			return $node->value;
		}
		return $node->upcast;
	}
}

sub unshift {
	my $self = CORE::shift;
	my @values = @_;
	$self->insertBefore($self->firstChild, $_ ) for (reverse @values);
}

sub shift {
	my $self = CORE::shift;
	my $node = $self->SUPER::shift;
	if ($node) {
		if ($node->base_type eq 'oilsScalar') {
			return $node->value;
		}
		return $node->upcast;
	}
}

sub FETCH {
	my $self = CORE::shift;
	my $index = CORE::shift;
	my $node =  ($self->childNodes)[$index]->upcast;
	if ($node) {
		if ($node->base_type eq 'oilsScalar') {
			return $node->value;
		}
		return $node->upcast;
	}
}

sub size {
	my $self = CORE::shift;
	scalar($self->FETCHSIZE)
}

sub FETCHSIZE {
	my $self = CORE::shift;
	my @a = $self->childNodes;
	return scalar(@a);
}

sub _expand {
	my $self = CORE::shift;
	my $count = CORE::shift;
	my $size = $self->FETCHSIZE;
	for ($size..$count) {
		$self->SUPER::push( new OpenSRF::DomainObject::oilsScalar );
	}
}

sub STORESIZE {
	my $self = CORE::shift;
	my $count = CORE::shift;
	my $size = $self->FETCHSIZE - 1;

	if (defined $count and $count != $size) {
		if ($size < $count) {
			$self->_expand($count);
			$size = $self->FETCHSIZE - 1;
		} else {
			while ($size > $count) {
				$self->SUPER::pop;
				$size = $self->FETCHSIZE - 1;
			}
		}
	}

	return $size
}

sub EXISTS {
	my $self = CORE::shift;
	my $index = CORE::shift;
	return $self->FETCHSIZE > abs($index) ? 1 : 0;
}

sub CLEAR {
	my $self = CORE::shift;
	$self->STORESIZE(0);
	return $self;
}

sub DELETE {
	my $self = CORE::shift;
	my $index = CORE::shift;
	return $self->removeChild( ($self->childNodes)[$index] );
}

package OpenSRF::DomainObjectCollection::oilsHash;
use base qw/OpenSRF::DomainObjectCollection Tie::Hash/;

=head1 NAME

OpenSRF::DomainObjectCollection::oilsHash

=head1 SYNOPSIS

  use OpenSRF::DomainObject::oilsPrimitive;

  my $collection = OpenSRF::DomainObjectCollection::oilsHash->new( key1 => $domain_object, key2 => $another_domain_object, ...);

  $collection->set( key =>'value' );
  my $value = $collection->find( $key );
  my $dead_value = $collection->remove( $key );
  my @keys = $collection->keys;
  my @values = $collection->values;

    Or, using the TIE interface:

  my %hash;
  my $real_object = tie(%hash, 'OpenSRF::DomainObjectCollection::oilsHash', domain => $objects, to => $store);

      or to tie an existing $collection object

  my %hash;
  tie(%hash, 'OpenSRF::DomainObjectCollection::oilsHash', $collection);

      or even....

  my %hash;
  tie(%hash, ref($collection), $collection);

      or perhaps ...

  my $content = $session->recv->content; # eh? EH?!?!
  tie(my %hash, ref($content), $content);

  $hash{domain} = $DomainObject; # replaces value for key 'domain' above
  delete( $hash{to} ); # removes 'to => $store' above.
  for my $key ( keys %hash ) {
    ... do stuff ...
  }

  print $real_object->toString;

=head1 ABSTRACT

This package impliments hash-like domain objects.  A full tie interface
is also provided.  If elements are passed in as strings (or numbers) they
are turned into oilsScalar objects.  Any simple scalar or Domain Object may
be stored in the hash.

=back

=cut

sub tie_me {
	my $class = shift;
	$class = ref($class) || $class;
	my $node = shift;
	my %hash;
	tie %hash, $class, $node;
	return %hash;
}


sub keys {
	my $self = shift;
	return map { $_->key } $self->childNodes;
}

sub values {
	my $self = shift;
	return map { $_->value } $self->childNodes;
}

# an existing DomainObjectCollection::oilsHash can now be tied
sub TIEHASH {
	return shift()->new(@_);
}

sub new {
	my $class = shift;
	$class = ref($class) || $class;
	my $first = shift;
	
	return $first
		if (	defined $first and
			ref $first and $first->can('base_type') and
			UNIVERSAL::isa($first->class, __PACKAGE__) and
			!scalar(@_)
		);
	
	my $self = $class->SUPER::new;

	my @args = @_;
	if (ref($first) and ref($first) eq 'HASH') {
		push @args, %$first;
		tie( %$first, ref($self->upcast), $self);
	} else {
		unshift @args, $first if (defined $first);
	}

	my %arg_hash = @args;
	while ( my ($key, $value) = each(%arg_hash) ) {
		$self->STORE($key => $value);
	}
	return $self;
}

sub STORE {
	shift()->set(@_);
}

sub set {
	my $self = shift;
	my ($key, $value) = @_;

	my $node = $self->find_node($key);

	return $node->value( $value ) if (defined $node);
	return $self->appendChild( OpenSRF::DomainObject::oilsPair->new($key => $value) );
}

sub _accessor {
	my $self = shift;
	my $key = shift;
	my $node = find_node($self, $key);
	return $node->value if ($node);
}       

sub find_node {
	my $self = shift;
	my $key = shift;
	return ($self->findnodes("oils:domainObject[\@name=\"oilsPair\" and \@key=\"$key\"]", $self))[0];
}

sub find {
	my $self = shift;
	my $key = shift;
	my $node = $self->find_node($key);
	my $value = $node->value if (defined $node);
	return $value;
}

sub size {
	my $self = CORE::shift;
	my @a = $self->childNodes;
	return scalar(@a);
}

sub FETCH {
	my $self = shift;
	my $key = shift;
	return $self->find($key);
}

sub EXISTS {
	my $self = shift;
	my $key = shift;
	return $self->find_node($key);
}

sub CLEAR {
	my $self = shift;
	$self->removeChild for ($self->childNodes);
	return $self;
}

sub DELETE {
	shift()->remove(@_);
}

sub remove {
	my $self = shift;
	my $key = shift;
	return $self->removeChild( $self->find_node($key) );
}

sub FIRSTKEY {
	my $self = shift;
	return $self->firstChild->key;
}

sub NEXTKEY {
	my $self = shift;
	my $key = shift;
	my ($prev_node) = $self->find_node($key);
	my $last_node = $self->lastChild;

	if ($last_node and $last_node->key eq $prev_node->key) {
		return undef;
	} else {
		return $prev_node->nextSibling->key;
	}
}

package OpenSRF::DomainObject::oilsHash;
use base qw/OpenSRF::DomainObjectCollection::oilsHash/;

package OpenSRF::DomainObject::oilsArray;
use base qw/OpenSRF::DomainObjectCollection::oilsArray/;

1;
