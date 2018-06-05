package OpenILS::Application::Search::Z3950;
use strict; use warnings;
use base qw/OpenILS::Application/;

use OpenILS::Utils::ZClient;
use MARC::Record;
use MARC::File::XML (BinaryEncoding => 'UTF-8');
use MARC::Charset;
use Unicode::Normalize;
use XML::LibXML;

use OpenILS::Event;
use OpenSRF::EX qw(:try);
use OpenSRF::MultiSession;
use OpenILS::Utils::ModsParser;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::JSON;
use OpenILS::Application::AppUtils;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Utils::Normalize qw/clean_marc/;                                  

MARC::Charset->assume_unicode(1);
MARC::Charset->ignore_errors(1);

my $output = "usmarc"; 
my $U = 'OpenILS::Application::AppUtils'; 

my $sclient;

__PACKAGE__->register_method(
    method    => 'apply_credentials',
    api_name  => 'open-ils.search.z3950.apply_credentials',
    signature => {
        desc   => "Apply credentials for a Z39.50 server",
        params => [
            {desc => 'Authtoken', type => 'string'},
            {desc => 'Z39.50 Source (server) name', type => 'string'},
            {desc => 'Context org unit', type => 'number'},
            {desc => 'Username', type => 'string'},
            {desc => 'Password', type => 'string'}
        ],
        return => {
            desc => 'Event; SUCCESS on success, other event type on error'
        }
    }
);

sub apply_credentials {
    my ($self, $client, $auth, $source, $ctx_ou, $username, $password) = @_;

    my $e = new_editor(authtoken => $auth, xact => 1);

    return $e->die_event unless 
        $e->checkauth and 
        $e->allowed('ADMIN_Z3950_SOURCE', $ctx_ou);

    $e->json_query({from => [
        'config.z3950_source_credentials_apply',
        $source, $ctx_ou, $username, $password
    ]}) or return $e->die_event;

    $e->commit;

    return OpenILS::Event->new('SUCCESS');
}
 


__PACKAGE__->register_method(
    method    => 'do_class_search',
    api_name  => 'open-ils.search.z3950.search_class',
    stream    => 1,
    signature => q/
        Performs a class based Z search.  The classes available
        are defined by the 'attr' fields in the config for the
        requested service.
        @param auth The login session key
        @param shash The search hash : { attr : value, attr2: value, ...}
        @param service The service to connect to
        @param username The username to use when connecting to the service
        @param password The password to use when connecting to the service
    /
);

__PACKAGE__->register_method(
    method    => 'do_service_search',
    api_name  => 'open-ils.search.z3950.search_service',
    signature => q/
        @param auth The login session key
        @param query The Z3950 search string to use
        @param service The service to connect to
        @param username The username to use when connecting to the service
        @param password The password to use when connecting to the service
    /
);


__PACKAGE__->register_method(
    method    => 'do_service_search',
    api_name  => 'open-ils.search.z3950.search_raw',
    signature => q/
        @param auth The login session key
        @param args An object of search params which must include:
            host, port, db and query.  
            optional fields include username and password
    /
);


__PACKAGE__->register_method(
    method    => "query_services",
    api_name  => "open-ils.search.z3950.retrieve_services",
    signature => q/
        @param auth The login session key
        Returns a list of service names that we have config
        data for
    /
);



# -------------------------------------------------------------------
# What services do we have config info for?
# -------------------------------------------------------------------
sub query_services {
    my( $self, $client, $auth ) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('REMOTE_Z3950_QUERY');

    return fetch_service_defs($e);
}

