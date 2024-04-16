use strict;
use warnings;

package OpenILS::Application::Storage::Driver::Pg::QueryParser;
use OpenILS::Application::Storage::QueryParser;
use base 'QueryParser';
use OpenILS::Utils::DateTime qw/:datetime/;
use OpenSRF::Utils::JSON;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor;
use OpenSRF::Utils::Logger qw($logger);
use Data::Dumper;
my $U = 'OpenILS::Application::AppUtils';

my ${spc} = ' ' x 2;
sub subquery_callback {
    my ($invocant, $self, $struct, $filter, $params, $negate) = @_;

    return sprintf(' ((%s)) ',
        join(
            ') || (',
            map {
                $_->query_text
            } @{
                OpenILS::Utils::CStoreEditor
                    ->new
                    ->search_actor_search_query({ id => $params })
            }
        )
    );
}

sub filter_group_entry_callback {
    my ($invocant, $self, $struct, $filter, $params, $negate) = @_;

    return sprintf(' saved_query(%s)', 
        join(
            ',', 
            map {
                $_->query
            } @{
                OpenILS::Utils::CStoreEditor
                    ->new
                    ->search_actor_search_filter_group_entry({ id => $params })
            }
        )
    );
}

sub format_callback {
    my ($invocant, $self, $struct, $filter, $params, $negate) = @_;

    my $return = '';
    my $negate_flag = ($negate ? '-' : '');
    my @returns;
    for my $param (@$params) {
        my ($t,$f) = split('-', $param);
        my $treturn = '';
        $treturn .= 'item_type(' . join(',',split('', $t)) . ')' if ($t);
        $treturn .= ' ' if ($t and $f);
        $treturn .= 'item_form(' . join(',',split('', $f)) . ')' if ($f);
        $treturn = '(' . $treturn . ')' if ($t and $f);
        push(@returns, $treturn) if $treturn;
    }
    $return = join(' || ', @returns);
    $return = '(' . $return . ')' if(@returns > 1);
    $return = $negate_flag.$return if($return);
    return $return;
}

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
    my $wb = shift;

    my $left_anchored = '';
    my $right_anchored = '';
    my $left_wb = 0;
    my $right_wb = 0;

    $left_anchored  = $1 if $value =~ m/^([*\^])/;
    $right_anchored = $1 if $value =~ m/([*\$])$/;

    # We can't use word-boundary bracket expressions if the relevant char
    # is not actually a "word" characters.
    $left_wb  = $wb if $value =~ m/^\w+/;
    $right_wb = $wb if $value =~ m/\w+$/;

    $value =~ s/^[*\^]//   if $left_anchored;
    $value =~ s/[*\$]$//  if $right_anchored;
    $value = quotemeta($value);
    $value = '^' . $value if $left_anchored eq '^';
    $value = "$value\$"   if $right_anchored eq '$';
    $value = '[[:<:]]' . $value if $left_wb && !$left_anchored;
    $value .= '[[:>:]]' if $right_wb && !$right_anchored;
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

sub max_popularity_importance_multiplier {
    my $self = shift;
    my $max = shift;

    $self->custom_data->{max_popularity_importance_multiplier} = $max if defined($max);
    return $self->custom_data->{max_popularity_importance_multiplier};
}

