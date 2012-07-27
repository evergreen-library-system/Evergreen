package OpenILS::Application::Vandelay;
use strict; use warnings;
use OpenILS::Application;
use base qw/OpenILS::Application/;
use Unicode::Normalize;
use OpenSRF::EX qw/:try/;
use OpenSRF::AppSession;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Cache;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Normalize qw/clean_marc/;
use MARC::Batch;
use MARC::Record;
use MARC::File::XML ( BinaryEncoding => 'UTF-8' );
use Time::HiRes qw(time);
use OpenSRF::Utils::Logger qw/$logger/;
use MIME::Base64;
use OpenILS::Const qw/:const/;
use OpenILS::Application::AppUtils;
use OpenILS::Application::Cat::BibCommon;
use OpenILS::Application::Cat::AuthCommon;
use OpenILS::Application::Cat::AssetCommon;
my $U = 'OpenILS::Application::AppUtils';

# A list of LDR/06 values from http://loc.gov/marc
my %record_types = (
        a => 'bib',
        c => 'bib',
        d => 'bib',
        e => 'bib',
        f => 'bib',
        g => 'bib',
        i => 'bib',
        j => 'bib',
        k => 'bib',
        m => 'bib',
        o => 'bib',
        p => 'bib',
        r => 'bib',
        t => 'bib',
        u => 'holdings',
        v => 'holdings',
        x => 'holdings',
        y => 'holdings',
        z => 'auth',
      ' ' => 'bib',
);

sub initialize {}
sub child_init {}

# --------------------------------------------------------------------------------
# Biblio ingest

sub create_bib_queue {
    my $self = shift;
    my $client = shift;
    my $auth = shift;
    my $name = shift;
    my $owner = shift;
    my $type = shift;
    my $match_set = shift;
    my $import_def = shift;

    my $e = new_editor(authtoken => $auth, xact => 1);

    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('CREATE_BIB_IMPORT_QUEUE');
    $owner ||= $e->requestor->id;

    if ($e->search_vandelay_bib_queue( {name => $name, owner => $owner, queue_type => $type})->[0]) {
        $e->rollback;
        return OpenILS::Event->new('BIB_QUEUE_EXISTS') 
    }

    my $queue = new Fieldmapper::vandelay::bib_queue();
    $queue->name( $name );
    $queue->owner( $owner );
    $queue->queue_type( $type ) if ($type);
    $queue->item_attr_def( $import_def ) if ($import_def);
    $queue->match_set($match_set) if $match_set;

    my $new_q = $e->create_vandelay_bib_queue( $queue );
    return $e->die_event unless ($new_q);
    $e->commit;

    return $new_q;
}
__PACKAGE__->register_method(  
    api_name   => "open-ils.vandelay.bib_queue.create",
    method     => "create_bib_queue",
    api_level  => 1,
    argc       => 4,
);                      


sub create_auth_queue {
    my $self = shift;
    my $client = shift;
    my $auth = shift;
    my $name = shift;
    my $owner = shift;
    my $type = shift;
    my $match_set = shift;

    my $e = new_editor(authtoken => $auth, xact => 1);

    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('CREATE_AUTHORITY_IMPORT_QUEUE');
    $owner ||= $e->requestor->id;

    if ($e->search_vandelay_authority_queue({name => $name, owner => $owner, queue_type => $type})->[0]) {
        $e->rollback;
        return OpenILS::Event->new('AUTH_QUEUE_EXISTS') 
    }

    my $queue = new Fieldmapper::vandelay::authority_queue();
    $queue->name( $name );
    $queue->owner( $owner );
    $queue->queue_type( $type ) if ($type);

    my $new_q = $e->create_vandelay_authority_queue( $queue );
    $e->die_event unless ($new_q);
    $e->commit;

    return $new_q;
}
__PACKAGE__->register_method(  
    api_name   => "open-ils.vandelay.authority_queue.create",
    method     => "create_auth_queue",
    api_level  => 1,
    argc       => 3,
);                      

sub add_record_to_bib_queue {
    my $self = shift;
    my $client = shift;
    my $auth = shift;
    my $queue = shift;
    my $marc = shift;
    my $purpose = shift;
    my $bib_source = shift;

    my $e = new_editor(authtoken => $auth, xact => 1);

    $queue = $e->retrieve_vandelay_bib_queue($queue);

    return $e->die_event unless $e->checkauth;
    return $e->die_event unless
        ($e->allowed('CREATE_BIB_IMPORT_QUEUE', undef, $queue) ||
         $e->allowed('CREATE_BIB_IMPORT_QUEUE'));

    my $new_rec = _add_bib_rec($e, $marc, $queue->id, $purpose, $bib_source);

    return $e->die_event unless ($new_rec);
    $e->commit;
    return $new_rec;
}
__PACKAGE__->register_method(  
    api_name   => "open-ils.vandelay.queued_bib_record.create",
    method     => "add_record_to_bib_queue",
    api_level  => 1,
    argc       => 3,
);                      

sub _add_bib_rec {
    my $e = shift;
    my $marc = shift;
    my $queue = shift;
    my $purpose = shift;
    my $bib_source = shift;

    my $rec = new Fieldmapper::vandelay::queued_bib_record();
    $rec->marc( $marc );
    $rec->queue( $queue );
    $rec->purpose( $purpose ) if ($purpose);
    $rec->bib_source($bib_source);

    return $e->create_vandelay_queued_bib_record( $rec );
}

sub add_record_to_authority_queue {
    my $self = shift;
    my $client = shift;
    my $auth = shift;
    my $queue = shift;
    my $marc = shift;
    my $purpose = shift;

    my $e = new_editor(authtoken => $auth, xact => 1);

    $queue = $e->retrieve_vandelay_authority_queue($queue);

    return $e->die_event unless $e->checkauth;
    return $e->die_event unless
        ($e->allowed('CREATE_AUTHORITY_IMPORT_QUEUE', undef, $queue) ||
         $e->allowed('CREATE_AUTHORITY_IMPORT_QUEUE'));

    my $new_rec = _add_auth_rec($e, $marc, $queue->id, $purpose);

    return $e->die_event unless ($new_rec);
    $e->commit;
    return $new_rec;
}
__PACKAGE__->register_method(
    api_name   => "open-ils.vandelay.queued_authority_record.create",
    method     => "add_record_to_authority_queue",
    api_level  => 1,
    argc       => 3,
);

sub _add_auth_rec {
    my $e = shift;
    my $marc = shift;
    my $queue = shift;
    my $purpose = shift;

    my $rec = new Fieldmapper::vandelay::queued_authority_record();
    $rec->marc( $marc );
    $rec->queue( $queue );
    $rec->purpose( $purpose ) if ($purpose);

    return $e->create_vandelay_queued_authority_record( $rec );
}

