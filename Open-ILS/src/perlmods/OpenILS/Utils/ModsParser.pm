package OpenILS::Utils::ModsParser;
use strict; use warnings;

use OpenSRF::EX qw/:try/;
use XML::LibXML;
use XML::LibXSLT;
use Time::HiRes qw(time);
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::SettingsClient;
use Data::Dumper;

my $parser		= XML::LibXML->new();
my $xslt			= XML::LibXSLT->new();
my $mods_sheet;

# ----------------------------------------------------------------------------------------
# XPATH for extracting info from a MODS doc
my $isbn_xpath			= "//mods:mods/mods:identifier[\@type='isbn']";
my $resource_xpath	= "//mods:mods/mods:typeOfResource";
my $pub_xpath			= "//mods:mods/mods:originInfo//mods:dateIssued[\@encoding='marc']|" . 
								"//mods:mods/mods:originInfo//mods:dateIssued[1]";
my $tcn_xpath			= "//mods:mods/mods:recordInfo/mods:recordIdentifier";
my $publisher_xpath	= "//mods:mods/mods:originInfo//mods:publisher[1]";
my $edition_xpath		= "//mods:mods/mods:originInfo//mods:edition[1]";
my $abstract_xpath	= "//mods:mods/mods:abstract";
my $toc_xpath			= "";
my $related_xpath		= "";
my $online_loc_xpath = "(//mods:location/mods:url|//mods:location/mods:url/\@displayLabel)";

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

		topic => 
			"//mods:mods/mods:subject/*[local-name()!='geographicCode']/parent::mods:subject",

#		geographic => 
#			"//mods:mods/*[local-name()='subject']/*[local-name()='geographic']",
#		name => 
#			"//mods:mods/*[local-name()='subject']/*[local-name()='name']",
#		temporal => 
#			"//mods:mods/*[local-name()='subject']/*[local-name()='temporal']",
#		topic => 
#			"//mods:mods/*[local-name()='subject']/*[local-name()='topic']",
	},
	#keyword => { keyword => "//mods:mods/*[not(local-name()='originInfo')]", },

	series => {
		series => "//mods:mods/mods:relatedItem[\@type='series']/mods:titleInfo"
	}
};
# ----------------------------------------------------------------------------------------



sub new { return bless( {}, shift() ); }

sub get_field_value {

	my( $self, $mods, $xpath ) = @_;

	my @string;
	my $root = $mods->documentElement;
	$root->setNamespace( "http://www.loc.gov/mods/v3", "mods", 1 );

	# grab the set of matching nodes
	my @nodes = $root->findnodes( $xpath );
	for my $value (@nodes) {

		# grab all children of the node
		my @children = $value->childNodes();
		my @child_text;
		for my $child (@children) {
			next unless( $child->nodeType != 3 );

			if($child->childNodes) {
				my @a;
				for my $c (@{$child->childNodes}){
					push @a, $c->textContent;
				}
				push(@child_text, join(' ', @a));

			} else {
				push(@child_text, $child->textContent); 
			}

		}
		if(@child_text) {
			push(@string, \@child_text);
		}

		if( !@child_text  ) {
			push(@string, $value->textContent );
		}
	}
	return @string;
}

=head
sub _modsdoc_to_values {
	my( $self, $mods ) = @_;
	my $data = {};
	for my $class (keys %$xpathset) {
		$data->{$class} = {};
		for my $type(keys %{$xpathset->{$class}}) {
			my @value = $self->get_field_value( $mods, $xpathset->{$class}->{$type} );
			if( $class eq "subject" ) {
				push( @{$data->{$class}->{$type}},  @value );
			} else {
				$data->{$class}->{$type} = $value[0];
			}
		}
	}
	return $data;
}
=cut

