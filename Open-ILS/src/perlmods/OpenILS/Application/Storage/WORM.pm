package OpenILS::Application::Storage::WORM;
use base qw/OpenILS::Application::Storage/;
use strict; use warnings;

use OpenSRF::EX qw/:try/;

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


sub child_init {
	#try {
	#	__PACKAGE__->method_lookup('i.do.not.exist');
	#} catch Error with {
	#	warn shift();
	#};
}


# get me from the database
my $xpathset = {

	title => {

		abbreviated => 
			"//mods:mods/mods:titleInfo[mods:title and (\@type='abreviated')]",

		translated =>
			"//mods:mods/mods:titleInfo[mods:title and (\@type='translated')]",

		uniform =>
			"//mods:mods/mods:titleInfo[mods:title and (\@type='uniform')]",

		proper =>
			"//mods:mods/mods:titleInfo[mods:title and not (\@type)]",
	},

	author => {

		corporate => 
			"//mods:mods/mods:name[\@type='corporate']/mods:namePart".
				"[../mods:role/mods:text[text()='creator']][1]",

		personal => 
			"//mods:mods/mods:name[\@type='personal']/mods:namePart".
				"[../mods:role/mods:text[text()='creator']][1]",

		conference => 
			"//mods:mods/mods:name[\@type='conference']/mods:namePart".
				"[../mods:role/mods:text[text()='creator']][1]",

		other => 
			"//mods:mods/mods:name[\@type='personal']/mods:namePart",
	},

	subject => {

		geographic => 
			"//mods:mods/mods:subject/mods:geographic",

		name => 
			"//mods:mods/mods:subject/mods:name",

		temporal => 
			"//mods:mods/mods:subject/mods:temporal",

		topic => 
			"//mods:mods/mods:subject/mods:topic",

		genre => 
			"//mods:mods/mods:genre",

	},

	keyword => { keyword => "//mods:mods/*[not(local-name()='originInfo')]", },

};


# --------------------------------------------------------------------------------

__PACKAGE__->register_method( 
	api_name	=> "open-ils.worm.wormize",
	method		=> "wormize",
	api_level	=> 1,
	argc		=> 1,
);

sub wormize {

	my( $self, $client, $docid ) = @_;

	# step -1: grab the doc from storage
	my $meth = $self->method_lookup('open-ils.storage.biblio.record_marc.retrieve');
	my ($marc) = $meth->run($docid);
	return undef unless ($marc);
	return $self->wormize_marc( $client, $docid, $marc->marc );
}


__PACKAGE__->register_method( 
	api_name	=> "open-ils.worm.wormize.marc",
	method		=> "wormize",
	api_level	=> 1,
	argc		=> 1,
);

my $rm_old_fr;
my $rm_old_tr;
my $rm_old_ar;
my $rm_old_sr;
my $rm_old_kr;

my $fr_create;
my $create = {};

my $begin;
my $commit;
my $rollback;