# -------------------------------------------------------------------
# What services do we have config info for?
# -------------------------------------------------------------------
sub fetch_service_defs {

    my $editor_with_authtoken = shift;

    # TODO Evergreen stopped shipping Z39.50 target definitions
    #      in opensrf.xml all the way back in 2012 (see LP#950067).
    #      Enough time may have passed to just remove the settings
    #      lookup.
    my $hash = $sclient->config_value('z3950', 'services');

    # overlay config file values with in-db values
    my $e = $editor_with_authtoken || new_editor();
    if($e->can('search_config_z3950_source')) {

        my $sources = $e->search_config_z3950_source(
            [ { name => { '!=' => undef } },
              { flesh => 1, flesh_fields => { czs => ['attrs'] } } ]
        );

        for my $s ( @$sources ) {
            $$hash{ $s->name } = {
                name => $s->name,
                label => $s->label,
                host => $s->host,
                port => $s->port,
                db => $s->db,
                record_format => $s->record_format,
                transmission_format => $s->transmission_format,
                auth => $s->auth,
                use_perm => ($s->use_perm) ? 
                    $e->retrieve_permission_perm_list($s->use_perm)->code : ''
            };

            for my $a ( @{ $s->attrs } ) {
                $$hash{ $a->source }{attrs}{ $a->name } = {
                    name => $a->name,
                    label => $a->label,
                    code => $a->code,
                    format => $a->format,
                    source => $a->source,
                    truncation => $a->truncation,
                };
            }
        }
    }

    # Define the set of native catalog services
    # XXX There are i18n problems here, but let's get the staff client working first
    # XXX Move into the DB?
    $hash->{'native-evergreen-catalog'} = {
        attrs => {
            title => {code => 'title', label => 'Title'},
            author => {code => 'author', label => 'Author'},
            subject => {code => 'subject', label => 'Subject'},
            keyword => {code => 'keyword', label => 'Keyword'},
            tcn => {code => 'tcn', label => 'TCN'},
            isbn => {code => 'isbn', label => 'ISBN'},
            issn => {code => 'issn', label => 'ISSN'},
            publisher => {code => 'publisher', label => 'Publisher'},
            pubdate => {code => 'pubdate', label => 'Pub Date'},
            item_type => {code => 'item_type', label => 'Item Type'},
            upc => {code => 'upc', label => 'UPC'},
        }
    };

    # then filter out any services which the requestor lacks the perm for
    if ($editor_with_authtoken) {
        foreach my $s (keys %{ $hash }) {
            if ($$hash{$s}{use_perm}) {
                if ($U->check_perms(
                    $e->requestor->id,
                    $e->requestor->ws_ou,
                    $$hash{$s}{use_perm}
                )) {
                    delete $$hash{$s};
                }
            };
        }
    }

    return $hash;
}



# -------------------------------------------------------------------
# Load the pre-defined Z server configs
# -------------------------------------------------------------------
sub child_init {
    $sclient = OpenSRF::Utils::SettingsClient->new();
}


# -------------------------------------------------------------------
# High-level class based search. 
# -------------------------------------------------------------------
sub do_class_search {

    my $self = shift;
    my $conn = shift;
    my $auth = shift;
    my $args = shift;

    if (!ref($$args{service})) {
        $$args{service} = [$$args{service}];
        $$args{username} = [$$args{username}];
        $$args{password} = [$$args{password}];
    }

    $$args{async} = 1;

    my @connections;
    my @results;
    my @services; 
    for (my $i = 0; $i < @{$$args{service}}; $i++) {
        my %tmp_args = %$args;
        $tmp_args{service} = $$args{service}[$i];
        $tmp_args{username} = $$args{username}[$i];
        $tmp_args{password} = $$args{password}[$i];

        $logger->debug("z3950: service: $tmp_args{service}, async: $tmp_args{async}");

        if ($tmp_args{service} eq 'native-evergreen-catalog') { 
            my $method = $self->method_lookup('open-ils.search.biblio.zstyle.staff'); 
            $conn->respond( 
                $self->method_lookup('open-ils.search.biblio.zstyle.staff')->run($auth, \%tmp_args) 
            ); 

        } else { 

            $tmp_args{query} = compile_query('and', $tmp_args{service}, $tmp_args{search}); 
    
            my $res = do_service_search( $self, $conn, $auth, \%tmp_args ); 
    
            if ($U->event_code($res)) { 
                $conn->respond($res) if $U->event_code($res); 

            } else { 
                push @services, $tmp_args{service}; 
                push @results, $res->{result}; 
                push @connections, $res->{connection}; 

                $logger->debug("z3950: Result object: $results[-1], Connection object: $connections[-1]");
            }
        }

    }

    $logger->debug("z3950: Connections created");

    return undef unless (@connections);
    my @records;

    # local catalog search is not processed with other z39 results;
    $$args{service} = [grep {$_ ne 'native-evergreen-catalog'} @{$$args{service}}];

    @connections = grep {defined $_} @connections;
    return undef unless @connections;

    while ((my $index = OpenILS::Utils::ZClient::event( \@connections )) != 0) {
        my $ev = $connections[$index - 1]->last_event();
        $logger->debug("z3950: Received event $ev");
        if ($ev == OpenILS::Utils::ZClient::EVENT_END()) {
            my $munged = process_results( $results[$index - 1], $$args{limit}, $$args{offset}, $$args{service}[$index -1] );
            $$munged{service} = $$args{service}[$index - 1];
            $conn->respond($munged);
        }
    }

    $logger->debug("z3950: Search Complete");
    return undef;
}


