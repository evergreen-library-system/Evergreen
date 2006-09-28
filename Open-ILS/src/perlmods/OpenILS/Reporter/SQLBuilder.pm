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

sub builder {
	my $self = shift;
	return $self->{_builder};
}

sub resolve_param {
	my $self = shift;
	my $val = shift;

	if ($val =~ /^::(.+)$/o) {
		$val = $self->get_param($1);
	}

	$val =~ s/\\/\\\\/go if (!ref($val));
	$val =~ s/"/\\"/go if (!ref($val));
	return $val;
}

sub parse_report {
	my $self = shift;
	my $report = shift;

	my $rs = OpenILS::Reporter::SQLBuilder::ResultSet->new;

	$rs->is_subquery( 1 ) if ( $report->{alias} );

	$rs	->set_builder( $self )
		->set_subquery_alias( $report->{alias} )
		->set_select( $report->{select} )
		->set_from( $report->{from} )
		->set_where( $report->{where} )
		->set_having( $report->{having} )
		->set_order_by( $report->{order_by} );

	return $rs;
}


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::ResultSet;
use base qw/OpenILS::Reporter::SQLBuilder/;

sub is_subquery {
	my $self = shift;
	my $flag = shift;
	$self->{_is_subquery} = $flag if (defined $flag);
	return $self->{_is_subquery};
}

sub set_subquery_alias {
	my $self = shift;
	my $alias = shift;
	$self->{_alias} = $alias if (defined $alias);
	return $self;
}

sub set_select {
	my $self = shift;
	my @cols = @_;

	$self->{_select} = [];

	return $self unless (@cols && defined($cols[0]));
	@cols = @{ $cols[0] } if (@cols == 1 && ref($cols[0]) eq 'ARRAY');

	push @{ $self->{_select} }, map { OpenILS::Reporter::SQLBuilder::Column::Select->new( $_ )->set_builder( $self->builder ) } @cols;

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

	push @{ $self->{_where} }, map { OpenILS::Reporter::SQLBuilder::Column::Where->new( $_ )->set_builder( $self->builder ) } @cols;

	return $self;
}

sub set_having {
	my $self = shift;
	my @cols = @_;

	$self->{_having} = [];

	return $self unless (@cols && defined($cols[0]));
	@cols = @{ $cols[0] } if (@cols == 1 && ref($cols[0]) eq 'ARRAY');

	push @{ $self->{_having} }, map { OpenILS::Reporter::SQLBuilder::Column::Having->new( $_ )->set_builder( $self->builder ) } @cols;

	return $self;
}

sub set_order_by {
	my $self = shift;
	my @cols = @_;

	$self->{_order_by} = [];

	return $self unless (@cols && defined($cols[0]));
	@cols = @{ $cols[0] } if (@cols == 1 && ref($cols[0]) eq 'ARRAY');

	push @{ $self->{_order_by} }, map { OpenILS::Reporter::SQLBuilder::Column::OrderBy->new( $_ )->set_builder( $self->builder ) } @cols;

	return $self;
}

sub toSQL {
	my $self = shift;

	return $self->{_sql} if ($self->{_sql});

	my $sql = '';

	if ($self->is_subquery) {
		$sql = '(';
	}

	$sql .= "SELECT\t" . join(",\n\t", map { $_->toSQL } @{ $self->{_select} }) . "\n" if (@{ $self->{_select} });
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

	if ($self->is_subquery) {
		$sql .= ') '. $self->{_alias} . "\n";
	}

	return $self->{_sql} = $sql;
}


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Input;
use base qw/OpenILS::Reporter::SQLBuilder/;

sub new {
	my $class = shift;
	my $self = $class->SUPER::new;

	my $col_data = shift;

	if (ref($col_data)) {
		$self->{params} = $col_data->{params};
		my $trans = $col_data->{transform} || 'Bare';
		my $pkg = "OpenILS::Reporter::SQLBuilder::Input::Transform::$trans";
		if (UNIVERSAL::can($pkg => 'toSQL')) {
			$self->{_transform} = $trans;
		} else {
			$self->{_transform} = 'GenericTransform';
		}
	} else {
		$self->{_transform} = 'Bare';
		$self->{params} = $col_data;
	}


	return $self;
}

sub toSQL {
	my $self = shift;
	my $type = $self->{_transform};
	return $self->{_sql} if ($self->{_sql});
	my $toSQL = "OpenILS::Reporter::SQLBuilder::Input::Transform::${type}::toSQL";
	return $self->{_sql} = $self->$toSQL;
}


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Input::Transform::Bare;

sub toSQL {
	my $self = shift;

	my $val = $self->{params};
	$val = $$val[0] if (ref($val));
	
	$val =~ s/\\/\\\\/go;
	$val =~ s/'/\\'/go;

	return "'$val'";
}


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Input::Transform::relative_year;

sub toSQL {
	my $self = shift;

	my $val = $self->{params};
	$val = $$val[0] if (ref($val));

	$val =~ s/\\/\\\\/go;
	$val =~ s/'/\\'/go;

	return "EXTRACT(YEAR FROM NOW() + '$val years')";
}


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Input::Transform::relative_month;

sub toSQL {
	my $self = shift;

	my $val = $self->{params};
	$val = $$val[0] if (ref($val));

	$val =~ s/\\/\\\\/go;
	$val =~ s/'/\\'/go;

	return "EXTRACT(YEAR FROM NOW() + '$val months')" .
		" || '-' || LPAD(EXTRACT(MONTH FROM NOW() + '$val months'),2,'0')";
}


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Input::Transform::relative_date;

