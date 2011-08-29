use strict;
use warnings;

package QueryParser;
use OpenSRF::Utils::JSON;
our %parser_config = (
    QueryParser => {
        filters => [],
        modifiers => [],
        operators => { 
            'and' => '&&',
            'or' => '||',
            group_start => '(',
            group_end => ')',
            required => '+',
            disallowed => '-',
            modifier => '#'
        }
    }
);

sub facet_class_count {
    my $self = shift;
    return @{$self->facet_classes};
}

sub search_class_count {
    my $self = shift;
    return @{$self->search_classes};
}

sub filter_count {
    my $self = shift;
    return @{$self->filters};
}

sub modifier_count {
    my $self = shift;
    return @{$self->modifiers};
}

sub custom_data {
    my $class = shift;
    $class = ref($class) || $class;

    $parser_config{$class}{custom_data} ||= {};
    return $parser_config{$class}{custom_data};
}

sub operators {
    my $class = shift;
    $class = ref($class) || $class;

    $parser_config{$class}{operators} ||= {};
    return $parser_config{$class}{operators};
}

sub filters {
    my $class = shift;
    $class = ref($class) || $class;

    $parser_config{$class}{filters} ||= [];
    return $parser_config{$class}{filters};
}

sub modifiers {
    my $class = shift;
    $class = ref($class) || $class;

    $parser_config{$class}{modifiers} ||= [];
    return $parser_config{$class}{modifiers};
}

sub new {
    my $class = shift;
    $class = ref($class) || $class;

    my %opts = @_;

    my $self = bless {} => $class;

    for my $o (keys %{QueryParser->operators}) {
        $class->operator($o => QueryParser->operator($o)) unless ($class->operator($o));
    }

    for my $opt ( keys %opts) {
        $self->$opt( $opts{$opt} ) if ($self->can($opt));
    }

    return $self;
}

sub new_plan {
    my $self = shift;
    my $pkg = ref($self) || $self;
    return do{$pkg.'::query_plan'}->new( QueryParser => $self, @_ );
}

sub add_search_filter {
    my $pkg = shift;
    $pkg = ref($pkg) || $pkg;
    my $filter = shift;

    return $filter if (grep { $_ eq $filter } @{$pkg->filters});
    push @{$pkg->filters}, $filter;
    return $filter;
}

sub add_search_modifier {
    my $pkg = shift;
    $pkg = ref($pkg) || $pkg;
    my $modifier = shift;

    return $modifier if (grep { $_ eq $modifier } @{$pkg->modifiers});
    push @{$pkg->modifiers}, $modifier;
    return $modifier;
}

sub add_facet_class {
    my $pkg = shift;
    $pkg = ref($pkg) || $pkg;
    my $class = shift;

    return $class if (grep { $_ eq $class } @{$pkg->facet_classes});

    push @{$pkg->facet_classes}, $class;
    $pkg->facet_fields->{$class} = [];

    return $class;
}

sub add_search_class {
    my $pkg = shift;
    $pkg = ref($pkg) || $pkg;
    my $class = shift;

    return $class if (grep { $_ eq $class } @{$pkg->search_classes});

    push @{$pkg->search_classes}, $class;
    $pkg->search_fields->{$class} = [];
    $pkg->default_search_class( $pkg->search_classes->[0] ) if (@{$pkg->search_classes} == 1);

    return $class;
}

sub operator {
    my $class = shift;
    $class = ref($class) || $class;
    my $opname = shift;
    my $op = shift;

    return undef unless ($opname);

    $parser_config{$class}{operators} ||= {};
    $parser_config{$class}{operators}{$opname} = $op if ($op);

    return $parser_config{$class}{operators}{$opname};
}

sub facet_classes {
    my $class = shift;
    $class = ref($class) || $class;
    my $classes = shift;

    $parser_config{$class}{facet_classes} ||= [];
    $parser_config{$class}{facet_classes} = $classes if (ref($classes) && @$classes);
    return $parser_config{$class}{facet_classes};
}

