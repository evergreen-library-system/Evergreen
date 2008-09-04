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

use MARC::Batch;
use MARC::Record;
use MARC::File::XML;

use OpenILS::Utils::Fieldmapper;

use Time::HiRes qw(time);

use OpenSRF::Utils::Logger qw/$logger/;
use MIME::Base64;
use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';

sub initialize {}
sub child_init {}

sub entityize {
	my $stuff = shift;
	my $form = shift || '';

	if ($form eq 'D') {
		$stuff = NFD($stuff);
	} else {
		$stuff = NFC($stuff);
	}

	$stuff =~ s/([\x{0080}-\x{fffd}])/sprintf('&#x%X;',ord($1))/sgoe;
	return $stuff;
}

# --------------------------------------------------------------------------------
# Biblio ingest

sub create_bib_queue {
	my $self = shift;
	my $client = shift;
	my $auth = shift;
	my $name = shift;
	my $owner = shift;
	my $type = shift;

	my $e = new_editor(authtoken => $auth, xact => 1);

	return $e->die_event unless $e->checkauth;
	return $e->die_event unless $e->allowed('CREATE_BIB_IMPORT_QUEUE');
    $owner ||= $e->requestor->id;

	my $queue = new Fieldmapper::vandelay::bib_queue();
	$queue->name( $name );
	$queue->owner( $owner );
	$queue->queue_type( $type ) if ($type);

	my $new_q = $e->create_vandelay_bib_queue( $queue );
	return $e->die_event unless ($new_q);
	$e->commit;

    return $new_q;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.vandelay.bib_queue.create",
	method		=> "create_bib_queue",
	api_level	=> 1,
	argc		=> 3,
);                      


sub create_auth_queue {
	my $self = shift;
	my $client = shift;
	my $auth = shift;
	my $name = shift;
	my $owner = shift;
	my $type = shift;

	my $e = new_editor(authtoken => $auth, xact => 1);

	return $e->die_event unless $e->checkauth;
	return $e->die_event unless $e->allowed('CREATE_AUTHORITY_IMPORT_QUEUE');
    $owner ||= $e->requestor->id;

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
	api_name	=> "open-ils.vandelay.authority_queue.create",
	method		=> "create_auth_queue",
	api_level	=> 1,
	argc		=> 3,
);                      

sub add_record_to_bib_queue {
	my $self = shift;
	my $client = shift;
	my $auth = shift;
	my $queue = shift;
	my $marc = shift;
	my $purpose = shift;

	my $e = new_editor(authtoken => $auth, xact => 1);

	$queue = $e->retrieve_vandelay_bib_queue($queue);

	return $e->die_event unless $e->checkauth;
	return $e->die_event unless
		($e->allowed('CREATE_BIB_IMPORT_QUEUE', undef, $queue) ||
		 $e->allowed('CREATE_BIB_IMPORT_QUEUE'));

	my $new_rec = _add_bib_rec($e, $marc, $queue->id, $purpose);

	return $e->die_event unless ($new_rec);
	$e->commit;
    return $new_rec;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.vandelay.queued_bib_record.create",
	method		=> "add_record_to_bib_queue",
	api_level	=> 1,
	argc		=> 3,
);                      

sub _add_bib_rec {
	my $e = shift;
	my $marc = shift;
	my $queue = shift;
	my $purpose = shift;

	my $rec = new Fieldmapper::vandelay::queued_bib_record();
	$rec->marc( $marc );
	$rec->queue( $queue );
	$rec->purpose( $purpose ) if ($purpose);

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
	api_name	=> "open-ils.vandelay.queued_authority_record.create",
	method		=> "add_record_to_authority_queue",
	api_level	=> 1,
	argc		=> 3,
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
	my $fingerprint = shift;
	my $queue_id = shift;

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
    return $evt if $evt;

	my $method = "open-ils.vandelay.queued_${type}_record.create";
	$method = $self->method_lookup( $method );

    my $cache = new OpenSRF::Utils::Cache();

    my $data = $cache->get_cache('vandelay_import_spool_' . $fingerprint);
	my $purpose = $data->{purpose};
    $data = decode_base64($data->{marc});

    $logger->info("vandelay loaded $fingerprint purpose=$purpose and ".length($data)." bytes of data");

    my $fh;
    open $fh, '<', \$data;

    my $marctype = 'USMARC'; # ?
	my $batch = new MARC::Batch ( $marctype, $fh );
	$batch->strict_off;

	my $count = 0;
	while (my $r = $batch->next) {
        $logger->info("processing record $count");
		try {
			(my $xml = $r->as_xml_record()) =~ s/\n//sog;
			$xml =~ s/^<\?xml.+\?\s*>//go;
			$xml =~ s/>\s+</></go;
			$xml =~ s/\p{Cc}//go;
			$xml = entityize($xml);
			$xml =~ s/[\x00-\x1f]//go;

			if ($type eq 'bib') {
				_add_bib_rec( $e, $xml, $queue_id, $purpose ) or return $e->die_event;
			} else {
				_add_auth_rec( $e, $xml, $queue_id, $purpose ) or return $e->die_event;
			}
			$count++;
			
			$client->respond( $count );
		} catch Error with {
			my $error = shift;
			$logger->warn("Encountered a bad record at Vandelay ingest: ".$error);
		}
	}

	$e->commit;
	return undef;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.vandelay.bib.process_spool",
	method		=> "process_spool",
	api_level	=> 1,
	argc		=> 3,
	record_type	=> 'bib'
);                      
__PACKAGE__->register_method(  
	api_name	=> "open-ils.vandelay.auth.process_spool",
	method		=> "process_spool",
	api_level	=> 1,
	argc		=> 3,
	record_type	=> 'auth'
);                      