sub toSQL {
	my $self = shift;

	my $val = $self->{params};
	$val = $$val[0] if (ref($val));

	$val =~ s/\\/\\\\/go;
	$val =~ s/'/\\'/go;

	return "DATE(NOW() + '$val days')";
}


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Input::Transform::relative_week;

sub toSQL {
	my $self = shift;

	my $val = $self->{params};
	$val = $$val[0] if (ref($val));

	$val =~ s/\\/\\\\/go;
	$val =~ s/'/\\'/go;

	return "EXTRACT(WEEK FROM NOW() + '$val weeks')";
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
		my $trans = $self->{_column}->{transform} || 'Bare';
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
		 return $self->{_column}->{colname};
	} else {
		return $self->{_column};
	}
}

sub toSQL {
	my $self = shift;
	my $type = $self->{_transform};
	return $self->{_sql} if ($self->{_sql});
	my $toSQL = "OpenILS::Reporter::SQLBuilder::Column::Transform::${type}::toSQL";
	return $self->{_sql} = $self->$toSQL;
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
	return $self->{_sql} if ($self->{_sql});
	return $self->{_sql} = $self->SUPER::toSQL .  " $dir";
}


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Select;
use base qw/OpenILS::Reporter::SQLBuilder::Column/;

sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);

	my $col_data = shift;
	$self->{_alias} = $col_data->{alias} || $self->name;
	return $self;
}

sub toSQL {
	my $self = shift;
	return $self->{_sql} if ($self->{_sql});
	return $self->{_sql} = $self->SUPER::toSQL .  ' AS "' . $self->resolve_param( $self->{_alias} ) . '"';
}


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::GenericTransform;

sub toSQL {
	my $self = shift;
	my $name = $self->name;
	my ($func) = keys %{ $self->{_column} };

	my @params;
	@params = @{ $self->resolve_param( $self->{_column}->{params} ) } if ($self->{_column}->{params});

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
	my $params = $self->resolve_param( $self->{_column}->{params} );
	my $start = $$params[0];
	my $len = $$params[1];
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
package OpenILS::Reporter::SQLBuilder::Column::Transform::first;

sub toSQL {
	my $self = shift;
	return 'FIRST("' . $self->{_relation} . '"."' . $self->name . '")';
}

sub is_aggregate { return 1 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::last;

sub toSQL {
	my $self = shift;
	return 'LAST("' . $self->{_relation} . '"."' . $self->name . '")';
}

sub is_aggregate { return 1 }


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
package OpenILS::Reporter::SQLBuilder::Column::Where;
use base qw/OpenILS::Reporter::SQLBuilder::Column/;

sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);

	my $col_data = shift;
	$self->{_condition} = $col_data->{condition};

	return $self;
}

sub _flesh_conditions {
	my $cond = shift;
	$cond = [$cond] unless (ref($cond) eq 'ARRAY');

	my @out;
	for my $c (@$cond) {
		push @out, OpenILS::Reporter::SQLBuilder::Input->new( $c );
	}

	return \@out;
}

sub toSQL {
	my $self = shift;

	return $self->{_sql} if ($self->{_sql});
	my $sql = $self->SUPER::toSQL;

	my ($op) = keys %{ $self->{_condition} };
	my $val = _flesh_conditions( $self->resolve_param( $self->{_condition}->{$op} ) );

	if (lc($op) eq 'in') {
		$sql .= " IN (". join(",", map { $_->toSQL } @$val).")";
	} elsif (lc($op) eq 'not in') {
		$sql .= " NOT IN (". join(",", map { $_->toSQL } @$val).")";
	} elsif (lc($op) eq 'between') {
		$sql .= " BETWEEN ". join(" AND ", map { $_->toSQL } @$val);
	} elsif (lc($op) eq 'not between') {
		$sql .= " NOT BETWEEN ". join(" AND ", map { $_->toSQL } @$val);
	} else {
		$val = $$val[0] if (ref($val) eq 'ARRAY');
		$sql .= " $op " . $val->toSQL;
	}

	return $self->{_sql} = $sql;
}


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Having;
use base qw/OpenILS::Reporter::SQLBuilder::Column::Where/;

#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Relation;
use base qw/OpenILS::Reporter::SQLBuilder/;

sub parse {
	my $self = shift;
	$self = $self->SUPER::new if (!ref($self));

	my $rel_data = shift;

	$self->{_table} = $rel_data->{table};
	$self->{_alias} = $rel_data->{alias} || $self->name;
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
	return $self->{_sql} if ($self->{_sql});

	my $sql = $self->{_table} .' AS "'. $self->{_alias} .'"';

	if (!$self->is_join) {
		for my $j ( @{ $self->{_join} } ) {
			$sql .= $j->toSQL;
		}
	}

	return $self->{_sql} = $sql;
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
	return $self->{_sql} if ($self->{_sql});

	my $sql = "\n\tJOIN " . $self->{_right_rel}->toSQL .
		' ON ("' . $self->{_left_rel}->{_alias} . '"."' . $self->{_left_col} .
		'" = "' . $self->{_right_rel}->{_alias} . '"."' . $self->{_right_col} . '")';

	$sql .= $_->toSQL for (@{ $self->{_right_rel}->{_join} });

	return $self->{_sql} = $sql;
}

1;
