package OpenILS::Application::SuperCat;

use strict;
use warnings;

# All OpenSRF applications must be based on OpenSRF::Application or
# a subclass thereof.  Makes sense, eh?
use OpenSRF::Application;
use base qw/OpenSRF::Application/;

# This is the client class, used for connecting to open-ils.storage
use OpenSRF::AppSession;

# This is an extention of Error.pm that supplies some error types to throw
use OpenSRF::EX qw(:try);

# This is a helper class for querying the OpenSRF Settings application ...
use OpenSRF::Utils::SettingsClient;

# ... and here we have the built in logging helper ...
use OpenSRF::Utils::Logger qw($logger);

# ... and this is our OpenILS object (en|de)coder and psuedo-ORM package.
use OpenILS::Utils::Fieldmapper;


# We'll be working with XML, so...
use XML::LibXML;
use XML::LibXSLT;
use Unicode::Normalize;

use JSON;

our (
  $_parser,
  $_xslt,
  %record_xslt,
  %metarecord_xslt,
  %holdings_data_cache,
);

sub child_init {
	# we need an XML parser
	$_parser = new XML::LibXML;

	# and an xslt parser
	$_xslt = new XML::LibXSLT;
	
	# parse the MODS xslt ...
	my $mods3_xslt = $_parser->parse_file(
		OpenSRF::Utils::SettingsClient
			->new
			->config_value( dirs => 'xsl' ).
		"/MARC21slim2MODS3.xsl"
	);
	# and stash a transformer
	$record_xslt{mods3}{xslt} = $_xslt->parse_stylesheet( $mods3_xslt );
	$record_xslt{mods3}{namespace_uri} = 'http://www.loc.gov/mods/v3';
	$record_xslt{mods3}{docs} = 'http://www.loc.gov/mods/';
	$record_xslt{mods3}{schema_location} = 'http://www.loc.gov/standards/mods/v3/mods-3-1.xsd';

	# parse the MODS xslt ...
	my $mods_xslt = $_parser->parse_file(
		OpenSRF::Utils::SettingsClient
			->new
			->config_value( dirs => 'xsl' ).
		"/MARC21slim2MODS.xsl"
	);
	# and stash a transformer
	$record_xslt{mods}{xslt} = $_xslt->parse_stylesheet( $mods_xslt );
	$record_xslt{mods}{namespace_uri} = 'http://www.loc.gov/mods/';
	$record_xslt{mods}{docs} = 'http://www.loc.gov/mods/';
	$record_xslt{mods}{schema_location} = 'http://www.loc.gov/standards/mods/mods.xsd';

	# parse the ATOM entry xslt ...
	my $atom_xslt = $_parser->parse_file(
		OpenSRF::Utils::SettingsClient
			->new
			->config_value( dirs => 'xsl' ).
		"/MARC21slim2ATOM.xsl"
	);
	# and stash a transformer
	$record_xslt{atom}{xslt} = $_xslt->parse_stylesheet( $atom_xslt );
	$record_xslt{atom}{namespace_uri} = 'http://www.w3.org/2005/Atom';
	$record_xslt{atom}{docs} = 'http://www.ietf.org/rfc/rfc4287.txt';

	# parse the RDFDC xslt ...
	my $rdf_dc_xslt = $_parser->parse_file(
		OpenSRF::Utils::SettingsClient
			->new
			->config_value( dirs => 'xsl' ).
		"/MARC21slim2RDFDC.xsl"
	);
	# and stash a transformer
	$record_xslt{rdf_dc}{xslt} = $_xslt->parse_stylesheet( $rdf_dc_xslt );
	$record_xslt{rdf_dc}{namespace_uri} = 'http://purl.org/dc/elements/1.1/';
	$record_xslt{rdf_dc}{schema_location} = 'http://purl.org/dc/elements/1.1/';

	# parse the SRWDC xslt ...
	my $srw_dc_xslt = $_parser->parse_file(
		OpenSRF::Utils::SettingsClient
			->new
			->config_value( dirs => 'xsl' ).
		"/MARC21slim2SRWDC.xsl"
	);
	# and stash a transformer
	$record_xslt{srw_dc}{xslt} = $_xslt->parse_stylesheet( $srw_dc_xslt );
	$record_xslt{srw_dc}{namespace_uri} = 'info:srw/schema/1/dc-schema';
	$record_xslt{srw_dc}{schema_location} = 'http://www.loc.gov/z3950/agency/zing/srw/dc-schema.xsd';

	# parse the OAIDC xslt ...
	my $oai_dc_xslt = $_parser->parse_file(
		OpenSRF::Utils::SettingsClient
			->new
			->config_value( dirs => 'xsl' ).
		"/MARC21slim2OAIDC.xsl"
	);
	# and stash a transformer
	$record_xslt{oai_dc}{xslt} = $_xslt->parse_stylesheet( $oai_dc_xslt );
	$record_xslt{oai_dc}{namespace_uri} = 'http://www.openarchives.org/OAI/2.0/oai_dc/';
	$record_xslt{oai_dc}{schema_location} = 'http://www.openarchives.org/OAI/2.0/oai_dc.xsd';

	# parse the RSS xslt ...
	my $rss_xslt = $_parser->parse_file(
		OpenSRF::Utils::SettingsClient
			->new
			->config_value( dirs => 'xsl' ).
		"/MARC21slim2RSS2.xsl"
	);
	# and stash a transformer
	$record_xslt{rss2}{xslt} = $_xslt->parse_stylesheet( $rss_xslt );

	register_record_transforms();

	return 1;
}