sub process_spool {
    my $self = shift;
    my $client = shift;
    my $auth = shift;
    my $fingerprint = shift || '';
    my $queue_id = shift;
    my $purpose = shift;
    my $filename = shift;
    my $bib_source = shift;

    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;

    my $queue;
    my $type = $self->{record_type};

    if($type eq 'bib') {
        $queue = $e->retrieve_vandelay_bib_queue($queue_id) or return $e->die_event;
    } else {
        $queue = $e->retrieve_vandelay_authority_queue($queue_id) or return $e->die_event;
    }

    my $evt = check_queue_perms($e, $type, $queue);
    return $evt if ($evt);

    my $cache = new OpenSRF::Utils::Cache();

    if($fingerprint) {
        my $data = $cache->get_cache('vandelay_import_spool_' . $fingerprint);
        $purpose = $data->{purpose};
        $filename = $data->{path};
        $bib_source = $data->{bib_source};
    }

    unless(-r $filename) {
        $logger->error("unable to read MARC file $filename");
        return -1; # make this an event XXX
    }

    $logger->info("vandelay spooling $fingerprint purpose=$purpose file=$filename");

    my $marctype = 'USMARC'; 

    open F, $filename;
    $marctype = 'XML' if (getc(F) =~ /^\D/o);
    close F;

    my $batch = new MARC::Batch ($marctype, $filename);
    $batch->strict_off;

    my $response_scale = 10;
    my $count = 0;
    my $r = -1;
    while (try { $r = $batch->next } otherwise { $r = -1 }) {
        if ($r == -1) {
            $logger->warn("Processing of record $count in set $filename failed.  Skipping this record");
            $count++;
        }

        $logger->info("processing record $count");

        try {
            my $xml = clean_marc($r);

            my $qrec;
            # Check the leader to ensure we've got something resembling the expected
            # Allow spaces to give records the benefit of the doubt
            my $ldr_type = substr($r->leader(), 6, 1);
            if ($type eq 'bib' && ($record_types{$ldr_type}) eq 'bib' || $ldr_type eq ' ') {
                $qrec = _add_bib_rec( $e, $xml, $queue_id, $purpose, $bib_source ) or return $e->die_event;
            } elsif ($type eq 'auth' && ($record_types{$ldr_type}) eq 'auth' || $ldr_type eq ' ') {
                $qrec = _add_auth_rec( $e, $xml, $queue_id, $purpose ) or return $e->die_event;
            } else {
                # I don't know how to handle this type; rock on
                $logger->error("In process_spool(), type was $type and leader type was $ldr_type ; not currently supported");
                next;
            }

            if($self->api_name =~ /stream_results/ and $qrec) {
                $client->respond($qrec->id)
            } else {
                $client->respond($count) if (++$count % $response_scale) == 0;
                $response_scale *= 10 if ($count == ($response_scale * 10));
            }
        } catch Error with {
            my $error = shift;
            $logger->warn("Encountered a bad record at Vandelay ingest: ".$error);
        }
    }

    $e->commit;
    unlink($filename);
    $cache->delete_cache('vandelay_import_spool_' . $fingerprint) if $fingerprint;
    return $count;
}

__PACKAGE__->register_method(  
    api_name    => "open-ils.vandelay.bib.process_spool",
    method      => "process_spool",
    api_level   => 1,
    argc        => 3,
    max_chunk_size => 0,
    record_type => 'bib'
);                      
__PACKAGE__->register_method(  
    api_name    => "open-ils.vandelay.auth.process_spool",
    method      => "process_spool",
    api_level   => 1,
    argc        => 3,
    max_chunk_size => 0,
    record_type => 'auth'
);                      

__PACKAGE__->register_method(  
    api_name    => "open-ils.vandelay.bib.process_spool.stream_results",
    method      => "process_spool",
    api_level   => 1,
    argc        => 3,
    stream      => 1,
    max_chunk_size => 0,
    record_type => 'bib'
);                      
__PACKAGE__->register_method(  
    api_name    => "open-ils.vandelay.auth.process_spool.stream_results",
    method      => "process_spool",
    api_level   => 1,
    argc        => 3,
    stream      => 1,
    max_chunk_size => 0,
    record_type => 'auth'
);

__PACKAGE__->register_method(  
    api_name    => "open-ils.vandelay.bib_queue.records.retrieve",
    method      => 'retrieve_queued_records',
    api_level   => 1,
    argc        => 2,
    stream      => 1,
    record_type => 'bib'
);
__PACKAGE__->register_method(
    api_name    => "open-ils.vandelay.bib_queue.records.retrieve.export.print",
    method      => 'retrieve_queued_records',
    api_level   => 1,
    argc        => 2,
    stream      => 1,
    record_type => 'bib'
);
__PACKAGE__->register_method(
    api_name    => "open-ils.vandelay.bib_queue.records.retrieve.export.csv",
    method      => 'retrieve_queued_records',
    api_level   => 1,
    argc        => 2,
    stream      => 1,
    record_type => 'bib'
);
__PACKAGE__->register_method(
    api_name    => "open-ils.vandelay.bib_queue.records.retrieve.export.email",
    method      => 'retrieve_queued_records',
    api_level   => 1,
    argc        => 2,
    stream      => 1,
    record_type => 'bib'
);

__PACKAGE__->register_method(  
    api_name    => "open-ils.vandelay.auth_queue.records.retrieve",
    method      => 'retrieve_queued_records',
    api_level   => 1,
    argc        => 2,
    stream      => 1,
    record_type => 'auth'
);
__PACKAGE__->register_method(
    api_name    => "open-ils.vandelay.auth_queue.records.retrieve.export.print",
    method      => 'retrieve_queued_records',
    api_level   => 1,
    argc        => 2,
    stream      => 1,
    record_type => 'auth'
);
__PACKAGE__->register_method(
    api_name    => "open-ils.vandelay.auth_queue.records.retrieve.export.csv",
    method      => 'retrieve_queued_records',
    api_level   => 1,
    argc        => 2,
    stream      => 1,
    record_type => 'auth'
);
__PACKAGE__->register_method(
    api_name    => "open-ils.vandelay.auth_queue.records.retrieve.export.email",
    method      => 'retrieve_queued_records',
    api_level   => 1,
    argc        => 2,
    stream      => 1,
    record_type => 'auth'
);

__PACKAGE__->register_method(  
    api_name    => "open-ils.vandelay.bib_queue.records.matches.retrieve",
    method      => 'retrieve_queued_records',
    api_level   => 1,
    argc        => 2,
    stream      => 1,
    record_type => 'bib',
    signature   => {
        desc => q/Only retrieve queued bib records that have matches against existing records/
    }
);
__PACKAGE__->register_method(  
    api_name    => "open-ils.vandelay.auth_queue.records.matches.retrieve",
    method      => 'retrieve_queued_records',
    api_level   => 1,
    argc        => 2,
    stream      => 1,
    record_type => 'auth',
    signature   => {
        desc => q/Only retrieve queued authority records that have matches against existing records/
    }
);

sub retrieve_queued_records {
    my($self, $conn, $auth, $queue_id, $options) = @_;

    $options ||= {};
    my $limit = $$options{limit} || 20;
    my $offset = $$options{offset} || 0;
    my $type = $self->{record_type};

    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;

    my $queue;
    if($type eq 'bib') {
        $queue = $e->retrieve_vandelay_bib_queue($queue_id) or return $e->die_event;
    } else {
        $queue = $e->retrieve_vandelay_authority_queue($queue_id) or return $e->die_event;
    }
    my $evt = check_queue_perms($e, $type, $queue);
    return $evt if ($evt);

    my $class = ($type eq 'bib') ? 'vqbr' : 'vqar';
    my $query = {
        select => {$class => ['id']},
        from => $class,
        where => {queue => $queue_id},
        distinct => 1,
        order_by => {$class => ['id']}, 
        limit => $limit,
        offset => $offset,
    };
    if($self->api_name =~ /export/) {
        delete $query->{limit};
        delete $query->{offset};
    }

    $query->{where}->{import_time} = undef if $$options{non_imported};

    if($$options{with_import_error}) {

        $query->{from} = {$class => {vii => {type => 'left'}}};
        $query->{where}->{'-or'} = [
            {'+vqbr' => {import_error => {'!=' => undef}}},
            {'+vii' => {import_error => {'!=' => undef}}}
        ];

    } else {
        
        if($$options{with_rec_import_error}) {
            $query->{where}->{import_error} = {'!=' => undef};

        } elsif( $$options{with_item_import_error} and $type eq 'bib') {

            $query->{from} = {$class => 'vii'};
            $query->{where}->{'+vii'} = {import_error => {'!=' => undef}};
        }
    }

    if($self->api_name =~ /matches/) {
        # find only records that have matches
        my $mclass = $type eq 'bib' ? 'vbm' : 'vam';
        $query->{from} = {$class => {$mclass => {type => 'right'}}};
    } 

    my $record_ids = $e->json_query($query);

    my $retrieve = ($type eq 'bib') ? 
        'retrieve_vandelay_queued_bib_record' : 'retrieve_vandelay_queued_authority_record';
    my $search = ($type eq 'bib') ? 
        'search_vandelay_queued_bib_record' : 'search_vandelay_queued_authority_record';

    if ($self->api_name =~ /export/) {
        my $rec_list = $e->$search({id => [map { $_->{id} } @$record_ids]}, {substream => 1});
        if ($self->api_name =~ /print/) {

            $e->rollback;
            return $U->fire_object_event(
                undef,
                'vandelay.queued_'.$type.'_record.print',
                $rec_list,
                $e->requestor->ws_ou
            );

        } elsif ($self->api_name =~ /csv/) {

            $e->rollback;
            return $U->fire_object_event(
                undef,
                'vandelay.queued_'.$type.'_record.csv',
                $rec_list,
                $e->requestor->ws_ou
            );

        } elsif ($self->api_name =~ /email/) {

            $conn->respond_complete(1);

            for my $rec (@$rec_list) {
                $U->create_events_for_hook(
                    'vandelay.queued_'.$type.'_record.email',
                    $rec,
                    $e->requestor->home_ou,
                    undef,
                    undef,
                    1
                );
            }

        }
    } else {
        for my $rec_id (@$record_ids) {
            my $flesh = ['attributes', 'matches'];
            push(@$flesh, 'import_items') if $$options{flesh_import_items};
            my $params = {flesh => 1, flesh_fields => {$class => $flesh}};
            my $rec = $e->$retrieve([$rec_id->{id}, $params]);
            $rec->clear_marc if $$options{clear_marc};
            $conn->respond($rec);
        }
    }

    $e->rollback;
    return undef;
}

