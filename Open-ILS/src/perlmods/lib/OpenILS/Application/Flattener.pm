package OpenILS::Application::Flattener;

# This package is not meant to be registered as a stand-alone OpenSRF
# application, but to be used by high level methods in other services.

use base qw/OpenILS::Application/;

use strict;
use warnings;

use OpenSRF::EX qw/:try/;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenSRF::Utils::JSON;

use Data::Dumper;

$Data::Dumper::Indent = 0;

sub _fm_link_from_class {
    my ($class, $field) = @_;

    return Fieldmapper->publish_fieldmapper->{$class}{links}{$field};
}

sub _flattened_search_single_flesh_wad {
    my ($hint, $path)  = @_;

    $path = [ @$path ]; # clone for processing here
    my $class = OpenSRF::Utils::JSON->lookup_class($hint);

    my $flesh_depth = 0;
    my $flesh_fields = {};

    pop @$path; # last part is just field

    my $piece;

    while ($piece = shift @$path) {
        my $link = _fm_link_from_class($class, $piece);
        if ($link) {
            $flesh_fields->{$hint} ||= [];
            push @{ $flesh_fields->{$hint} }, $piece;
            $hint = $link->{class};
            $class = OpenSRF::Utils::JSON->lookup_class($hint);
            $flesh_depth++;
        } else {
            throw OpenSRF::EX::ERROR("no link $piece on $class");
        }
    }

    return {
        flesh => $flesh_depth,
        flesh_fields => $flesh_fields
    };
}

# returns a join clause AND a string representing the deepest join alias
# generated.
sub _flattened_search_single_join_clause {
    my ($column_name, $hint, $path)  = @_;

    my $class = OpenSRF::Utils::JSON->lookup_class($hint);
    my $last_ident = $class->Identity;

    $path = [ @$path ]; # clone for processing here

    pop @$path; # last part is just field

    my $core_join = {};
    my $last_join;
    my $piece;
    my $alias;  # yes, we need it out at this scope.

    while ($piece = shift @$path) {
        my $link = _fm_link_from_class($class, $piece);
        if ($link) {
            $hint = $link->{class};
            $class = OpenSRF::Utils::JSON->lookup_class($hint);

            my $reltype = $link->{reltype};
            my $field = $link->{key};
            if ($link->{map}) {
                # XXX having a non-blank value for map means we'll need
                # an additional level of join. TODO.
                throw OpenSRF::EX::ERROR(
                    "support not yet implemented for links like '$piece' with" .
                    " non-blank 'map' IDL attribute"
                );
            }

            $alias = "__${column_name}_${hint}";
            my $new_join;
            if ($reltype eq "has_a") {
                $new_join = {
                    type => "left",
                    class => $hint,
                    fkey => $piece,
                    field => $field
                };
            } elsif ($reltype eq "has_many" or $reltype eq "might_have") {
                $new_join = {
                    type => "left",
                    class => $hint,
                    fkey => $last_ident,
                    field => $field
                };
            } else {
                throw OpenSRF::EX::ERROR("unexpected reltype for link $piece");
            }

            if ($last_join) {
                $last_join->{join}{$alias} = $new_join;
            } else {
                $core_join->{$alias} = $new_join;
            }

            $last_ident = $class->Identity;
            $last_join = $new_join;
        } else {
            throw new OpenSRF::EX::ERROR("no link '$piece' on $class");
        }
    }

    return ($core_join, $alias);
}

# When $value is a string (short form of a column definition), it is assumed to
# be a dot-delimited path.  This will be normalized into a hash (long form)
# containing and path key, whose value will be made into an array, and true
# values for sort/filter/display.
#
# When $value is already a hash (long form), just make an array of the path key
# and explicity set any sort/filter/display values not present to 0.
#
sub _flattened_search_normalize_map_column {
    my ($value) = @_;

    if (ref $value eq "HASH") {
        foreach (qw/sort filter display/) {
            $value->{$_} = 0 unless exists $value->{$_};
        }
        $value->{path} = [split /\./, $value->{path}];
    } else {
        $value = {
            path => [split /\./, $value],
            sort => 1,
            filter => 1,
            display => 1
        };
    }

    return $value;
}