sub search_classes {
    my $class = shift;
    $class = ref($class) || $class;
    my $classes = shift;

    $parser_config{$class}{classes} ||= [];
    $parser_config{$class}{classes} = $classes if (ref($classes) && @$classes);
    return $parser_config{$class}{classes};
}

sub add_query_normalizer {
    my $pkg = shift;
    $pkg = ref($pkg) || $pkg;
    my $class = shift;
    my $field = shift;
    my $func = shift;
    my $params = shift || [];

    # do not add if function AND params are identical to existing member
    return $func if (grep {
        $_->{function} eq $func and 
        OpenSRF::Utils::JSON->perl2JSON($_->{params}) eq OpenSRF::Utils::JSON->perl2JSON($params)
    } @{$pkg->query_normalizers->{$class}->{$field}});

    push(@{$pkg->query_normalizers->{$class}->{$field}}, { function => $func, params => $params });

    return $func;
}

sub query_normalizers {
    my $pkg = shift;
    $pkg = ref($pkg) || $pkg;

    my $class = shift;
    my $field = shift;

    $parser_config{$pkg}{normalizers} ||= {};
    if ($class) {
        if ($field) {
            $parser_config{$pkg}{normalizers}{$class}{$field} ||= [];
            return $parser_config{$pkg}{normalizers}{$class}{$field};
        } else {
            return $parser_config{$pkg}{normalizers}{$class};
        }
    }

    return $parser_config{$pkg}{normalizers};
}

sub add_filter_normalizer {
    my $pkg = shift;
    $pkg = ref($pkg) || $pkg;
    my $filter = shift;
    my $func = shift;
    my $params = shift || [];

    return $func if (grep { $_ eq $func } @{$pkg->filter_normalizers->{$filter}});

    push(@{$pkg->filter_normalizers->{$filter}}, { function => $func, params => $params });

    return $func;
}

sub filter_normalizers {
    my $pkg = shift;
    $pkg = ref($pkg) || $pkg;

    my $filter = shift;

    $parser_config{$pkg}{filter_normalizers} ||= {};
    if ($filter) {
        $parser_config{$pkg}{filter_normalizers}{$filter} ||= [];
        return $parser_config{$pkg}{filter_normalizers}{$filter};
    }

    return $parser_config{$pkg}{filter_normalizers};
}

sub default_search_class {
    my $pkg = shift;
    $pkg = ref($pkg) || $pkg;
    my $class = shift;
    $QueryParser::parser_config{$pkg}{default_class} = $pkg->add_search_class( $class ) if $class;

    return $QueryParser::parser_config{$pkg}{default_class};
}

sub remove_facet_class {
    my $pkg = shift;
    $pkg = ref($pkg) || $pkg;
    my $class = shift;

    return $class if (!grep { $_ eq $class } @{$pkg->facet_classes});

    $pkg->facet_classes( [ grep { $_ ne $class } @{$pkg->facet_classes} ] );
    delete $QueryParser::parser_config{$pkg}{facet_fields}{$class};

    return $class;
}

sub remove_search_class {
    my $pkg = shift;
    $pkg = ref($pkg) || $pkg;
    my $class = shift;

    return $class if (!grep { $_ eq $class } @{$pkg->search_classes});

    $pkg->search_classes( [ grep { $_ ne $class } @{$pkg->search_classes} ] );
    delete $QueryParser::parser_config{$pkg}{fields}{$class};

    return $class;
}

sub add_facet_field {
    my $pkg = shift;
    $pkg = ref($pkg) || $pkg;
    my $class = shift;
    my $field = shift;

    $pkg->add_facet_class( $class );

    return { $class => $field }  if (grep { $_ eq $field } @{$pkg->facet_fields->{$class}});

    push @{$pkg->facet_fields->{$class}}, $field;

    return { $class => $field };
}

sub facet_fields {
    my $class = shift;
    $class = ref($class) || $class;

    $parser_config{$class}{facet_fields} ||= {};
    return $parser_config{$class}{facet_fields};
}