sub register_record_transforms {
	for my $type ( keys %record_xslt ) {
		__PACKAGE__->register_method(
			method    => 'retrieve_record_transform',
			api_name  => "open-ils.supercat.record.$type.retrieve",
			api_level => 1,
			argc      => 1,
			signature =>
				{ desc     => "Returns the \U$type\E representation ".
				              "of the requested bibliographic record",
				  params   =>
			  		[
						{ name => 'bibId',
						  desc => 'An OpenILS biblio::record_entry id',
						  type => 'number' },
					],
			  	'return' =>
		  			{ desc => "The bib record in \U$type\E",
					  type => 'string' }
				}
		);
	}
}


sub entityize {
	my $stuff = NFC(shift());
	$stuff =~ s/([\x{0080}-\x{fffd}])/sprintf('&#x%X;',ord($1))/sgoe;
	return $stuff;
}

sub tree_walker {
	my $tree = shift;
	my $field = shift;
	my $filter = shift;

	my @things = $filter->($tree);
	for my $v ( @{$tree->$field} ){
		push @things, $filter->($v);
		push @things, tree_walker($v, $field, $filter);
	}
	return @things
}

sub cn_browse {
	my $self = shift;
	my $client = shift;

	my $label = shift;
	my $ou = shift;
	my $page_size = shift || 9;
	my $page = shift || 0;

	my ($before_limit,$after_limit) = (0,0);
	my ($before_offset,$after_offset) = (0,0);

	if (!$page) {
		$before_limit = $after_limit = int($page_size / 2);
		$after_limit += 1 if ($page_size % 2);
	} else {
		$before_offset = $after_offset = int($page_size / 2);
		$before_offset += 1 if ($page_size % 2);
		$before_limit = $after_limit = $page_size;
	}

	my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );

	my $o_search = { shortname => $ou };
	if (!$ou || $ou eq '-') {
		$o_search = { parent_ou => undef };
	}

	my $orgs = $_storage->request(
		"open-ils.cstore.direct.actor.org_unit.search",
		$o_search,
		{ flesh		=> 3,
		  flesh_fields	=> { aou	=> [qw/children/] }
		}
	)->gather(1);

	my @ou_ids = tree_walker($orgs, 'children', sub {shift->id});

	$logger->debug("Searching for CNs at orgs [".join(',',@ou_ids)."], based on $ou");

	my @list = ();

	if ($page <= 0) {
		my $before = $_storage->request(
			"open-ils.cstore.direct.asset.call_number.search.atomic",
			{ label		=> { "<" => { transform => "upper", value => ["upper", $label] } },
			  owning_lib	=> \@ou_ids,
			},
			{ flesh		=> 1,
			  flesh_fields	=> { acn => [qw/record owning_lib/] },
			  order_by	=> { acn => "upper(label) desc, id desc, owning_lib desc" },
			  limit		=> $before_limit,
			  offset	=> abs($page) * $page_size - $before_offset,
			}
		)->gather(1);
		push @list, reverse(@$before);
	}

	if ($page >= 0) {
		my $after = $_storage->request(
			"open-ils.cstore.direct.asset.call_number.search.atomic",
			{ label		=> { ">=" => { transform => "upper", value => ["upper", $label] } },
			  owning_lib	=> \@ou_ids,
			},
			{ flesh		=> 1,
			  flesh_fields	=> { acn => [qw/record owning_lib/] },
			  order_by	=> { acn => "upper(label), id, owning_lib" },
			  limit		=> $after_limit,
			  offset	=> abs($page) * $page_size - $after_offset,
			}
		)->gather(1);
		push @list, @$after;
	}

	return \@list;
}
__PACKAGE__->register_method(
	method    => 'cn_browse',
	api_name  => 'open-ils.supercat.call_number.browse',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => <<"		  DESC",
Returns the XML representation of the requested bibliographic record's holdings
		  DESC
		  params   =>
		  	[
				{ name => 'label',
				  desc => 'The target call number lable',
				  type => 'string' },
				{ name => 'org_unit',
				  desc => 'The org unit shortname (or "-" or undef for global) to browse',
				  type => 'string' },
				{ name => 'page_size',
				  desc => 'Count of call numbers to retrieve, default is 9',
				  type => 'number' },
				{ name => 'page',
				  desc => 'The page of call numbers to retrieve, calculated based on page_size.  Can be positive, negative or 0.',
				  type => 'number' },
			],
		  'return' =>
		  	{ desc => 'Call numbers with owning_lib and record fleshed',
			  type => 'array' }
		}
);


