package OpenILS::WWW::SuperCat;
use strict; use warnings;

use Apache2 ();
use Apache2::Log;
use Apache2::Const -compile => qw(OK REDIRECT DECLINED :log);
use APR::Const    -compile => qw(:error SUCCESS);
use Apache2::RequestRec ();
use Apache2::RequestIO ();
use Apache2::RequestUtil;
use CGI;
use Data::Dumper;

use OpenSRF::EX qw(:try);
use OpenSRF::Utils qw/:datetime/;
use OpenSRF::System;
use OpenSRF::AppSession;
use XML::LibXML;

use Unicode::Normalize;
use OpenILS::Utils::Fieldmapper;


# set the bootstrap config when this module is loaded
my ($bootstrap, $supercat, $actor, $parser);

sub import {
	my $self = shift;
	$bootstrap = shift;
}


sub child_init {
	OpenSRF::System->bootstrap_client( config_file => $bootstrap );
	$supercat = OpenSRF::AppSession->create('open-ils.supercat');
	$actor = OpenSRF::AppSession->create('open-ils.actor');
	$parser = new XML::LibXML;
}

sub oisbn {

	my $apache = shift;
	return Apache2::Const::DECLINED if (-e $apache->filename);

	(my $isbn = $apache->path_info) =~ s{^.*?([^/]+)$}{$1}o;

	my $list = $supercat
		->request("open-ils.supercat.oisbn", $isbn)
		->gather(1);

	print "Content-type: application/xml; charset=utf-8\n\n";
	print "<?xml version='1.0' encoding='UTF-8' ?>\n";

	unless (exists $$list{metarecord}) {
		print '<idlist/>';
		return Apache2::Const::OK;
	}

	print "<idlist metarecord='$$list{metarecord}'>\n";

	for ( keys %{ $$list{record_list} } ) {
		(my $o = $$list{record_list}{$_}) =~s/^(\S+).*?$/$1/o;
		print "  <isbn record='$_'>$o</isbn>\n"
	}

	print "</idlist>\n";

	return Apache2::Const::OK;
}

sub unapi {

	my $apache = shift;
	return Apache2::Const::DECLINED if (-e $apache->filename);

	print "Content-type: application/xml; charset=utf-8\n";
	
	my $cgi = new CGI;

	my $uri = $cgi->param('uri') || '';
	my $base = $cgi->url;
	my $host = $cgi->virtual_host || $cgi->server_name;

	my $format = $cgi->param('format');
	my ($id,$type,$command) = ('','','');

	if (!$format) {
		if ($uri =~ m{^tag:[^:]+:([^\/]+)/(\d+)}o) {
			$id = $2;
			$type = 'record';
			$type = 'metarecord' if ($1 =~ /^m/o);

			my $list = $supercat
			->request("open-ils.supercat.$type.formats")
				->gather(1);

			print "\n";

			my $body =
				"<formats>
				 <uri>$uri</uri>
				   <format>
				     <name>opac</name>
				     <type>text/html</type>
				   </format>";

			for my $h (@$list) {
				my ($type) = keys %$h;
				$body .= "<format><name>$type</name><type>application/$type+xml</type>";

				for my $part ( qw/namespace_uri docs schema_location/ ) {
					$body .= "<$part>$$h{$type}{$part}</$part>"
						if ($$h{$type}{$part});
				}
				
				$body .= '</format>';
			}

			$body .= "</formats>\n";

			$apache->custom_response( 300, $body);
			return 300;
		} else {
			my $list = $supercat
				->request("open-ils.supercat.record.formats")
				->gather(1);
				
			push @$list,
				@{ $supercat
					->request("open-ils.supercat.metarecord.formats")
					->gather(1);
				};

			my %hash = map { ( (keys %$_)[0] => (values %$_)[0] ) } @$list;
			$list = [ map { { $_ => $hash{$_} } } sort keys %hash ];

			print "\n<formats>
				   <format>
				     <name>opac</name>
				     <type>text/html</type>
				   </format>";

			for my $h (@$list) {
				my ($type) = keys %$h;
				print "<format><name>$type</name><type>application/$type+xml</type>";

				for my $part ( qw/namespace_uri docs schema_location/ ) {
					print "<$part>$$h{$type}{$part}</$part>"
						if ($$h{$type}{$part});
				}
				
				print '</format>';
			}

			print "</formats>\n";


			return Apache2::Const::OK;
		}
	}

		
	if ($uri =~ m{^tag:[^:]+:([^\/]+)/(\d+)}o) {
		$id = $2;
		$type = 'record';
		$type = 'metarecord' if ($1 =~ /^m/o);
		$command = 'retrieve';
	}

	if ($format eq 'opac') {
		print "Location: $base/../../en-US/skin/default/xml/rresult.xml?m=$id\n\n"
			if ($type eq 'metarecord');
		print "Location: $base/../../en-US/skin/default/xml/rdetail.xml?r=$id\n\n"
			if ($type eq 'record');
		return 302;
	}

	print "\n" . $supercat->request("open-ils.supercat.$type.$format.$command",$id)->gather(1);

	return Apache2::Const::OK;
}

