package OpenILS::Application::WoRM;
use base qw/OpenSRF::Application/;
use open qw/:utf8/;

use Unicode::Normalize;
use OpenSRF::EX qw/:try/;

use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Logger qw/:level/;

use OpenILS::Utils::FlatXML;
use OpenILS::Utils::Fieldmapper;
use JSON;

use OpenILS::Utils::Fieldmapper;

use XML::LibXML;
use XML::LibXSLT;
use Time::HiRes qw(time);


our $log = 'OpenSRF::Utils::Logger';
our $xml_util = OpenILS::Utils::FlatXML->new();

our $parser = XML::LibXML->new();
our $xslt = XML::LibXSLT->new();
our $mods_sheet;
our $mads_sheet;

our $st_sess;
sub st_sess {
	my $self = shift;
	my $sess = shift;
	$st_sess = $sess if ($sess);
	return $st_sess;
}

our $xpathset = {};

sub initialize {}
sub child_init {}

sub post_init {
	$log->debug("Running post_init", DEBUG);

	unless ($mods_sheet) {
		$log->debug("Loading MODS XSLT", DEBUG);
	 	my $xslt_doc = $parser->parse_file(
			OpenSRF::Utils::SettingsClient->new->config_value(dirs => 'xsl') .  "/MARC21slim2MODS.xsl");
		$mods_sheet = $xslt->parse_stylesheet( $xslt_doc );
	}

	if (!__PACKAGE__->st_sess()) {
		$log->debug("Creating cached storage server session", DEBUG);
		__PACKAGE__->st_sess( OpenSRF::AppSession->create('open-ils.storage') );
	}

	unless (keys %$xpathset) {
		my $req = __PACKAGE__->st_sess()->request('open-ils.storage.direct.config.metabib_field.retrieve.all');
		while (my $resp = $req->recv) {
			my $f = $resp->content;
			$xpathset->{ $f->field_class }->{ $f->name }->{xpath} = $f->xpath;
			$xpathset->{ $f->field_class }->{ $f->name }->{id} = $f->id;
			$log->debug("Loaded XPath from DB: ".$f->field_class." => ".$f->name." : ".$f->xpath, DEBUG);
		}
	}
}


sub in_transaction {
	OpenILS::Application::WoRM->post_init();
	return __PACKAGE__->st_sess->request( 'open-ils.storage.transaction.current' )->gather(1);
}

sub begin_transaction {
	my $self = shift;
	my $client = shift;
	
	OpenILS::Application::WoRM->post_init();
	my $outer_xact = __PACKAGE__->st_sess->request( 'open-ils.storage.transaction.current' )->gather(1);
	
	try {
		if (!$outer_xact) {
			$log->debug("WoRM isn't inside a transaction, starting one now.", INFO);
			__PACKAGE__->st_sess->connect;
			my $r = __PACKAGE__->st_sess->request( 'open-ils.storage.transaction.begin' )->gather(1);
			unless (defined $r and $r) {
				__PACKAGE__->st_sess->request( 'open-ils.storage.transaction.rollback' )->gather(1);
				__PACKAGE__->st_sess->disconnect;
				throw OpenSRF::EX::PANIC ("Couldn't BEGIN transaction!")
			}
		}
	} catch Error with {
		$log->debug("WoRM Couldn't BEGIN transaction!", ERROR)
	};

	return __PACKAGE__->st_sess->request( 'open-ils.storage.transaction.current' )->gather(1);
}

sub commit_transaction {
	my $self = shift;
	my $client = shift;

	OpenILS::Application::WoRM->post_init();
	my $outer_xact = __PACKAGE__->st_sess->request( 'open-ils.storage.transaction.current' )->gather(1);

	try {
		if (__PACKAGE__->st_sess->connected && $outer_xact) {
			my $r = __PACKAGE__->st_sess->request( 'open-ils.storage.transaction.commit' )->gather(1);
			unless (defined $r and $r) {
				__PACKAGE__->st_sess->request( 'open-ils.storage.transaction.rollback' )->gather(1);
				throw OpenSRF::EX::PANIC ("Couldn't COMMIT transaction!")
			}
			__PACKAGE__->st_sess->disconnect;
		} else {
			$log->debug("WoRM isn't inside a transaction.", INFO);
		}
	} catch Error with {
		throw OpenSRF::EX::PANIC ("WoRM Couldn't COMMIT transaction!")
	};

	return 1;
}

sub storage_req {
	my $self = shift;
	__PACKAGE__->st_sess->request( @_ )->gather(1);
}

sub scrub_authority_record {
	my $self = shift;
	my $client = shift;
	my $rec = shift;

	my $commit = 0;
	if (!OpenILS::Application::WoRM->in_transaction) {
		OpenILS::Application::WoRM->begin_transaction || throw OpenSRF::EX::PANIC ("Couldn't BEGIN transaction!");
		$commit = 1;
	}

	OpenILS::Application::WoRM->storage_req( 'open-ils.storage.direct.authority.full_rec.mass_delete', { record => $rec } );
	OpenILS::Application::WoRM->storage_req( 'open-ils.storage.direct.authority.record_descriptor.mass_delete', { record => $rec } );

	OpenILS::Application::WoRM->commit_transaction if ($commit);
	return 1;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.worm.scrub.authority",
	method		=> "scrub_authority_record",
	api_level	=> 1,
	argc		=> 1,
);                      