sub new_record_holdings {
	my $self = shift;
	my $client = shift;
	my $bib = shift;
	my $ou = shift;

	my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );

	my $tree = $_storage->request(
		"open-ils.cstore.direct.biblio.record_entry.retrieve",
		$bib,
		{ flesh		=> 5,
		  flesh_fields	=> {
					bre	=> [qw/call_numbers/],
		  			acn	=> [qw/copies owning_lib/],
					acp	=> [qw/location status circ_lib stat_cat_entries notes/],
					asce	=> [qw/stat_cat/],
				}
		}
	)->gather(1);

	my $o_search = { shortname => $ou };
	if (!$ou || $ou eq '-') {
		$o_search = { parent_ou => undef };
	}

	my $orgs = $_storage->request(
		"open-ils.cstore.direct.actor.org_unit.search",
		$o_search,
		{ flesh		=> 3,
		  flesh_fields	=> { aou	=> [qw/children/] }
		}
	)->gather(1);

	my @ou_ids = tree_walker($orgs, 'children', sub {shift->id});

	$logger->debug("Searching for holdings at orgs [".join(',',@ou_ids)."], based on $ou");

	my ($year,$month,$day) = reverse( (localtime)[3,4,5] );
	$year += 1900;
	$month += 1;

	my $xml = "<hold:volumes xmlns:hold='http://open-ils.org/spec/holdings/v1'>";

	for my $cn (@{$tree->call_numbers}) {

		my $found = 0;
		for my $c (@{$cn->copies}) {
			next unless grep {$c->circ_lib->id == $_} @ou_ids;
			$found = 1;
		}
		next unless $found;

		(my $cn_class = $cn->class_name) =~ s/::/-/gso;
		$cn_class =~ s/Fieldmapper-//gso;
		my $cn_tag = sprintf("tag:open-ils.org,$year-\%0.2d-\%0.2d:$cn_class/".$cn->id, $month, $day);

		my $cn_lib = $cn->owning_lib->shortname;

		my $cn_label = $cn->label;

		$xml .= "<hold:volume id='$cn_tag' lib='$cn_lib' label='$cn_label'><hold:copies>";
		
		for my $cp (@{$cn->copies}) {

			next unless grep { $cp->circ_lib->id == $_ } @ou_ids;

			(my $cp_class = $cp->class_name) =~ s/::/-/gso;
			$cp_class =~ s/Fieldmapper-//gso;
			my $cp_tag = sprintf("tag:open-ils.org,$year-\%0.2d-\%0.2d:$cp_class/".$cp->id, $month, $day);

			my $cp_stat = $cp->status->name;

			my $cp_loc = $cp->location->name;

			my $cp_lib = $cp->circ_lib->shortname;

			my $cp_bc = $cp->barcode;

			$xml .= "<hold:copy id='$cp_tag' barcode='$cp_bc'><hold:status>$cp_stat</hold:status>".
				"<hold:location>$cp_loc</hold:location><hold:circlib>$cp_lib</hold:circlib><hold:notes>";

			#if ($cp->notes) {
			#	for my $note ( @{$cp->notes} ) {
			#		next unless ( $sce->stat_cat->pub eq 't' );
			#		$xml .= sprintf('<hold:note date="%s" title="%s">%s</hold:note>',$note->create_date, escape($note->title), escape($note->value));
			#	}
			#}

			$xml .= "</hold:notes><hold:statcats>";

			if ($cp->stat_cat_entries) {
				for my $sce ( @{$cp->stat_cat_entries} ) {
					next unless ( $sce->stat_cat->opac_visible eq 't' );
					$xml .= sprintf('<hold:statcat name="%s">%s</hold:statcat>',escape($sce->stat_cat->name) ,escape($sce->value));
				}
			}

			$xml .= "</hold:statcats></hold:copy>";
		}
		
		$xml .= "</hold:copies></hold:volume>";
	}

	$xml .= "</hold:volumes>";

	return $xml;
}
__PACKAGE__->register_method(
	method    => 'new_record_holdings',
	api_name  => 'open-ils.supercat.record.holdings_xml.retrieve',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => <<"		  DESC",
Returns the XML representation of the requested bibliographic record's holdings
		  DESC
		  params   =>
		  	[
				{ name => 'bibId',
				  desc => 'An OpenILS biblio::record_entry id',
				  type => 'number' },
			],
		  'return' =>
		  	{ desc => 'The bib record holdings hierarchy in XML',
			  type => 'string' }
		}
);



