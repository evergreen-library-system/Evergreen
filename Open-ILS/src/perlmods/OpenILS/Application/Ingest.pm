package OpenILS::Application::Ingest;
use OpenILS::Application;
use base qw/OpenILS::Application/;

use Unicode::Normalize;
use OpenSRF::EX qw/:try/;

use OpenSRF::AppSession;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Logger qw/:level/;

use OpenILS::Utils::ScriptRunner;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::JSON;

use OpenILS::Utils::Fieldmapper;

use XML::LibXML;
use XML::LibXSLT;
use Time::HiRes qw(time);

our %supported_formats = (
	mods32	=> {ns => 'http://www.loc.gov/mods/v3'},
	mods3	=> {ns => 'http://www.loc.gov/mods/v3'},
	mods	=> {ns => 'http://www.loc.gov/mods/'},
	marcxml	=> {ns => 'http://www.loc.gov/MARC21/slim'},
	srw_dc	=> {ns => 'info:srw/schema/1/dc-schema'},
	oai_dc	=> {ns => 'http://www.openarchives.org/OAI/2.0/oai_dc/'},
	rdf_dc	=> {ns => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#'},
	atom	=> {ns => 'http://www.w3.org/2005/Atom'},
	rss091	=> {ns => 'http://my.netscape.com/rdf/simple/0.9/'},
	rss092	=> {ns => ''},
	rss093	=> {ns => ''},
	rss094	=> {ns => ''},
	rss10	=> {ns => 'http://purl.org/rss/1.0/'},
	rss11	=> {ns => 'http://purl.org/net/rss1.1#'},
	rss2	=> {ns => ''},
);


my $log = 'OpenSRF::Utils::Logger';

my  $parser = XML::LibXML->new();
my  $xslt = XML::LibXSLT->new();

my  $mods_sheet;
my  $mads_sheet;
my  $xpathset = {};
sub initialize {}
sub child_init {}

sub post_init {

	unless (keys %$xpathset) {
		$log->debug("Running post_init", DEBUG);

		my $xsldir = OpenSRF::Utils::SettingsClient->new->config_value(dirs => 'xsl');

		unless ($supported_formats{mods}{xslt}) {
			$log->debug("Loading MODS XSLT", DEBUG);
	 		my $xslt_doc = $parser->parse_file( $xsldir . "/MARC21slim2MODS.xsl");
			$supported_formats{mods}{xslt} = $xslt->parse_stylesheet( $xslt_doc );
		}

		unless ($supported_formats{mods3}{xslt}) {
			$log->debug("Loading MODS v3 XSLT", DEBUG);
	 		my $xslt_doc = $parser->parse_file( $xsldir . "/MARC21slim2MODS3.xsl");
			$supported_formats{mods3}{xslt} = $xslt->parse_stylesheet( $xslt_doc );
		}

		unless ($supported_formats{mods32}{xslt}) {
			$log->debug("Loading MODS v32 XSLT", DEBUG);
	 		my $xslt_doc = $parser->parse_file( $xsldir . "/MARC21slim2MODS32.xsl");
			$supported_formats{mods32}{xslt} = $xslt->parse_stylesheet( $xslt_doc );
		}

		my $req = OpenSRF::AppSession
				->create('open-ils.cstore')
				
				# XXX testing new metabib field use for faceting
				#->request( 'open-ils.cstore.direct.config.metabib_field.search.atomic', { id => { '!=' => undef } } )
				->request( 'open-ils.cstore.direct.config.metabib_field.search.atomic', { search_field => 't' } )

				->gather(1);

		if (ref $req and @$req) {
			for my $f (@$req) {
				$xpathset->{ $f->field_class }->{ $f->name }->{xpath} = $f->xpath;
				$xpathset->{ $f->field_class }->{ $f->name }->{id} = $f->id;
				$xpathset->{ $f->field_class }->{ $f->name }->{format} = $f->format;
				$log->debug("Loaded XPath from DB: ".$f->field_class." => ".$f->name." : ".$f->xpath, DEBUG);
			}
		}
	}
}

sub entityize {
	my $stuff = shift;
	my $form = shift;

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

package OpenILS::Application::Ingest::Biblio;
use base qw/OpenILS::Application::Ingest/;
use Unicode::Normalize;

sub rw_biblio_ingest_single_object {
	my $self = shift;
	my $client = shift;
	my $bib = shift;

	my ($blob) = $self->method_lookup("open-ils.ingest.full.biblio.object.readonly")->run($bib);
	return undef unless ($blob);

	$bib->fingerprint( $blob->{fingerprint}->{fingerprint} );
	$bib->quality( $blob->{fingerprint}->{quality} );

	my $cstore = OpenSRF::AppSession->connect('open-ils.cstore');

	my $xact = $cstore->request('open-ils.cstore.transaction.begin')->gather(1);
    my $tmp;

	# update uri stuff ...

    # gather URI call numbers for this record
    my $uri_cns = $u->{call_number} = $cstore->request(
        'open-ils.cstore.direct.asset.call_number.id_list.atomic' => { record => $bib->id, label => '##URI##' }
    )->gather(1);

    # gather the maps for those call numbers
    my $uri_maps = $u->{call_number} = $cstore->request(
        'open-ils.cstore.direct.asset.uri_call_number_map.id_list.atomic' => { call_number => $uri_cns }
    )->gather(1);

    # delete the old maps
    $cstore->request( 'open-ils.cstore.direct.asset.uri_call_number_map.delete' => $_ )->gather(1) for (@$uri_maps);

    # and delete the call numbers if there are no more URIs
    if (!@{ $blob->{uri} }) {
        $cstore->request( 'open-ils.cstore.direct.asset.call_number.delete' => $_ )->gather(1) for (@$uri_cns);
    }

    # now, add CNs, URIs and maps
    my %new_cns_by_owner;
    my %new_uris_by_owner;
    for my $u ( @{ $blob->{uri} } ) {

        my $owner = $u->{call_number}->owning_lib;

        if ($u->{call_number}->isnew) {
            if ($new_cns_by_owner{$owner}) {
                $u->{call_number} = $new_cns_by_owner{$owner};
            } else {
                $u->{call_number}->clear_id;
    	        $u->{call_number} = $new_cns_by_owner{$owner} = $cstore->request(
                    'open-ils.cstore.direct.asset.call_number.create' => $u->{call_number}
                )->gather(1);
            }
        }

        if ($u->{uri}->isnew) {
            if ($new_uris_by_owner{$owner}) {
	            $u->{uri} = $new_uris_by_owner{$owner};
            } else {
	            $u->{uri} = $new_uris_by_owner{$owner} = $cstore->request(
                    'open-ils.cstore.direct.asset.uri.create' => $u->{uri}
                )->gather(1);
            }
        }

        my $umap = Fieldmapper::asset::uri_call_number_map->new;
        $umap->uri($u->{uri}->id);
        $umap->call_number($u->{call_number}->id);

	    $cstore->request( 'open-ils.cstore.direct.asset.uri_call_number_map.create' => $umap )->gather(1) if (!$tmp);
    }

	# update full_rec stuff ...
	$tmp = $cstore->request(
		'open-ils.cstore.direct.metabib.full_rec.id_list.atomic',
		{ record => $bib->id }
	)->gather(1);

	$cstore->request( 'open-ils.cstore.direct.metabib.full_rec.delete' => $_ )->gather(1) for (@$tmp);
	$cstore->request( 'open-ils.cstore.direct.metabib.full_rec.create' => $_ )->gather(1) for (@{ $blob->{full_rec} });

	# update rec_descriptor stuff ...
	$tmp = $cstore->request(
		'open-ils.cstore.direct.metabib.record_descriptor.id_list.atomic',
		{ record => $bib->id }
	)->gather(1);

	$cstore->request( 'open-ils.cstore.direct.metabib.record_descriptor.delete' => $_ )->gather(1) for (@$tmp);
	$cstore->request( 'open-ils.cstore.direct.metabib.record_descriptor.create' => $blob->{descriptor} )->gather(1);

	# deal with classed fields...
	for my $class ( qw/title author subject keyword series/ ) {
		$tmp = $cstore->request(
			"open-ils.cstore.direct.metabib.${class}_field_entry.id_list.atomic",
			{ source => $bib->id }
		)->gather(1);

		$cstore->request( "open-ils.cstore.direct.metabib.${class}_field_entry.delete" => $_ )->gather(1) for (@$tmp);
	}
	for my $obj ( @{ $blob->{field_entries} } ) {
		my $class = $obj->class_name;
		$class =~ s/^Fieldmapper:://o;
		$class =~ s/::/./go;
		$cstore->request( "open-ils.cstore.direct.$class.create" => $obj )->gather(1);
	}

	# update MR map ...

	$tmp = $cstore->request(
		'open-ils.cstore.direct.metabib.metarecord_source_map.search.atomic',
		{ source => $bib->id }
	)->gather(1);

	$cstore->request( 'open-ils.cstore.direct.metabib.metarecord_source_map.delete' => $_->id )->gather(1) for (@$tmp);

	# get the old MRs
	my $old_mrs = $cstore->request(
		'open-ils.cstore.direct.metabib.metarecord.search.atomic' => { id => [map { $_->metarecord } @$tmp] }
	)->gather(1) if (@$tmp);

	$old_mrs = [] if (!ref($old_mrs));

	my $mr;
	for my $m (@$old_mrs) {
		if ($m->fingerprint eq $bib->fingerprint) {
			$mr = $m;
		} else {
			my $others = $cstore->request(
				'open-ils.cstore.direct.metabib.metarecord_source_map.id_list.atomic' => { metarecord => $m->id }
			)->gather(1);

			if (!@$others) {
				$cstore->request(
					'open-ils.cstore.direct.metabib.metarecord.delete' => $m->id
				)->gather(1);
			}

			$m->isdeleted(1);
		}
	}

	my $holds;
	if (!$mr) {
		# Get the matchin MR, if any.
		$mr = $cstore->request(
			'open-ils.cstore.direct.metabib.metarecord.search',
			{ fingerprint => $bib->fingerprint }
		)->gather(1);

		$holds = $cstore->request(
			'open-ils.cstore.direct.action.hold_request.search.atomic',
			{ hold_type => 'M', target => [ map { $_->id } grep { $_->isdeleted } @$old_mrs ] }
		)->gather(1) if (@$old_mrs);

		if ($mr) {
			for my $h (@$holds) {
				$h->target($mr);
				$cstore->request( 'open-ils.cstore.direct.action.hold_request.update' => $h )->gather(1);
				$h->ischanged(1);
			}
		}
	}

	if (!$mr) {
		$mr = new Fieldmapper::metabib::metarecord;
		$mr->fingerprint( $bib->fingerprint );
		$mr->master_record( $bib->id );
		$mr->id(
			$cstore->request(
				"open-ils.cstore.direct.metabib.metarecord.create",
				$mr => { quiet => 'true' }
			)->gather(1)
		);

		for my $h (grep { !$_->ischanged } @$holds) {
			$h->target($mr);
			$cstore->request( 'open-ils.cstore.direct.action.hold_request.update' => $h )->gather(1);
		}
	} else {
		my $mrm = $cstore->request(
			'open-ils.cstore.direct.metabib.metarecord_source_map.search.atomic',
			{ metarecord => $mr->id }
		)->gather(1);

		if (@$mrm) {
			my $best = $cstore->request(
				"open-ils.cstore.direct.biblio.record_entry.search",
				{ id => [ map { $_->source } @$mrm ] },
				{ 'select'	=> { bre => [ qw/id quality/ ] },
			  	order_by	=> { bre => "quality desc" },
			  	limit		=> 1,
				}
			)->gather(1);

			if ($best->quality > $bib->quality) {
				$mr->master_record($best->id);
			} else {
				$mr->master_record($bib->id);
			}
		} else {
			$mr->master_record($bib->id);
		}

		$mr->clear_mods;

		$cstore->request( 'open-ils.cstore.direct.metabib.metarecord.update' => $mr )->gather(1);
	}

	my $mrm = new Fieldmapper::metabib::metarecord_source_map;
	$mrm->source($bib->id);
	$mrm->metarecord($mr->id);

	$cstore->request( 'open-ils.cstore.direct.metabib.metarecord_source_map.create' => $mrm )->gather(1);
	$cstore->request( 'open-ils.cstore.direct.biblio.record_entry.update' => $bib )->gather(1);

	$cstore->request( 'open-ils.cstore.transaction.commit' )->gather(1) || return undef;;
    $cstore->disconnect;

	return $bib->id;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.full.biblio.object",
	method		=> "rw_biblio_ingest_single_object",
	api_level	=> 1,
	argc		=> 1,
);                      

sub rw_biblio_ingest_single_record {
	my $self = shift;
	my $client = shift;
	my $rec = shift;

	OpenILS::Application::Ingest->post_init();
	my $cstore = OpenSRF::AppSession->connect( 'open-ils.cstore' );
	$cstore->request('open-ils.cstore.transaction.begin')->gather(1);

	my $r = $cstore->request( 'open-ils.cstore.direct.biblio.record_entry.retrieve' => $rec )->gather(1);

	$cstore->request('open-ils.cstore.transaction.rollback')->gather(1);
	$cstore->disconnect;

	return undef unless ($r and @$r);

	return ($self->method_lookup("open-ils.ingest.full.biblio.object")->run($r))[0];
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.full.biblio.record",
	method		=> "rw_biblio_ingest_single_record",
	api_level	=> 1,
	argc		=> 1,
);                      

sub rw_biblio_ingest_record_list {
	my $self = shift;
	my $client = shift;
	my @rec = ref($_[0]) ? @{ $_[0] } : @_ ;

	OpenILS::Application::Ingest->post_init();
	my $cstore = OpenSRF::AppSession->connect( 'open-ils.cstore' );
	$cstore->request('open-ils.cstore.transaction.begin')->gather(1);

	my $r = $cstore->request( 'open-ils.cstore.direct.biblio.record_entry.search.atomic' => { id => $rec } )->gather(1);

	$cstore->request('open-ils.cstore.transaction.rollback')->gather(1);
	$cstore->disconnect;

	return undef unless ($r and @$r);

	my $count = 0;
	$count += ($self->method_lookup("open-ils.ingest.full.biblio.object")->run($_))[0] for (@$r);

	return $count;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.full.biblio.record_list",
	method		=> "rw_biblio_ingest_record_list",
	api_level	=> 1,
	argc		=> 1,
);                      

sub ro_biblio_ingest_single_object {
	my $self = shift;
	my $client = shift;
	my $bib = shift;
	my $xml = OpenILS::Application::Ingest::entityize($bib->marc);
    my $max_cn = shift;
    my $max_uri = shift;

	my $cstore = OpenSRF::AppSession->connect( 'open-ils.cstore' );

    if (!$max_cn) {
    	my $cn = $cstore->request( 'open-ils.cstore.direct.asset.call_number.search' => { id => { '!=' => undef } }, { limit => 1, order_by => { acn => 'id desc' } } )->gather(1);
        $max_cn = int($cn->id) + 1000;
    }

    if (!$max_uri) {
    	my $cn = $cstore->request( 'open-ils.cstore.direct.asset.call_number.search' => { id => { '!=' => undef } }, { limit => 1, order_by => { acn => 'id desc' } } )->gather(1);
        $max_uri = int($cn->id) + 1000;
    }

    $cstore->disconnect;

	my $document = $parser->parse_string($xml);

	my @uris = $self->method_lookup("open-ils.ingest.856_uri.object")->run($bib, $max_cn, $max_uri);
	my @mfr = $self->method_lookup("open-ils.ingest.flat_marc.biblio.xml")->run($document);
	my @mXfe = $self->method_lookup("open-ils.ingest.extract.field_entry.all.xml")->run($document);
	my ($fp) = $self->method_lookup("open-ils.ingest.fingerprint.xml")->run($xml);
	my ($rd) = $self->method_lookup("open-ils.ingest.descriptor.xml")->run($xml);

	$_->source($bib->id) for (@mXfe);
	$_->record($bib->id) for (@mfr);
	$rd->record($bib->id) if ($rd);

	return { full_rec => \@mfr, field_entries => \@mXfe, fingerprint => $fp, descriptor => $rd, uri => \@uris };
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.full.biblio.object.readonly",
	method		=> "ro_biblio_ingest_single_object",
	api_level	=> 1,
	argc		=> 1,
);                      

sub ro_biblio_ingest_single_xml {
	my $self = shift;
	my $client = shift;
	my $xml = OpenILS::Application::Ingest::entityize(shift);

	my $document = $parser->parse_string($xml);

	my @mfr = $self->method_lookup("open-ils.ingest.flat_marc.biblio.xml")->run($document);
	my @mXfe = $self->method_lookup("open-ils.ingest.extract.field_entry.all.xml")->run($document);
	my ($fp) = $self->method_lookup("open-ils.ingest.fingerprint.xml")->run($xml);
	my ($rd) = $self->method_lookup("open-ils.ingest.descriptor.xml")->run($xml);

	return { full_rec => \@mfr, field_entries => \@mXfe, fingerprint => $fp, descriptor => $rd };
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.full.biblio.xml.readonly",
	method		=> "ro_biblio_ingest_single_xml",
	api_level	=> 1,
	argc		=> 1,
);                      

sub ro_biblio_ingest_single_record {
	my $self = shift;
	my $client = shift;
	my $rec = shift;

	OpenILS::Application::Ingest->post_init();
	my $r = OpenSRF::AppSession
			->create('open-ils.cstore')
			->request( 'open-ils.cstore.direct.biblio.record_entry.retrieve' => $rec )
			->gather(1);

	return undef unless ($r and @$r);

	my ($res) = $self->method_lookup("open-ils.ingest.full.biblio.xml.readonly")->run($r->marc);

	$_->source($rec) for (@{$res->{field_entries}});
	$_->record($rec) for (@{$res->{full_rec}});
	$res->{descriptor}->record($rec);

	return $res;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.full.biblio.record.readonly",
	method		=> "ro_biblio_ingest_single_record",
	api_level	=> 1,
	argc		=> 1,
);                      

sub ro_biblio_ingest_stream_record {
	my $self = shift;
	my $client = shift;

	OpenILS::Application::Ingest->post_init();

	my $ses = OpenSRF::AppSession->create('open-ils.cstore');

	while (my ($resp) = $client->recv( count => 1, timeout => 5 )) {
	
		my $rec = $resp->content;
		last unless (defined $rec);

		$log->debug("Running open-ils.ingest.full.biblio.record.readonly ...");
		my ($res) = $self->method_lookup("open-ils.ingest.full.biblio.record.readonly")->run($rec);

		$_->source($rec) for (@{$res->{field_entries}});
		$_->record($rec) for (@{$res->{full_rec}});

		$client->respond( $res );
	}

	return undef;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.full.biblio.record_stream.readonly",
	method		=> "ro_biblio_ingest_stream_record",
	api_level	=> 1,
	stream		=> 1,
);                      

sub ro_biblio_ingest_stream_xml {
	my $self = shift;
	my $client = shift;

	OpenILS::Application::Ingest->post_init();

	my $ses = OpenSRF::AppSession->create('open-ils.cstore');

	while (my ($resp) = $client->recv( count => 1, timeout => 5 )) {
	
		my $xml = $resp->content;
		last unless (defined $xml);

		$log->debug("Running open-ils.ingest.full.biblio.xml.readonly ...");
		my ($res) = $self->method_lookup("open-ils.ingest.full.biblio.xml.readonly")->run($xml);

		$client->respond( $res );
	}

	return undef;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.full.biblio.xml_stream.readonly",
	method		=> "ro_biblio_ingest_stream_xml",
	api_level	=> 1,
	stream		=> 1,
);                      

sub rw_biblio_ingest_stream_import {
	my $self = shift;
	my $client = shift;

	OpenILS::Application::Ingest->post_init();

	my $ses = OpenSRF::AppSession->create('open-ils.cstore');

	while (my ($resp) = $client->recv( count => 1, timeout => 5 )) {
	
		my $bib = $resp->content;
		last unless (defined $bib);

		$log->debug("Running open-ils.ingest.full.biblio.xml.readonly ...");
		my ($res) = $self->method_lookup("open-ils.ingest.full.biblio.xml.readonly")->run($bib->marc);

		$_->source($bib->id) for (@{$res->{field_entries}});
		$_->record($bib->id) for (@{$res->{full_rec}});

		$client->respond( $res );
	}

	return undef;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.full.biblio.bib_stream.import",
	method		=> "rw_biblio_ingest_stream_import",
	api_level	=> 1,
	stream		=> 1,
);                      


# --------------------------------------------------------------------------------
# Authority ingest

package OpenILS::Application::Ingest::Authority;
use base qw/OpenILS::Application::Ingest/;
use Unicode::Normalize;

sub ro_authority_ingest_single_object {
	my $self = shift;
	my $client = shift;
	my $bib = shift;
	my $xml = OpenILS::Application::Ingest::entityize($bib->marc);

	my $document = $parser->parse_string($xml);

	my @mfr = $self->method_lookup("open-ils.ingest.flat_marc.authority.xml")->run($document);

	$_->record($bib->id) for (@mfr);

	return { full_rec => \@mfr };
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.full.authority.object.readonly",
	method		=> "ro_authority_ingest_single_object",
	api_level	=> 1,
	argc		=> 1,
);                      

sub ro_authority_ingest_single_xml {
	my $self = shift;
	my $client = shift;
	my $xml = OpenILS::Application::Ingest::entityize(shift);

	my $document = $parser->parse_string($xml);

	my @mfr = $self->method_lookup("open-ils.ingest.flat_marc.authority.xml")->run($document);

	return { full_rec => \@mfr };
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.full.authority.xml.readonly",
	method		=> "ro_authority_ingest_single_xml",
	api_level	=> 1,
	argc		=> 1,
);                      

sub ro_authority_ingest_single_record {
	my $self = shift;
	my $client = shift;
	my $rec = shift;

	OpenILS::Application::Ingest->post_init();
	my $r = OpenSRF::AppSession
			->create('open-ils.cstore')
			->request( 'open-ils.cstore.direct.authority.record_entry.retrieve' => $rec )
			->gather(1);

	return undef unless ($r and @$r);

	my ($res) = $self->method_lookup("open-ils.ingest.full.authority.xml.readonly")->run($r->marc);

	$_->record($rec) for (@{$res->{full_rec}});
	$res->{descriptor}->record($rec);

	return $res;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.full.authority.record.readonly",
	method		=> "ro_authority_ingest_single_record",
	api_level	=> 1,
	argc		=> 1,
);                      

sub ro_authority_ingest_stream_record {
	my $self = shift;
	my $client = shift;

	OpenILS::Application::Ingest->post_init();

	my $ses = OpenSRF::AppSession->create('open-ils.cstore');

	while (my ($resp) = $client->recv( count => 1, timeout => 5 )) {
	
		my $rec = $resp->content;
		last unless (defined $rec);

		$log->debug("Running open-ils.ingest.full.authority.record.readonly ...");
		my ($res) = $self->method_lookup("open-ils.ingest.full.authority.record.readonly")->run($rec);

		$_->record($rec) for (@{$res->{full_rec}});

		$client->respond( $res );
	}

	return undef;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.full.authority.record_stream.readonly",
	method		=> "ro_authority_ingest_stream_record",
	api_level	=> 1,
	stream		=> 1,
);                      

sub ro_authority_ingest_stream_xml {
	my $self = shift;
	my $client = shift;

	OpenILS::Application::Ingest->post_init();

	my $ses = OpenSRF::AppSession->create('open-ils.cstore');

	while (my ($resp) = $client->recv( count => 1, timeout => 5 )) {
	
		my $xml = $resp->content;
		last unless (defined $xml);

		$log->debug("Running open-ils.ingest.full.authority.xml.readonly ...");
		my ($res) = $self->method_lookup("open-ils.ingest.full.authority.xml.readonly")->run($xml);

		$client->respond( $res );
	}

	return undef;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.full.authority.xml_stream.readonly",
	method		=> "ro_authority_ingest_stream_xml",
	api_level	=> 1,
	stream		=> 1,
);                      

sub rw_authority_ingest_stream_import {
	my $self = shift;
	my $client = shift;

	OpenILS::Application::Ingest->post_init();

	my $ses = OpenSRF::AppSession->create('open-ils.cstore');

	while (my ($resp) = $client->recv( count => 1, timeout => 5 )) {
	
		my $bib = $resp->content;
		last unless (defined $bib);

		$log->debug("Running open-ils.ingest.full.authority.xml.readonly ...");
		my ($res) = $self->method_lookup("open-ils.ingest.full.authority.xml.readonly")->run($bib->marc);

		$_->record($bib->id) for (@{$res->{full_rec}});

		$client->respond( $res );
	}

	return undef;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.full.authority.bib_stream.import",
	method		=> "rw_authority_ingest_stream_import",
	api_level	=> 1,
	stream		=> 1,
);                      


# --------------------------------------------------------------------------------
# MARC index extraction

package OpenILS::Application::Ingest::XPATH;
use base qw/OpenILS::Application::Ingest/;
use Unicode::Normalize;

# give this an XML documentElement and an XPATH expression
sub xpath_to_string {
	my $xml = shift;
	my $xpath = shift;
	my $ns_uri = shift;
	my $ns_prefix = shift;
	my $unique = shift;

	$xml->setNamespace( $ns_uri, $ns_prefix, 1 ) if ($ns_uri && $ns_prefix);

	my $string = "";

	# grab the set of matching nodes
	my @nodes = $xml->findnodes( $xpath );
	for my $value (@nodes) {

		# grab all children of the node
		my @children = $value->childNodes();
		for my $child (@children) {

			# add the childs content to the growing buffer
			my $content = quotemeta($child->textContent);
			next if ($unique && $string =~ /$content/);  # uniquify the values
			$string .= $child->textContent . " ";
		}
		if( ! @children ) {
			$string .= $value->textContent . " ";
		}
	}

    $string =~ s/(\w+)\/(\w+)/$1 $2/sgo;
    $string =~ s/(\d{4})-(\d{4})/$1 $2/sgo;

	return NFD($string);
}

sub class_index_string_xml {
	my $self = shift;
	my $client = shift;
	my $xml = shift;
	my @classes = @_;

	OpenILS::Application::Ingest->post_init();
	$xml = $parser->parse_string(OpenILS::Application::Ingest::entityize($xml)) unless (ref $xml);

	my %transform_cache;
	
	for my $class (@classes) {
		my $class_constructor = "Fieldmapper::metabib::${class}_field_entry";
		for my $type ( keys %{ $xpathset->{$class} } ) {

			my $def = $xpathset->{$class}->{$type};
			my $sf = $OpenILS::Application::Ingest::supported_formats{$def->{format}};

			my $document = $xml;

			if ($sf->{xslt}) {
				$document = $transform_cache{$def->{format}} || $sf->{xslt}->transform($xml);
				$transform_cache{$def->{format}} = $document;
			}

			my $value =  xpath_to_string(
					$document->documentElement	=> $def->{xpath},
					$sf->{ns}			=> $def->{format},
					1
			);

			next unless $value;

			$value = NFD($value);
			$value =~ s/\pM+//sgo;
			$value =~ s/\pC+//sgo;
			$value =~ s/\W+$//sgo;

			$value =~ s/\b\.+\b//sgo;
			$value = lc($value);

			my $fm = $class_constructor->new;
			$fm->value( $value );
			$fm->field( $xpathset->{$class}->{$type}->{id} );
			$client->respond($fm);
		}
	}
	return undef;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.field_entry.class.xml",
	method		=> "class_index_string_xml",
	api_level	=> 1,
	argc		=> 2,
	stream		=> 1,
);                      

sub class_index_string_record {
	my $self = shift;
	my $client = shift;
	my $rec = shift;
	my @classes = shift;

	OpenILS::Application::Ingest->post_init();
	my $r = OpenSRF::AppSession
			->create('open-ils.cstore')
			->request( 'open-ils.cstore.direct.authority.record_entry.retrieve' => $rec )
			->gather(1);

	return undef unless ($r and @$r);

	for my $fm ($self->method_lookup("open-ils.ingest.field_entry.class.xml")->run($r->marc, @classes)) {
		$fm->source($rec);
		$client->respond($fm);
	}
	return undef;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.field_entry.class.record",
	method		=> "class_index_string_record",
	api_level	=> 1,
	argc		=> 2,
	stream		=> 1,
);                      

sub all_index_string_xml {
	my $self = shift;
	my $client = shift;
	my $xml = shift;

	for my $fm ($self->method_lookup("open-ils.ingest.field_entry.class.xml")->run($xml, keys(%$xpathset))) {
		$client->respond($fm);
	}
	return undef;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.extract.field_entry.all.xml",
	method		=> "all_index_string_xml",
	api_level	=> 1,
	argc		=> 1,
	stream		=> 1,
);                      

sub all_index_string_record {
	my $self = shift;
	my $client = shift;
	my $rec = shift;

	OpenILS::Application::Ingest->post_init();
	my $r = OpenSRF::AppSession
			->create('open-ils.cstore')
			->request( 'open-ils.cstore.direct.biblio.record_entry.retrieve' => $rec )
			->gather(1);

	return undef unless ($r and @$r);

	for my $fm ($self->method_lookup("open-ils.ingest.field_entry.class.xml")->run($r->marc, keys(%$xpathset))) {
		$fm->source($rec);
		$client->respond($fm);
	}
	return undef;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.extract.field_entry.all.record",
	method		=> "all_index_string_record",
	api_level	=> 1,
	argc		=> 1,
	stream		=> 1,
);                      

# --------------------------------------------------------------------------------
# Flat MARC

package OpenILS::Application::Ingest::FlatMARC;
use base qw/OpenILS::Application::Ingest/;
use Unicode::Normalize;


sub _marcxml_to_full_rows {

	my $marcxml = shift;
	my $xmltype = shift || 'metabib';

	my $type = "Fieldmapper::${xmltype}::full_rec";

	my @ns_list;
	
	my ($root) = $marcxml->findnodes('//*[local-name()="record"]');

	for my $tagline ( @{$root->getChildrenByTagName("leader")} ) {
		next unless $tagline;

		my $ns = $type->new;

		$ns->tag( 'LDR' );
		my $val = $tagline->textContent;
		$val = NFD($val);
		$val =~ s/\pM+//sgo;
		$val =~ s/\pC+//sgo;
		$val =~ s/\W+$//sgo;
		$ns->value( $val );

		push @ns_list, $ns;
	}

	for my $tagline ( @{$root->getChildrenByTagName("controlfield")} ) {
		next unless $tagline;

		my $ns = $type->new;

		$ns->tag( $tagline->getAttribute( "tag" ) );
		my $val = $tagline->textContent;
		$val = NFD($val);
		$val =~ s/\pM+//sgo;
		$val =~ s/\pC+//sgo;
		$val =~ s/\W+$//sgo;
		$ns->value( $val );

		push @ns_list, $ns;
	}

	for my $tagline ( @{$root->getChildrenByTagName("datafield")} ) {
		next unless $tagline;

		my $tag = $tagline->getAttribute( "tag" );
		my $ind1 = $tagline->getAttribute( "ind1" );
		my $ind2 = $tagline->getAttribute( "ind2" );

		for my $data ( @{$tagline->getChildrenByTagName('subfield')} ) {
			next unless $data;

			my $ns = $type->new;

			$ns->tag( $tag );
			$ns->ind1( $ind1 );
			$ns->ind2( $ind2 );
			$ns->subfield( $data->getAttribute( "code" ) );
			my $val = $data->textContent;
			$val = NFD($val);
			$val =~ s/\pM+//sgo;
			$val =~ s/\pC+//sgo;
			$val =~ s/\W+$//sgo;
            $val =~ s/(\d{4})-(\d{4})/$1 $2/sgo;
            $val =~ s/(\w+)\/(\w+)/$1 $2/sgo;
			$ns->value( lc($val) );

			push @ns_list, $ns;
		}

        if ($xmltype eq 'metabib' and $tag eq '245') {
       		$tag = 'tnf';
    
    		for my $data ( @{$tagline->getChildrenByTagName('subfield')} ) {
    			next unless ($data and $data->getAttribute( "code" ) eq 'a');
    
    			$ns = $type->new;
    
    			$ns->tag( $tag );
    			$ns->ind1( $ind1 );
    			$ns->ind2( $ind2 );
    			$ns->subfield( $data->getAttribute( "code" ) );
    			my $val = substr( $data->textContent, $ind2 );
    			$val = NFD($val);
    			$val =~ s/\pM+//sgo;
    			$val =~ s/\pC+//sgo;
    			$val =~ s/\W+$//sgo;
                $val =~ s/(\w+)\/(\w+)/$1 $2/sgo;
                $val =~ s/(\d{4})-(\d{4})/$1 $2/sgo;
    			$ns->value( lc($val) );
    
    			push @ns_list, $ns;
    		}
        }
	}

	$log->debug("Returning ".scalar(@ns_list)." Fieldmapper nodes from $xmltype xml");
	return @ns_list;
}

sub flat_marc_xml {
	my $self = shift;
	my $client = shift;
	my $xml = shift;

	$log->debug("processing [$xml]");

	$xml = $parser->parse_string(OpenILS::Application::Ingest::entityize($xml)) unless (ref $xml);

	my $type = 'metabib';
	$type = 'authority' if ($self->api_name =~ /authority/o);

	OpenILS::Application::Ingest->post_init();

	$client->respond($_) for (_marcxml_to_full_rows($xml, $type));
	return undef;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.flat_marc.authority.xml",
	method		=> "flat_marc_xml",
	api_level	=> 1,
	argc		=> 1,
	stream		=> 1,
);                      
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.flat_marc.biblio.xml",
	method		=> "flat_marc_xml",
	api_level	=> 1,
	argc		=> 1,
	stream		=> 1,
);                      

sub flat_marc_record {
	my $self = shift;
	my $client = shift;
	my $rec = shift;

	my $type = 'biblio';
	$type = 'authority' if ($self->api_name =~ /authority/o);

	OpenILS::Application::Ingest->post_init();
	my $r = OpenSRF::AppSession
			->create('open-ils.cstore')
			->request( "open-ils.cstore.direct.${type}.record_entry.retrieve" => $rec )
			->gather(1);


	return undef unless ($r and $r->marc);

	my @rows = $self->method_lookup("open-ils.ingest.flat_marc.$type.xml")->run($r->marc);
	for my $row (@rows) {
		$client->respond($row);
		$log->debug(OpenSRF::Utils::JSON->perl2JSON($row), DEBUG);
	}
	return undef;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.flat_marc.biblio.record_entry",
	method		=> "flat_marc_record",
	api_level	=> 1,
	argc		=> 1,
	stream		=> 1,
);                      
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.flat_marc.authority.record_entry",
	method		=> "flat_marc_record",
	api_level	=> 1,
	argc		=> 1,
	stream		=> 1,
);                      


