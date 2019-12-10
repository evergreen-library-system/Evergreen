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
        'open-ils.circ',
        'open-ils.circ.courses.retrieve',
        [$course_id]
    )->[0];
    
    $ctx->{instructors} = $U->simplereq(
        'open-ils.circ',
        'open-ils.circ.course_users.retrieve',
        $course_id
    );

    $ctx->{course_materials} = $U->simplereq(
        'open-ils.circ',
        'open-ils.circ.course_materials.retrieve.fleshed',
        {course => $course_id}
    );
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
                        '-or' => [
                            {'pref_first_given_name' => {'~*' => $query}},
                            {'first_given_name' => {'~*' => $query}},
                            {'pref_second_given_name' => {'~*' => $query}},
                            {'second_given_name' => {'~*' => $query}},
                            {'pref_family_name' => {'~*' => $query}},
                            {'family_name' => {'~*' => $query}}
                        ]
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