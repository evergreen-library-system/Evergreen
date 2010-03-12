package OpenILS::Application::Storage::Driver::Pg::QueryParser;
use OpenILS::Application::Storage::QueryParser;
use base 'QueryParser';
use OpenSRF::Utils::JSON;

sub simple_plan {
    my $self = shift;

    return 0 unless $self->parse_tree;
    return 0 if @{$self->parse_tree->filters};
    return 0 if @{$self->parse_tree->modifiers};
    for my $node ( @{ $self->parse_tree->query_nodes } ) {
        return 0 if (!ref($node) && $node eq '|');
        next unless (ref($node));
        return 0 if ($node->isa('QueryParser::query_plan'));
    }

    return 1;
}

sub toSQL {
    my $self = shift;
    return $self->parse_tree->toSQL;
}

sub field_id_map {
    my $self = shift;
    my $map = shift;

    $self->custom_data->{field_id_map} ||= {};
    $self->custom_data->{field_id_map} = $map if ($map);
    return $self->custom_data->{field_id_map};
}

sub add_field_id_map {
    my $self = shift;
    my $class = shift;
    my $field = shift;
    my $id = shift;
    my $weight = shift;

    $self->add_search_field( $class => $field );
    $self->field_id_map->{by_id}{$id} = { classname => $class, field => $field, weight => $weight };
    $self->field_id_map->{by_class}{$class}{$field} = $id;

    return {
        by_id => { $id => { classname => $class, field => $field, weight => $weight } },
        by_class => { $class => { $field => $id } }
    };
}

sub field_class_by_id {
    my $self = shift;
    my $id = shift;

    return $self->field_id_map->{by_id}{$id};
}

sub field_ids_by_class {
    my $self = shift;
    my $class = shift;
    my $field = shift;

    return undef unless ($class);

    if ($field) {
        return [$self->field_id_map->{by_class}{$class}{$field}];
    }

    return [values( %{ $self->field_id_map->{by_class}{$class} } )];
}

sub relevance_bumps {
    my $self = shift;
    my $bumps = shift;

    $self->custom_data->{rel_bumps} ||= {};
    $self->custom_data->{rel_bumps} = $bumps if ($bumps);
    return $self->custom_data->{rel_bumps};
}

sub find_relevance_bumps {
    my $self = shift;
    my $class = shift;
    my $field = shift;

    return $self->relevance_bumps->{$class}{$field};
}

sub add_relevance_bump {
    my $self = shift;
    my $class = shift;
    my $field = shift;
    my $type = shift;
    my $multiplier = shift;
    my $active = shift;

    $active = 1 if (!defined($active));

    $self->relevance_bumps->{$class}{$field}{$type} = { multiplier => $multiplier, active => $active };

    return { $class => { $field => { $type => { multiplier => $multiplier, active => $active } } } };
}


sub initialize_field_id_map {
    my $self = shift;
    my $cmf_list = shift;

    for my $cmf (@$cmf_list) {
        $self->add_field_id_map( $cmf->field_class, $cmf->field, $cmf->id, $cmf->weight );
    }

    return $self->field_id_map;
}

sub initialize_relevance_bumps {
    my $self = shift;
    my $sra_list = shift;

    for my $sra (@$sra_list) {
        my $c = $self->field_class_by_id( $sra->field );
        $self->add_relevance_bump( $c->{classname}, $c->{field}, $sra->bump_type, $sra->multiplier );
    }

    return $self->relevance_bumps;
}

sub initialize_normalizers {
    my $self = shift;
    my $tree = shift; # open-ils.cstore.direct.config.metabib_field_index_norm_map.search.atomic { "id" : { "!=" : null } }, { "flesh" : 1, "flesh_fields" : { "cmfinm" : ["norm"] }, "order_by" : [{ "class" : "cmfinm", "field" : "pos" }] }

    for my $cmfinm ( @$tree ) {
        my $field_info = $self->field_class_by_id( $cmfinm->field );
        $self->add_query_normalizer( $field_info->{classname}, $field_info->{field}, $cmfinm->norm->func, OpenSRF::Utils::JSON->JSON2perl($cmfinm->params) );
    }
}

our $_complete = 0;
sub initialization_complete {
    return $_complete;
}

sub initialize {
    my $self = shift;
    my %args = @_;

    return $_complete if ($_complete);

    $self->initialize_field_id_map( $args{config_metabib_field} )
        if ($args{config_metabib_field});

    $self->initialize_relevance_bumps( $args{search_relevance_adjustment} )
        if ($args{search_relevance_adjustment});

    $self->initialize_normalizers( $args{config_metabib_field_index_norm_map} )
        if ($args{config_metabib_field_index_norm_map});

    $_complete = 1 if (
        $args{config_metabib_field_index_norm_map} &&
        $args{search_relevance_adjustment} &&
        $args{config_metabib_field}
    );

    return $_complete;
}

