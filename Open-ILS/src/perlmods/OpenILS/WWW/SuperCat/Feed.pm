package OpenILS::WWW::SuperCat::Feed;
use strict; use warnings;
use vars qw/$parser/;
use OpenSRF::EX qw(:try);
use XML::LibXML;
use XML::LibXSLT;
use OpenSRF::Utils::SettingsClient;
use CGI;
use DateTime;
use DateTime::Format::Mail;


sub exists {
	my $class = shift;
	my $type = shift;

	return 1 if UNIVERSAL::can("OpenILS::WWW::SuperCat::Feed::$type" => 'new');
	return 0;
}

sub new {
	my $class = shift;
	my $type = shift;
	if ($type) {
		$class .= '::'.$type;
		return $class->new;
	}
	throw OpenSRF::EX::ERROR ("I need a feed type!") ;
}

sub build {
	my $class = shift;
	my $xml = shift;
	return undef unless $xml;

	$parser = new XML::LibXML if (!$parser);

	my $self = { doc => $parser->parse_string($xml), items => [] };

	$self = bless $self => $class;
	$self->{count} = 0;
	return $self;
}

sub type {
	my $self = shift;
	my $type = shift;
	$self->{type} = $type if ($type);
	return $self->{type};
}

sub count {
	my $self = shift;
	return $self->{count};
}

sub search {
	my $self = shift;
	my $search = shift;
	$self->{search} = $search if ($search);
	return $self->{search};
}

sub class {
	my $self = shift;
	my $search = shift;
	$self->{class} = $search if ($search);
	return $self->{class};
}

sub Sort {
	my $self = shift;
	my $search = shift;
	$self->{sort} = $search if ($search);
	return $self->{sort};
}

sub SortDir {
	my $self = shift;
	my $search = shift;
	$self->{sort_dir} = $search if ($search);
	return $self->{sort_dir};
}

sub lang {
	my $self = shift;
	my $search = shift;
	$self->{lang} = $search if ($search);
	return $self->{lang};
}

sub lib {
	my $self = shift;
	my $lib = shift;
	$self->{lib} = $lib if ($lib);
	return $self->{lib};
}

sub base {
	my $self = shift;
	my $base = shift;
	$self->{base} = $base if ($base);
	return $self->{base};
}

sub root {
	my $self = shift;
	my $root = shift;
	$self->{root} = $root if ($root);
	return $self->{root};
}

sub unapi {
	my $self = shift;
	my $unapi = shift;
	$self->{unapi} = $unapi if ($unapi);
	return $self->{unapi};
}

sub push_item {
	my $self = shift;
	$self->{count} += scalar(@_);
	push @{ $self->{items} }, @_;
}

sub items {
	my $self = shift;
	return @{ $self->{items} } if (wantarray);
	return $self->{items};
}

sub _add_node {
	my $self = shift;

	my $xpath = shift;
	my $new = shift;

	for my $node ($self->{doc}->findnodes($xpath)) {
		$node->appendChild($new);
		last;
	}
}

sub _create_node {
	my $self = shift;

	my $xpath = shift;
	my $ns = shift;
	my $name = shift;
	my $text = shift;
	my $attrs = shift;

	for my $node ($self->{doc}->findnodes($xpath)) {
		my $new = $self->{doc}->createElement($name) if (!$ns);
		$new = $self->{doc}->createElementNS($ns,$name) if ($ns);

		$new->appendChild( $self->{doc}->createTextNode( $text ) )
			if (defined $text);

		if (ref($attrs)) {
			for my $key (keys %$attrs) {
				next unless $$attrs{$key};
				$new->setAttribute( $key => $$attrs{$key} );
			}
		}

		$node->appendChild( $new );

		return $new;
	}
}

sub add_item {
	my $self = shift;
	my $class = ref($self) || $self;
	$class .= '::item';

	my $item_xml = shift;
	my $entry = $class->new($item_xml);
	return undef unless $entry;

	$entry->base($self->base);
	$entry->unapi($self->unapi);

	$self->push_item($entry);
	return $entry;
}

sub add_holdings {
	my $self = shift;
	my $holdings_xml = shift;

	return $self unless ($holdings_xml);

	$parser = new XML::LibXML if (!$parser);
	my $new_doc = $parser->parse_string($holdings_xml);

	for my $root ( $self->{doc}->findnodes($self->{holdings_xpath}) ) {
		$root->appendChild($new_doc->documentElement);
		last;
	}
	return $self;
}