sub add_search_field {
    my $pkg = shift;
    $pkg = ref($pkg) || $pkg;
    my $class = shift;
    my $field = shift;

    $pkg->add_search_class( $class );

    return { $class => $field }  if (grep { $_ eq $field } @{$pkg->search_fields->{$class}});

    push @{$pkg->search_fields->{$class}}, $field;

    return { $class => $field };
}

sub search_fields {
    my $class = shift;
    $class = ref($class) || $class;

    $parser_config{$class}{fields} ||= {};
    return $parser_config{$class}{fields};
}

sub add_search_class_alias {
    my $pkg = shift;
    $pkg = ref($pkg) || $pkg;
    my $class = shift;
    my $alias = shift;

    $pkg->add_search_class( $class );

    return { $class => $alias }  if (grep { $_ eq $alias } @{$pkg->search_class_aliases->{$class}});

    push @{$pkg->search_class_aliases->{$class}}, $alias;

    return { $class => $alias };
}

sub search_class_aliases {
    my $class = shift;
    $class = ref($class) || $class;

    $parser_config{$class}{class_map} ||= {};
    return $parser_config{$class}{class_map};
}

sub add_search_field_alias {
    my $pkg = shift;
    $pkg = ref($pkg) || $pkg;
    my $class = shift;
    my $field = shift;
    my $alias = shift;

    return { $class => { $field => $alias } }  if (grep { $_ eq $alias } @{$pkg->search_field_aliases->{$class}{$field}});

    push @{$pkg->search_field_aliases->{$class}{$field}}, $alias;

    return { $class => { $field => $alias } };
}

sub search_field_aliases {
    my $class = shift;
    $class = ref($class) || $class;

    $parser_config{$class}{field_alias_map} ||= {};
    return $parser_config{$class}{field_alias_map};
}

sub remove_facet_field {
    my $pkg = shift;
    $pkg = ref($pkg) || $pkg;
    my $class = shift;
    my $field = shift;

    return { $class => $field }  if (!$pkg->facet_fields->{$class} || !grep { $_ eq $field } @{$pkg->facet_fields->{$class}});

    $pkg->facet_fields->{$class} = [ grep { $_ ne $field } @{$pkg->facet_fields->{$class}} ];

    return { $class => $field };
}

sub remove_search_field {
    my $pkg = shift;
    $pkg = ref($pkg) || $pkg;
    my $class = shift;
    my $field = shift;

    return { $class => $field }  if (!$pkg->search_fields->{$class} || !grep { $_ eq $field } @{$pkg->search_fields->{$class}});

    $pkg->search_fields->{$class} = [ grep { $_ ne $field } @{$pkg->search_fields->{$class}} ];

    return { $class => $field };
}

sub remove_search_field_alias {
    my $pkg = shift;
    $pkg = ref($pkg) || $pkg;
    my $class = shift;
    my $field = shift;
    my $alias = shift;

    return { $class => { $field => $alias } }  if (!$pkg->search_field_aliases->{$class}{$field} || !grep { $_ eq $alias } @{$pkg->search_field_aliases->{$class}{$field}});

    $pkg->search_field_aliases->{$class}{$field} = [ grep { $_ ne $alias } @{$pkg->search_field_aliases->{$class}{$field}} ];

    return { $class => { $field => $alias } };
}

sub remove_search_class_alias {
    my $pkg = shift;
    $pkg = ref($pkg) || $pkg;
    my $class = shift;
    my $alias = shift;

    return { $class => $alias }  if (!$pkg->search_class_aliases->{$class} || !grep { $_ eq $alias } @{$pkg->search_class_aliases->{$class}});

    $pkg->search_class_aliases->{$class} = [ grep { $_ ne $alias } @{$pkg->search_class_aliases->{$class}} ];

    return { $class => $alias };
}

sub debug {
    my $self = shift;
    my $q = shift;
    $self->{_debug} = $q if (defined $q);
    return $self->{_debug};
}

sub query {
    my $self = shift;
    my $q = shift;
    $self->{_query} = $q if (defined $q);
    return $self->{_query};
}

