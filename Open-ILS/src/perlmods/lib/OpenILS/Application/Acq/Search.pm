package OpenILS::Application::Acq::Search;
use base "OpenILS::Application";

use strict;
use warnings;

use OpenSRF::AppSession;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenILS::Event;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::Acq::Lineitem;
use OpenILS::Application::Acq::Financials;
use OpenILS::Application::Acq::Picklist;
use OpenILS::Application::Acq::Invoice;
use OpenILS::Application::Acq::Order;

my %RETRIEVERS = (
    "lineitem" =>
        \&{"OpenILS::Application::Acq::Lineitem::retrieve_lineitem_impl"},
    "picklist" =>
        \&{"OpenILS::Application::Acq::Picklist::retrieve_picklist_impl"},
    "purchase_order" => \&{
        "OpenILS::Application::Acq::Financials::retrieve_purchase_order_impl"
    },
    "invoice" => \&{
        "OpenILS::Application::Acq::Invoice::fetch_invoice_impl"
    },
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

sub castdate {
    my ($value, $gte, $lte) = @_;

    my $op = "=";
    $op = ">=" if $gte;
    $op = "<=" if $lte;

    +{$op => {"transform" => "date", "value" => $value}};
}

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
        $term->{"__castdate"} ? 1 : 0,
        $term->{"__gte"} ? 1 : 0,
        $term->{"__lte"} ? 1 : 0
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
    my $lc_value = {
        "=" => { transform => "lowercase", value => lc($value) }
    };

    +{
        "-or" => [
            {"+au$n" => {"usrname" => $value}},
            {"+au$n" => {"first_given_name" => $lc_value}},
            {"+au$n" => {"second_given_name" => $lc_value}},
            {"+au$n" => {"family_name" => $lc_value}},
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

    foreach my $class (qw/acqpo acqpl acqinv jub acqlid acqlisum acqlisumi/) {
        next if not exists $terms->{$class};

        $outer_clause->{$conj} = [] unless $outer_clause->{$conj};
        foreach my $unit (@{$terms->{$class}}) {
            my ($k, $v, $fuzzy, $between, $not, $castdate, $gte, $lte) =
                breakdown_term($unit);

            my $term_clause;
            if ($fuzzy and not ref $v) {
                $term_clause = {$k => {"ilike" => "%" . $v . "%"}};
            } elsif ($between and could_be_range($v)) {
                $term_clause = {$k => {"between" => $v}};
            } elsif (check_1d_max($v)) {
                if ($castdate) {
                    $v = castdate($v, $gte, $lte) if $castdate;
                } elsif ($gte or $lte) {
                    my $op = $gte ? '>=' : '<=';
                    $v = {$op => $v};
                }
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
    my $graft_map = shift;
    my $core_hint = shift;

    my $n = 0;
    foreach my $join (@_) {
        my ($hint, $attr, $num) = @$join;
        my $start = $graft_map->{$hint};
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

        if ($hint eq $core_hint) {
            $start->{"au$num"} = $clause;
        } else {
            $start->{"join"} ||= {};
            $start->{"join"}->{"au$num"} = $clause;
        }

        $n++;
    }
    $n;
}

sub build_from_clause_and_joins {
    my ($query, $core, $and_terms, $or_terms) = @_;

    my %graft_map = ();

    $graft_map{$core} = $query->{from}{$core} = {};

    my $join_type = keys(%$or_terms) ? "left" : "inner";

    my @classes = grep { $core ne $_ } (keys(%$and_terms), keys(%$or_terms));
    my %classes_uniq = map { $_ => 1 } @classes;
    @classes = keys(%classes_uniq);

    my $acqlia_join = sub {
        return {"type" => "left", "field" => "lineitem", "fkey" => "id"};
    };

    foreach my $class (@classes) {
        if ($class eq 'acqlia') {
            if ($core eq 'acqinv') {
                $graft_map{acqlia} =
                    $query->{from}{$core}{acqmapinv}{join}{jub}{join}{acqlia} =
                    $acqlia_join->();
            } elsif ($core eq 'jub') {
                $graft_map{acqlia} = 
                    $query->{from}{$core}{acqlia} =
                    $acqlia_join->();
            } else {
                $graft_map{acqlia} = 
                    $query->{from}{$core}{jub}{join}{acqlia} =
                    $acqlia_join->();
            }
        } elsif ($class eq 'acqinv' or $core eq 'acqinv') {
            $graft_map{$class} =
                $query->{from}{$core}{acqmapinv}{join}{$class} ||= {};
            $graft_map{$class}{type} = $join_type;
        } else {
            $graft_map{$class} = $query->{from}{$core}{$class} ||= {};
            $graft_map{$class}{type} = $join_type;

            # without this, the SQL attempts to join on 
            # jub.order_summary, which is a virtual field.
            $graft_map{$class}{field} = 'lineitem' 
                if $class eq 'acqlisum' or $class eq 'acqlisumi';
        }
    }

    return \%graft_map;
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

__PACKAGE__->register_method(
    method    => "unified_search",
    api_name  => "open-ils.acq.invoice.unified_search",
    stream    => 1,
    signature => {
        desc   => q/Returns invoices lists based on flexible search terms.
            See open-ils.acq.lineitem.unified_search/,
        return => {desc => "A stream of invoices on success, Event on failure"}
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

    my $select_clause = {
        $hint => [{"column" => "id", "transform" => "distinct"}]
    };

    my $attr_from_filter;
    if ($options->{"order_by"}) {
        # What's the point of this block?  When using ORDER BY in conjuction
        # with SELECT DISTINCT, the fields present in ORDER BY have to also
        # be in the SELECT clause.  This will take _one_ such field and add
        # it to the SELECT clause as needed.
        my ($order_by, $class, $field);
        unless (
            ($order_by = $options->{"order_by"}->[0]) &&
            ($class = $order_by->{"class"}) =~ /^[\da-z_]+$/ &&
            ($field = $order_by->{"field"}) =~ /^[\da-z_]+$/
        ) {
            $e->disconnect;
            return new OpenILS::Event(
                "BAD_PARAMS", "note" =>
q/order_by clause must be of the long form, like:
"order_by": [{"class": "foo", "field": "bar", "direction": "asc"}]/
            );

        } else {

            # we can't combine distinct(id) with another select column, 
            # since the non-distinct column may arbitrarily (via hash keys)
            # sort to the front of the final SQL, which PG will complain about.  
            $select_clause = { $hint => ["id"] };
            $select_clause->{$class} ||= [];
            push @{$select_clause->{$class}}, 
                {column => $field, transform => 'first', aggregate => 1};

            # when sorting by LI attr values, we have to limit 
            # to a specific type of attr value to sort on.
            if ($class eq 'acqlia') {
                $attr_from_filter = {
                    "fkey" => "id",
                    "filter" => {
                        "attr_type" => "lineitem_marc_attr_definition",
                        "attr_name" => $options->{"order_by_attr"} || "title"
                    },
                    "type" => "left",
                    "field" =>"lineitem"
                };
            }
        }
    }

    my $query = {
        select => $select_clause,
        order_by => ($options->{order_by} || {$hint => {id => {}}}),
        offset => ($options->{offset} || 0)
    };

    $query->{"limit"} = $options->{"limit"} if $options->{"limit"};

    my $graft_map = build_from_clause_and_joins(
        $query, $hint, $and_terms, $or_terms
    );

    $and_terms = prepare_terms($and_terms, 1);
    $or_terms = prepare_terms($or_terms, 0);

    my $offset = add_au_joins($graft_map, $hint, prepare_au_terms($and_terms));
    add_au_joins($graft_map, $hint, prepare_au_terms($or_terms, $offset));

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


    # if ordering by acqlia, insert the from clause 
    # filter to limit to one type of attr.
    if ($attr_from_filter) {
        $query->{from}->{jub} = {} unless $query->{from}->{jub};
        $query->{from}->{jub}->{acqlia} = $attr_from_filter;
    }

    my $results = $e->json_query($query) or return $e->die_event;
    my @id_list = map { $_->{"id"} } (grep { $_->{"id"} } @$results);

    if ($options->{"id_list"}) {
        $conn->respond($_) foreach @id_list;
    } else {
        foreach(@id_list){
            my $resp = $retriever->($e, $_, $options);
            next if(ref($resp) ne "Fieldmapper::acq::$ret_type");
            $conn->respond($resp);
        }
    }

    $e->disconnect;
    undef;
}

__PACKAGE__->register_method(
    method    => "bib_search",
    api_name  => "open-ils.acq.biblio.wrapped_search",
    stream    => 1,
    signature => {
        desc   => q/Returns new lineitems for each matching bib record/,
        params => [
            {desc => "Authentication token", type => "string"},
            {desc => "search string", type => "string"},
            {desc => "search options", type => "object"}
        ],
        return => {desc => "A stream of LIs on success, Event on failure"}
    }
);

__PACKAGE__->register_method(
    method    => "bib_search",
    api_name  => "open-ils.acq.biblio.create_by_id",
    stream    => 1,
    signature => {
        desc   => q/Returns new lineitems for each matching bib record/,
        params => [
            {desc => "Authentication token", type => "string"},
            {desc => "list of bib IDs", type => "array"},
            {desc => "options (for lineitem fleshing)", type => "object"}
        ],
        return => {desc => "A stream of LIs on success, Event on failure"}
    }
);

# This is very similar to zsearch() in Order.pm
sub bib_search {
    my ($self, $conn, $auth, $search, $opts) = @_;

    my $e = new_editor("authtoken" => $auth, "xact" => 1);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed("CREATE_PICKLIST");

    my $mgr = new OpenILS::Application::Acq::BatchManager(
        "editor" => $e, "conn" => $conn
    );

    $opts ||= {};

    my $picklist;
    my @li_ids = ();
    if ($self->api_name =~ /create_by_id/) {
        $search = [ sort @$search ]; # for consitency
        my $bibs = $e->search_biblio_record_entry(
            {"id" => $search}, {"order_by" => {"bre" => ["id"]}}
        ) or return $e->die_event;

        if ($opts->{"reuse_picklist"}) {
            $picklist = $e->retrieve_acq_picklist($opts->{"reuse_picklist"}) or
                return $e->die_event;
            return $e->die_event unless
                $e->allowed("UPDATE_PICKLIST", $picklist->org_unit);

            # If we're reusing an existing picklist, we don't need to
            # create new lineitems for any bib records for which we already

            my $already_have = $e->search_acq_lineitem({
                "picklist" => $picklist->id,
                "eg_bib_id" => [ map { $_->id } @$bibs ]
            }) or return $e->die_event;
         
            # So in that case we a) save the lineitem id's of the relevant
            # items that already exist so that we can return those items later,
            # and b) remove the bib id's in question from our list of bib
            # id's to lineitemize.
            if (@$already_have) {
                push @li_ids, $_->id foreach (@$already_have);
                my @new_bibs = ();
                foreach my $bib (@$bibs) {
                    push @new_bibs, $bib unless
                        grep { $_->eg_bib_id == $bib->id } @$already_have;
                }
                $bibs = [ @new_bibs ];
            }
        } else {
            $picklist = OpenILS::Application::Acq::Order::zsearch_build_pl($mgr, undef)
                or return $e->die_event;
        }

        $conn->respond($picklist->id);

        push @li_ids, map {
            OpenILS::Application::Acq::Order::create_lineitem(
                $mgr,
                "picklist" => $picklist->id,
                "source_label" => "native-evergreen-catalog",
                "marc" => $_->marc,
                "eg_bib_id" => $_->id
            )->id;
        } (@$bibs);
    } else {
        $opts->{"limit"} ||= 10;

        my $ses = create OpenSRF::AppSession("open-ils.search");
        my $req = $ses->request(
            "open-ils.search.biblio.multiclass.query.staff", $opts, $search
        );

        my $count = 0;
        while (my $resp = $req->recv("timeout" => 60)) {
            $picklist = OpenILS::Application::Acq::Order::zsearch_build_pl(
                $mgr, undef
            ) unless $count++;

            my $result = $resp->content;
            next if not ref $result;

            # The result object contains a whole heck of a lot more information
            # than just bib IDs, so maybe we could tell the client something
            # useful (progress meter at least) in the future...
            push @li_ids, map {
                my $bib = $_->[0];
                OpenILS::Application::Acq::Order::create_lineitem(
                    $mgr,
                    "picklist" => $picklist->id,
                    "source_label" => "native-evergreen-catalog",
                    "marc" => $e->retrieve_biblio_record_entry($bib)->marc,
                    "eg_bib_id" => $bib
                )->id;
            } (@{$result->{"ids"}});
        }
        $ses->disconnect;
    }

    $e->commit;

    $logger->info("created @li_ids new lineitems for picklist $picklist");

    # new editor, but still using transaction to ensure correct retrieval
    # in a replicated setup
    $e = new_editor("authtoken" => $auth, xact => 1) or return $e->die_event;
    return $e->die_event unless $e->checkauth;
    $conn->respond($RETRIEVERS{"lineitem"}->($e, $_, $opts)) foreach @li_ids;
    $e->rollback;
    $e->disconnect;

    undef;
}

1;