sub scrub_metabib_record {
	my $self = shift;
	my $client = shift;
	my $rec = shift;

	my $commit = 0;
	if (!OpenILS::Application::WoRM->in_transaction) {
		OpenILS::Application::WoRM->begin_transaction || throw OpenSRF::EX::PANIC ("Couldn't BEGIN transaction!");
		$commit = 1;
	}

	OpenILS::Application::WoRM->storage_req( 'open-ils.storage.direct.metabib.full_rec.mass_delete', { record => $rec } );
	OpenILS::Application::WoRM->storage_req( 'open-ils.storage.direct.metabib.metarecord_source_map.mass_delete', { source => $rec } );
	OpenILS::Application::WoRM->storage_req( 'open-ils.storage.direct.metabib.record_descriptor.mass_delete', { record => $rec } );
	OpenILS::Application::WoRM->storage_req( 'open-ils.storage.direct.metabib.title_field_entry.mass_delete', { source => $rec } );
	OpenILS::Application::WoRM->storage_req( 'open-ils.storage.direct.metabib.author_field_entry.mass_delete', { source => $rec } );
	OpenILS::Application::WoRM->storage_req( 'open-ils.storage.direct.metabib.subject_field_entry.mass_delete', { source => $rec } );
	OpenILS::Application::WoRM->storage_req( 'open-ils.storage.direct.metabib.keyword_field_entry.mass_delete', { source => $rec } );
	OpenILS::Application::WoRM->storage_req( 'open-ils.storage.direct.metabib.series_field_entry.mass_delete', { source => $rec } );

	my $mr = OpenILS::Application::WoRM->storage_req( 'open-ils.storage.direct.metabib.metarecord.search_where', { master_record => $rec } );

	if ($mr) {
		my $others = OpenILS::Application::WoRM->storage_req(
				'open-ils.storage.direct.metabib.metarecord_source_map.search_where.atomic',
				{ metarecord => $mr->id }
		);

		if (@$others) {
			$mr->master_record($others->[0]->source);
			OpenILS::Application::WoRM->storage_req(
				'open-ils.storage.direct.metabib.metarecord.remote_update',
				{ id => $mr->id },
				{ master_record => $others->[0]->source }
			);
		} else {
			OpenILS::Application::WoRM->storage_req( 'open-ils.storage.direct.metabib.metarecord.delete', $mr->id );
		}
	}

	OpenILS::Application::WoRM->commit_transaction if ($commit);
	return 1;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.worm.scrub.biblio",
	method		=> "scrub_metabib_record",
	api_level	=> 1,
	argc		=> 1,
);                      


# --------------------------------------------------------------------------------
# MARC index extraction

package OpenILS::Application::WoRM::XPATH;
use base qw/OpenILS::Application::WoRM/;

# give this a MODS documentElement and an XPATH expression
sub _xpath_to_string {
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
	NFD($string);
	$string =~ s/(\pM)//gso;
	return $string;
}

sub class_all_index_string_xml {
	my $self = shift;
	my $client = shift;
	my $xml = shift;
	my $class = shift;

	OpenILS::Application::WoRM->post_init();
	$xml = $parser->parse_string($xml) unless (ref $xml);
	
	my $class_constructor = "Fieldmapper::metabib::${class}_field_entry";
	for my $type ( keys %{ $xpathset->{$class} } ) {
		my $value =  _xpath_to_string(
				$mods_sheet->transform($xml)->documentElement,
				$xpathset->{$class}->{$type}->{xpath},
				"http://www.loc.gov/mods/",
				"mods",
				1
		);

		next unless $value;

		my $fm = $class_constructor->new;
		$fm->value( $value );
		$fm->field( $xpathset->{$class}->{$type}->{id} );
		$client->respond($fm);
	}
	return undef;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.worm.field_entry.class.xml",
	method		=> "class_all_index_string_xml",
	api_level	=> 1,
	argc		=> 1,
	stream		=> 1,
);                      

sub class_all_index_string_record {
	my $self = shift;
	my $client = shift;
	my $rec = shift;
	my $class = shift;

	OpenILS::Application::WoRM->post_init();
	my $r = OpenILS::Application::WoRM->st_sess->request( "open-ils.storage.direct.biblio.record_entry.retrieve" => $rec )->gather(1);

	for my $fm ($self->method_lookup("open-ils.worm.field_entry.class.xml")->run($r->marc, $class)) {
		$fm->source($rec);
		$client->respond($fm);
	}
	return undef;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.worm.field_entry.class.record",
	method		=> "class_all_index_string_record",
	api_level	=> 1,
	argc		=> 1,
	stream		=> 1,
);                      


sub class_index_string_xml {
	my $self = shift;
	my $client = shift;
	my $xml = shift;
	my $class = shift;
	my $type = shift;

	OpenILS::Application::WoRM->post_init();
	$xml = $parser->parse_string($xml) unless (ref $xml);
	return _xpath_to_string( $mods_sheet->transform($xml)->documentElement, $xpathset->{$class}->{$type}->{xpath}, "http://www.loc.gov/mods/", "mods", 1 );
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.worm.class.type.xml",
	method		=> "class_index_string_xml",
	api_level	=> 1,
	argc		=> 1,
);                      

sub class_index_string_record {
	my $self = shift;
	my $client = shift;
	my $rec = shift;
	my $class = shift;
	my $type = shift;

	OpenILS::Application::WoRM->post_init();
	my $r = OpenILS::Application::WoRM->st_sess->request( "open-ils.storage.direct.biblio.record_entry.retrieve" => $rec )->gather(1);

	my ($d) = $self->method_lookup("open-ils.worm.class.type.xml")->run($r->marc, $class => $type);
	$log->debug("XPath $class->$type for bib rec $rec returns ($d)", DEBUG);
	return $d;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.worm.class.type.record",
	method		=> "class_index_string_record",
	api_level	=> 1,
	argc		=> 1,
);                      

sub xml_xpath {
	my $self = shift;
	my $client = shift;
	my $xml = shift;
	my $xpath = shift;
	my $uri = shift;
	my $prefix = shift;
	my $unique = shift;

	OpenILS::Application::WoRM->post_init();
	$xml = $parser->parse_string($xml) unless (ref $xml);
	return _xpath_to_string( $xml->documentElement, $xpath, $uri, $prefix, $unique );
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.worm.xpath.xml",
	method		=> "xml_xpath",
	api_level	=> 1,
	argc		=> 1,
);                      