sub record_holdings {
	my $self = shift;
	my $client = shift;
	my $bib = shift;

	my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );

	if (!$holdings_data_cache{status}) {
		$holdings_data_cache{status} = {
			map { ($_->id => $_) } @{ $_storage->request( "open-ils.cstore.direct.config.copy_status.search.atomic", {id => {'<>' => undef}} )->gather(1) }
		};
		$holdings_data_cache{location} = {
			map { ($_->id => $_) } @{ $_storage->request( "open-ils.cstore.direct.asset.copy_location.retrieve.all.atomic", {id => {'<>' => undef}} )->gather(1) }
		};
		$holdings_data_cache{ou} =
		{
			map {
				($_->id => $_)
			} @{$_storage->request( "open-ils.cstore.direct.actor.org_unit.search.atomic" => { id => { '<>' => undef } } )->gather(1)}
		};
		$holdings_data_cache{statcat} =
		{
			map {
				($_->id => $_)
			} @{$_storage->request( "open-ils.cstore.direct.asset.stat_cat_entry.search.atomic" => { id => { '<>' => undef } } )->gather(1)}
		};
	}


	my ($year,$month,$day) = reverse( (localtime)[3,4,5] );
	$year += 1900;
	$month += 1;

	my $xml = "<volumes xmlns='http://open-ils.org/spec/holdings/v1'>";
	
	for my $cn ( @{$_storage->request( "open-ils.cstore.direct.asset.call_number.search.atomic" => {record => $bib} )->gather(1)} ) {
		(my $cn_class = $cn->class_name) =~ s/::/-/gso;
		$cn_class =~ s/Fieldmapper-//gso;
		my $cn_tag = sprintf("tag:open-ils.org,$year-\%0.2d-\%0.2d:$cn_class/".$cn->id, $month, $day);

		my $cn_lib = $holdings_data_cache{ou}{$cn->owning_lib}->shortname;

		my $cn_label = $cn->label;

		$xml .= "<volume id='$cn_tag' lib='$cn_lib' label='$cn_label'><copies>";
		
		for my $cp ( @{$_storage->request( "open-ils.cstore.direct.asset.copy.search.atomic" => {call_number => $cn->id} )->gather(1)} ) {
			(my $cp_class = $cn->class_name) =~ s/::/-/gso;
			$cp_class =~ s/Fieldmapper-//gso;
			my $cp_tag = sprintf("tag:open-ils.org,$year-\%0.2d-\%0.2d:$cp_class/".$cp->id, $month, $day);

			my $cp_stat = $holdings_data_cache{status}{$cp->status}->name;

			my $cp_loc = $holdings_data_cache{location}{$cp->location}->name;

			my $cp_lib = $holdings_data_cache{ou}{$cp->circ_lib}->shortname;

			my $cp_bc = $cp->barcode;

			$xml .= "<copy id='$cp_tag' barcode='$cp_bc'><status>$cp_stat</status><location>$cp_loc</location><circlib>$cp_lib</circlib><notes>";

			for my $note ( @{$_storage->request( "open-ils.cstore.direct.asset.copy_note.search.atomic" => {id => $cp->id, pub => "t" })->gather(1)} ) {
				$xml .= sprintf('<note date="%s" title="%s">%s</note>',$note->create_date, escape($note->title), escape($note->value));
			}

			$xml .= "</notes><statcats>";

			for my $sce ( @{$_storage->request( "open-ils.cstore.direct.asset.stat_cat_entry_copy_map.search.atomic" => { owning_copy => $cp->id })->gather(1)} ) {
				my $sc = $holdings_data_cache{statcat}{$sce->stat_cat_entry};
				$xml .= sprintf('<statcat>%s</statcat>',escape($sc->value));
			}

			$xml .= "</statcats></copy>";
		}
		
		$xml .= "</volume>";
	}

	$xml .= "</volumes>";

	return $xml;
}