# -------------------------------------------------------------------
# This handles the host settings, but expects a fully formed z query
# -------------------------------------------------------------------
sub do_service_search {

    my $self = shift;
    my $conn = shift;
    my $auth = shift;
    my $args = shift;

    my $services = fetch_service_defs();
    my $info = $services->{$$args{service}};

    $$args{host} = $$info{host};
    $$args{port} = $$info{port};
    $$args{db} = $$info{db};
    $logger->debug("z3950: do_search...");

    return do_search( $self, $conn, $auth, $args );
}



# -------------------------------------------------------------------
# This is the low level search method.  All config and query
# data must be provided to this method
# -------------------------------------------------------------------
sub do_search {

    my $self = shift;
    my $conn = shift;
    my $auth = shift;
    my $args = shift;

    my $host = $$args{host} or return undef;
    my $port = $$args{port} or return undef;
    my $db = $$args{db} or return undef;
    my $query = $$args{query} or return undef;
    my $async = $$args{async} || 0;

    my $limit = $$args{limit} || 10;
    my $offset = $$args{offset} || 0;

    my $editor = new_editor(authtoken => $auth);
    return $editor->event unless 
        $editor->checkauth and
        $editor->allowed('REMOTE_Z3950_QUERY', $editor->requestor->ws_ou);

    my $creds = $editor->json_query({from => [
        'config.z3950_source_credentials_lookup',
        $$args{service}, $editor->requestor->ws_ou
    ]})->[0] || {};

    # use the caller-provided username/password if offered.
    # otherwise, use the stored credentials.
    my $username = $$args{username} || $creds->{username} || "";
    my $password = $$args{password} || $creds->{password} || "";

    my $services = fetch_service_defs();
    my $tformat = $services->{$args->{service}}->{transmission_format} || $output;

    $logger->info("z3950: connecting to server $host:$port:$db as $username");

    my $connection = OpenILS::Utils::ZClient->new(
        $host, $port,
        databaseName => $db, 
        user => $username,
        password => $password,
        async => $async,
        preferredRecordSyntax => $tformat, 
    );

    if( ! $connection ) {
        $logger->error("z3950: Unable to connect to Z server: ".
            "$host:$port:$db:$username:$password");
        return OpenILS::Event->new('Z3950_LOGIN_FAILED') unless $connection;
    }

    my $start = time;
    my $results;
    my $err;

    $logger->info("z3950: query => $query");

    try {
        $results = $connection->search_pqf( $query );
    } catch Error with { $err = shift; };

    return OpenILS::Event->new(
        'Z3950_BAD_QUERY', payload => $query, debug => "$err") if $err;

    return OpenILS::Event->new('Z3950_SEARCH_FAILED', 
        debug => $connection->errcode." => ".$connection->errmsg." : query = $query") unless $results;

    $logger->info("z3950: search [$query] took ".(time - $start)." seconds");

    return {result => $results, connection => $connection} if ($async);

    my $munged = process_results($results, $limit, $offset, $$args{service});
    $munged->{query} = $query;

    return $munged;
}