__PACKAGE__->register_method(  
    api_name    => 'open-ils.vandelay.import_item.queue.retrieve',
    method      => 'retrieve_queue_import_items',
    api_level   => 1,
    argc        => 2,
    stream      => 1,
    authoritative => 1,
    signature => q/
        Returns Import Item (vii) objects for the selected queue.
        Filter options:
            with_import_error : only return items that failed to import
    /
);
__PACKAGE__->register_method(
    api_name    => 'open-ils.vandelay.import_item.queue.export.print',
    method      => 'retrieve_queue_import_items',
    api_level   => 1,
    argc        => 2,
    stream      => 1,
    authoritative => 1,
    signature => q/
        Returns template-generated printable output of Import Item (vii) objects for the selected queue.
        Filter options:
            with_import_error : only return items that failed to import
    /
);
__PACKAGE__->register_method(
    api_name    => 'open-ils.vandelay.import_item.queue.export.csv',
    method      => 'retrieve_queue_import_items',
    api_level   => 1,
    argc        => 2,
    stream      => 1,
    authoritative => 1,
    signature => q/
        Returns template-generated CSV output of Import Item (vii) objects for the selected queue.
        Filter options:
            with_import_error : only return items that failed to import
    /
);
__PACKAGE__->register_method(
    api_name    => 'open-ils.vandelay.import_item.queue.export.email',
    method      => 'retrieve_queue_import_items',
    api_level   => 1,
    argc        => 2,
    stream      => 1,
    authoritative => 1,
    signature => q/
        Emails template-generated output of Import Item (vii) objects for the selected queue.
        Filter options:
            with_import_error : only return items that failed to import
    /
);

sub retrieve_queue_import_items {
    my($self, $conn, $auth, $q_id, $options) = @_;

    $options ||= {};
    my $limit = $$options{limit} || 20;
    my $offset = $$options{offset} || 0;

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    my $queue = $e->retrieve_vandelay_bib_queue($q_id) or return $e->event;
    my $evt = check_queue_perms($e, 'bib', $queue);
    return $evt if $evt;

    my $query = {
        select => {vii => ['id']},
        from => {
            vii => {
                vqbr => {
                    join => {
                        'vbq' => {
                            field => 'id',
                            fkey => 'queue',
                            filter => {id => $q_id}
                        }
                    }
                }
            }
        },
        order_by => {'vii' => ['record','id']},
        limit => $limit,
        offset => $offset
    };
    if($self->api_name =~ /export/) {
        delete $query->{limit};
        delete $query->{offset};
    }

    $query->{where} = {'+vii' => {import_error => {'!=' => undef}}}
        if $$options{with_import_error};

    my $items = $e->json_query($query);
    my $item_list = $e->search_vandelay_import_item({id => [map { $_->{id} } @$items]});
    if ($self->api_name =~ /export/) {
        if ($self->api_name =~ /print/) {

            return $U->fire_object_event(
                undef,
                'vandelay.import_items.print',
                $item_list,
                $e->requestor->ws_ou
            );

        } elsif ($self->api_name =~ /csv/) {

            return $U->fire_object_event(
                undef,
                'vandelay.import_items.csv',
                $item_list,
                $e->requestor->ws_ou
            );

        } elsif ($self->api_name =~ /email/) {

            $conn->respond_complete(1);

            for my $item (@$item_list) {
                $U->create_events_for_hook(
                    'vandelay.import_items.email',
                    $item,
                    $e->requestor->home_ou,
                    undef,
                    undef,
                    1
                );
            }

        }
    } else {
        for my $item (@$item_list) {
            $conn->respond($item);
        }
    }

    return undef;
}

sub check_queue_perms {
    my($e, $type, $queue) = @_;
    if ($type eq 'bib') {
        return $e->die_event unless
            ($e->allowed('CREATE_BIB_IMPORT_QUEUE', undef, $queue) ||
             $e->allowed('CREATE_BIB_IMPORT_QUEUE'));
    } else {
        return $e->die_event unless
            ($e->allowed('CREATE_AUTHORITY_IMPORT_QUEUE', undef, $queue) ||
             $e->allowed('CREATE_AUTHORITY_IMPORT_QUEUE'));
    }

    return undef;
}

__PACKAGE__->register_method(  
    api_name    => "open-ils.vandelay.bib_record.list.import",
    method      => 'import_record_list',
    api_level   => 1,
    argc        => 2,
    stream      => 1,
    record_type => 'bib'
);

__PACKAGE__->register_method(  
    api_name    => "open-ils.vandelay.auth_record.list.import",
    method      => 'import_record_list',
    api_level   => 1,
    argc        => 2,
    stream      => 1,
    record_type => 'auth'
);

sub import_record_list {
    my($self, $conn, $auth, $rec_ids, $args) = @_;
    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;
    $args ||= {};
    my $err = import_record_list_impl($self, $conn, $rec_ids, $e->requestor, $args);
    try {$e->rollback} otherwise {}; 
    return $err if $err;
    return {complete => 1};
}


__PACKAGE__->register_method(  
    api_name    => "open-ils.vandelay.bib_queue.import",
    method      => 'import_queue',
    api_level   => 1,
    argc        => 2,
    stream      => 1,
    max_chunk_size => 0,
    record_type => 'bib',
    signature => {
        desc => q/
            Attempts to import all non-imported records for the selected queue.
            Will also attempt import of all non-imported items.
        /
    }
);

__PACKAGE__->register_method(  
    api_name    => "open-ils.vandelay.auth_queue.import",
    method      => 'import_queue',
    api_level   => 1,
    argc        => 2,
    stream      => 1,
    max_chunk_size => 0,
    record_type => 'auth'
);