sub escape {
	my $text = shift;
	$text =~ s/&/&amp;/gsom;
	$text =~ s/</&lt;/gsom;
	$text =~ s/>/&gt;/gsom;
	$text =~ s/"/\\"/gsom;
	return $text;
}

sub recent_changes {
	my $self = shift;
	my $client = shift;
	my $when = shift;
	my $limit = shift;

	if (!$when) {
		my ($d,$m,$y) = (localtime)[4,5,6];
		$when = sprintf('%4d-%02d-%02d', $y + 1900, $m + 1, $d);
	}

	my $type = 'biblio';
	$type = 'authority' if ($self->api_name =~ /authority/o);

	my $axis = 'create_date';
	$axis = 'edit_date' if ($self->api_name =~ /edit/o);

	my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );

	return $_storage
		->request(
			"open-ils.cstore.direct.$type.record_entry.id_list.atomic",
			{ $axis => { ">" => $when } },
			{ order_by => "$axis desc", limit => $limit } )
		->gather(1);
}

for my $t ( qw/biblio authority/ ) {
	for my $a ( qw/import edit/ ) {

		__PACKAGE__->register_method(
			method    => 'recent_changes',
			api_name  => "open-ils.supercat.$t.record.$a.recent",
			api_level => 1,
			argc      => 0,
			signature =>
				{ desc     => "Returns a list of recently ${a}ed $t records",
		  		  params   =>
		  			[
						{ name => 'when',
				  		  desc => "Date to start looking for ${a}ed records",
				  		  default => 'today',
				  		  type => 'string' },

						{ name => 'limit',
				  		  desc => "Maximum count to retrieve",
				  		  type => 'number' },
					],
		  		  'return' =>
		  			{ desc => "An id list of $t records",
			  		  type => 'array' }
				},
		);
	}
}


