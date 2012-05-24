use strict; use warnings;
package OpenILS::Application::Cat;
use OpenILS::Application::AppUtils;
use OpenILS::Application;
use OpenILS::Application::Cat::Merge;
use OpenILS::Application::Cat::Authority;
use OpenILS::Application::Cat::BibCommon;
use OpenILS::Application::Cat::AssetCommon;
use base qw/OpenILS::Application/;
use Time::HiRes qw(time);
use OpenSRF::EX qw(:try);
use OpenSRF::Utils::JSON;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Event;
use OpenILS::Const qw/:const/;

use XML::LibXML;
use Unicode::Normalize;
use Data::Dumper;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Perm;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Logger qw($logger);
use OpenSRF::AppSession;

my $U = "OpenILS::Application::AppUtils";
my $conf;
my %marctemplates;
my $assetcom = 'OpenILS::Application::Cat::AssetCommon';

__PACKAGE__->register_method(
    method   => "retrieve_marc_template",
    api_name => "open-ils.cat.biblio.marc_template.retrieve",
    notes    => <<"    NOTES");
    Returns a MARC 'record tree' based on a set of pre-defined templates.
    Templates include : book
    NOTES

sub retrieve_marc_template {
    my( $self, $client, $type ) = @_;
    return $marctemplates{$type} if defined($marctemplates{$type});
    $marctemplates{$type} = _load_marc_template($type);
    return $marctemplates{$type};
}

__PACKAGE__->register_method(
    method   => 'fetch_marc_template_types',
    api_name => 'open-ils.cat.marc_template.types.retrieve'
);

my $marc_template_files;

sub fetch_marc_template_types {
    my( $self, $conn ) = @_;
    __load_marc_templates();
    return [ keys %$marc_template_files ];
}

sub __load_marc_templates {
    return if $marc_template_files;
    if(!$conf) { $conf = OpenSRF::Utils::SettingsClient->new; }

    $marc_template_files = $conf->config_value(                    
        "apps", "open-ils.cat","app_settings", "marctemplates" );

    $logger->info("Loaded marc templates: " . Dumper($marc_template_files));
}

sub _load_marc_template {
    my $type = shift;

    __load_marc_templates();

    my $template = $$marc_template_files{$type};
    open( F, $template ) or 
        throw OpenSRF::EX::ERROR ("Unable to open MARC template file: $template : $@");

    my @xml = <F>;
    close(F);
    my $xml = join('', @xml);

    return XML::LibXML->new->parse_string($xml)->documentElement->toString;
}



__PACKAGE__->register_method(
    method   => 'fetch_bib_sources',
    api_name => 'open-ils.cat.bib_sources.retrieve.all');

sub fetch_bib_sources {
    return OpenILS::Application::Cat::BibCommon->fetch_bib_sources();
}

__PACKAGE__->register_method(
    method    => "create_record_xml",
    api_name  => "open-ils.cat.biblio.record.xml.create.override",
    signature => q/@see open-ils.cat.biblio.record.xml.create/);

__PACKAGE__->register_method(
    method    => "create_record_xml",
    api_name  => "open-ils.cat.biblio.record.xml.create",
    signature => q/
        Inserts a new biblio with the given XML
    /
);

sub create_record_xml {
    my( $self, $client, $login, $xml, $source, $oargs ) = @_;

    my $override = 1 if $self->api_name =~ /override/;
    $oargs = { all => 1 } unless defined $oargs;

    my( $user_obj, $evt ) = $U->checksesperm($login, 'CREATE_MARC');
    return $evt if $evt;

    $logger->activity("user ".$user_obj->id." creating new MARC record");

    my $meth = $self->method_lookup("open-ils.cat.biblio.record.xml.import");

    $meth = $self->method_lookup(
        "open-ils.cat.biblio.record.xml.import.override") if $override;

    my ($s) = $meth->run($login, $xml, $source, $oargs);
    return $s;
}



__PACKAGE__->register_method(
    method    => "biblio_record_replace_marc",
    api_name  => "open-ils.cat.biblio.record.xml.update",
    argc      => 3, 
    signature => q/
        Updates the XML for a given biblio record.
        This does not change any other aspect of the record entry
        exception the XML, the editor, and the edit date.
        @return The update record object
    /
);

__PACKAGE__->register_method(
    method    => 'biblio_record_replace_marc',
    api_name  => 'open-ils.cat.biblio.record.marc.replace',
    signature => q/
        @param auth The authtoken
        @param recid The record whose MARC we're replacing
        @param newxml The new xml to use
    /
);

__PACKAGE__->register_method(
    method    => 'biblio_record_replace_marc',
    api_name  => 'open-ils.cat.biblio.record.marc.replace.override',
    signature => q/@see open-ils.cat.biblio.record.marc.replace/
);

sub biblio_record_replace_marc  {
    my( $self, $conn, $auth, $recid, $newxml, $source, $oargs ) = @_;
    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('CREATE_MARC', $e->requestor->ws_ou);

    my $fix_tcn = $self->api_name =~ /replace/o;
    if($self->api_name =~ /override/o) {
        $oargs = { all => 1 } unless defined $oargs;
    } else {
        $oargs = {};
    }

    my $res = OpenILS::Application::Cat::BibCommon->biblio_record_replace_marc(
        $e, $recid, $newxml, $source, $fix_tcn, $oargs);

    $e->commit unless $U->event_code($res);

    #my $ses = OpenSRF::AppSession->create('open-ils.ingest');
    #$ses->request('open-ils.ingest.full.biblio.record', $recid);

    return $res;
}