sub dbh {
    my $self = shift;
    my $dbh = shift;

    $self->custom_data->{dbh} = $dbh if defined($dbh);
    return $self->custom_data->{dbh};
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

sub dynamic_filters {
    my $self = shift;
    my $new = shift;

    $self->custom_data->{dynamic_filters} ||= [];
    push(@{$self->custom_data->{dynamic_filters}}, $new) if ($new);
    return $self->custom_data->{dynamic_filters};
}

sub dynamic_sorters {
    my $self = shift;
    my $new = shift;

    $self->custom_data->{dynamic_sorters} ||= [];
    push(@{$self->custom_data->{dynamic_sorters}}, $new) if ($new);
    return $self->custom_data->{dynamic_sorters};
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

sub search_field_virtual_map {
    my $self = shift;
    my $map = shift;

    $self->custom_data->{search_field_virtual_map} ||= {};
    $self->custom_data->{search_field_virtual_map} = $map if ($map);
    return $self->custom_data->{search_field_virtual_map};
}

sub add_search_field_id_map {
    my $self = shift;
    my $class = shift;
    my $field = shift;
    my $id = shift;
    my $weight = shift;
    my $combined = shift;

    $self->add_search_field( $class => $field );
    $self->search_field_id_map->{by_id}{$id} = { classname => $class, field => $field, weight => $weight };
    $self->search_field_id_map->{by_class}{$class}{$field} = $id;

    return {
        by_id => { $id => { classname => $class, field => $field, weight => $weight } },
        by_class => { $class => { $field => $id } }
    };
}

sub add_search_field_virtual_map {
    my $self = shift;
    my $realid = shift;
    my $virtid = shift;
    my $weight = shift;

    $self->search_field_virtual_map->{by_virt}{$virtid} ||= [];
    push @{$self->search_field_virtual_map->{by_virt}{$virtid}}, { real => $realid, weight => $weight };

    $self->search_field_virtual_map->{by_real}{$realid} ||= [];
    push @{$self->search_field_virtual_map->{by_real}{$realid}}, { virt => $virtid, weight => $weight };
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

sub search_class_weights {
    my $self = shift;
    my $class = shift;
    my $a_weight = shift;
    my $b_weight = shift;
    my $c_weight = shift;
    my $d_weight = shift;

    $self->custom_data->{class_weights} ||= {};
    # Note: This reverses the A-D order, putting D first, because that is how the call actually works in PG
    $self->custom_data->{class_weights}->{$class} ||= [0.1, 0.2, 0.4, 1.0];
    $self->custom_data->{class_weights}->{$class} = [$d_weight, $c_weight, $b_weight, $a_weight] if $a_weight;
    return $self->custom_data->{class_weights}->{$class};
}

sub search_class_combined {
    my $self = shift;
    my $class = shift;
    my $c = shift;

    $self->custom_data->{class_combined} ||= {};
    # Note: This reverses the A-D order, putting D first, because that is how the call actually works in PG
    $self->custom_data->{class_combined}->{$class} ||= 0;
    $self->custom_data->{class_combined}->{$class} = 1 if $c && $c =~ /^(?:t|y|1)/i;
    return $self->custom_data->{class_combined}->{$class};
}

sub class_ts_config {
    my $self = shift;
    my $class = shift;
    my $lang = shift || 'DEFAULT';
    my $always = shift;
    my $ts_config = shift;

    $self->custom_data->{class_ts_config} ||= {};
    $self->custom_data->{class_ts_config}->{$class} ||= {};
    $self->custom_data->{class_ts_config}->{$class}->{$lang} ||= {};
    $self->custom_data->{class_ts_config}->{$class}->{$lang}->{normal} ||= [];
    $self->custom_data->{class_ts_config}->{$class}->{$lang}->{always} ||= [];
    $self->custom_data->{class_ts_config}->{$class}->{'DEFAULT'} ||= {};
    $self->custom_data->{class_ts_config}->{$class}->{'DEFAULT'}->{normal} ||= [];
    $self->custom_data->{class_ts_config}->{$class}->{'DEFAULT'}->{always} ||= [];

    if ($ts_config) {
        push @{$self->custom_data->{class_ts_config}->{$class}->{$lang}->{normal}}, $ts_config unless $always;
        push @{$self->custom_data->{class_ts_config}->{$class}->{$lang}->{always}}, $ts_config if $always;
    }

    my $return = [];
    push @$return, @{$self->custom_data->{class_ts_config}->{$class}->{$lang}->{always}};
    push @$return, @{$self->custom_data->{class_ts_config}->{$class}->{$lang}->{normal}} unless $always;
    if($lang ne 'DEFAULT') {
        push @$return, @{$self->custom_data->{class_ts_config}->{$class}->{'DEFAULT'}->{always}};
        push @$return, @{$self->custom_data->{class_ts_config}->{$class}->{'DEFAULT'}->{normal}} unless $always;
    }
    return $return;
}

sub field_ts_config {
    my $self = shift;
    my $class = shift;
    my $field = shift;
    my $lang = shift || 'DEFAULT';
    my $ts_config = shift;

    $self->custom_data->{field_ts_config} ||= {};
    $self->custom_data->{field_ts_config}->{$class} ||= {};
    $self->custom_data->{field_ts_config}->{$class}->{$field} ||= {};
    $self->custom_data->{field_ts_config}->{$class}->{$field}->{$lang} ||= [];
    $self->custom_data->{field_ts_config}->{$class}->{$field}->{'DEFAULT'} ||= [];

    if ($ts_config) {
        push @{$self->custom_data->{field_ts_config}->{$class}->{$field}->{$lang}}, $ts_config;
    }

    my $return = [];
    push @$return, @{$self->custom_data->{field_ts_config}->{$class}->{$field}->{$lang}};
    if($lang ne 'DEFAULT') {
        push @$return, @{$self->custom_data->{field_ts_config}->{$class}->{$field}->{'DEFAULT'}};
    }
    # Make it easy on us: Grab any "always" for the class here. If we have none we grab them all.
    push @$return, @{$self->class_ts_config($class, $lang, scalar(@$return))};
    return $return;
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

sub initialize_search_field_virtual_map {
    my $self = shift;
    my $cmfvm_list = shift;

    __PACKAGE__->add_search_field_virtual_map( $_->real, $_->virtual, $_->weight )
        for (@$cmfvm_list);

    $logger->debug('Virtual field map: ' . Dumper($self->search_field_virtual_map));
    return $self->search_field_virtual_map;
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

sub initialize_query_normalizers {
    my $self = shift;
    my $tree = shift; # open-ils.cstore.direct.config.metabib_field_index_norm_map.search.atomic { "id" : { "!=" : null } }, { "flesh" : 1, "flesh_fields" : { "cmfinm" : ["norm"] }, "order_by" : [{ "class" : "cmfinm", "field" : "pos" }] }

    for my $cmfinm ( @$tree ) {
        my $field_info = $self->search_field_class_by_id( $cmfinm->field );
        next unless $field_info;
        __PACKAGE__->add_query_normalizer( $field_info->{classname}, $field_info->{field}, $cmfinm->norm->func, OpenSRF::Utils::JSON->JSON2perl($cmfinm->params) );
    }
}

sub initialize_dynamic_filters {
    my $self = shift;
    my $list = shift; # open-ils.cstore.direct.config.record_attr_definition.search.atomic { "id" : { "!=" : null } }

    for my $crad ( @$list ) {
        __PACKAGE__->dynamic_filters( __PACKAGE__->add_search_filter( $crad->name ) ) if ($U->is_true($crad->filter));
        __PACKAGE__->dynamic_sorters( $crad->name ) if ($U->is_true($crad->sorter));
    }
}

sub initialize_filter_normalizers {
    my $self = shift;
    my $tree = shift; # open-ils.cstore.direct.config.record_attr_index_norm_map.search.atomic { "id" : { "!=" : null } }, { "flesh" : 1, "flesh_fields" : { "crainm" : ["norm"] }, "order_by" : [{ "class" : "crainm", "field" : "pos" }] }

    for my $crainm ( @$tree ) {
        __PACKAGE__->add_filter_normalizer( $crainm->attr, $crainm->norm->func, OpenSRF::Utils::JSON->JSON2perl($crainm->params) );
    }
}

sub initialize_search_class_weights {
    my $self = shift;
    my $classes = shift;

    for my $search_class (@$classes) {
        __PACKAGE__->search_class_weights( $search_class->name, $search_class->a_weight, $search_class->b_weight, $search_class->c_weight, $search_class->d_weight );
        __PACKAGE__->search_class_combined( $search_class->name, $search_class->combined );
    }
}

sub initialize_class_ts_config {
    my $self = shift;
    my $class_entries = shift;

    for my $search_class_entry (@$class_entries) {
        __PACKAGE__->class_ts_config($search_class_entry->field_class,$search_class_entry->search_lang,$U->is_true($search_class_entry->always),$search_class_entry->ts_config);
    }
}

sub initialize_field_ts_config {
    my $self = shift;
    my $field_entries = shift;
    my $field_objects = shift;
    my %field_hash = map { $_->id => $_ } @$field_objects;

    for my $search_field_entry (@$field_entries) {
        my $field_object = $field_hash{$search_field_entry->metabib_field};
        __PACKAGE__->field_ts_config($field_object->field_class,$field_object->name,$search_field_entry->search_lang,$search_field_entry->ts_config);
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

    # tsearch rank normalization adjustments. see http://www.postgresql.org/docs/9.0/interactive/textsearch-controls.html#TEXTSEARCH-RANKING for details
    $self->custom_data->{rank_cd_weight_map} = {
        CD_logDocumentLength    => 1,
        CD_documentLength       => 2,
        CD_meanHarmonic         => 4,
        CD_uniqueWords          => 8,
        CD_logUniqueWords       => 16,
        CD_selfPlusOne          => 32
    };

    $self->add_search_modifier( $_ ) for (keys %{ $self->custom_data->{rank_cd_weight_map} });

    $self->initialize_search_field_id_map( $args{config_metabib_field} )
        if ($args{config_metabib_field});

    $self->initialize_search_field_virtual_map( $args{config_metabib_field_virtual_map} )
        if ($args{config_metabib_field_virtual_map});

    $self->initialize_aliases( $args{config_metabib_search_alias} )
        if ($args{config_metabib_search_alias});

    $self->initialize_relevance_bumps( $args{search_relevance_adjustment} )
        if ($args{search_relevance_adjustment});

    $self->initialize_query_normalizers( $args{config_metabib_field_index_norm_map} )
        if ($args{config_metabib_field_index_norm_map});

    $self->initialize_dynamic_filters( $args{config_record_attr_definition} )
        if ($args{config_record_attr_definition});

    $self->initialize_filter_normalizers( $args{config_record_attr_index_norm_map} )
        if ($args{config_record_attr_index_norm_map});

    $self->initialize_search_class_weights( $args{config_metabib_class} )
        if ($args{config_metabib_class});

    $self->initialize_class_ts_config( $args{config_metabib_class_ts_map} )
        if ($args{config_metabib_class_ts_map});

    $self->initialize_field_ts_config( $args{config_metabib_field_ts_map}, $args{config_metabib_field} )
        if ($args{config_metabib_field_ts_map} && $args{config_metabib_field});

    $_complete = 1 if (
        $args{config_metabib_field_index_norm_map} &&
        $args{search_relevance_adjustment} &&
        $args{config_metabib_search_alias} &&
        $args{config_metabib_field} &&
        $args{config_record_attr_definition}
    );

    return $_complete;
}

sub TEST_SETUP {
    
    __PACKAGE__->allow_nested_modifiers(1);

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
    __PACKAGE__->add_query_normalizer( title => proper => 'search_normalize' );
    __PACKAGE__->add_relevance_bump( title => proper => first_word => 1.5 );
    __PACKAGE__->add_relevance_bump( title => proper => full_match => 20 );
    __PACKAGE__->add_relevance_bump( title => proper => word_order => 10 );
    
    __PACKAGE__->add_search_field_id_map( author => corporate => 7 => 1 );
    __PACKAGE__->add_relevance_bump( author => corporate => first_word => 1.5 );
    __PACKAGE__->add_relevance_bump( author => corporate => full_match => 20 );
    
    __PACKAGE__->add_facet_field_id_map( author => personal => 8 => 1 );

    __PACKAGE__->add_search_field_id_map( author => personal => 8 => 1 );
    __PACKAGE__->add_relevance_bump( author => personal => first_word => 1.5 );
    __PACKAGE__->add_relevance_bump( author => personal => full_match => 20 );
    __PACKAGE__->add_query_normalizer( author => personal => 'search_normalize' );
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
    
    __PACKAGE__->add_search_field_virtual_map( 6 => 15 => 5 );

    __PACKAGE__->class_ts_config( 'series', undef, 1, 'english_nostop' );
    __PACKAGE__->class_ts_config( 'title', undef, 1, 'english_nostop' );
    __PACKAGE__->class_ts_config( 'author', undef, 1, 'english_nostop' );
    __PACKAGE__->class_ts_config( 'subject', undef, 1, 'english_nostop' );
    __PACKAGE__->class_ts_config( 'keyword', undef, 1, 'english_nostop' );
    __PACKAGE__->class_ts_config( 'series', undef, 1, 'simple' );
    __PACKAGE__->class_ts_config( 'title', undef, 1, 'simple' );
    __PACKAGE__->class_ts_config( 'author', undef, 1, 'simple' );
    __PACKAGE__->class_ts_config( 'subject', undef, 1, 'simple' );
    __PACKAGE__->class_ts_config( 'keyword', undef, 1, 'simple' );

    # French! To test language limiters
    __PACKAGE__->class_ts_config( 'series', 'fre', 1, 'french_nostop' );
    __PACKAGE__->class_ts_config( 'title', 'fre', 1, 'french_nostop' );
    __PACKAGE__->class_ts_config( 'author', 'fre', 1, 'french_nostop' );
    __PACKAGE__->class_ts_config( 'subject', 'fre', 1, 'french_nostop' );
    __PACKAGE__->class_ts_config( 'keyword', 'fre', 1, 'french_nostop' );

    # Not a default config by any means, but good for some testing
    __PACKAGE__->field_ts_config( 'author', 'personal', 'eng', 'english' );
    __PACKAGE__->field_ts_config( 'author', 'personal', 'fre', 'french' );
    
    __PACKAGE__->add_search_class_alias( keyword => 'kw' );
    __PACKAGE__->add_search_class_alias( title => 'ti' );
    __PACKAGE__->add_search_class_alias( author => 'au' );
    __PACKAGE__->add_search_class_alias( author => 'name' );
    __PACKAGE__->add_search_class_alias( author => 'dc.contributor' );
    __PACKAGE__->add_search_class_alias( subject => 'su' );
    __PACKAGE__->add_search_class_alias( subject => 'bib.subject(?:Title|Place|Occupation)' );
    __PACKAGE__->add_search_class_alias( series => 'se' );
    __PACKAGE__->add_search_class_alias( keyword => 'dc.identifier' );
    
    __PACKAGE__->add_query_normalizer( author => corporate => 'search_normalize' );
    __PACKAGE__->add_query_normalizer( keyword => keyword => 'search_normalize' );
    
    __PACKAGE__->add_search_field_alias( subject => name => 'bib.subjectName' );
    
    #__PACKAGE__->search_class_combined( keyword => 1 );
    __PACKAGE__->search_class_combined( author => 1 );
}

__PACKAGE__->default_search_class( 'keyword' );

# implements EG-specific stored subqueries
__PACKAGE__->add_search_filter( 'saved_query', sub { return __PACKAGE__->subquery_callback(@_) } );
__PACKAGE__->add_search_filter( 'filter_group_entry', sub { return __PACKAGE__->filter_group_entry_callback(@_) } );

# will be retained simply for back-compat
__PACKAGE__->add_search_filter( 'format', sub { return __PACKAGE__->format_callback(@_) } );

# grumble grumble, special cases against date1 and date2
__PACKAGE__->add_search_filter( 'before' );
__PACKAGE__->add_search_filter( 'after' );
__PACKAGE__->add_search_filter( 'between' );
__PACKAGE__->add_search_filter( 'during' );

# various filters for limiting in various ways
__PACKAGE__->add_search_filter( 'edit_date' );
__PACKAGE__->add_search_filter( 'create_date' );
__PACKAGE__->add_search_filter( 'statuses' );
__PACKAGE__->add_search_filter( 'locations' );
__PACKAGE__->add_search_filter( 'location_groups' );
__PACKAGE__->add_search_filter( 'bib_source' );
__PACKAGE__->add_search_filter( 'badge_orgs' );
__PACKAGE__->add_search_filter( 'badges' );
__PACKAGE__->add_search_filter( 'site' );
__PACKAGE__->add_search_filter( 'pref_ou' );
__PACKAGE__->add_search_filter( 'lasso' );
__PACKAGE__->add_search_filter( 'my_lasso' );
__PACKAGE__->add_search_filter( 'depth' );
__PACKAGE__->add_search_filter( 'language' );
__PACKAGE__->add_search_filter( 'offset' );
__PACKAGE__->add_search_filter( 'limit' );
__PACKAGE__->add_search_filter( 'check_limit' );
__PACKAGE__->add_search_filter( 'skip_check' );
__PACKAGE__->add_search_filter( 'superpage' );
__PACKAGE__->add_search_filter( 'superpage_size' );
__PACKAGE__->add_search_filter( 'estimation_strategy' );
__PACKAGE__->add_search_filter( 'from_metarecord' );
__PACKAGE__->add_search_filter( 'on_reserve' );
__PACKAGE__->add_search_modifier( 'available' );
__PACKAGE__->add_search_modifier( 'staff' );
__PACKAGE__->add_search_modifier( 'deleted' );
__PACKAGE__->add_search_modifier( 'lucky' );

# Start from container data (bre, acn, acp): container(bre,bookbag,123,deadb33fdeadb33fdeadb33fdeadb33f)
__PACKAGE__->add_search_filter( 'container' );

# Start from a list of record ids, either bre or metarecords, depending on the #metabib modifier
__PACKAGE__->add_search_filter( 'record_list' );

__PACKAGE__->add_search_filter( 'has_browse_entry' );

# copy_tag(copy_tag_code,copy_tag_search)
__PACKAGE__->add_search_filter( 'copy_tag' );

# used internally, but generally not user-settable
__PACKAGE__->add_search_filter( 'preferred_language' );
__PACKAGE__->add_search_filter( 'preferred_language_weight' );
__PACKAGE__->add_search_filter( 'preferred_language_multiplier' );
__PACKAGE__->add_search_filter( 'core_limit' );

# XXX Valid values to be supplied by SVF
__PACKAGE__->add_search_filter( 'sort' );

# modifies core query, not configurable
__PACKAGE__->add_search_modifier( 'descending' );
__PACKAGE__->add_search_modifier( 'ascending' );
__PACKAGE__->add_search_modifier( 'nullsfirst' );
__PACKAGE__->add_search_modifier( 'nullslast' );
__PACKAGE__->add_search_modifier( 'metarecord' );
__PACKAGE__->add_search_modifier( 'metabib' );


#-------------------------------
package OpenILS::Application::Storage::Driver::Pg::QueryParser::query_plan;
use base 'QueryParser::query_plan';
use OpenSRF::Utils::Logger qw($logger);
use OpenILS::Utils::DateTime qw/:datetime/;
use Data::Dumper;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::Normalize qw/search_normalize/;
my $apputils = "OpenILS::Application::AppUtils";

our %_dfilter_controlled_cache = ();
our %_dfilter_stats_cache = ();
our $_pg_version = 0;

sub dynamic_filter_compile {
    my ($self, $filter, $params, $negate) = @_;
    my $e = OpenILS::Utils::CStoreEditor->new;

    $negate = $negate ? '!' : '';

    if (!$_pg_version) {
        ($_pg_version = $e->json_query({from => ['version']})->[0]->{version}) =~ s/^.+?(\d\.\d).+$/$1/;
    }

    my $common = 0;
    if ($_pg_version >= 9.2) {
        if (!scalar keys %_dfilter_stats_cache) {
            my $data = $e->json_query({from => ['evergreen.pg_statistics', 'record_attr_vector_list', 'vlist']});
            %_dfilter_stats_cache = map {
                ( $_->{element}, $_->{frequency} )
            } grep { $_->{frequency} > 5 } @$data; # Pin floor to 5% of the table
        }
    } else {
        $common = 1; # Assume it's expensive
    }

    if (!exists($_dfilter_controlled_cache{$filter})) {
        my $crad = $e->retrieve_config_record_attr_definition($filter);
        my $ccvm_list = $e->search_config_coded_value_map({ctype =>$filter});

        $_dfilter_controlled_cache{$filter} = $crad->to_bare_hash;
        $_dfilter_controlled_cache{$filter}{controlled} = scalar @$ccvm_list;
    }

    my $method = $_dfilter_controlled_cache{$filter}{controlled} ?
        'search_config_coded_value_map' : 'search_metabib_uncontrolled_record_attr_value';
    my $attr_field = $_dfilter_controlled_cache{$filter}{controlled} ?
        'ctype' : 'attr';
    my $value_field = $_dfilter_controlled_cache{$filter}{controlled} ?
        'code' : 'value';

    my $attr_objects = $e->$method({ $attr_field => $filter, $value_field => $params });
    $common = scalar(grep { exists($_dfilter_stats_cache{$_->id}) } @$attr_objects) unless $common;
    
    return (sprintf('%s(%s)', $negate,
        join(
            '|', 
            map { $_->id } @$attr_objects
        )
    ), $common);
}

sub toSQL {
    my $self = shift;

    my %filters;

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
    my $rel = '1'; # Default to something simple in case rank_list is empty.
    if (@{$$flat_plan{rank_list}}) {
        $rel = "AVG(\n"
             . ${spc} x 5 ."("
             . join(")\n" . ${spc} x 5 . "+ (", @{$$flat_plan{rank_list}})
             . ")\n"
             . ${spc} x 4 . ")+1";
    }

    # find any supplied sort option
    my ($sort_filter) = $self->find_filter('sort');
    if ($sort_filter) {
        $sort_filter = $sort_filter->args->[0];
    } else {
        $sort_filter = 'rel';
    }

    my $lang_join = '';
    if (($filters{preferred_language} || $self->QueryParser->default_preferred_language) && ($filters{preferred_language_multiplier} || $self->QueryParser->default_preferred_language_multiplier)) {
    
        my $pl = $self->QueryParser->quote_value( $filters{preferred_language} ? $filters{preferred_language} : $self->QueryParser->default_preferred_language );
        $$flat_plan{with} .= ',' if $$flat_plan{with};
        $$flat_plan{with} .= "lang_with AS (SELECT id FROM config.coded_value_map WHERE ctype = 'item_lang' AND code = $pl)";
        $lang_join = ",lang_with";

        my $plw = $filters{preferred_language_multiplier} ? $filters{preferred_language_multiplier} : $self->QueryParser->default_preferred_language_multiplier;
        $rel = "($rel * COALESCE( NULLIF( FIRST(mrv.vlist \@> ARRAY[lang_with.id]), FALSE )::INT * $plw, 1))";
        $$flat_plan{uses_mrv} = 1;
    }

    my $mrv_join = '';
    if ($$flat_plan{uses_mrv}) {
        $mrv_join = 'INNER JOIN metabib.record_attr_vector_list mrv ON m.source = mrv.source';
    }

    my $mra_join = '';
    if ($$flat_plan{uses_mrd}) {
        $mra_join = 'INNER JOIN metabib.record_attr mrd ON m.source = mrd.id';
    }

    my $pubdate_join = "LEFT JOIN metabib.record_sorter pubdate_t ON m.source = pubdate_t.source AND attr = 'pubdate'";

    my $bre_join = '';
    if ($self->find_modifier('deleted')) {
        $bre_join = 'INNER JOIN biblio.record_entry bre ON m.source = bre.id AND bre.deleted';
        # The above suffices for filters too when the #deleted modifier
        # is in use.
    } else {
        $bre_join = 'INNER JOIN biblio.record_entry bre ON m.source = bre.id AND NOT bre.deleted';
    }

    my $desc = 'ASC';
    $desc = 'DESC' if ($self->find_modifier('descending'));

    my $nullpos = 'NULLS LAST';
    $nullpos = 'NULLS FIRST' if ($self->find_modifier('nullsfirst'));

    my $course_join = q{};
    my $course_where = q{};
    my ($course_filter) = $self->find_filter('on_reserve');
    if ($course_filter) {
        my $course_org_filter = q{};
        if (@{$course_filter->args}) {
            my @course_orgs = grep /^\d+$/, @{$course_filter->args};
            # Don't filter by course OU if we didn't find any good candidate IDs.
            # This way, users can do searches like `biology on_reserve(all)` to
            # find matches from all org units' courses
            if (@course_orgs > 0) {
                my $course_orgs_with_descendants = [];
                foreach ( @course_orgs ) {
                    push @$course_orgs_with_descendants, @{$U->get_org_descendants($_)};
                }
                my $course_org_string = join q{,}, @$course_orgs_with_descendants;
                $course_org_filter .= "AND acmc.owning_lib IN ($course_org_string) ";
            }
        }
        if ($course_filter->negate) {
          $course_join .= ' LEFT JOIN (SELECT record FROM asset.course_module_course_materials acmcm';
          $course_join .= " INNER JOIN asset.course_module_course acmc ON acmcm.course=acmc.id $course_org_filter ) cm";
          $course_join .= ' ON cm.record=m.source';
          $course_where .= ' AND cm.record IS NULL';
        } else {
          $course_join .= ' INNER JOIN asset.course_module_course_materials acmcm ON m.source = acmcm.record';
          $course_join .= " INNER JOIN asset.course_module_course acmc ON acmcm.course=acmc.id $course_org_filter";
        }
    }

    # Do we have a badges() filter?
    my $badges = '';
    my ($badge_filter) = $self->find_filter('badges');
    if ($badge_filter && @{$badge_filter->args}) {
        $badges = join (',', grep /^\d+$/, @{$badge_filter->args});
    }

    # Do we have a badge_orgs() filter? (used for calculating popularity)
    my $borgs = '';
    my ($bo_filter) = $self->find_filter('badge_orgs');
    if ($bo_filter && @{$bo_filter->args}) {
        $borgs = join (',', grep /^\d+$/, @{$bo_filter->args});
    }

    # Build the badge-ish WITH query
    my $pop_with = <<'    WITH';
        pop_with AS (
            SELECT  record,
                    ARRAY_AGG(badge) AS badges,
                    SUM(s.score::NUMERIC*b.weight::NUMERIC)/SUM(b.weight::NUMERIC) AS total_score
              FROM  rating.record_badge_score s
                    JOIN rating.badge b ON (
                        b.id = s.badge
    WITH

    $pop_with .= " AND b.id = ANY ('{$badges}')" if ($badges);
    $pop_with .= " AND b.scope = ANY ('{$borgs}')" if ($borgs);
    $pop_with .= ') GROUP BY 1)'; 

    my $pop_join = $badges ? # inner join if we are restricting via badges()
        'INNER JOIN pop_with ON ( m.source = pop_with.record )' : 
        'LEFT JOIN pop_with ON ( m.source = pop_with.record )';

    $$flat_plan{with} .= ',' if $$flat_plan{with};
    $$flat_plan{with} .= $pop_with;


    my $rank;
    my $pop_extra_sort = '';
    if (grep {$_ eq $sort_filter} @{$self->QueryParser->dynamic_sorters}) {
        $rank = "FIRST((SELECT value FROM metabib.record_sorter rbr WHERE rbr.source = m.source and attr = '$sort_filter'))"
    } elsif ($sort_filter eq 'create_date') {
        $rank = "FIRST((SELECT create_date FROM biblio.record_entry rbr WHERE rbr.id = m.source))";
    } elsif ($sort_filter eq 'edit_date') {
        $rank = "FIRST((SELECT edit_date FROM biblio.record_entry rbr WHERE rbr.id = m.source))";
    } elsif ($sort_filter eq 'poprel') {
        my $max_mult = $self->QueryParser->max_popularity_importance_multiplier() // 2.0;
        $max_mult = 0.1 if $max_mult < 0.1; # keep it within reasonable bounds,
                                            # and avoid the division-by-zero error
                                            # you'd get if you allowed it to be
                                            # zero

        if ( $max_mult == 1.0 ) { # no adjustment requested by the configuration
            $rank = "1.0/($rel)::NUMERIC";
        } else { # calculate adjustment

            # Scale the 0-5 effect of popularity badges by providing a multiplier
            # for the badge average based on the overall maximum
            # multiplier.  Two examples, comparing the effect to the default
            # $max_mult value of 2.0, which causes a $adjusted_scale value
            # of 0.2:
            #
            #  * Given the default $max_mult of 2.0, the value of
            #    $adjusted_scale will be 0.2 [($max_mult - 1.0) / 5.0].
            #    For a record whose average badge score is the maximum
            #    of 5.0, that would make the relevance multiplier be
            #    2.0:
            #       1.0 + (5.0 [average score] * 0.2 [ $adjusted_scale ],
            #    This would have the effect of doubling the effective
            #    relevance of highly popular items.
            #
            #  * Given a $max_mult of 1.1, the value of $adjusted_scale
            #    will be 0.02, meaning that the average badge value will be
            #    multiplied by 0.02 rather than 0.2, then added to 1.0 and
            #    used as a multiplier against the base relevance.  Thus a
            #    change of at most 10% to the base relevance for a record
            #    with a 5.0 average badge score. This will allow records
            #    that are naturally very relevant to avoid being pushed
            #    below badge-heavy records.
            #
            #  * Given a $max_mult of 3.0, the value of $adjusted_scale
            #    will be 0.4, meaning that the average badge value will be
            #    multiplied by 0.4 rather than 0.2, then added to 1.0 and
            #    used as a multiplier against the base relevance. Thus a
            #    change of as much as 200% to (or three times the size of)
            #    the base relevance for a record with a 5.0 average badge
            #    score.  This in turn will cause badges to outweigh
            #    relevance to a very large degree.
            #
            # The maximum badge multiplier can be set to a value less than
            # 1.0; this would have the effect of making less popular items
            # show up higher in the results.  While this is not a likely
            # option for production use, it could be useful for identifying
            # interesting long-tail hits, particularly in a database
            # where enough badges are configured so that very few records
            # have an overage badge score of zero.

            my $adjusted_scale = ( $max_mult - 1.0 ) / 5.0;
            $rank = "1.0/(( $rel ) * (1.0 + (AVG(COALESCE(pop_with.total_score::NUMERIC,0.0::NUMERIC)) * ${adjusted_scale}::NUMERIC)))::NUMERIC";
        }
    } elsif ($sort_filter =~ /^pop/) {
        $rank = '1.0/(AVG(COALESCE(pop_with.total_score::NUMERIC,0.0::NUMERIC)) + 5.0::NUMERIC)::NUMERIC';
        my $pop_desc = $desc eq 'ASC' ? 'DESC' : 'ASC';
        $pop_extra_sort = "3 $pop_desc $nullpos,";
    } else {
        # default to rel ranking
        $rank = "1.0/($rel)::NUMERIC";
    }

    my $key = 'm.source';
    $key = 'm.metarecord' if (grep {$_->name eq 'metarecord' or $_->name eq 'metabib'} @{$self->modifiers});

    my $core_limit = $self->QueryParser->core_limit || 'NULL';
    if ($self->find_modifier('lucky')) {
        $filters{check_limit} = 1;
        $filters{skip_check} = 0;
    	$core_limit = 1;
    }


    my $flat_where = $$flat_plan{where};
    if ($flat_where ne '') {
        $flat_where = "AND (\n" . ${spc} x 5 . $flat_where . "\n" . ${spc} x 4 . ")";
    }

    my $final_c_attr_test;
    my $c_attr_join = '';
    my $c_vis_test = '';
    my $pc_vis_test = '';

    # copy visibility testing
    if (!$self->find_modifier('staff')) {
        $pc_vis_test = "c_attrs";
        $c_attr_join = ",c_attr"
    }

    if ($self->find_modifier('available')) {
        push @{$$flat_plan{vis_filter}{'c_attr'}},
            "search.calculate_visibility_attribute_test('status','{0,7,12}')";
    }

    if (@{$$flat_plan{vis_filter}{c_attr}}) {
        $c_vis_test = join(",",@{$$flat_plan{vis_filter}{c_attr}});
        $c_attr_join = ',c_attr';
    }

    if ($c_vis_test or $pc_vis_test) {
        my $vis_test = '';

        if ($c_vis_test and $pc_vis_test) {
            $vis_test = $pc_vis_test . ",". $c_vis_test;
        } elsif ($pc_vis_test) {
            $vis_test = $pc_vis_test;
        } else {
            $vis_test = $c_vis_test;
        }

        # WITH-clause just generates vis test
        $$flat_plan{with} .= "\n," if $$flat_plan{with};
        $$flat_plan{with} .= "c_attr AS (SELECT (ARRAY_TO_STRING(ARRAY[$vis_test],'&'))::query_int AS vis_test FROM asset.patron_default_visibility_mask() x OFFSET 0)";

        $final_c_attr_test = 'EXISTS (SELECT 1 FROM asset.copy_vis_attr_cache WHERE record = m.source AND vis_attr_vector @@ c_attr.vis_test)';
    }
 
    if ($self->find_modifier('staff') && !$self->find_modifier('available') && !$self->find_filter('locations') && !$self->find_filter('location_groups')) {
        $final_c_attr_test ||= 'FALSE';
        $final_c_attr_test = '(' . $final_c_attr_test . " OR (" .
                "NOT EXISTS (SELECT 1 FROM asset.copy_vis_attr_cache WHERE record = m.source) " .
                "AND (bre.vis_attr_vector IS NULL OR NOT ( int4range(0,268435455,'[]') @> ANY(bre.vis_attr_vector) ))".
            "))";
        # We need bre here, regardless
        $bre_join ||= 'INNER JOIN biblio.record_entry bre ON m.source = bre.id AND NOT bre.deleted';
    }

    my $final_b_attr_test;
    my $b_attr_join = '';
    my $b_vis_test = '';
    my $pb_vis_test = '';

    # bib visibility testing
    if (!$self->find_modifier('staff')) {
        $pb_vis_test = "b_attrs";
        $b_attr_join = ",b_attr"
    }

    if (@{$$flat_plan{vis_filter}{b_attr}}) {
        $b_attr_join = ',b_attr ';
        $b_vis_test = join("||'&'||",@{$$flat_plan{vis_filter}{b_attr}});
    }

    # bib vis tests are handled a little bit differently, as they're simpler but need special handling
    if ($b_vis_test or $pb_vis_test) {
        my $vis_test = '';

        if ($b_vis_test and $pb_vis_test) { # $pb_vis_test supplies a query_int operator at its end
            $vis_test = $pb_vis_test . '||'. $b_vis_test;
        } elsif ($pb_vis_test) { # here we want to remove it
            $vis_test = "RTRIM($pb_vis_test,'|&')";
        } else {
            $vis_test = $b_vis_test;
        }

        # WITH-clause just generates vis test
        $$flat_plan{with} .= "\n," if $$flat_plan{with};
        $$flat_plan{with} .= "b_attr AS (SELECT ($vis_test)::query_int AS vis_test FROM asset.patron_default_visibility_mask() x OFFSET 0)";

        # These are magic numbers... see: search.calculate_visibility_attribute() UDF
        $final_b_attr_test = '(b_attr.vis_test IS NULL OR bre.vis_attr_vector @@ b_attr.vis_test)';
    }

    if ($final_c_attr_test or $final_b_attr_test) { # something...
        if ($final_c_attr_test and $final_b_attr_test) { # both!
            my $plan = "($final_c_attr_test) OR ($final_b_attr_test)";
            $flat_where .= "\n" . ${spc} x 4 . "AND (\n" . ${spc} x 5 .  $plan .  "\n" . ${spc} x 4 . ")";
        } elsif ($final_c_attr_test) { # just copies...
            $flat_where .= "\n" . ${spc} x 4 . "AND (\n" . ${spc} x 5 .  $final_c_attr_test .  "\n" . ${spc} x 4 . ")";
        } else { # just bibs...
            $flat_where .= "\n" . ${spc} x 4 . "AND (\n" . ${spc} x 5 .  $final_b_attr_test .  "\n" . ${spc} x 4 . ")";
        }
    }

    my $with = $$flat_plan{with};
    $with= "\nWITH $with" if $with;

    # Need an array for query parser db function; this gives a better plan
    # than the ARRAY_AGG(DISTINCT m.source) option as of PostgreSQL 9.1
    my $agg_records = 'ARRAY[m.source] AS records';
    if ($key =~ /metarecord/) {
        # metarecord searches still require the ARRAY_AGG approach
        $agg_records = 'ARRAY_AGG(DISTINCT m.source) AS records';
    }

    my $sql = <<SQL;
WITH w AS (

$with
SELECT  id,
        rel,
        CASE WHEN cardinality(records) = 1 THEN records[1] ELSE NULL END AS record,
        NULL::INT AS total,
        NULL::INT AS checked,
        NULL::INT AS visible,
        NULL::INT AS deleted,
        NULL::INT AS excluded,
        badges,
        popularity
  FROM  (SELECT $key AS id,
                $agg_records,
                ${rel}::NUMERIC AS rel,
                $rank AS rank, 
                FIRST(pubdate_t.value) AS tie_break,
                STRING_AGG(ARRAY_TO_STRING(pop_with.badges,','),',') AS badges,
                AVG(COALESCE(pop_with.total_score::NUMERIC,0.0::NUMERIC))::NUMERIC(2,1) AS popularity
          FROM  metabib.metarecord_source_map m
                $$flat_plan{from}
                $mra_join
                $mrv_join
                $bre_join
                $course_join
                $pop_join
                $pubdate_join
                $lang_join
                $c_attr_join
                $b_attr_join
          WHERE 1=1
                $flat_where
                $course_where
          GROUP BY 1
          ORDER BY 4 $desc $nullpos, $pop_extra_sort 5 DESC $nullpos, 3 DESC
          LIMIT $core_limit
        ) AS core_query
) (SELECT * FROM w LIMIT $filters{check_limit} OFFSET $filters{skip_check})
        UNION ALL
  SELECT NULL,NULL,NULL,COUNT(*),COUNT(*),COUNT(*),0,0,NULL,NULL FROM w;
SQL

    warn $sql if $self->QueryParser->debug;
    return $sql;

}

sub is_org_visible {
    my $org = shift;
    if ( defined($org) ) {
        my $non_inherited_vis_gf = shift || $U->get_global_flag('opac.org_unit.non_inherited_visibility');
        my $method = shift || 'opac_visible';
        return 0 if (!$U->is_true($org->$method));

        return 1 if ($U->is_true($non_inherited_vis_gf->enabled));

        while ($org = $org->parent_ou) {
            return 0 if (!$U->is_true($org->$method));
        }
        return 1; 
    }  else {
        return 0;
    }
}

sub flesh_parents {
    my $t = shift;
    my $kids = $t->children;
    if ($kids && @$kids) {
        map {$_->parent_ou($t); flesh_parents($_)} @$kids;
    }
}

sub unflesh_parents {
    my $t = shift;
    my $kids = $t->children;
    if ($kids && @$kids) {
        map {$_->parent_ou($t->id); unflesh_parents($_)} @$kids;
    }
}

sub flatten {
    my $self = shift;

    die 'ERROR: nesting too deep or boolean list too long' if ($self->plan_level > 40);

    my $from = shift || '';
    my $where = shift || '';
    my $with = '';
    my %vis_filter = ( c_attr => [], b_attr => [] );
    my $uses_bre = 0;
    my $uses_mrd = 0;
    my $uses_mrv = 0;

    my @rank_list;
    for my $node ( @{$self->query_nodes} ) {

        if (ref($node)) {
            if ($node->isa( 'QueryParser::query_plan::node' )) {

                unless (@{$node->only_atoms}) {
                    push @rank_list, '1';
                    $where .= 'TRUE';
                    next;
                }

                my @bump_fields;
                my @field_ids;
                if (@{$node->fields} > 0) {
                    @bump_fields = @{$node->fields};

                    @field_ids = grep defined, (
                        map {
                            $self->QueryParser->search_field_ids_by_class(
                                $node->classname, $_
                            )->[0]
                        } @bump_fields
                    );
                } else {
                    @bump_fields = @{$self->QueryParser->search_fields->{$node->classname}};
                }

                # use search_field_list to handle virtual index defs
                my $search_field_list = $self->QueryParser->search_field_ids_by_class($node->classname);
                $search_field_list = [@field_ids] if (@field_ids);

                my $table = $node->table;
                my $ctable = $node->combined_table;
                my $talias = $node->table_alias;

                my $node_rank = 'COALESCE(' . $node->rank . " * ${talias}.weight * 1000, 0.0)";

                my $search_cte = ",\n $talias AS (\n"
                      . ${spc} x 5 . "SELECT fe.*, fe_weight.weight, ${talias}_xq.tsq, ${talias}_xq.tsq_rank /* search */\n"
                      . ${spc} x 6 . "FROM  $table AS fe\n"
                      . ${spc} x 7 . "JOIN config.metabib_field AS fe_weight ON (fe_weight.id = fe.field)";

                if ($node->dummy_count < @{$node->only_atoms} or @{$node->phrases}) {
                    $with .= ",\n     " if $with;
                    $with .= "${talias}_xq AS (SELECT ". $node->tsquery ." AS tsq,". $node->tsquery_rank ." AS tsq_rank )";
                    if ($node->combined_search) {
                        $search_cte .= "\n" . ${spc} x 7 . "JOIN $ctable AS com ON (com.record = fe.source";
                        if (@field_ids) {
                            $search_cte .= " AND com.metabib_field IN (" . join(',',@field_ids) . "))";
                        } else {
                            $search_cte .= " AND com.metabib_field IS NULL)";
                        }
                        $search_cte .= "\n" . ${spc} x 7 . "JOIN ${talias}_xq ON (com.index_vector @@ ${talias}_xq.tsq)";
                    } else {
                        $search_cte .= "\n" . ${spc} x 7 . "JOIN ${talias}_xq ON (fe.index_vector @@ ${talias}_xq.tsq)";
                    }
                } else {
                    $search_cte .= "\n" . ${spc} x 7 . ", (SELECT NULL::tsquery AS tsq, NULL::tsquery AS tsq_rank ) AS ${talias}_xq";
                }

                if (@field_ids) {
                    $search_cte .= "\n" . ${spc} x 6 . "WHERE fe_weight.id IN  (" .
                        join(',', @field_ids) . ")";
                }

                # Even though virtual fields have all the real field data in
                # their combined version, and thus a search against the real
                # fields is not necessary to match records, we still want to
                # UNION them in so we can get their virtual weight if they
                # would match a search directly against them.
                if ($node->dummy_count < @{$node->only_atoms} ) { # no point in searching real fields with no search terms
                    for my $possible_vfield (@$search_field_list) {
                        my $real_fields = $self->QueryParser->search_field_virtual_map->{by_virt}->{$possible_vfield};
                        if ($real_fields and @$real_fields) { # this is a virt field
                            my %vtable_field_map;

                            # UNION in the others ... group by class
                            for my $real_field (@$real_fields) {
                                my $natural_field = $self->QueryParser->search_field_id_map->{by_id}{$$real_field{real}};

                                $node->add_vfield($$real_field{real});
                                $logger->debug("Looking up virtual field for real field $$real_field{real}");
                                my $vtable = $node->table(
                                    $self->QueryParser
                                        ->search_field_class_by_id($$real_field{real})
                                        ->{classname}
                                );
                                $vtable_field_map{$vtable} ||= [];
                                push(@{$vtable_field_map{$vtable}}, $$real_field{real})
                                    if ($$real_field{weight} != $$natural_field{weight});
                            }

                            for my $vtable (keys %vtable_field_map) {
                                my $rfields = $vtable_field_map{$vtable};
                                next unless (@$rfields);

                                # NOTE: only real fields that match the (component) tsquery will
                                #       get to contribute to and increased rank for the record.
                                $search_cte .= "\n" . ${spc} x 8 . "UNION ALL\n"
                                      . ${spc} x 5 . "SELECT fe.id, fe.source, fe.field, fe.value, fe.index_vector, "
                                      . "fe_weight.weight, ${talias}_xq.tsq, ${talias}_xq.tsq_rank /* virtual field addition */\n"
                                      . ${spc} x 6 . "FROM  $vtable AS fe\n"
                                      . ${spc} x 7 . "JOIN config.metabib_field_virtual_map AS fe_weight ON ("
                                            ."fe_weight.virtual = $possible_vfield AND "
                                            ."fe_weight.real IN (".join(',',@$rfields).") AND "
                                            ."fe_weight.real = fe.field)\n"
                                      . ${spc} x 7 . "JOIN ${talias}_xq ON (fe.index_vector @@ ${talias}_xq.tsq)"
                                ;
                            }
                        }
                    }
                }

                $with .= $search_cte . ')';
                $from .= "\n" . ${spc} x 4 . "LEFT JOIN $talias ON (m.source = ${talias}.source)";

                my %used_bumps;
                my @bumps;
                my @bumpmults;
                for my $field ( @bump_fields ) {
                    my $bumps = $self->QueryParser->find_relevance_bumps( $node->classname => $field );
                    for my $b (keys %$bumps) {
                        next if (!$$bumps{$b}{active});
                        next if ($used_bumps{$b});
                        $used_bumps{$b} = 1;

                        next if ($$bumps{$b}{multiplier} == 1); # optimization to remove unneeded bumps
                        push @bumps, $b;
                        push @bumpmults, $$bumps{$b}{multiplier};
                    }
                }

                if(scalar @bumps > 0 && scalar @{$node->only_positive_atoms} > 0) {
                    # Note: Previous rank function used search_normalize outright. Duplicating that here.
                    $node_rank .= "\n" . ${spc} x 5 . "* COALESCE(evergreen.rel_bump(('{' || quote_literal(search_normalize(";
                    $node_rank .= join(")) || ',' || quote_literal(search_normalize(",map { $self->QueryParser->quote_phrase_value($_->content) } @{$node->only_positive_atoms});
                    $node_rank .= ")) || '}')::TEXT[], " . $node->table_alias . ".value, '{" . join(",",@bumps) . "}'::TEXT[], '{" . join(",",@bumpmults) . "}'::NUMERIC[]),1.0)";
                }

                my $NOT = '';
                $NOT = 'NOT ' if $node->negate;

                $where .= "$NOT(" . $talias . ".id IS NOT NULL";
                for my $atom (@{$node->only_real_atoms}) { # left and right anchored substring match (prefix / suffix search)
                    next unless $atom->{content} && $atom->{content} =~ /(^\^|\$$)/;
                    $where .= " AND ${talias}.value ~* ".$self->QueryParser->quote_phrase_value($atom->{content});
                }
                $where .= ')';

                push @rank_list, $node_rank;

            } elsif ($node->isa( 'QueryParser::query_plan::facet' )) {

                my $talias = $node->table_alias;

                my @field_ids;
                if (@{$node->fields} > 0) {
                    push(@field_ids, $self->QueryParser->facet_field_ids_by_class( $node->classname, $_ )->[0]) for (@{$node->fields});
                } else {
                    @field_ids = @{ $self->QueryParser->facet_field_ids_by_class( $node->classname ) };
                }

                my $join_type = ($node->negate or !$self->top_plan) ? 'LEFT' : 'INNER';
                $from .= "\n${spc}$join_type JOIN /* facet */ metabib.facet_entry $talias ON (\n"
                      . ${spc} x 2 . "m.source = ${talias}.source\n"
                      . ${spc} x 2 . "AND SUBSTRING(${talias}.value,1,1024) IN ("
                      . join(",", map { $self->QueryParser->quote_value($_) } @{$node->values}) . ")\n"
                      . ${spc} x 2 ."AND ${talias}.field IN (". join(',', @field_ids) . ")\n"
                      . "${spc})";

                if ($join_type ne 'INNER') {
                    my $NOT = $node->negate ? '' : ' NOT';
                    $where .= "${talias}.id IS$NOT NULL";
                } elsif ($where ne '') {
                    # Strip extra joiner
                    $where =~ s/(\s|\n)+(AND|OR)\s$//;
                }

            } else {
                my $subnode = $node->flatten;

                # strip the trailing bool from the previous loop if there is 
                # nothing to add to the where within this loop.
                if ($$subnode{where} eq '') {
                    $where =~ s/(\s|\n)+(AND|OR)\s$//;
                }

                push(@rank_list, @{$$subnode{rank_list}});
                $from .= $$subnode{from};

                my $NOT = '';
                $NOT = 'NOT ' if $node->negate;

                if ($$subnode{where} ne '') {
                    $where .= "$NOT(\n"
                           . ${spc} x ($self->plan_level + 6) . $$subnode{where} . "\n"
                           . ${spc} x ($self->plan_level + 5) . ')';
                }

                if ($$subnode{with}) {
                    $with .= ",\n     " if $with;
                    $with .= $$subnode{with};
                }

                $uses_bre = $$subnode{uses_bre};
                $uses_mrd = $$subnode{uses_mrd};
                $uses_mrv = $$subnode{uses_mrv};
            }
        } else {

            warn "flatten(): appending WHERE bool to: $where\n" if $self->QueryParser->debug;

            if ($where ne '') {
                $where .= "\n" . ${spc} x ( $self->plan_level + 5 ) . 'AND ' if ($node eq '&');
                $where .= "\n" . ${spc} x ( $self->plan_level + 5 ) . 'OR ' if ($node eq '|');
            }
        }
    }

    my $joiner = "\n" . ${spc} x ( $self->plan_level + 5 ) . ($self->joiner eq '&' ? 'AND ' : 'OR ');

    my ($depth_filter) = grep { $_->name eq 'depth' } @{$self->filters};
    if ($depth_filter and @{$depth_filter->args} == 1) {
        $depth_filter = $depth_filter->args->[0];
    }

    my $ot = $U->get_org_tree;
    my $site_org = $ot;
    my $negate = 'FALSE';

    my @lasso_list;
    my ($lasso_filter) = grep { $_->name eq 'lasso' } @{$self->filters};
    if ($lasso_filter and @{$lasso_filter->args} == 1) {
        $negate = $lasso_filter->negate ? 'TRUE' : 'FALSE';

        my $lasso = $lasso_filter->args->[0];
        if ($lasso !~ /^\d+$/) {
            $lasso = $U->find_lasso_by_name($lasso);
        }

        if ($lasso) {
            $lasso = $lasso->id if (ref $lasso);
            @lasso_list = map { $_->org_unit } @{ $U->fetch_lasso_org_maps($lasso) };
        }
    }


    if (!@lasso_list) {
        my ($site_filter) = grep { $_->name eq 'site' } @{$self->filters};
        if ($site_filter and @{$site_filter->args} == 1) {
           $negate = $site_filter->negate ? 'TRUE' : 'FALSE';

           my $sitename = $site_filter->args->[0];
           $site_org = $U->find_org_by_shortname($ot, $sitename) || $ot;
        }
    }

    my $dorgs = scalar(@lasso_list) ? [@lasso_list] : $U->get_org_descendants($site_org->id, $depth_filter);
    my $aorgs = $U->get_org_ancestors($site_org->id);

    flesh_parents($ot);
    my $visibility_method = ($self->find_modifier('staff')) ? 'staff_catalog_visible' : 'opac_visible';
    my $non_inherited_vis_gf = $U->get_global_flag('opac.org_unit.non_inherited_visibility');
    $dorgs = [ grep { is_org_visible($U->find_org($ot,$_), $non_inherited_vis_gf, $visibility_method) } @$dorgs ];
    $aorgs = [ grep { is_org_visible($U->find_org($ot,$_), $non_inherited_vis_gf, $visibility_method) } @$aorgs ];
    unflesh_parents($ot);

    push @{$vis_filter{'c_attr'}},
        "search.calculate_visibility_attribute_test('circ_lib','{".join(',', @$dorgs)."}',$negate)";

    # NOTE: both lassos and shelving locations preclude Located URI search
    if (!$lasso_filter && !$self->find_filter('locations') && !$self->find_filter('location_groups')) {
        my $lorgs = [@$aorgs];
        my $luri_as_copy_gf = $U->get_global_flag('opac.located_uri.act_as_copy');
        push @$lorgs, @$dorgs if ($luri_as_copy_gf and $U->is_true($luri_as_copy_gf->enabled));

        $uses_bre = 1;
        push @{$vis_filter{'b_attr'}},
            "search.calculate_visibility_attribute_test('luri_org','{".join(',', @$lorgs)."}',$negate)";
    }

    my @dlist = ();
    my $common = 0;
    # for each dynamic filter, build more of the WHERE clause
    for my $filter (@{$self->filters}) {
        my $NOT = $filter->negate ? 'NOT ' : '';
        if (grep { $_ eq $filter->name } @{ $self->QueryParser->dynamic_filters }) {

            my $fname = $filter->name;
            $fname = 'item_lang' if $fname eq 'language'; #XXX filter aliases 

            warn "flatten(): processing dynamic filter ". $filter->name ."\n"
                if $self->QueryParser->debug;

            my $vlist_query;
            ($vlist_query, $common) = $self->dynamic_filter_compile( $fname, $filter->args, $filter->negate );

            # bool joiner for intra-plan nodes/filters
            push(@dlist, $self->joiner) if @dlist;
            push(@dlist, $vlist_query);
            $uses_mrv = 1;
        } else {
            if ($filter->name eq 'before') {
                if (@{$filter->args} == 1) {
                    $where .= $joiner if $where ne '';
                    $where .= "${NOT}COALESCE(pubdate_t.value <= "
                           . $self->QueryParser->quote_value($filter->args->[0])
                           . ", false)";
                }
            } elsif ($filter->name eq 'after') {
                if (@{$filter->args} == 1) {
                    $where .= $joiner if $where ne '';
                    $where .= "${NOT}COALESCE(pubdate_t.value >= "
                           . $self->QueryParser->quote_value($filter->args->[0])
                           . ", false)";
                }
            } elsif ($filter->name eq 'during') {
                if (@{$filter->args} == 1) {
                    $where .= $joiner if $where ne '';
                    $where .= "${NOT}COALESCE("
                           . $self->QueryParser->quote_value($filter->args->[0])
                           . " BETWEEN pubdate_t.value AND (mrd.attrs->'date2'), false)";
                    $uses_mrd = 1;
                }
            } elsif ($filter->name eq 'between') {
                if (@{$filter->args} == 2) {
                    $where .= $joiner if $where ne '';
                    $where .= "${NOT}COALESCE(pubdate_t.value BETWEEN "
                           . $self->QueryParser->quote_value($filter->args->[0])
                           . " AND "
                           . $self->QueryParser->quote_value($filter->args->[1])
                           . ", false)";
                }
            } elsif ($filter->name eq 'container') {
                if (@{$filter->args} >= 3) {
                    my ($class, $ctype, $cid, $token) = @{$filter->args};
                    my $perm_join = '';
                    my $rec_join = '';
                    my $rec_field = 'ci.target_biblio_record_entry';
                    if ($class eq 'bre') {
                        $class = 'biblio_record_entry';
                    } elsif ($class eq 'acn') {
                        $class = 'call_number';
                        $rec_field = 'cn.record';
                        $rec_join = 'JOIN asset.call_number cn ON (ci.target_call_number = cn.id)';
                    } elsif ($class eq 'acp') {
                        $class = 'copy';
                        $rec_field = 'cn.record';
                        $rec_join = 'JOIN asset.copy cp ON (ci.target_copy = cp.id) JOIN asset.call_number cn ON (cp.call_number = cn.id)';
                    } else {
                        $class = undef;
                    }

                    if ($class) {
                        my ($u,$e) = $apputils->checksesperm($token) if ($token);
                        $perm_join = ' OR c.owner = ' . $u->id if ($u && !$e);

                        my $filter_alias = "$filter";
                        $filter_alias =~ s/^.*\(0(x[0-9a-fA-F]+)\)$/$1/go;
                        $filter_alias =~ s/\|/_/go;

                        $with .= ",\n     " if $with;
                        $with .= "container_${filter_alias} AS (\n";
                        $with .= "       SELECT $rec_field AS record FROM container.${class}_bucket_item ci\n"
                               . "             JOIN container.${class}_bucket c ON (c.id = ci.bucket) $rec_join\n"
                               . "       WHERE c.btype = " . $self->QueryParser->quote_value($ctype) . "\n"
                               . "             AND c.id = " . $self->QueryParser->quote_value($cid) . "\n"
                               . "             AND (c.pub IS TRUE$perm_join)\n";
                        if ($class eq 'copy') {
                            $with .= "       UNION\n"
                                   . "       SELECT pr.peer_record AS record FROM container.copy_bucket_item ci\n"
                                   . "             JOIN container.copy_bucket c ON (c.id = ci.bucket)\n"
                                   . "             JOIN biblio.peer_bib_copy_map pr ON ci.target_copy = pr.target_copy\n"
                                   . "       WHERE c.btype = " . $self->QueryParser->quote_value($ctype) . "\n"
                                   . "             AND c.id = " . $self->QueryParser->quote_value($cid) . "\n"
                                   . "             AND (c.pub IS TRUE$perm_join)\n";
                        }
                        $with .= "     )";

                        my $optimize_join = 1 if $self->top_plan and !$NOT;
                        $from .= "\n" . ${spc} x 3 . ( $optimize_join ? 'INNER' : 'LEFT') . " JOIN container_${filter_alias} ON container_${filter_alias}.record = m.source";

                        if (!$optimize_join) {
                            $where .= $joiner if $where ne '';
                            $where .= "(container_${filter_alias} IS " . ( $NOT ? 'NULL)' : 'NOT NULL)');
                        }
                    }
                }
            } elsif ($filter->name eq 'copy_tag') {
                my $valid_copy_tag_search = 0;
                my $copy_tag_type;
                my $tag_value;
                if (@{$filter->args} >= 2) { # must have at least two parts, tag (or *) and terms
                    my @fargs = @{$filter->args};
                    $copy_tag_type = shift(@fargs);
                    $tag_value = join(' ', @fargs);
                    $valid_copy_tag_search = 1;
                }
                if ($valid_copy_tag_search) {
                    my $norm_value = search_normalize($tag_value);
                    my @tokens = split /\s+/, $norm_value;
                    
                    my $filter_alias = "$filter";
                    $filter_alias =~ s/^.*\(0(x[0-9a-fA-F]+)\)$/$1/go;
                    $filter_alias =~ s/\|/_/go;

                    $with .= ",\n     " if $with;
                    $with .= "copy_tag_${filter_alias} AS (\n";
                    $with .= "       SELECT cn.record AS record FROM config.copy_tag_type cctt\n";
                    $with .= "             JOIN asset.copy_tag acpt ON (cctt.code = acpt.tag_type)\n";
                    $with .= "             JOIN asset.copy_tag_copy_map acptcm ON (acpt.id = acptcm.tag)\n";
                    $with .= "             JOIN asset.copy cp ON (acptcm.copy = cp.id)\n";
                    $with .= "             JOIN asset.call_number cn ON (cp.call_number = cn.id)\n";
                    $with .= "       WHERE 1 = 1 \n";
                    $with .= "       AND cp.circ_lib IN (" . join(',', @$dorgs) . ")\n";
                    if ($copy_tag_type ne '*') {
                        $with .= "             AND cctt.code = " . $self->QueryParser->quote_value($copy_tag_type) . "\n";
                    }
                    if (@tokens) {
                        $with .= '             AND acpt.value @@ to_tsquery(' . $self->QueryParser->quote_value(join(' & ', @tokens)) . ")\n";
                    }
                    if (!$self->find_modifier('staff')) {
                        $with .= "             AND acpt.pub IS TRUE\n";
                    }
                    $with .= "     )";

                    my $optimize_join = 1 if $self->top_plan and !$NOT;
                    $from .= "\n" . ${spc} x 3 . ( $optimize_join ? 'INNER' : 'LEFT') . " JOIN copy_tag_${filter_alias} ON copy_tag_${filter_alias}.record = m.source";

                    if (!$optimize_join) {
                        $where .= $joiner if $where ne '';
                        $where .= "(copy_tag_${filter_alias} IS " . ( $NOT ? 'NULL)' : 'NOT NULL)');
                    }
                }
            } elsif ($filter->name eq 'record_list') {
                if (@{$filter->args} > 0) {
                    my $key = 'm.source';
                    $key = 'm.metarecord' if (grep {$_->name eq 'metarecord' or $_->name eq 'metabib'} @{$self->QueryParser->parse_tree->modifiers});
                    $where .= $joiner if $where ne '';
                    $where .= "$key ${NOT}IN (" . join(',', map { $self->QueryParser->quote_value($_) } @{$filter->args}) . ')';
                }

            } elsif ($filter->name eq 'locations') {
                if (@{$filter->args} > 0) {
                    my $negate = $filter->negate ? 'TRUE' : 'FALSE';
                    my $filter_args = join(",", map(int, @{$filter->args}));
                    push @{$vis_filter{'c_attr'}},
                        "search.calculate_visibility_attribute_test('location','{$filter_args}',$negate)";
                }

            } elsif ($filter->name eq 'location_groups') {
                if (@{$filter->args} > 0) {
                    my $negate = $filter->negate ? 'TRUE' : 'FALSE';
                    my $filter_args = join(",", map(int, @{$filter->args}));
                    push @{$vis_filter{'c_attr'}},
                        "search.calculate_visibility_attribute_test('location',(SELECT ARRAY_AGG(location) FROM asset.copy_location_group_map WHERE lgroup IN ($filter_args)),$negate)";
                }

            } elsif ($filter->name eq 'statuses') {
                if (@{$filter->args} > 0) {
                    my $negate = $filter->negate ? 'TRUE' : 'FALSE';
                    push @{$vis_filter{'c_attr'}},
                        "search.calculate_visibility_attribute_test('status','{".join(',', @{$filter->args})."}',$negate)";
                }

            } elsif ($filter->name eq 'has_browse_entry') {
                if (@{$filter->args} >= 2) {
                    my $entry = int(shift @{$filter->args});
                    my $fields = join(",", map(int, @{$filter->args}));
                    $from .= "\n" . $spc x 3 . sprintf("INNER JOIN metabib.browse_entry_def_map mbedm ON (mbedm.source = m.source AND mbedm.entry = %d AND mbedm.def IN (%s))", $entry, $fields);
                }
            } elsif ($filter->name eq 'edit_date' or $filter->name eq 'create_date') {
                # bre.create_date and bre.edit_date filtering
                my $datefilter = $filter->name;

                $uses_bre = 1;

                if ($filter && $filter->args && scalar(@{$filter->args}) > 0 && scalar(@{$filter->args}) < 3) {
                    my ($cstart, $cend) = @{$filter->args};
        
                    if (!$cstart and !$cend) {
                        # useless use of filter
                    } elsif (!$cstart or $cstart eq '-infinity') { # no start supplied
                        if ($cend eq 'infinity') {
                            # useless use of filter
                        } else {
                            # "before $cend"
                            $cend = clean_ISO8601($cend);
                            $where .= $joiner if $where ne '';
                            $where .= "bre.$datefilter <= \$_$$\$$cend\$_$$\$";
                        }
            
                    } elsif (!$cend or $cend eq 'infinity') { # no end supplied
                        if ($cstart eq '-infinity') {
                            # useless use of filter
                        } else { # "after $cstart"
                            $cstart = clean_ISO8601($cstart);
                            $where .= $joiner if $where ne '';
                            $where .= "bre.$datefilter >= \$_$$\$$cstart\$_$$\$";
                        }
                    } else { # both supplied
                        # "between $cstart and $cend"
                        $cstart = clean_ISO8601($cstart);
                        $cend = clean_ISO8601($cend);
                        $where .= $joiner if $where ne '';
                        $where .= "bre.$datefilter BETWEEN \$_$$\$$cstart\$_$$\$ AND \$_$$\$$cend\$_$$\$";
                    }
                }
            } elsif ($filter->name eq 'bib_source') {
                if (@{$filter->args} > 0) {
                    $uses_bre = 1;
                    my $negate = $filter->negate ? 'TRUE' : 'FALSE';
                    push @{$vis_filter{'b_attr'}},
                        "search.calculate_visibility_attribute_test('source','{".join(',', @{$filter->args})."}',$negate)";
                }
            } elsif ($filter->name eq 'from_metarecord') {
                if (@{$filter->args} > 0) {
                    my $key = 'm.metarecord';
                    $where .= $joiner if $where ne '';
                    $where .= "$key ${NOT}IN (" . join(',', map { $self->QueryParser->quote_value($_) } @{$filter->args}) . ')';
                }
            }
        }
    }

    if (@dlist) {

        $where .= $joiner if $where ne '';
        if ($common) { # Use a function wrapper to inform PG of the non-rareness of one or more filter elements
            $where .= sprintf(
                'evergreen.query_int_wrapper(mrv.vlist, \'%s\')',
                join('', @dlist)
            );
        } else {
            $where .= sprintf(
                'mrv.vlist @@ \'%s\'',
                join('', @dlist)
            );
        }
    }

    warn "flatten(): full filter where => $where\n" if $self->QueryParser->debug;

    return {
        rank_list => \@rank_list,
        from => $from,
        where => $where,
        with => $with,
        vis_filter => \%vis_filter,
        uses_bre => $uses_bre,
        uses_mrv => $uses_mrv,
        uses_mrd => $uses_mrd
    };
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

sub fields {
    my $self = shift;
    my ($classname,@fields) = split '\|', $self->name;
    return \@fields;
}

sub table_alias {
    my $self = shift;
    my $suffix = shift;

    my $table_alias = "$self";
    $table_alias =~ s/^.*\(0(x[0-9a-fA-F]+)\)$/$1/go;
    $table_alias .= '_' . $self->name;
    $table_alias =~ s/\|/_/go;
    $table_alias .= "_$suffix" if ($suffix);

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

    return $self->sql("''::tsquery") if $self->{dummy};

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
    my $joiner = ' || ';
    $joiner = ' && ' if $self->prefix eq '!'; # Negative atoms should be "none of the variants" instead of "any of the variants"

    $prefix = "'$prefix' ||" if $prefix;
    my $suffix_op = '';
    my $suffix_after = '';

    $suffix_op = ":$suffix" if $suffix;
    $suffix_after = "|| '$suffix_op'" if $suffix;

    my $ts_configs = $self->node->ts_configs;

    my @sql_set = ();
    for my $ts_config (@$ts_configs) {
        push @sql_set, "to_tsquery('$ts_config', COALESCE(NULLIF($prefix '(' || btrim(regexp_replace($sql,E'(?:\\\\s+|:)','$suffix_op&','g'),'&|') $suffix_after || ')', $prefix '()'), ''))";
    }

    $sql = join($joiner, @sql_set);
    $sql = '(' . $sql . ')' if (scalar(@$ts_configs) > 1);

    return $self->sql($sql);
}

#-------------------------------
package OpenILS::Application::Storage::Driver::Pg::QueryParser::query_plan::node;
use base 'QueryParser::query_plan::node';
use List::MoreUtils qw/uniq/;
use Data::Dumper;

sub ts_configs {
    my $self = shift;
    my $ts_configs = $self->{ts_configs} || [];

    if (!@$ts_configs) {
        my $classname = $self->classname;
        my $lang;
        my $filter = $self->plan->find_filter('preferred_language');
        $lang ||= $filter->args->[0] if ($filter && $filter->args);
        $lang ||= $self->plan->QueryParser->default_preferred_language;

        my $fields = $self->fields;
        if (!@$fields) {
            $ts_configs = $self->plan->QueryParser->class_ts_config($classname, $lang);
        } else {
            for my $field (@$fields) {
                push @$ts_configs, @{$self->plan->QueryParser->field_ts_config($classname, $field, $lang)};
            }
        }
        $ts_configs = [keys %{{map { $_ => 1 } @$ts_configs}}];

        # Assume we want exact if none otherwise provided.
        # Because we can reasonably expect this to exist
        $ts_configs = ['simple'] unless (scalar @$ts_configs);
        $self->{ts_configs} = $ts_configs;
    }

    return $ts_configs;
}

sub abstract_node_additions {
    my $self = shift;
    my $aq = shift;

    my $hm = $self->plan
                ->QueryParser
                ->parse_tree
                ->get_abstract_data('highlight_map') // {};

    return unless ref($hm);

    my $field_set = $self->fields;
    $field_set = $self->plan->QueryParser->search_fields->{$self->classname}
        if (!@$field_set);

    my @field_ids = grep defined, (
        map {
            $self->plan->QueryParser->search_field_ids_by_class(
                $self->classname, $_
            )->[0]
        } @$field_set
    );

    push @field_ids, @{$self->{vfields}} if $self->{vfields};

    my $ts_query = $self->tsquery_rank;

    # We need to rework the hash so fields are only ever pointed at once.
    # That means if a field is already being looked at elsewhere then we'll
    # need to separate it out and combine its preexisting tsqueries.  This
    # will be fairly brute-force, and could be improved later, likely, with
    # a clever algorithm.

    my %inverted_hm;
    for my $t (keys %$hm) {
        for my $f (@{$$hm{$t}}) {
            $inverted_hm{$f} = $t;
        }
    }

    # Then, loop over new fields and put them in the inverted hash.
    my @existing_fields = keys %inverted_hm;

    for my $f (@field_ids) {
        if (grep { $f == $_ } @existing_fields) { # We've seen the field, should we combine?
            my $t = $inverted_hm{$f};
            if ($t ne $ts_query) { # Different tsquery, do it!
                $t .= ' || '. $ts_query;
                $inverted_hm{$f} = $t;
            }
        } else { # New field
            $inverted_hm{$f} = $ts_query;
        }
    }

    # Now, flip it back over.
    $hm = {};
    for my $f (keys %inverted_hm) {
        my $t = $inverted_hm{$f};
        if ($$hm{$t}) {
            push @{$$hm{$t}}, $f;
        } else {
            $$hm{$t} = [$f];
        }
    }

    # finally, ask the database to give us an hstore literal
    my $hl_map_string = "";
    for my $tsq (keys %$hm) {
        my $field_list = join(',', @{$$hm{$tsq}});
        $hl_map_string .= ' || ' if $hl_map_string;
        $hl_map_string .= "hstore(($tsq)\:\:TEXT,'$field_list')";
    }

    my $calculated_hm = '';
    $calculated_hm = $self->plan->QueryParser->dbh->selectcol_arrayref(
        "SELECT $hl_map_string AS hm"
    )->[0] if ($hl_map_string);

    $self->plan
        ->QueryParser
        ->parse_tree
        ->set_abstract_data('highlight_map', $calculated_hm);
}

sub add_vfield {
    my $self = shift;
    my $vfield = shift;

    $self->{vfields} ||= [];
    push @{$self->{vfields}}, $vfield;
}

sub only_atoms {
    my $self = shift;

    $self->{dummy_count} = 0;

    my $atoms = $self->query_atoms;
    my @only_atoms;
    for my $a (@$atoms) {
        push(@only_atoms, $a) if (ref($a) && $a->isa('QueryParser::query_plan::node::atom'));
        $self->{dummy_count}++ if (ref($a) && $a->{dummy});
    }

    return \@only_atoms;
}

sub only_real_atoms {
    my $self = shift;

    my $atoms = $self->query_atoms;
    my @only_real_atoms;
    for my $a (@$atoms) {
        push(@only_real_atoms, $a) if (ref($a) && $a->isa('QueryParser::query_plan::node::atom') && !($a->{dummy}));
    }

    return \@only_real_atoms;
}

sub only_positive_atoms {
    my $self = shift;

    my $atoms = $self->query_atoms;
    my @only_positive_atoms;
    for my $a (@$atoms) {
        push(@only_positive_atoms, $a) if (ref($a) && $a->isa('QueryParser::query_plan::node::atom') && !($a->{dummy}) && ($a->{prefix} ne '!'));
    }

    return \@only_positive_atoms;
}

sub dummy_count {
    my $self = shift;
    return $self->{dummy_count};
}

sub table {
    my $self = shift;
    my $classname = shift || $self->classname;
    return 'metabib.' . $classname . '_field_entry';
}

sub combined_table {
    my $self = shift;
    my $classname = shift || $self->classname;
    return 'metabib.combined_' . $classname . '_field_entry';
}

sub combined_search {
    my $self = shift;
    return $self->plan->QueryParser->search_class_combined($self->classname);
}

sub table_alias {
    my $self = shift;
    my $suffix = shift;

    my $table_alias = "$self";
    $table_alias =~ s/^.*\(0(x[0-9a-fA-F]+)\)$/$1/go;
    $table_alias .= '_' . $self->requested_class;
    $table_alias =~ s/\|/_/go;
    $table_alias .= "_$suffix" if ($suffix);

    return $table_alias;
}

sub tsquery {
    my $self = shift;
    return $self->{tsquery} if ($self->{tsquery});

    for my $atom (@{$self->query_atoms}) {
        if (ref($atom)) {
            $self->{tsquery} .= "\n" . ${spc} x 3;
            $self->{tsquery} .= '(' x $atom->explicit_start if $atom->explicit_start;
            $self->{tsquery} .= $atom->sql;
            $self->{tsquery} .= ')' x $atom->explicit_end if $atom->explicit_end;
        } else {
            $self->{tsquery} .= $atom x 2;
        }
    }

    # any phrases that are more than empty or all-whitespace
    if (my @phrases = grep { /\S+/ } @{$self->phrases}) {
        my $neg = $self->negate ? '!!' : '';
        $self->{tsquery} ||= "''::tsquery";
        $self->{tsquery} .= ' && ' . join(
            ' && ',
            map { "${neg}phraseto_tsquery('simple', \$_$$\$$_\$_$$\$)" } @phrases
        );
    }

    return $self->{tsquery};
}

sub tsquery_rank {
    my $self = shift;
    return $self->{tsquery_rank} if ($self->{tsquery_rank});
    my @atomlines;

    for my $atom (@{$self->only_positive_atoms}) {
        push @atomlines, "\n" . ${spc} x 3 . $atom->sql;
    }
    $self->{tsquery_rank} = join(' ||', @atomlines);
    $self->{tsquery_rank} = "''::tsquery" unless $self->{tsquery_rank};

    # any non-negated phrases that are more than empty or all-whitespace
    if (!$self->negate) {
        if (my @phrases = grep { /\S+/ } @{$self->phrases}) {
            for my $tsc (@{$self->ts_configs}) {
                $self->{tsquery_rank} .= ' || ' . join(
                    ' || ',
                    map { "phraseto_tsquery('$tsc', \$_$$\$$_\$_$$\$)" } @phrases
                );
            }
        }
    }

    return $self->{tsquery_rank};
}

sub rank {
    my $self = shift;
    return $self->{rank} if ($self->{rank});

    my $rank_norm_map = $self->plan->QueryParser->custom_data->{rank_cd_weight_map};

    my $cover_density = 0;
    for my $norm ( keys %$rank_norm_map) {
        $cover_density += $$rank_norm_map{$norm} if ($self->plan->QueryParser->parse_tree->find_modifier($norm));
    }

    my $weights = join(', ', @{$self->plan->QueryParser->search_class_weights($self->classname)});

    return $self->{rank} = "ts_rank_cd('{" . $weights . "}', " . $self->table_alias . '.index_vector, ' . $self->table_alias . ".tsq_rank, $cover_density)";
}


1;

