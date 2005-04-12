package OpenILS::Application::Storage::WORM;
use base qw/OpenILS::Application::Storage/;
use strict; use warnings;

use OpenSRF::EX qw/:try/;

use OpenSRF::Utils::Logger qw/:level/;
my $log = 'OpenSRF::Utils::Logger';

use OpenILS::Utils::FlatXML;
use OpenILS::Utils::Fieldmapper;
use JSON;

use XML::LibXML;
use XML::LibXSLT;
use Time::HiRes qw(time);

my $xml_util	= OpenILS::Utils::FlatXML->new();

my $parser		= XML::LibXML->new();
my $xslt			= XML::LibXSLT->new();
my $xslt_doc	=	$parser->parse_file( "/home/miker/cvs/OpenILS/app_server/stylesheets/MARC21slim2MODS.xsl" );
#my $xslt_doc	= $parser->parse_file( "/pines/cvs/ILS/Open-ILS/xsl/MARC21slim2MODS.xsl" );
my $mods_sheet = $xslt->parse_stylesheet( $xslt_doc );

use open qw/:utf8/;

my $xpathset = {};

sub child_init {
	my $meth = __PACKAGE__->method_lookup('open-ils.storage.direct.config.metabib_field.all');
	for my $f ($meth->run) {
		$xpathset->{ $f->field_class }->{ $f->name }->{xpath} = $f->xpath;
		$xpathset->{ $f->field_class }->{ $f->name }->{id} = $f->id;
		$log->debug("Loaded XPath from DB: ".$f->field_class." => ".$f->name." : ".$f->xpath, DEBUG);
	}
}

# --------------------------------------------------------------------------------
# Fingerprinting

my @fp_mods_xpath = (
	'//mods:mods/mods:typeOfResource[text()="text"]' => [
			title	=> {
					xpath	=> [
							'//mods:mods/mods:titleInfo[mods:title and (@type="uniform")]',
							'//mods:mods/mods:titleInfo[mods:title and (@type="translated")]',
							'//mods:mods/mods:titleInfo[mods:title and (@type="alternative")]',
							'//mods:mods/mods:titleInfo[mods:title and not(@type)]',
					],
					fixup	=> '
							do {
								$text = lc($text);
								$text =~ s/\s+/ /sgo;
								$text =~ s/^\s*(.+)\s*$/$1/sgo;
								$text =~ s/\b(?:the|an?)\b//sgo;
								$text =~ s/\[.[^\]]+\]//sgo;
								$text =~ s/\s*[;\/\.]*$//sgo;
								$text =~ s/\pM+//gso;
							};
					',
			},
			author	=> {
					xpath	=> [
							'//mods:mods/mods:name[mods:role/mods:text/text()="creator" and @type="personal"]/mods:namePart',
							'//mods:mods/mods:name[mods:role/mods:text/text()="creator"]/mods:namePart',
					],
					fixup	=> '
							do {
								$text = lc($text);
								$text =~ s/\s+/ /sgo;
								$text =~ s/^\s*(.+)\s*$/$1/sgo;
								$text =~ s/,?\s+.*$//sgo;
								$text =~ s/\pM+//gso;
							};
					',
			},
	],

	'//mods:mods/mods:relatedItem[@type!="host"]' => [
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
					fixup	=> '
							do {
								$text = lc($text);
								$text =~ s/\s+/ /sgo;
								$text =~ s/^\s*(.+)\s*$/$1/sgo;
								$text =~ s/\b(?:the|an?)\b//sgo;
								$text =~ s/\[.[^\]]+\]//sgo;
								$text =~ s/\s*[;\/\.]*$//sgo;
								$text =~ s/\pM+//gso;
							};
					',
			},
			author	=> {
					xpath	=> [
							'//mods:mods/mods:relatedItem/mods:name[mods:role/mods:text/text()="creator" and @type="personal"]/mods:namePart',
							'//mods:mods/mods:relatedItem/mods:name[mods:role/mods:text/text()="creator"]/mods:namePart',
							'//mods:mods/mods:name[mods:role/mods:text/text()="creator" and @type="personal"]/mods:namePart',
							'//mods:mods/mods:name[mods:role/mods:text/text()="creator"]/mods:namePart',
					],
					fixup	=> '
							do {
								$text = lc($text);
								$text =~ s/\s+/ /sgo;
								$text =~ s/^\s*(.+)\s*$/$1/sgo;
								$text =~ s/,?\s+.*$//sgo;
								$text =~ s/\pM+//gso;
							};
					',
			},
	],

);

push @fp_mods_xpath, '//mods:mods/mods:titleInfo' => $fp_mods_xpath[1];