# --------------------------------------------------------------------------------
# URI extraction

package OpenILS::Application::Ingest::Biblio::URI;
use base qw/OpenILS::Application::Ingest/;
use Unicode::Normalize;
use OpenSRF::EX qw/:try/;


sub _extract_856_uris {

    my $recid   = shift;
	my $marcxml = shift;
	my $max_cn = shift;
	my $max_uri = shift;
	my @objects;
	
	my $document = $parser->parse_string($marcxml);
	my @nodes = $document->findnodes('//*[local-name()="datafield" and @tag="856" and (@ind1="4" or @ind1="1") and (@ind2="0" or @ind2="1")]');

    my $cstore = OpenSRF::AppSession->connect('open-ils.cstore');

    for my $node (@nodes) {
        # first, is there a URI?
        my $href = $node->findvalue('*[local-name()="subfield" and @code="u"]/text()');
        next unless ($href);

        # now, find the best possible label
        my $label = $node->findvalue('*[local-name()="subfield" and @code="y"]/text()');
        $label ||= $node->findvalue('*[local-name()="subfield" and @code="3"]/text()');
        $label ||= $href;

        # look for use info
        my $use = $node->findvalue('*[local-name()="subfield" and @code="z"]/text()');
        $use ||= $node->findvalue('*[local-name()="subfield" and @code="2"]/text()');
        $use ||= $node->findvalue('*[local-name()="subfield" and @code="n"]/text()');

        # moving on to the URI owner
        my $owner = $node->findvalue('*[local-name()="subfield" and @code="w"]/text()');
        $owner ||= $node->findvalue('*[local-name()="subfield" and @code="n"]/text()');
        $owner ||= $node->findvalue('*[local-name()="subfield" and @code="9"]/text()'); # Evergreen special sauce

        $owner =~ s/^.*?\((\w+)\).*$/$1/o; # unwrap first paren-enclosed string and then ...

        # no owner? skip it :(
        next unless ($owner);

    	my $org = $cstore
            ->request( 'open-ils.cstore.direct.actor.org_unit.search' => { shortname => $owner} )
			->gather(1);

        next unless ($org);

        # now we can construct the uri object
    	my $uri = $cstore
            ->request( 'open-ils.cstore.direct.asset.uri.search' => { label => $label, href => $href, use_restriction => $use, active => 't' } )
			->gather(1);

        if (!$uri) {
            $uri = Fieldmapper::asset::uri->new;
            $uri->isnew( 1 );
            $uri->id( $$max_uri++ );
            $uri->label($label);
            $uri->href($href);
            $uri->use_restriction($use);
        }

        # see if we need to create a call number
    	my $cn = $cstore
            ->request( 'open-ils.cstore.direct.asset.call_number.search' => { owning_lib => $org->id, record => $recid, label => '##URI##' } )
			->gather(1);

        if (!$cn) {
            $cn = Fieldmapper::asset::call_number->new;
            $cn->isnew( 1 );
            $cn->id( $$max_cn++ );
            $cn->owning_lib( $org->id );
            $cn->record( $recid );
            $cn->label( '##URI##' );
        }

        push @objects, { uri => $uri, call_number => $cn };
    }

	$log->debug("Returning ".scalar(@objects)." URI nodes for record $recid");
	return @objects;
}

