package OpenILS::DomainObject::oilsSearch;
use OpenILS::DomainObject;
use OpenILS::DomainObject::oilsPrimitive;
use OpenILS::DOM::Element::searchCriteria;
use base 'OpenILS::DomainObject';

sub new {
	my $class = shift;
	$class = ref($class) || $class;

	unshift @_, 'table' if (@_ == 1);
	my %args = @_;

	my $self = $class->SUPER::new;
	
	for my $part ( keys %args ) {
		if ($part ne 'criteria') {
			$self->$part( $args{$part} );
			next;
		}
		$self->criteria( OpenILS::DOM::Element::searchCriteria->new( @{$args{$part}} ) );
	}
	return $self;
}

sub format {
	my $self = shift;
	return $self->_attr_get_set( format => shift );
}

sub table {
	my $self = shift;
	return $self->_attr_get_set( table => shift );
}

sub fields {
	my $self = shift;
	my $new_fields_ref = shift;

	my ($old_fields) = $self->getChildrenByTagName("oils:domainObjectCollection");
	
	if ($new_fields_ref) {
		my $do = OpenILS::DomainObjectCollection::oilsArray->new( @$new_fields_ref );
		if (defined $old_fields) {
			$old_fields->replaceNode($do);
		} else {
			$self->appendChild($do);
			return $do->list;
		}
	}

	return $old_fields->list if ($old_fields);
}

sub limit {
	my $self = shift;
	return $self->_attr_get_set( limit => shift );
}

sub offset {
	my $self = shift;
	return $self->_attr_get_set( offset => shift );
}

sub group_by {
	my $self = shift;
	return $self->_attr_get_set( group_by => shift );
}

sub criteria {
	my $self = shift;
	my $new_crit = shift;

	if (@_) {
		unshift @_, $new_crit;
		$new_crit = OpenILS::DOM::Element::searchCriteria->new(@_);
	}

	my ($old_crit) = $self->getChildrenByTagName("oils:searchCriteria");
	
	if (defined $new_crit) {
		if (defined $old_crit) {
			$old_crit->replaceNode($new_crit);
		} else {
			$self->appendChild($new_crit);
			return $new_crit;
		}
	}

	return $old_crit;
}

sub toSQL {
	my $self = shift;

	my $SQL  = 'SELECT    ' . join(',', $self->fields);
	   $SQL .= '  FROM    ' . $self->table;
	   $SQL .= '  WHERE   ' . $self->criteria->toSQL if ($self->criteria);
	   $SQL .= ' GROUP BY ' . $self->group_by if ($self->group_by);
	   $SQL .= '  LIMIT   ' . $self->limit if ($self->limit);
	   $SQL .= '  OFFSET  ' . $self->offset if ($self->offset);
	
	return $SQL;
}

1;