sub retrieve_record_marcxml {
	my $self = shift;
	my $client = shift;
	my $rid = shift;

	my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );

	return
	entityize(
		$_storage
			->request( 'open-ils.cstore.direct.biblio.record_entry.retrieve' => $rid )
			->gather(1)
			->marc
	);
}

__PACKAGE__->register_method(
	method    => 'retrieve_record_marcxml',
	api_name  => 'open-ils.supercat.record.marcxml.retrieve',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => <<"		  DESC",
Returns the MARCXML representation of the requested bibliographic record
		  DESC
		  params   =>
		  	[
				{ name => 'bibId',
				  desc => 'An OpenILS biblio::record_entry id',
				  type => 'number' },
			],
		  'return' =>
		  	{ desc => 'The bib record in MARCXML',
			  type => 'string' }
		}
);

sub retrieve_record_transform {
	my $self = shift;
	my $client = shift;
	my $rid = shift;

	(my $transform = $self->api_name) =~ s/^.+record\.([^\.]+)\.retrieve$/$1/o;

	my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );
	$_storage->connect;

	warn "Fetching record entry $rid\n";
	my $marc = $_storage->request(
		'open-ils.cstore.direct.biblio.record_entry.retrieve',
		$rid
	)->gather(1)->marc;
	warn "Fetched record entry $rid\n";

	$_storage->disconnect;

	return entityize($record_xslt{$transform}{xslt}->transform( $_parser->parse_string( $marc ) )->toString);
}