sub get_uris_record {
	my $self = shift;
	my $client = shift;
	my $rec = shift;

	OpenILS::Application::Ingest->post_init();
	my $r = OpenSRF::AppSession
			->create('open-ils.cstore')
			->request( "open-ils.cstore.direct.biblio.record_entry.retrieve" => $rec )
			->gather(1);

	return undef unless ($r and $r->marc);

	$client->respond($_) for (_extract_856_uris($r->id, $r->marc));
	return undef;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.856_uri.record",
	method		=> "get_uris_record",
	api_level	=> 1,
	argc		=> 1,
	stream		=> 1,
);                      

sub get_uris_object {
	my $self = shift;
	my $client = shift;
	my $obj = shift;
	my $max_cn = shift;
	my $max_uri = shift;

	return undef unless ($obj and $obj->marc);

	$client->respond($_) for (_extract_856_uris($obj->id, $obj->marc, \$max_cn, \$max_uri));
	return undef;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.856_uri.object",
	method		=> "get_uris_object",
	api_level	=> 1,
	argc		=> 1,
	stream		=> 1,
);                      


# --------------------------------------------------------------------------------
# Fingerprinting

package OpenILS::Application::Ingest::Biblio::Fingerprint;
use base qw/OpenILS::Application::Ingest/;
use Unicode::Normalize;
use OpenSRF::EX qw/:try/;