sub record_xpath {
	my $self = shift;
	my $client = shift;
	my $rec = shift;
	my $xpath = shift;
	my $uri = shift;
	my $prefix = shift;
	my $unique = shift;

	OpenILS::Application::WoRM->post_init();
	my $r = OpenILS::Application::WoRM->st_sess->request( "open-ils.storage.direct.biblio.record_entry.retrieve" => $rec )->gather(1);

	my ($d) = $self->method_lookup("open-ils.worm.xpath.xml")->run($r->marc, $xpath, $uri, $prefix, $unique );
	$log->debug("XPath [$xpath] bib rec $rec returns ($d)", DEBUG);
	return $d;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.worm.xpath.record",
	method		=> "record_xpath",
	api_level	=> 1,
	argc		=> 1,
);                      


# --------------------------------------------------------------------------------
# MARC Descriptor

package OpenILS::Application::WoRM::Biblio::Leader;
use base qw/OpenILS::Application::WoRM/;

our %descriptor_code = (
	item_type => sub { substr($ldr,6,1); },
	item_form => sub { (substr($ldr,6,1) =~ /^(?:f|g|i|m|o|p|r)$/o) ? substr($oo8,29,1) : substr($oo8,23,1); },
	bib_level => sub { substr($ldr,7,1); },
	control_type => sub { substr($ldr,8,1); },
	char_encoding => sub { substr($ldr,9,1); },
	enc_level => sub { substr($ldr,17,1); },
	cat_form => sub { substr($ldr,18,1); },
	pub_status => sub { substr($ldr,5,1); },
	item_lang => sub { substr($oo8,35,3); },
	#lit_form => sub { (substr($ldr,6,1) =~ /^(?:f|g|i|m|o|p|r)$/) ? substr($oo8,33,1) : "0"; },
	audience => sub { substr($oo8,22,1); },
);

sub _extract_descriptors {
	my $xml = shift;

	local $ldr = $xml->findvalue('//*[local-name()="leader"]');
	local $oo8 = $xml->findvalue('//*[local-name()="controlfield" and @tag="008"]');

	my $rd_obj = Fieldmapper::metabib::record_descriptor->new;
	for my $rd_field ( keys %descriptor_code ) {
		$rd_obj->$rd_field( $descriptor_code{$rd_field}->() );
	}

	return $rd_obj;
}

sub extract_desc_xml {
	my $self = shift;
	my $client = shift;
	my $xml = shift;

	$xml = $parser->parse_string($xml) unless (ref $xml);

	return _extract_descriptors( $xml );
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.worm.biblio_leader.xml",
	method		=> "extract_desc_xml",
	api_level	=> 1,
	argc		=> 1,
);                      

sub extract_desc_record {
	my $self = shift;
	my $client = shift;
	my $rec = shift;

	OpenILS::Application::WoRM->post_init();
	my $r = OpenILS::Application::WoRM->st_sess->request( "open-ils.storage.direct.biblio.record_entry.retrieve" => $rec )->gather(1);

	my ($d) = $self->method_lookup("open-ils.worm.biblio_leader.xml")->run($r->marc);
	$log->debug("Record descriptor for bib rec $rec is ".JSON->perl2JSON($d), DEBUG);
	return $d;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.worm.biblio_leader.record",
	method		=> "extract_desc_record",
	api_level	=> 1,
	argc		=> 1,
);                      

# --------------------------------------------------------------------------------
# Flat MARC

package OpenILS::Application::WoRM::FlatMARC;
use base qw/OpenILS::Application::WoRM/;


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
		my $val = NFD($tagline->textContent);
		$val =~ s/(\pM+)//gso;
		$ns->value( $val );

		push @ns_list, $ns;
	}

	for my $tagline ( @{$root->getChildrenByTagName("controlfield")} ) {
		next unless $tagline;

		my $ns = $type->new;

		$ns->tag( $tagline->getAttribute( "tag" ) );
		my $val = NFD($tagline->textContent);
		$val =~ s/(\pM+)//gso;
		$ns->value( $val );

		push @ns_list, $ns;
	}

	for my $tagline ( @{$root->getChildrenByTagName("datafield")} ) {
		next unless $tagline;

		my $tag = $tagline->getAttribute( "tag" );
		my $ind1 = $tagline->getAttribute( "ind1" );
		my $ind2 = $tagline->getAttribute( "ind2" );

		for my $data ( $tagline->childNodes ) {
			next unless $data;

			my $ns = $type->new;

			$ns->tag( $tag );
			$ns->ind1( $ind1 );
			$ns->ind2( $ind2 );
			$ns->subfield( $data->getAttribute( "code" ) );
			my $val = NFD($data->textContent);
			$val =~ s/(\pM+)//gso;
			$ns->value( lc($val) );

			push @ns_list, $ns;
		}
	}

	$log->debug("Returning ".scalar(@ns_list)." Fieldmapper nodes from $xmltype xml", DEBUG);
	return @ns_list;
}