sub TEST_SETUP {
    
    __PACKAGE__->add_field_id_map( series => seriestitle => 1 => 1 );
    __PACKAGE__->add_relevance_bump( series => seriestitle => first_word => 1.5 );
    __PACKAGE__->add_relevance_bump( series => seriestitle => full_match => 20 );
    
    __PACKAGE__->add_field_id_map( title => abbreviated => 2 => 1 );
    __PACKAGE__->add_relevance_bump( title => abbreviated => first_word => 1.5 );
    __PACKAGE__->add_relevance_bump( title => abbreviated => full_match => 20 );
    
    __PACKAGE__->add_field_id_map( title => translated => 3 => 1 );
    __PACKAGE__->add_relevance_bump( title => translated => first_word => 1.5 );
    __PACKAGE__->add_relevance_bump( title => translated => full_match => 20 );
    
    __PACKAGE__->add_field_id_map( title => proper => 6 => 1 );
    __PACKAGE__->add_query_normalizer( title => proper => 'naco_normalize' );
    __PACKAGE__->add_relevance_bump( title => proper => first_word => 1.5 );
    __PACKAGE__->add_relevance_bump( title => proper => full_match => 20 );
    __PACKAGE__->add_relevance_bump( title => proper => word_order => 10 );
    
    __PACKAGE__->add_field_id_map( author => coporate => 7 => 1 );
    __PACKAGE__->add_relevance_bump( author => coporate => first_word => 1.5 );
    __PACKAGE__->add_relevance_bump( author => coporate => full_match => 20 );
    
    __PACKAGE__->add_field_id_map( author => personal => 8 => 1 );
    __PACKAGE__->add_relevance_bump( author => personal => first_word => 1.5 );
    __PACKAGE__->add_relevance_bump( author => personal => full_match => 20 );
    __PACKAGE__->add_query_normalizer( author => personal => 'naco_normalize' );
    __PACKAGE__->add_query_normalizer( author => personal => 'split_date_range' );
    
    __PACKAGE__->add_field_id_map( subject => topic => 14 => 1 );
    __PACKAGE__->add_relevance_bump( subject => topic => first_word => 1 );
    __PACKAGE__->add_relevance_bump( subject => topic => full_match => 1 );
    
    __PACKAGE__->add_field_id_map( subject => complete => 16 => 1 );
    __PACKAGE__->add_relevance_bump( subject => complete => first_word => 1 );
    __PACKAGE__->add_relevance_bump( subject => complete => full_match => 1 );
    
    __PACKAGE__->add_field_id_map( keyword => keyword => 15 => 1 );
    __PACKAGE__->add_relevance_bump( keyword => keyword => first_word => 1 );
    __PACKAGE__->add_relevance_bump( keyword => keyword => full_match => 1 );
    
    
    __PACKAGE__->add_search_class_alias( keyword => 'kw' );
    __PACKAGE__->add_search_class_alias( title => 'ti' );
    __PACKAGE__->add_search_class_alias( author => 'au' );
    __PACKAGE__->add_search_class_alias( author => 'name' );
    __PACKAGE__->add_search_class_alias( author => 'dc.contributor' );
    __PACKAGE__->add_search_class_alias( subject => 'su' );
    __PACKAGE__->add_search_class_alias( subject => 'bib.subject(?:Title|Place|Occupation)' );
    __PACKAGE__->add_search_class_alias( series => 'se' );
    __PACKAGE__->add_search_class_alias( keyword => 'dc.identifier' );
    
    __PACKAGE__->add_query_normalizer( author => corporate => 'naco_normalize' );
    __PACKAGE__->add_query_normalizer( keyword => keyword => 'naco_normalize' );
    
    __PACKAGE__->add_search_field_alias( subject => name => 'bib.subjectName' );
    
}

__PACKAGE__->default_search_class( 'keyword' );