sub biblio_fingerprint_record {
	my $self = shift;
	my $client = shift;
	my $rec = shift;

	OpenILS::Application::Ingest->post_init();

	my $r = OpenSRF::AppSession
			->create('open-ils.cstore')
			->request( 'open-ils.cstore.direct.biblio.record_entry.retrieve' => $rec )
			->gather(1);

	return undef unless ($r and $r->marc);

	my ($fp) = $self->method_lookup('open-ils.ingest.fingerprint.xml')->run($r->marc);
	$log->debug("Returning [$fp] as fingerprint for record $rec", INFO);
	$fp->{quality} = int($fp->{quality});
	return $fp;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.fingerprint.record",
	method		=> "biblio_fingerprint_record",
	api_level	=> 1,
	argc		=> 1,
);                      

our $fp_script;
sub biblio_fingerprint {
	my $self = shift;
	my $client = shift;
	my $xml = OpenILS::Application::Ingest::entityize(shift);

	$log->internal("Got MARC [$xml]");

	if(!$fp_script) {
		my @pfx = ( "apps", "open-ils.ingest","app_settings" );
		my $conf = OpenSRF::Utils::SettingsClient->new;

		my $libs        = $conf->config_value(@pfx, 'script_path');
		my $script_file = $conf->config_value(@pfx, 'scripts', 'biblio_fingerprint');
		my $script_libs = (ref($libs)) ? $libs : [$libs];

		$log->debug("Loading script $script_file for biblio fingerprinting...");
		
		$fp_script = new OpenILS::Utils::ScriptRunner
			( file		=> $script_file,
			  paths		=> $script_libs,
			  reset_count	=> 100 );
	}

	$fp_script->insert('environment' => {marc => $xml} => 1);

	my $res = $fp_script->run || ($log->error( "Fingerprint script died!  $@" ) && return undef);
	$log->debug("Script for biblio fingerprinting completed successfully...");

	return $res;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.fingerprint.xml",
	method		=> "biblio_fingerprint",
	api_level	=> 1,
	argc		=> 1,
);                      