sub import_queue {
    my($self, $conn, $auth, $q_id, $options) = @_;
    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;
    $options ||= {};
    my $type = $self->{record_type};
    my $class = ($type eq 'bib') ? 'vqbr' : 'vqar';

    # First, collect the not-yet-imported records
    my $query = {queue => $q_id, import_time => undef};
    my $search = ($type eq 'bib') ? 
        'search_vandelay_queued_bib_record' : 
        'search_vandelay_queued_authority_record';
    my $rec_ids = $e->$search($query, {idlist => 1});

    # Now add any imported records that have un-imported items

    if($type eq 'bib') {
        my $item_recs = $e->json_query({
            select => {vqbr => ['id']},
            from => {vqbr => 'vii'},
            where => {
                '+vqbr' => {
                    queue => $q_id,
                    import_time => {'!=' => undef}
                },
                '+vii' => {import_time => undef}
            },
            distinct => 1
        });
        push(@$rec_ids, map {$_->{id}} @$item_recs);
    }

    my $err = import_record_list_impl($self, $conn, $rec_ids, $e->requestor, $options);
    try {$e->rollback} otherwise {}; # only using this to make the read authoritative -- don't die from it
    return $err if $err;
    return {complete => 1};
}

# returns a list of queued record IDs for a given queue that 
# have at least one entry in the match table
# XXX DEPRECATED?
sub queued_records_with_matches {
    my($e, $type, $q_id, $limit, $offset, $filter) = @_;

    my $match_class = 'vbm';
    my $rec_class = 'vqbr';
    if($type eq 'auth') {
        $match_class = 'vam';
         $rec_class = 'vqar';
    }

    $filter ||= {};
    $filter->{queue} = $q_id;

    my $query = {
        distinct => 1, 
        select => {$match_class => ['queued_record']}, 
        from => {
            $match_class => {
                $rec_class => {
                    field => 'id',
                    fkey => 'queued_record',
                    filter => $filter,
                }
            }
        }
    };        

    if($limit or defined $offset) {
        $limit ||= 20;
        $offset ||= 0;
        $query->{limit} = $limit;
        $query->{offset} = $offset;
    }

    my $data = $e->json_query($query);
    return [ map {$_->{queued_record}} @$data ];
}


sub import_record_list_impl {
    my($self, $conn, $rec_ids, $requestor, $args) = @_;

    my $overlay_map = $args->{overlay_map} || {};
    my $type = $self->{record_type};
    my %queues;

    my $report_args = {
        progress => 1,
        step => 1,
        conn => $conn,
        total => scalar(@$rec_ids),
        report_all => $$args{report_all}
    };

    $conn->max_chunk_count(1) if $$args{report_all};

    my $auto_overlay_exact = $$args{auto_overlay_exact};
    my $auto_overlay_1match = $$args{auto_overlay_1match};
    my $auto_overlay_best = $$args{auto_overlay_best_match};
    my $match_quality_ratio = $$args{match_quality_ratio};
    my $merge_profile = $$args{merge_profile};
    my $ft_merge_profile = $$args{fall_through_merge_profile};
    my $bib_source = $$args{bib_source};
    my $import_no_match = $$args{import_no_match};

    my $overlay_func = 'vandelay.overlay_bib_record';
    my $auto_overlay_func = 'vandelay.auto_overlay_bib_record';
    my $auto_overlay_best_func = 'vandelay.auto_overlay_bib_record_with_best'; # XXX bib-only
    my $retrieve_func = 'retrieve_vandelay_queued_bib_record';
    my $update_func = 'update_vandelay_queued_bib_record';
    my $search_func = 'search_vandelay_queued_bib_record';
    my $retrieve_queue_func = 'retrieve_vandelay_bib_queue';
    my $update_queue_func = 'update_vandelay_bib_queue';
    my $delete_queue_func = 'delete_vandelay_bib_queue';
    my $rec_class = 'vqbr';

    my $editor = new_editor();

    my %bib_sources;
    my $sources = $editor->search_config_bib_source({id => {'!=' => undef}});
    $bib_sources{$_->id} = $_->source for @$sources;

    if($type eq 'auth') {
        $overlay_func =~ s/bib/auth/o;
        $auto_overlay_func = s/bib/auth/o;
        $retrieve_func =~ s/bib/authority/o;
        $retrieve_queue_func =~ s/bib/authority/o;
        $update_queue_func =~ s/bib/authority/o;
        $update_func =~ s/bib/authority/o;
        $search_func =~ s/bib/authority/o;
        $delete_queue_func =~ s/bib/authority/o;
        $rec_class = 'vqar';
    }

    my $new_rec_perm_cache;
    my @success_rec_ids;
    for my $rec_id (@$rec_ids) {

        my $error = 0;
        my $overlay_target = $overlay_map->{$rec_id};

        my $e = new_editor(xact => 1);
        $e->requestor($requestor);

        $$report_args{e} = $e;
        $$report_args{evt} = undef;
        $$report_args{import_error} = undef;
        $$report_args{no_import} = 0;

        my $rec = $e->$retrieve_func([
            $rec_id,
            {   flesh => 1,
                flesh_fields => { $rec_class => ['matches']},
            }
        ]);

        unless($rec) {
            $$report_args{evt} = $e->event;
            finish_rec_import_attempt($report_args);
            next;
        }

        if($rec->import_time) {
            # if the record is already imported, that means it may have 
            # un-imported copies.  Add to success list for later processing.
            push(@success_rec_ids, $rec_id);
            $e->rollback;
            next;
        }

        $$report_args{rec} = $rec;
        $queues{$rec->queue} = 1;

        my $record;
        my $imported = 0;

        if(defined $overlay_target) {
            # Caller chose an explicit overlay target

            my $res = $e->json_query(
                {
                    from => [
                        $overlay_func,
                        $rec_id,
                        $overlay_target, 
                        $merge_profile
                    ]
                }
            );

            if($res and ($res = $res->[0])) {

                if($res->{$overlay_func} eq 't') {
                    $logger->info("vl: $type direct overlay succeeded for queued rec ".
                        "$rec_id and overlay target $overlay_target");
                    $imported = 1;
                }

            } else {
                $error = 1;
                $logger->error("vl: Error attempting overlay with func=$overlay_func, profile=$merge_profile, record=$rec_id");
            }

        } else {

            if($auto_overlay_1match) { # overlay if there is exactly 1 match

                my %match_recs = map { $_->eg_record => 1 } @{$rec->matches};

                if( scalar(keys %match_recs) == 1) { # all matches point to the same record

                    ($imported, $error, $rec) = try_auto_overlay(
                        $e, $type,
                        $report_args, 
                        $auto_overlay_best_func,
                        $retrieve_func,
                        $rec_class,
                        $rec_id, 
                        $match_quality_ratio, 
                        $merge_profile, 
                        $ft_merge_profile
                    );
                }
            }

            if(!$imported and !$error and $auto_overlay_exact and scalar(@{$rec->matches}) == 1 ) {
                
                # caller says to overlay if there is an /exact/ match
                # $auto_overlay_func only proceeds and returns true on exact matches

                my $res = $e->json_query(
                    {
                        from => [
                            $auto_overlay_func,
                            $rec_id,
                            $merge_profile
                        ]
                    }
                );

                if($res and ($res = $res->[0])) {

                    if($res->{$auto_overlay_func} eq 't') {
                        $logger->info("vl: $type auto-overlay succeeded for queued rec $rec_id");
                        $imported = 1;

                        # re-fetch the record to pick up the imported_as value from the DB
                        $$report_args{rec} = $rec = $e->$retrieve_func([
                            $rec_id, {flesh => 1, flesh_fields => {$rec_class => ['matches']}}]);

                    } else {
                        $logger->info("vl: $type auto-overlay failed for queued rec $rec_id");
                    }

                } else {
                    $error = 1;
                    $logger->error("vl: Error attempting overlay with func=$auto_overlay_func, profile=$merge_profile, record=$rec_id");
                }
            }

            if(!$imported and !$error and $auto_overlay_best and scalar(@{$rec->matches}) > 0 ) {
                # caller says to overlay the best match

                ($imported, $error, $rec) = try_auto_overlay(
                    $e, $type,
                    $report_args, 
                    $auto_overlay_best_func,
                    $retrieve_func,
                    $rec_class,
                    $rec_id, 
                    $match_quality_ratio, 
                    $merge_profile, 
                    $ft_merge_profile
                );
            }

            if(!$imported and !$error and $import_no_match and scalar(@{$rec->matches}) == 0) {
            
                # No overlay / merge occurred.  Do a traditional record import by creating a new record

                if (!$new_rec_perm_cache) {
                    $new_rec_perm_cache = {};

                    # all users creating new records are required to have the basic permission.
                    # if the client requests, we can enforce extra permissions for creating new records.
                    # for speed, check the permissions the first time then cache the result.

                    my $perm = ($type eq 'bib') ? 'IMPORT_MARC' : 'IMPORT_AUTHORITY_MARC';
                    my $xperm = $$args{new_rec_perm};
                    my $rec_ou = $e->requestor->ws_ou;

                    $new_rec_perm_cache->{evt} = $e->die_event
                        if !$e->allowed($perm, $rec_ou) || ($xperm and !$e->allowed($xperm, $rec_ou));
                }

                if ($new_rec_perm_cache->{evt}) {

                    # a cached event won't roll back the transaction (a la die_event), but
                    # the transaction will get rolled back in finish_rec_import_attempt() below
                    $$report_args{evt} = $new_rec_perm_cache->{evt};
                    $$report_args{import_error} = 'import.record.perm_failure';

                } else { # perm checks succeeded

                    $logger->info("vl: creating new $type record for queued record $rec_id");

                    if ($type eq 'bib') {

                        $record = OpenILS::Application::Cat::BibCommon->biblio_record_xml_import(
                            $e, $rec->marc, $bib_sources{$rec->bib_source}, undef, 1);

                    } else { # authority record

                        $record = OpenILS::Application::Cat::AuthCommon->import_authority_record($e, $rec->marc); #$source);
                    }

                    if($U->event_code($record)) {
                        $$report_args{import_error} = 'import.duplicate.tcn' 
                            if $record->{textcode} eq 'OPEN_TCN_NOT_FOUND';
                        $$report_args{evt} = $record;

                    } else {

                        $logger->info("vl: successfully imported new $type record");
                        $rec->imported_as($record->id);
                        $imported = 1;
                    }
                }
            }
        }

        if($imported) {

            $rec->import_time('now');
            $rec->clear_import_error;
            $rec->clear_error_detail;

            if($e->$update_func($rec)) {

                if($type eq 'bib') {

                    # see if this record is linked from an acq record.
                    my $li = $e->search_acq_lineitem(
                        {queued_record => $rec->id, state => {'!=' => 'canceled'}})->[0];

                    if ($li) { 
                        # if so, update the acq lineitem to point to the imported record
                        $li->eg_bib_id($rec->imported_as);
                        $$report_args{evt} = $e->die_event unless $e->update_acq_lineitem($li);
                    }
                }

                push @success_rec_ids, $rec_id;
                finish_rec_import_attempt($report_args);

            } else {
                $imported = 0;
            }
        }

        if(!$imported) {
            $logger->info("vl: record $rec_id was not imported");
            $$report_args{evt} = $e->event unless $$report_args{evt};
            $$report_args{no_import} = 1;
            finish_rec_import_attempt($report_args);
        }
    }

    # see if we need to mark any queues as complete
    for my $q_id (keys %queues) {

    	my $e = new_editor(xact => 1);
        my $remaining = $e->$search_func(
            [{queue => $q_id, import_time => undef}, {limit =>1}], {idlist => 1});

        unless(@$remaining) {
            my $queue = $e->$retrieve_queue_func($q_id);
            unless($U->is_true($queue->complete)) {
                $queue->complete('t');
                $e->$update_queue_func($queue) or return $e->die_event;
                $e->commit;
                next;
            }
        } 
    	$e->rollback;
    }

    # import the copies
    import_record_asset_list_impl($conn, \@success_rec_ids, $requestor) if @success_rec_ids;

    $conn->respond({total => $$report_args{total}, progress => $$report_args{progress}});
    return undef;
}


