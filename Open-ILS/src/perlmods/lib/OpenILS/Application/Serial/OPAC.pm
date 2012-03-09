package OpenILS::Application::Serial::OPAC;

# This package contains methods for open-ils.serial that present data suitable
# for OPAC display.

use base qw/OpenILS::Application/;
use strict;
use warnings;

# All of the packages we might 'use' are already imported in
# OpenILS::Application::Serial.  Only those that export symbols
# need to be mentioned explicitly here.

use OpenSRF::Utils::Logger qw/:logger/;
use OpenILS::Utils::CStoreEditor q/:funcs/;

my $U = "OpenILS::Application::AppUtils";

my %MFHD_SUMMARIZED_SUBFIELDS = (
   enum => [ split //, "abcdef" ],   # $g and $h intentionally omitted for now
   chron => [ split //, "ijklm" ]
);

# This is a helper for scoped_holding_summary_tree_for_bib() a little further down

sub _place_org_node {
    my ($node, $tree, $org_tree) = @_;

    my @ancestry = reverse @{ $U->get_org_ancestors($node->{org_unit}, 1) };
    shift @ancestry;    # discard current org_unit

    foreach (@ancestry) {  # in leaf-to-root order
        my $graft_point = _find_ou_in_holdings_tree($tree, $_);

        if ($graft_point) {
            push @{$graft_point->{children}}, $node;
            return;
        } else {
            $node = {
                org_unit => $_,
                holding_summaries => [],
                children => [$node]
            }
        }
    }

    # If we reach this point, we got all the way to the top of the org tree
    # without finding corresponding nodes in $tree (holdings tree), so the
    # latter must be empty, and we need to make $tree just contain what $node
    # contains.

    %$tree = %$node;
}

# This is a helper for scoped_holding_summary_tree_for_bib() a little further down

sub _find_ou_in_holdings_tree {
    my ($tree, $id) = @_;

    return $tree if $tree->{org_unit} eq $id;
    if (ref $tree->{children}) {
        foreach (@{$tree->{children}}) {
            my $maybe = _find_ou_in_holdings_tree($_, $id);
            return $maybe if $maybe;
        }
    }

    return;
}

sub scoped_holding_summary_tree_for_bib {
    my (
        $self, $client, $bib, $org_unit, $depth, $limit, $offset, $ascending
    ) = @_;

    my $org_tree = $U->get_org_tree;    # caches

    $org_unit ||= $org_tree->id;
    $depth ||= 0;
    $limit ||= 10;
    $offset ||= 0;

    my $e = new_editor;

    # What we want to know from this query is essentially the set of
    # holdings related to a given bib and the org units that have said
    # holdings.

    # For this we would only need sasum, sdist and ssub, but
    # because we also need to be able to page (and therefore must sort) the
    # results we get, we need reasonable columns on which to do the sorting.
    # So for that we join sitem (via sstr) so we can sort on the maximum
    # date_expected (which is basically the issue pub date) for items that
    # have been received.  That maximum date_expected is actually the second
    # sort key, however.  The first is the holding lib's position in a
    # depth-first representation of the org tree (if you think about it,
    # paging through holdings held at diverse points in the tree only makes
    # sense if you do it this way).

    my $rows = $e->json_query({
        select => {
            sasum => [qw/summary_type id generated_coverage/],
            sdist => ["holding_lib"],
            sitem => [
                {column => "date_expected", transform => "max", aggregate => 1}
            ]
        },
        from => {
            sasum => {
                sdist => {
                    join => {
                        ssub => {},
                        sstr => {
                            join => {sitem => {}}
                        },
                    }
                }
            }
        },
        where => {
            "+sdist" => {
                holding_lib =>
                    $U->get_org_descendants(int($org_unit), int($depth))
            },
            "+ssub" => {record_entry => int($bib)},
            "+sitem" => {date_received => {"!=" => undef}}
        },
        limit => int($limit) + 1, # see comment below on "limit trick"
        offset => int($offset),
        order_by => [
            {
                class => "sdist",
                field => "holding_lib",
                transform => "actor.org_unit_simple_path",
                params => [$org_tree->id]
            },
            {
                class => "sitem",
                field => "date_expected",
                transform => "max", # to match select clause
                direction => ($ascending ? "ASC" : "DESC")
            }
        ],
    }) or return $e->die_event;

    $e->disconnect;

    # Now we build a tree out of our result set.
    my $result = {};

    # Use our "limit trick" from above to cheaply determine whether there's
    # another page of results, for the UI's benefit.  Put $more into the
    # result hash at the very end.
    my $more = 0;
    if (scalar(@$rows) > int($limit)) {
        $more = 1;
        pop @$rows;
    }

    foreach my $row (@$rows) {
        my $org_node_needs_placed = 0;
        my $org_node =
            _find_ou_in_holdings_tree($result, $row->{holding_lib});

        if (not $org_node) {
            $org_node_needs_placed = 1;
            $org_node = {
                org_unit => $row->{holding_lib},
                holding_summaries => [],
                children => []
            };
        }

        # Make a very simple object for a single holding summary.
        # generated_coverage is stored as JSON, and here we can unpack it.
        my $summary = {
            id => $row->{id},
            summary_type => $row->{summary_type},
            generated_coverage =>
                OpenSRF::Utils::JSON->JSON2perl($row->{generated_coverage})
        };

        push @{$org_node->{holding_summaries}}, $summary;

        if ($org_node_needs_placed) {
            _place_org_node($org_node, $result, $org_tree);
        }
    }

    $result->{more} = $more;
    return $result;
}

__PACKAGE__->register_method(
    method    => "scoped_holding_summary_tree_for_bib",
    api_name  => "open-ils.serial.holding_summary_tree.by_bib",
    api_level => 1,
    argc      => 6,
    signature => {
        desc   => 'Return a set of holding summaries organized into a tree
        of nodes that look like:
            {org_unit:<id>, holding_summaries:[], children:[]}

        The root node has an extra key: "more". Its value is 1 if there
        are more pages (in the limit/offset sense) of results that the caller
        could potentially fetch.

        All arguments except the first (bibid) are optional.
        ',
        params => [
            {   name => "bibid",
                desc => "ID of the bre to which holdings belong",
                type => "number"
            },
            { name => "org_unit", type => "number" },
            { name => "depth (default 0)", type => "number" },
            { name => "limit (default 10)", type => "number" },
            { name => "offset (default 0)", type => "number" },
            { name => "ascending (default false)", type => "boolean" },
        ]
    }
);

# This is a helper for grouped_holdings_for_summary() later.
sub _label_holding_level {
    my ($pattern_field, $subfield, $value, $mfhd_cache) = @_;

    # This is naïve, in that a-f are sometimes chron fields and not enum.
    # OpenILS::Utils::MFHD understands that, but so far I don't think our
    # interfaces do.

    my $cache_key = $subfield . $value;

    if (not exists $mfhd_cache->{$cache_key}) {
        my $link_id = (split(/\./, $pattern_field->subfield('8')))[0];
        my $fake_holding = new MFHD::Holding(
            1,
            new MARC::Field('863', '4', '1', '8', "$link_id.1"),
            new MFHD::Caption($pattern_field->clone)
        );

        if ($subfield ge 'i') { # chron
            $mfhd_cache->{$cache_key} = $fake_holding->format_single_chron(
                {$subfield => $value}, $subfield, 1, 1
            );
        } else {                # enum
            $mfhd_cache->{$cache_key} = $fake_holding->format_single_enum(
                {$subfield => $value}, $subfield, 1
            );
        }
    }

    return $mfhd_cache->{$cache_key};
}

# This is a helper for grouped_holdings_for_summary() later.
sub _get_deepest_holding_level {
    my ($display_grouping, $pattern_field) = @_;

    my @present = grep { $pattern_field->subfield($_) } @{
        $MFHD_SUMMARIZED_SUBFIELDS{$display_grouping}
    };

    return pop @present;
}

# This is a helper for grouped_holdings_for_summary() later.
sub _opac_visible_unit_data {
    my ($issuance_id_list, $dist_id, $staff, $e) = @_;

    return {} unless @$issuance_id_list;

    my $rows = $e->json_query(
        $U->basic_opac_copy_query(
            undef, $issuance_id_list, $dist_id,
            1000, 0,    # XXX no mechanism for users to page at this level yet
            $staff
        )
    ) or return $e->die_event;

    my $results = {};

    # Take the list of rows returned from json_query() and sort results into
    # several smaller lists stored in a hash keyed by issuance ID.
    foreach my $row (@$rows) {
        $results->{$row->{issuance}} = [] unless
            exists $results->{$row->{issuance}};
        push @{ $results->{$row->{issuance}} }, $row;
    }

    return $results;
}

# This is a helper for grouped_holdings_for_summary() later.
sub _make_grouped_holding_node {
    my (
        $row, $subfield, $deepest_level, $pattern_field,
        $unit_data, $mfhd_cache
    ) = @_;

    return {
        $subfield eq $deepest_level ? (
            label => $row->{label},
            holding => $row->{id},
            ($unit_data ? (units => ($unit_data->{$row->{id}} || [])) : ())
        ) : (
            value => $row->{value},
            label => _label_holding_level(
                $pattern_field, $subfield, $row->{value}, $mfhd_cache
            )
        )
    };
}

# This is a helper for grouped_holdings_for_summary() later.
sub _make_single_level_grouped_holding_query {
    my (
        $subfield, $deepest_level, $summary_hint, $summary_id,
        $subfield_joins, $subfield_where_clauses,
        $limit, $offsets
    ) = @_;

    return {
        select => {
            sstr => ["distribution"],
            "smhc_$subfield" => ["value"], (
                $subfield eq $deepest_level ?
                    (siss => [qw/id label date_published/]) : ()
            )
        },
        from => {
            $summary_hint => {
                sdist => {
                    join => {
                        sstr => {
                            join => {
                                sitem => {
                                    join => {
                                        siss => {
                                            join => {%$subfield_joins}
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        },
        where => {
            "+$summary_hint" => {id => $summary_id},
            "+sitem" => {date_received => {"!=" => undef}},
            %$subfield_where_clauses
        },
        distinct => 1,  # sic, this goes here in json_query
        limit => int($limit) + 1,
        offset => int(shift(@$offsets)),
        order_by => {
            "smhc_$subfield" => {
                "value" => {
                    direction => ($subfield eq $deepest_level ? "asc" : "desc")
                }
            }
        }
    };
}

sub grouped_holdings_for_summary {
    my (
        $self, $client, $summary_type, $summary_id,
        $expand_path, $limit, $offsets, $auto_expand_first, $with_units
    ) = @_;

    # Validate input or set defaults.
    ($summary_type .= "") =~ s/[^\w]//g;
    $summary_id = int($summary_id);
    $expand_path ||= [];
    $limit ||= 12;
    $limit = 12 if $limit < 1;
    $offsets ||= [0];

    foreach ($expand_path, $offsets) {
        if (ref $_ ne 'ARRAY') {
            return new OpenILS::Event(
                "BAD_PARAMS", note =>
                    "'expand_path' and 'offsets' arguments must be arrays"
            );
        }
    }

    if (scalar(@$offsets) != scalar(@$expand_path) + 1) {
        return new OpenILS::Event(
            "BAD_PARAMS", note =>
                "'offsets' array must be one element longer than 'expand_path'"
        );
    }

    # Get the class hint for whichever type of summary we're expanding.
    my $fmclass = "Fieldmapper::serial::${summary_type}_summary";
    my $summary_hint = $Fieldmapper::fieldmap->{$fmclass}{hint} or
        return new OpenILS::Event("BAD_PARAMS", note => "summary_type");

    my $e = new_editor;

    # First, get display grouping for requested summary (either chron or enum)
    # and the pattern code. Even though we have to JOIN through sitem to get
    # pattern_code from scap, we don't actually care about specific items yet.
    my $row = $e->json_query({
        select => {sdist => ["display_grouping"], scap => ["pattern_code"]},
        from => {
            $summary_hint => {
                sdist => {
                    join => {
                        sstr => {
                            join => {
                                sitem => {
                                    join => {
                                        siss => {
                                            join => {scap => {}}
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        },
        where => {
            "+$summary_hint" => {id => $summary_id},
            "+sitem" => {date_received => {"!=" => undef}}
        },
        limit => 1
    }) or return $e->die_event;

    # Summaries without attached holdings constitute bad data, not benign
    # empty result sets.
    return new OpenILS::Event(
        "BAD_PARAMS",
        note => "Summary #$summary_id not found, or no holdings attached"
    ) unless @$row;

    # Unless data has been disarranged, all holdings grouped together under
    # the same summary should have the same pattern code, so we can take any
    # result from the set we just got.
    my $pattern_field;
    eval {
        $pattern_field = new MARC::Field(
            "853", # irrelevant for our purposes
            @{ OpenSRF::Utils::JSON->JSON2perl($row->[0]->{pattern_code}) }
        );
    };
    if ($@) {
        return new OpenILS::Event("SERIAL_CORRUPT_PATTERN_CODE", note => $@);
    }

    # And now we know which subfields we will care about from
    # serial.materialized_holding_code.
    my $display_grouping = $row->[0]->{display_grouping};

    # This will tell us when to stop grouping and start showing actual
    # holdings.
    my $deepest_level =
        _get_deepest_holding_level($display_grouping, $pattern_field);
    if (not defined $deepest_level) {
        # corrupt pattern code
        my $msg = "couldn't determine deepest holding level for " .
            "$summary_type summary #$summary_id";
        $logger->warn($msg);
        return new OpenILS::Event("SERIAL_CORRUPT_PATTERN_CODE", note => $msg);
    }

    my @subfields = @{ $MFHD_SUMMARIZED_SUBFIELDS{$display_grouping} };

    # We look for holdings grouped at the top level once no matter what,
    # then we'll look deeper with additional queries for every element of
    # $expand_path later.
    # Below we define parts of the SELECT and JOIN clauses that we'll
    # potentially reuse if $expand_path has elements.

    my $subfield = shift @subfields;
    my %subfield_joins = ("smhc_$subfield" => {class => "smhc"});
    my %subfield_where_clauses = ("+smhc_$subfield" => {subfield => $subfield});

    # Now get the top level of holdings.
    my $top = $e->json_query(
        _make_single_level_grouped_holding_query(
            $subfield, $deepest_level, $summary_hint, $summary_id,
            \%subfield_joins, \%subfield_where_clauses,
            $limit, $offsets
        )
    ) or return $e->die_event;

    # Deal with the extra row, if present, that tells are there are more pages
    # of results.
    my $top_more = 0;
    if (scalar(@$top) > int($limit)) {
        $top_more = 1;
        pop @$top;
    }

    # Distribution is the same for all rows anyway, but we may need it for a
    # copy query later.
    my $dist_id = @$top ? $top->[0]->{distribution} : undef;

    # This will help us avoid certain repetitive calculations. Examine
    # _label_holding_level() to see what I mean.
    my $mfhd_cache = {};

    # Prepare related unit data if appropriate.
    my $unit_data;

    if ($with_units and $subfield eq $deepest_level) {
        $unit_data = _opac_visible_unit_data(
            [map { $_->{id} } @$top], $dist_id, $with_units > 1, $e
        );
        return $unit_data if defined $U->event_code($unit_data);
    }

    # Make the tree we have so far.
    my $tree = [
        { display_grouping => $display_grouping,
            caption => $pattern_field->subfield($subfield) },
        map(
            _make_grouped_holding_node(
                $_, $subfield, $deepest_level, $pattern_field,
                $unit_data, $mfhd_cache
            ),
            @$top
        ),
        ($top_more ? undef : ())
    ];

    # We'll need a parent reference at each level as we descend.
    my $parent = $tree;

    # Will we be trying magic auto-expansion of the first top-level grouping?
    if ($auto_expand_first and @$tree and not @$expand_path) {
        $expand_path = [$tree->[1]->{value}];
        $offsets = [0];
    }

    # Ok, that got us the top level, with nothing expanded. Now we loop through
    # the elements of @$expand_path, issuing similar queries to get us deeper
    # groupings and even actual specific holdings.
    foreach my $value (@$expand_path) {
        my $prev_subfield = $subfield;
        $subfield = shift @subfields;

        # This wad of JOINs is additive over each iteration.
        $subfield_joins{"smhc_$subfield"} = {class => "smhc"};

        # The WHERE clauses also change and grow each time.
        $subfield_where_clauses{"+smhc_$prev_subfield"}->{value} = $value;
        $subfield_where_clauses{"+smhc_$subfield"}->{subfield} = $subfield;

        my $level = $e->json_query(
            _make_single_level_grouped_holding_query(
                $subfield, $deepest_level, $summary_hint, $summary_id,
                \%subfield_joins, \%subfield_where_clauses,
                $limit, $offsets
            )
        ) or return $e->die_event;

        return $tree unless @$level;

        # Deal with the extra row, if present, that tells are there are more
        # pages of results.
        my $level_more = 0;
        if (scalar(@$level) > int($limit)) {
            $level_more = 1;
            pop @$level;
        }

        # Find attachment point for our results.
        my ($point) = grep { ref $_ and $_->{value} eq $value } @$parent;

        # Prepare related unit data if appropriate.
        if ($with_units and $subfield eq $deepest_level) {
            $unit_data = _opac_visible_unit_data(
                [map { $_->{id} } @$level], $dist_id, $with_units > 1, $e
            );
            return $unit_data if defined $U->event_code($unit_data);
        }

        # Set parent for the next iteration.
        $parent = $point->{children} = [
            { display_grouping => $display_grouping,
                caption => $pattern_field->subfield($subfield) },
            map(
                _make_grouped_holding_node(
                    $_, $subfield, $deepest_level, $pattern_field,
                    $unit_data, $mfhd_cache
                ),
                @$level
            ),
            ($level_more ? undef : ())
        ];

        last if $subfield eq $deepest_level;
    }

    return $tree;
}

__PACKAGE__->register_method(
    method    => "grouped_holdings_for_summary",
    api_name  => "open-ils.serial.holdings.grouped_by_summary",
    api_level => 1,
    argc      => 7,
    signature => {
        desc   => q/Return a tree of holdings associated with a given summary
        grouped by all but the last of either chron or enum units./,
        params => [
            { name => "summary_type", type => "string" },
            { name => "summary_id", type => "number" },
            { name => "expand_path", type => "array",
                desc => "In root-to-leaf order, the values of the nodes along the axis you want to expand" },
            { name => "limit (default 12)", type => "number" },
            { name => "offsets", type => "array", desc =>
                "This must be exactly one element longer than expand_path" },
            { name => "auto_expand_first", type => "boolean", desc =>
                "Only if expand_path is empty, automatically expand first top-level grouping" },
            { name => "with_units", type => "number", desc => q/
                If true at all, for each holding, if there are associated units,
                add some information about them to the result tree. These units
                will be filtered by OPAC visibility unless you provide a value
                greater than 1.

                IOW:
                    0 = no units,
                    1 = opac visible units,
                    2 = all units (i.e. staff view)
                / }
        ]
    }
);

1;