__PACKAGE__->register_method(
    method    => "template_overlay_biblio_record_entry",
    api_name  => "open-ils.cat.biblio.record_entry.template_overlay",
    stream    => 1,
    signature => q#
        Overlays biblio.record_entry MARC values
        @param auth The authtoken
        @param records The record ids to be updated by the template
        @param template The overlay template
        @return Stream of hashes record id in the key "record" and t or f for the success of the overlay operation in key "success"
    #
);

sub template_overlay_biblio_record_entry {
    my($self, $conn, $auth, $records, $template) = @_;
    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;

    $records = [$records] if (!ref($records));

    for my $rid ( @$records ) {
        my $rec = $e->retrieve_biblio_record_entry($rid);
        next unless $rec;

        unless ($e->allowed('UPDATE_RECORD', $rec->owner, $rec)) {
            $conn->respond({ record => $rid, success => 'f' });
            next;
        }

        my $success = $e->json_query(
            { from => [ 'vandelay.template_overlay_bib_record', $template, $rid ] }
        )->[0]->{'vandelay.template_overlay_bib_record'};

        $conn->respond({ record => $rid, success => $success });
    }

    $e->commit;
    return undef;
}

__PACKAGE__->register_method(
    method    => "template_overlay_container",
    api_name  => "open-ils.cat.container.template_overlay",
    stream    => 1,
    signature => q#
        Overlays biblio.record_entry MARC values
        @param auth The authtoken
        @param container The container, um, containing the records to be updated by the template
        @param template The overlay template, or nothing and the method will look for a negative bib id in the container
        @return Stream of hashes record id in the key "record" and t or f for the success of the overlay operation in key "success"
    #
);

__PACKAGE__->register_method(
    method    => "template_overlay_container",
    api_name  => "open-ils.cat.container.template_overlay.background",
    stream    => 1,
    signature => q#
        Overlays biblio.record_entry MARC values
        @param auth The authtoken
        @param container The container, um, containing the records to be updated by the template
        @param template The overlay template, or nothing and the method will look for a negative bib id in the container
        @return Cache key to check for status of the container overlay
    #
);

sub template_overlay_container {
    my($self, $conn, $auth, $container, $template) = @_;
    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;

    my $actor = OpenSRF::AppSession->create('open-ils.actor') if ($self->api_name =~ /background$/);

    my $items = $e->search_container_biblio_record_entry_bucket_item({ bucket => $container });

    my $titem;
    if (!$template) {
        ($titem) = grep { $_->target_biblio_record_entry < 0 } @$items;
        if (!$titem) {
            $e->rollback;
            return undef;
        }
        $items = [grep { $_->target_biblio_record_entry > 0 } @$items];

        $template = $e->retrieve_biblio_record_entry( $titem->target_biblio_record_entry )->marc;
    }

    my $responses = [];
    my $some_failed = 0;

    $self->respond_complete(
        $actor->request('open-ils.actor.anon_cache.set_value', $auth, res_list => $responses)->gather(1)
    ) if ($actor);

    for my $item ( @$items ) {
        my $rec = $e->retrieve_biblio_record_entry($item->target_biblio_record_entry);
        next unless $rec;

        my $success = 'f';
        if ($e->allowed('UPDATE_RECORD', $rec->owner, $rec)) {
            $success = $e->json_query(
                { from => [ 'vandelay.template_overlay_bib_record', $template, $rec->id ] }
            )->[0]->{'vandelay.template_overlay_bib_record'};
        }

        $some_failed++ if ($success eq 'f');

        if ($actor) {
            push @$responses, { record => $rec->id, success => $success };
            $actor->request('open-ils.actor.anon_cache.set_value', $auth, res_list => $responses);
        } else {
            $conn->respond({ record => $rec->id, success => $success });
        }

        if ($success eq 't') {
            unless ($e->delete_container_biblio_record_entry_bucket_item($item)) {
                $e->rollback;
                if ($actor) {
                    push @$responses, { complete => 1, success => 'f' };
                    $actor->request('open-ils.actor.anon_cache.set_value', $auth, res_list => $responses);
                    return undef;
                } else {
                    return { complete => 1, success => 'f' };
                }
            }
        }
    }

    if ($titem && !$some_failed) {
        return $e->die_event unless ($e->delete_container_biblio_record_entry_bucket_item($titem));
    }

    if ($e->commit) {
        if ($actor) {
            push @$responses, { complete => 1, success => 't' };
            $actor->request('open-ils.actor.anon_cache.set_value', $auth, res_list => $responses);
        } else {
            return { complete => 1, success => 't' };
        }
    } else {
        if ($actor) {
            push @$responses, { complete => 1, success => 'f' };
            $actor->request('open-ils.actor.anon_cache.set_value', $auth, res_list => $responses);
        } else {
            return { complete => 1, success => 'f' };
        }
    }
    return undef;
}

__PACKAGE__->register_method(
    method    => "update_biblio_record_entry",
    api_name  => "open-ils.cat.biblio.record_entry.update",
    signature => q/
        Updates a biblio.record_entry
        @param auth The authtoken
        @param record The record with updated values
        @return 1 on success, Event on error.
    /
);

sub update_biblio_record_entry {
    my($self, $conn, $auth, $record) = @_;
    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('UPDATE_RECORD');
    $e->update_biblio_record_entry($record) or return $e->die_event;
    $e->commit;
    return 1;
}

