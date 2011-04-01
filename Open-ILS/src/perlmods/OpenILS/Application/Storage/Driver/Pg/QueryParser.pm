package OpenILS::Application::Storage::Driver::Pg::QueryParser;
use OpenILS::Application::Storage::QueryParser;
use base 'QueryParser';
use OpenSRF::Utils::JSON;
use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';

sub quote_value {
    my $self = shift;
    my $value = shift;

    if ($value =~ /^\d/) { # may have to use non-$ quoting
        $value =~ s/'/''/g;
        $value =~ s/\\/\\\\/g;
        return "E'$value'";
    }
    return "\$_$$\$$value\$_$$\$";
}

sub quote_phrase_value {
    my $self = shift;
    my $value = shift;

    my $left_anchored  = $value =~ m/^\^/;
    my $right_anchored = $value =~ m/\$$/;
    $value =~ s/\^//   if $left_anchored;
    $value =~ s/\$$//  if $right_anchored;
    $value =~ quotemeta($value);
    $value = '^' . $value if $left_anchored;
    $value = "$value\$"   if $right_anchored;
    return $self->quote_value($value);
}

sub init {
    my $class = shift;

}

sub default_preferred_language {
    my $self = shift;
    my $lang = shift;

    $self->custom_data->{default_preferred_language} = $lang if ($lang);
    return $self->custom_data->{default_preferred_language};
}

sub default_preferred_language_multiplier {
    my $self = shift;
    my $lang = shift;

    $self->custom_data->{default_preferred_language_multiplier} = $lang if ($lang);
    return $self->custom_data->{default_preferred_language_multiplier};
}

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

sub facet_field_id_map {
    my $self = shift;
    my $map = shift;

    $self->custom_data->{facet_field_id_map} ||= {};
    $self->custom_data->{facet_field_id_map} = $map if ($map);
    return $self->custom_data->{facet_field_id_map};
}

sub add_facet_field_id_map {
    my $self = shift;
    my $class = shift;
    my $field = shift;
    my $id = shift;
    my $weight = shift;

    $self->add_facet_field( $class => $field );
    $self->facet_field_id_map->{by_id}{$id} = { classname => $class, field => $field, weight => $weight };
    $self->facet_field_id_map->{by_class}{$class}{$field} = $id;

    return {
        by_id => { $id => { classname => $class, field => $field, weight => $weight } },
        by_class => { $class => { $field => $id } }
    };
}

sub facet_field_class_by_id {
    my $self = shift;
    my $id = shift;

    return $self->facet_field_id_map->{by_id}{$id};
}

sub facet_field_ids_by_class {
    my $self = shift;
    my $class = shift;
    my $field = shift;

    return undef unless ($class);

    if ($field) {
        return [$self->facet_field_id_map->{by_class}{$class}{$field}];
    }

    return [values( %{ $self->facet_field_id_map->{by_class}{$class} } )];
}

sub search_field_id_map {
    my $self = shift;
    my $map = shift;

    $self->custom_data->{search_field_id_map} ||= {};
    $self->custom_data->{search_field_id_map} = $map if ($map);
    return $self->custom_data->{search_field_id_map};
}

sub add_search_field_id_map {
    my $self = shift;
    my $class = shift;
    my $field = shift;
    my $id = shift;
    my $weight = shift;

    $self->add_search_field( $class => $field );
    $self->search_field_id_map->{by_id}{$id} = { classname => $class, field => $field, weight => $weight };
    $self->search_field_id_map->{by_class}{$class}{$field} = $id;

    return {
        by_id => { $id => { classname => $class, field => $field, weight => $weight } },
        by_class => { $class => { $field => $id } }
    };
}

sub search_field_class_by_id {
    my $self = shift;
    my $id = shift;

    return $self->search_field_id_map->{by_id}{$id};
}