sub composeDoc {
	my $self = shift;
	for my $root ( $self->{doc}->findnodes($self->{item_xpath}) ) {
		for my $item ( $self->items ) {
			$root->appendChild( $item->{doc}->documentElement );
		}
		last;
	}
}

sub toString {
	my $self = shift;
	$self->composeDoc;
	return $self->{doc}->toString(1);
}

sub id {};
sub link {};
sub title {};
sub update_ts {};
sub creator {};

#----------------------------------------------------------

package OpenILS::WWW::SuperCat::Feed::atom;
use base 'OpenILS::WWW::SuperCat::Feed';
use OpenSRF::Utils qw/:datetime/;

sub new {
	my $class = shift;
	my $self = $class->SUPER::build('<feed xmlns:atom="http://www.w3.org/2005/Atom"/>');
	$self->{doc}->documentElement->setNamespace('http://www.w3.org/2005/Atom', undef);
	$self->{doc}->documentElement->setNamespace('http://www.w3.org/2005/Atom', 'atom');
	$self->{type} = 'application/atom+xml';
	$self->{item_xpath} = '/atom:feed';
	return $self;
}

sub title {
	my $self = shift;
	my $text = shift;
	$self->_create_node('/atom:feed','http://www.w3.org/2005/Atom','title', $text);
}

sub update_ts {
	my $self = shift;
	# ATOM demands RFC-3339 compliant datetime formats
	my $text = shift || gmtime_ISO8601();
	$self->_create_node($self->{item_xpath},'http://www.w3.org/2005/Atom','updated', $text);
}

sub creator {
	my $self = shift;
	my $text = shift;
	$self->_create_node('/atom:feed','http://www.w3.org/2005/Atom','author');
	$self->_create_node('/atom:feed/atom:author', 'http://www.w3.org/2005/Atom','name', $text);
}

sub link {
	my $self = shift;
	my $type = shift;
	my $id = shift;
	my $mime = shift || "application/x-$type+xml";
	my $title = shift;

	$type = 'self' if ($type eq 'atom');

	$self->_create_node(
		$self->{item_xpath},
		'http://www.w3.org/2005/Atom',
		'link',
		undef,
		{ rel => $type,
		  href => $id,
		  title => $title,
		  type => $mime,
		}
	);
}

sub id {
	my $self = shift;
	my $id = shift;

	$self->_create_node( $self->{item_xpath}, 'http://www.w3.org/2005/Atom', 'id', $id );
}

package OpenILS::WWW::SuperCat::Feed::atom::item;
use base 'OpenILS::WWW::SuperCat::Feed::atom';

sub new {
	my $class = shift;
	my $xml = shift;
	my $self = $class->SUPER::build($xml);
	$self->{doc}->documentElement->setNamespace('http://www.w3.org/2005/Atom', undef);
	$self->{doc}->documentElement->setNamespace('http://www.w3.org/2005/Atom', 'atom');
	$self->{item_xpath} = '/atom:entry';
	$self->{holdings_xpath} = '/atom:entry';
	$self->{type} = 'application/atom+xml';
	return $self;
}


#----------------------------------------------------------

package OpenILS::WWW::SuperCat::Feed::rss2;
use base 'OpenILS::WWW::SuperCat::Feed';

sub new {
	my $class = shift;
	my $self = $class->SUPER::build('<rss version="2.0"><channel/></rss>');
	$self->{type} = 'application/rss+xml';
	$self->{item_xpath} = '/rss/channel';
	return $self;
}

sub title {
	my $self = shift;
	my $text = shift;
	$self->_create_node('/rss/channel',undef,'title', $text);
	# RSS2 demands a /channel/description element; just dupe title until we give
	# users the ability to provide a description for their bookbags
	$self->_create_node('/rss/channel',undef,'description', $text);
}

sub update_ts {
	my $self = shift;
	# RSS2 demands RFC-822 compliant datetime formats
	my $text = shift || DateTime::Format::Mail->format_datetime(DateTime->now());
	$self->_create_node($self->{item_xpath},undef,'lastBuildDate', $text);
}

sub creator {
	my $self = shift;
	my $text = shift;
	$self->_create_node('/rss/channel', undef,'generator', $text);
}