sub try_auto_overlay {
    my $e = shift;
    my $type = shift;
    my $report_args = shift;
    my $overlay_func  = shift;
    my $retrieve_func = shift; 
    my $rec_class = shift;
    my $rec_id  = shift;
    my $match_quality_ratio = shift;
    my $merge_profile  = shift;
    my $ft_merge_profile = shift;

    my $imported = 0;
    my $error = 0;

    # Find the best match and overlay if the quality ratio allows it.
    my $res = $e->json_query(
        {
            from => [
                $overlay_func,
                $rec_id, 
                $merge_profile,
                $match_quality_ratio
            ]
        }
    );

    if($res and ($res = $res->[0])) {

        if($res->{$overlay_func} eq 't') {

            # first attempt succeeded
            $imported = 1;

        } else {

            # quality-limited merge failed with insufficient quality.  If there is a 
            # fall-through merge profile, re-do the merge with the alternate profile
            # and no quality restriction.

            if($ft_merge_profile and $match_quality_ratio > 0) {

                $logger->info("vl: $type auto-merge failed with profile $merge_profile; ".
                    "re-merging with fall-through profile $ft_merge_profile");

                my $res = $e->json_query(
                    {
                        from => [
                            $overlay_func,
                            $rec_id, 
                            $ft_merge_profile,
                            0 # minimum quality not required
                        ]
                    }
                );

                if($res and ($res = $res->[0])) {

                    if($res->{$overlay_func} eq 't') {

                        # second attempt succeeded
                        $imported = 1;

                    } else {

                        # failed to merge on second attempt
                        $logger->info("vl: $type auto-merge with fall-through failed for queued rec $rec_id");
                    }
                } else {
                    
                    # second attempt died 
                    $error = 1;
                    $logger->error("vl: Error attempting overlay with func=$overlay_func, profile=$merge_profile, record=$rec_id");
                }

            } else { 

                # failed to merge on first attempt, no fall-through was provided
                $$report_args{import_error} = 'overlay.record.quality' if $match_quality_ratio > 0;
                $logger->info("vl: $type auto-merge failed for queued rec $rec_id");
            }
        }

    } else {

        # first attempt died 
        $error = 1;
        $logger->error("vl: Error attempting overlay with func=$overlay_func, profile=$merge_profile, record=$rec_id");
    }

    if($imported) {

        # at least 1 of the attempts succeeded
        $logger->info("vl: $type auto-merge succeeded for queued rec $rec_id");

        # re-fetch the record to pick up the imported_as value from the DB
        $$report_args{rec} = $e->$retrieve_func([
            $rec_id, {flesh => 1, flesh_fields => {$rec_class => ['matches']}}]);
    }

    return ($imported, $error, $$report_args{rec});
}


# tracks any import errors, commits the current xact, responds to the client
sub finish_rec_import_attempt {
    my $args = shift;
    my $evt = $$args{evt};
    my $rec = $$args{rec};
    my $e = $$args{e};

    my $error = $$args{import_error};
    $error = 'general.unknown' if $evt and not $error;

    # error tracking
    if($rec) {

        if($error or $evt) {
            # failed import
            # since an error occurred, there's no guarantee the transaction wasn't 
            # rolled back.  force a rollback and create a new editor.
            $e->rollback;
            $e = new_editor(xact => 1);
            $rec->import_error($error);

            if($evt) {
                my $detail = sprintf("%s : %s", $evt->{textcode}, substr($evt->{desc}, 0, 140));
                $rec->error_detail($detail);
            }

            my $method = 'update_vandelay_queued_bib_record';
            $method =~ s/bib/authority/ if $$args{type} eq 'auth';
            $e->$method($rec) and $e->commit or $e->rollback;

        } else {
            # commit the successful import
            $e->commit;
        }

    } else {
        # requested queued record was not found
        $e->rollback;
    }
        
    # respond to client
    if($$args{report_all} or ($$args{progress} % $$args{step}) == 0) {
        $$args{conn}->respond({
            total => $$args{total}, 
            progress => $$args{progress}, 
            imported => ($rec) ? $rec->id : undef,
            import_error => $error,
            no_import => $$args{no_import},
            err_event => $evt
        });
        $$args{step} *= 2 unless $$args{step} == 256;
    }

    $$args{progress}++;
}