# -------------------------------------------------------------------
# Takes a result batch and returns the hitcount and a list of xml
# and mvr objects
# -------------------------------------------------------------------
sub process_results {

    my $results = shift;
    my $limit = shift || 10;
    my $offset = shift || 0;
    my $service = shift;

    my $services = fetch_service_defs();
    my $rformat = $services->{$service}->{record_format};
    my $tformat = $services->{$service}->{transmission_format} || $output;

    $results->option(elementSetName => $rformat);
    $results->option(preferredRecordSyntax => $tformat);
    $logger->info("z3950: using record format '$rformat' and transmission format '$tformat'");

    my @records;
    my $res = {};
    my $count = $$res{count} = $results->size;

    $logger->info("z3950: '$service' search returned $count hits");

    my $tend = $limit + $offset;

    my $end = ($tend <= $count) ? $tend : $count;

    for($offset..$end - 1) {

        my $err;
        my $mods;
        my $marc;
        my $marcs;
        my $marcxml;

        $logger->info("z3950: fetching record $_");

        try {

            my $rec = $results->record($_);

            if ($tformat eq 'usmarc') {
                my $raw = $rec->raw();
                if (length($raw) <= 99999) {
                    $marc = MARC::Record->new_from_usmarc($raw);
                } else {
                    $marcs = '';
                    die "ISO2709 record is too large to process";
                }
            } elsif ($tformat eq 'xml') {
                $marc = MARC::Record->new_from_xml($rec->raw());
            } else {
                die "Unsupported record transmission format $tformat"
            }

            $marcs = $U->entityize($marc->as_xml_record);
            $marcs = $U->strip_ctrl_chars($marcs);
            my $doc = XML::LibXML->new->parse_string($marcs);
            $marcxml = $U->entityize($doc->documentElement->toString);
            $marcxml = $U->strip_ctrl_chars($marcxml);
    
            my $u = OpenILS::Utils::ModsParser->new();
            $u->start_mods_batch( $marcxml );
            $mods = $u->finish_mods_batch();
    

        } catch Error with { $err = shift; };

        push @records, { 'mvr' => $mods, 'marcxml' => $marcxml } unless $err;
        $logger->error("z3950: bad XML : $err") if $err;

        if( $err ) {
            warn "\n\n$marcs\n\n";
        }
    }
    
    $res->{records} = \@records;
    return $res;
}



# -------------------------------------------------------------------
# Compiles the class based search query
# -------------------------------------------------------------------
sub compile_query {

    my $separator = shift;
    my $service = shift;
    my $hash = shift;

    my $count = scalar(keys %$hash);

    my $str = "";
    $str .= "\@$separator " for (1..$count-1);
    
    # -------------------------------------------------------------------
    # "code" is the bib-1 "use attribute", "format" is the bib-1 
    # "structure attribute"
    # -------------------------------------------------------------------
    my $services = fetch_service_defs();
    for( keys %$hash ) {
        next unless ( exists $services->{$service}->{attrs}->{$_} );
        $str .= '@attr 1=' . $services->{$service}->{attrs}->{$_}->{code} . # add the use attribute
            ' @attr 4=' . $services->{$service}->{attrs}->{$_}->{format}; # add the structure attribute
        if (exists $services->{$service}->{attrs}->{$_}->{truncation}
                && $services->{$service}->{attrs}->{$_}->{truncation} >= 0) {
            $str .= ' @attr 5=' . $services->{$service}->{attrs}->{$_}->{truncation};
        }
        $str .= " \"" . $$hash{$_} . "\" "; # add the search term
    }
    return $str;
}