sub flat_marc_xml {
	my $self = shift;
	my $client = shift;
	my $xml = shift;

	$xml = $parser->parse_string($xml) unless (ref $xml);

	my $type = 'metabib';
	$type = 'authority' if ($self->api_name =~ /authority/o);

	OpenILS::Application::WoRM->post_init();

	$client->respond($_) for (_marcxml_to_full_rows($xml, $type));
	return undef;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.worm.flat_marc.authority.xml",
	method		=> "flat_marc_xml",
	api_level	=> 1,
	argc		=> 1,
	stream		=> 1,
);                      
__PACKAGE__->register_method(  
	api_name	=> "open-ils.worm.flat_marc.biblio.xml",
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

	OpenILS::Application::WoRM->post_init();
	my $r = OpenILS::Application::WoRM->st_sess->request( "open-ils.storage.direct.${type}.record_entry.retrieve" => $rec )->gather(1);

	$client->respond($_) for ($self->method_lookup("open-ils.worm.flat_marc.$type.xml")->run($r->marc));
	return undef;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.worm.flat_marc.biblio.record_entry",
	method		=> "flat_marc_record",
	api_level	=> 1,
	argc		=> 1,
	stream		=> 1,
);                      
__PACKAGE__->register_method(  
	api_name	=> "open-ils.worm.flat_marc.authority.record_entry",
	method		=> "flat_marc_record",
	api_level	=> 1,
	argc		=> 1,
	stream		=> 1,
);                      


# --------------------------------------------------------------------------------
# Fingerprinting

package OpenILS::Application::WoRM::Biblio::Fingerprint;
use base qw/OpenILS::Application::WoRM/;

my @fp_mods_xpath = (
	'//mods:mods/mods:typeOfResource[text()="text"]' => [
			title	=> {
					xpath	=> [
							'//mods:mods/mods:titleInfo[mods:title and (@type="uniform")]',
							'//mods:mods/mods:titleInfo[mods:title and (@type="translated")]',
							'//mods:mods/mods:titleInfo[mods:title and (@type="alternative")]',
							'//mods:mods/mods:titleInfo[mods:title and not(@type)]',
					],
					fixup	=> sub {
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							NFD($text);
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							$text =~ s/\pM+//gso;
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							$text = lc($text);
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							$text =~ s/\s+/ /sgo;
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							$text =~ s/^\s*(.+)\s*$/$1/sgo;
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							$text =~ s/\b(?:the|an?)\b//sgo;
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							$text =~ s/\[.[^\]]+\]//sgo;
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							$text =~ s/\s*[;\/\.]*$//sgo;
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
						},
			},
			author	=> {
					xpath	=> [
							'//mods:mods/mods:name[mods:role/mods:text/text()="creator" and @type="personal"]/mods:namePart',
							'//mods:mods/mods:name[mods:role/mods:text/text()="creator"]/mods:namePart',
					],
					fixup	=> sub {
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							NFD($text);
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							$text =~ s/\pM+//gso;
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							$text = lc($text);
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							$text =~ s/\s+/ /sgo;
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							$text =~ s/^\s*(.+)\s*$/$1/sgo;
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							$text =~ s/,?\s+.*$//sgo;
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
						},
			},
	],

	'//mods:mods/mods:relatedItem[@type!="host" and @type!="series"]' => [
			title	=> {
					xpath	=> [
							'//mods:mods/mods:relatedItem/mods:titleInfo[mods:title and (@type="uniform")]',
							'//mods:mods/mods:relatedItem/mods:titleInfo[mods:title and (@type="translated")]',
							'//mods:mods/mods:relatedItem/mods:titleInfo[mods:title and (@type="alternative")]',
							'//mods:mods/mods:relatedItem/mods:titleInfo[mods:title and not(@type)]',
							'//mods:mods/mods:titleInfo[mods:title and (@type="uniform")]',
							'//mods:mods/mods:titleInfo[mods:title and (@type="translated")]',
							'//mods:mods/mods:titleInfo[mods:title and (@type="alternative")]',
							'//mods:mods/mods:titleInfo[mods:title and not(@type)]',
					],
					fixup	=> sub {
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							NFD($text);
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							$text =~ s/\pM+//gso;
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							$text = lc($text);
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							$text =~ s/\s+/ /sgo;
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							$text =~ s/^\s*(.+)\s*$/$1/sgo;
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							$text =~ s/\b(?:the|an?)\b//sgo;
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							$text =~ s/\[.[^\]]+\]//sgo;
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							$text =~ s/\s*[;\/\.]*$//sgo;
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
						},
			},
			author	=> {
					xpath	=> [
							'//mods:mods/mods:relatedItem/mods:name[mods:role/mods:text/text()="creator" and @type="personal"]/mods:namePart',
							'//mods:mods/mods:relatedItem/mods:name[mods:role/mods:text/text()="creator"]/mods:namePart',
							'//mods:mods/mods:name[mods:role/mods:text/text()="creator" and @type="personal"]/mods:namePart',
							'//mods:mods/mods:name[mods:role/mods:text/text()="creator"]/mods:namePart',
					],
					fixup	=> sub {
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							NFD($text);
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							$text =~ s/\pM+//gso;
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							$text = lc($text);
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							$text =~ s/\s+/ /sgo;
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							$text =~ s/^\s*(.+)\s*$/$1/sgo;
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
							$text =~ s/,?\s+.*$//sgo;
							$log->debug("Fingerprint text /durring/ fixup : [$text]", INTERNAL);
						},
			},
	],

);

push @fp_mods_xpath, '//mods:mods/mods:titleInfo' => $fp_mods_xpath[1];

sub _fp_mods {
	my $mods = shift;
	$mods->setNamespace( "http://www.loc.gov/mods/", "mods", 1 );

	my $fp_string = '';

	my $match_index = 0;
	my $block_index = 1;
	while ( my $match_xpath = $fp_mods_xpath[$match_index] ) {
		if ( my @nodes = $mods->findnodes( $match_xpath ) ) {

			my $block_name_index = 0;
			my $block_value_index = 1;
			my $block = $fp_mods_xpath[$block_index];
			while ( my $part = $$block[$block_value_index] ) {
				local $text;
				for my $xpath ( @{ $part->{xpath} } ) {
					$text = $mods->findvalue( $xpath );
					last if ($text);
				}

				$log->debug("Found fingerprint text using $$block[$block_name_index] : [$text]", DEBUG);

				if ($text) {
					$$part{fixup}->();
					$log->debug("Fingerprint text after fixup : [$text]", DEBUG);
					$fp_string .= $text;
				}

				$block_name_index += 2;
				$block_value_index += 2;
			}
		}
		if ($fp_string) {
			$fp_string =~ s/\W+//gso;
			$log->debug("Fingerprint is [$fp_string]", INFO);;
			return $fp_string;
		}

		$match_index += 2;
		$block_index += 2;
	}
	return undef;
}


