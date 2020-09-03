package OpenILS::WWW::EGCatLoader;
use strict; use warnings;
use Apache2::Const -compile => qw(OK DECLINED FORBIDDEN HTTP_GONE HTTP_INTERNAL_SERVER_ERROR REDIRECT HTTP_BAD_REQUEST HTTP_NOT_FOUND);
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
use Net::HTTP::NB;
use IO::Select;
my $U = 'OpenILS::Application::AppUtils';

sub load_course {
    my $self = shift;
    my $ctx = $self->ctx;

    $ctx->{page} = 'course';
    $ctx->{readonly} = $self->cgi->param('readonly');

    my $course_id = $ctx->{page_args}->[0];

    return Apache2::Const::HTTP_BAD_REQUEST
        unless $course_id and $course_id =~ /^\d+$/;

    $ctx->{course} = $U->simplereq(
        'open-ils.courses',
        'open-ils.courses.courses.retrieve',
        [$course_id]
    )->[0];
    
    $ctx->{instructors} = $U->simplereq(
        'open-ils.courses',
        'open-ils.courses.course_users.retrieve',
        $course_id
    );

    $ctx->{course_materials} = $U->simplereq(
        'open-ils.courses',
        'open-ils.courses.course_materials.retrieve.fleshed.atomic',
        {course => $course_id}
    );
    return Apache2::Const::OK;
}

sub load_course_browse {
    my $self = shift;
    my $cgi = $self->cgi;
    my $ctx = $self->ctx;
    my $e = $self->editor;

    my $browse_results = [];

    # Are we searching? Cool, let's generate some links
    if ($cgi->param('bterm')) {
        my $bterm = $cgi->param('bterm');
        my $qtype = $cgi->param('qtype');
        # Search term is optional. If it's empty, start at the
        # beginning. Otherwise, center results on a match.
        # Regardless, we're listing everything, so retrieve all.
        my $results;
        my $instructors;
        if ($qtype eq 'instructor') {
            $instructors = $e->json_query({
                "from" => "acmcu",
                "select" => {"acmcu" => [
                    'id',
                    'usr',
                ]},
                # TODO: We need to support the chosen library as well...
                "where" => {'usr_role' => {'in' => {'from' => 'acmr', 'select' => {'acmr' => ['id']}, 'where' => {'+acmr' => 'is_public'}}}}
            });
            $results = $e->json_query({
                "from" => "au",
                "select" => {"au" => [
                    'id',
                    'pref_first_given_name',
                    'first_given_name',
                    'pref_second_given_name',
                    'second_given_name',
                    'pref_family_name',
                    'family_name'
                ]},
                "order_by" => {'au' => ['pref_family_name', 'family_name']},
                "where" => {'-and' => [{
                    "id" => { "in" => {
                        "from" => "acmcu",
                        "select" => {
                            "acmcu" => ['usr']
                        },
                        "where" => {'-and' => [
                            {'usr_role' => { 'in' => {
                                'from' => 'acmr',
                                "select" => {
                                    "acmr" => ['id']
                                },
                                "where" => {'+acmr' => 'is_public'}}}},
                            {"course" => { "in" =>{
                                "from" => "acmc",
                                "select" => {
                                    "acmc" => ['id']
                                },
                                "where" => {'-not' => [{'+acmc' => 'is_archived'}]}
                            }}}
                        ]}
                    }}
                }]}
            });
        } else {
            $results = $e->json_query({
                "from" => "acmc",
                "select" => {"acmc" => [
                    'id',
                    'name',
                    'course_number',
                    'is_archived',
                    'owning_lib'
                ]},
                "order_by" => {"acmc" => [$qtype]},
                # TODO: We need to support the chosen library as well...
                "where" => {'-not' => {'+acmc' => 'is_archived'}}
            });
        }
        my $bterm_match = 0;
        for my $result(@$results) {
            my $value_exists = 0;
            my $rqtype = $qtype;
            my $entry = {
                'value' => '',
                'results_count' => 0,
                'match' => 0
            };

            if ($qtype eq 'instructor') {
                # Put together the name
                my $name_str = '';
                if ($result->{'pref_family_name'}) {
                    $name_str = $result->{'pref_family_name'} . ", ";
                } elsif ($result->{'family_name'}) {
                    $name_str = $result->{'family_name'} . ", ";
                }

                if ($result->{'pref_first_given_name'}) {
                    $name_str .= $result->{'pref_first_given_name'};
                } elsif ($result->{'first_given_name'}) {
                    $name_str .= $result->{'first_given_name'};
                }

                if ($result->{'pref_second_given_name'}) {
                    $name_str .= " " . $result->{'pref_second_given_name'};
                } elsif ($result->{'second_given_name'}) {
                    $name_str .= " " . $result->{'second_given_name'};
                }

                $result->{$rqtype} = $name_str;

                # Get an accurate count of matching courses
                for my $instructor(@$instructors) {
                    if ($instructor->{'usr'} eq $result->{'id'}) {
                        $entry->{'results_count'} += 1;
                        last;
                    }
                }
            } else {
                $entry->{'results_count'} += 1;
            }

            for my $existing_entry(@$browse_results) {
                if ($existing_entry->{'value'} eq $result->{$rqtype} && $value_exists eq 0) {
                    $value_exists = 1;
                    $existing_entry->{'results_count'} += 1;
                    last;
                }
            }

            if ($value_exists eq 0) {
                # For Name/Course Number browse queries...
                if ($bterm_match eq 0) {
                    if ($result->{$qtype} =~ m/^$bterm./ || $result->{$qtype} eq $bterm) {
                        $bterm_match = 1;
                        $entry->{'match'} = 1;
                    }
                }
                $entry->{'value'} = $result->{$rqtype};
                push @$browse_results, $entry;
            }
        }
        # Feels a bit hacky, but we need the index of the matching entry
        my $match_idx = 0;
        if ($bterm_match) {
            for my $i (0..$#$browse_results) {
                if ($browse_results->[$i]->{'match'}) {
                    $match_idx = $i;
                    last;
                }
            }
        }

        for my $i(0..$#$browse_results) {
            $browse_results->[$i]->{'browse_index'} = $i;
        }
        $ctx->{match_idx} = $match_idx;
        $ctx->{browse_results} = $browse_results;
    }

    return Apache2::Const::OK;
}

