package OpenILS::Utils::ModsParser;
use strict; use warnings;

use OpenSRF::EX qw/:try/;
use XML::LibXML;
use XML::LibXSLT;
use Time::HiRes qw(time);

my $parser		= XML::LibXML->new();
my $xslt			= XML::LibXSLT->new();
my $xslt_doc	= $parser->parse_file( 
		"/pines/cvs/ILS/Open-ILS/xsl/MARC21slim2MODS.xsl" );
my $mods_sheet = $xslt->parse_stylesheet( $xslt_doc );

# ----------------------------------------------------------------------------------------
# XXX get me from the database and cache me ...
my $isbn_xpath			= "//mods:mods/mods:identifier[\@type='isbn']";
my $resource_xpath	= "//mods:mods/mods:typeOfResource";
my $pub_xpath			= "//mods:mods/mods:originInfo//mods:dateIssued[\@encoding='marc']|" . 
								"//mods:mods/mods:originInfo//mods:dateIssued[1]";
my $tcn_xpath			= "//mods:mods/mods:recordInfo/mods:recordIdentifier";
my $publisher_xpath	= "//mods:mods/mods:originInfo//mods:publisher[1]";


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
# ----------------------------------------------------------------------------------------



sub new { return bless( {}, shift() ); }

sub get_field_value {

	my( $self, $mods, $xpath ) = @_;

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
			next if ($string =~ /$content/);  # uniquify the values ! don't de-dup for the WORM!
			$string .= $child->textContent . " ";
		}
		if( ! @children ) {
			$string .= $value->textContent . " ";
		}
	}
	return $string;
}


sub modsdoc_to_values {
	my( $self, $mods ) = @_;
	my $data = {};
	for my $class (keys %$xpathset) {
		$data->{$class} = {};
		for my $type(keys %{$xpathset->{$class}}) {
			my $value = $self->get_field_value( $mods, $xpathset->{$class}->{$type} );
			$data->{$class}->{$type} = $value;
		}
	}
	return $data;
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



# ---------------------------------------------------------------------------
# Initializes a MARC -> Unified MODS batch process
# ---------------------------------------------------------------------------

sub start_mods_batch {

	my( $self, $master_doc ) = @_;

	my $xmldoc = $parser->parse_string($master_doc);
	my $mods = $mods_sheet->transform($xmldoc);

	$self->{master_doc} = $self->modsdoc_to_values( $mods );
	$self->{master_doc} = $self->mods_values_to_mods_slim( $self->{master_doc} );

	$self->{master_doc}->{isbn} = 
		$self->get_field_value( $mods, $isbn_xpath );

	$self->{master_doc}->{type_of_resource} = 
		[ $self->get_field_value( $mods, $resource_xpath ) ];

	$self->{master_doc}->{tcn} = 
		$self->get_field_value( $mods, $tcn_xpath );

	$self->{master_doc}->{pubdate} = 
		$self->get_field_value( $mods, $pub_xpath );

	$self->{master_doc}->{publisher} = 
		$self->get_field_value( $mods, $publisher_xpath );

}

# ---------------------------------------------------------------------------
# Takes a MARCXML string and adds it to the growing MODS doc
# ---------------------------------------------------------------------------
sub push_mods_batch {
	my( $self, $marcxml ) = @_;

	my $xmldoc = $parser->parse_string($marcxml);
	my $mods = $mods_sheet->transform($xmldoc);

	my $xmlperl = $self->modsdoc_to_values( $mods );
	$xmlperl = $self->mods_values_to_mods_slim( $xmlperl );

	for my $subject( @{$xmlperl->{subject}} ) {
		push @{$self->{master_doc}->{subject}}, $subject;
	}

	push( @{$self->{master_doc}->{type_of_resource}}, 
		$self->get_field_value( $mods, $resource_xpath ));

	if(!($self->{master_doc}->{isbn}) ) {
		$self->{master_doc}->{isbn} = 
			$self->get_field_value( $mods, $isbn_xpath );
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



