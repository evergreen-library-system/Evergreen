package OpenILS::Application::Acq::Search;
use base "OpenILS::Application";

use strict;
use warnings;

use OpenILS::Event;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::Acq::Lineitem;
use OpenILS::Application::Acq::Financials;
use OpenILS::Application::Acq::Picklist;

my %RETRIEVERS = (
    "lineitem" =>
        \&{"OpenILS::Application::Acq::Lineitem::retrieve_lineitem_impl"},
    "picklist" =>
        \&{"OpenILS::Application::Acq::Picklist::retrieve_picklist_impl"},
    "purchase_order" => \&{
        "OpenILS::Application::Acq::Financials::retrieve_purchase_order_impl"
    }
);

sub F { $Fieldmapper::fieldmap->{"Fieldmapper::" . $_[0]}; }

# This subroutine returns 1 if the argument is a) a scalar OR
# b) an array of ONLY scalars. Otherwise it returns 0.
sub check_1d_max {
    my ($o) = @_;
    return 1 unless ref $o;
    if (ref($o) eq "ARRAY") {
        foreach (@$o) { return 0 if ref $_; }
        return 1;
    }
    0;
}

# Returns 1 if and only if argument is an array of exactly two scalars.
sub could_be_range {
    my ($o) = @_;
    if (ref $o eq "ARRAY") {
        return 1 if (scalar(@$o) == 2 && (!ref $o->[0] && !ref $o->[1]));
    }
    0;
}

sub castdate { +{"=" => {"transform" => "date", "value" => $_[0]}}; }

sub prepare_acqlia_search_and {
    my ($acqlia) = @_;

    my @phrases = ();
    foreach my $unit (@{$acqlia}) {
        my $subquery = {
            "select" => {"acqlia" => ["id"]},
            "from" => "acqlia",
            "where" => {"-and" => [{"lineitem" => {"=" => {"+jub" => "id"}}}]}
        };

        # castdate not supported for acqlia fields: they're all type text
        my ($k, $v, $fuzzy, $between, $not) = breakdown_term($unit);
        my $point = $subquery->{"where"}->{"-and"};
        my $term_clause;

        push @$point, {"definition" => $k};

        if ($fuzzy and not ref $v) {
            push @$point, {"attr_value" => {"ilike" => "%" . $v . "%"}};
        } elsif ($between and could_be_range($v)) {
            push @$point, {"attr_value" => {"between" => $v}};
        } elsif (check_1d_max($v)) {
            push @$point, {"attr_value" => $v};
        } else {
            next;
        }

        my $operator = $not ? "-not-exists" : "-exists";
        push @phrases, {$operator => $subquery};
    }
    @phrases;
}

sub prepare_acqlia_search_or {
    my ($acqlia) = @_;

    my $point = [];
    my $result = {"+acqlia" => {"-or" => $point}};

    foreach my $unit (@$acqlia) {
        # castdate not supported for acqlia fields: they're all type text
        my ($k, $v, $fuzzy, $between, $not) = breakdown_term($unit);
        my $term_clause;
        if ($fuzzy and not ref $v) {
            $term_clause = {
                "-and" => {
                    "definition" => $k,
                    "attr_value" => {"ilike" => "%" . $v . "%"}
                }
            };
        } elsif ($between and could_be_range($v)) {
            $term_clause = {
                "-and" => {
                    "definition" => $k, "attr_value" => {"between" => $v}
                }
            };
        } elsif (check_1d_max($v)) {
            $term_clause = {
                "-and" => {"definition" => $k, "attr_value" => $v}
            };
        } else {
            next;
        }

        push @$point, $not ? {"-not" => $term_clause} : $term_clause;
    }
    $result;
}

sub breakdown_term {
    my ($term) = @_;

    my $key = (grep { !/^__/ } keys %$term)[0];
    (
        $key, $term->{$key},
        $term->{"__fuzzy"} ? 1 : 0,
        $term->{"__between"} ? 1 : 0,
        $term->{"__not"} ? 1 : 0,
        $term->{"__castdate"} ? 1 : 0
    );
}

sub get_fm_links_by_hint {
    my ($hint) = @_;
    foreach my $field (values %{$Fieldmapper::fieldmap}) {
        return $field->{"links"} if $field->{"hint"} eq $hint;
    }
    undef;
}

