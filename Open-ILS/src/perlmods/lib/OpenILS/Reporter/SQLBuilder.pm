#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder;
use Scalar::Util qw(blessed);
our $_minimum_repsec_version = 7;

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
    return $self->builder->{_params}->{$p};
}

sub set_builder {
    my $self = shift;
    $self->{_builder} = shift;
    return $self;
}

sub builder {
    my $self = shift;
    return $self->{_builder} || $self;
}

sub do_repsec {
    my $self = shift;
    if ($self->template_version and $self->template_version >= $self->minimum_repsec_version) {
        return 1;
    }
    return 0;
}

sub template_version {
    my $self = shift;
    return $self->builder->{_template_version};
}

sub minimum_repsec_version {
    my $self = shift;
    my $v = shift;
    $self->builder->{_minimum_repsec_version} = $v if (defined $v);
    return $self->builder->{_minimum_repsec_version} || $_minimum_repsec_version;
}

sub runner {
    my $self = shift;
    my $t = shift;
    $self->builder->{_runner} = $t if (defined $t);
    return $self->builder->{_runner};
}

sub relative_time {
    my $self = shift;
    my $t = shift;
    $self->builder->{_relative_time} = $t if (defined $t);
    return $self->builder->{_relative_time};
}

sub resultset_limit {
    my $self = shift;
    my $limit = shift;
    $self->builder->{_resultset_limit} = $limit if (defined $limit);
    return $self->builder->{_resultset_limit};
}

sub resolve_param {
    my $self = shift;
    my $val = shift;

    if (defined($val) && $val =~ /^::(.+)$/o) {
        $val = $self->get_param($1);
    }

    if (defined($val) && !ref($val)) {
        $val =~ s/\\/\\\\/go;
        $val =~ s/"/\\"/go;
    }

    return $val;
}