sub fingerprint_mods {
	my $mods = shift;

	my $fp_string = '';

	my $match_index = 0;
	my $block_index = 1;
	while ( my $match_xpath = $fp_mods_xpath[$match_index] ) {
		if ( my @nodes = $mods->findnodes( $match_xpath ) ) {

			my $block_name_index = 0;
			my $block_value_index = 1;
			my $block = $fp_mods_xpath[$block_index];
			while ( my $part = $$block[$block_value_index] ) {
				my $text;
				for my $xpath ( @{ $part->{xpath} } ) {
					$text = $mods->findvalue( $xpath );
					last if ($text);
				}

				$log->debug("Found fingerprint text using $$block[$block_name_index] : [$text]", DEBUG);

				if ($text) {
					eval $$part{fixup};
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



# --------------------------------------------------------------------------------

my $begin;
my $commit;
my $rollback;
my $lookup;
my $update_entry;
my $mr_lookup;
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
	audience => 'substr($oo8,22,1)',
);

sub wormize {

	my $self = shift;
	my $client = shift;
	my @docids = @_;

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


	try {
		my ($r) = $begin->run($client);
		unless (defined $r and $r) {
			$rollback->run;
			throw OpenSRF::EX::PANIC ("Couldn't BEGIN transaction!")
		}
	} catch Error with {
		throw OpenSRF::EX::PANIC ("WoRM Couldn't BEGIN transaction!")
	};

	my @source_maps;
	my @entry_list;
	my @rd_list;
	my @ns_list;
	my @mods_data;
	my $ret = 0;
	for my $entry ( $lookup->run(@docids) ) {
		# step -1: grab the doc from storage
		next unless ($entry);

		my $xml = $entry->marc;
		my $docid = $entry->id;
		my $marcdoc = $parser->parse_string($xml);
		my $modsdoc = $mods_sheet->transform($marcdoc);

		my $mods = $modsdoc->documentElement;
		$mods->setNamespace( "http://www.loc.gov/mods/", "mods", 1 );

		$entry->fingerprint( fingerprint_mods( $mods ) );
		push @entry_list, $entry;

		my ($mr) = $mr_lookup->run( $entry->fingerprint );
		if (!@$mr) {
			$mr = new Fieldmapper::metabib::metarecord;
			$mr->fingerprint( $entry->fingerprint );
			$mr->master_record( $entry->id );
			my ($new_mr) = $mr_create->run($mr);
			$mr->id($new_mr);
			unless (defined $mr) {
				throw OpenSRF::EX::PANIC ("Couldn't run open-ils.storage.direct.metabib.metarecord.create!")
			}
		} else {
			$mr = $$mr[0];
		}

		my $sm = new Fieldmapper::metabib::metarecord_source_map;
		$sm->metarecord( $mr->id );
		$sm->source( $entry->id );
		push @source_maps, $sm;

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
	$rm_old_sm->run( { source => \@docids } );
	$rm_old_tr->run( { source => \@docids } );
	$rm_old_ar->run( { source => \@docids } );
	$rm_old_sr->run( { source => \@docids } );
	$rm_old_kr->run( { source => \@docids } );

	my ($sm) = $create_source_map->run(@source_maps);
	unless (defined $sm) {
		throw OpenSRF::EX::PANIC ("Couldn't run open-ils.storage.direct.metabib.metarecord_source_map.batch.create!")
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
	for my $class ( qw/title author subject keyword/ ) {
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

	my ($c) = $commit->run;
	unless (defined $c and $c) {
		$rollback->run;
		throw OpenSRF::EX::PANIC ("Couldn't COMMIT changes!")
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
	api_name	=> "open-ils.worm.wormize.batch",
	method		=> "wormize",
	api_level	=> 1,
	argc		=> 1,
);


# --------------------------------------------------------------------------------


sub _marcxml_to_full_rows {

	my $marcxml = shift;

	my @ns_list;
	
	my $root = $marcxml->documentElement;

	for my $tagline ( @{$root->getChildrenByTagName("leader")} ) {
		next unless $tagline;

		my $ns = new Fieldmapper::metabib::full_rec;

		$ns->tag( 'LDR' );
		my $val = $tagline->textContent;
		$val =~ s/(\pM)//gso;
		$ns->value( $val );

		push @ns_list, $ns;
	}

	for my $tagline ( @{$root->getChildrenByTagName("controlfield")} ) {
		next unless $tagline;

		my $ns = new Fieldmapper::metabib::full_rec;

		$ns->tag( $tagline->getAttribute( "tag" ) );
		my $val = $tagline->textContent;
		$val =~ s/(\pM)//gso;
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

			my $ns = new Fieldmapper::metabib::full_rec;

			$ns->tag( $tag );
			$ns->ind1( $ind1 );
			$ns->ind2( $ind2 );
			$ns->subfield( $data->getAttribute( "code" ) );
			my $val = $data->textContent;
			$val =~ s/(\pM)//gso;
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
			$data->{$class}->{$type}->{value} = _get_field_value( $mods, $xpathset->{$class}->{$type}->{xpath} );
			$data->{$class}->{$type}->{field_id} = $xpathset->{$class}->{$type}->{id};
		}
	}
	return $data;
}


1;