sub fingerprint_bibrec {
	my $self = shift;
	my $client = shift;
	my $rec = shift;

	OpenILS::Application::WoRM->post_init();
	my $r = OpenILS::Application::WoRM->st_sess->request( 'open-ils.storage.direct.biblio.record_entry.retrieve' => $rec )->gather(1);

	my ($fp) = $self->method_lookup('open-ils.worm.fingerprint.marc')->run($r->marc);
	$log->debug("Returning [$fp] as fingerprint for record $rec", INFO);
	return $fp;

}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.worm.fingerprint.record",
	method		=> "fingerprint_bibrec",
	api_level	=> 1,
	argc		=> 1,
);                      

sub fingerprint_mods {
	my $self = shift;
	my $client = shift;
	my $xml = shift;

	OpenILS::Application::WoRM->post_init();
	my $mods = $parser->parse_string($xml)->documentElement;

	return _fp_mods( $mods );
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.worm.fingerprint.mods",
	method		=> "fingerprint_mods",
	api_level	=> 1,
	argc		=> 1,
);                      

sub fingerprint_marc {
	my $self = shift;
	my $client = shift;
	my $xml = shift;

	$xml = $parser->parse_string($xml) unless (ref $xml);

	OpenILS::Application::WoRM->post_init();
	my $fp = _fp_mods( $mods_sheet->transform($xml)->documentElement );
	$log->debug("Returning [$fp] as fingerprint", INFO);
	return $fp;
}
__PACKAGE__->register_method(  
	api_name	=> "open-ils.worm.fingerprint.marc",
	method		=> "fingerprint_marc",
	api_level	=> 1,
	argc		=> 1,
);                      


# --------------------------------------------------------------------------------

1;
__END__
my $in_xact;
my $begin;
my $commit;
my $rollback;
my $lookup;
my $update_entry;
my $mr_lookup;
my $mr_update;
my $mr_create;
my $create_source_map;
my $sm_lookup;
my $rm_old_rd;
my $rm_old_sm;
my $rm_old_fr;
my $rm_old_tr;
my $rm_old_ar;
my $rm_old_sr;
my $rm_old_kr;
my $rm_old_ser;

my $fr_create;
my $rd_create;
my $create = {};

my %descriptor_code = (
	item_type => 'substr($ldr,6,1)',
	item_form => '(substr($ldr,6,1) =~ /^(?:f|g|i|m|o|p|r)$/) ? substr($oo8,29,1) : substr($oo8,23,1)',
	bib_level => 'substr($ldr,7,1)',
	control_type => 'substr($ldr,8,1)',
	char_encoding => 'substr($ldr,9,1)',
	enc_level => 'substr($ldr,17,1)',
	cat_form => 'substr($ldr,18,1)',
	pub_status => 'substr($ldr,5,1)',
	item_lang => 'substr($oo8,35,3)',
	#lit_form => '(substr($ldr,6,1) =~ /^(?:f|g|i|m|o|p|r)$/) ? substr($oo8,33,1) : "0"',
	audience => 'substr($oo8,22,1)',
);