__PACKAGE__->add_search_filter( 'audience' );
__PACKAGE__->add_search_filter( 'vr_format' );
__PACKAGE__->add_search_filter( 'format' );
__PACKAGE__->add_search_filter( 'item_type' );
__PACKAGE__->add_search_filter( 'item_form' );
__PACKAGE__->add_search_filter( 'lit_form' );
__PACKAGE__->add_search_filter( 'location' );
__PACKAGE__->add_search_filter( 'site' );
__PACKAGE__->add_search_filter( 'depth' );
__PACKAGE__->add_search_filter( 'sort' );
__PACKAGE__->add_search_filter( 'language' );
__PACKAGE__->add_search_filter( 'preferred_language' );
__PACKAGE__->add_search_filter( 'preferred_language_weight' );
__PACKAGE__->add_search_filter( 'statuses' );
__PACKAGE__->add_search_filter( 'bib_level' );
__PACKAGE__->add_search_filter( 'before' );
__PACKAGE__->add_search_filter( 'after' );
__PACKAGE__->add_search_filter( 'during' );
__PACKAGE__->add_search_filter( 'core_limit' );
__PACKAGE__->add_search_filter( 'check_limit' );
__PACKAGE__->add_search_filter( 'skip_check' );
__PACKAGE__->add_search_filter( 'estimation_strategy' );

__PACKAGE__->add_search_modifier( 'available' );
__PACKAGE__->add_search_modifier( 'descending' );
__PACKAGE__->add_search_modifier( 'ascending' );
__PACKAGE__->add_search_modifier( 'metarecord' );
__PACKAGE__->add_search_modifier( 'metabib' );
__PACKAGE__->add_search_modifier( 'staff' );


#-------------------------------
package OpenILS::Application::Storage::Driver::Pg::QueryParser::query_plan;
use base 'QueryParser::query_plan';

sub toSQL {
    my $self = shift;
    my $flat_plan = $self->flatten;

    # generate the relevance ranking
    my $rel = "AVG(\n\t\t(" . join(")+\n\t\t(", @{$$flat_plan{rank_list}}) . ")\n\t)";

    # find any supplied sort option
    my ($sort_filter) = $self->find_filter('sort');
    if ($sort_filter) {
        $sort_filter = $sort_filter->args->[0];
    } else {
        $sort_filter = 'rel';
    }

    my %filters;
    my ($format) = $self->find_filter('format');
    if ($format) {
        my ($t,$f) = split('-', $format->args->[0]);
        $self->new_filter( item_type => [ split '', $t ] ) if ($t);
        $self->new_filter( item_form => [ split '', $f ] ) if ($f);
    }

    for my $f ( qw/audience vr_format item_type item_form lit_form language bib_level/ ) {
        my $col = $f;
        $col = 'item_lang' if ($f eq 'language');
        $filters{$f} = '';
        my ($filter) = $self->find_filter($f);
        if ($filter) {
            $filters{$f} = "AND mrd.$col in (\$_$$\$" . join("\$_$$\$,\$_$$\$",@{$filter->args}) . "\$_$$\$)";
        }
    }

    my $audience = $filters{audience};
    my $vr_format = $filters{vr_format};
    my $item_type = $filters{item_type};
    my $item_form = $filters{item_form};
    my $lit_form = $filters{lit_form};
    my $language = $filters{language};
    my $bib_level = $filters{bib_level};

    my $rank = $rel;

    my $desc = 'ASC';
    $desc = 'DESC' if ($self->find_modifier('descending'));

    if ($sort_filter eq 'rel') { # relevance ranking flips sort dir
         if ($desc eq  'ASC') {
            $desc = 'DESC';
        } else {
            $desc = 'ASC';
        }
    } else {
        if ($sort_filter eq 'title') {
            my $default = $desc eq 'DESC' ? '       ' : 'zzzzzz';
            $rank = <<"            SQL";
( COALESCE( FIRST ((
                SELECT  LTRIM(SUBSTR( frt.value, COALESCE(SUBSTRING(frt.ind2 FROM E'\\\\d+'),'0')::INT + 1 ))
                  FROM  metabib.full_rec frt
                  WHERE frt.record = m.source
                    AND frt.tag = 'tnf'
                    AND frt.subfield = 'a'
                  LIMIT 1
        )),'$default'))
            SQL
        } elsif ($sort_filter eq 'pubdate') {
            $rank = "COALESCE( FIRST(NULLIF(REGEXP_REPLACE(mrd.date1, E'\\\\D+', '0', 'g'),'')), '0' )::INT";
        } elsif ($sort_filter eq 'create_date') {
            $rank = "( FIRST (( SELECT create_date FROM biblio.record_entry rbr WHERE rbr.id = m.source)) )";
        } elsif ($sort_filter eq 'edit_date') {
            $rank = "( FIRST (( SELECT edit_date FROM biblio.record_entry rbr WHERE rbr.id = m.source)) )";
        } elsif ($sort_filter eq 'author') {
            my $default = $desc eq 'DESC' ? '       ' : 'zzzzzz';
            $rank = <<"            SQL"
( COALESCE( FIRST ((
                SELECT  LTRIM(fra.value)
                  FROM  metabib.full_rec fra
                  WHERE fra.record = m.source
                    AND fra.tag LIKE '1%'
                    AND fra.subfield = 'a'
                  ORDER BY fra.tag::text::int
                  LIMIT 1
        )),'$default'))
            SQL
        } else {
            # default to rel ranking
            $rank = $rel;
        }
    }


    my $key = 'm.source';
    $key = 'm.metarecord' if (grep {$_->name eq 'metarecord'} @{$self->modifiers});

    my $sp_size = $self->QueryParser->superpage_size;
    my $sp = $self->QueryParser->superpage;

    my $offset = '';
    if ($sp > 1) {
        $offset = 'OFFSET ' . ($sp - 1) * $sp_size;
    }

    return <<SQL
SELECT  $key AS id,
        ARRAY_ACCUM(DISTINCT m.source) AS records,
        $rel AS rel,
        $rank AS rank, 
        COALESCE( FIRST(NULLIF(REGEXP_REPLACE(mrd.date1, E'\\\\D+', '0', 'g'),'')), '0' )::INT AS tie_break
  FROM  metabib.metarecord_source_map m
        JOIN metabib.rec_descriptor mrd ON (m.source = mrd.record)
        $$flat_plan{from}
  WHERE 1=1
        $audience
        $vr_format
        $item_type
        $item_form
        $lit_form
        $language
        $bib_level
        AND $$flat_plan{where}
  GROUP BY 1
  ORDER BY 4 $desc, 5 DESC
  LIMIT $sp_size
  $offset
SQL

}