sub search_field_ids_by_class {
    my $self = shift;
    my $class = shift;
    my $field = shift;

    return undef unless ($class);

    if ($field) {
        return [$self->search_field_id_map->{by_class}{$class}{$field}];
    }

    return [values( %{ $self->search_field_id_map->{by_class}{$class} } )];
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

    if (defined($active) and $active eq 'f') {
        $active = 0;
    } else {
        $active = 1;
    }

    $self->relevance_bumps->{$class}{$field}{$type} = { multiplier => $multiplier, active => $active };

    return { $class => { $field => { $type => { multiplier => $multiplier, active => $active } } } };
}


sub initialize_search_field_id_map {
    my $self = shift;
    my $cmf_list = shift;

    for my $cmf (@$cmf_list) {
        __PACKAGE__->add_search_field_id_map( $cmf->field_class, $cmf->name, $cmf->id, $cmf->weight ) if ($U->is_true($cmf->search_field));
        __PACKAGE__->add_facet_field_id_map( $cmf->field_class, $cmf->name, $cmf->id, $cmf->weight ) if ($U->is_true($cmf->facet_field));
    }

    return $self->search_field_id_map;
}

sub initialize_aliases {
    my $self = shift;
    my $cmsa_list = shift;

    for my $cmsa (@$cmsa_list) {
        if (!$cmsa->field) {
            __PACKAGE__->add_search_class_alias( $cmsa->field_class, $cmsa->alias );
        } else {
            my $c = $self->search_field_class_by_id( $cmsa->field );
            __PACKAGE__->add_search_field_alias( $cmsa->field_class, $c->{field}, $cmsa->alias );
        }
    }
}

sub initialize_relevance_bumps {
    my $self = shift;
    my $sra_list = shift;

    for my $sra (@$sra_list) {
        my $c = $self->search_field_class_by_id( $sra->field );
        __PACKAGE__->add_relevance_bump( $c->{classname}, $c->{field}, $sra->bump_type, $sra->multiplier, $sra->active );
    }

    return $self->relevance_bumps;
}