__PACKAGE__->register_method(
    method    => "undelete_biblio_record_entry",
    api_name  => "open-ils.cat.biblio.record_entry.undelete",
    signature => q/
        Un-deletes a record and sets active=true
        @param auth The authtoken
        @param record The record_id to ressurect
        @return 1 on success, Event on error.
    /
);
sub undelete_biblio_record_entry {
    my($self, $conn, $auth, $record_id) = @_;
    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('UPDATE_RECORD');

    my $record = $e->retrieve_biblio_record_entry($record_id)
        or return $e->die_event;
    $record->deleted('f');
    $record->active('t');

    # Set the leader/05 to indicate that the record has been corrected/revised
    my $marc = $record->marc();
    $marc =~ s{(<leader>.{5}).}{$1c};
    $record->marc($marc);

    # no 2 non-deleted records can have the same tcn_value
    my $existing = $e->search_biblio_record_entry(
        {   deleted => 'f', 
            tcn_value => $record->tcn_value, 
            id => {'!=' => $record_id}
        }, {idlist => 1});
    return OpenILS::Event->new('TCN_EXISTS') if @$existing;

    $e->update_biblio_record_entry($record) or return $e->die_event;
    $e->commit;
    return 1;
}


__PACKAGE__->register_method(
    method    => "biblio_record_xml_import",
    api_name  => "open-ils.cat.biblio.record.xml.import.override",
    signature => q/@see open-ils.cat.biblio.record.xml.import/);

__PACKAGE__->register_method(
    method    => "biblio_record_xml_import",
    api_name  => "open-ils.cat.biblio.record.xml.import",
    notes     => <<"    NOTES");
    Takes a marcxml record and imports the record into the database.  In this
    case, the marcxml record is assumed to be a complete record (i.e. valid
    MARC).  The title control number is taken from (whichever comes first)
    tags 001, 039[ab], 020a, 022a, 010, 035a and whichever does not already exist
    in the database.
    user_session must have IMPORT_MARC permissions
    NOTES


sub biblio_record_xml_import {
    my( $self, $client, $authtoken, $xml, $source, $auto_tcn, $oargs) = @_;
    my $e = new_editor(xact=>1, authtoken=>$authtoken);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('IMPORT_MARC', $e->requestor->ws_ou);

    if ($self->api_name =~ /override/) {
        $oargs = { all => 1 } unless defined $oargs;
    } else {
        $oargs = {};
    }
    my $record = OpenILS::Application::Cat::BibCommon->biblio_record_xml_import(
        $e, $xml, $source, $auto_tcn, $oargs);

    return $record if $U->event_code($record);

    $e->commit;

    #my $ses = OpenSRF::AppSession->create('open-ils.ingest');
    #$ses->request('open-ils.ingest.full.biblio.record', $record->id);

    return $record;
}

__PACKAGE__->register_method(
    method        => "biblio_record_record_metadata",
    api_name      => "open-ils.cat.biblio.record.metadata.retrieve",
    authoritative => 1,
    argc          => 2, #(session_id, list of bre ids )
    notes         => "Returns a list of slim-downed bre objects based on the " .
                     "ids passed in",
);

sub biblio_record_record_metadata {
    my( $self, $client, $authtoken, $ids ) = @_;

    return [] unless $ids and @$ids;

    my $editor = new_editor(authtoken => $authtoken);
    return $editor->event unless $editor->checkauth;
    return $editor->event unless $editor->allowed('VIEW_USER');

    my @results;

    for(@$ids) {
        return $editor->event unless 
            my $rec = $editor->retrieve_biblio_record_entry($_);
        $rec->creator($editor->retrieve_actor_user($rec->creator));
        $rec->editor($editor->retrieve_actor_user($rec->editor));
        $rec->attrs($U->get_bre_attrs([$rec->id], $editor)->{$rec->id});
        $rec->clear_marc; # slim the record down
        push( @results, $rec );
    }

    return \@results;
}



__PACKAGE__->register_method(
    method    => "biblio_record_marc_cn",
    api_name  => "open-ils.cat.biblio.record.marc_cn.retrieve",
    argc      => 1, #(bib id ) 
    signature => {
        desc   => 'Extracts call number candidates from a bibliographic record',
        params => [
            {desc => 'Record ID', type => 'number'},
            {desc => '(Optional) Classification scheme ID', type => 'number'},
        ]
    },
    return => {desc => 'Hash of candidate call numbers identified by tag' }
);