sub link {
	my $self = shift;
	my $type = shift;
	my $id = shift;
	my $mime = shift || "application/x-$type+xml";

	if ($type eq 'rss2' or $type eq 'alternate') {
		# Just link to ourself using standard RSS2 link element
		$self->_create_node(
			$self->{item_xpath},
			undef,
			'link',
			$id,
			undef
		);
	} else {
		# Alternate link: use XHTML link element
		$self->_create_node(
			$self->{item_xpath},
			'http://www.w3.org/1999/xhtml',
			'xhtml:link',
			$id,
			{ rel => $type,
			  type => $mime,
			}
		);
	}
}

sub id {
	my $self = shift;
	my $id = shift;

	$self->_create_node($self->{item_xpath}, undef,'guid', $id);
}

package OpenILS::WWW::SuperCat::Feed::rss2::item;
use base 'OpenILS::WWW::SuperCat::Feed::rss2';

sub new {
	my $class = shift;
	my $xml = shift;
	my $self = $class->SUPER::build($xml);
	$self->{type} = 'application/rss+xml';
	$self->{item_xpath} = '/item';
	$self->{holdings_xpath} = '/item';
	return $self;
}

sub update_ts {
	my $self = shift;
	# RSS2 demands RFC-822 compliant datetime formats
	my $text = shift;
	if (!$text) {
		# No date passed in, default to now
		$text = DateTime::Format::Mail->format_datetime(DateTime->now());
	} elsif ($text =~ m/^\s*(\d{4})\.?\s*$/o) {
		# Publication date is just a year, convert accordingly
		my $year = DateTime->new(year=>$1);
		$text = DateTime::Format::Mail->format_datetime($year);
	}
	$self->_create_node($self->{item_xpath},undef,'pubDate', $text);
}

sub id {
	my $self = shift;
	my $id = shift;

	$self->_create_node(
		$self->{item_xpath},
		undef,
		'guid',
		$id,
		{
			isPermaLink=>"false"
		}
	);
}

#----------------------------------------------------------

package OpenILS::WWW::SuperCat::Feed::mods;
use base 'OpenILS::WWW::SuperCat::Feed';

sub new {
	my $class = shift;
	my $self = $class->SUPER::build('<mods:modsCollection version="3.0" xmlns:mods="http://www.loc.gov/mods/"/>');
	$self->{type} = 'application/xml';
	$self->{item_xpath} = '/mods:modsCollection';
	return $self;
}

package OpenILS::WWW::SuperCat::Feed::mods::item;
use base 'OpenILS::WWW::SuperCat::Feed::mods';

sub new {
	my $class = shift;
	my $xml = shift;
	my $self = $class->SUPER::build($xml);
	$self->{doc}->documentElement->setNamespace('http://www.loc.gov/mods/', undef);
	$self->{doc}->documentElement->setNamespace('http://www.loc.gov/mods/', 'mods');
	$self->{type} = 'application/xml';
	$self->{holdings_xpath} = '/mods:mods';
	return $self;
}

my $linkid = 1;

sub link {
	my $self = shift;
	my $type = shift;
	my $id = shift;

	if ($type eq 'unapi' || $type eq 'opac') {
		$self->_create_node(
			'mods:mods',
			'http://www.loc.gov/mods/',
			'mods:relatedItem',
			undef,
			{ type => 'otherFormat', id => 'link-'.$linkid }
		);
		$self->_create_node(
			"mods:mods/mods:relatedItem[\@id='link-$linkid']",
			'http://www.loc.gov/mods/',
			'mods:recordIdentifier',
			$id
		);
		$linkid++;
	}
}


#----------------------------------------------------------

package OpenILS::WWW::SuperCat::Feed::mods32;
use base 'OpenILS::WWW::SuperCat::Feed::mods';

sub new {
	my $class = shift;
	my $self = $class->SUPER::build('<mods:modsCollection version="3.2" xmlns:mods="http://www.loc.gov/mods/v3"/>');
	$self->{type} = 'application/xml';
	$self->{item_xpath} = '/mods:modsCollection';
	return $self;
}

package OpenILS::WWW::SuperCat::Feed::mods32::item;
use base 'OpenILS::WWW::SuperCat::Feed::mods::item';

#----------------------------------------------------------

package OpenILS::WWW::SuperCat::Feed::mods33;
use base 'OpenILS::WWW::SuperCat::Feed::mods';

sub new {
	my $class = shift;
	my $self = $class->SUPER::build('<mods:modsCollection version="3.3" xmlns:mods="http://www.loc.gov/mods/v3"/>');
	$self->{type} = 'application/xml';
	$self->{item_xpath} = '/mods:modsCollection';
	return $self;
}

