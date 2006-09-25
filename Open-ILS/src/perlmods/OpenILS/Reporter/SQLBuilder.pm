#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder;

sub new {
	my $class = shift;
	$class = ref($class) || $class;

	return bless { _sql => undef } => $class;
}

sub register_params {
	my $self  = shift;
	my $p = shift;
	$self->{_params} = $p;
}

sub get_param {
	my $self = shift;
	my $p = shift;
	return $self->{_builder}->{_params}->{$p};
}

sub set_builder {
	my $self = shift;
	$self->{_builder} = shift;
	return $self;
}

sub resolve_param {
	my $self = shift;
	my $val = shift;

	if ($val =~ /^::(.+)$/o) {
		$val = $self->get_param($1);
	}

	$val =~ s/\\/\\\\/go;
	$val =~ s/"/\\"/go;
	return $val;
}

sub parse_report {
	my $self = shift;
	my $report = shift;

	$self->set_select( $report->{select} );
	$self->set_from( $report->{from} );
	$self->set_where( $report->{where} );
	$self->set_having( $report->{having} );
	$self->set_order_by( $report->{order_by} );

	return $self;
}

sub set_select {
	my $self = shift;
	my @cols = @_;

	$self->{_select} = [];

	return $self unless (@cols && defined($cols[0]));
	@cols = @{ $cols[0] } if (@cols == 1 && ref($cols[0]) eq 'ARRAY');

	push @{ $self->{_select} }, map { OpenILS::Reporter::SQLBuilder::Column::Select->new( $_ )->set_builder( $self ) } @cols;

	return $self;
}

sub set_from {
	my $self = shift;
	my $f = shift;

	$self->{_from} = OpenILS::Reporter::SQLBuilder::Relation->parse( $f );

	return $self;
}

sub set_where {
	my $self = shift;
	my @cols = @_;

	$self->{_where} = [];

	return $self unless (@cols && defined($cols[0]));
	@cols = @{ $cols[0] } if (@cols == 1 && ref($cols[0]) eq 'ARRAY');

	push @{ $self->{_where} }, map { OpenILS::Reporter::SQLBuilder::Column::Where->new( $_ )->set_builder( $self ) } @cols;

	return $self;
}

sub set_having {
	my $self = shift;
	my @cols = @_;

	$self->{_having} = [];

	return $self unless (@cols && defined($cols[0]));
	@cols = @{ $cols[0] } if (@cols == 1 && ref($cols[0]) eq 'ARRAY');

	push @{ $self->{_having} }, map { OpenILS::Reporter::SQLBuilder::Column::Having->new( $_ )->set_builder( $self ) } @cols;

	return $self;
}

sub set_order_by {
	my $self = shift;
	my @cols = @_;

	$self->{_order_by} = [];

	return $self unless (@cols && defined($cols[0]));
	@cols = @{ $cols[0] } if (@cols == 1 && ref($cols[0]) eq 'ARRAY');

	push @{ $self->{_order_by} }, map { OpenILS::Reporter::SQLBuilder::Column::OrderBy->new( $_ )->set_builder( $self ) } @cols;

	return $self;
}

sub toSQL {
	my $self = shift;

	my $sql = "SELECT\t" . join(",\n\t", map { $_->toSQL } @{ $self->{_select} }) . "\n" if (@{ $self->{_select} });

	$sql .= "  FROM\t" . $self->{_from}->toSQL . "\n" if ($self->{_from});

	$sql .= "  WHERE\t" . join("\n\tAND ", map { $_->toSQL } @{ $self->{_where} }) . "\n" if (@{ $self->{_where} });

	my $gcount = 1;
	my @group_by;
	for my $c ( @{ $self->{_select} } ) {
		push @group_by, $gcount if (!$c->is_aggregate);
		$gcount++;
	}

	$sql .= '  GROUP BY ' . join(', ', @group_by) . "\n" if (@group_by);
	$sql .= "  HAVING " . join("\n\tAND ", map { $_->toSQL } @{ $self->{_having} }) . "\n" if (@{ $self->{_having} });
	$sql .= '  ORDER BY ' . join(', ', map { $_->toSQL } @{ $self->{_order_by} }) . "\n" if (@{ $self->{_order_by} });

	return $sql;
}


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column;
use base qw/OpenILS::Reporter::SQLBuilder/;