sub biblio_record_marc_cn {
    my( $self, $client, $id, $class ) = @_;

    my $e = new_editor();
    my $marc = $e->retrieve_biblio_record_entry($id)->marc;

    my $doc = XML::LibXML->new->parse_string($marc);
    $doc->documentElement->setNamespace( "http://www.loc.gov/MARC21/slim", "marc", 1 );

    my @fields;
    my @res;
    if ($class) {
        @fields = split(/,/, $e->retrieve_asset_call_number_class($class)->field);
    } else {
        @fields = qw/050ab 055ab 060ab 070ab 080ab 082ab 086ab 088ab 090 092 096 098 099/;
    }

    # Get field/subfield combos based on acnc value; for example "050ab,055ab"

    foreach my $field (@fields) {
        my $tag = substr($field, 0, 3);
        $logger->debug("Tag = $tag");
        my @node = $doc->findnodes("//marc:datafield[\@tag='$tag']");

        # Now parse the subfields and build up the subfield XPath
        my @subfields = split(//, substr($field, 3));

        # If they give us no subfields to parse, default to just the 'a'
        if (!@subfields) {
            @subfields = ('a');
        }
        my $subxpath;
        foreach my $sf (@subfields) {
            $subxpath .= "\@code='$sf' or ";
        }
        $subxpath = substr($subxpath, 0, -4);
        $logger->debug("subxpath = $subxpath");

        # Find the contents of the specified subfields
        foreach my $x (@node) {
            my $cn = $x->findvalue("marc:subfield[$subxpath]");
            push @res, {$tag => $cn} if ($cn);
        }
    }

    return \@res;
}

__PACKAGE__->register_method(
    method    => 'autogen_barcodes',
    api_name  => "open-ils.cat.item.barcode.autogen",
    signature => {
        desc   => 'Returns N generated barcodes following a specified barcode.',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Barcode which the sequence should follow from', type => 'string'},
            {desc => 'Number of barcodes to generate', type => 'number'},
            {desc => 'Options hash.  Currently you can pass in checkdigit : false to disable the use of checkdigits.'}
        ],
        return => {desc => 'Array of generated barcodes'}
    }
);

sub autogen_barcodes {
    my( $self, $client, $auth, $barcode, $num_of_barcodes, $options ) = @_;
    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('UPDATE_COPY', $e->requestor->ws_ou);
    $options ||= {};

    my $barcode_text = '';
    my $barcode_number = 0;

    if ($barcode =~ /^(\D+)/) { $barcode_text = $1; }
    if ($barcode =~ /(\d+)$/) { $barcode_number = $1; }

    my @res;
    for (my $i = 1; $i <= $num_of_barcodes; $i++) {
        my $calculated_barcode;

        # default is to use checkdigits, so looking for an explicit false here
        if (defined $$options{'checkdigit'} && ! $$options{'checkdigit'}) { 
            $calculated_barcode = $barcode_number + $i;
        } else {
            if ($barcode_number =~ /^\d{8}$/) {
                $calculated_barcode = add_codabar_checkdigit($barcode_number + $i, 0);
            } elsif ($barcode_number =~ /^\d{9}$/) {
                $calculated_barcode = add_codabar_checkdigit($barcode_number + $i*10, 1); # strip last digit
            } elsif ($barcode_number =~ /^\d{13}$/) {
                $calculated_barcode = add_codabar_checkdigit($barcode_number + $i, 0);
            } elsif ($barcode_number =~ /^\d{14}$/) {
                $calculated_barcode = add_codabar_checkdigit($barcode_number + $i*10, 1); # strip last digit
            } else {
                $calculated_barcode = $barcode_number + $i;
            }
        }
        push @res, $barcode_text . $calculated_barcode;
    }
    return \@res
}

# Codabar doesn't define a checkdigit algorithm, but this one is typically used by libraries.  gmcharlt++
sub add_codabar_checkdigit {
    my $barcode = shift;
    my $strip_last_digit = shift;

    return $barcode if $barcode =~ /\D/;
    $barcode = substr($barcode, 0, length($barcode)-1) if $strip_last_digit;
    my @digits = split //, $barcode;
    my $total = 0;
    for (my $i = 1; $i < length($barcode); $i+=2) { # for a 13/14 digit barcode, would expect 1,3,5,7,9,11
        $total += $digits[$i];
    }
    for (my $i = 0; $i < length($barcode); $i+=2) { # for a 13/14 digit barcode, would expect 0,2,4,6,8,10,12
        $total += (2 * $digits[$i] >= 10) ? (2 * $digits[$i] - 9) : (2 * $digits[$i]);
    }
    my $remainder = $total % 10;
    my $checkdigit = ($remainder == 0) ? $remainder : 10 - $remainder;
    return $barcode . $checkdigit;
}

__PACKAGE__->register_method(
    method        => "orgs_for_title",
    authoritative => 1,
    api_name      => "open-ils.cat.actor.org_unit.retrieve_by_title"
);

sub orgs_for_title {
    my( $self, $client, $record_id ) = @_;

    my $vols = $U->simple_scalar_request(
        "open-ils.cstore",
        "open-ils.cstore.direct.asset.call_number.search.atomic",
        { record => $record_id, deleted => 'f' });

    my $orgs = { map {$_->owning_lib => 1 } @$vols };
    return [ keys %$orgs ];
}


__PACKAGE__->register_method(
    method        => "retrieve_copies",
    authoritative => 1,
    api_name      => "open-ils.cat.asset.copy_tree.retrieve");

__PACKAGE__->register_method(
    method   => "retrieve_copies",
    api_name => "open-ils.cat.asset.copy_tree.global.retrieve");

# user_session may be null/undef
sub retrieve_copies {

    my( $self, $client, $user_session, $docid, @org_ids ) = @_;

    if(ref($org_ids[0])) { @org_ids = @{$org_ids[0]}; }

    $docid = "$docid";

    # grabbing copy trees should be available for everyone..
    if(!@org_ids and $user_session) {
        my($user_obj, $evt) = OpenILS::Application::AppUtils->checkses($user_session); 
        return $evt if $evt;
        @org_ids = ($user_obj->home_ou);
    }

    if( $self->api_name =~ /global/ ) {
        return _build_volume_list( { record => $docid, deleted => 'f', label => { '<>' => '##URI##' } } );

    } else {

        my @all_vols;
        for my $orgid (@org_ids) {
            my $vols = _build_volume_list( 
                    { record => $docid, owning_lib => $orgid, deleted => 'f', label => { '<>' => '##URI##' } } );
            push( @all_vols, @$vols );
        }
        
        return \@all_vols;
    }

    return undef;
}