sub parse_report {
    my $self = shift;
    my $report = shift;

    my $rs = OpenILS::Reporter::SQLBuilder::ResultSet->new;

    if (!$report->{order_by} || @{$report->{order_by}} == 0) {
        $report->{order_by} = $report->{select};
    }

    $rs->is_subquery( 1 ) if ( $report->{alias} );

    $rs ->set_builder( $self )
        ->set_template_version( $report->{version} )
        ->set_subquery_alias( $report->{alias} )
        ->set_select( $report->{select} )
        ->set_from( $report->{from} )
        ->set_where( $report->{where} )
        ->set_having( $report->{having} )
        ->set_order_by( $report->{order_by} )
        ->set_do_rollup( $report->{do_rollup} )
        ->set_pivot_data( $report->{pivot_data} )
        ->set_pivot_label( $report->{pivot_label} )
        ->set_pivot_default( $report->{pivot_default} )
        ->set_bib_column_number( $report->{bib_column_number} )
        ->set_record_bucket( $report->{record_bucket} );

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

sub do_rollup {
    my $self = shift;
    return $self->builder->{_do_rollup};
}

sub pivot_data {
    my $self = shift;
    return $self->builder->{_pivot_data};
}

sub pivot_label {
    my $self = shift;
    return $self->builder->{_pivot_label};
}

sub pivot_default {
    my $self = shift;
    return $self->builder->{_pivot_default};
}

sub set_template_version {
    my $self = shift;
    my $v = shift;
    $self->builder->{_template_version} = $v || 0;
    return $self;
}

sub record_bucket {
    my $self = shift;
    return $self->builder->{_record_bucket};
}

sub set_record_bucket {
    my $self = shift;
    my $p = shift;
    $self->builder->{_record_bucket} = $p if (defined $p);
    return $self;
}

sub bib_column_number {
    my $self = shift;
    return $self->builder->{_bib_column_number};
}

sub set_bib_column_number {
    my $self = shift;
    my $p = shift;
    $self->builder->{_bib_column_number} = $p if (defined $p);
    return $self;
}

sub set_do_rollup {
    my $self = shift;
    my $p = shift;
    $self->builder->{_do_rollup} = $p if (defined $p);
    return $self;
}

sub set_pivot_default {
    my $self = shift;
    my $p = shift;
    $self->builder->{_pivot_default} = $p if (defined $p);
    return $self;
}

sub set_pivot_data {
    my $self = shift;
    my $p = shift;
    $self->builder->{_pivot_data} = $p if (defined $p);
    return $self;
}

sub set_pivot_label {
    my $self = shift;
    my $p = shift;
    $self->builder->{_pivot_label} = $p if (defined $p);
    return $self;
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

    $self->{_from} = OpenILS::Reporter::SQLBuilder::Relation->parse( $f, $self->builder );

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

sub column_label_list {
    my $self = shift;

    my @labels;
    push @labels, $self->resolve_param( $_->{_alias} ) for ( @{ $self->{_select} } );
    return @labels;
}

sub group_by_list {
    my $self = shift;
    my $base = shift;
    $base = 1 unless (defined $base);

    my $seen_label = 0;
    my $gcount = $base;
    my @group_by;
    for my $c ( @{ $self->{_select} } ) {
        if ($base == 0 && !$seen_label  && defined($self->pivot_label) && $gcount == $self->pivot_label - 1) {
            $seen_label++;
            next;
        }
        push @group_by, $gcount if (!$c->is_aggregate);
        $gcount++;
    }

    return @group_by;
}

sub toSQL {
    my $self = shift;

    return $self->{_sql} if ($self->{_sql});

    my $sql = '';

    if ($self->is_subquery) {
        $sql = '(';
    } elsif ($self->resultset_limit) {
        $sql = 'SELECT * FROM (';
    }

    $sql .= "SELECT\t" . join(",\n\t", map { $_->toSQL } @{ $self->{_select} }) . "\n" if (@{ $self->{_select} });
    $sql .= "  FROM\t" . $self->{_from}->toSQL . "\n" if ($self->{_from});
    $sql .= "  WHERE\t" . join("\n\tAND ", map { $_->toSQL } @{ $self->{_where} }) . "\n" if (@{ $self->{_where} } or $self->{_from}->{_where_addition});

    # if we precalculated a WHERE condition based on @repsec:restriction_function in the IDL, add that here
    if ($self->{_from}->{_where_addition}) {
        my $and = "AND " if (@{ $self->{_where} });
        $sql .= "  \t$and". $self->{_from}->{_where_addition} ."\n";
    }

    my @group_by = $self->group_by_list;

    # The GROUP BY clause is used to generate distinct rows even if there are no aggregates in the select list
    my $rollup_start = 'ROLLUP (';
    my $rollup_end = ')';

    $rollup_start = $rollup_end = ''
        if (!$self->do_rollup or scalar(@group_by) == scalar(@{$self->{_select}})); # No ROLLUP if there are no aggregates, or not requested

    $sql .= "  GROUP BY $rollup_start" . join(', ', @group_by) . "$rollup_end\n" if (@group_by);
    $sql .= "  HAVING " . join("\n\tAND ", map { $_->toSQL } @{ $self->{_having} }) . "\n" if (@{ $self->{_having} });
    $sql .= '  ORDER BY ' . join(', ', map { $_->toSQL } @{ $self->{_order_by} }) . "\n" if (@{ $self->{_order_by} });

    if ($self->is_subquery) {
        $sql .= ') '. $self->{_alias} . "\n";
    } elsif ($self->resultset_limit) {
        $sql .= ') limited_to_' . $self->resultset_limit .
                '_hits LIMIT ' . $self->resultset_limit . "\n";
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
    } elsif( defined($col_data) ) {
        $self->{_transform} = 'Bare';
        $self->{params} = $col_data;
    } else {
        $self->{_transform} = 'NULL';
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
package OpenILS::Reporter::SQLBuilder::Input::Transform::GenericTransform;

sub toSQL {
    my $self = shift;
    my $func = $self->{transform};

    my @params;
    @params = @{ $self->{params} } if ($self->{params});

    my $sql = $func . "(\$_$$\$";
    $sql .= join("\$_$$\$,\$_$$\$", @params) if (@params);
    $sql .= "\$_$$\$)";

    return $sql;
}


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Input::Transform::NULL;

sub toSQL {
    return "NULL";
}


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Input::Transform::Bare;

sub toSQL {
    my $self = shift;

    my $val = $self->{params};
    $val = $$val[0] if (ref($val));
    
    return "\$_$$\$$val\$_$$\$";
}


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Input::Transform::age;

sub toSQL {
    my $self = shift;

    my $val = $self->{params};
    $val = $$val[0] if (ref($val));

    return "AGE(NOW(),\$_$$\$$val\$_$$\$::TIMESTAMPTZ)";
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Input::Transform::relative_year;

sub toSQL {
    my $self = shift;

    my $rtime = $self->relative_time || 'now';
    my $val = $self->{params};
    $val = $$val[0] if (ref($val));

    return "EXTRACT(YEAR FROM \$_$$\$$rtime\$_$$\$::TIMESTAMPTZ + \$_$$\$$val years\$_$$\$)";
}


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Input::Transform::relative_month;

sub toSQL {
    my $self = shift;

    my $rtime = $self->relative_time || 'now';
    my $val = $self->{params};
    $val = $$val[0] if (ref($val));

    return "(EXTRACT(YEAR FROM \$_$$\$$rtime\$_$$\$::TIMESTAMPTZ + \$_$$\$$val months\$_$$\$)" .
        " || \$_$$\$-\$_$$\$ || LPAD(EXTRACT(MONTH FROM \$_$$\$$rtime\$_$$\$::TIMESTAMPTZ + \$_$$\$$val months\$_$$\$)::text,2,\$_$$\$0\$_$$\$))";
}


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Input::Transform::relative_date;

sub toSQL {
    my $self = shift;

    my $rtime = $self->relative_time || 'now';
    my $val = $self->{params};
    $val = $$val[0] if (ref($val));

    return "DATE(\$_$$\$$rtime\$_$$\$::TIMESTAMPTZ + \$_$$\$$val days\$_$$\$)";
}


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Input::Transform::relative_week;

sub toSQL {
    my $self = shift;

    my $rtime = $self->relative_time || 'now';
    my $val = $self->{params};
    $val = $$val[0] if (ref($val));

    return "EXTRACT(WEEK FROM \$_$$\$rtime\$_$$\$::TIMESTAMPTZ + \$_$$\$$val weeks\$_$$\$)";
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
    } elsif( defined($self->{_column}) ) {
        $self->{_transform} = 'Bare';
    } else {
        $self->{_transform} = 'NULL';
    }


    return $self;
}

sub find_relation {
    my $self = shift;
    return $self->builder->{_rels}->{$self->{_relation}};
}

sub full_column_name {
    my $self = shift;
    return '"' . $self->{_relation} . '"."' . $self->name . '"';
}

sub full_column_output_reference {
    my $self = shift;
    my $fullname = $self->full_column_name;

    if ($self->do_repsec) { # template is new enough...
        my $rel = $self->find_relation;
        if ($rel && $$rel{_idlclass}) { # we need and idl hint in order to do any repsec stuff ...
            if (my $idl_class = Fieldmapper::class_for_hint( $rel->{_idlclass} )) { # ... and we have one
                my $field_info = $idl_class->FieldInfo($self->name);

                if ($$field_info{reporter_redact}) { # the field wants redaction ...
                    $fullname = 'evergreen.redact_value('. $fullname;

                    if ($$field_info{reporter_redact_skip}) { # ... there IS a function we should use to maybe allow the data through
                        $fullname .= ", $$field_info{reporter_redact_skip}(";
                        if ($$field_info{reporter_redact_skip_params}) { # ... and there are parameters needed by the function ...
                            my @params = split(':', $$field_info{reporter_redact_skip_params});
                            my $first = 1;
                            for my $p (@params) { # ... so loop over them and add each
                                $fullname .= ', ' unless $first;
                                $first = 0;
                                if ($p eq '$runner') { # special!
                                    $fullname .= $self->runner;
                                } elsif ($idl_class->has_field($p)) {
                                    $fullname .= '"' . $rel->{_alias} . '"."' . $p . '"';
                                } else {
                                    $fullname .= "\$_$$\$$p\$_$$\$";
                                }
                            }
                        }
                        $fullname .= ')';
                    } else { # ... there is NOT a function, we do not skip!
                        $fullname .= ', FALSE';
                    }

                    if ($$field_info{reporter_redact_with}) { # an alternate value was supplied, otherwise it will be NULL
                        $fullname .= ", \$_$$\$$$field_info{reporter_redact_with}\$_$$\$";
                    }

                    $fullname .= ')';
                }
            }
        }
    }

    return $fullname;
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
    my $func = $self->{_column}->{transform};

    my @params;
    @params = @{ $self->resolve_param( $self->{_column}->{params} ) } if ($self->{_column}->{params});

    my $sql = $func . '(' . $self->full_column_output_reference;
    $sql .= ",\$_$$\$" . join("\$_$$\$,\$_$$\$", @params) . "\$_$$\$" if (@params);
    $sql .= ')';

    return $sql;
}

sub is_aggregate { return $self->{_aggregate} }

#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::Bare;

sub toSQL {
    my $self = shift;
    return $self->full_column_output_reference;
}

sub is_aggregate { return 0 }

#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::upper;

sub toSQL {
    my $self = shift;
    my $params = $self->resolve_param( $self->{_column}->{params} );
    return 'UPPER(' . $self->full_column_output_reference . ')';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::lower;

sub toSQL {
    my $self = shift;
    my $params = $self->resolve_param( $self->{_column}->{params} );
    return 'evergreen.lowercase(' . $self->full_column_output_reference . ')';
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
    return 'TO_CHAR(' . $self->full_column_output_reference . ', \'Day\')';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::month_name;

sub toSQL {
    my $self = shift;
    return 'TO_CHAR(' . $self->full_column_output_reference . ', \'Month\')';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::doy;

sub toSQL {
    my $self = shift;
    return 'EXTRACT(DOY FROM ' . $self->full_column_output_reference . ')';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::woy;

sub toSQL {
    my $self = shift;
    return 'EXTRACT(WEEK FROM ' . $self->full_column_output_reference . ')';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::moy;

sub toSQL {
    my $self = shift;
    return 'EXTRACT(MONTH FROM ' . $self->full_column_output_reference . ')';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::qoy;

sub toSQL {
    my $self = shift;
    return 'EXTRACT(QUARTER FROM ' . $self->full_column_output_reference . ')';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::dom;

sub toSQL {
    my $self = shift;
    return 'EXTRACT(DAY FROM ' . $self->full_column_output_reference . ')';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::dow;

sub toSQL {
    my $self = shift;
    return 'EXTRACT(DOW FROM ' . $self->full_column_output_reference . ')';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::year_trunc;

sub toSQL {
    my $self = shift;
    return 'EXTRACT(YEAR FROM ' . $self->full_column_output_reference . ')';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::month_trunc;

sub toSQL {
    my $self = shift;
    return '(EXTRACT(YEAR FROM ' . $self->full_column_output_reference . ')' .
        ' || \'-\' || LPAD(EXTRACT(MONTH FROM ' . $self->full_column_output_reference . ')::text,2,\'0\'))';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::date_trunc;

sub toSQL {
    my $self = shift;
    return 'DATE(' . $self->full_column_output_reference . ')';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::hour_trunc;

sub toSQL {
    my $self = shift;
    return 'EXTRACT(HOUR FROM ' . $self->full_column_output_reference . ')';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::quarter;

sub toSQL {
    my $self = shift;
    return '(EXTRACT(YEAR FROM ' . $self->full_column_output_reference . ')' .
        ' || \'-Q\' || EXTRACT(QUARTER FROM ' . $self->full_column_output_reference . '))';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::months_ago;

sub toSQL {
    my $self = shift;
    return '(EXTRACT(YEAR FROM AGE(NOW(),' . $self->full_column_output_reference . ')) * 12) +'.
           ' EXTRACT(MONTH FROM AGE(NOW(),' . $self->full_column_output_reference . '))';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::hod;

sub toSQL {
    my $self = shift;
    return 'EXTRACT(HOUR FROM ' . $self->full_column_output_reference . ')';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::quarters_ago;

sub toSQL {
    my $self = shift;
    return '(EXTRACT(YEAR FROM AGE(NOW(),' . $self->full_column_output_reference . ')) * 4) +'.
           ' EXTRACT(QUARTER FROM AGE(NOW(),' . $self->full_column_output_reference . '))';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::age;

sub toSQL {
    my $self = shift;
    return 'AGE(NOW(),' . $self->full_column_output_reference . ')';
}

sub is_aggregate { return 0 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::first;

sub toSQL {
    my $self = shift;
    return 'FIRST(' . $self->full_column_output_reference . ')';
}

sub is_aggregate { return 1 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::last;

sub toSQL {
    my $self = shift;
    return 'LAST(' . $self->full_column_output_reference . ')';
}

sub is_aggregate { return 1 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::min;

sub toSQL {
    my $self = shift;
    return 'MIN(' . $self->full_column_output_reference . ')';
}

sub is_aggregate { return 1 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::max;

sub toSQL {
    my $self = shift;
    return 'MAX(' . $self->full_column_output_reference . ')';
}

sub is_aggregate { return 1 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::count;

sub toSQL {
    my $self = shift;
    return 'COUNT(' . $self->full_column_output_reference . ')';
}

sub is_aggregate { return 1 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::count_distinct;

sub toSQL {
    my $self = shift;
    return 'COUNT(DISTINCT ' . $self->full_column_output_reference . ')';
}

sub is_aggregate { return 1 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::sum;

sub toSQL {
    my $self = shift;
    return 'SUM(' . $self->full_column_output_reference . ')';
}

sub is_aggregate { return 1 }


#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Column::Transform::average;

sub toSQL {
    my $self = shift;
    return 'AVG(' . $self->full_column_output_reference . ')';
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
    my $builder = shift;
    $cond = [$cond] unless (ref($cond) eq 'ARRAY');

    my @out;
    for my $c (@$cond) {
        push @out, OpenILS::Reporter::SQLBuilder::Input->new( $c )->set_builder( $builder );
    }

    return \@out;
}

sub toSQL {
    my $self = shift;

    return $self->{_sql} if ($self->{_sql});

    my $sql = '';

    my $rel = $self->find_relation();
    if ($rel && $rel->is_nullable) {
        $sql = "((". $self->SUPER::toSQL .") IS NULL OR ";
    }

    $sql .= $self->SUPER::toSQL;

    my ($op) = keys %{ $self->{_condition} };
    my $val = _flesh_conditions( $self->resolve_param( $self->{_condition}->{$op} ), $self->builder );

    if (lc($op) eq 'in') {
        $sql .= " IN (". join(",", map { $_->toSQL } @$val).")";

    } elsif (lc($op) eq 'not in') {
        $sql .= " NOT IN (". join(",", map { $_->toSQL } @$val).")";

    } elsif (lc($op) eq '= any') {
        $val = $$val[0] if (ref($val) eq 'ARRAY');
        $val = $val->toSQL;
        if ($rel && $rel->is_nullable) { # need to redo this
            $sql = "((". $self->SUPER::toSQL .") IS NULL OR ";
        } else {
            $sql = '';
        }
        $sql .= "(".$self->SUPER::toSQL.") = ANY ($val)";

    } elsif (lc($op) eq '<> any') {
        $val = $$val[0] if (ref($val) eq 'ARRAY');
        $val = $val->toSQL;
        if ($rel && $rel->is_nullable) { # need to redo this
            $sql = "((". $self->SUPER::toSQL .") IS NULL OR ";
        } else {
            $sql = '';
        }
        $sql .= "(".$self->SUPER::toSQL.") <> ANY ($val)";

    } elsif (lc($op) eq 'is blank') {
        if ($rel && $rel->is_nullable) { # need to redo this
            $sql = "((". $self->SUPER::toSQL .") IS NULL OR ";
        } else {
            $sql = '';
        }
        $sql .= '('. $self->SUPER::toSQL ." IS NULL OR ". $self->SUPER::toSQL ." = '')";

    } elsif (lc($op) eq 'is not blank') {
        if ($rel && $rel->is_nullable) { # need to redo this
            $sql = "((". $self->SUPER::toSQL .") IS NULL OR ";
        } else {
            $sql = '';
        }
        $sql .= '('. $self->SUPER::toSQL ." IS NOT NULL AND ". $self->SUPER::toSQL ." <> '')";

    } elsif (lc($op) eq 'between') {
        $sql .= " BETWEEN SYMMETRIC ". join(" AND ", map { $_->toSQL } @$val);

    } elsif (lc($op) eq 'not between') {
        $sql .= " NOT BETWEEN SYMMETRIC ". join(" AND ", map { $_->toSQL } @$val);

    } elsif (lc($op) eq 'like') {
        $val = $$val[0] if (ref($val) eq 'ARRAY');
        $val = $val->toSQL;
        $val =~ s/\$_$$\$//g;
        $val =~ s/%/\\%/o;
        $val =~ s/_/\\_/o;
        $sql .= " LIKE \$_$$\$\%$val\%\$_$$\$";

    } elsif (lc($op) eq 'ilike') {
        $val = $$val[0] if (ref($val) eq 'ARRAY');
        $val = $val->toSQL;
        $val =~ s/\$_$$\$//g;
        $val =~ s/%/\\%/o;
        $val =~ s/_/\\_/o;
        $sql .= " ILIKE \$_$$\$\%$val\%\$_$$\$";

    } else {
        $val = $$val[0] if (ref($val) eq 'ARRAY');
        $sql .= " $op " . $val->toSQL;
    }

    if ($rel && $rel->is_nullable) {
        $sql .= ")";
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
    my $b = shift;
    $self->set_builder($b);

    $self->{_idlclass} = $rel_data->{idlclass};
    $self->{_table} = $rel_data->{table};
    $self->{_alias} = $rel_data->{alias} || $self->{_table};
    $self->{_RHS_join_addition} = '';
    $self->{_LHS_join_addition} = '';
    $self->{_where_addition} = '';
    $self->{_join} = [];
    $self->{_columns} = [];

    $self->builder->{_rels}{$self->{_alias}} = $self;

    if ($rel_data->{join}) {
        $self->add_join(
            $_ => OpenILS::Reporter::SQLBuilder::Relation->parse( $rel_data->{join}->{$_}, $b ) => $rel_data->{join}->{$_}->{key} => $rel_data->{join}->{$_}->{type}
        ) for ( keys %{ $rel_data->{join} } );
    }

    if ($self->do_repsec) {
        if (my $idl_class = Fieldmapper::class_for_hint($self->{_idlclass})) {

            # Gather JOIN restriction function for use when we're on the right side of a join
            if (my $join_func = $Fieldmapper::fieldmap->{$idl_class}->{reporter_join_function}) {
                $join_func .= '(';
                if (my $join_func_params = $Fieldmapper::fieldmap->{$idl_class}->{reporter_join_parameters}) {
                    my @params = split(':', $join_func_params);
                    my $first = 1;
                    for my $p (@params) { # ... so loop over them and add each
                        $join_func .= ', ' unless $first;
                        $first = 0;
                        if ($p eq '$runner') { # special!
                            $join_func .= $self->runner;
                        } elsif ($idl_class->has_field($p)) {
                            $join_func .= '"'.$self->{_alias}.'"."'.$p.'"';
                        } else {
                            $join_func .= "\$_$$\$$p\$_$$\$";
                        }
                    }
                }
                $join_func .= ')';
                $self->{_RHS_join_addition} = $join_func;
            }

            # Gather WHERE restriction function for use when we're the core class
            if (my $where_func = $Fieldmapper::fieldmap->{$idl_class}->{reporter_where_function}) {
                $where_func .= '(';
                if (my $where_func_params = $Fieldmapper::fieldmap->{$idl_class}->{reporter_where_parameters}) {
                    my @params = split(':', $where_func_params);
                    my $first = 1;
                    for my $p (@params) { # ... so loop over them and add each
                        $where_func .= ', ' unless $first;
                        $first = 0;
                        if ($p eq '$runner') { # special!
                            $where_func .= $self->runner;
                        } elsif ($idl_class->has_field($p)) {
                            $where_func .= '"'.$self->{_alias}.'"."'.$p.'"';
                        } else {
                            $where_func .= "\$_$$\$$p\$_$$\$";
                        }
                    }
                }
                $where_func .= ')';
                $self->{_where_addition} = $where_func;
            }
        }
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
    my $type = lc(shift()) || 'inner';

    if (UNIVERSAL::isa($col,'OpenILS::Reporter::SQLBuilder::Join')) {
        push @{ $self->{_join} }, $col;
    } else {
        push @{ $self->{_join} }, OpenILS::Reporter::SQLBuilder::Join->build( $self => $col, $frel => $fkey, $type );
    }

    return $self;
}

sub is_nullable {
    my $self = shift;
    return $self->{_nullable};
}

sub is_join {
    my $self = shift;
    my $j = shift;
    $self->{_is_join} = $j if ($j);
    return $self->{_is_join};
}

sub join_type {
    my $self = shift;
    my $j = shift;
    $self->{_join_type} = $j if ($j);
    return $self->{_join_type};
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
    my $class = shift;
    my $self = $class->SUPER::new if (!ref($class));

    $self->{_left_rel} = shift;
    ($self->{_left_col}) = split(/-/,shift());

    $self->{_right_rel} = shift;
    $self->{_right_col} = shift;

    $self->{_join_type} = shift;

    $self->{_right_rel}->set_builder($self->{_left_rel}->builder);

    $self->{_right_rel}->is_join(1);
    $self->{_right_rel}->join_type($self->{_join_type});

    bless $self => "OpenILS::Reporter::SQLBuilder::Join::$self->{_join_type}";

    if ( $self->{_join_type} eq 'inner' or !$self->{_join_type}) {
        $self->{_join_type} = 'i';
    } else {
        if ($self->{_join_type} eq 'left') {
            $self->{_right_rel}->{_nullable} = 'l';
        } elsif ($self->{_join_type} eq 'right') {
            $self->{_left_rel}->{_nullable} = 'r';
        } else {
            $self->{_right_rel}->{_nullable} = 'f';
            $self->{_left_rel}->{_nullable} = 'f';
        }
    }

    if ($self->do_repsec) {
        if (my $idl_class = Fieldmapper::class_for_hint($self->{_left_rel}->{_idlclass})) {
            my $lcol = $self->{_left_col};

            # Gather JOIN restriction function for use when we're on the left side of a join, via IDL link
            if (my $join_func = $Fieldmapper::fieldmap->{$idl_class}{links}{$lcol}->{reporter_join_function}) {
                $join_func .= '(';
                if (my $join_func_params = $Fieldmapper::fieldmap->{$idl_class}{links}{$lcol}->{reporter_join_parameters}) {
                    my @params = split(':', $join_func_params);
                    my $first = 1;
                    for my $p (@params) { # ... so loop over them and add each
                        $join_func .= ', ' unless $first;
                        $first = 0;
                        if ($p eq '$runner') { # special!
                            $join_func .= $self->runner;
                        } elsif ($idl_class->has_field($p)) {
                            $join_func .= '"'.$self->{_left_rel}->{_alias}.'"."'.$p.'"';
                        } else {
                            $join_func .= "\$_$$\$$p\$_$$\$";
                        }
                    }
                }
                $join_func .= ')';
                $self->{_left_rel}->{_LHS_join_addition} = $join_func;
            }
        }
    }

    return $self;
}

sub toSQL {
    my $self = shift;
    my $dir = shift;

    my $sql = "JOIN " . $self->{_right_rel}->toSQL .
        ' ON ("' . $self->{_left_rel}->{_alias} . '"."' . $self->{_left_col} .
        '" = "' . $self->{_right_rel}->{_alias} . '"."' . $self->{_right_col} . '"';

    # if we precalculated a JOIN condition based on @repsec:projection_function in the IDL, add that here
    if ($self->{_right_rel}->{_RHS_join_addition}) {
        $sql .= ' AND ' . $self->{_right_rel}->{_RHS_join_addition};
    }

    # if we precalculated a JOIN condition based on @repsec:projection_function in the IDL, add that here
    if ($self->{_left_rel}->{_LHS_join_addition}) {
        $sql .= ' AND ' . $self->{_left_rel}->{_LHS_join_addition};
    }

    $sql .= ")\n";

    $sql .= $_->toSQL($dir) for (@{ $self->{_right_rel}->{_join} });

    return $sql;
}

#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Join::left;
use base qw/OpenILS::Reporter::SQLBuilder::Join/;

sub toSQL {
    my $self = shift;
    my $dir = shift;
    #return $self->{_sql} if ($self->{_sql});

    my $j = $dir && $dir eq 'r' ? 'FULL OUTER' : 'LEFT OUTER';

    my $sql = "\n\t$j ". $self->SUPER::toSQL('l');

    #$sql .= $_->toSQL for (@{ $self->{_right_rel}->{_join} });

    return $self->{_sql} = $sql;
}

#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Join::right;
use base qw/OpenILS::Reporter::SQLBuilder::Join/;

sub toSQL {
    my $self = shift;
    my $dir = shift;
    #return $self->{_sql} if ($self->{_sql});

    my $_nullable_rel = $dir && $dir eq 'l' ? '_right_rel' : '_left_rel';
    $self->{_left_rel}->{_nullable} = 'r';
    $self->{$_nullable_rel}->{_nullable} = $dir;

    my $j = $dir && $dir eq 'l' ? 'FULL OUTER' : 'RIGHT OUTER';

    my $sql = "\n\t$j ". $self->SUPER::toSQL('r');

    #$sql .= $_->toSQL for (@{ $self->{_right_rel}->{_join} });

    return $self->{_sql} = $sql;
}

#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Join::inner;
use base qw/OpenILS::Reporter::SQLBuilder::Join/;

sub toSQL {
    my $self = shift;
    my $dir = shift;
    #return $self->{_sql} if ($self->{_sql});

    my $_nullable_rel = $dir && $dir eq 'l' ? '_right_rel' : '_left_rel';
    $self->{$_nullable_rel}->{_nullable} = $dir;

    my $j = 'INNER';

    my $sql = "\n\t$j ". $self->SUPER::toSQL;

    #$sql .= $_->toSQL for (@{ $self->{_right_rel}->{_join} });

    return $self->{_sql} = $sql;
}

#-------------------------------------------------------------------------------------------------
package OpenILS::Reporter::SQLBuilder::Join::cross;
use base qw/OpenILS::Reporter::SQLBuilder::Join/;

sub toSQL {
    my $self = shift;
    #return $self->{_sql} if ($self->{_sql});

    $self->{_right_rel}->{_nullable} = 'f';
    $self->{_left_rel}->{_nullable} = 'f';

    my $sql = "\n\tFULL OUTER ". $self->SUPER::toSQL('f');

    #$sql .= $_->toSQL for (@{ $self->{_right_rel}->{_join} });

    return $self->{_sql} = $sql;
}

1;