__PACKAGE__->register_method(  
    api_name    => "open-ils.vandelay.bib_queue.owner.retrieve",
    method      => 'owner_queue_retrieve',
    api_level   => 1,
    argc        => 2,
    stream      => 1,
    record_type => 'bib'
);
__PACKAGE__->register_method(  
    api_name    => "open-ils.vandelay.authority_queue.owner.retrieve",
    method      => 'owner_queue_retrieve',
    api_level   => 1,
    argc        => 2,
    stream      => 1,
    record_type => 'auth'
);

sub owner_queue_retrieve {
    my($self, $conn, $auth, $owner_id, $filters) = @_;
    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;
    $owner_id = $e->requestor->id; # XXX add support for viewing other's queues?
    my $queues;
    $filters ||= {};
    my $search = {owner => $owner_id};
    $search->{$_} = $filters->{$_} for keys %$filters;

    if($self->{record_type} eq 'bib') {
        $queues = $e->search_vandelay_bib_queue(
            [$search, {order_by => {vbq => 'evergreen.lowercase(name)'}}]);
    } else {
        $queues = $e->search_vandelay_authority_queue(
            [$search, {order_by => {vaq => 'evergreen.lowercase(name)'}}]);
    }
    $conn->respond($_) for @$queues;
    $e->rollback;
    return undef;
}

__PACKAGE__->register_method(  
    api_name    => "open-ils.vandelay.bib_queue.delete",
    method      => "delete_queue",
    api_level   => 1,
    argc        => 2,
    record_type => 'bib'
);            
__PACKAGE__->register_method(  
    api_name    => "open-ils.vandelay.auth_queue.delete",
    method      => "delete_queue",
    api_level   => 1,
    argc        => 2,
    record_type => 'auth'
);  

sub delete_queue {
    my($self, $conn, $auth, $q_id) = @_;
    my $e = new_editor(xact => 1, authtoken => $auth);
    return $e->die_event unless $e->checkauth;
    if($self->{record_type} eq 'bib') {
        return $e->die_event unless $e->allowed('CREATE_BIB_IMPORT_QUEUE');
        my $queue = $e->retrieve_vandelay_bib_queue($q_id)
            or return $e->die_event;
        $e->delete_vandelay_bib_queue($queue)
            or return $e->die_event;
    } else {
           return $e->die_event unless $e->allowed('CREATE_AUTHORITY_IMPORT_QUEUE');
        my $queue = $e->retrieve_vandelay_authority_queue($q_id)
            or return $e->die_event;
        $e->delete_vandelay_authority_queue($queue)
            or return $e->die_event;
    }
    $e->commit;
    return 1;
}


__PACKAGE__->register_method(  
    api_name    => "open-ils.vandelay.queued_bib_record.html",
    method      => 'queued_record_html',
    api_level   => 1,
    argc        => 2,
    stream      => 1,
    record_type => 'bib'
);
__PACKAGE__->register_method(  
    api_name    => "open-ils.vandelay.queued_authority_record.html",
    method      => 'queued_record_html',
    api_level   => 1,
    argc        => 2,
    stream      => 1,
    record_type => 'auth'
);

sub queued_record_html {
    my($self, $conn, $auth, $rec_id) = @_;
    my $e = new_editor(xact=>1,authtoken => $auth);
    return $e->die_event unless $e->checkauth;
    my $rec;
    if($self->{record_type} eq 'bib') {
        $rec = $e->retrieve_vandelay_queued_bib_record($rec_id)
            or return $e->die_event;
    } else {
        $rec = $e->retrieve_vandelay_queued_authority_record($rec_id)
            or return $e->die_event;
    }

    $e->rollback;
    return $U->simplereq(
        'open-ils.search',
        'open-ils.search.biblio.record.html', undef, 1, $rec->marc);
}


__PACKAGE__->register_method(  
    api_name    => "open-ils.vandelay.bib_queue.summary.retrieve", 
    method      => 'retrieve_queue_summary',
    api_level   => 1,
    argc        => 2,
    stream      => 1,
    record_type => 'bib'
);
__PACKAGE__->register_method(  
    api_name    => "open-ils.vandelay.auth_queue.summary.retrieve",
    method      => 'retrieve_queue_summary',
    api_level   => 1,
    argc        => 2,
    stream      => 1,
    record_type => 'auth'
);

sub retrieve_queue_summary {
    my($self, $conn, $auth, $queue_id) = @_;
    my $e = new_editor(xact=>1, authtoken => $auth);
    return $e->die_event unless $e->checkauth;

    my $queue;
    my $type = $self->{record_type};
    if($type eq 'bib') {
        $queue = $e->retrieve_vandelay_bib_queue($queue_id)
            or return $e->die_event;
    } else {
        $queue = $e->retrieve_vandelay_authority_queue($queue_id)
            or return $e->die_event;
    }

    my $evt = check_queue_perms($e, $type, $queue);
    return $evt if $evt;

    my $search = 'search_vandelay_queued_bib_record';
    $search =~ s/bib/authority/ if $type ne 'bib';

    my $summary = {
        queue => $queue,
        total => scalar(@{$e->$search({queue => $queue_id}, {idlist=>1})}),
        imported => scalar(@{$e->$search({queue => $queue_id, import_time => {'!=' => undef}}, {idlist=>1})}),
    };

    my $class = ($type eq 'bib') ? 'vqbr' : 'vqar';
    $summary->{rec_import_errors} = $e->json_query({
        select => {$class => [{alias => 'count', column => 'id', transform => 'count', aggregate => 1}]},
        from => $class,
        where => {queue => $queue_id, import_error => {'!=' => undef}}
    })->[0]->{count};

    if($type eq 'bib') {
        
        # count of all items attached to records in the queue in question
        my $query = {
            select => {vii => [{alias => 'count', column => 'id', transform => 'count', aggregate => 1}]},
            from => 'vii',
            where => {
                record => {
                    in => {
                        select => {vqbr => ['id']},
                        from => 'vqbr',
                        where => {queue => $queue_id}
                    }
                }
            }
        };
        $summary->{total_items} = $e->json_query($query)->[0]->{count};

        # count of items we attempted to import, but errored, attached to records in the queue in question
        $query->{where}->{import_error} = {'!=' => undef};
        $summary->{item_import_errors} = $e->json_query($query)->[0]->{count};

        # count of items we successfully imported attached to records in the queue in question
        delete $query->{where}->{import_error};
        $query->{where}->{import_time} = {'!=' => undef};
        $summary->{total_items_imported} = $e->json_query($query)->[0]->{count};
    }

    return $summary;
}

