package OpenILS::Application::Cat::Utils;
use strict; use warnings;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::Fieldmapper;
use XML::LibXML;
use XML::LibXSLT;
use OpenSRF::Utils::SettingsParser;
use OpenILS::Utils::FlatXML;
use OpenILS::Application::WORM;

my $utils = OpenILS::Application::Cat::Utils->new();

my $parser		= XML::LibXML->new();
my $xslt			= XML::LibXSLT->new();
my $xslt_doc	= $parser->parse_file( "/pines/cvs/ILS/Open-ILS/xsl/MARC21slim2MODS.xsl" );
my $mods_sheet = $xslt->parse_stylesheet( $xslt_doc );

my $isbn_xpath			= "//mods:mods/mods:identifier[\@type='isbn']";

my $resource_xpath	= "//mods:mods/mods:typeOfResource";

my $pub_xpath			= "//mods:mods/mods:originInfo//mods:dateIssued[\@encoding='marc']|" . 
								"//mods:mods/mods:originInfo//mods:dateIssued[1]";

my $tcn_xpath			= "//mods:mods/mods:recordInfo/mods:recordIdentifier";
my $publisher_xpath	= "//mods:mods/mods:originInfo//mods:publisher[1]";


sub new {
	my($class) = @_;
	$class = ref($class) || $class;
	return bless( {}, $class );
}


# ---------------------------------------------------------------------------
# Converts an XML nodeset into a tree
# This method expects a blessed Fieldmapper::biblio::record_node object 
sub nodeset2tree {
	my($class, $nodeset) = @_;

	for my $child (@$nodeset) {
		next unless ($child and defined($child->parent_node));
		my $parent = $nodeset->[$child->parent_node];
		if( ! $parent ) {
			warn "No Parent For " . $child->intra_doc_id() . "\n";
		}
		$parent->children([]) unless defined($parent->children); 
		$child->isnew(0);
		$child->isdeleted(0);
		push( @{$parent->children}, $child );
	}

	return $nodeset->[0];
}


# ---------------------------------------------------------------------------
# Converts a tree into an xml nodeset
# This method expects a blessed Fieldmapper::biblio::record_node object 

sub tree2nodeset {

	my($self, $node, $newnodes) = @_;
	return $newnodes unless $node;

	if(!$newnodes) { $newnodes = []; }
	push( @$newnodes, $node );

	if( $node->children() ) {

		for my $child (@{ $node->children() }) {

			new Fieldmapper::biblio::record_node ($child);
			if(!defined($child->parent_node)) {
				$child->parent_node($node->intra_doc_id); 
				$child->ischanged(1); #just to be sure
			}
			$self->tree2nodeset( $child, $newnodes );
		}
	}

	$node->children([]); #we don't need them hanging around
	return $newnodes;
}


# Removes any deleted nodes from the tree
sub clean_nodeset {

	my($self, $nodeset) = @_;
	my @newnodes = ();
	for my $node (@$nodeset) {
		if(!$node->isdeleted() ) {
			push @newnodes, $node;
		}
	}

	return \@newnodes;
}




# ---------------------------------------------------------------------------
# Grabs the data 'we want' from the MODS doc and returns it in hash form
# ---------------------------------------------------------------------------
sub mods_values_to_mods_slim {
	my( $self, $modsperl ) = @_;

	my $title = "";
	my $author = "";
	my $subject = [];

	my $tmp = $modsperl->{title};

	if(!$tmp) { $title = ""; }
	else {
		($title = $tmp->{proper}) ||
		($title = $tmp->{translated}) ||
		($title = $tmp->{abbreviated}) ||
		($title = $tmp->{uniform});
	}

	$tmp = $modsperl->{author};
	if(!$tmp) { $author = ""; }
	else {
		($author = $tmp->{personal}) ||
		($author = $tmp->{other}) ||
		($author = $tmp->{corporate}) ||
		($author = $tmp->{conference}); 
	}

	$tmp = $modsperl->{subject};
	if(!$tmp) { $subject = []; } 
	else {
		for my $key( keys %{$tmp}) {
			push(@$subject, $tmp->{$key}) if $tmp->{$key};
		}
	}

	return { title => $title, author => $author, subject => $subject };

}

sub _marcxml_to_perl {
	my($self, $marcxml) = @_;
	my $xmldoc = $parser->parse_string( $marcxml );
	my $mods = $mods_sheet->transform($xmldoc);
	my $perl = OpenSRF::Utils::SettingsParser::XML2perl( $mods->documentElement );
	return $perl->{mods} if exists($perl->{mods});
	return $perl;
}


# ---------------------------------------------------------------------------
# Initializes a MARC -> Unified MODS batch process
# ---------------------------------------------------------------------------

sub start_mods_batch {

	my( $self, $master_doc ) = @_;
	if(!ref($self)) { 
		$self = new OpenILS::Application::Cat::Utils; 
	}

	my $xmldoc = $parser->parse_string($master_doc);
	my $mods = $mods_sheet->transform($xmldoc);

	$self->{master_doc} = OpenILS::Application::WORM->modsdoc_to_values( $mods );
	$self->{master_doc} = $utils->mods_values_to_mods_slim( $self->{master_doc} );

	$self->{master_doc}->{isbn} = 
		OpenILS::Application::WORM::_get_field_value( $mods, $isbn_xpath );

	$self->{master_doc}->{type_of_resource} = 
		[ OpenILS::Application::WORM::_get_field_value( $mods, $resource_xpath ) ];

	$self->{master_doc}->{tcn} = 
		OpenILS::Application::WORM::_get_field_value( $mods, $tcn_xpath );

	$self->{master_doc}->{pubdate} = 
		OpenILS::Application::WORM::_get_field_value( $mods, $pub_xpath );

	$self->{master_doc}->{publisher} = 
		OpenILS::Application::WORM::_get_field_value( $mods, $publisher_xpath );

}

# ---------------------------------------------------------------------------
# Takes a MARCXML string and adds it to the growing MODS doc
# ---------------------------------------------------------------------------
sub push_mods_batch {
	my( $self, $marcxml ) = @_;

	my $xmldoc = $parser->parse_string($marcxml);
	my $mods = $mods_sheet->transform($xmldoc);

	my $xmlperl = OpenILS::Application::WORM->modsdoc_to_values( $mods );
	$xmlperl = $utils->mods_values_to_mods_slim( $xmlperl );

	for my $subject( @{$xmlperl->{subject}} ) {
		push @{$self->{master_doc}->{subject}}, $subject;
	}

	push( @{$self->{master_doc}->{type_of_resource}}, 
		OpenILS::Application::WORM::_get_field_value( $mods, $resource_xpath ));

	if(!($self->{master_doc}->{isbn}) ) {
		$self->{master_doc}->{isbn} = 
			OpenILS::Application::WORM::_get_field_value( $mods, $isbn_xpath );
	}
}


# ---------------------------------------------------------------------------
# Completes a MARC -> Unified MODS batch process and returns the perl hash
# ---------------------------------------------------------------------------
sub finish_mods_batch {
	my $self = shift;
	my $perl = $self->{master_doc};
	$self->{master_doc} = undef;
	return $perl
}


1;
