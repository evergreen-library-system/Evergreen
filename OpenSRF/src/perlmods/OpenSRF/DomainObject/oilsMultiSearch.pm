package OpenSRF::DomainObjectCollection::oilsMultiSearch;
use OpenSRF::DomainObjectCollection;
use OpenSRF::DomainObject::oilsPrimitive;
use OpenSRF::DomainObject::oilsSearch;
use OpenSRF::DOM::Element::searchCriteria;
use OpenSRF::DOM::Element::searchCriterium;
use base 'OpenSRF::DomainObjectCollection::oilsHash';

sub new {
	my $class = shift;
	my %args = @_;

	$class = ref($class) || $class;

	my $self = $class->SUPER::new;

	tie my %hash, 'OpenSRF::DomainObjectCollection::oilsHash', $self;

	$self->set( bind_count	=> 1 );
	$self->set( searches	=> new OpenSRF::DomainObjectCollection::oilsHash );
	$self->set( relators	=> new OpenSRF::DomainObjectCollection::oilsArray );
	$self->set( fields	=> new OpenSRF::DomainObjectCollection::oilsArray );
	$self->set( group_by	=> new OpenSRF::DomainObjectCollection::oilsArray );
	$self->set( order_by	=> new OpenSRF::DomainObjectCollection::oilsArray );
	
	return $self;
}

sub add_subsearch {
	my $self = shift;
	my $alias = shift;
	my $search = shift;
	my $relator = shift;
	
	$search = OpenSRF::DomainObject::oilsSearch->new($search) if (ref($search) eq 'ARRAY');

	$self->searches->set( $alias => $search );
	
	if ($self->searches->size > 1) {
		throw OpenSRF::EX::InvalidArg ('You need to pass a relator searchCriterium')
			unless (defined $relator);
	}

	$relator = OpenSRF::DOM::Element::searchCriterium->new( @$relator )
		if (ref($relator) eq 'ARRAY');

	$self->relators->push( $relator ) if (defined $relator);

	return $self;
}

sub relators {
	return $_[0]->_accessor('relators');
}

sub searches {
	return $_[0]->_accessor('searches');
}

sub fields {
	my $self = shift;
	my @parts = @_;
	if (@parts) {
		$self->set( fields => OpenSRF::DomainObjectCollection::oilsArray->new(@_) );
	}
	return $self->_accessor('fields')->list;
}

sub format {
	$_[0]->set( format => $_[1] ) if (defined $_[1]);
	return $_[0]->_accessor('format');
}

sub limit {
	$_[0]->set( limit => $_[1] ) if (defined $_[1]);
	return $_[0]->_accessor('limit');
}

sub offset {
	$_[0]->set( offset => $_[1] ) if (defined $_[1]);
	return $_[0]->_accessor('offset');
}

sub chunk_key {
	$_[0]->set( chunk_key => $_[1] ) if (defined $_[1]);
	return $_[0]->_accessor('chunk_key');
}

sub order_by {
	my $self = shift;
	my @parts = @_;
	if (@parts) {
		$self->set( order_by => OpenSRF::DomainObjectCollection::oilsArray->new(@_) );
	}
	return $self->_accessor('order_by')->list;
}

sub group_by {
	my $self = shift;
	my @parts = @_;
	if (@parts) {
		$self->set( group_by => OpenSRF::DomainObjectCollection::oilsArray->new(@_) );
	}
	return $self->_accessor('group_by')->list;
}

sub SQL_select_list {
	my $self = shift;

	if (my $sql = $self->_accessor('sql_select_list')) {
		return $sql;
	}

	$self->set( sql_select_list => 'SELECT '.join(', ', $self->fields) ) if defined($self->fields);
	return $self->_accessor('sql_select_list');
}

sub SQL_group_by {
	my $self = shift;

	if (my $sql = $self->_accessor('sql_group_by')) {
		return $sql;
	}

	$self->set( sql_group_by => 'GROUP BY '.join(', ', $self->group_by) ) if defined($self->group_by);
	return $self->_accessor('sql_group_by');
}

sub SQL_order_by {
	my $self = shift;

	if (my $sql = $self->_accessor('sql_order_by')) {
		return $sql;
	}

	$self->set( sql_order_by => 'ORDER BY '.join(', ', $self->order_by) ) if defined($self->order_by);
	return $self->_accessor('sql_order_by');
}

sub SQL_offset {
	my $self = shift;

	if (my $sql = $self->_accessor('sql_offset')) {
		return $sql;
	}

	$self->set( sql_offset => 'OFFSET '.$self->offset ) if defined($self->offset);
	return $self->_accessor('sql_offset');
}

sub SQL_limit {
	my $self = shift;

	if (my $sql = $self->_accessor('sql_limit')) {
		return $sql;
	}

	$self->set( sql_limit => 'LIMIT '.$self->limit ) if defined($self->limit);
	return $self->_accessor('sql_limit');
}

sub toSQL {
	my $self = shift;

	my $SQL = $self->SQL_select_list.' FROM ';

	my @subselects;
	for my $search ( $self->searches->keys ) {
		push @subselects, '('.$self->searches->_accessor($search)->toSQL.') '.$search;
	}
	$SQL .= join(', ', @subselects).' WHERE ';

	my @relators;
	for my $rel ( $self->relators->list ) {
		push @relators, $rel->value->toSQL( no_quote => 1 );
	}
	$SQL .= join(' AND ', @relators).' ';
	$SQL .= join ' ', ($self->SQL_group_by, $self->SQL_order_by, $self->SQL_limit, $self->SQL_offset);

	return $SQL;
}

#this is just to allow DomainObject to "upcast" nicely
package OpenSRF::DomainObject::oilsMultiSearch;
use base OpenSRF::DomainObjectCollection::oilsMultiSearch;
1;