sub modsdoc_to_values {
	my( $self, $mods ) = @_;
	my $data = {};

	{
		my $class = "subject";
		$data->{$class} = {};
		for my $type(keys %{$xpathset->{$class}}) {
			my @value = $self->get_field_value( $mods, $xpathset->{$class}->{$type} );
			for my $arr (@value) {
				push( @{$data->{$class}->{$type}},  $arr);
			}
		}
	}

	{
		my $class = "title";
		$data->{$class} = {};
		for my $type(keys %{$xpathset->{$class}}) {
			my @value = $self->get_field_value( $mods, $xpathset->{$class}->{$type} );
			for my $arr (@value) {
				if( ref($arr) ) {
					$data->{$class}->{$type} = shift @$arr;
					$data->{$class}->{$type} = shift @$arr if (lc($data->{$class}->{$type}) =~ /^the|an?/o);
					for my $t (@$arr) {
						$data->{$class}->{$type} .= ' : ' if ($data->{$class}->{$type} =~ /\w\s*$/o);
						$data->{$class}->{$type} .= " $t";
					}
				} else {
					$data->{$class}->{$type} = $arr;
				}
			}
		}
	}

	{
		my $class = "author";
		$data->{$class} = {};
		for my $type(keys %{$xpathset->{$class}}) {
			my @value = $self->get_field_value( $mods, $xpathset->{$class}->{$type} );
			$data->{$class}->{$type} = $value[0];
		}
	}

	{
		my $class = "series";
		$data->{$class} = {};
		for my $type(keys %{$xpathset->{$class}}) {
			my @value = $self->get_field_value( $mods, $xpathset->{$class}->{$type} );
			for my $arr (@value) {
				if( ref($arr) ) {
					push(@{$data->{$class}->{$type}}, join(" ", @$arr));
				} else {
					push( @{$data->{$class}->{$type}}, $arr );
				}
			}
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
	my $series	= [];

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
	if(!$tmp) { $subject = {}; } 
	else {
		for my $key( keys %{$tmp}) {
			push(@$subject, @{$tmp->{$key}}) if ($tmp->{$key});
		}
		my $subh = {};
		for my $s (@$subject) {
			if(defined($subh->{$s})) { $subh->{$s->[0]}++ } else { $subh->{$s->[0]} = 1;}
		}
		$subject = $subh
	}

	$tmp = $modsperl->{'series'};
	if(!$tmp) { $series = []; }
	else { $series = $tmp->{'series'}; }


	return { series => $series, title => $title, 
			author => $author, subject => $subject };
}



# ---------------------------------------------------------------------------
# Initializes a MARC -> Unified MODS batch process
# ---------------------------------------------------------------------------

sub start_mods_batch {

	my( $self, $master_doc ) = @_;


	if(!$mods_sheet) {
		 my $xslt_doc = $parser->parse_file(
			OpenSRF::Utils::SettingsClient->new->config_value(dirs => 'xsl') .  "/MARC21slim2MODS3.xsl");
		$mods_sheet = $xslt->parse_stylesheet( $xslt_doc );
	}


	my $xmldoc = $parser->parse_string($master_doc);
	my $mods = $mods_sheet->transform($xmldoc);

#	warn "-" x 100 . "\n";
#	warn "MODS " . $mods->toString(1) . "\n";
#	warn "-" x 100 . "\n";

	$self->{master_doc} = $self->modsdoc_to_values( $mods );
	$self->{master_doc} = $self->mods_values_to_mods_slim( $self->{master_doc} );

	($self->{master_doc}->{isbn}) = 
		$self->get_field_value( $mods, $isbn_xpath );

	$self->{master_doc}->{type_of_resource} = 
		[ $self->get_field_value( $mods, $resource_xpath ) ];

	($self->{master_doc}->{tcn}) = 
		$self->get_field_value( $mods, $tcn_xpath );

	($self->{master_doc}->{pubdate}) = 
		$self->get_field_value( $mods, $pub_xpath );

	($self->{master_doc}->{publisher}) = 
		$self->get_field_value( $mods, $publisher_xpath );

	($self->{master_doc}->{edition}) =
		$self->get_field_value( $mods, $edition_xpath );



# ------------------------------
	# holds an array of [ link, title, link, title, ... ]
	$self->{master_doc}->{online_loc} = [];
	push(@{$self->{master_doc}->{online_loc}},
		$self->get_field_value( $mods, $online_loc_xpath ));

	($self->{master_doc}->{synopsis}) = 
		$self->get_field_value( $mods, $abstract_xpath );

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

	# for backwards compatibility, remove the array part when all is decided
	if(ref($xmlperl->{subject}) eq 'ARRAY' ) {
		for my $subject( @{$xmlperl->{subject}} ) {
			push @{$self->{master_doc}->{subject}}, $subject;
		}
	} else {
		for my $subject ( keys %{$xmlperl->{subject}} ) {
			my $s = $self->{master_doc}->{subject};
			if(defined($s->{$subject})) { $s->{$subject}++; } else { $s->{$subject} = 1; }
		}
	}

	push( @{$self->{master_doc}->{type_of_resource}}, 
		$self->get_field_value( $mods, $resource_xpath ));

	if(!($self->{master_doc}->{isbn}) ) {
		($self->{master_doc}->{isbn}) = 
			$self->get_field_value( $mods, $isbn_xpath );
	}
}


# ---------------------------------------------------------------------------
# Completes a MARC -> Unified MODS batch process and returns the perl hash
# ---------------------------------------------------------------------------
sub init_virtual_record {
	my $record = new Fieldmapper::metabib::virtual_record;
	$record->subject([]);
	$record->types_of_resource([]);
	$record->call_numbers([]);
	return $record;
}

sub finish_mods_batch {
	my $self = shift;
	my $perl = $self->{master_doc};
	my $record = init_virtual_record();

	# turn the hash into a fieldmapper object
	(my $title = $perl->{title}) =~ s/\[.*?\]//og;
	(my $author = $perl->{author}) =~ s/\(.*?\)//og;

	my @series;
	for my $s (@{$perl->{series}}) {
		push @series, (split( /\s*;/, $s ))[0];
	}

	# uniquify the types of resource
	my $rtypes = $perl->{type_of_resource};
	my %hash = map { ($_ => 1) } @$rtypes;
	$rtypes = [ keys %hash ];

	$record->title($title);
	$record->author($author);

	$record->doc_id($perl->{doc_id});
	$record->isbn($perl->{isbn});
	$record->pubdate($perl->{pubdate});
	$record->publisher($perl->{publisher});
	$record->tcn($perl->{tcn});

	$record->edition($perl->{edition});

	$record->subject($perl->{subject});
	$record->types_of_resource($rtypes);
	$record->series(\@series);

	$record->online_loc($perl->{online_loc});
	$record->synopsis($perl->{synopsis});

	$self->{master_doc} = undef;
	return $record;
}



