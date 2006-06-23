package OpenILS::WWW::SuperCat::Feed;
use strict; use warnings;
use vars qw/$parser/;
use OpenSRF::EX qw(:try);
use XML::LibXML;
use XML::LibXSLT;
use OpenSRF::Utils::SettingsClient;
use CGI;

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

	return bless $self => $class;
}

sub type {
	my $self = shift;
	my $type = shift;
	$self->{type} = $type if ($type);
	return $self->{type};
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

sub new {
	my $class = shift;
	my $self = $class->SUPER::build('<atom:feed xmlns:atom="http://www.w3.org/2005/Atom"/>');
	$self->{type} = 'application/xml';
	$self->{item_xpath} = '/atom:feed';
	return $self;
}

sub title {
	my $self = shift;
	my $text = shift;
	$self->_create_node('/atom:feed','http://www.w3.org/2005/Atom','atom:title', $text);
}

sub update_ts {
	my $self = shift;
	my $text = shift;
	$self->_create_node('/atom:feed','http://www.w3.org/2005/Atom','atom:updated', $text);
}

sub creator {
	my $self = shift;
	my $text = shift;
	$self->_create_node('/atom:feed','http://www.w3.org/2005/Atom','atom:author');
	$self->_create_node('/atom:feed/atom:author', 'http://www.w3.org/2005/Atom','atom:name', $text);
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
		'atom:link',
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

	$self->_create_node( '/atom:feed', 'http://www.w3.org/2005/Atom', 'atom:id', $id );
}

package OpenILS::WWW::SuperCat::Feed::atom::item;
use base 'OpenILS::WWW::SuperCat::Feed::atom';

sub new {
	my $class = shift;
	my $xml = shift;
	my $self = $class->SUPER::build($xml);
	$self->{doc}->documentElement->setNamespace('http://www.w3.org/2005/Atom', 'atom');
	$self->{item_xpath} = '/atom:entry';
	$self->{holdings_xpath} = '/atom:entry';
	$self->{type} = 'application/xml';
	return $self;
}


#----------------------------------------------------------

package OpenILS::WWW::SuperCat::Feed::rss2;
use base 'OpenILS::WWW::SuperCat::Feed';

sub new {
	my $class = shift;
	my $self = $class->SUPER::build('<rss version="2.0"><channel/></rss>');
	$self->{type} = 'application/xml';
	$self->{item_xpath} = '/rss/channel';
	return $self;
}

sub title {
	my $self = shift;
	my $text = shift;
	$self->_create_node('/rss/channel',undef,'title', $text);
}

sub update_ts {
	my $self = shift;
	my $text = shift;
	$self->_create_node('/rss/channel',undef,'lastBuildDate', $text);
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

	$type = 'self' if ($type eq 'rss2');

	$self->_create_node(
		$self->{item_xpath},
		undef,
		'link',
		$id,
		{ rel => $type,
		  type => $mime,
		}
	);
}

package OpenILS::WWW::SuperCat::Feed::rss2::item;
use base 'OpenILS::WWW::SuperCat::Feed::rss2';

sub new {
	my $class = shift;
	my $xml = shift;
	my $self = $class->SUPER::build($xml);
	$self->{type} = 'application/xml';
	$self->{item_xpath} = '/item';
	$self->{holdings_xpath} = '/item';
	return $self;
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

package OpenILS::WWW::SuperCat::Feed::marcxml::item;
use base 'OpenILS::WWW::SuperCat::Feed::marcxml';

sub new {
	my $class = shift;
	my $xml = shift;
	my $self = $class->SUPER::build($xml);
	return undef unless $self;
	$self->{doc}->documentElement->setNamespace('http://www.loc.gov/MARC21/slim', 'marc');
	$self->{type} = 'application/xml';
	$self->{holdings_xpath} = '/marc:record';
	return $self;
}

sub link {
	my $self = shift;
	my $type = shift;
	my $id = shift;

	if ($type eq 'unapi' || $type eq 'opac') {
		$self->_create_node(
			'marc:record',
			'http://www.w3.org/1999/xhtml',
			'xhtml:link',
			undef,
			{ rel => 'otherFormat', href => $id, title => "Dynamic Details" }
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

1;