sub gen_au_term {
    my ($value, $n) = @_;
    +{
        "-or" => [
            {"+au$n" => {"usrname" => $value}},
            {"+au$n" => {"first_given_name" => $value}},
            {"+au$n" => {"second_given_name" => $value}},
            {"+au$n" => {"family_name" => $value}},
            {"+ac$n" => {"barcode" => $value}}
        ]
    };
}

# go through the terms hash, find keys that correspond to fields links
# to actor.usr, and rewrite the search as one that searches not by
# actor.usr.id but by any of these user properties: card barcode, username,
# given names and family name.
sub prepare_au_terms {
    my ($terms, $join_num) = @_;

    my @joins = ();
    my $nots = 0;
    $join_num ||= 0;

    foreach my $conj (qw/-and -or/) {
        next unless exists $terms->{$conj};

        my @new_outer_terms = ();
        HINT_UNIT: foreach my $hint_unit (@{$terms->{$conj}}) {
            my $hint = (keys %$hint_unit)[0];
            (my $plain_hint = $hint) =~ y/+//d;
            if ($hint eq "-not") {
                $hint_unit = $hint_unit->{$hint};
                $nots++;
                redo HINT_UNIT;
            }

            if (my $links = get_fm_links_by_hint($plain_hint) and
                $plain_hint ne "acqlia") {
                my @new_terms = ();
                my ($attr, $value) = breakdown_term($hint_unit->{$hint});
                if ($links->{$attr} and
                    $links->{$attr}->{"class"} eq "au") {
                    push @joins, [$plain_hint, $attr, $join_num];
                    my $au_term = gen_au_term($value, $join_num);
                    if ($nots > 0) {
                        $au_term = {"-not" => $au_term};
                        $nots--;
                    }
                    push @new_outer_terms, $au_term;
                    $join_num++;
                    delete $hint_unit->{$hint};
                }
            }
            if ($nots > 0) {
                $hint_unit = {"-not" => $hint_unit};
                $nots--;
            }
            push @new_outer_terms, $hint_unit if scalar keys %$hint_unit;
        }
        $terms->{$conj} = [ @new_outer_terms ];
    }
    @joins;
}

sub prepare_terms {
    my ($terms, $is_and) = @_;

    my $conj = $is_and ? "-and" : "-or";
    my $outer_clause = {};

    foreach my $class (qw/acqpo acqpl jub/) {
        next if not exists $terms->{$class};

        $outer_clause->{$conj} = [] unless $outer_clause->{$conj};
        foreach my $unit (@{$terms->{$class}}) {
            my ($k, $v, $fuzzy, $between, $not, $castdate) =
                breakdown_term($unit);

            my $term_clause;
            if ($fuzzy and not ref $v) {
                $term_clause = {$k => {"ilike" => "%" . $v . "%"}};
            } elsif ($between and could_be_range($v)) {
                $term_clause = {$k => {"between" => $v}};
            } elsif (check_1d_max($v)) {
                $v = castdate($v) if $castdate;
                $term_clause = {$k => $v};
            } else {
                next;
            }

            my $clause = {"+" . $class => $term_clause};
            $clause = {"-not" => $clause} if $not;
            push @{$outer_clause->{$conj}}, $clause;
        }
    }

    if ($terms->{"acqlia"}) {
        push @{$outer_clause->{$conj}},
            $is_and ? prepare_acqlia_search_and($terms->{"acqlia"}) :
                prepare_acqlia_search_or($terms->{"acqlia"});
    }

    return undef unless scalar keys %$outer_clause;
    $outer_clause;
}

sub add_au_joins {
    my ($from) = shift;

    my $n = 0;
    foreach my $join (@_) {
        my ($hint, $attr, $num) = @$join;
        my $start = $hint eq "jub" ? $from->{$hint} : $from->{"jub"}->{$hint};
        my $clause = {
            "class" => "au",
            "type" => "left",
            "field" => "id",
            "fkey" => $attr,
            "join" => {
                "ac$num" => {
                    "class" => "ac",
                    "type" => "left",
                    "field" => "id",
                    "fkey" => "card"
                }
            }
        };
        if ($hint eq "jub") {
            $start->{"au$num"} = $clause;
        } else {
            $start->{"join"} ||= {};
            $start->{"join"}->{"au$num"} = $clause;
        }
        $n++;
    }
    $n;
}