sub _flattened_search_merge_flesh_wad {
    my ($old, $new) = @_;

    $old->{flesh} ||= 0;
    $old->{flesh} = $old->{flesh} > $new->{flesh} ? $old->{flesh} : $new->{flesh};

    $old->{flesh_fields} ||= {};
    foreach my $key (keys %{$new->{flesh_fields}}) {
        if ($old->{flesh_fields}{$key}) {
            # For easy bonus points, somebody could take the following block
            # and make it use Set::Scalar so it's more semantic, which would
            # mean a new Evergreen dependency.
            #
            # The nonobvious point of the following code is to merge the
            # arrays at $old->{flesh_fields}{$key} and
            # $new->{flesh_fields}{$key}, treating the arrays as sets.

            my %hash = map { $_ => 1 } (
                @{ $old->{flesh_fields}{$key} },
                @{ $new->{flesh_fields}{$key} }
            );
            $old->{flesh_fields}{$key} = [ keys(%hash) ];
        } else {
            $old->{flesh_fields}{$key} = $new->{flesh_fields}{$key};
        }
    }
}

sub _flattened_search_merge_join_clause {
    my ($old, $new) = @_;

    %$old = ( %$old, %$new );
}

sub _flattened_search_expand_filter_column {
    my ($o, $key, $map) = @_;

    if ($map->{$key}) {
        my $table = $map->{$key}{last_join_alias};
        my $column = $map->{$key}{path}[-1];

        if ($table) {
            $table = "+" . $table;
            $o->{$table} ||= {};

            $o->{$table}{$column} = $o->{$key};
            delete $o->{$key};

            return $o->{$table}{$column};
        } else {    # field must be on core class
            if ($column ne $key) {
                $o->{$column} = $o->{$key};
                delete $o->{$key};
            }
            return $o->{$column};
        }
    } else {
        return $o->{$key};
    }
}

sub _flattened_search_recursively_apply_map_to_filter {
    my ($o, $map, $state) = @_;

    $state ||= {};

    if (ref $o eq "HASH") {
        foreach my $key (keys %$o) {
            # XXX this business about "in_expr" may prove inadequate, but it's
            # intended to avoid trying to map things like "between" in
            # constructs like:
            #   {"somecolumn": {"between": [1,10]}}
            # and to that extent, it works.

            if (not $state->{in_expr} and $key =~ /^[a-z]/) {
                $state->{in_expr} = 1;

                _flattened_search_recursively_apply_map_to_filter(
                    _flattened_search_expand_filter_column($o, $key, $map),
                    $map, $state
                );

                $state->{in_expr} = 0;
            } else {
                _flattened_search_recursively_apply_map_to_filter(
                    $o->{$key}, $map, $state
                );
            }
        }
    } elsif (ref $o eq "ARRAY") {
        _flattened_search_recursively_apply_map_to_filter(
            $_, $map, $state
        ) foreach @$o;
    } # else scalar, nothing to do?
}

# returns a normalized version of the map, and the jffolo (see below)
sub process_map {
    my ($hint, $map) = @_;

    $map = { %$map };   # clone map, to work on new copy

    my $jffolo = {    # jffolo: join/flesh/flesh_fields/order_by/limit/offset
        join => {}
    };

    # Here's a hash where we'll keep track of whether we've already provided
    # a join to cover a given hash.  It seems that without this we build
    # redundant joins.
    my $join_coverage = {};

    foreach my $k (keys %$map) {
        my $column = $map->{$k} =
            _flattened_search_normalize_map_column($map->{$k});

        # For display columns, we'll need fleshing.
        if ($column->{display}) {
            _flattened_search_merge_flesh_wad(
                $jffolo,
                _flattened_search_single_flesh_wad($hint, $column->{path})
            );
        }

        # For filter or sort columns, we'll need joining.
        if ($column->{filter} or $column->{sort}) {
            my @path = @{ $column->{path} };
            pop @path; # discard last part (field)
            my $joinkey = join(",", @path);

            my ($clause, $last_join_alias);

            # Skip joins that are already covered. We shouldn't need more than
            # one join for the same path
            if ($join_coverage->{$joinkey}) {
                ($clause, $last_join_alias) = @{ $join_coverage->{$joinkey} };
            } else {
                ($clause, $last_join_alias) =
                    _flattened_search_single_join_clause(
                        $k, $hint, $column->{path}
                    );
                $join_coverage->{$joinkey} = [$clause, $last_join_alias];
            }

            $map->{$k}{last_join_alias} = $last_join_alias;
            _flattened_search_merge_join_clause($jffolo->{join}, $clause);
        }
    }

    return ($map, $jffolo);
}