__PACKAGE__->register_method(  
	api_name	=> "open-ils.vandelay.bib_queue.records.retrieve",
	method		=> 'retrieve_queue',
	api_level	=> 1,
	argc		=> 2,
    stream      => 1,
	record_type	=> 'bib'
);
__PACKAGE__->register_method(  
	api_name	=> "open-ils.vandelay.auth_queue.records.retrieve",
	method		=> 'retrieve_queue',
	api_level	=> 1,
	argc		=> 2,
    stream      => 1,
	record_type	=> 'auth'
);

sub retrieve_queue {
    my($self, $conn, $auth, $queue_id, $options) = @_;
    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    my $type = $self->{record_type};
    my $queue;
    if($type eq 'bib') {
        $queue = $e->retrieve_vandelay_bib_queue($queue_id) or return $e->die_event;
    } else {
        $queue = $e->retrieve_vandelay_authority_queue($queue_id) or return $e->die_event;
    }
    my $evt = check_queue_perms($e, $type, $queue);
    return $evt if $evt;

    my $class = ($type eq 'bib') ? 'vqbr' : 'vqar';
    my $search = ($type eq 'bib') ? 'search_vandelay_queued_bib_record' : 'search_vandelay_queued_authority_record';
    my $retrieve = ($type eq 'bib') ? 'retrieve_vandelay_queued_bib_record' : 'retrieve_vandelay_queued_authority_record';
    my $record_ids = $e->$search({queue => $queue_id}, {idlist => 1});

    for my $rec_id (@$record_ids) {
        my $rec = $e->$retrieve([
            $rec_id,
            {   flesh => 1,
                flesh_fields => {$class => ['attributes', 'matches']}
            }
        ]);
        $rec->clear_marc if $$options{clear_marc};
        $conn->respond($rec);
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
	api_name	=> "open-ils.vandelay.bib_record.list.import",
	method		=> 'import_record_list',
	api_level	=> 1,
	argc		=> 2,
    stream      => 1,
	record_type	=> 'bib'
);

__PACKAGE__->register_method(  
	api_name	=> "open-ils.vandelay.auth_record.list.import",
	method		=> 'import_record_list',
	api_level	=> 1,
	argc		=> 2,
    stream      => 1,
	record_type	=> 'auth'
);

__PACKAGE__->register_method(  
	api_name	=> "open-ils.vandelay.bib_record.list.overlay",
	method		=> 'import_record_list',
	api_level	=> 1,
	argc		=> 2,
    stream      => 1,
	record_type	=> 'bib'
);

__PACKAGE__->register_method(  
	api_name	=> "open-ils.vandelay.auth_record.list.overlay",
	method		=> 'import_record_list',
	api_level	=> 1,
	argc		=> 2,
    stream      => 1,
	record_type	=> 'auth'
);


sub import_record_list {
    my($self, $conn, $auth, $rec_ids, $args) = @_;
    my $e = new_editor(xact => 1, authtoken => $auth);
    return $e->die_event unless $e->checkauth;
    $args ||= {};
    my $err = import_record_list_impl($self, $conn, $auth, $e, $rec_ids, $args);
    return $err if $err;
    $e->commit;
    return {complete => 1};
}

#open-ils.cat.biblio.record.xml.update

sub import_record_list_impl {
    my($self, $conn, $auth, $e, $rec_ids, $args) = @_;

    my $overlay_map = $args->{overlay_map};
    my $type = $self->{record_type};
    my $total = @$rec_ids;
    my $count = 0;

    for my $rec_id (@$rec_ids) {
        if($type eq 'bib') {

            my $rec = $e->retrieve_vandelay_queued_bib_record($rec_id) 
                or return $e->die_event;

            my $record;
            if($self->api_name =~ /overlay/) {
                $record = $U->simplereq(
                    'open-ils.cat',
                    'open-ils.cat.biblio.record.xml.update',
                    $auth, $overlay_map->{$rec_id}, $rec->marc); #$rec->bib_source);
            } else {
                $record = $U->simplereq(
                    'open-ils.cat',
                    'open-ils.cat.biblio.record.xml.import',
                    $auth, $rec->marc); #$rec->bib_source);
            }

            if($U->event_code($record)) {
                $e->rollback;
                return $record;
            }

            $rec->imported_as($record->id);
            $rec->import_time('now');
            $e->update_vandelay_queued_bib_record($rec) or return $e->die_event;
        }

        $conn->respond({total => $total, progress => ++$count, imported => $rec_id});
    }

    return undef;
}




1;