sub rel_bump {
    my $self = shift;
    my $node = shift;
    my $bump = shift;
    my $multiplier = shift;

    my $only_atoms = $node->only_atoms;
    return '' if (!@$only_atoms);

    if ($bump eq 'first_word') {
        return "/* first_word */ CASE WHEN naco_normalize(".$node->table_alias.".value) ".
                    "LIKE naco_normalize(\$_$$\$".$only_atoms->[0]->content."\$_$$\$) \|\| '\%' ".
                    "THEN $multiplier ELSE 1 END";
    } elsif ($bump eq 'full_match') {
        return "/* full_match */ CASE WHEN naco_normalize(".$node->table_alias.".value) ".
                    "LIKE". join( '||\'%\'||', map { " naco_normalize(\$_$$\$".$_->content."\$_$$\$) " } @$only_atoms ) .
                    "THEN $multiplier ELSE 1 END";
    } elsif ($bump eq 'word_order') {
        return "/* word_order */ CASE WHEN naco_normalize(".$node->table_alias.".value) ".
                    "LIKE '\%'||". join( '||\'%\'||', map { " naco_normalize(\$_$$\$".$_->content."\$_$$\$) " } @$only_atoms ) . '||\'%\' '.
                    "THEN $multiplier ELSE 1 END";
    }

    return '';
}

sub flatten {
    my $self = shift;

    my $from = shift || '';
    my $where = shift || '';

    my @rank_list;
    for my $node ( @{$self->query_nodes} ) {
        if (ref($node)) {
            if ($node->isa( 'QueryParser::query_plan::node' )) {

                my $table = $node->table;
                my $talias = $node->table_alias;

                my $node_rank = $node->rank . " * ${talias}_weight.weight";

                $from .= "\n\tLEFT JOIN (\n\t\tSELECT *\n\t\t  FROM $table\n\t\t  WHERE index_vector @@ (" .$node->tsquery . ')';

                my @bump_fields;
                if (@{$node->fields} > 0) {
                    @bump_fields = @{$node->fields};
                    $from .= "\n\t\t\tAND field IN (SELECT id FROM config.metabib_field WHERE field_class = \$_$$\$". $node->classname ."\$_$$\$ AND name IN (";
                    $from .= "\$_$$\$" . join("\$_$$\$,\$_$$\$", @{$node->fields}) . "\$_$$\$))";

                } else {
                    @bump_fields = @{$self->QueryParser->search_fields->{$node->classname}};
                }

                my %used_bumps;
                for my $field ( @bump_fields ) {
                    my $bumps = $self->QueryParser->find_relevance_bumps( $node->classname => $field );
                    for my $b (keys %$bumps) {
                        next if (!$$bumps{$b}{active});
                        next if ($used_bumps{$b});
                        $used_bumps{$b} = 1;

                        my $bump_case = $self->rel_bump( $node, $b, $$bumps{$b}{multiplier} );
                        $node_rank .= "\n\t\t\t\t * " . $bump_case if ($bump_case);
                    }
                }

                $from .= "\n\t\tLIMIT " . $self->QueryParser->core_limit . "\n\t) AS " . $node->table_alias . ' ON (m.source = ' . $node->table_alias . ".source)";
                $from .= "\n\tJOIN config.metabib_field AS ${talias}_weight ON (${talias}_weight.id = $talias.field)\n";

                $where .= $node->table_alias . ".id IS NOT NULL ";

                push @rank_list, $node_rank;

            } else {
                my $subnode = $node->flatten;

                push(@rank_list, @{$$subnode{rank_list}});
                $from .= $$subnode{from};
                $where .= "($$subnode{where})";
            }
        } else {
            $where .= ' AND ' if ($node eq '&');
            $where .= ' OR ' if ($node eq '|');
            # ... stitching the WHERE together ...
        }
    }

    return { rank_list => \@rank_list, from => $from, where => $where };

}