sub load_cresults {
    my $self = shift;
    my %args = @_;
    my $internal = $args{internal};
    my $cgi = $self->cgi;
    my $ctx = $self->ctx;
    my $e = $self->editor;
    my $limit = 10;

    $ctx->{page} = 'cresult' unless $internal;
    $ctx->{ids} = [];
    $ctx->{courses} = [];
    $ctx->{hit_count} = 0;
    $ctx->{search_ou} = $self->_get_search_lib();
    my $page = $cgi->param('page') || 0;
    my $offset = $page * $limit;
    my $results;
    $ctx->{page_size} = $limit;
    $ctx->{search_page} = $page;
    $ctx->{pagable_limit} = 50;

    # fetch this page plus the first hit from the next page
    if ($internal) {
        $limit = $offset + $limit + 1;
        $offset = 0;
    }

    my ($user_query, $query, @queries, $modifiers) = _prepare_course_search($cgi, $ctx);

    return Apache2::Const::OK unless $query;

    $ctx->{user_query} = $user_query;
    $ctx->{processed_search_query} = $query;
    my $search_args = {};
    my $course_numbers = ();
    
    my $where_clause;
    my $and_terms = [];
    my $or_terms = [];

    # Handle is_archived checkbox and Org Selector
    my $search_orgs = $U->get_org_descendants($ctx->{search_ou});
    push @$and_terms, {'owning_lib' => $search_orgs};
    push @$and_terms, {'-not' => {'+acmc' => 'is_archived'}} unless $query =~ qr\#include_archived\;

    # Now let's push the actual queries
    for my $query_obj (@queries) {
        my $type = $query_obj->{'qtype'};
        my $query = $query_obj->{'value'};
        my $bool = $query_obj->{'bool'};
        my $contains = $query_obj->{'contains'};
        my $operator = ($contains eq 'nocontains') ? '!~*' : '~*';
        my $search_query;
        if ($type eq 'instructor') {
            my $in = ($contains eq 'nocontains') ? "not in" : "in";
            $search_query = {'id' => {$in => {
                'from' => 'acmcu',
                'select' => {'acmcu' => ['course']},
                'where' => {'usr' => {'in' => {
                    'from' => 'au',
                    'select' => {'au' => ['id']},
                    'where' => {
                        'name_kw_tsvector' => {
                            '@@' => {'value' => [ 'plainto_tsquery', $query ] }
                        }
                    }
                }}}
            }}};
        } else {
            $search_query = ($contains eq 'nocontains') ?
              {'+acmc' => { $type => {$operator => $query}}} :
              {$type => {$operator => $query}};
        }

        if ($bool eq 'or') {
            push @$or_terms, $search_query;
        }

        if ($bool eq 'and') {
            push @$and_terms, $search_query;
        }
    }

    if ($or_terms and @$or_terms > 0) {
        if ($and_terms and @$and_terms > 0) {
            push @$or_terms, $and_terms;
        }
        $where_clause = {'-or' => $or_terms};
    } else {
        $where_clause = {'-and' => $and_terms};
    }

    my $hits = $e->json_query({
        "from" => "acmc",
        "select" => {"acmc" => ['id']},
        "where" => $where_clause
    });

    my $results = $e->json_query({
        "from" => "acmc",
        "select" => {"acmc" => [
            'id',
            'name',
            'course_number',
            'section_number',
            'is_archived',
            'owning_lib'
        ]},
        "limit" => $limit,
        "offset" => $offset,
        "order_by" => {"acmc" => ['id']},
        "where" => $where_clause
    });
    for my $result (@$results) {
        push @{$ctx->{courses}}, {
            id => $result->{id},
            course_number => $result->{course_number},
            section_number => $result->{section_number},
            owning_lib => $result->{owning_lib},
            name => $result->{name},
            is_archived => $result->{is_archived},
            instructors => []
        }
    }

    #$ctx->{courses} = $@courses;#[{id=>10, name=>"test", course_number=>"LIT"}];
    $ctx->{hit_count} = @$hits || 0;
    #$ctx->{hit_count} = 0;
    return Apache2::Const::OK;
}