sub initialize_normalizers {
    my $self = shift;
    my $tree = shift; # open-ils.cstore.direct.config.metabib_field_index_norm_map.search.atomic { "id" : { "!=" : null } }, { "flesh" : 1, "flesh_fields" : { "cmfinm" : ["norm"] }, "order_by" : [{ "class" : "cmfinm", "field" : "pos" }] }

    for my $cmfinm ( @$tree ) {
        my $field_info = $self->search_field_class_by_id( $cmfinm->field );
        __PACKAGE__->add_query_normalizer( $field_info->{classname}, $field_info->{field}, $cmfinm->norm->func, OpenSRF::Utils::JSON->JSON2perl($cmfinm->params) );
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

    $self->initialize_search_field_id_map( $args{config_metabib_field} )
        if ($args{config_metabib_field});

    $self->initialize_aliases( $args{config_metabib_search_alias} )
        if ($args{config_metabib_search_alias});

    $self->initialize_relevance_bumps( $args{search_relevance_adjustment} )
        if ($args{search_relevance_adjustment});

    $self->initialize_normalizers( $args{config_metabib_field_index_norm_map} )
        if ($args{config_metabib_field_index_norm_map});

    $_complete = 1 if (
        $args{config_metabib_field_index_norm_map} &&
        $args{search_relevance_adjustment} &&
        $args{config_metabib_search_alias} &&
        $args{config_metabib_field}
    );

    return $_complete;
}

sub TEST_SETUP {
    
    __PACKAGE__->add_search_field_id_map( series => seriestitle => 1 => 1 );

    __PACKAGE__->add_search_field_id_map( series => seriestitle => 1 => 1 );
    __PACKAGE__->add_relevance_bump( series => seriestitle => first_word => 1.5 );
    __PACKAGE__->add_relevance_bump( series => seriestitle => full_match => 20 );
    
    __PACKAGE__->add_search_field_id_map( title => abbreviated => 2 => 1 );
    __PACKAGE__->add_relevance_bump( title => abbreviated => first_word => 1.5 );
    __PACKAGE__->add_relevance_bump( title => abbreviated => full_match => 20 );
    
    __PACKAGE__->add_search_field_id_map( title => translated => 3 => 1 );
    __PACKAGE__->add_relevance_bump( title => translated => first_word => 1.5 );
    __PACKAGE__->add_relevance_bump( title => translated => full_match => 20 );
    
    __PACKAGE__->add_search_field_id_map( title => proper => 6 => 1 );
    __PACKAGE__->add_query_normalizer( title => proper => 'naco_normalize' );
    __PACKAGE__->add_relevance_bump( title => proper => first_word => 1.5 );
    __PACKAGE__->add_relevance_bump( title => proper => full_match => 20 );
    __PACKAGE__->add_relevance_bump( title => proper => word_order => 10 );
    
    __PACKAGE__->add_search_field_id_map( author => coporate => 7 => 1 );
    __PACKAGE__->add_relevance_bump( author => coporate => first_word => 1.5 );
    __PACKAGE__->add_relevance_bump( author => coporate => full_match => 20 );
    
    __PACKAGE__->add_facet_field_id_map( author => personal => 8 => 1 );

    __PACKAGE__->add_search_field_id_map( author => personal => 8 => 1 );
    __PACKAGE__->add_relevance_bump( author => personal => first_word => 1.5 );
    __PACKAGE__->add_relevance_bump( author => personal => full_match => 20 );
    __PACKAGE__->add_query_normalizer( author => personal => 'naco_normalize' );
    __PACKAGE__->add_query_normalizer( author => personal => 'split_date_range' );
    
    __PACKAGE__->add_facet_field_id_map( subject => topic => 14 => 1 );

    __PACKAGE__->add_search_field_id_map( subject => topic => 14 => 1 );
    __PACKAGE__->add_relevance_bump( subject => topic => first_word => 1 );
    __PACKAGE__->add_relevance_bump( subject => topic => full_match => 1 );
    
    __PACKAGE__->add_search_field_id_map( subject => complete => 16 => 1 );
    __PACKAGE__->add_relevance_bump( subject => complete => first_word => 1 );
    __PACKAGE__->add_relevance_bump( subject => complete => full_match => 1 );
    
    __PACKAGE__->add_search_field_id_map( keyword => keyword => 15 => 1 );
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
__PACKAGE__->add_search_filter( 'locations' );
__PACKAGE__->add_search_filter( 'site' );
__PACKAGE__->add_search_filter( 'lasso' );
__PACKAGE__->add_search_filter( 'my_lasso' );
__PACKAGE__->add_search_filter( 'depth' );
__PACKAGE__->add_search_filter( 'sort' );
__PACKAGE__->add_search_filter( 'language' );
__PACKAGE__->add_search_filter( 'preferred_language' );
__PACKAGE__->add_search_filter( 'preferred_language_weight' );
__PACKAGE__->add_search_filter( 'preferred_language_multiplier' );
__PACKAGE__->add_search_filter( 'statuses' );
__PACKAGE__->add_search_filter( 'bib_level' );
__PACKAGE__->add_search_filter( 'before' );
__PACKAGE__->add_search_filter( 'after' );
__PACKAGE__->add_search_filter( 'between' );
__PACKAGE__->add_search_filter( 'during' );
__PACKAGE__->add_search_filter( 'offset' );
__PACKAGE__->add_search_filter( 'limit' );
__PACKAGE__->add_search_filter( 'core_limit' );
__PACKAGE__->add_search_filter( 'check_limit' );
__PACKAGE__->add_search_filter( 'skip_check' );
__PACKAGE__->add_search_filter( 'superpage' );
__PACKAGE__->add_search_filter( 'superpage_size' );
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
use OpenSRF::Utils::Logger qw($logger);
use Data::Dumper;

sub toSQL {
    my $self = shift;

    my %filters;
    my ($format) = $self->find_filter('format');
    if ($format) {
        my ($t,$f) = split('-', $format->args->[0]);
        $self->new_filter( item_type => [ split '', $t ] ) if ($t);
        $self->new_filter( item_form => [ split '', $f ] ) if ($f);
    }

    for my $f ( qw/preferred_language preferred_language_multiplier preferred_language_weight core_limit check_limit skip_check superpage superpage_size/ ) {
        my $col = $f;
        $col = 'preferred_language_multiplier' if ($f eq 'preferred_language_weight');
        my ($filter) = $self->find_filter($f);
        if ($filter and @{$filter->args}) {
            $filters{$col} = $filter->args->[0];
        }
    }

    $self->QueryParser->superpage($filters{superpage}) if ($filters{superpage});
    $self->QueryParser->superpage_size($filters{superpage_size}) if ($filters{superpage_size});
    $self->QueryParser->core_limit($filters{core_limit}) if ($filters{core_limit});

    $logger->debug("Query plan:\n".Dumper($self));

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

    if (($filters{preferred_language} || $self->QueryParser->default_preferred_language) && ($filters{preferred_language_multiplier} || $self->QueryParser->default_preferred_language_multiplier)) {
        my $pl = $self->QueryParser->quote_value( $filters{preferred_language} ? $filters{preferred_language} : $self->QueryParser->default_preferred_language );
        my $plw = $filters{preferred_language_multiplier} ? $filters{preferred_language_multiplier} : $self->QueryParser->default_preferred_language_multiplier;
        $rel = "($rel * COALESCE( NULLIF( FIRST(mrd.item_lang) = $pl , FALSE )::INT * $plw, 1))";
    }
    $rel .= '::NUMERIC';

    for my $f ( qw/audience vr_format item_type item_form lit_form language bib_level/ ) {
        my $col = $f;
        $col = 'item_lang' if ($f eq 'language');
        $filters{$f} = '';
        my ($filter) = $self->find_filter($f);
        if ($filter) {
            $filters{$f} = "AND mrd.$col in (" . join(",",map { $self->QueryParser->quote_value($_) } @{$filter->args}) . ")";
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
            $rank = "FIRST((SELECT frt.value FROM metabib.full_rec frt WHERE frt.record = m.source AND frt.tag = 'tnf' AND frt.subfield = 'a' LIMIT 1))";
        } elsif ($sort_filter eq 'pubdate') {
            $rank = "FIRST(mrd.date1)::NUMERIC";
        } elsif ($sort_filter eq 'create_date') {
            $rank = "FIRST((SELECT create_date FROM biblio.record_entry rbr WHERE rbr.id = m.source))";
        } elsif ($sort_filter eq 'edit_date') {
            $rank = "FIRST((SELECT edit_date FROM biblio.record_entry rbr WHERE rbr.id = m.source))";
        } elsif ($sort_filter eq 'author') {
            $rank = "FIRST((SELECT fra.value FROM metabib.full_rec fra WHERE fra.record = m.source AND fra.tag LIKE '1%' AND fra.subfield = 'a' ORDER BY fra.tag LIMIT 1))";
        } else {
            # default to rel ranking
            $rank = $rel;
        }
    }

    my $key = 'm.source';
    $key = 'm.metarecord' if (grep {$_->name eq 'metarecord' or $_->name eq 'metabib'} @{$self->modifiers});

    my ($before) = $self->find_filter('before');
    my ($after) = $self->find_filter('after');
    my ($during) = $self->find_filter('during');
    my ($between) = $self->find_filter('between');

    if ($before and @{$before->args} == 1) {
        $before = "AND mrd.date1 <= " . $self->QueryParser->quote_value($before->args->[0]);
    } else {
        $before = '';
    }

    if ($after and @{$after->args} == 1) {
        $after = "AND mrd.date1 >= " . $self->QueryParser->quote_value($after->args->[0]);
    } else {
        $after = '';
    }

    if ($during and @{$during->args} == 1) {
        $during = "AND " . $self->QueryParser->quote_value($during->args->[0]) . " BETWEEN mrd.date1 AND mrd.date2";
    } else {
        $during = '';
    }

    if ($between and @{$between->args} == 2) {
        $between = "AND mrd.date1 BETWEEN " . $self->QueryParser->quote_value($between->args->[0]) . " AND " . $self->QueryParser->quote_value($between->args->[1]);
    } else {
        $between = '';
    }

    my $core_limit = $self->QueryParser->core_limit || 25000;

    my $sql = <<SQL;
SELECT  $key AS id,
        ARRAY_ACCUM(DISTINCT m.source) AS records,
        $rel AS rel,
        $rank AS rank, 
        FIRST(mrd.date1) AS tie_break
  FROM  metabib.metarecord_source_map m
        JOIN metabib.rec_descriptor mrd ON (m.source = mrd.record)
        $$flat_plan{from}
  WHERE 1=1
        $before
        $after
        $during
        $between
        $audience
        $vr_format
        $item_type
        $item_form
        $lit_form
        $language
        $bib_level
        AND $$flat_plan{where}
  GROUP BY 1
  ORDER BY 4 $desc NULLS LAST, 5 DESC NULLS LAST, 3 DESC
  LIMIT $core_limit
SQL

    warn $sql if $self->QueryParser->debug;
    return $sql;

}


sub rel_bump {
    my $self = shift;
    my $node = shift;
    my $bump = shift;
    my $multiplier = shift;

    my $only_atoms = $node->only_atoms;
    return '' if (!@$only_atoms);

    if ($bump eq 'first_word') {
        return " /* first_word */ COALESCE(NULLIF( (naco_normalize(".$node->table_alias.".value) ~ ('^'||naco_normalize(".$self->QueryParser->quote_value($only_atoms->[0]->content)."))), FALSE )::INT * $multiplier, 1)";
    } elsif ($bump eq 'full_match') {
        return " /* full_match */ COALESCE(NULLIF( (naco_normalize(".$node->table_alias.".value) ~ ('^'||".
                    join( "||' '||", map { "naco_normalize(".$self->QueryParser->quote_value($_->content).")" } @$only_atoms )."||'\$')), FALSE )::INT * $multiplier, 1)";
    } elsif ($bump eq 'word_order') {
        return " /* word_order */ COALESCE(NULLIF( (naco_normalize(".$node->table_alias.".value) ~ (".
                    join( "||'.*'||", map { "naco_normalize(".$self->QueryParser->quote_value($_->content).")" } @$only_atoms ).")), FALSE )::INT * $multiplier, 1)";
    }

    return '';
}

sub flatten {
    my $self = shift;

    my $from = shift || '';
    my $where = shift || '(';

    my @rank_list;
    for my $node ( @{$self->query_nodes} ) {
        if (ref($node)) {
            if ($node->isa( 'QueryParser::query_plan::node' )) {

                unless (@{$node->only_atoms}) {
                    push @rank_list, '1';
                    $where .= 'TRUE';
                    next;
                }

                my $table = $node->table;
                my $talias = $node->table_alias;

                my $node_rank = $node->rank . " * ${talias}.weight";

                my $core_limit = $self->QueryParser->core_limit || 25000;
                $from .= "\n\tLEFT JOIN (\n\t\tSELECT fe.*, fe_weight.weight, x.tsq /* search */\n\t\t  FROM  $table AS fe";
                $from .= "\n\t\t\tJOIN config.metabib_field AS fe_weight ON (fe_weight.id = fe.field)";
                $from .= "\n\t\t\tJOIN (SELECT ".$node->tsquery ." AS tsq ) AS x ON (fe.index_vector @@ x.tsq)";

                my @bump_fields;
                if (@{$node->fields} > 0) {
                    @bump_fields = @{$node->fields};

                    my @field_ids;
                    push(@field_ids, $self->QueryParser->search_field_ids_by_class( $node->classname, $_ )->[0]) for (@bump_fields);
                    $from .= "\n\t\t\tWHERE fe_weight.id IN  (". join(',', @field_ids) .")";

                } else {
                    @bump_fields = @{$self->QueryParser->search_fields->{$node->classname}};
                }

                ###$from .= "\n\t\tLIMIT $core_limit";
                $from .= "\n\t) AS $talias ON (m.source = ${talias}.source)";


                my %used_bumps;
                for my $field ( @bump_fields ) {
                    my $bumps = $self->QueryParser->find_relevance_bumps( $node->classname => $field );
                    for my $b (keys %$bumps) {
                        next if (!$$bumps{$b}{active});
                        next if ($used_bumps{$b});
                        $used_bumps{$b} = 1;

                        next if ($$bumps{$b}{multiplier} == 1); # optimization to remove unneeded bumps

                        my $bump_case = $self->rel_bump( $node, $b, $$bumps{$b}{multiplier} );
                        $node_rank .= "\n\t\t\t\t * " . $bump_case if ($bump_case);
                    }
                }

                $where .= '(' . $talias . ".id IS NOT NULL";
                $where .= ' AND ' . join(' AND ', map {"${talias}.value ~* ".$self->QueryParser->quote_phrase_value($_)} @{$node->phrases}) if (@{$node->phrases});
                $where .= ')';

                push @rank_list, $node_rank;

            } elsif ($node->isa( 'QueryParser::query_plan::facet' )) {

                my $table = $node->table;
                my $talias = $node->table_alias;

                my @field_ids;
                if (@{$node->fields} > 0) {
                    push(@field_ids, $self->QueryParser->facet_field_ids_by_class( $node->classname, $_ )->[0]) for (@{$node->fields});
                } else {
                    @field_ids = @{ $self->QueryParser->facet_field_ids_by_class( $node->classname ) };
                }

                $from .= "\n\tJOIN /* facet */ metabib.facet_entry $talias ON (\n\t\tm.source = ${talias}.source\n\t\t".
                         "AND SUBSTRING(${talias}.value,1,1024) IN (" . join(",", map { $self->QueryParser->quote_value($_) } @{$node->values}) . ")\n\t\t".
                         "AND ${talias}.field IN (". join(',', @field_ids) . ")\n\t)";

                $where .= 'TRUE';

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

    return { rank_list => \@rank_list, from => $from, where => $where.')' };

}


#-------------------------------
package OpenILS::Application::Storage::Driver::Pg::QueryParser::query_plan::filter;
use base 'QueryParser::query_plan::filter';

#-------------------------------
package OpenILS::Application::Storage::Driver::Pg::QueryParser::query_plan::facet;
use base 'QueryParser::query_plan::facet';

sub classname {
    my $self = shift;
    my ($classname) = split '\|', $self->name;
    return $classname;
}

sub table {
    my $self = shift;
    return 'metabib.' . $self->classname . '_field_entry';
}

sub fields {
    my $self = shift;
    my ($classname,@fields) = split '\|', $self->name;
    return \@fields;
}

sub table_alias {
    my $self = shift;

    my $table_alias = "$self";
    $table_alias =~ s/^.*\(0(x[0-9a-fA-F]+)\)$/$1/go;
    $table_alias .= '_' . $self->name;
    $table_alias =~ s/\|/_/go;

    return $table_alias;
}


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

    my %norms;
    my $pos = 0;
    for my $field (@$fields) {
        for my $nfield (keys %$normalizers) {
            for my $nizer ( @{$$normalizers{$nfield}} ) {
                if ($field eq $nfield) {
                    my $param_string = OpenSRF::Utils::JSON->perl2JSON($nizer->{params});
                    if (!exists($norms{$nizer->{function}.$param_string})) {
                        $norms{$nizer->{function}.$param_string} = {p=>$pos++,n=>$nizer};
                    }
                }
            }
        }
    }

    my $sql = $self->node->plan->QueryParser->quote_value($self->content);

    for my $n ( map { $$_{n} } sort { $$a{p} <=> $$b{p} } values %norms ) {
        $sql = join(', ', $sql, map { $self->node->plan->QueryParser->quote_value($_) } @{ $n->{params} });
        $sql = $n->{function}."($sql)";
    }

    my $prefix = $self->prefix || '';
    my $suffix = $self->suffix || '';

    $prefix = "'$prefix' ||" if $prefix;
    my $suffix_op = ":$suffix" if $suffix;
    my $suffix_after = "|| '$suffix_op'" if $suffix;

    $sql = "to_tsquery('$classname', COALESCE(NULLIF($prefix '(' || btrim(regexp_replace($sql,E'(?:\\\\s+|:)','$suffix_op&','g'),'&|') $suffix_after || ')', '()'), ''))";

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
    return $self->{rank} = 'rank(' . $self->table_alias . '.index_vector, ' . $self->table_alias . '.tsq)';
}


1;