sub supercat {

	my $apache = shift;
	return Apache2::Const::DECLINED if (-e $apache->filename);

	my $path = $apache->path_info;

	my $cgi = new CGI;
	my $base = $cgi->url;

	my ($id,$type,$format,$command) = reverse split '/', $path;

	print "Content-type: application/xml; charset=utf-8\n";
	
	if ( $path =~ m{^/formats(?:/([^\/]+))?$}o ) {
		if ($1) {
			my $list = $supercat
				->request("open-ils.supercat.$1.formats")
				->gather(1);

			print "\n";

			print "<formats>
				   <format>
				     <name>opac</name>
				     <type>text/html</type>
				   </format>";

			for my $h (@$list) {
				my ($type) = keys %$h;
				print "<format><name>$type</name><type>application/$type+xml</type>";

				for my $part ( qw/namespace_uri docs schema_location/ ) {
					print "<$part>$$h{$type}{$part}</$part>"
						if ($$h{$type}{$part});
				}
				
				print '</format>';
			}

			print "</formats>\n";

			return Apache2::Const::OK;
		}

		my $list = $supercat
			->request("open-ils.supercat.record.formats")
			->gather(1);
				
		push @$list,
			@{ $supercat
				->request("open-ils.supercat.metarecord.formats")
				->gather(1);
			};

		my %hash = map { ( (keys %$_)[0] => (values %$_)[0] ) } @$list;
		$list = [ map { { $_ => $hash{$_} } } sort keys %hash ];

		print "\n<formats>
			   <format>
			     <name>opac</name>
			     <type>text/html</type>
			   </format>";

		for my $h (@$list) {
			my ($type) = keys %$h;
			print "<format><name>$type</name><type>application/$type+xml</type>";

			for my $part ( qw/namespace_uri docs schema_location/ ) {
				print "<$part>$$h{$type}{$part}</$part>"
					if ($$h{$type}{$part});
			}
			
			print '</format>';
		}

		print "</formats>\n";


		return Apache2::Const::OK;
	}

	if ($format eq 'opac') {
		print "Location: $base/../../en-US/skin/default/xml/rresult.xml?m=$id\n\n"
			if ($type eq 'metarecord');
		print "Location: $base/../../en-US/skin/default/xml/rdetail.xml?r=$id\n\n"
			if ($type eq 'record');
		return 302;
	}

	print "\n" . $supercat->request("open-ils.supercat.$type.$format.$command",$id)->gather(1);

	return Apache2::Const::OK;
}


sub bookbag_feed {
	my $apache = shift;
	return Apache2::Const::DECLINED if (-e $apache->filename);

	print "Content-type: application/xml; charset=utf-8\n\n";

	my $cgi = new CGI;
	(my $unapi = $cgi->url) =~ s{[^/]+/?$}{unapi};

	my $year = (gmtime())[5];

	my $host = $cgi->virtual_host || $cgi->server_name;
	my $path = $apache->path_info;

	my ($id,$type) = reverse split '/', $path;

	my $bucket = $actor->request("open-ils.actor.container.public.flesh", 'biblio', $id)->gather(1);
	my $bucket_tag = "tag:$host,$year:record_bucket/$id";

	my $feed = create_record_feed(
		$type,
		[ map { $_->target_biblio_record_entry } @{ $bucket->items } ],
		$unapi,
	);

	$feed->title("Items in Book Bag #".$bucket->id);
	$feed->creator($host);
	$feed->update_ts(gmtime_ISO8601());

	$feed->link(atom => $id);
	$feed->link(rss2 => $id);
	$feed->link(html => $id);

	print entityize($feed->toString) . "\n";

	return Apache2::Const::OK;
}