sub parse_tree {
    my $self = shift;
    my $q = shift;
    $self->{_parse_tree} = $q if (defined $q);
    return $self->{_parse_tree};
}

sub parse {
    my $self = shift;
    my $pkg = ref($self) || $self;
    warn " ** parse package is $pkg\n" if $self->debug;
    $self->parse_tree(
        $self->decompose(
            $self->query( shift() )
        )
    );

    return $self;
}

sub decompose {
    my $self = shift;
    my $pkg = ref($self) || $self;

    warn " ** decompose package is $pkg\n" if $self->debug;

    $_ = shift;
    my $current_class = shift || $self->default_search_class;

    my $recursing = shift || 0;
    my $phrase_helper = shift || 0;

    # Build the search class+field uber-regexp
    my $search_class_re = '^\s*(';
    my $first_class = 1;

    my %seen_classes;
    for my $class ( keys %{$pkg->search_fields} ) {

        for my $field ( @{$pkg->search_fields->{$class}} ) {

            for my $alias ( @{$pkg->search_field_aliases->{$class}{$field}} ) {
                $alias = qr/$alias/;
                s/(^|\s+)$alias[:=]/$1$class\|$field:/g;
            }
        }

        $search_class_re .= '|' unless ($first_class);
        $first_class = 0;
        $search_class_re .= $class . '(?:\|\w+)*';
        $seen_classes{$class} = 1;
    }

    for my $class ( keys %{$pkg->search_class_aliases} ) {

        for my $alias ( @{$pkg->search_class_aliases->{$class}} ) {
            $alias = qr/$alias/;
            s/(^|[^|])\b$alias\|/$1$class\|/g;
            s/(^|[^|])\b$alias[:=]/$1$class:/g;
        }

        if (!$seen_classes{$class}) {
            $search_class_re .= '|' unless ($first_class);
            $first_class = 0;

            $search_class_re .= $class . '(?:\|\w+)*';
            $seen_classes{$class} = 1;
        }
    }
    $search_class_re .= '):';

    warn " ** Search class RE: $search_class_re\n" if $self->debug;

    my $required_re = $pkg->operator('required');
    $required_re = qr/\Q$required_re\E/;

    my $disallowed_re = $pkg->operator('disallowed');
    $disallowed_re = qr/\Q$disallowed_re\E/;

    my $and_re = $pkg->operator('and');
    $and_re = qr/^\s*\Q$and_re\E/;

    my $or_re = $pkg->operator('or');
    $or_re = qr/^\s*\Q$or_re\E/;

    my $group_start_re = $pkg->operator('group_start');
    $group_start_re = qr/^\s*\Q$group_start_re\E/;

    my $group_end = $pkg->operator('group_end');
    my $group_end_re = qr/^\s*\Q$group_end\E/;

    my $modifier_tag_re = $pkg->operator('modifier');
    $modifier_tag_re = qr/^\s*\Q$modifier_tag_re\E/;


    # Build the filter and modifier uber-regexps
    my $facet_re = '^\s*(-?)((?:' . join( '|', @{$pkg->facet_classes}) . ')(?:\|\w+)*)\[(.+?)\]';
    warn " Facet RE: $facet_re\n" if $self->debug;

    my $filter_re = '^\s*(-?)(' . join( '|', @{$pkg->filters}) . ')\(([^()]+)\)';
    my $filter_as_class_re = '^\s*(-?)(' . join( '|', @{$pkg->filters}) . '):\s*(\S+)';

    my $modifier_re = '^\s*'.$modifier_tag_re.'(' . join( '|', @{$pkg->modifiers}) . ')\b';
    my $modifier_as_class_re = '^\s*(' . join( '|', @{$pkg->modifiers}) . '):\s*(\S+)';

    my $struct = $self->new_plan( level => $recursing );
    my $remainder = '';

    my $last_type = '';
    while (!$remainder) {
        if (/^\s*$/) { # end of an explicit group
            last;
        } elsif (/$group_end_re/) { # end of an explicit group
            warn "Encountered explicit group end\n" if $self->debug;

            $_ = $';
            $remainder = $struct->top_plan ? '' : $';

            $last_type = '';
        } elsif ($self->filter_count && /$filter_re/) { # found a filter
            warn "Encountered search filter: $1$2 set to $3\n" if $self->debug;

            my $negate = ($1 eq $pkg->operator('disallowed')) ? 1 : 0;
            $_ = $';
            $struct->new_filter( $2 => [ split '[,]+', $3 ], $negate );

            $last_type = '';
        } elsif ($self->filter_count && /$filter_as_class_re/) { # found a filter
            warn "Encountered search filter: $1$2 set to $3\n" if $self->debug;

            my $negate = ($1 eq $pkg->operator('disallowed')) ? 1 : 0;
            $_ = $';
            $struct->new_filter( $2 => [ split '[,]+', $3 ], $negate );

            $last_type = '';
        } elsif ($self->modifier_count && /$modifier_re/) { # found a modifier
            warn "Encountered search modifier: $1\n" if $self->debug;

            $_ = $';
            if (!$struct->top_plan) {
                warn "  Search modifiers only allowed at the top level of the query\n" if $self->debug;
            } else {
                $struct->new_modifier($1);
            }

            $last_type = '';
        } elsif ($self->modifier_count && /$modifier_as_class_re/) { # found a modifier
            warn "Encountered search modifier: $1\n" if $self->debug;

            my $mod = $1;

            $_ = $';
            if (!$struct->top_plan) {
                warn "  Search modifiers only allowed at the top level of the query\n" if $self->debug;
            } elsif ($2 =~ /^[ty1]/i) {
                $struct->new_modifier($mod);
            }

            $last_type = '';
        } elsif (/$group_start_re/) { # start of an explicit group
            warn "Encountered explicit group start\n" if $self->debug;

            my ($substruct, $subremainder) = $self->decompose( $', $current_class, $recursing + 1 );
            $struct->add_node( $substruct ) if ($substruct);
            $_ = $subremainder;

            $last_type = '';
        } elsif (/$and_re/) { # ANDed expression
            $_ = $';
            next if ($last_type eq 'AND');
            next if ($last_type eq 'OR');
            warn "Encountered AND\n" if $self->debug;

            $struct->joiner( '&' );

            $last_type = 'AND';
        } elsif (/$or_re/) { # ORed expression
            $_ = $';
            next if ($last_type eq 'AND');
            next if ($last_type eq 'OR');
            warn "Encountered OR\n" if $self->debug;

            $struct->joiner( '|' );

            $last_type = 'OR';
        } elsif ($self->facet_class_count && /$facet_re/) { # changing current class
            warn "Encountered facet: $1$2 => $3\n" if $self->debug;

            my $negate = ($1 eq $pkg->operator('disallowed')) ? 1 : 0;
            my $facet = $2;
            my $facet_value = [ split '\s*#\s*', $3 ];
            $struct->new_facet( $facet => $facet_value, $negate );
            $_ = $';

            $last_type = '';
        } elsif ($self->search_class_count && /$search_class_re/) { # changing current class

            if ($last_type eq 'CLASS') {
                $struct->remove_last_node( $current_class );
                warn "Encountered class change with no searches!\n" if $self->debug;
            }

            warn "Encountered class change: $1\n" if $self->debug;

            $current_class = $1;
            $struct->classed_node( $current_class );
            $_ = $';

            $last_type = 'CLASS';
        } elsif (/^\s*($required_re|$disallowed_re)?"([^"]+)"/) { # phrase, always anded
            warn 'Encountered' . ($1 ? " ['$1' modified]" : '') . " phrase: $2\n" if $self->debug;

            my $req_ness = $1 || '';
            my $phrase = $2;

            if (!$phrase_helper) {
                warn "Recursing into decompose with the phrase as a subquery\n" if $self->debug;
                my $after = $';
                my ($substruct, $subremainder) = $self->decompose( qq/$req_ness"$phrase"/, $current_class, $recursing + 1, 1 );
                $struct->add_node( $substruct ) if ($substruct);
                $_ = $after;
            } else {
                warn "Directly parsing the phrase subquery\n" if $self->debug;
                $struct->joiner( '&' );

                my $class_node = $struct->classed_node($current_class);

                if ($req_ness eq $pkg->operator('disallowed')) {
                    $class_node->add_dummy_atom( node => $class_node );
                    $class_node->add_unphrase( $phrase );
                    $phrase = '';
                    #$phrase =~ s/(^|\s)\b/$1-/g;
                } else { 
                    $class_node->add_phrase( $phrase );
                }
                $_ = $phrase . $';

            }

            $last_type = '';

#        } elsif (/^\s*$required_re([^\s"]+)/) { # phrase, always anded
#            warn "Encountered required atom (mini phrase): $1\n" if $self->debug;
#
#            my $phrase = $1;
#
#            my $class_node = $struct->classed_node($current_class);
#            $class_node->add_phrase( $phrase );
#            $_ = $phrase . $';
#            $struct->joiner( '&' );
#
#            $last_type = '';
        } elsif (/^\s*([^$group_end\s]+)/o) { # atom
            warn "Encountered atom: $1\n" if $self->debug;
            warn "Remainder: $'\n" if $self->debug;

            my $atom = $1;
            my $after = $';

            $_ = $after;
            $last_type = '';

            my $class_node = $struct->classed_node($current_class);

            my $prefix = ($atom =~ s/^$disallowed_re//o) ? '!' : '';
            my $truncate = ($atom =~ s/\*$//o) ? '*' : '';

            if ($atom ne '' and !grep { $atom =~ /^\Q$_\E+$/ } ('&','|','-','+')) { # throw away & and |, not allowed in tsquery, and not really useful anyway
#                $class_node->add_phrase( $atom ) if ($atom =~ s/^$required_re//o);
#                $class_node->add_unphrase( $atom ) if ($prefix eq '!');

                $class_node->add_fts_atom( $atom, suffix => $truncate, prefix => $prefix, node => $class_node );
                $struct->joiner( '&' );
            }
        } 

        last unless ($_);

    }

    $struct = undef if (scalar(@{$struct->query_nodes}) == 0 && !$struct->top_plan);

    return $struct if !wantarray;
    return ($struct, $remainder);
}

sub find_class_index {
    my $class = shift;
    my $query = shift;

    my ($class_part, @field_parts) = split '\|', $class;
    $class_part ||= $class;

    for my $idx ( 0 .. scalar(@$query) - 1 ) {
        next unless ref($$query[$idx]);
        return $idx if ( $$query[$idx]{requested_class} && $class eq $$query[$idx]{requested_class} );
    }

    push(@$query, { classname => $class_part, (@field_parts ? (fields => \@field_parts) : ()), requested_class => $class, ftsquery => [], phrases => [] });
    return -1;
}

sub core_limit {
    my $self = shift;
    my $l = shift;
    $self->{core_limit} = $l if ($l);
    return $self->{core_limit};
}

sub superpage {
    my $self = shift;
    my $l = shift;
    $self->{superpage} = $l if ($l);
    return $self->{superpage};
}

sub superpage_size {
    my $self = shift;
    my $l = shift;
    $self->{superpage_size} = $l if ($l);
    return $self->{superpage_size};
}


#-------------------------------
package QueryParser::query_plan;

sub QueryParser {
    my $self = shift;
    return undef unless ref($self);
    return $self->{QueryParser};
}

sub new {
    my $pkg = shift;
    $pkg = ref($pkg) || $pkg;
    my %args = (query => [], joiner => '&', @_);

    return bless \%args => $pkg;
}

sub new_node {
    my $self = shift;
    my $pkg = ref($self) || $self;
    my $node = do{$pkg.'::node'}->new( plan => $self, @_ );
    $self->add_node( $node );
    return $node;
}

sub new_facet {
    my $self = shift;
    my $pkg = ref($self) || $self;
    my $name = shift;
    my $args = shift;
    my $negate = shift;

    my $node = do{$pkg.'::facet'}->new( plan => $self, name => $name, 'values' => $args, negate => $negate );
    $self->add_node( $node );

    return $node;
}

sub new_filter {
    my $self = shift;
    my $pkg = ref($self) || $self;
    my $name = shift;
    my $args = shift;
    my $negate = shift;

    my $node = do{$pkg.'::filter'}->new( plan => $self, name => $name, args => $args, negate => $negate );
    $self->add_filter( $node );

    return $node;
}

sub find_filter {
    my $self = shift;
    my $needle = shift;;
    return undef unless ($needle);
    return grep { $_->name eq $needle } @{ $self->filters };
}

sub find_modifier {
    my $self = shift;
    my $needle = shift;;
    return undef unless ($needle);
    return grep { $_->name eq $needle } @{ $self->modifiers };
}

sub new_modifier {
    my $self = shift;
    my $pkg = ref($self) || $self;
    my $name = shift;

    my $node = do{$pkg.'::modifier'}->new( $name );
    $self->add_modifier( $node );

    return $node;
}

sub classed_node {
    my $self = shift;
    my $requested_class = shift;

    my $node;
    for my $n (@{$self->{query}}) {
        next unless (ref($n) && $n->isa( 'QueryParser::query_plan::node' ));
        if ($n->requested_class eq $requested_class) {
            $node = $n;
            last;
        }
    }

    if (!$node) {
        $node = $self->new_node;
        $node->requested_class( $requested_class );
    }

    return $node;
}

sub remove_last_node {
    my $self = shift;
    my $requested_class = shift;

    my $old = pop(@{$self->query_nodes});
    pop(@{$self->query_nodes}) if (@{$self->query_nodes});

    return $old;
}

sub query_nodes {
    my $self = shift;
    return $self->{query};
}

sub add_node {
    my $self = shift;
    my $node = shift;

    $self->{query} ||= [];
    push(@{$self->{query}}, $self->joiner) if (@{$self->{query}});
    push(@{$self->{query}}, $node);

    return $self;
}

sub top_plan {
    my $self = shift;

    return $self->{level} ? 0 : 1;
}

sub plan_level {
    my $self = shift;
    return $self->{level};
}

sub joiner {
    my $self = shift;
    my $joiner = shift;

    $self->{joiner} = $joiner if ($joiner);
    return $self->{joiner};
}

sub modifiers {
    my $self = shift;
    $self->{modifiers} ||= [];
    return $self->{modifiers};
}

sub add_modifier {
    my $self = shift;
    my $modifier = shift;

    $self->{modifiers} ||= [];
    return $self if (grep {$$_ eq $$modifier} @{$self->{modifiers}});

    push(@{$self->{modifiers}}, $modifier);

    return $self;
}

sub facets {
    my $self = shift;
    $self->{facets} ||= [];
    return $self->{facets};
}

sub add_facet {
    my $self = shift;
    my $facet = shift;

    $self->{facets} ||= [];
    return $self if (grep {$_->name eq $facet->name} @{$self->{facets}});

    push(@{$self->{facets}}, $facet);

    return $self;
}

sub filters {
    my $self = shift;
    $self->{filters} ||= [];
    return $self->{filters};
}

sub add_filter {
    my $self = shift;
    my $filter = shift;

    $self->{filters} ||= [];
    return $self if (grep {$_->name eq $filter->name} @{$self->{filters}});

    push(@{$self->{filters}}, $filter);

    return $self;
}


#-------------------------------
package QueryParser::query_plan::node;

sub new {
    my $pkg = shift;
    $pkg = ref($pkg) || $pkg;
    my %args = @_;

    return bless \%args => $pkg;
}

sub new_atom {
    my $self = shift;
    my $pkg = ref($self) || $self;
    return do{$pkg.'::atom'}->new( @_ );
}

sub requested_class { # also split into classname and fields
    my $self = shift;
    my $class = shift;

    if ($class) {
        my ($class_part, @field_parts) = split '\|', $class;
        $class_part ||= $class;

        $self->{requested_class} = $class;
        $self->{classname} = $class_part;
        $self->{fields} = \@field_parts;
    }

    return $self->{requested_class};
}

sub plan {
    my $self = shift;
    my $plan = shift;

    $self->{plan} = $plan if ($plan);
    return $self->{plan};
}

sub classname {
    my $self = shift;
    my $class = shift;

    $self->{classname} = $class if ($class);
    return $self->{classname};
}

sub fields {
    my $self = shift;
    my @fields = @_;

    $self->{fields} ||= [];
    $self->{fields} = \@fields if (@fields);
    return $self->{fields};
}

sub phrases {
    my $self = shift;
    my @phrases = @_;

    $self->{phrases} ||= [];
    $self->{phrases} = \@phrases if (@phrases);
    return $self->{phrases};
}

sub unphrases {
    my $self = shift;
    my @phrases = @_;

    $self->{unphrases} ||= [];
    $self->{unphrases} = \@phrases if (@phrases);
    return $self->{unphrases};
}

sub add_phrase {
    my $self = shift;
    my $phrase = shift;

    push(@{$self->phrases}, $phrase);

    return $self;
}

sub add_unphrase {
    my $self = shift;
    my $phrase = shift;

    push(@{$self->unphrases}, $phrase);

    return $self;
}

sub query_atoms {
    my $self = shift;
    my @query_atoms = @_;

    $self->{query_atoms} ||= [];
    $self->{query_atoms} = \@query_atoms if (@query_atoms);
    return $self->{query_atoms};
}

sub add_fts_atom {
    my $self = shift;
    my $atom = shift;

    if (!ref($atom)) {
        my $content = $atom;
        my @parts = @_;

        $atom = $self->new_atom( content => $content, @parts );
    }

    push(@{$self->query_atoms}, $self->plan->joiner) if (@{$self->query_atoms});
    push(@{$self->query_atoms}, $atom);

    return $self;
}

sub add_dummy_atom {
    my $self = shift;
    my @parts = @_;

    my $atom = $self->new_atom( @parts, dummy => 1 );

    push(@{$self->query_atoms}, $self->plan->joiner) if (@{$self->query_atoms});
    push(@{$self->query_atoms}, $atom);

    return $self;
}

#-------------------------------
package QueryParser::query_plan::node::atom;

sub new {
    my $pkg = shift;
    $pkg = ref($pkg) || $pkg;
    my %args = @_;

    return bless \%args => $pkg;
}

sub node {
    my $self = shift;
    return undef unless (ref $self);
    return $self->{node};
}

sub content {
    my $self = shift;
    return undef unless (ref $self);
    return $self->{content};
}

sub prefix {
    my $self = shift;
    return undef unless (ref $self);
    return $self->{prefix};
}

sub suffix {
    my $self = shift;
    return undef unless (ref $self);
    return $self->{suffix};
}

#-------------------------------
package QueryParser::query_plan::filter;

sub new {
    my $pkg = shift;
    $pkg = ref($pkg) || $pkg;
    my %args = @_;

    return bless \%args => $pkg;
}

sub plan {
    my $self = shift;
    return $self->{plan};
}

sub name {
    my $self = shift;
    return $self->{name};
}

sub negate {
    my $self = shift;
    return $self->{negate};
}

sub args {
    my $self = shift;
    return $self->{args};
}

#-------------------------------
package QueryParser::query_plan::facet;

sub new {
    my $pkg = shift;
    $pkg = ref($pkg) || $pkg;
    my %args = @_;

    return bless \%args => $pkg;
}

sub plan {
    my $self = shift;
    return $self->{plan};
}

sub name {
    my $self = shift;
    return $self->{name};
}

sub negate {
    my $self = shift;
    return $self->{negate};
}

sub values {
    my $self = shift;
    return $self->{'values'};
}

#-------------------------------
package QueryParser::query_plan::modifier;

sub new {
    my $pkg = shift;
    $pkg = ref($pkg) || $pkg;
    my $modifier = shift;

    return bless \$modifier => $pkg;
}

sub name {
    my $self = shift;
    return $$self;
}

1;