sub new {
	my $class = shift;
	my $self = $class->SUPER::new;

	my $col_data = shift;
	$self->{_relation} = $col_data->{relation};
	$self->{_column} = $col_data->{column};

	$self->{_aggregate} = $col_data->{aggregate};

	if (ref($self->{_column})) {
		my ($trans) = keys %{ $self->{_column} };
		my $pkg = "OpenILS::Reporter::SQLBuilder::Column::Transform::$trans";
		if (UNIVERSAL::can($pkg => 'toSQL')) {
			$self->{_transform} = $trans;
		} else {
			$self->{_transform} = 'GenericTransform';
		}
	} else {
		$self->{_transform} = 'Bare';
	}


	return $self;
}

sub name {
	my $self = shift;
	if (ref($self->{_column})) {
		my ($k) = keys %{$self->{_column}};
		if (ref($self->{_column}->{$k})) {
		 	return $self->resolve_param( $self->{_column}->{$k}->[0] );
		} else {
			return $self->resolve_param( $self->{_column}->{$k} );
		}
	} else {
		return $self->resolve_param( $self->{_column} );
	}
}

sub toSQL {
	my $self = shift;
	my $type = $self->{_transform};
	my $toSQL = "OpenILS::Reporter::SQLBuilder::Column::Transform::${type}::toSQL";
	return $self->$toSQL;
}

sub is_aggregate {
	my $self = shift;
	my $type = $self->{_transform};
	my $is_agg = "OpenILS::Reporter::SQLBuilder::Column::Transform::${type}::is_aggregate";
	return $self->$is_agg;
}


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::OrderBy;
use base qw/OpenILS::Reporter::SQLBuilder::Column/;

sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);

	my $col_data = shift;
	$self->{_direction} = $col_data->{direction} || 'ascending';
	return $self;
}

sub toSQL {
	my $self = shift;
	my $dir = ($self->{_direction} =~ /^d/oi) ? 'DESC' : 'ASC';
	return $self->SUPER::toSQL .  " $dir";
}


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Select;
use base qw/OpenILS::Reporter::SQLBuilder::Column/;

sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);

	my $col_data = shift;
	$self->{_alias} = $col_data->{alias};
	return $self;
}

sub toSQL {
	my $self = shift;
	return $self->SUPER::toSQL .  ' AS "' . $self->resolve_param( $self->{_alias} ) . '"';
}


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::GenericTransform;

sub toSQL {
	my $self = shift;
	my $name = $self->name;
	my ($func) = keys %{ $self->{_column} };

	my @params;
	@params = @{ $self->{_column}->{$func} } if (ref($self->{_column}->{$func}));
	shift @params if (@params);

	my $sql = $func . '("' . $self->{_relation} . '"."' . $self->name . '"';
	$sql .= ",'" . join("','", @params) . "'" if (@params);
	$sql .= ')';

	return $sql;
}

sub is_aggregate { return $self->{_aggregate} }

#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::Bare;

sub toSQL {
	my $self = shift;
	return '"' . $self->{_relation} . '"."' . $self->name . '"';
}

sub is_aggregate { return 0 }

#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::substring;