sub wormize {

	my $self = shift;
	my $client = shift;
	my @docids = @_;

	my $no_map = 0;
	if ($self->api_name =~ /no_map/o) {
		$no_map = 1;
	}

	$in_xact = $self->method_lookup( 'open-ils.storage.transaction.current')
		unless ($in_xact);
	$begin = $self->method_lookup( 'open-ils.storage.transaction.begin')
		unless ($begin);
	$commit = $self->method_lookup( 'open-ils.storage.transaction.commit')
		unless ($commit);
	$rollback = $self->method_lookup( 'open-ils.storage.transaction.rollback')
		unless ($rollback);
	$sm_lookup = $self->method_lookup('open-ils.storage.direct.metabib.metarecord_source_map.search.source')
		unless ($sm_lookup);
	$mr_lookup = $self->method_lookup('open-ils.storage.direct.metabib.metarecord.search.fingerprint')
		unless ($mr_lookup);
	$mr_update = $self->method_lookup('open-ils.storage.direct.metabib.metarecord.batch.update')
		unless ($mr_update);
	$mr_create = $self->method_lookup('open-ils.storage.direct.metabib.metarecord.create')
		unless ($mr_create);
	$create_source_map = $self->method_lookup('open-ils.storage.direct.metabib.metarecord_source_map.batch.create')
		unless ($create_source_map);
	$lookup = $self->method_lookup('open-ils.storage.direct.biblio.record_entry.batch.retrieve')
		unless ($lookup);
	$update_entry = $self->method_lookup('open-ils.storage.direct.biblio.record_entry.batch.update')
		unless ($update_entry);
	$rm_old_sm = $self->method_lookup( 'open-ils.storage.direct.metabib.metarecord_source_map.mass_delete')
		unless ($rm_old_sm);
	$rm_old_rd = $self->method_lookup( 'open-ils.storage.direct.metabib.record_descriptor.mass_delete')
		unless ($rm_old_rd);
	$rm_old_fr = $self->method_lookup( 'open-ils.storage.direct.metabib.full_rec.mass_delete')
		unless ($rm_old_fr);
	$rm_old_tr = $self->method_lookup( 'open-ils.storage.direct.metabib.title_field_entry.mass_delete')
		unless ($rm_old_tr);
	$rm_old_ar = $self->method_lookup( 'open-ils.storage.direct.metabib.author_field_entry.mass_delete')
		unless ($rm_old_ar);
	$rm_old_sr = $self->method_lookup( 'open-ils.storage.direct.metabib.subject_field_entry.mass_delete')
		unless ($rm_old_sr);
	$rm_old_kr = $self->method_lookup( 'open-ils.storage.direct.metabib.keyword_field_entry.mass_delete')
		unless ($rm_old_kr);
	$rm_old_ser = $self->method_lookup( 'open-ils.storage.direct.metabib.series_field_entry.mass_delete')
		unless ($rm_old_ser);
	$rd_create = $self->method_lookup( 'open-ils.storage.direct.metabib.record_descriptor.batch.create')
		unless ($rd_create);
	$fr_create = $self->method_lookup( 'open-ils.storage.direct.metabib.full_rec.batch.create')
		unless ($fr_create);
	$$create{title} = $self->method_lookup( 'open-ils.storage.direct.metabib.title_field_entry.batch.create')
		unless ($$create{title});
	$$create{author} = $self->method_lookup( 'open-ils.storage.direct.metabib.author_field_entry.batch.create')
		unless ($$create{author});
	$$create{subject} = $self->method_lookup( 'open-ils.storage.direct.metabib.subject_field_entry.batch.create')
		unless ($$create{subject});
	$$create{keyword} = $self->method_lookup( 'open-ils.storage.direct.metabib.keyword_field_entry.batch.create')
		unless ($$create{keyword});
	$$create{series} = $self->method_lookup( 'open-ils.storage.direct.metabib.series_field_entry.batch.create')
		unless ($$create{series});


	my ($outer_xact) = $in_xact->run;
	try {
		unless ($outer_xact) {
			$log->debug("WoRM isn't inside a transaction, starting one now.", INFO);
			my ($r) = $begin->run($client);
			unless (defined $r and $r) {
				$rollback->run;
				throw OpenSRF::EX::PANIC ("Couldn't BEGIN transaction!")
			}
		}
	} catch Error with {
		throw OpenSRF::EX::PANIC ("WoRM Couldn't BEGIN transaction!")
	};

	my @source_maps;
	my @entry_list;
	my @mr_list;
	my @rd_list;
	my @ns_list;
	my @mods_data;
	my $ret = 0;
	for my $entry ( $lookup->run(@docids) ) {
		# step -1: grab the doc from storage
		next unless ($entry);

		if(!$mods_sheet) {
		 	my $xslt_doc = $parser->parse_file(
				OpenSRF::Utils::SettingsClient->new->config_value(dirs => 'xsl') .  "/MARC21slim2MODS.xsl");
			$mods_sheet = $xslt->parse_stylesheet( $xslt_doc );
		}

		my $xml = $entry->marc;
		my $docid = $entry->id;
		my $marcdoc = $parser->parse_string($xml);
		my $modsdoc = $mods_sheet->transform($marcdoc);

		my $mods = $modsdoc->documentElement;
		$mods->setNamespace( "http://www.loc.gov/mods/", "mods", 1 );

		$entry->fingerprint( fingerprint_mods( $mods ) );
		push @entry_list, $entry;

		$log->debug("Fingerprint for Record Entry ".$docid." is [".$entry->fingerprint."]", INFO);

		unless ($no_map) {
			my ($mr) = $mr_lookup->run( $entry->fingerprint );
			if (!$mr || !@$mr) {
				$log->debug("No metarecord found for fingerprint [".$entry->fingerprint."]; Creating a new one", INFO);
				$mr = new Fieldmapper::metabib::metarecord;
				$mr->fingerprint( $entry->fingerprint );
				$mr->master_record( $entry->id );
				my ($new_mr) = $mr_create->run($mr);
				$mr->id($new_mr);
				unless (defined $mr) {
					throw OpenSRF::EX::PANIC ("Couldn't run open-ils.storage.direct.metabib.metarecord.create!")
				}
			} else {
				$log->debug("Retrieved metarecord, id is ".$mr->id, INFO);
				$mr->mods('');
				push @mr_list, $mr;
			}

			my $sm = new Fieldmapper::metabib::metarecord_source_map;
			$sm->metarecord( $mr->id );
			$sm->source( $entry->id );
			push @source_maps, $sm;
		}

		my $ldr = $marcdoc->documentElement->getChildrenByTagName('leader')->pop->textContent;
		my $oo8 = $marcdoc->documentElement->findvalue('//*[local-name()="controlfield" and @tag="008"]');

		my $rd_obj = Fieldmapper::metabib::record_descriptor->new;
		for my $rd_field ( keys %descriptor_code ) {
			$rd_obj->$rd_field( eval "$descriptor_code{$rd_field};" );
		}
		$rd_obj->record( $docid );
		push @rd_list, $rd_obj;

		push @mods_data, { $docid => $self->modsdoc_to_values( $mods ) };

		# step 2: build the KOHA rows
		my @tmp_list = _marcxml_to_full_rows( $marcdoc );
		$_->record( $docid ) for (@tmp_list);
		push @ns_list, @tmp_list;

		$ret++;

		last unless ($self->api_name =~ /batch$/o);
	}

	$rm_old_rd->run( { record => \@docids } );
	$rm_old_fr->run( { record => \@docids } );
	$rm_old_sm->run( { source => \@docids } ) unless ($no_map);
	$rm_old_tr->run( { source => \@docids } );
	$rm_old_ar->run( { source => \@docids } );
	$rm_old_sr->run( { source => \@docids } );
	$rm_old_kr->run( { source => \@docids } );
	$rm_old_ser->run( { source => \@docids } );

	unless ($no_map) {
		my ($sm) = $create_source_map->run(@source_maps);
		unless (defined $sm) {
			throw OpenSRF::EX::PANIC ("Couldn't run open-ils.storage.direct.metabib.metarecord_source_map.batch.create!")
		}
		my ($mr) = $mr_update->run(@mr_list);
		unless (defined $mr) {
			throw OpenSRF::EX::PANIC ("Couldn't run open-ils.storage.direct.metabib.metarecord.batch.update!")
		}
	}

	my ($re) = $update_entry->run(@entry_list);
	unless (defined $re) {
		throw OpenSRF::EX::PANIC ("Couldn't run open-ils.storage.direct.biblio.record_entry.batch.update!")
	}

	my ($rd) = $rd_create->run(@rd_list);
	unless (defined $rd) {
		throw OpenSRF::EX::PANIC ("Couldn't run open-ils.storage.direct.metabib.record_descriptor.batch.create!")
	}

	my ($fr) = $fr_create->run(@ns_list);
	unless (defined $fr) {
		throw OpenSRF::EX::PANIC ("Couldn't run open-ils.storage.direct.metabib.full_rec.batch.create!")
	}

	# step 5: insert the new metadata
	for my $class ( qw/title author subject keyword series/ ) {
		my @md_list = ();
		for my $doc ( @mods_data ) {
			my ($did) = keys %$doc;
			my ($data) = values %$doc;

			my $fm_constructor = "Fieldmapper::metabib::${class}_field_entry";
			for my $row ( keys %{ $$data{$class} } ) {
				next unless (exists $$data{$class}{$row});
				next unless ($$data{$class}{$row}{value});
				my $fm_obj = $fm_constructor->new;
				$fm_obj->value( $$data{$class}{$row}{value} );
				$fm_obj->field( $$data{$class}{$row}{field_id} );
				$fm_obj->source( $did );
				$log->debug("$class entry: ".$fm_obj->source." => ".$fm_obj->field." : ".$fm_obj->value, DEBUG);

				push @md_list, $fm_obj;
			}
		}
			
		my ($cr) = $$create{$class}->run(@md_list);
		unless (defined $cr) {
			throw OpenSRF::EX::PANIC ("Couldn't run open-ils.storage.direct.metabib.${class}_field_entry.batch.create!")
		}
	}

	unless ($outer_xact) {
		$log->debug("Commiting transaction started by the WoRM.", INFO);
		my ($c) = $commit->run;
		unless (defined $c and $c) {
			$rollback->run;
			throw OpenSRF::EX::PANIC ("Couldn't COMMIT changes!")
		}
	}

	return $ret;
}
__PACKAGE__->register_method( 
	api_name	=> "open-ils.worm.wormize",
	method		=> "wormize",
	api_level	=> 1,
	argc		=> 1,
);
__PACKAGE__->register_method( 
	api_name	=> "open-ils.worm.wormize.no_map",
	method		=> "wormize",
	api_level	=> 1,
	argc		=> 1,
);
__PACKAGE__->register_method( 
	api_name	=> "open-ils.worm.wormize.batch",
	method		=> "wormize",
	api_level	=> 1,
	argc		=> 1,
);
__PACKAGE__->register_method( 
	api_name	=> "open-ils.worm.wormize.no_map.batch",
	method		=> "wormize",
	api_level	=> 1,
	argc		=> 1,
);