# --------------------------------------------------------------------------------
# Given a list of queued record IDs, imports all items attached to those records
# --------------------------------------------------------------------------------
sub import_record_asset_list_impl {
    my($conn, $rec_ids, $requestor) = @_;

    my $roe = new_editor(xact=> 1, requestor => $requestor);

    # for speed, filter out any records have not been 
    # imported or have no import items to load
    $rec_ids = $roe->json_query({
        select => {vqbr => ['id']},
        from => {vqbr => 'vii'},
        where => {'+vqbr' => {
            id => $rec_ids,
            import_time => {'!=' => undef}
        }},
        distinct => 1
    });
    $rec_ids = [map {$_->{id}} @$rec_ids];

    my $report_args = {
        conn => $conn,
        total => scalar(@$rec_ids),
        step => 1, # how often to respond
        progress => 1,
        in_count => 0,
    };

    for my $rec_id (@$rec_ids) {
        my $rec = $roe->retrieve_vandelay_queued_bib_record($rec_id);
        my $item_ids = $roe->search_vandelay_import_item(
            {record => $rec->id, import_error => undef}, 
            {idlist=>1}
        );

        for my $item_id (@$item_ids) {
            my $e = new_editor(requestor => $requestor, xact => 1);
            my $item = $e->retrieve_vandelay_import_item($item_id);
            my ($copy, $vol, $evt);

            $$report_args{import_item} = $item;
            $$report_args{e} = $e;
            $$report_args{import_error} = undef;
            $$report_args{evt} = undef;

            if (my $copy_id = $item->internal_id) { # assignment
                # copy matches an existing copy.  Overlay instead of create.

                $logger->info("vl: performing copy overlay for internal_id=$copy_id");

                my $qt = $e->json_query({
                    select => {vbq => ['queue_type']},
                    from => {vqbr => 'vbq'},
                    where => {'+vqbr' => {id => $rec_id}}
                })->[0]->{queue_type};

                if ($qt eq 'acq') {
                    # internal_id for ACQ queues refers to acq.lineitem_detail.id
                    # pull the real copy id from the acq LID

                    my $lid = $e->retrieve_acq_lineitem_detail($copy_id);
                    if (!$lid) {
                        $$report_args{evt} = $e->die_event;
                        respond_with_status($report_args);
                        next;
                    }
                    $copy_id = $lid->eg_copy_id;
                    $logger->info("vl: performing ACQ copy overlay for copy $copy_id");
                }

                $copy = $e->search_asset_copy([
                    {id => $copy_id, deleted => 'f'},
                    {flesh => 1, flesh_fields => {acp => ['call_number']}}
                ])->[0];

                if (!$copy) {
                    $$report_args{evt} = $e->die_event;
                    respond_with_status($report_args);
                    next;
                }

                # prevent update of unrelated copies
                if ($copy->call_number->record != $rec->imported_as) {
                    $logger->info("vl: attempt to overlay unrelated copy=$copy_id; rec=".$rec->imported_as);

                    $evt = OpenILS::Event->new('INVALID_IMPORT_COPY_ID', 
                        note => 'Cannot overlay copies for unlinked bib',
                        bre => $rec->imported_as, 
                        copy_id => $copy_id
                    );
                    $$report_args{evt} = $evt;
                    respond_with_status($report_args);
                    next;
                }

                # overlaying copies requires an extra permission
                if (!$e->allowed("IMPORT_OVERLAY_COPY", $copy->call_number->owning_lib)) {
                    $$report_args{evt} = $e->die_event;
                    respond_with_status($report_args);
                    next;
                }

                # are we updating the call-number?
                if ($item->call_number and $item->call_number ne $copy->call_number->label) {

                    my $count = $e->json_query({
                        select => {acp => [{
                            alias => 'count', 
                            column => 'id', 
                            transform => 'count', 
                            aggregate => 1
                        }]},
                        from => 'acp',
                        where => {
                            deleted => 'f',
                            call_number => $copy->call_number->id
                        }
                    })->[0]->{count};

                    if ($count == 1) {
                        # if this is the only copy attached to this 
                        # callnumber, just update the callnumber

                        $logger->info("vl: updating callnumber label in copy overlay");

                        $copy->call_number->label($item->call_number);
                        if (!$e->update_asset_call_number($copy->call_number)) {
                            $$report_args{evt} = $e->die_event;
                            respond_with_status($report_args);
                            next;
                        }

                    } else {

                        # otherwise, move the copy to a new/existing 
                        # call-number with the given label/owner
                        # note that overlay does not allow the owning_lib 
                        # to be changed.  Should it?

                        $logger->info("vl: moving copy to new callnumber in copy overlay");

                        ($vol, $evt) =
                            OpenILS::Application::Cat::AssetCommon->find_or_create_volume(
                                $e, $item->call_number, 
                                $copy->call_number->record, 
                                $copy->call_number->owning_lib
                            );

                        if($evt) {
                            $$report_args{evt} = $evt;
                            respond_with_status($report_args);
                            next;
                        }

                        $copy->call_number($vol);
                    }
                } # cn-update

                # for every field that has a non-'' value, overlay the copy value
                foreach (qw/ barcode location circ_lib status 
                    circulate deposit deposit_amount ref holdable 
                    price circ_as_type alert_message opac_visible circ_modifier/) {

                    my $val = $item->$_();
                    $copy->$_($val) if $val and $val ne '';
                }

                # de-flesh for update
                $copy->call_number($copy->call_number->id);
                $copy->ischanged(1);

                $evt = OpenILS::Application::Cat::AssetCommon->
                    update_fleshed_copies($e, {all => 1}, undef, [$copy]);

                if($evt) {
                    $$report_args{evt} = $evt;
                    respond_with_status($report_args);
                    next;
                }

            } else { 

                # Creating a new copy
                $logger->info("vl: creating new copy in import");

                # --------------------------------------------------------------------------------
                # Find or create the volume
                # --------------------------------------------------------------------------------
                my ($vol, $evt) =
                    OpenILS::Application::Cat::AssetCommon->find_or_create_volume(
                        $e, $item->call_number, $rec->imported_as, $item->owning_lib);

                if($evt) {
                    $$report_args{evt} = $evt;
                    respond_with_status($report_args);
                    next;
                }

                # --------------------------------------------------------------------------------
                # Create the new copy
                # --------------------------------------------------------------------------------
                $copy = Fieldmapper::asset::copy->new;
                $copy->loan_duration(2);
                $copy->fine_level(2);
                $copy->barcode($item->barcode);
                $copy->location($item->location);
                $copy->circ_lib($item->circ_lib || $item->owning_lib);
                $copy->status( defined($item->status) ? $item->status : OILS_COPY_STATUS_IN_PROCESS );
                $copy->circulate($item->circulate);
                $copy->deposit($item->deposit);
                $copy->deposit_amount($item->deposit_amount);
                $copy->ref($item->ref);
                $copy->holdable($item->holdable);
                $copy->price($item->price);
                $copy->circ_as_type($item->circ_as_type);
                $copy->alert_message($item->alert_message);
                $copy->opac_visible($item->opac_visible);
                $copy->circ_modifier($item->circ_modifier);

                # --------------------------------------------------------------------------------
                # Check for dupe barcode
                # --------------------------------------------------------------------------------
                if($evt = OpenILS::Application::Cat::AssetCommon->create_copy($e, $vol, $copy)) {
                    $$report_args{evt} = $evt;
                    $$report_args{import_error} = 'import.item.duplicate.barcode'
                        if $evt->{textcode} eq 'ITEM_BARCODE_EXISTS';
                    respond_with_status($report_args);
                    next;
                }

                # --------------------------------------------------------------------------------
                # create copy notes
                # --------------------------------------------------------------------------------
                $evt = OpenILS::Application::Cat::AssetCommon->create_copy_note(
                    $e, $copy, '', $item->pub_note, 1) if $item->pub_note;

                if($evt) {
                    $$report_args{evt} = $evt;
                    respond_with_status($report_args);
                    next;
                }

                $evt = OpenILS::Application::Cat::AssetCommon->create_copy_note(
                    $e, $copy, '', $item->priv_note) if $item->priv_note;

                if($evt) {
                    $$report_args{evt} = $evt;
                    respond_with_status($report_args);
                    next;
                }
            }

            # set the import data on the import item
            $item->imported_as($copy->id); # $copy->id is set by create_copy() ^--
            $item->import_time('now');

            unless($e->update_vandelay_import_item($item)) {
                $$report_args{evt} = $e->die_event;
                respond_with_status($report_args);
                next;
            }

            # --------------------------------------------------------------------------------
            # Item import succeeded
            # --------------------------------------------------------------------------------
            $e->commit;
            $$report_args{in_count}++;
            respond_with_status($report_args);
            $logger->info("vl: successfully imported item " . $item->barcode);
        }
    }

    $roe->rollback;
    return undef;
}