sub create_record_feed {
	my $type = shift;
	my $records = shift;
	my $unapi = shift;

	my $cgi = new CGI;
	my $base = $cgi->url;
	my $host = $cgi->virtual_host || $cgi->server_name;

	my $year = (gmtime())[5];

	my $feed = new OpenILS::WWW::SuperCat::Feed ($type);
	$feed->base($base);
	$feed->unapi($unapi);

	for my $rec (@$records) {
		my $item_tag = "tag:$host,$year:biblio-record_entry/" . $rec;

		my $xml = $supercat->request(
			"open-ils.supercat.record.$type.retrieve",
			$rec
		)->gather(1);

		my $node = $feed->add_item($xml);

		$node->id($item_tag);
		$node->link(unapi => $item_tag);
	}

	return $feed;
}

sub entityize {
	my $stuff = NFC(shift());
	$stuff =~ s/([\x{0080}-\x{fffd}])/sprintf('&#x%X;',ord($1))/sgoe;
	return $stuff;
}

package OpenILS::WWW::SuperCat::Feed;

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

	my $self = { doc => $parser->parse_string($xml), items => [] };

	return bless $self => $class;
}

sub base {
	my $self = shift;
	my $base = shift;
	$self->{base} = $base if ($base);
	return $self->{base};
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
			if ($text);

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

	$entry->base($self->base);
	$entry->unapi($self->unapi);

	$self->push_item($entry);
	return $entry;
}

sub toString {
	my $self = shift;
	for my $root ( $self->{doc}->findnodes($self->{item_xpath}) ) {
		for my $item ( $self->items ) {
			$root->appendChild( $item->{doc}->documentElement );
		}
		last;
	}

	return $self->{doc}->toString;
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
	$self->{type} = 'atom';
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

	$self->_create_node(
		'/atom:feed',
		'http://www.w3.org/2005/Atom',
		'atom:link',
		undef,
		{ rel => $type,
		  href => $self->base . '/' . $type . '/' . $id,
		  type => "application/$type+xml",
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
	$self->{type} = 'atom::item';
	return $self;
}

sub link {
	my $self = shift;
	my $type = shift;
	my $id = shift;

	if ($type eq 'unapi') {
		$self->_create_node(
			'atom:entry',
			'http://www.w3.org/2005/Atom',
			'atom:link',
			undef,
			{ rel => $type,
			  type => "application/xml",
			  href => $self->unapi . '?uri=' . $id,
			}
		);
	}
}


#----------------------------------------------------------

package OpenILS::WWW::SuperCat::Feed::rss2;
use base 'OpenILS::WWW::SuperCat::Feed';

sub new {
	my $class = shift;
	my $self = $class->SUPER::build('<rss version="2.0"><channel/></rss>');
	$self->{type} = 'rss2';
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

	$self->_create_node(
		'/rss/channel',
		undef,
		'link',
		$self->base . '/' . $type . '/' . $id,
		{ rel => $type }
	);
}

package OpenILS::WWW::SuperCat::Feed::rss2::item;
use base 'OpenILS::WWW::SuperCat::Feed::rss2';

sub new {
	my $class = shift;
	my $xml = shift;
	my $self = $class->SUPER::build($xml);
	$self->{type} = 'atom::item';
	return $self;
}

sub link {
	my $self = shift;
	my $type = shift;
	my $id = shift;

	$self->_create_node( item => undef, 'link' => $self->unapi . '?uri=' . $id )
		if ($type eq 'unapi');
}


#----------------------------------------------------------

package OpenILS::WWW::SuperCat::Feed::mods;
use base 'OpenILS::WWW::SuperCat::Feed';

sub new {
	my $class = shift;
	my $self = $class->SUPER::build('<mods:modsCollection version="3.0" xmlns:mods="http://www.loc.gov/mods/"/>');
	$self->{type} = 'mods';
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
	$self->{type} = 'mods::item';
	return $self;
}

my $linkid = 1;

sub link {
	my $self = shift;
	my $type = shift;
	my $id = shift;

	if ($type eq 'unapi') {
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
			$self->unapi .'?uri=' . $id
		);
		$linkid++;
	}
}


#----------------------------------------------------------

package OpenILS::WWW::SuperCat::Feed::html;
use base 'OpenILS::WWW::SuperCat::Feed';

sub new {
	my $class = shift;
	my $self = $class->SUPER::build('<html><head/><body/></html>');
	$self->{type} = 'html';
	$self->{item_xpath} = '/html/body';
	return $self;
}


1;