sub wormize_marc {
	my( $self, $client, $docid, $xml) = @_;

	$rm_old_fr = $self->method_lookup( 'open-ils.storage.metabib.full_rec.mass_delete')
		unless ($rm_old_fr);

	$rm_old_tr = $self->method_lookup( 'open-ils.storage.metabib.title_field_entry.mass_delete')
		unless ($rm_old_tr);

	$rm_old_ar = $self->method_lookup( 'open-ils.storage.metabib.author_field_entry.mass_delete')
		unless ($rm_old_ar);

	$rm_old_sr = $self->method_lookup( 'open-ils.storage.metabib.subject_field_entry.mass_delete')
		unless ($rm_old_sr);

	$rm_old_kr = $self->method_lookup( 'open-ils.storage.metabib.keyword_field_entry.mass_delete')
		unless ($rm_old_kr);

	$fr_create = $self->method_lookup( 'open-ils.storage.metabib.full_rec.batch.create')
		unless ($fr_create);
	$$create{title} = $self->method_lookup( 'open-ils.storage.metabib.title_field_entry.batch.create')
		unless ($$create{title});
	$$create{author} = $self->method_lookup( 'open-ils.storage.metabib.author_field_entry.batch.create')
		unless ($$create{author});
	$$create{subject} = $self->method_lookup( 'open-ils.storage.metabib.subject_field_entry.batch.create')
		unless ($$create{subject});
	$$create{keyword} = $self->method_lookup( 'open-ils.storage.metabib.keyword_field_entry.batch.create')
		unless ($$create{keyword});

	$begin = $self->method_lookup( 'open-ils.storage.transaction.begin')
		unless ($begin);
	$commit = $self->method_lookup( 'open-ils.storage.transaction.commit')
		unless ($commit);
	$rollback = $self->method_lookup( 'open-ils.storage.transaction.rollback')
		unless ($rollback);


	my ($br) = $begin->run($client);
	unless (defined $br) {
		$rollback->run;
		throw OpenSRF::EX::PANIC ("Couldn't BEGIN transaction!")
	}

	# step 0: turn the doc into marcxml and delete old entries
	my $marcdoc = $parser->parse_string($xml);

	my ($res) = $rm_old_fr->run( { record => $docid } );
	throw OpenSRF::EX::PANIC ("Couldn't remove old metabib::full_rec entries!")
		unless (defined $res);

	undef $res;
	($res) = $rm_old_tr->run( { source => $docid } );
	throw OpenSRF::EX::PANIC ("Couldn't remove old metabib::title_field_entry entries!")
		unless (defined $res);

	undef $res;
	($res) = $rm_old_ar->run( { source => $docid } );
	throw OpenSRF::EX::PANIC ("Couldn't remove old metabib::author_field_entry entries!")
		unless (defined $res);

	undef $res;
	($res) = $rm_old_sr->run( { source => $docid } );
	throw OpenSRF::EX::PANIC ("Couldn't remove old metabib::subject_field_entry entries!")
		unless (defined $res);

	undef $res;
	($res) = $rm_old_kr->run( { source => $docid } );
	throw OpenSRF::EX::PANIC ("Couldn't remove old metabib::keyword_field_entry entries!")
		unless (defined $res);

	# step 2: build the KOHA rows
	my @ns_list = _marcxml_to_full_rows( $marcdoc );
	$_->record( $docid ) for (@ns_list);


	my ($fr) = $fr_create->run(@ns_list);
	unless (defined $fr) {
		$rollback->run;
		throw OpenSRF::EX::PANIC ("Couldn't run open-ils.storage.metabib.full_rec.batch.create!")
	}

	# step 4: get the MODS based metadata
	my $data = $self->modsdoc_to_values( $mods_sheet->transform($marcdoc) );

	# step 5: insert the new metadata
	for my $class ( keys %$data ) {
			
		my $fm_constructor = "Fieldmapper::metabib::${class}_field_entry";
		my @md_list = ();
		for my $row ( keys %{ $$data{$class} } ) {
			next unless (exists $$data{$class}{$row});
			next unless ($$data{$class}{$row});
			my $fm_obj = $fm_constructor->new;
			$fm_obj->value( $$data{$class}{$row} );
			$fm_obj->source( $docid );

			# XXX This needs to be a real thing once the xpath is in the DB
			$fm_obj->field( 1 );

			push @md_list, $fm_obj;
		}
			
		my ($cr) = $$create{$class}->run(@md_list);
		unless (defined $cr) {
			$rollback->run;
			throw OpenSRF::EX::PANIC ("Couldn't run open-ils.storage.metabib.${class}_field_entry.batch.create!")
		}
	}

	my ($c) = $commit->run;
	unless (defined $c) {
		$rollback->run;
		throw OpenSRF::EX::PANIC ("Couldn't COMMIT changes!")
	}

	return 1;

}



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

		for my $data ( @{$tagline->getChildrenByTagName("subfield")} ) {
			next unless $tagline;

			my $ns = new Fieldmapper::metabib::full_rec;

			$ns->tag( $tagline->getAttribute( "tag" ) );
			$ns->ind1( $tagline->getAttribute( "ind1" ) );
			$ns->ind2( $tagline->getAttribute( "ind2" ) );
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

	my( $mods, $xpath ) = @_;

	my $string = "";
	my $root = $mods->documentElement;
	$root->setNamespace( "http://www.loc.gov/mods/", "mods", 1 );

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
		for my $type(keys %{$xpathset->{$class}}) {
			my $value = _get_field_value( $mods, $xpathset->{$class}->{$type} );
			$data->{$class}->{$type} = $value;
		}
	}
	return $data;
}


1;