__PACKAGE__->register_method(
    method    => 'bucket_search_queue',
    api_name  => 'open-ils.search.z3950.bucket_search_queue',
    stream    => 1,
    # disable opensrf chunking so the caller can receive timely responses
    max_bundle_count => 1,
    signature => {
        desc => q/
            Performs a Z39.50 search for every record in a bucket, using the
            provided Z39.50 fields.  Add all search results to the specified
            Vandelay queue.  If no source records or search results are found,
            no queue is created.
        /,
        params => [
            {desc => q/Authentication token/, type => 'string'},
            {desc => q/Bucket ID/, type => 'number'},
            {desc => q/Z39 Sources.  List of czs.name/, type => 'array'},
            {desc => q/Z39 Index Maps.  List of czifm.id/, type => 'array'},
            {   desc => q/Vandelay arguments
                    queue_name -- required
                    match_set
                    ...
                    /, 
                type => 'object'
            }
        ],
        return => {
            desc => q/Object containing status information about the on-going search
            and queue operation. 
            {
                bre_count    : $num, -- number of bibs to search against
                search_count : $num,
                search_complete  : $num,
                queue_count  : $num
                queue        : $queue_obj
            }
            This object will be streamed back with each milestone (search
            result or complete).
            Event object returned on failure
            /
        }
    }
);

sub bucket_search_queue {
    my $self = shift;
    my $conn = shift;
    my $auth = shift;
    my $bucket_id = shift;
    my $z_sources = shift;
    my $z_indexes = shift;
    my $vandelay = shift;

    my $e = new_editor(authtoken => $auth);
    return $e->event unless 
        $e->checkauth and
        $e->allowed('REMOTE_Z3950_QUERY') and
        $e->allowed('CREATE_BIB_IMPORT_QUEUE');
    
    # find the source bib records

    my $bre_ids = $e->json_query({
        select => {cbrebi => ['target_biblio_record_entry']},
        from => 'cbrebi',
        where => {bucket => $bucket_id},
        distinct => 1
    });

    # empty bucket
    return {bre_count => 0} unless @$bre_ids;

    $bre_ids = [ map {$_->{target_biblio_record_entry}} @$bre_ids ];

    $z_indexes = $e->search_config_z3950_index_field_map({id => $z_indexes});

    return OpenILS::Event->new('BAD_PARAMS', 
        note => q/No z_indexes/) unless @$z_indexes;

    # build the Z39 queries for the source bib records

    my $z_searches = compile_bucket_zsearch(
        $e, $bre_ids, $z_sources, $z_indexes);

    return $e->event unless $z_searches;
    return {bre_count => 0} unless @$z_searches;

    my $queue = create_z39_bucket_queue($e, $bucket_id, $vandelay);
    return $e->event unless $queue;

    send_and_queue_bucket_searches($conn, $e, $queue, $z_searches);

    return undef;
}

 # create the queue for storing search results
sub create_z39_bucket_queue {
    my ($e, $bucket_id, $vandelay) = @_;

    my $existing = $e->search_vandelay_bib_queue({
        name => $vandelay->{queue_name},
        owner => $e->requestor->id
    })->[0];

    return $existing if $existing;

    my $queue = Fieldmapper::vandelay::bib_queue->new;
    $queue->match_bucket($bucket_id);
    $queue->owner($e->requestor->id);
    $queue->name($vandelay->{queue_name});
    $queue->match_set($vandelay->{match_set});

    $e->xact_begin;
    unless ($e->create_vandelay_bib_queue($queue)) {
        $e->rollback;
        return undef;
    }
    $e->commit;

    return $queue;
}

