package OpenILS::OpenAPI::Controller::search;
use strict;
use warnings;
use OpenILS::OpenAPI::Controller;
use OpenILS::Application::AppUtils;

our $VERSION = 1;
my $U = 'OpenILS::Application::AppUtils';

sub multiclass_search {
    my ($c, $ses, $title, $author, $subject, $series, $keyword, $identifier, $isbn, $issn, $org_unit, $depth, $limit, $offset, $sort, $sort_dir, $tag_circulated_records, $query, $docache) = @_;

    # Before we get too involved, let's validate that sort and
    # sort_dir are correct if needed.
    if (defined($sort)) {
        $sort = lc($sort);
        if ($sort !~ /^(?:author|title|pubdate|edit_date|create_date|rel|poprel)$/) {
            $c->res->code(400);
            return {error=>"Bad value for sort ($sort). Must be one of author|title|pubdate|edit_date|create_date|rel|poprel."};
        }
        if ($sort_dir !~ /^(?:asc|desc)$/i) {
            $c->res->code(400);
            return {error=>"Bad value for sort_dir ($sort_dir). Must be one of asc|desc."};
        }

    }

    # Set a default of 'true' for $docache:
    $docache = 1 unless(defined($docache));

    # See perldoc OpenILS::Application::Search::Biblio for the
    # rationale for the following code and comments.
    #
    # The following parmeters go into the searches hash:
    # $title => title
    # $author => author
    # $subject => subject
    # $series => series
    # $keyword => keyword
    # $identifier => identifier
    # $isbn => isbn
    # $issn => issn
    my %searches = ();
    add_to_hash($title, 'title', \%searches) if ($title && @{$title});
    add_to_hash($author, 'author', \%searches) if ($author && @{$author});
    add_to_hash($subject, 'subject', \%searches) if ($subject && @{$subject});
    add_to_hash($series, 'series', \%searches) if ($series && @{$series});
    add_to_hash($keyword, 'keyword', \%searches) if ($keyword && @{$keyword});
    add_to_hash($identifier, 'identifier', \%searches)
        if ($identifier && @{$identifier});
    add_to_hash($isbn, 'isbn', \%searches) if ($isbn && @{$isbn});
    add_to_hash($issn, 'issn', \%searches) if ($issn && @{$issn});

    # The searches hash, plus the following go into the arghash:
    # $org_unit => org_unit
    # $depth => depth
    # $limit => limit
    # $offset => offset
    # $sort => sort
    # $sort_dir => sort_dir
    # $tag_circulated_records => tag_circulated_records
    my %arghash = ();
    $arghash{searches} = \%searches if (%searches);
    if (defined($org_unit)) {
        $arghash{org_unit} = $org_unit;
    }
    if (defined($depth)) {
        $arghash{depth} = $depth;
    }
    if (defined($limit)) {
        $arghash{limit} = $limit;
    }
    if (defined($offset)) {
        $arghash{offset} = $offset;
    }
    if (defined($sort)) {
        $arghash{sort} = $sort;
        $arghash{sort_dir} = $sort_dir;
    }

    # If tag_circulated_records is true, then the authtoken is added
    # to arghash:
    # $ses => authtoken
    if (defined($tag_circulated_records)) {
        $arghash{tag_circulated_records} = ($tag_circulated_records) ? 1 : 0;
        if ($tag_circulated_records) {
            $arghash{authtoken} = $ses;
        }
    }

    # If $query has a value, we run
    # open-ils.search.biblio.multiclass.query and put the $query
    # between arghash and docache.
    if (defined($query)) {
        return $U->simplereq(
            'open-ils.search',
            'open-ils.search.biblio.multiclass.query',
            \%arghash,
            $query,
            ($docache) ? 1 : 0
        );
    }

    # $query does not have a value so we run
    # open-ils.search.biblio.multiclass.
    return $U->simplereq(
        'open-ils.search',
        'open-ils.search.biblio.multiclass',
        \%arghash,
        ($docache) ? 1 : 0
    );
}

# Add arrayref of values as field to hashref
sub add_to_hash {
    my $values = shift;
    my $field = shift;
    my $hash = shift;
    my $pval = join_parameters($values);
    if (length($pval)) {
        $hash->{"$field"} = $pval;
    }
}

# Join multiple parameters into 1 string.
sub join_parameters {
    my $params = shift;
    my $pstring = "";
    foreach my $value (@{$params}) {
        my $norm = normalize_param($value);
        if (length($norm)) {
            $pstring .= ' || ' if (length($pstring));
            $pstring .= $norm;
        }
    }
    return $pstring;
}

# Remove excess spaces and possibly other junk from a search
# parameter.
sub normalize_param {
    my $pvalue = shift;
    $pvalue =~ s/^\s+//;
    $pvalue =~ s/\s+$//;
    $pvalue =~ s/\s+/ /g;
    return $pvalue;
}

1;