sub retrieve_metarecord_mods {
	my $self = shift;
	my $client = shift;
	my $rid = shift;

	my $_storage = OpenSRF::AppSession->connect( 'open-ils.cstore' );

	# Get the metarecord in question
	my $mr =
	$_storage->request(
		'open-ils.cstore.direct.metabib.metarecord.retrieve' => $rid
	)->gather(1);

	# Now get the map of all bib records for the metarecord
	my $recs =
	$_storage->request(
		'open-ils.cstore.direct.metabib.metarecord_source_map.search.atomic',
		{metarecord => $rid}
	)->gather(1);

	$logger->debug("Adding ".scalar(@$recs)." bib record to the MODS of the metarecord");

	# and retrieve the lead (master) record as MODS
	my ($master) =
		$self	->method_lookup('open-ils.supercat.record.mods.retrieve')
			->run($mr->master_record);
	my $master_mods = $_parser->parse_string($master)->documentElement;
	$master_mods->setNamespace( "http://www.loc.gov/mods/", "mods", 1 );

	# ... and a MODS clone to populate, with guts removed.
	my $mods = $_parser->parse_string($master)->documentElement;
	$mods->setNamespace( "http://www.loc.gov/mods/", "mods", 1 );
	($mods) = $mods->findnodes('//mods:mods');
	$mods->removeChildNodes;

	# Add the metarecord ID as a (locally defined) info URI
	my $recordInfo = $mods
		->ownerDocument
		->createElement("mods:recordInfo");

	my $recordIdentifier = $mods
		->ownerDocument
		->createElement("mods:recordIdentifier");

	my ($year,$month,$day) = reverse( (localtime)[3,4,5] );
	$year += 1900;
	$month += 1;

	my $id = $mr->id;
	$recordIdentifier->appendTextNode(
		sprintf("tag:open-ils.org,$year-\%0.2d-\%0.2d:metabib-metarecord/$id", $month, $day)
	);

	$recordInfo->appendChild($recordIdentifier);
	$mods->appendChild($recordInfo);

	# Grab the title, author and ISBN for the master record and populate the metarecord
	my ($title) = $master_mods->findnodes( './mods:titleInfo[not(@type)]' );
	
	if ($title) {
		$title->setNamespace( "http://www.loc.gov/mods/", "mods", 1 );
		$title = $mods->ownerDocument->importNode($title);
		$mods->appendChild($title);
	}

	my ($author) = $master_mods->findnodes( './mods:name[mods:role/mods:text[text()="creator"]]' );
	if ($author) {
		$author->setNamespace( "http://www.loc.gov/mods/", "mods", 1 );
		$author = $mods->ownerDocument->importNode($author);
		$mods->appendChild($author);
	}

	my ($isbn) = $master_mods->findnodes( './mods:identifier[@type="isbn"]' );
	if ($isbn) {
		$isbn->setNamespace( "http://www.loc.gov/mods/", "mods", 1 );
		$isbn = $mods->ownerDocument->importNode($isbn);
		$mods->appendChild($isbn);
	}

	# ... and loop over the constituent records
	for my $map ( @$recs ) {

		# get the MODS
		my ($rec) =
			$self	->method_lookup('open-ils.supercat.record.mods.retrieve')
				->run($map->source);

		my $part_mods = $_parser->parse_string($rec);
		$part_mods->documentElement->setNamespace( "http://www.loc.gov/mods/", "mods", 1 );
		($part_mods) = $part_mods->findnodes('//mods:mods');

		for my $node ( ($part_mods->findnodes( './mods:subject' )) ) {
			$node->setNamespace( "http://www.loc.gov/mods/", "mods", 1 );
			$node = $mods->ownerDocument->importNode($node);
			$mods->appendChild( $node );
		}

		my $relatedItem = $mods
			->ownerDocument
			->createElement("mods:relatedItem");

		$relatedItem->setAttribute( type => 'constituent' );

		my $identifier = $mods
			->ownerDocument
			->createElement("mods:identifier");

		$identifier->setAttribute( type => 'uri' );

		my $subRecordInfo = $mods
			->ownerDocument
			->createElement("mods:recordInfo");

		my $subRecordIdentifier = $mods
			->ownerDocument
			->createElement("mods:recordIdentifier");

		my $subid = $map->source;
		$subRecordIdentifier->appendTextNode(
			sprintf("tag:open-ils.org,$year-\%0.2d-\%0.2d:biblio-record_entry/$subid",
				$month,
				$day
			)
		);
		$subRecordInfo->appendChild($subRecordIdentifier);

		$relatedItem->appendChild( $subRecordInfo );

		my ($tor) = $part_mods->findnodes( './mods:typeOfResource' );
		$tor->setNamespace( "http://www.loc.gov/mods/", "mods", 1 ) if ($tor);
		$tor = $mods->ownerDocument->importNode($tor) if ($tor);
		$relatedItem->appendChild($tor) if ($tor);

		if ( my ($part_isbn) = $part_mods->findnodes( './mods:identifier[@type="isbn"]' ) ) {
			$part_isbn->setNamespace( "http://www.loc.gov/mods/", "mods", 1 );
			$part_isbn = $mods->ownerDocument->importNode($part_isbn);
			$relatedItem->appendChild( $part_isbn );

			if (!$isbn) {
				$isbn = $mods->appendChild( $part_isbn->cloneNode(1) );
			}
		}

		$mods->appendChild( $relatedItem );

	}

	$_storage->disconnect;

	return entityize($mods->toString);

}
__PACKAGE__->register_method(
	method    => 'retrieve_metarecord_mods',
	api_name  => 'open-ils.supercat.metarecord.mods.retrieve',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => <<"		  DESC",
Returns the MODS representation of the requested metarecord
		  DESC
		  params   =>
		  	[
				{ name => 'metarecordId',
				  desc => 'An OpenILS metabib::metarecord id',
				  type => 'number' },
			],
		  'return' =>
		  	{ desc => 'The metarecord in MODS',
			  type => 'string' }
		}
);