#-------------------------------
package OpenILS::Application::Storage::Driver::Pg::QueryParser::query_plan::filter;
use base 'QueryParser::query_plan::filter';

#-------------------------------
package OpenILS::Application::Storage::Driver::Pg::QueryParser::query_plan::modifier;
use base 'QueryParser::query_plan::modifier';

#-------------------------------
package OpenILS::Application::Storage::Driver::Pg::QueryParser::query_plan::node::atom;
use base 'QueryParser::query_plan::node::atom';

sub sql {
    my $self = shift;
    my $sql = shift;

    $self->{sql} = $sql if ($sql);
    
    return $self->{sql} if ($self->{sql});
    return $self->buildSQL;
}

sub buildSQL {
    my $self = shift;

    my $classname = $self->node->classname;

    my $normalizers = $self->node->plan->QueryParser->query_normalizers( $classname );
    my $fields = $self->node->fields;

    $fields = $self->node->plan->QueryParser->search_fields->{$classname} if (!@$fields);

    my @norm_list;
    for my $field (@$fields) {
        for my $nfield (keys %$normalizers) {
            for my $nizer ( @{$$normalizers{$nfield}} ) {
                push(@norm_list, $nizer) if ($field eq $nfield && !(grep {$_ eq $nizer} @norm_list));
            }
        }
    }

    my $sql = "\$_$$\$" . $self->content . "\$_$$\$";;

    for my $n ( @norm_list ) {
        $sql = join(', ', $sql, map { "\$_$$\$" . $_ . "\$_$$\$" } @{ $n->{params} });
        $sql = $n->{function}."($sql)";
    }

    $sql = "to_tsquery('$classname'," . ($self->prefix ? "\$_$$\$" . $self->prefix . "\$_$$\$||" : '') . "'('||regexp_replace($sql,E'(?:\\\\s+|:)','&','g')||')')";

    return $self->sql($sql);
}

#-------------------------------
package OpenILS::Application::Storage::Driver::Pg::QueryParser::query_plan::node;
use base 'QueryParser::query_plan::node';

sub only_atoms {
    my $self = shift;

    my $atoms = $self->query_atoms;
    my @only_atoms;
    for my $a (@$atoms) {
        push(@only_atoms, $a) if (ref($a) && $a->isa('QueryParser::query_plan::node::atom'));
    }

    return \@only_atoms;
}

sub table {
    my $self = shift;
    my $table = shift;
    $self->{table} = $table if ($table);
    return $self->{table} if $self->{table};
    return $self->table( 'metabib.' . $self->classname . '_field_entry' );
}

sub table_alias {
    my $self = shift;
    my $table_alias = shift;
    $self->{table_alias} = $table_alias if ($table_alias);
    return $self->{table_alias} if ($self->{table_alias});

    $table_alias = "$self";
    $table_alias =~ s/^.*\(0(x[0-9a-fA-F]+)\)$/$1/go;
    $table_alias .= '_' . $self->requested_class;
    $table_alias =~ s/\|/_/go;

    return $self->table_alias( $table_alias );
}

sub tsquery {
    my $self = shift;
    return $self->{tsquery} if ($self->{tsquery});

    for my $atom (@{$self->query_atoms}) {
        if (ref($atom)) {
            $self->{tsquery} .= "\n\t\t\t" .$atom->sql;
        } else {
            $self->{tsquery} .= $atom x 2;
        }
    }

    return $self->{tsquery};
}

sub rank {
    my $self = shift;
    return $self->{rank} if ($self->{rank});
    return $self->{rank} = 'rank(' . $self->table_alias . '.index_vector, ' . $self->tsquery . ')';
}


1;