our $rd_script;
sub biblio_descriptor {
	my $self = shift;
	my $client = shift;
	my $xml = OpenILS::Application::Ingest::entityize(shift);

	$log->internal("Got MARC [$xml]");

	if(!$rd_script) {
		my @pfx = ( "apps", "open-ils.ingest","app_settings" );
		my $conf = OpenSRF::Utils::SettingsClient->new;

		my $libs        = $conf->config_value(@pfx, 'script_path');
		my $script_file = $conf->config_value(@pfx, 'scripts', 'biblio_descriptor');
		my $script_libs = (ref($libs)) ? $libs : [$libs];

		$log->debug("Loading script $script_file for biblio descriptor extraction...");
		
		$rd_script = new OpenILS::Utils::ScriptRunner
			( file		=> $script_file,
			  paths		=> $script_libs,
			  reset_count	=> 100 );
	}

	$log->debug("Setting up environment for descriptor extraction script...");
	$rd_script->insert('environment.marc' => $xml => 1);
	$log->debug("Environment building complete...");

	my $res = $rd_script->run || ($log->error( "Descriptor script died!  $@" ) && return undef);
	$log->debug("Script for biblio descriptor extraction completed successfully");

    my $d1 = $res->date1;
    if ($d1 && $d1 ne '    ') {
        $d1 =~ tr/ux/00/;
        $res->date1( $d1 );
    }

    my $d2 = $res->date2;
    if ($d2 && $d2 ne '    ') {
        $d2 =~ tr/ux/99/;
        $res->date2( $d2 );
    }

	return $res;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.ingest.descriptor.xml",
	method		=> "biblio_descriptor",
	api_level	=> 1,
	argc		=> 1,
);                      


1;