# sets the 901c value to the Z39 service and 
# adds the record to the growing vandelay queue
# returns the number of successfully queued records
sub stamp_and_queue_results {
    my ($e, $queue, $service, $bre_id, $result) = @_;
    my $qcount = 0;

    for my $rec (@{$result->{records}}) {
        # insert z39 service as the 901z
        my $marc = MARC::Record->new_from_xml(
            $rec->{marcxml}, 'UTF-8', 'USMARC');

        $marc->insert_fields_ordered(
            MARC::Field->new('901', '', '', z => $service));

        # put the record into the queue
        my $qrec = Fieldmapper::vandelay::queued_bib_record->new;
        $qrec->marc(clean_marc($marc));
        $qrec->queue($queue->id);

        $e->xact_begin;
        if ($e->create_vandelay_queued_bib_record($qrec)) {
            $e->commit;
            $qcount++;
        } else {
            my $evt = $e->die_event;
            $logger->error("z39: unable to queue record: $evt");
        }
    }

    return $qcount;
}

sub send_and_queue_bucket_searches {
    my ($conn, $e, $queue, $z_searches) = @_;

    my $max_parallel = $U->ou_ancestor_setting(
        $e->requestor->ws_ou,
        'cat.z3950.batch.max_parallel') || 5;

    my $search_limit = $U->ou_ancestor_setting(
        $e->requestor->ws_ou,
        'cat.z3950.batch.max_results') || 5;

    my $response = {
        bre_count => 0,
        search_count => 0,
        search_complete => 0,
        queue_count => 0
    };

    # searches are about to be in flight
    # let the caller know we're still alive
    $conn->respond($response);

    my $handle_search_result = sub {
        my ($self, $req) = @_;
        my $bre_id = $req->{req}->{_bre_id};

        my @p = $req->{req}->payload->params;
        $logger->debug("z39: multi-search response for request [$bre_id]". 
            OpenSRF::Utils::JSON->perl2JSON(\@p));

        for my $resp (@{$req->{response}}) {
            $response->{search_complete}++;
            my $result = $resp->content or next;
            my $service = $result->{service};
            $response->{queue_count} += 
                stamp_and_queue_results($e, $queue, $service, $bre_id, $result);
        }

        $conn->respond($response);
    };

    my $multi_ses = OpenSRF::MultiSession->new(
        app             => 'open-ils.search',
        cap             => $max_parallel,
        timeout         => 120,
        success_handler => $handle_search_result
    );

    # note: mult-session blocks new requests when it hits max 
    # parallel, so we need to cacluate summary values up front.
    my %bre_uniq;
    $bre_uniq{$_->{bre_id}} = 1 for @$z_searches;
    $response->{bre_count} = int(scalar(keys %bre_uniq));
    $response->{search_count} += scalar(@$z_searches);

    # let the caller know searches are on their way out
    $conn->respond($response);

    for my $search (@$z_searches) {

        my $bre_id = delete $search->{bre_id};
        $search->{limit} = $search_limit;

        # toss it onto the multi-pile
        my $req = $multi_ses->request(
            'open-ils.search.z3950.search_class', $e->authtoken, $search);

        $req->{_bre_id} = $bre_id;
    }

    $multi_ses->session_wait(1);
    $response->{queue} = $queue;
    $conn->respond($response);
}