sub respond_with_status {
    my $args = shift;
    my $e = $$args{e};

    #  If the import failed, track the failure reason

    my $error = $$args{import_error};
    my $evt = $$args{evt};

    if($error or $evt) {

        my $item = $$args{import_item};
        $logger->info("vl: unable to import item " . $item->barcode);

        $error ||= 'general.unknown';
        $item->import_error($error);

        if($evt) {
            my $detail = sprintf("%s : %s", $evt->{textcode}, substr($evt->{desc}, 0, 140));
            $item->error_detail($detail);
        }

        # state of the editor is unknown at this point.  Force a rollback and start over.
        $e->rollback;
        $e = new_editor(xact => 1);
        $e->update_vandelay_import_item($item);
        $e->commit;
    }

    if($$args{report_all} or ($$args{progress} % $$args{step}) == 0) {
        $$args{conn}->respond({
            total => $$args{total},
            progress => $$args{progress},
            success_count => $$args{success_count},
            err_event => $evt
        });
        $$args{step} *= 2 unless $$args{step} == 256;
    }

    $$args{progress}++;
}

__PACKAGE__->register_method(  
    api_name    => "open-ils.vandelay.match_set.get_tree",
    method      => "match_set_get_tree",
    api_level   => 1,
    argc        => 2,
    signature   => {
        desc    => q/For a given vms object, return a tree of match set points
                    represented by a vmsp object with recursively fleshed
                    children./
    }
);

sub match_set_get_tree {
    my ($self, $conn, $authtoken, $match_set_id) = @_;

    $match_set_id = int($match_set_id) or return;

    my $e = new_editor("authtoken" => $authtoken);
    $e->checkauth or return $e->die_event;

    my $set = $e->retrieve_vandelay_match_set($match_set_id) or
        return $e->die_event;

    $e->allowed("ADMIN_IMPORT_MATCH_SET", $set->owner) or
        return $e->die_event;

    my $tree = $e->search_vandelay_match_set_point([
        {"match_set" => $match_set_id, "parent" => undef},
        {"flesh" => -1, "flesh_fields" => {"vmsp" => ["children"]}}
    ]) or return $e->die_event;

    return pop @$tree;
}


__PACKAGE__->register_method(
    api_name    => "open-ils.vandelay.match_set.update",
    method      => "match_set_update_tree",
    api_level   => 1,
    argc        => 3,
    signature   => {
        desc => q/Replace any vmsp objects associated with a given (by ID) vms
                with the given objects (recursively fleshed vmsp tree)./
    }
);

sub _walk_new_vmsp {
    my ($e, $match_set_id, $node, $parent_id) = @_;

    my $point = new Fieldmapper::vandelay::match_set_point;
    $point->parent($parent_id);
    $point->match_set($match_set_id);
    $point->$_($node->$_) for (qw/bool_op svf tag subfield negate quality/);

    $e->create_vandelay_match_set_point($point) or return $e->die_event;

    $parent_id = $e->data->id;
    if ($node->children && @{$node->children}) {
        for (@{$node->children}) {
            return $e->die_event if
                _walk_new_vmsp($e, $match_set_id, $_, $parent_id);
        }
    }

    return;
}

sub match_set_update_tree {
    my ($self, $conn, $authtoken, $match_set_id, $tree) = @_;

    my $e = new_editor("xact" => 1, "authtoken" => $authtoken);
    $e->checkauth or return $e->die_event;

    my $set = $e->retrieve_vandelay_match_set($match_set_id) or
        return $e->die_event;

    $e->allowed("ADMIN_IMPORT_MATCH_SET", $set->owner) or
        return $e->die_event;

    my $existing = $e->search_vandelay_match_set_point([
        {"match_set" => $match_set_id},
        {"order_by" => {"vmsp" => "id DESC"}}
    ]) or return $e->die_event;

    # delete points, working up from leaf points to the root
    while(@$existing) {
        for my $point (shift @$existing) {
            if( grep {$_->parent eq $point->id} @$existing) {
                push(@$existing, $point);
            } else {
                $e->delete_vandelay_match_set_point($point) or return $e->die_event;
            }
        }
    }

    _walk_new_vmsp($e, $match_set_id, $tree);

    $e->commit or return $e->die_event;
}

__PACKAGE__->register_method(  
    api_name    => 'open-ils.vandelay.bib_queue.to_bucket',
    method      => 'bib_queue_to_bucket',
    api_level   => 1,
    argc        => 2,
    signature   => {
        desc    => q/Add to or create a new bib container (bucket) with the successfully 
                    imported contents of a vandelay queue.  Any user that has Vandelay 
                    queue create permissions can append or create buckets from his-her own queues./,
        params  => [
            {desc => 'Authtoken', type => 'string'},
            {desc => 'Queue ID', type => 'number'},
            {desc => 'Bucket Name', type => 'string'}
        ],
        return  => {desc => q/
            {bucket => $bucket, addcount => number-of-items-added-to-bucket, item_count => total-bucket-item-count} on success,
            {add_count => 0} if there is nothing to do, and Event on error/}
    }
);

sub bib_queue_to_bucket {
    my ($self, $conn, $auth, $q_id, $bucket_name) = @_;

    my $e = new_editor(xact => 1, authtoken => $auth);
    return $e->die_event unless $e->checkauth;
    
    my $queue = $e->retrieve_vandelay_bib_queue($q_id)
        or return $e->die_event;

    return OpenILS::Event->new('BAD_PARAMS', 
        note => q/Bucket creator must be queue owner/)
        unless $queue->owner == $e->requestor->id;

    # find the bib IDs that will go into the bucket
    my $bib_ids = $e->json_query({
        select => {vqbr => ['imported_as']},
        from => 'vqbr',
        where => {queue => $q_id, imported_as => {'!=' => undef}}
    });

    if (!@$bib_ids) { # no records to add
        $e->rollback;
        return {add_count => 0};
    }

    # allow user to add to an existing bucket by name
    my $bucket = $e->search_container_biblio_record_entry_bucket({
        owner => $e->requestor->id, 
        name => $bucket_name,
        btype => 'vandelay_queue'
    })->[0];

    # if the bucket does not exist, create a new one
    if (!$bucket) { 
        $bucket = Fieldmapper::container::biblio_record_entry_bucket->new;
        $bucket->name($bucket_name);
        $bucket->owner($e->requestor->id);
        $bucket->btype('vandelay_queue');

        $e->create_container_biblio_record_entry_bucket($bucket)
            or return $e->die_event;
    }

    # create the new bucket items
    for my $bib_id ( map {$_->{imported_as}} @$bib_ids ) {
        my $item = Fieldmapper::container::biblio_record_entry_bucket_item->new;
        $item->target_biblio_record_entry($bib_id);
        $item->bucket($bucket->id);
        $e->create_container_biblio_record_entry_bucket_item($item)
            or return $e->die_event;
    }

    # re-fetch the bucket to pick up the correct create_time
    $bucket = $e->retrieve_container_biblio_record_entry_bucket($bucket->id)
        or return $e->die_event;

    # get the total count of items in this bucket
    my $count = $e->json_query({
        select => {cbrebi => [{
            aggregate =>  1,
            transform => 'count',
            alias => 'count',
            column => 'id'
        }]},
        from => 'cbrebi',
        where => {bucket => $bucket->id}
    })->[0];

    $e->commit;

    return {
        bucket => $bucket, 
        add_count => scalar(@$bib_ids), # items added to the bucket
        item_count => $count->{count} # total items in buckets
    };
}

1;