sub toSQL {
	my $self = shift;
	my ($params) = values %{ $self->{_column} };
	my $start = $$params[1];
	my $len = $$params[2];
	return 'SUBSTRING("' . $self->{_relation} . '"."' . $self->name . "\",$start,$len)";
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::day_name;

sub toSQL {
	my $self = shift;
	return 'TO_CHAR("' . $self->{_relation} . '"."' . $self->name . '", \'Day\')';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::month_name;

sub toSQL {
	my $self = shift;
	return 'TO_CHAR("' . $self->{_relation} . '"."' . $self->name . '", \'Month\')';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::doy;

sub toSQL {
	my $self = shift;
	return 'EXTRACT(DOY FROM "' . $self->{_relation} . '"."' . $self->name . '")';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::woy;

sub toSQL {
	my $self = shift;
	return 'EXTRACT(WEEK FROM "' . $self->{_relation} . '"."' . $self->name . '")';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::moy;

sub toSQL {
	my $self = shift;
	return 'EXTRACT(MONTH FROM "' . $self->{_relation} . '"."' . $self->name . '")';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::qoy;

sub toSQL {
	my $self = shift;
	return 'EXTRACT(QUARTER FROM "' . $self->{_relation} . '"."' . $self->name . '")';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::dom;

sub toSQL {
	my $self = shift;
	return 'EXTRACT(DAY FROM "' . $self->{_relation} . '"."' . $self->name . '")';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::dow;

sub toSQL {
	my $self = shift;
	return 'EXTRACT(DOW FROM "' . $self->{_relation} . '"."' . $self->name . '")';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::year_trunc;

sub toSQL {
	my $self = shift;
	return 'EXTRACT(YEAR FROM "' . $self->{_relation} . '"."' . $self->name . '")';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::month_trunc;

sub toSQL {
	my $self = shift;
	return 'EXTRACT(YEAR FROM "' . $self->{_relation} . '"."' . $self->name . '")' .
		' || \'-\' || LPAD(EXTRACT(MONTH FROM "' . $self->{_relation} . '"."' . $self->name . '"),2,\'0\')';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::quarter;

sub toSQL {
	my $self = shift;
	return 'EXTRACT(YEAR FROM "' . $self->{_relation} . '"."' . $self->name . '")' .
		' || \'-Q\' || EXTRACT(QUARTER FROM "' . $self->{_relation} . '"."' . $self->name . '")';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::months_ago;

sub toSQL {
	my $self = shift;
	return 'EXTRACT(MONTH FROM AGE(NOW(),"' . $self->{_relation} . '"."' . $self->name . '"))';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::quarters_ago;

sub toSQL {
	my $self = shift;
	return 'EXTRACT(QUARTER FROM AGE(NOW(),"' . $self->{_relation} . '"."' . $self->name . '"))';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::age;

sub toSQL {
	my $self = shift;
	return 'AGE(NOW(),"' . $self->{_relation} . '"."' . $self->name . '")';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::min;

sub toSQL {
	my $self = shift;
	return 'MIN("' . $self->{_relation} . '"."' . $self->name . '")';
}

sub is_aggregate { return 1 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::max;

sub toSQL {
	my $self = shift;
	return 'MAX("' . $self->{_relation} . '"."' . $self->name . '")';
}

sub is_aggregate { return 1 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::count;

sub toSQL {
	my $self = shift;
	return 'COUNT("' . $self->{_relation} . '"."' . $self->name . '")';
}

sub is_aggregate { return 1 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::count_distinct;

sub toSQL {
	my $self = shift;
	return 'COUNT(DISTINCT "' . $self->{_relation} . '"."' . $self->name . '")';
}

sub is_aggregate { return 1 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::sum;

sub toSQL {
	my $self = shift;
	return 'SUM("' . $self->{_relation} . '"."' . $self->name . '")';
}

sub is_aggregate { return 1 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::average;

sub toSQL {
	my $self = shift;
	return 'AVG("' . $self->{_relation} . '"."' . $self->name .  '")';
}

sub is_aggregate { return 1 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Having;
use base qw/OpenILS::Reporter::SQLBuilder::Column/;

sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);

	my $col_data = shift;
	$self->{_condition} = $col_data->{condition};

	return $self;
}

sub toSQL {
	my $self = shift;

	my $sql = $self->SUPER::toSQL;

	my ($op) = keys %{ $self->{_condition} };
	my $val = $self->resolve_param( values %{ $self->{_condition} } );

	$val =~ s/'/\\'/go; $val =~ s/\\/\\\\/go;
	$sql .= " $op '$val'";

	return $sql;
}


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Where;
use base qw/OpenILS::Reporter::SQLBuilder::Column/;

sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);

	my $col_data = shift;
	$self->{_condition} = $col_data->{condition};

	return $self;
}

sub toSQL {
	my $self = shift;

	my $sql = $self->SUPER::toSQL;

	my ($op) = keys %{ $self->{_condition} };
	my $val = $self->resolve_param( values %{ $self->{_condition} } );

	if (lc($op) eq 'in') {
		$val = [$val] unless (ref($val));
		$sql .= " IN ('". join("','", map { $_ =~ s/'/\\'/go; $_ =~ s/\\/\\\\/go; $_ } @$val)."')";
	} elsif (lc($op) eq 'not in') {
		$val = [$val] unless (ref($val));
		$sql .= " NOT IN ('". join("','", map { $_ =~ s/'/\\'/go; $_ =~ s/\\/\\\\/go; $_ } @$val)."')";
	} elsif (lc($op) eq 'between') {
		$val = [$val] unless (ref($val));
		$sql .= " BETWEEN '". join("' AND '", map { $_ =~ s/'/\\'/go; $_ =~ s/\\/\\\\/go; $_ } @$val)."'";
	} elsif (lc($op) eq 'not between') {
		$val = [$val] unless (ref($val));
		$sql .= " NOT BETWEEN '". join("' AND '", map { $_ =~ s/'/\\'/go; $_ =~ s/\\/\\\\/go; $_ } @$val)."'";
	} else {
		$val =~ s/'/\\'/go; $val =~ s/\\/\\\\/go;
		$sql .= " $op '$val'";
	}

	return $sql;
}


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Relation;
use base qw/OpenILS::Reporter::SQLBuilder/;

sub parse {
	my $self = shift;
	$self = $self->SUPER::new if (!ref($self));

	my $rel_data = shift;

	$self->{_table} = $rel_data->{table};
	$self->{_alias} = $rel_data->{alias};
	$self->{_join} = [];
	$self->{_columns} = [];

	if ($rel_data->{join}) {
		$self->add_join(
			$_ => OpenILS::Reporter::SQLBuilder::Relation->parse( $rel_data->{join}->{$_} ) => $rel_data->{join}->{$_}->{key}
		) for ( keys %{ $rel_data->{join} } );
	}

	return $self;
}

sub add_column {
	my $self = shift;
	my $col = shift;
	
	push @{ $self->{_columns} }, $col;
}

sub find_column {
	my $self = shift;
	my $col = shift;
	return (grep { $_->name eq $col} @{ $self->{_columns} })[0];
}

sub add_join {
	my $self = shift;
	my $col = shift;
	my $frel = shift;
	my $fkey = shift;

	if (ref($col) eq 'OpenILS::Reporter::SQLBuilder::Join') {
		push @{ $self->{_join} }, $col;
	} else {
		push @{ $self->{_join} }, OpenILS::Reporter::SQLBuilder::Join->build( $self => $col, $frel => $fkey );
	}

	return $self;
}

sub is_join {
	my $self = shift;
	my $j = shift;
	$self->{_is_join} = $j if ($j);
	return $self->{_is_join};
}

sub toSQL {
	my $self = shift;
	my $sql = $self->{_table} .' AS "'. $self->{_alias} .'"';

	if (!$self->is_join) {
		for my $j ( @{ $self->{_join} } ) {
			$sql .= $j->toSQL;
		}
	}

	return $sql;
}

#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Join;
use base qw/OpenILS::Reporter::SQLBuilder/;

sub build {
	my $self = shift;
	$self = $self->SUPER::new if (!ref($self));

	$self->{_left_rel} = shift;
	$self->{_left_col} = shift;

	$self->{_right_rel} = shift;
	$self->{_right_col} = shift;

	$self->{_right_rel}->is_join(1);

	return $self;
}

sub toSQL {
	my $self = shift;
	my $sql = "\n\tJOIN " . $self->{_right_rel}->toSQL .
		' ON ("' . $self->{_left_rel}->{_alias} . '"."' . $self->{_left_col} .
		'" = "' . $self->{_right_rel}->{_alias} . '"."' . $self->{_right_col} . '")';

	$sql .= $_->toSQL for (@{ $self->{_right_rel}->{_join} });

	return $sql;
}

1;