# return a filter clause for PCRUD or cstore, by processing the supplied
# simplifed $where clause using $map.
sub prepare_filter {
    my ($map, $where) = @_;

    my $filter = {%$where};

    _flattened_search_recursively_apply_map_to_filter($filter, $map);

    return $filter;
}

# Return a jffolo with sort/limit/offset from the simplified sort hash (slo)
# mixed in.  limit and offset are copied as-is.  sort is translated into
# an order_by that calls simplified column named by their real names by checking
# the map.
sub finish_jffolo {
    my ($core_hint, $map, $jffolo, $slo) = @_;

    $jffolo = { %$jffolo }; # clone
    $slo = { %$slo };       # clone

    $jffolo->{limit} = $slo->{limit} if exists $slo->{limit};
    $jffolo->{offset} = $slo->{offset} if exists $slo->{offset};

    return $jffolo unless $slo->{sort};

    # The slo has a special format for 'sort' that gives callers what they
    # need, but isn't as flexible as json_query's 'order_by'.
    #
    # "sort": [{"column1": "asc"}, {"column2": "desc"}]
    #   or
    # "sort": ["column1", {"column2": "desc"}]
    #   or
    # "sort": {"onlycolumn": "asc"}
    #   or
    # "sort": "onlycolumn"

    $jffolo->{order_by} = [];

    # coerce from optional simpler format (see comment blob above)
    $slo->{sort} = [ $slo->{sort} ] unless ref $slo->{sort} eq "ARRAY";

    foreach my $exp (@{ $slo->{sort} }) {
        $exp = { $exp => "asc" } unless ref $exp;

        # XXX By assuming that each sort expression is (at most) a single
        # key/value pair, we preclude the ability to use transforms and the
        # like for now.

        my ($key) = keys(%$exp);

        if ($map->{$key}) {
            my $class = $map->{$key}{last_join_alias} || $core_hint;

            push @{ $jffolo->{order_by} }, {
                class => $class,
                field => $map->{$key}{path}[-1],
                direction => $exp->{$key}
            };
        }

        # If the key wasn't defined in the map, we'll leave it out of our
        # order_by clause.
    }

    return $jffolo;
}

# Given a map and a fieldmapper object, return a flat representation as
# specified by the map's display fields
sub process_result {
    my ($map, $fmobj) = @_;

    if (not ref $fmobj) {
        throw OpenSRF::EX::ERROR(
            "process_result() was passed an inappropriate second argument ($fmobj)"
        );
    }

    my $flatrow = {};

    while (my ($key, $mapping) = each %$map) {
        next unless $mapping->{display};

        my @path = @{ $mapping->{path} };
        my $field = pop @path;

        my $objs = [$fmobj];
        while (my $step = shift @path) {
            $objs = [ map { $_->$step } @$objs ];
            last unless ref $$objs[0];
        }

        # We can get arrays of values be either:
        #  - ending on a $field within a has_many reltype
        #  - passing through a path that is a has_many reltype
        if (@$objs > 1 or ref $$objs[0] eq 'ARRAY') {
            $flatrow->{$key} = [];
            for my $o (@$objs) {
                push @{ $flatrow->{$key} }, extract_field_value( $o, $field );
            }
        } else {
            $flatrow->{$key} = extract_field_value( $$objs[0], $field );
        }
    }

    return $flatrow;
}

sub extract_field_value {
    my $obj = shift;
    my $field = shift;

    if (ref $obj eq 'ARRAY') {
        # has_many links return arrays
        return ( map {$_->$field} @$obj );
    }
    return ref $obj ? $obj->$field : undef;
}

1;