sub _prepare_course_search {
    my ($cgi, $ctx) = @_;

    my ($user_query, @queries) = _prepare_query($cgi);
    my $modifiers;
    $user_query //= '';

    my $query = $user_query;
    $query .= ' ' . $ctx->{global_search_filter} if $ctx->{global_search_filter};

    foreach ($cgi->param('modifier')) {
        $query = ('#' . $_ . ' ' . $query) unless $query =~ qr/\#\Q$_/;

    }
    # filters
    foreach (grep /^fi:/, $cgi->param) {
        /:(-?\w+)$/ or next;
        my $term = join(",", $cgi->param($_));
        $query .= " $1($term)" if length $term;
    }

    return () unless $query;

    return ($user_query, $query, @queries);
}

sub _prepare_query {
    my $cgi = shift;

    return $cgi->param('query') unless $cgi->param('qtype');

    my %parts;
    my @part_names = qw/qtype contains query bool modifier/;
    $parts{$_} = [ $cgi->param($_) ] for (@part_names);

    my $full_query = '';
    my @queries;
    for (my $i = 0; $i < scalar @{$parts{'qtype'}}; $i++) {
        my ($qtype, $contains, $query, $bool, $modifier) = map { $parts{$_}->[$i] } @part_names;
        next unless $query =~ /\S/;

        $contains = "" unless defined $contains;

        push @queries, {
            contains => $contains,
            bool => $bool,
            qtype => $qtype,
            value => $query
        };

        $bool = ($bool and $bool eq 'or') ? '||' : '&&';

        $query = "$qtype:$query";

        $full_query = $full_query ? "($full_query $bool $query)" : $query;
    }

    return ($full_query, @queries);
}