my $ain_xact;
my $abegin;
my $acommit;
my $arollback;
my $alookup;
my $aupdate_entry;
my $amr_lookup;
my $amr_update;
my $amr_create;
my $acreate_source_map;
my $asm_lookup;
my $arm_old_rd;
my $arm_old_sm;
my $arm_old_fr;
my $arm_old_tr;
my $arm_old_ar;
my $arm_old_sr;
my $arm_old_kr;
my $arm_old_ser;

my $afr_create;
my $ard_create;
my $acreate = {};

sub authority_wormize {

	my $self = shift;
	my $client = shift;
	my @docids = @_;

	my $no_map = 0;
	if ($self->api_name =~ /no_map/o) {
		$no_map = 1;
	}

	$in_xact = $self->method_lookup( 'open-ils.storage.transaction.current')
		unless ($in_xact);
	$begin = $self->method_lookup( 'open-ils.storage.transaction.begin')
		unless ($begin);
	$commit = $self->method_lookup( 'open-ils.storage.transaction.commit')
		unless ($commit);
	$rollback = $self->method_lookup( 'open-ils.storage.transaction.rollback')
		unless ($rollback);
	$alookup = $self->method_lookup('open-ils.storage.direct.authority.record_entry.batch.retrieve')
		unless ($alookup);
	$aupdate_entry = $self->method_lookup('open-ils.storage.direct.authority.record_entry.batch.update')
		unless ($aupdate_entry);
	$arm_old_rd = $self->method_lookup( 'open-ils.storage.direct.authority.record_descriptor.mass_delete')
		unless ($arm_old_rd);
	$arm_old_fr = $self->method_lookup( 'open-ils.storage.direct.authority.full_rec.mass_delete')
		unless ($arm_old_fr);
	$ard_create = $self->method_lookup( 'open-ils.storage.direct.authority.record_descriptor.batch.create')
		unless ($ard_create);
	$afr_create = $self->method_lookup( 'open-ils.storage.direct.authority.full_rec.batch.create')
		unless ($afr_create);


	my ($outer_xact) = $in_xact->run;
	try {
		unless ($outer_xact) {
			$log->debug("WoRM isn't inside a transaction, starting one now.", INFO);
			my ($r) = $begin->run($client);
			unless (defined $r and $r) {
				$rollback->run;
				throw OpenSRF::EX::PANIC ("Couldn't BEGIN transaction!")
			}
		}
	} catch Error with {
		throw OpenSRF::EX::PANIC ("WoRM Couldn't BEGIN transaction!")
	};

	my @source_maps;
	my @entry_list;
	my @mr_list;
	my @rd_list;
	my @ns_list;
	my @mads_data;
	my $ret = 0;
	for my $entry ( $lookup->run(@docids) ) {
		# step -1: grab the doc from storage
		next unless ($entry);

		#if(!$mads_sheet) {
		# 	my $xslt_doc = $parser->parse_file(
		#		OpenSRF::Utils::SettingsClient->new->config_value(dirs => 'xsl') .  "/MARC21slim2MODS.xsl");
		#	$mads_sheet = $xslt->parse_stylesheet( $xslt_doc );
		#}

		my $xml = $entry->marc;
		my $docid = $entry->id;
		my $marcdoc = $parser->parse_string($xml);
		#my $madsdoc = $mads_sheet->transform($marcdoc);

		#my $mads = $madsdoc->documentElement;
		#$mads->setNamespace( "http://www.loc.gov/mads/", "mads", 1 );

		push @entry_list, $entry;

		my $ldr = $marcdoc->documentElement->getChildrenByTagName('leader')->pop->textContent;
		my $oo8 = $marcdoc->documentElement->findvalue('//*[local-name()="controlfield" and @tag="008"]');

		my $rd_obj = Fieldmapper::authority::record_descriptor->new;
		for my $rd_field ( keys %descriptor_code ) {
			$rd_obj->$rd_field( eval "$descriptor_code{$rd_field};" );
		}
		$rd_obj->record( $docid );
		push @rd_list, $rd_obj;

		# step 2: build the KOHA rows
		my @tmp_list = _marcxml_to_full_rows( $marcdoc, 'Fieldmapper::authority::full_rec' );
		$_->record( $docid ) for (@tmp_list);
		push @ns_list, @tmp_list;

		$ret++;

		last unless ($self->api_name =~ /batch$/o);
	}

	$arm_old_rd->run( { record => \@docids } );
	$arm_old_fr->run( { record => \@docids } );

	my ($rd) = $ard_create->run(@rd_list);
	unless (defined $rd) {
		throw OpenSRF::EX::PANIC ("Couldn't run open-ils.storage.direct.authority.record_descriptor.batch.create!")
	}

	my ($fr) = $fr_create->run(@ns_list);
	unless (defined $fr) {
		throw OpenSRF::EX::PANIC ("Couldn't run open-ils.storage.direct.authority.full_rec.batch.create!")
	}

	unless ($outer_xact) {
		$log->debug("Commiting transaction started by the WoRM.", INFO);
		my ($c) = $commit->run;
		unless (defined $c and $c) {
			$rollback->run;
			throw OpenSRF::EX::PANIC ("Couldn't COMMIT changes!")
		}
	}

	return $ret;
}
__PACKAGE__->register_method( 
	api_name	=> "open-ils.worm.authortiy.wormize",
	method		=> "wormize",
	api_level	=> 1,
	argc		=> 1,
);
__PACKAGE__->register_method( 
	api_name	=> "open-ils.worm.authority.wormize.batch",
	method		=> "wormize",
	api_level	=> 1,
	argc		=> 1,
);