package OpenILS::WWW::SuperCat::Feed::mods33::item;
use base 'OpenILS::WWW::SuperCat::Feed::mods::item';

#----------------------------------------------------------

package OpenILS::WWW::SuperCat::Feed::mods3;
use base 'OpenILS::WWW::SuperCat::Feed::mods';

sub new {
	my $class = shift;
	my $self = $class->SUPER::build('<mods:modsCollection version="3.0" xmlns:mods="http://www.loc.gov/mods/v3"/>');
	$self->{type} = 'application/xml';
	$self->{item_xpath} = '/mods:modsCollection';
	return $self;
}

package OpenILS::WWW::SuperCat::Feed::mods3::item;
use base 'OpenILS::WWW::SuperCat::Feed::mods::item';

sub new {
	my $class = shift;
	my $xml = shift;
	my $self = $class->SUPER::build($xml);
	$self->{doc}->documentElement->setNamespace('http://www.loc.gov/mods/v3', undef);
	$self->{doc}->documentElement->setNamespace('http://www.loc.gov/mods/v3', 'mods');
	$self->{type} = 'application/xml';
	$self->{holdings_xpath} = '/mods:mods';
	return $self;
}

sub link {
	my $self = shift;
	my $type = shift;
	my $id = shift;

	if ($type eq 'unapi' || $type eq 'opac') {
		$self->_create_node(
			'mods:mods',
			'http://www.loc.gov/mods/v3',
			'mods:relatedItem',
			undef,
			{ type => 'otherFormat', id => 'link-'.$linkid }
		);
		$self->_create_node(
			"mods:mods/mods:relatedItem[\@id='link-$linkid']",
			'http://www.loc.gov/mods/v3',
			'mods:recordIdentifier',
			$id
		);
		$linkid++;
	}
}


#----------------------------------------------------------

package OpenILS::WWW::SuperCat::Feed::marcxml;
use base 'OpenILS::WWW::SuperCat::Feed';

sub new {
	my $class = shift;
	my $self = $class->SUPER::build('<marc:collection xmlns:marc="http://www.loc.gov/MARC21/slim"/>');
	$self->{type} = 'application/xml';
	$self->{item_xpath} = '/marc:collection';
	return $self;
}
sub link {
	my $self = shift;
	my $type = shift;
	my $id = shift;

	if ($type eq 'unapi') {
		$self->_create_node(
			'marc:collection',
			'http://www.w3.org/1999/xhtml',
			'xhtml:link',
			undef,
			{ rel => 'unapi-server', href => $id, title => "unapi" }
		);
		$linkid++;
	}
}


package OpenILS::WWW::SuperCat::Feed::marcxml::item;
use base 'OpenILS::WWW::SuperCat::Feed::marcxml';

sub new {
	my $class = shift;
	my $xml = shift;
	my $self = $class->SUPER::build($xml);
	return undef unless $self;
	$self->{doc}->documentElement->setNamespace('http://www.loc.gov/MARC21/slim', undef);
	$self->{type} = 'application/xml';
	$self->{holdings_xpath} = '/*[local-name()="record"]';
	return $self;
}

sub link {
	my $self = shift;
	my $type = shift;
	my $id = shift;

	if ($type eq 'opac') {
		$self->_create_node(
			'*[local-name()="record"]',
			'http://www.w3.org/1999/xhtml',
			'xhtml:link',
			undef,
			{ rel => 'otherFormat', href => $id, title => "Dynamic Details" }
		);
		$linkid++;
	} elsif ($type eq 'unapi-id') {
		$self->_create_node(
			'*[local-name()="record"]',
			'http://www.w3.org/1999/xhtml',
			'xhtml:abbr',
			undef,
			{  title => $id, class => "unapi-id" }
		);
		$linkid++;
	}
}


#----------------------------------------------------------

package OpenILS::WWW::SuperCat::Feed::html;
use base 'OpenILS::WWW::SuperCat::Feed::atom';

sub new {
	my $class = shift;
	my $self = $class->SUPER::new;
	$self->type('text/html');
	return $self;
}

our ($_parser, $_xslt, $xslt_file);