sub _build_volume_list {
    my $search_hash = shift;

    $search_hash->{deleted} = 'f';
    my $e = new_editor();

    my $vols = $e->search_asset_call_number([
        $search_hash,
        {
            flesh => 1,
            flesh_fields => { acn => ['prefix','suffix','label_class'] },
            'order_by' => { 'acn' => 'oils_text_as_bytea(label_sortkey), oils_text_as_bytea(label), id, owning_lib' }
        }
    ]);

    my @volumes;

    for my $volume (@$vols) {

        my $copies = $e->search_asset_copy([
            { call_number => $volume->id , deleted => 'f' },
            { flesh => 1, flesh_fields => { acp => ['stat_cat_entries','parts'] } }
        ]);

        $copies = [ sort { $a->barcode cmp $b->barcode } @$copies  ];

        for my $c (@$copies) {
            if( $c->status == OILS_COPY_STATUS_CHECKED_OUT ) {
                $c->circulations(
                    $e->search_action_circulation(
                        [
                            { target_copy => $c->id },
                            {
                                order_by => { circ => 'xact_start desc' },
                                limit => 1
                            }
                        ]
                    )
                )
            }
        }

        $volume->copies($copies);
        push( @volumes, $volume );
    }

    #$session->disconnect();
    return \@volumes;

}


__PACKAGE__->register_method(
    method   => "fleshed_copy_update",
    api_name => "open-ils.cat.asset.copy.fleshed.batch.update",);

__PACKAGE__->register_method(
    method   => "fleshed_copy_update",
    api_name => "open-ils.cat.asset.copy.fleshed.batch.update.override",);


sub fleshed_copy_update {
    my( $self, $conn, $auth, $copies, $delete_stats, $oargs ) = @_;
    return 1 unless ref $copies;
    my( $reqr, $evt ) = $U->checkses($auth);
    return $evt if $evt;
    my $editor = new_editor(requestor => $reqr, xact => 1);
    if ($self->api_name =~ /override/) {
        $oargs = { all => 1 } unless defined $oargs;
    } else {
        $oargs = {};
    }
    my $retarget_holds = [];
    $evt = OpenILS::Application::Cat::AssetCommon->update_fleshed_copies(
        $editor, $oargs, undef, $copies, $delete_stats, $retarget_holds, undef);

    if( $evt ) { 
        $logger->info("fleshed copy update failed with event: ".OpenSRF::Utils::JSON->perl2JSON($evt));
        $editor->rollback; 
        return $evt; 
    }

    $editor->commit;
    $logger->info("fleshed copy update successfully updated ".scalar(@$copies)." copies");
    reset_hold_list($auth, $retarget_holds);

    return 1;
}

sub reset_hold_list {
    my($auth, $hold_ids) = @_;
    return unless @$hold_ids;
    $logger->info("reseting holds after copy status change: @$hold_ids");
    my $ses = OpenSRF::AppSession->create('open-ils.circ');
    $ses->request('open-ils.circ.hold.reset.batch', $auth, $hold_ids);
}


__PACKAGE__->register_method(
    method    => 'in_db_merge',
    api_name  => 'open-ils.cat.biblio.records.merge',
    signature => q/
        Merges a group of records
        @param auth The login session key
        @param master The id of the record all other records should be merged into
        @param records Array of records to be merged into the master record
        @return 1 on success, Event on error.
    /
);

sub in_db_merge {
    my( $self, $conn, $auth, $master, $records ) = @_;

    my $editor = new_editor( authtoken => $auth, xact => 1 );
    return $editor->die_event unless $editor->checkauth;
    return $editor->die_event unless $editor->allowed('MERGE_BIB_RECORDS'); # TODO see below about record ownership

    my $count = 0;
    for my $source ( @$records ) {
        #XXX we actually /will/ want to check perms for master and sources after record ownership exists

        # This stored proc (asset.merge_record_assets(target,source)) has the side effects of
        # moving call_number, title-type (and some volume-type) hold_request and uri-mapping
        # objects from the source record to the target record, so must be called from within
        # a transaction.

        $count += $editor->json_query({
            select => {
                bre => [{
                    alias => 'count',
                    transform => 'asset.merge_record_assets',
                    column => 'id',
                    params => [$source]
                }]
            },
            from   => 'bre',
            where  => { id => $master }
        })->[0]->{count}; # count of objects moved, of all types

    }

    $editor->commit;
    return $count;
}

__PACKAGE__->register_method(
    method    => 'in_db_auth_merge',
    api_name  => 'open-ils.cat.authority.records.merge',
    signature => q/
        Merges a group of authority records
        @param auth The login session key
        @param master The id of the record all other records should be merged into
        @param records Array of records to be merged into the master record
        @return 1 on success, Event on error.
    /
);

sub in_db_auth_merge {
    my( $self, $conn, $auth, $master, $records ) = @_;

    my $editor = new_editor( authtoken => $auth, xact => 1 );
    return $editor->die_event unless $editor->checkauth;
    return $editor->die_event unless $editor->allowed('MERGE_AUTH_RECORDS'); # TODO see below about record ownership

    my $count = 0;
    for my $source ( @$records ) {
        $count += $editor->json_query({
            select => {
                are => [{
                    alias => 'count',
                    transform => 'authority.merge_records',
                    column => 'id',
                    params => [$source]
                }]
            },
            from   => 'are',
            where  => { id => $master }
        })->[0]->{count}; # count of objects moved, of all types
    }

    $editor->commit;
    return $count;
}

