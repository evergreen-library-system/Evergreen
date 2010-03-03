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

sub prepare_acqlia_search_and {
    my ($acqlia) = @_;

    my @phrases = ();
    foreach my $unit (@{$acqlia}) {
        my $something = 0;
        my $subquery = {
            "select" => {"acqlia" => ["id"]},
            "from" => "acqlia",
            "where" => {"-and" => [{"lineitem" => {"=" => {"+jub" => "id"}}}]}
        };

        while (my ($k, $v) = each %$unit) {
            my $point = $subquery->{"where"}->{"-and"};
            if ($k !~ /^__/) {
                push @$point, {"definition" => $k};
                $something++;

                if ($unit->{"__fuzzy"} and not ref $v) {
                    push @$point, {"attr_value" => {"ilike" => "%" . $v . "%"}};
                } elsif ($unit->{"__between"} and could_be_range($v)) {
                    push @$point, {"attr_value" => {"between" => $v}};
                } elsif (check_1d_max($v)) {
                    push @$point, {"attr_value" => $v};
                } else {
                    $something--;
                }
            }
        }
        push @phrases, {"-exists" => $subquery} if $something;
    }
    @phrases;
}

sub prepare_acqlia_search_or {
    my ($acqlia) = @_;

    my $point = [];
    my $result = {"+acqlia" => {"-or" => $point}};

    foreach my $unit (@$acqlia) {
        while (my ($k, $v) = each %$unit) {
            if ($k !~ /^__/) {
                if ($unit->{"__fuzzy"} and not ref $v) {
                    push @$point, {
                        "-and" => {
                            "definition" => $k,
                            "attr_value" => {"ilike" => "%" . $v . "%"}
                        }
                    };
                } elsif ($unit->{"__between"} and could_be_range($v)) {
                    push @$point, {
                        "-and" => {
                            "definition" => $k,
                            "attr_value" => {"between" => $v}
                        }
                    };
                } elsif (check_1d_max($v)) {
                    push @$point, {
                        "-and" => {"definition" => $k, "attr_value" => $v}
                    };
                } else {
                    next;
                }
                last;
            }
        }
    }
    $result;
}

sub prepare_terms {
    my ($terms, $is_and) = @_;

    my $conj = $is_and ? "-and" : "-or";
    my $outer_clause = {};

    foreach my $class (qw/acqpo acqpl jub/) {
        next if not exists $terms->{$class};

        my $clause = [];
        $outer_clause->{$conj} = [] unless $outer_clause->{$conj};
        foreach my $unit (@{$terms->{$class}}) {
            while (my ($k, $v) = each %$unit) {
                if ($k !~ /^__/) {
                    if ($unit->{"__fuzzy"} and not ref $v) {
                        push @$clause, {$k => {"ilike" => "%" . $v . "%"}};
                    } elsif ($unit->{"__between"} and could_be_range($v)) {
                        push @$clause, {$k => {"between" => $v}};
                    } elsif (check_1d_max($v)) {
                        push @$clause, {$k => $v};
                    }
                }
            }
        }
        push @{$outer_clause->{$conj}}, {"+" . $class => $clause};
    }

    if ($terms->{"acqlia"}) {
        push @{$outer_clause->{$conj}},
            $is_and ? prepare_acqlia_search_and($terms->{"acqlia"}) :
                prepare_acqlia_search_or($terms->{"acqlia"});
    }

    return undef unless scalar keys %$outer_clause;
    $outer_clause;
}

__PACKAGE__->register_method(
    method    => "grand_search",
    api_name  => "open-ils.acq.lineitem.grand_search",
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
    method    => "grand_search",
    api_name  => "open-ils.acq.purchase_order.grand_search",
    signature => {
        desc   => q/Returns purchase orders based on flexible search terms.
            See open-ils.acq.lineitem.grand_search/,
        return => {desc => "A stream of POs on success, Event on failure"}
    }
);

__PACKAGE__->register_method(
    method    => "grand_search",
    api_name  => "open-ils.acq.picklist.grand_search",
    signature => {
        desc   => q/Returns pick lists based on flexible search terms.
            See open-ils.acq.lineitem.grand_search/,
        return => {desc => "A stream of PLs on success, Event on failure"}
    }
);

sub grand_search {
    my ($self, $conn, $auth, $and_terms, $or_terms, $conj, $options) = @_;
    my $e = new_editor("authtoken" => $auth);
    return $e->die_event unless $e->checkauth;

    # What kind of object are we returning? Important: (\w+) had better be
    # a legit acq classname particle, so don't register any crazy api_names.
    my $ret_type = ($self->api_name =~ /cq.(\w+).gr/)[0];
    my $retriever = $RETRIEVERS{$ret_type};

    my $query = {
        "select" => {
            F("acq::$ret_type")->{"hint"} =>
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
        }
    };

    $and_terms = prepare_terms($and_terms, 1);
    $or_terms = prepare_terms($or_terms, 0) and do {
        $query->{"from"}->{"jub"}->{"acqlia"} = {
            "type" => "left", "field" => "lineitem", "fkey" => "id",
        };
    };

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
    $conn->respond($retriever->($e, $_->{"id"}, $options)) foreach (@$results);
    $e->disconnect;
    undef;
}

1;