sub list_metarecord_formats {
	my @list = (
		{ mods =>
			{ namespace_uri	  => 'http://www.loc.gov/mods/',
			  docs		  => 'http://www.loc.gov/mods/',
			  schema_location => 'http://www.loc.gov/standards/mods/mods.xsd',
			}
		}
	);

	for my $type ( keys %metarecord_xslt ) {
		push @list,
			{ $type => 
				{ namespace_uri	  => $metarecord_xslt{$type}{namespace_uri},
				  docs		  => $metarecord_xslt{$type}{docs},
				  schema_location => $metarecord_xslt{$type}{schema_location},
				}
			};
	}

	return \@list;
}
__PACKAGE__->register_method(
	method    => 'list_metarecord_formats',
	api_name  => 'open-ils.supercat.metarecord.formats',
	api_level => 1,
	argc      => 0,
	signature =>
		{ desc     => <<"		  DESC",
Returns the list of valid metarecord formats that supercat understands.
		  DESC
		  'return' =>
		  	{ desc => 'The format list',
			  type => 'array' }
		}
);


sub list_record_formats {
	my @list = (
		{ marcxml =>
			{ namespace_uri	  => 'http://www.loc.gov/MARC21/slim',
			  docs		  => 'http://www.loc.gov/marcxml/',
			  schema_location => 'http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd',
			}
		}
	);

	for my $type ( keys %record_xslt ) {
		push @list,
			{ $type => 
				{ namespace_uri	  => $record_xslt{$type}{namespace_uri},
				  docs		  => $record_xslt{$type}{docs},
				  schema_location => $record_xslt{$type}{schema_location},
				}
			};
	}

	return \@list;
}
__PACKAGE__->register_method(
	method    => 'list_record_formats',
	api_name  => 'open-ils.supercat.record.formats',
	api_level => 1,
	argc      => 0,
	signature =>
		{ desc     => <<"		  DESC",
Returns the list of valid record formats that supercat understands.
		  DESC
		  'return' =>
		  	{ desc => 'The format list',
			  type => 'array' }
		}
);


sub oISBN {
	my $self = shift;
	my $client = shift;
	my $isbn = shift;

	throw OpenSRF::EX::InvalidArg ('I need an ISBN please')
		unless (length($isbn) >= 10);

	my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );

	# Create a storage session, since we'll be making muliple requests.
	$_storage->connect;

	# Find the record that has that ISBN.
	my $bibrec = $_storage->request(
		'open-ils.cstore.direct.metabib.full_rec.search.atomic',
		{ tag => '020', subfield => 'a', value => { ilike => $isbn.'%'} }
	)->gather(1);

	# Go away if we don't have one.
	return {} unless (@$bibrec);

	# Find the metarecord for that bib record.
	my $mr = $_storage->request(
		'open-ils.cstore.direct.metabib.metarecord_source_map.search.atomic',
		{source => $bibrec->[0]->record}
	)->gather(1);

	# Find the other records for that metarecord.
	my $records = $_storage->request(
		'open-ils.cstore.direct.metabib.metarecord_source_map.search.atomic',
		{metarecord => $mr->[0]->metarecord}
	)->gather(1);

	# Just to be safe.  There's currently no unique constraint on sources...
	my %unique_recs = map { ($_->source, 1) } @$records;
	my @rec_list = sort keys %unique_recs;

	# And now fetch the ISBNs for thos records.
	my $recs = $_storage->request(
		'open-ils.cstore.direct.metabib.full_rec.search.atomic',
		{ tag => '020', subfield => 'a', record => \@rec_list }
	)->gather(1);

	# We're done with the storage server session.
	$_storage->disconnect;

	# Return the oISBN data structure.  This will be XMLized at a higher layer.
	return
		{ metarecord => $mr->[0]->metarecord,
		  record_list => { map { ($_->record, $_->value) } @$recs } };

}
__PACKAGE__->register_method(
	method    => 'oISBN',
	api_name  => 'open-ils.supercat.oisbn',
	api_level => 1,
	argc      => 1,
	signature =>
		{ desc     => <<"		  DESC",
Returns the ISBN list for the metarecord of the requested isbn
		  DESC
		  params   =>
		  	[
				{ name => 'isbn',
				  desc => 'An ISBN.  Duh.',
				  type => 'string' },
			],
		  'return' =>
		  	{ desc => 'record to isbn map',
			  type => 'object' }
		}
);

1;