__PACKAGE__->register_method(
    method   => "fleshed_volume_update",
    api_name => "open-ils.cat.asset.volume.fleshed.batch.update",);

__PACKAGE__->register_method(
    method   => "fleshed_volume_update",
    api_name => "open-ils.cat.asset.volume.fleshed.batch.update.override",);

sub fleshed_volume_update {
    my( $self, $conn, $auth, $volumes, $delete_stats, $options, $oargs ) = @_;
    my( $reqr, $evt ) = $U->checkses($auth);
    return $evt if $evt;
    $options ||= {};

    if ($self->api_name =~ /override/) {
        $oargs = { all => 1 } unless defined $oargs;
    } else {
        $oargs = {};
    }
    my $editor = new_editor( requestor => $reqr, xact => 1 );
    my $retarget_holds = [];
    my $auto_merge_vols = $options->{auto_merge_vols};

    for my $vol (@$volumes) {
        $logger->info("vol-update: investigating volume ".$vol->id);

        $vol->editor($reqr->id);
        $vol->edit_date('now');

        my $copies = $vol->copies;
        $vol->clear_copies;

        $vol->editor($editor->requestor->id);
        $vol->edit_date('now');

        if( $vol->isdeleted ) {

            $logger->info("vol-update: deleting volume");
            return $editor->die_event unless
                $editor->allowed('UPDATE_VOLUME', $vol->owning_lib);

            if(my $evt = $assetcom->delete_volume($editor, $vol, $oargs, $$options{force_delete_copies})) {
                $editor->rollback;
                return $evt;
            }

            return $editor->die_event unless
                $editor->update_asset_call_number($vol);

        } elsif( $vol->isnew ) {
            $logger->info("vol-update: creating volume");
            $evt = $assetcom->create_volume( $oargs, $editor, $vol );
            return $evt if $evt;

        } elsif( $vol->ischanged ) {
            $logger->info("vol-update: update volume");
            my $resp = update_volume($vol, $editor, ($oargs->{all} or grep { $_ eq 'VOLUME_LABEL_EXISTS' } @{$oargs->{events}} or $auto_merge_vols));
            return $resp->{evt} if $resp->{evt};
            $vol = $resp->{merge_vol};
        }

        # now update any attached copies
        if( $copies and @$copies and !$vol->isdeleted ) {
            $_->call_number($vol->id) for @$copies;
            $evt = $assetcom->update_fleshed_copies(
                $editor, $oargs, $vol, $copies, $delete_stats, $retarget_holds, undef);
            return $evt if $evt;
        }
    }

    $editor->finish;
    reset_hold_list($auth, $retarget_holds);
    return scalar(@$volumes);
}


sub update_volume {
    my $vol = shift;
    my $editor = shift;
    my $auto_merge = shift;
    my $evt;
    my $merge_vol;

    return {evt => $editor->event} unless
        $editor->allowed('UPDATE_VOLUME', $vol->owning_lib);

    return {evt => $evt} 
        if ( $evt = OpenILS::Application::Cat::AssetCommon->org_cannot_have_vols($editor, $vol->owning_lib) );

    my $vols = $editor->search_asset_call_number({ 
        owning_lib => $vol->owning_lib,
        record     => $vol->record,
        label      => $vol->label,
        prefix     => $vol->prefix,
        suffix     => $vol->suffix,
        deleted    => 'f',
        id         => {'!=' => $vol->id}
    });

    if(@$vols) {

        if($auto_merge) {

            # If the auto-merge option is on, merge our updated volume into the existing
            # volume with the same record + owner + label.
            ($merge_vol, $evt) = OpenILS::Application::Cat::Merge::merge_volumes($editor, [$vol], $vols->[0]);
            return {evt => $evt, merge_vol => $merge_vol};

        } else {
            return {evt => OpenILS::Event->new('VOLUME_LABEL_EXISTS', payload => $vol->id)};
        }
    }

    return {evt => $editor->die_event} unless $editor->update_asset_call_number($vol);
    return {};
}



__PACKAGE__->register_method (
    method   => 'delete_bib_record',
    api_name => 'open-ils.cat.biblio.record_entry.delete');

sub delete_bib_record {
    my($self, $conn, $auth, $rec_id) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('DELETE_RECORD', $e->requestor->ws_ou);
    my $vols = $e->search_asset_call_number({record=>$rec_id, deleted=>'f'});
    return OpenILS::Event->new('RECORD_NOT_EMPTY', payload=>$rec_id) if @$vols;
    my $evt = OpenILS::Application::Cat::BibCommon->delete_rec($e, $rec_id);
    if($evt) { $e->rollback; return $evt; }   
    $e->commit;
    return 1;
}



__PACKAGE__->register_method (
    method   => 'batch_volume_transfer',
    api_name => 'open-ils.cat.asset.volume.batch.transfer',
);

__PACKAGE__->register_method (
    method   => 'batch_volume_transfer',
    api_name => 'open-ils.cat.asset.volume.batch.transfer.override',
);