# creates a series of Z39.50 searchs based on the 
# in-bucket records and the selected sources and indexes
sub compile_bucket_zsearch {
    my ($e, $bre_ids, $z_sources, $z_indexes) = @_;

    # pre-load the metabib_field's we'll need for this batch

    my %mb_fields;
    my @mb_fields = grep { $_->metabib_field } @$z_indexes;
    if (@mb_fields) {
        @mb_fields = map { $_->metabib_field } @mb_fields;
        my $field_objs = $e->search_config_metabib_field({id => \@mb_fields});
        %mb_fields = map {$_->id => $_} @$field_objs;
    }

    # pre-load the z3950_attrs we'll need for this batch

    my %z3950_attrs;
    my @z3950_attrs = grep { $_->z3950_attr } @$z_indexes;
    if (@z3950_attrs) {
        @z3950_attrs = map { $_->z3950_attr } @z3950_attrs;
        my $attr_objs = $e->search_config_z3950_attr({id => \@z3950_attrs});
        %z3950_attrs = map {$_->id => $_} @$attr_objs;
    }

    # indexes with specific z3950_attr's take precedence
    my @z_index_attrs = grep { $_->z3950_attr } @$z_indexes;
    my @z_index_types = grep { !$_->z3950_attr } @$z_indexes;

    # for each bib record, extract the indexed value for the selected indexes.  
    my %z_searches;

    for my $bre_id (@$bre_ids) {

        $z_searches{$bre_id} = {};

        for my $z_index (@z_index_attrs, @z_index_types) {

            my $bre_val;
            if ($z_index->record_attr) {

                my $attrs = $U->get_bre_attrs($bre_id, $e);
                $bre_val = $attrs->{$bre_id}{$z_index->record_attr}{code};

            } else { # metabib_field
                my $fid = $z_index->metabib_field;

                # the value for each field will be in the 
                # index class-specific table
                my $entry_query = sprintf(
                    'search_metabib_%s_field_entry', 
                    $mb_fields{$fid}->field_class);

                my $entry = $e->$entry_query(
                    {field => $fid, source => $bre_id})->[0];

                $bre_val = $entry->value if $entry;
            }

            # no value means no search
            next unless $bre_val;

            # determine which z3950 source to send this search field to 

            my $z_source = [];
            my $z_index_name;
            if ($z_index->z3950_attr) {

                # a specific z3950_attr means this search index
                # only applies to the z_source linked to the attr

                $z_index_name = $z3950_attrs{$z_index->z3950_attr}->name;
                my $src = $z3950_attrs{$z_index->z3950_attr}->source;

                if (grep { $_ eq $src } @$z_sources) {
                    $z_searches{$bre_id}{$src} ||= {
                        service => [$src],
                        search => {}
                    };
                    $z_searches{$bre_id}{$src}{search}{$z_index_name} = $bre_val;

                } else {
                    $logger->warn("z39: z3950_attr '$z_index_name' for '$src'".
                        " selected, but $src is not in the search list.  Skipping...");
                }

            } else {

                # when a generic attr type is used, it applies to all 
                # z-sources, except those for which a more specific
                # z3950_attr has already been applied

                $z_index_name = $z_index->z3950_attr_type;

                my @excluded;
                for my $attr (values %z3950_attrs) {
                    push(@excluded, $attr->source)
                        if $attr->name eq $z_index_name;
                }

                for my $src (@$z_sources) {
                    next if grep {$_ eq $src} @excluded;
                    $z_searches{$bre_id}{$src} ||= {
                        service => [$src],
                        search => {}
                    };
                    $z_searches{$bre_id}{$src}{search}{$z_index_name} = $bre_val;
                }
            }
        }
    }

    # NOTE: ISBNs are sent through the translate_isbn1013 normalize
    # before entring metabib.identifier_field_entry.  As such, there
    # will always be at minimum 2 ISBNs per record w/ ISBN and the
    # data will be pre-sanitized.  The first ISBN in the list is the
    # ISBN from the record.  Use that for these searches.
    for my $bre_id (keys %z_searches) {
        for my $src (keys %{$z_searches{$bre_id}}) {
            my $blob = $z_searches{$bre_id}{$src};

            # Sanitized ISBNs are space-separated.
            # kill everything past the first space
            $blob->{search}{isbn} =~ s/\s.*//g if $blob->{search}{isbn};
        }
    }

    # let's turn this into something slightly more digestable
    my @searches;
    for my $bre_id (keys %z_searches) {
        for my $blobset (values %{$z_searches{$bre_id}}) {
            $blobset = [$blobset] unless ref $blobset eq 'ARRAY';
            for my $blob (@$blobset) {
                $blob->{bre_id} = $bre_id;
                push(@searches, $blob);
            }
        }
    }

    return \@searches;
}



1;
# vim:et:ts=4:sw=4:
