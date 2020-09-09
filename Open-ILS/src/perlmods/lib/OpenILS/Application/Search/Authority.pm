package OpenILS::Application::Search::Authority;
use base qw/OpenILS::Application/;
use strict; use warnings;

use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
use MARC::Record;
use MARC::File::XML (BinaryEncoding => 'UTF-8');
use MARC::Charset;
use XML::LibXML;
use XML::LibXSLT;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenSRF::Utils::Logger qw/$logger/;

use OpenSRF::Utils::JSON;

use Time::HiRes qw(time);
use OpenSRF::EX qw(:try);
use Digest::MD5 qw(md5_hex);

my $cache;


sub validate_authority {
    my $self = shift;
    my $client = shift;

    my $session = OpenSRF::AppSession->create("open-ils.storage");
    return $session->request( 'open-ils.storage.authority.validate.tag' => @_ )->gather(1);
}
__PACKAGE__->register_method(
        method      => "validate_authority",
        api_name    => "open-ils.search.authority.validate.tag",
        argc        => 4, 
        note        => "Validates authority data from existing controlled terms",
);              

sub validate_authority_return_records_by_id {
    my $self = shift;
    my $client = shift;

    my $session = OpenSRF::AppSession->create("open-ils.storage");
    return $session->request( 'open-ils.storage.authority.validate.tag.id_list' => @_ )->gather(1);
}
__PACKAGE__->register_method(
        method      => "validate_authority_return_records_by_id",
        api_name    => "open-ils.search.authority.validate.tag.id_list",
        argc        => 4, 
        note        => "Validates authority data from existing controlled terms",
);              

sub search_authority {
    my $self = shift;
    my $client = shift;

    my $session = OpenSRF::AppSession->create("open-ils.storage");
    return $session->request( 'open-ils.storage.authority.search.marc.atomic' => @_ )->gather(1);
}
__PACKAGE__->register_method(
        method      => "search_authority",
        api_name    => "open-ils.search.authority.fts",
        argc        => 2, 
        note        => "Searches authority data for existing controlled terms and crossrefs",
);              

sub search_authority_by_simple_normalize_heading {
    my $self = shift;
    my $client = shift;
    my $marcxml = shift;
    my $controlset = shift;

    my $norm_heading_query = {
        from => [ 'authority.simple_normalize_heading' => $marcxml ]
    };

    my $e = new_editor();
    my $norm_heading = $e->json_query($norm_heading_query)->[0]->{'authority.simple_normalize_heading'};

    unless (defined($norm_heading) && $norm_heading != '') {
        return OpenILS::Event->new('BAD_PARAMS', note => 'Heading normalized to null or empty string');
    }

    my $query = {
        select => { are => ['id'] },
        from   => 'are',
        where  => {
            deleted => 'f',
            simple_heading => {
                'startwith' => $norm_heading
            },
            defined($controlset) ? ( control_set => $controlset ) : ()
        }
    };

    $client->respond($_->{id}) for @{ $e->json_query( $query ) };
    $client->respond_complete;
}
__PACKAGE__->register_method(
        method      => "search_authority_by_simple_normalize_heading",
        api_name    => "open-ils.search.authority.simple_heading.from_xml",
        argc        => 1, 
        stream      => 1,
        note        => "Searches authority data by main entry using marcxml, returning 'are' ids; params are marcxml and optional control-set-id",
);

sub search_authority_batch_by_simple_normalize_heading {
    my $self = shift;
    my $client = shift;
    my $search_set = [@_];

    my $m = $self->method_lookup('open-ils.search.authority.simple_heading.from_xml.atomic');

    for my $s ( @$search_set ) {
        for my $k ( keys %$s ) {
            $client->respond( { $k => $m->run( $s->{$k}, $k ) } );
        }
    }

    $client->respond_complete;
}
__PACKAGE__->register_method(
        method      => "search_authority_batch_by_simple_normalize_heading",
        api_name    => "open-ils.search.authority.simple_heading.from_xml.batch",
        argc        => 1, 
        stream      => 1,
        note        => "Searches authority data by main entry using marcxml, in control-set batches, returning 'are' ids; params are hashes of { control-set-id => marcxml }",
);


sub crossref_authority {
    my $self = shift;
    my $client = shift;
    my $class = shift;
    my $term = shift;
    my $limit = shift || 10;

    my $session = OpenSRF::AppSession->create("open-ils.storage");

    # Avoid generating spurious errors for more granular indexes, like author|personal
    $class =~ s/^(.*?)\|.*?$/$1/;

    $logger->info("authority xref search for $class=$term, limit=$limit");
    my $fr = $session->request(
        "open-ils.storage.authority.$class.see_from.controlled.atomic",$term, $limit)->gather(1);
    my $al = $session->request(
        "open-ils.storage.authority.$class.see_also_from.controlled.atomic",$term, $limit)->gather(1);

    my $data = _auth_flatten( $term, $fr, $al, 1 );

    return $data;
}

sub _auth_flatten {
    my $term = shift;
    my $fr = shift;
    my $al = shift;
    my $limit = shift;

    my %hash = ();
    for my $x (@$fr) {
        my $string = $$x[0];
        for my $i (1..10) {
            last unless ($$x[$i]);
            if ($string =~ /\W$/o) {
                $string .= ' '.$$x[$i];
            } else {
                $string .= ' -- '.$$x[$i];
            }
        }
        next if (lc($string) eq lc($term));
        $hash{$string}++;
        $hash{$string}++ if (lc($$x[0]) eq lc($term));
    }
    my $from = [keys %hash]; #[ sort { $hash{$b} <=> $hash{$a} || $a cmp $b } keys %hash ];

#   $from = [ @$from[0..4] ] if $limit;

    %hash = ();
    for my $x (@$al) {
        my $string = $$x[0];
        for my $i (1..10) {
            last unless ($$x[$i]);
            if ($string =~ /\W$/o) {
                $string .= ' '.$$x[$i];
            } else {
                $string .= ' -- '.$$x[$i];
            }
        }
        next if (lc($string) eq lc($term));
        $hash{$string}++;
        $hash{$string}++ if (lc($$x[0]) eq lc($term));
    }
    my $also = [keys %hash]; #[ sort { $hash{$b} <=> $hash{$a} || $a cmp $b } keys %hash ];

#   $also = [ @$also[0..4] ] if $limit;

    #warn Dumper( { from => $from, also => $also } );

    return { from => $from, also => $also };
}

__PACKAGE__->register_method(
        method      => "crossref_authority",
        api_name    => "open-ils.search.authority.crossref",
        argc        => 2, 
        note        => "Searches authority data for existing controlled terms and crossrefs",
);              

__PACKAGE__->register_method(
    #method     => "new_crossref_authority_batch",
    method      => "crossref_authority_batch2",
    api_name    => "open-ils.search.authority.crossref.batch",
    argc        => 1, 
    note        => <<"    NOTE");
    Takes an array of class,term pair sub-arrays and performs an authority lookup for each

    PARAMS( [ ["subject", "earth"], ["author","shakespeare"] ] );

    Returns an object like so:
    {
        "classname" : {
            "term" : { "from" : [ ...], "also" : [...] }
            "term2" : { "from" : [ ...], "also" : [...] }
        }
    }
    NOTE

sub new_crossref_authority_batch {
    my( $self, $client, $reqs ) = @_;

    my $response = {};
    my $lastr = [];
    my $session = OpenSRF::AppSession->create("open-ils.storage");

    for my $req (@$reqs) {

        my $class = $req->[0];
        my $term = $req->[1];
        next unless $class and $term;
        $logger->info("Sending authority request for $class : $term");
        my $fr = $session->request("open-ils.storage.authority.$class.see_from.controlled.atomic",$term, 10)->gather(1);
        my $al = $session->request("open-ils.storage.authority.$class.see_also_from.controlled.atomic",$term, 10)->gather(1);

        $response->{$class} = {} unless exists $response->{$class};
        $response->{$class}->{$term} = _auth_flatten( $term, $fr, $al, 1 );

    }

    #warn Dumper( $response );
    return $response;
}

sub crossref_authority_batch {
    my( $self, $client, $reqs ) = @_;

    my $response = {};
    my $lastr = [];
    my $session = OpenSRF::AppSession->create("open-ils.storage");

    for my $req (@$reqs) {

        my $class = $req->[0];
        my $term = $req->[1];
        next unless $class and $term;
        $logger->info("Sending authority request for $class : $term");
        my $freq = $session->request("open-ils.storage.authority.$class.see_from.controlled.atomic",$term, 10);
        my $areq = $session->request("open-ils.storage.authority.$class.see_also_from.controlled.atomic",$term, 10);

        if( $lastr->[0] ) { #process old data while waiting on new data
            my $cls = $lastr->[0];
            my $trm = $lastr->[1];
            my $fr  = $lastr->[2];
            my $al  = $lastr->[3];
            $response->{$cls} = {} unless exists $response->{$cls};
            $response->{$cls}->{$trm} = _auth_flatten( $trm, $fr, $al, 1 );
        }

        $lastr->[0] = $class;
        $lastr->[1] = $term; 
        $lastr->[2] = $freq->gather(1);
        $lastr->[3] = $areq->gather(1);
    }

    if( $lastr->[0] ) { #process old data while waiting on new data
        my $cls = $lastr->[0];
        my $trm = $lastr->[1];
        my $fr  = $lastr->[2];
        my $al  = $lastr->[3];
        $response->{$cls} = {} unless exists $response->{$cls};
        $response->{$cls}->{$trm} = _auth_flatten( $trm, $fr, $al, 1);
    }

    return $response;
}




sub crossref_authority_batch2 {
    my( $self, $client, $reqs ) = @_;

    my $response = {};
    my $lastr = [];
    my $session = OpenSRF::AppSession->create("open-ils.storage");

    $cache = OpenSRF::Utils::Cache->new('global') unless $cache;

    for my $req (@$reqs) {

        my $class = $req->[0];
        my $term = $req->[1];
        next unless $class and $term;

        my $t = $term;
        $t =~ s/\s//og;
        my $cdata = $cache->get_cache("oils_authority_${class}_$t");

        if( $cdata ) {
            $logger->debug("returning authority response from cache..");
            $response->{$class} = {} unless exists $response->{$class};
            $response->{$class}->{$term} = $cdata;
            next;
        }

        $logger->debug("authority data not found in cache.. fetching from storage");

        $logger->info("Sending authority request for $class : $term");
        my $freq = $session->request("open-ils.storage.authority.$class.see_from.controlled.atomic",$term, 10);
        my $areq = $session->request("open-ils.storage.authority.$class.see_also_from.controlled.atomic",$term, 10);
        my $fr = $freq->gather(1);  
        my $al = $areq->gather(1);
        $response->{$class} = {} unless exists $response->{$class};
        my $auth = _auth_flatten( $term, $fr, $al, 1 );

        my $timeout = 7200; #two hours
        $timeout = 300 if @{$auth->{from}} or @{$auth->{also}}; # 5 minutes
        $response->{$class}->{$term} = $auth;
        $logger->debug("adding authority lookup to cache with timeout $timeout");
        $cache->put_cache("oils_authority_${class}_$t", $auth, $timeout);
    }
    return $response;
}

__PACKAGE__->register_method(
    method        => "authority_main_entry",
    api_name      => "open-ils.search.authority.main_entry",
    stream => 1,
    signature     => {
        desc => q/
            Returns the main entry details for one or more authority 
            records plus a few other details.
        /,
        params => [
            {desc => 'Authority IDs', type => 'number or array'}
        ],
        return => {
            desc => q/
                Stream of authority metadata objects.
                {   authority: are_object,
                    heading: heading_text,
                    thesaurus: short_code,
                    thesaurus_code: code,
                    control_set: control_set_object,
                    linked_bib_count: number
                }
            /,
            type => 'object'
        }
    }
);

sub authority_main_entry {
    my ($self, $client, $auth_ids) = @_;

    $auth_ids = [$auth_ids] unless ref $auth_ids;

    my $e = new_editor();

    for my $auth_id (@$auth_ids) {

        my $rec = $e->retrieve_authority_record_entry([
            $auth_id, {
                flesh => 1,
                flesh_fields => {are => [qw/control_set creator/]}
            }
        ]) or return $e->event;

        my $response = {
            authority => $rec,
            control_set => $rec->control_set
        };

        $response->{linked_bib_count} = $e->json_query({
            select => {abl => [
                {column => 'bib', transform => 'count', aggregate => 1}
            ]},
            from => 'abl',
            where => {authority => $auth_id}
        })->[0]->{bib};

        # Extract the heading and thesaurus.
        # In theory this data has already been extracted in the DB, but
        # using authority.simple_heading results in data that varies
        # quite a bit from the previous authority manage interface.  I
        # took the MARC parsing approach because it matches the logic
        # (and results) of the previous UI.

        my $marc = MARC::Record->new_from_xml($rec->marc);
        my $heading_field = $marc->field('1..');
        $response->{heading} = $heading_field->as_string if $heading_field;

        my $field_008 = $marc->field('008');
        if ($field_008) {

            my $extract_thesaurus_query = {
                from => [ 'authority.extract_thesaurus' => $rec->marc ]
            };
            my $thes = $e->json_query($extract_thesaurus_query)->[0]->{'authority.extract_thesaurus'};

            if (defined $thes) {
                $response->{thesaurus_code} = $thes;
                my $thesaurus = $e->search_authority_thesaurus(
                    {code => $thes})->[0];

                $response->{thesaurus} = $thesaurus->short_code if $thesaurus;
            }
        }

        $rec->clear_marc;
        $client->respond($response);
    }

    return undef;
}



1;