sub batch_volume_transfer {
    my( $self, $conn, $auth, $args, $oargs ) = @_;

    my $evt;
    my $rec     = $$args{docid};
    my $o_lib   = $$args{lib};
    my $vol_ids = $$args{volumes};

    my $override = 1 if $self->api_name =~ /override/;
    $oargs = { all => 1 } unless defined $oargs;

    $logger->info("merge: transferring volumes to lib=$o_lib and record=$rec");

    my $e = new_editor(authtoken => $auth, xact =>1);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('UPDATE_VOLUME', $o_lib);

    my $dorg = $e->retrieve_actor_org_unit($o_lib)
        or return $e->event;

    my $ou_type = $e->retrieve_actor_org_unit_type($dorg->ou_type)
        or return $e->event;

    return $evt if ( $evt = OpenILS::Application::Cat::AssetCommon->org_cannot_have_vols($e, $o_lib) );

    my $vols = $e->batch_retrieve_asset_call_number($vol_ids);
    my @seen;

   my @rec_ids;

    for my $vol (@$vols) {

        # if we've already looked at this volume, go to the next
        next if !$vol or grep { $vol->id == $_ } @seen;

        # grab all of the volumes in the list that have 
        # the same label so they can be merged
        my @all = grep { $_->label eq $vol->label } @$vols;

        # take note of the fact that we've looked at this set of volumes
        push( @seen, $_->id ) for @all;
        push( @rec_ids, $_->record ) for @all;

        # for each volume, see if there are any copies that have a 
        # remote circ_lib (circ_lib != vol->owning_lib and != $o_lib ).  
        # if so, warn them
        unless( $override && ($oargs->{all} || grep { $_ eq 'COPY_REMOTE_CIRC_LIB' } @{$oargs->{events}}) ) {
            for my $v (@all) {

                $logger->debug("merge: searching for copies with remote circ_lib for volume ".$v->id);
                my $args = { 
                    call_number => $v->id, 
                    circ_lib    => { "not in" => [ $o_lib, $v->owning_lib ] },
                    deleted     => 'f'
                };

                my $copies = $e->search_asset_copy($args, {idlist=>1});

                # if the copy's circ_lib matches the destination lib,
                # that's ok too
                return OpenILS::Event->new('COPY_REMOTE_CIRC_LIB') if @$copies;
            }
        }

        # see if there is a volume at the destination lib that 
        # already has the requested label
        my $existing_vol = $e->search_asset_call_number(
            {
                label      => $vol->label, 
                prefix     => $vol->prefix, 
                suffix     => $vol->suffix, 
                record     => $rec, 
                owning_lib => $o_lib,
                deleted    => 'f'
            }
        )->[0];

        if( $existing_vol ) {

            if( grep { $_->id == $existing_vol->id } @all ) {
                # this volume is already accounted for in our list of volumes to merge
                $existing_vol = undef;

            } else {
                # this volume exists on the destination record/owning_lib and must
                # be used as the destination for merging
                $logger->debug("merge: volume already exists at destination record: ".
                    $existing_vol->id.' : '.$existing_vol->label) if $existing_vol;
            }
        } 

        if( @all > 1 || $existing_vol ) {
            $logger->info("merge: found collisions in volume transfer");
            my @args = ($e, \@all);
            @args = ($e, \@all, $existing_vol) if $existing_vol;
            ($vol, $evt) = OpenILS::Application::Cat::Merge::merge_volumes(@args);
            return $evt if $evt;
        } 
        
        if( !$existing_vol ) {

            $vol->owning_lib($o_lib);
            $vol->record($rec);
            $vol->editor($e->requestor->id);
            $vol->edit_date('now');
    
            $logger->info("merge: updating volume ".$vol->id);
            $e->update_asset_call_number($vol) or return $e->event;

        } else {
            $logger->info("merge: bypassing volume update because existing volume used as target");
        }

        # regardless of what volume was used as the destination, 
        # update any copies that have moved over to the new lib
        my $copies = $e->search_asset_copy({call_number=>$vol->id, deleted => 'f'});

        # update circ lib on the copies - make this a method flag?
        for my $copy (@$copies) {
            next if $copy->circ_lib == $o_lib;
            $logger->info("merge: transfer moving circ lib on copy ".$copy->id);
            $copy->circ_lib($o_lib);
            $copy->editor($e->requestor->id);
            $copy->edit_date('now');
            $e->update_asset_copy($copy) or return $e->event;
        }

        # Now see if any empty records need to be deleted after all of this

        for(@rec_ids) {
            $logger->debug("merge: seeing if we should delete record $_...");
            $evt = OpenILS::Application::Cat::BibCommon->delete_rec($e, $_) 
                if OpenILS::Application::Cat::BibCommon->title_is_empty($e, $_);
            return $evt if $evt;
        }
    }

    $logger->info("merge: transfer succeeded");
    $e->commit;
    return 1;
}




__PACKAGE__->register_method(
    api_name => 'open-ils.cat.call_number.find_or_create',
    method   => 'find_or_create_volume',
);

sub find_or_create_volume {
    my( $self, $conn, $auth, $label, $record_id, $org_id, $prefix, $suffix, $label_class ) = @_;
    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;
    my ($vol, $evt, $exists) = 
        OpenILS::Application::Cat::AssetCommon->find_or_create_volume($e, $label, $record_id, $org_id, $prefix, $suffix, $label_class);
    return $evt if $evt;
    $e->rollback if $exists;
    $e->commit if $vol;
    return { 'acn_id' => $vol->id, 'existed' => $exists };
}


__PACKAGE__->register_method(
    method    => "create_serial_record_xml",
    api_name  => "open-ils.cat.serial.record.xml.create.override",
    signature => q/@see open-ils.cat.serial.record.xml.create/);

__PACKAGE__->register_method(
    method    => "create_serial_record_xml",
    api_name  => "open-ils.cat.serial.record.xml.create",
    signature => q/
        Inserts a new serial record with the given XML
    /
);

sub create_serial_record_xml {
    my( $self, $client, $login, $source, $owning_lib, $record_id, $xml, $oargs ) = @_;

    my $override = 1 if $self->api_name =~ /override/; # not currently used
    $oargs = { all => 1 } unless defined $oargs; # Not currently used, but here for consistency.

    my $e = new_editor(xact=>1, authtoken=>$login);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('CREATE_MFHD_RECORD', $owning_lib);

    # Auto-populate the location field of a placeholder MFHD record with the library name
    my $aou = $e->retrieve_actor_org_unit($owning_lib) or return $e->die_event;

    my $mfhd = Fieldmapper::serial::record_entry->new;

    $mfhd->source($source) if $source;
    $mfhd->record($record_id);
    $mfhd->creator($e->requestor->id);
    $mfhd->editor($e->requestor->id);
    $mfhd->create_date('now');
    $mfhd->edit_date('now');
    $mfhd->owning_lib($owning_lib);

    # If the caller did not pass in MFHD XML, create a placeholder record.
    # The placeholder will only contain the name of the owning library.
    # The goal is to generate common patterns for the caller in the UI that
    # then get passed in here.
    if (!$xml) {
        my $aou_name = $aou->name;
        $xml = <<HERE;
<record 
 xsi:schemaLocation="http://www.loc.gov/MARC21/slim http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd"
 xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
 xmlns="http://www.loc.gov/MARC21/slim">
<leader>00307ny  a22001094  4500</leader>
<controlfield tag="001">42153</controlfield>
<controlfield tag="005">20090601182414.0</controlfield>
<controlfield tag="004">$record_id</controlfield>
<controlfield tag="008">      4u####8###l# 4   uueng1      </controlfield>
<datafield tag="852" ind1=" " ind2=" "> <subfield code="b">$aou_name</subfield></datafield>
</record>
HERE
    }
    my $marcxml = XML::LibXML->new->parse_string($xml);
    $marcxml->documentElement->setNamespace("http://www.loc.gov/MARC21/slim", "marc", 1 );
    $marcxml->documentElement->setNamespace("http://www.loc.gov/MARC21/slim");

    $mfhd->marc($U->entityize($marcxml->documentElement->toString));

    $e->create_serial_record_entry($mfhd) or return $e->die_event;

    $e->commit;
    return $mfhd->id;
}

__PACKAGE__->register_method(
    method   => "create_update_asset_copy_template",
    api_name => "open-ils.cat.asset.copy_template.create_or_update"
);

sub create_update_asset_copy_template {
    my ($self, $client, $authtoken, $act) = @_;

    my $e = new_editor("xact" => 1, "authtoken" => $authtoken);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed(
        "ADMIN_ASSET_COPY_TEMPLATE", $act->owning_lib
    );

    $act->editor($e->requestor->id);
    $act->edit_date("now");

    my $retval;
    if (!$act->id) {
        $act->creator($e->requestor->id);
        $act->create_date("now");

        $e->create_asset_copy_template($act) or return $e->die_event;
        $retval = $e->data;
    } else {
        $e->update_asset_copy_template($act) or return $e->die_event;
        $retval = $e->retrieve_asset_copy_template($e->data);
    }
    $e->commit and return $retval;
}

__PACKAGE__->register_method(
    method      => "acn_sms_msg",
    api_name    => "open-ils.cat.acn.send_sms_text",
    signature   => q^
        Send an SMS text from an A/T template for specified call numbers.

        First parameter is null or an auth token (whether a null is allowed
        depends on the sms.disable_authentication_requirement.callnumbers OU
        setting).

        Second parameter is the id of the context org.

        Third parameter is the code of the SMS carrier from the
        config.sms_carrier table.

        Fourth parameter is the SMS number.

        Fifth parameter is the ACN id's to target, though currently only the
        first ACN is used by the template (and the UI is only sending one).
    ^
);

sub acn_sms_msg {
    my($self, $conn, $auth, $org_id, $carrier, $number, $target_ids) = @_;

    my $sms_enable = $U->ou_ancestor_setting_value(
        $org_id || $U->fetch_org_tree->id,
        'sms.enable'
    );
    # We could maybe make a Validator for this on the templates
    if (! $U->is_true($sms_enable)) {
        return -1;
    }

    my $disable_auth = $U->ou_ancestor_setting_value(
        $org_id || $U->fetch_org_tree->id,
        'sms.disable_authentication_requirement.callnumbers'
    );

    my $e = new_editor(
        (defined $auth)
        ? (authtoken => $auth, xact => 1)
        : (xact => 1)
    );
    return $e->event unless $disable_auth || $e->checkauth;

    my $targets = $e->batch_retrieve_asset_call_number($target_ids);

    $e->rollback; # FIXME using transaction because of pgpool/slony setups, but not
                  # simply making this method authoritative because of weirdness
                  # with transaction handling in A/T code that causes rollback
                  # failure down the line if handling many targets

    return undef unless @$targets;
    return $U->fire_object_event(
        undef,                    # event_def
        'acn.format.sms_text',    # hook
        $targets,
        $org_id,
        undef,                    # granularity
        {                         # user_data
            sms_carrier => $carrier,
            sms_notify => $number
        }
    );
}



1;

# vi:et:ts=4:sw=4