__PACKAGE__->register_method(
    method    => "unified_search",
    api_name  => "open-ils.acq.lineitem.unified_search",
    stream    => 1,
    signature => {
        desc   => q/Returns lineitems based on flexible search terms./,
        params => [
            {desc => "Authentication token", type => "string"},
            {desc => "Field/value pairs for AND'ing", type => "object"},
            {desc => "Field/value pairs for OR'ing", type => "object"},
            {desc => "Conjunction between AND pairs and OR pairs " .
                "(can be 'and' or 'or')", type => "string"},
            {desc => "Retrieval options (clear_marc, flesh_notes, etc) " .
                "- XXX detail all the options",
                type => "object"}
        ],
        return => {desc => "A stream of LIs on success, Event on failure"}
    }
);

__PACKAGE__->register_method(
    method    => "unified_search",
    api_name  => "open-ils.acq.purchase_order.unified_search",
    stream    => 1,
    signature => {
        desc   => q/Returns purchase orders based on flexible search terms.
            See open-ils.acq.lineitem.unified_search/,
        return => {desc => "A stream of POs on success, Event on failure"}
    }
);

__PACKAGE__->register_method(
    method    => "unified_search",
    api_name  => "open-ils.acq.picklist.unified_search",
    stream    => 1,
    signature => {
        desc   => q/Returns pick lists based on flexible search terms.
            See open-ils.acq.lineitem.unified_search/,
        return => {desc => "A stream of PLs on success, Event on failure"}
    }
);

sub unified_search {
    my ($self, $conn, $auth, $and_terms, $or_terms, $conj, $options) = @_;
    $options ||= {};

    my $e = new_editor("authtoken" => $auth);
    return $e->die_event unless $e->checkauth;

    # What kind of object are we returning? Important: (\w+) had better be
    # a legit acq classname particle, so don't register any crazy api_names.
    my $ret_type = ($self->api_name =~ /cq.(\w+).un/)[0];
    my $retriever = $RETRIEVERS{$ret_type};
    my $hint = F("acq::$ret_type")->{"hint"};

    my $query = {
        "select" => {
            $hint =>
                [{"column" => "id", "transform" => "distinct"}]
        },
        "from" => {
            "jub" => {
                "acqpo" => {
                    "type" => "full",
                    "field" => "id",
                    "fkey" => "purchase_order"
                },
                "acqpl" => {
                    "type" => "full",
                    "field" => "id",
                    "fkey" => "picklist"
                }
            }
        },
        "order_by" => { $hint => {"id" => {}}},
        "offset" => ($options->{"offset"} || 0)
    };

    $query->{"limit"} = $options->{"limit"} if $options->{"limit"};

    $and_terms = prepare_terms($and_terms, 1);
    $or_terms = prepare_terms($or_terms, 0) and do {
        $query->{"from"}->{"jub"}->{"acqlia"} = {
            "type" => "left", "field" => "lineitem", "fkey" => "id",
        };
    };

    # TODO find instances of fields of type "timestamp" and massage the
    # comparison to match search input (which is only at date precision,
    # not timestamp).
    my $offset = add_au_joins($query->{"from"}, prepare_au_terms($and_terms));
    add_au_joins($query->{"from"}, prepare_au_terms($or_terms, $offset));

    if ($and_terms and $or_terms) {
        $query->{"where"} = {
            "-" . (lc $conj eq "or" ? "or" : "and") => [$and_terms, $or_terms]
        };
    } elsif ($and_terms) {
        $query->{"where"} = $and_terms;
    } elsif ($or_terms) {
        $query->{"where"} = $or_terms;
    } else {
        $e->disconnect;
        return new OpenILS::Event("BAD_PARAMS", "desc" => "No usable terms");
    }

    my $results = $e->json_query($query) or return $e->die_event;
    if ($options->{"id_list"}) {
        foreach (@$results) {
            $conn->respond($_->{"id"}) if $_->{"id"};
        }
    } else {
        foreach (@$results) {
            $conn->respond($retriever->($e, $_->{"id"}, $options))
                if $_->{"id"};
        }
    }
    $e->disconnect;
    undef;
}

1;