sub toString {
	my $self = shift;
	my $base = $self->base || '';
	my $root = $self->root || '';
	my $search = $self->search || '';
	my $class = $self->class || '';
	my $lib = $self->lib || '-';

	$self->composeDoc;

        $_parser ||= new XML::LibXML;
        $_xslt ||= new XML::LibXSLT;

	$xslt_file ||=
                OpenSRF::Utils::SettingsClient
       	                ->new
               	        ->config_value( dirs => 'xsl' ).
                "/ATOM2XHTML.xsl";

        # parse the MODS xslt ...
        my $atom2html_xslt = $_xslt->parse_stylesheet( $_parser->parse_file($xslt_file) );

	my $new_doc = $atom2html_xslt->transform(
		$self->{doc},
		base_dir => "'$root'",
		lib => "'$lib'",
		searchTerms => "'$search'",
		searchClass => "'$class'",
	);

	return $new_doc->toString(1); 
}


package OpenILS::WWW::SuperCat::Feed::html::item;
use base 'OpenILS::WWW::SuperCat::Feed::atom::item';

#----------------------------------------------------------

package OpenILS::WWW::SuperCat::Feed::htmlcard;
use base 'OpenILS::WWW::SuperCat::Feed::marcxml';

sub new {
	my $class = shift;
	my $self = $class->SUPER::new;
	$self->type('text/html');
	$self->{xsl} = "/MARC21slim2HTMLCard.xsl";
	return $self;
}

our ($_parser, $_xslt, $xslt_file);

sub toString {
	my $self = shift;
	my $base = $self->base || '';
	my $root = $self->root || '';
	my $search = $self->search || '';
	my $sort = $self->Sort || '';
	my $sort_dir = $self->SortDir || '';
	my $lang = $self->lang || '';
	my $lib = $self->lib || '-';

	$self->composeDoc;

        $_parser ||= new XML::LibXML;
        $_xslt ||= new XML::LibXSLT;

	$xslt_file =
                OpenSRF::Utils::SettingsClient
       	                ->new
               	        ->config_value( dirs => 'xsl' ).$self->{xsl};

        # parse the MODS xslt ...
        my $atom2html_xslt = $_xslt->parse_stylesheet( $_parser->parse_file($xslt_file) );

	my $new_doc = $atom2html_xslt->transform(
		$self->{doc},
		base_dir => "'$root'",
		lib => "'$lib'",
		searchTerms => "'$search'",
		searchSort => "'$sort'",
		searchSortDir => "'$sort_dir'",
		searchLang => "'$lang'",
	);

	return $new_doc->toString(1); 
}

package OpenILS::WWW::SuperCat::Feed::htmlcard::item;
use base 'OpenILS::WWW::SuperCat::Feed::marcxml::item';

package OpenILS::WWW::SuperCat::Feed::htmlholdings;
use base 'OpenILS::WWW::SuperCat::Feed::htmlcard';

sub new {
	my $class = shift;
	my $self = $class->SUPER::new;
	$self->{xsl} = "/MARC21slim2HTMLCard-holdings.xsl";
	return $self;
}

package OpenILS::WWW::SuperCat::Feed::htmlholdings::item;
use base 'OpenILS::WWW::SuperCat::Feed::htmlcard::item';


package OpenILS::WWW::SuperCat::Feed::marctxt;
use base 'OpenILS::WWW::SuperCat::Feed::marcxml';

sub new {
	my $class = shift;
	my $self = $class->SUPER::new;
	$self->{type} = 'text/plain';
	$self->{xsl} = "/MARC21slim2MARCtxt.xsl";
	return $self;
}


our ($_parser, $_xslt, $xslt_file);

sub toString {
	my $self = shift;
	my $base = $self->base || '';
	my $root = $self->root || '';
	my $search = $self->search || '';
	my $class = $self->class || '';
	my $lib = $self->lib || '-';

	$self->composeDoc;

        $_parser ||= new XML::LibXML;
        $_xslt ||= new XML::LibXSLT;

	$xslt_file ||=
                OpenSRF::Utils::SettingsClient
       	                ->new
               	        ->config_value( dirs => 'xsl' ).
                $self->{xsl};

        # parse the MARC text xslt ...
        my $marctxt_xslt = $_xslt->parse_stylesheet( $_parser->parse_file($xslt_file) );

	my $new_doc = $marctxt_xslt->transform(
		$self->{doc},
		base_dir => "'$root'",
		lib => "'$lib'",
		searchTerms => "'$search'",
		searchClass => "'$class'",
	);

	return $marctxt_xslt->output_string($new_doc); 
}


package OpenILS::WWW::SuperCat::Feed::marctxt::item;
use base 'OpenILS::WWW::SuperCat::Feed::marcxml::item';


1;
