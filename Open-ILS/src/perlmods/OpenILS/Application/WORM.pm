package OpenILS::Application::WORM;
use base qw/OpenSRF::Application/;
use strict; use warnings;

use OpenILS::Utils::FlatXML;
use OpenILS::Utils::Fieldmapper;
use JSON;

use XML::LibXML;
use XML::LibXSLT;
use Time::HiRes qw(time);

my $xml_util	= OpenILS::Utils::FlatXML->new();

my $parser		= XML::LibXML->new();
my $xslt			= XML::LibXSLT->new();
my $xslt_doc	=	$parser->parse_file( "/pines/cvs/ILS/Open-ILS/xsl/MARC21slim2MODS.xsl" );
my $mods_sheet = $xslt->parse_stylesheet( $xslt_doc );

use open qw/:utf8/;

sub child_init {
	__PACKAGE__->method_lookup('i.do.not.exist');
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
			"//mods:mods/mods:name[\@type='corporate']/*[local-name()='namePart']".
				"[../mods:role/mods:text[text()='creator']][1]",

		personal => 
			"//mods:mods/mods:name[\@type='personal']/*[local-name()='namePart']".
				"[../mods:role/mods:text[text()='creator']][1]",

		conference => 
			"//mods:mods/mods:name[\@type='conference']/*[local-name()='namePart']".
				"[../mods:role/mods:text[text()='creator']][1]",

		other => 
			"//mods:mods/mods:name[\@type='personal']/*[local-name()='namePart']",
	},

	subject => {

		geographic => 
			"//mods:mods/*[local-name()='subject']/*[local-name()='geographic']",

		name => 
			"//mods:mods/*[local-name()='subject']/*[local-name()='name']",

		temporal => 
			"//mods:mods/*[local-name()='subject']/*[local-name()='temporal']",

		topic => 
			"//mods:mods/*[local-name()='subject']/*[local-name()='topic']",

	},

	keyword => { keyword => "//mods:mods/*[not(local-name()='originInfo')]", },

};


# --------------------------------------------------------------------------------

__PACKAGE__->register_method( 
		api_name => "open-ils.worm.wormize",
		method	=> "wormize",
		api_level	=> 1,
		argc	=> 1,
		stream => 0,
		);

sub wormize {

	my( $self, $client, $docid ) = @_;

	# step -1: grab the doc from storage
	my $name = "open-ils.storage.biblio.record_entry.nodeset.retrieve";
	my $method = $self->method_lookup( $name ); 
	if(!$method) { throw OpenSRF::EX::PANIC ("Can't locate method $name"); }
	my ($nodeset) = $method->run( $docid );
	if(!$nodeset) { throw OpenSRF::EX::ERROR ("Do MARC document found with id $docid");}


	# step 0: turn the doc into marcxml and mods
	my $marcxml	= $xml_util->nodeset_to_xml( $nodeset );
	if(!$marcxml) { throw OpenSRF::EX::PANIC ("Can't build XML from nodeset for $docid'"); }
	$marcxml = $parser->parse_string($marcxml->toString()); #bad, but good
	my $mods = $mods_sheet->transform($marcxml);


	# step 1: build the rows
	my $full_rows = _marcxml_to_full_rows( $marcxml );

	# step 2;
	for my $class (keys %$xpathset) {
		for my $type(keys %{$xpathset->{$class}}) {
			my $value = _get_field_value( $mods, $xpathset->{$class}->{$type} );
			print " $class : $type \t=> $value\n\n"
		}
	}

}



# --------------------------------------------------------------------------------


sub _marcxml_to_full_rows {

	my $marcxml = shift;

	my @full_marc_rows;
	my $root = $marcxml->documentElement;

	for my $tagline ( @{$root->getChildrenByTagName("datafield")} ) {

		next unless $tagline;
		my $tag	= $tagline->getAttribute( "tag" );
		my $ind1 = $tagline->getAttribute( "ind1" );
		my $ind2 = $tagline->getAttribute( "ind2" );
	
		for my $data ( @{$tagline->getChildrenByTagName("subfield")} ) {
			next unless $data;
			my $code		= $data->getAttribute( "code" );
			my $content = $data->textContent;
			push @full_marc_rows, [ $tag, $ind1, $ind2, $code, $content ]; #fieldmapper
		}
	}
	return \@full_marc_rows;
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
			next if ($string =~ $child->textContent);  # uniquify the values
			$string .= $child->textContent . " ";
		}
		if( ! @children ) {
			$string .= $value->textContent . " ";
		}
	}
	return $string;
}


1;