# --------------------------------------------------------------------------------


sub _marcxml_to_full_rows {

	my $marcxml = shift;
	my $type = shift || 'Fieldmapper::metabib::full_rec';

	my @ns_list;
	
	my $root = $marcxml->documentElement;

	for my $tagline ( @{$root->getChildrenByTagName("leader")} ) {
		next unless $tagline;

		my $ns = new Fieldmapper::metabib::full_rec;

		$ns->tag( 'LDR' );
		my $val = NFD($tagline->textContent);
		$val =~ s/(\pM+)//gso;
		$ns->value( $val );

		push @ns_list, $ns;
	}

	for my $tagline ( @{$root->getChildrenByTagName("controlfield")} ) {
		next unless $tagline;

		my $ns = new Fieldmapper::metabib::full_rec;

		$ns->tag( $tagline->getAttribute( "tag" ) );
		my $val = NFD($tagline->textContent);
		$val =~ s/(\pM+)//gso;
		$ns->value( $val );

		push @ns_list, $ns;
	}

	for my $tagline ( @{$root->getChildrenByTagName("datafield")} ) {
		next unless $tagline;

		my $tag = $tagline->getAttribute( "tag" );
		my $ind1 = $tagline->getAttribute( "ind1" );
		my $ind2 = $tagline->getAttribute( "ind2" );

		for my $data ( $tagline->childNodes ) {
			next unless $data;

			my $ns = $type->new;

			$ns->tag( $tag );
			$ns->ind1( $ind1 );
			$ns->ind2( $ind2 );
			$ns->subfield( $data->getAttribute( "code" ) );
			my $val = NFD($data->textContent);
			$val =~ s/(\pM+)//gso;
			$ns->value( lc($val) );

			push @ns_list, $ns;
		}
	}
	return @ns_list;
}

sub _get_field_value {

	my( $root, $xpath ) = @_;

	my $string = "";

	# grab the set of matching nodes
	my @nodes = $root->findnodes( $xpath );
	for my $value (@nodes) {

		# grab all children of the node
		my @children = $value->childNodes();
		for my $child (@children) {

			# add the childs content to the growing buffer
			my $content = quotemeta($child->textContent);
			next if ($string =~ /$content/);  # uniquify the values
			$string .= $child->textContent . " ";
		}
		if( ! @children ) {
			$string .= $value->textContent . " ";
		}
	}
	$string = NFD($string);
	$string =~ s/(\pM)//gso;
	return lc($string);
}


sub modsdoc_to_values {
	my( $self, $mods ) = @_;
	my $data = {};
	for my $class (keys %$xpathset) {
		$data->{$class} = {};
		for my $type (keys %{$xpathset->{$class}}) {
			$data->{$class}->{$type} = {};
			$data->{$class}->{$type}->{field_id} = $xpathset->{$class}->{$type}->{id};
		}
	}
	return $data;
}


1;


