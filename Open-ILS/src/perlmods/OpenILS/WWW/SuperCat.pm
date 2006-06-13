package OpenILS::WWW::SuperCat;
use strict; use warnings;

use Apache2 ();
use Apache2::Log;
use Apache2::Const -compile => qw(OK REDIRECT DECLINED NOT_FOUND :log);
use APR::Const    -compile => qw(:error SUCCESS);
use Apache2::RequestRec ();
use Apache2::RequestIO ();
use Apache2::RequestUtil;
use CGI;
use Data::Dumper;

use OpenSRF::EX qw(:try);
use OpenSRF::Utils qw/:datetime/;
use OpenSRF::Utils::Cache;
use OpenSRF::System;
use OpenSRF::AppSession;
use XML::LibXML;

use Encode;
use Unicode::Normalize;
use OpenILS::Utils::Fieldmapper;
use OpenILS::WWW::SuperCat::Feed;


# set the bootstrap config when this module is loaded
my ($bootstrap, $supercat, $actor, $parser, $search);

sub import {
	my $self = shift;
	$bootstrap = shift;
}


sub child_init {
	OpenSRF::System->bootstrap_client( config_file => $bootstrap );
	$supercat = OpenSRF::AppSession->create('open-ils.supercat');
	$actor = OpenSRF::AppSession->create('open-ils.actor');
	$search = OpenSRF::AppSession->create('open-ils.search');
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

	my $cgi = new CGI;
	my $rel_name = quotemeta($cgi->url(-relative=>1));

	my $add_path = 1;
	$add_path = 0 if ($cgi->url(-path_info=>1) =~ /$rel_name$/);


	my $url = $cgi->url(-path_info=>$add_path);
	my $root = (split 'unapi', $url)[0];
	my $base = (split 'unapi', $url)[0] . 'unapi';


	my $uri = $cgi->param('id') || '';
	my $host = $cgi->virtual_host || $cgi->server_name;

	my $format = $cgi->param('format');
	my ($id,$type,$command,$lib) = ('','','');

	if (!$format) {
		print "Content-type: application/xml; charset=utf-8\n";
	
		if ($uri =~ m{^tag:[^:]+:([^\/]+)/(\d+)}o) {
			$id = $2;
			$lib = $3;
			$type = 'record';
			$type = 'metarecord' if ($1 =~ /^m/o);

			my $list = $supercat
			->request("open-ils.supercat.$type.formats")
				->gather(1);

			print "\n";

			my $body = "<formats id='$uri'><format name='opac' type='text/html'/>";

			for my $h (@$list) {
				my ($type) = keys %$h;
				$body .= "<format name='$type' type='application/xml'";

				for my $part ( qw/namespace_uri docs schema_location/ ) {
					$body .= " $part='$$h{$type}{$part}'"
						if ($$h{$type}{$part});
				}
				
				$body .= '/>';
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

			print "<formats><format name='opac' type='text/html'/>";

			for my $h (@$list) {
				my ($type) = keys %$h;
				print "<format name='$type' type='application/xml'";

				for my $part ( qw/namespace_uri docs schema_location/ ) {
					print " $part='$$h{$type}{$part}'"
						if ($$h{$type}{$part});
				}
				
				print '/>';
			}

			print "</formats>\n";


			return Apache2::Const::OK;
		}
	}

		
	if ($uri =~ m{^tag:[^:]+:([^\/]+)/(\d+)(?:/(.+))?}o) {
		$id = $2;
		$lib = $3;
		$type = 'record';
		$type = 'metarecord' if ($1 =~ /^m/o);
		$command = 'retrieve';
	}

	if ($format eq 'opac') {
		print "Location: $root/../../en-US/skin/default/xml/rresult.xml?m=$id\n\n"
			if ($type eq 'metarecord');
		print "Location: $root/../../en-US/skin/default/xml/rdetail.xml?r=$id\n\n"
			if ($type eq 'record');
		return 302;
	} else {
		my $feed = create_record_feed(
			$format => [ $id ],
			$base,
			$lib,
		);

		$feed->root($root);
		$feed->creator($host);
		$feed->update_ts(gmtime_ISO8601());

		print "Content-type: ". $feed->type ."; charset=utf-8\n\n";
		print entityize($feed->toString) . "\n";

		return Apache2::Const::OK;
	}

	my $req = $supercat->request("open-ils.supercat.$type.$format.$command",$id);
	$req->wait_complete;

	if ($req->failed) {
		print "Content-type: text/html; charset=utf-8\n\n";
		$apache->custom_response( 404, <<"		HTML");
		<html>
			<head>
				<title>$type $id not found!</title>
			</head>
			<body>
				<br/>
				<center>Sorry, we couldn't $command a $type with the id of $id in format $format.</center>
			</body>
		</html>
		HTML
		return 404;
	}

	print "Content-type: application/xml; charset=utf-8\n\n";
	print $req->gather(1);

	return Apache2::Const::OK;
}

sub supercat {

	my $apache = shift;
	return Apache2::Const::DECLINED if (-e $apache->filename);

	my $cgi = new CGI;

	my $rel_name = quotemeta($cgi->url(-relative=>1));

	my $add_path = 1;
	$add_path = 0 if ($cgi->url(-path_info=>1) =~ /$rel_name$/);


	my $url = $cgi->url(-path_info=>$add_path);
	my $root = (split 'supercat', $url)[0];
	my $base = (split 'supercat', $url)[0] . 'supercat';
	my $path = (split 'supercat', $url)[1];
	my $unapi = (split 'supercat', $url)[0] . 'unapi';

	my $host = $cgi->virtual_host || $cgi->server_name;

	my ($id,$type,$format,$command) = reverse split '/', $path;

	
	if ( $path =~ m{^/formats(?:/([^\/]+))?$}o ) {
		print "Content-type: application/xml; charset=utf-8\n";
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
				print "<format><name>$type</name><type>application/xml</type>";

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
			print "<format><name>$type</name><type>application/xml</type>";

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
		print "Location: $root/../../en-US/skin/default/xml/rresult.xml?m=$id\n\n"
			if ($type eq 'metarecord');
		print "Location: $root/../../en-US/skin/default/xml/rdetail.xml?r=$id\n\n"
			if ($type eq 'record');
		return 302;
	} elsif ($format =~ /^html/o) {
		my $feed = create_record_feed( $format => [ $id ], $unapi,);

		$feed->root($root);
		$feed->creator($host);
		$feed->update_ts(gmtime_ISO8601());

		print "Content-type: ". $feed->type ."; charset=utf-8\n\n";
		print entityize($feed->toString) . "\n";

		return Apache2::Const::OK;
	}

	my $req = $supercat->request("open-ils.supercat.$type.$format.$command",$id);
	$req->wait_complete;

	if ($req->failed) {
		print "Content-type: text/html; charset=utf-8\n\n";
		$apache->custom_response( 404, <<"		HTML");
		<html>
			<head>
				<title>$type $id not found!</title>
			</head>
			<body>
				<br/>
				<center>Sorry, we couldn't $command a $type with the id of $id.</center>
			</body>
		</html>
		HTML
		return 404;
	}

	print "Content-type: application/xml; charset=utf-8\n\n";
	print entityize( $parser->parse_string( $req->gather(1) )->documentElement->toString );

	return Apache2::Const::OK;
}


sub bookbag_feed {
	my $apache = shift;
	return Apache2::Const::DECLINED if (-e $apache->filename);

	my $cgi = new CGI;

	my $year = (gmtime())[5] + 1900;
	my $host = $cgi->virtual_host || $cgi->server_name;

	my $rel_name = quotemeta($cgi->url(-relative=>1));

	my $add_path = 1;
	$add_path = 0 if ($cgi->url(-path_info=>1) =~ /$rel_name$/);

	my $url = $cgi->url(-path_info=>$add_path);
	my $root = (split 'feed', $url)[0];
	my $base = (split 'bookbag', $url)[0] . 'bookbag';
	my $path = (split 'bookbag', $url)[1];
	my $unapi = (split 'feed', $url)[0] . 'unapi';


	#warn "URL breakdown: $url ($rel_name) -> $root -> $base -> $path -> $unapi";

	my ($id,$type) = reverse split '/', $path;

	my $bucket = $actor->request("open-ils.actor.container.public.flesh", 'biblio', $id)->gather(1);
	return Apache2::Const::NOT_FOUND unless($bucket);

	my $bucket_tag = "tag:$host,$year:record_bucket/$id";
	if ($type eq 'opac') {
		print "Location: $root/../../en-US/skin/default/xml/rresult.xml?rt=list&" .
			join('&', map { "rl=" . $_->target_biblio_record_entry } @{ $bucket->items }) .
			"\n\n";
		return 302;
	}

	my $feed = create_record_feed(
		$type,
		[ map { $_->target_biblio_record_entry } @{ $bucket->items } ],
		$unapi,
	);
	$feed->root($root);

	$feed->title("Items in Book Bag [".$bucket->name."]");
	$feed->creator($host);
	$feed->update_ts(gmtime_ISO8601());

	$feed->link(atom => $base . "/atom/$id" => 'application/atom+xml');
	$feed->link(rss2 => $base . "/rss2/$id");
	$feed->link(html => $base . "/html/$id" => 'text/html');
	$feed->link(unapi => $unapi);

	$feed->link(
		OPAC =>
		'/opac/en-US/skin/default/xml/rresult.xml?rt=list&' .
			join('&', map { 'rl=' . $_->target_biblio_record_entry } @{$bucket->items} ),
		'text/html'
	);


	print "Content-type: ". $feed->type ."; charset=utf-8\n\n";
	print entityize($feed->toString) . "\n";

	return Apache2::Const::OK;
}

sub changes_feed {
	my $apache = shift;
	return Apache2::Const::DECLINED if (-e $apache->filename);

	my $cgi = new CGI;

	my $year = (gmtime())[5] + 1900;
	my $host = $cgi->virtual_host || $cgi->server_name;

	my $rel_name = quotemeta($cgi->url(-relative=>1));

	my $add_path = 1;
	$add_path = 0 if ($cgi->url(-path_info=>1) =~ /$rel_name$/);

	my $url = $cgi->url(-path_info=>$add_path);
	my $root = (split 'feed', $url)[0];
	my $base = (split 'freshmeat', $url)[0] . 'freshmeat';
	my $path = (split 'freshmeat', $url)[1];
	my $unapi = (split 'feed', $url)[0] . 'unapi';


	#warn "URL breakdown: $url ($rel_name) -> $root -> $base -> $path -> $unapi";

	$path =~ s/^\///og;
	
	my ($type,$rtype,$axis,$date,$limit) = split '/', $path;
	$date ||= 'today';
	$limit ||= 10;

	my $list = $supercat->request("open-ils.supercat.$rtype.record.$axis.recent", $date, $limit)->gather(1);

	if ($type eq 'opac') {
		print "Location: $root/../../en-US/skin/default/xml/rresult.xml?rt=list&" .
			join('&', map { "rl=" . $_ } @$list) .
			"\n\n";
		return 302;
	}

	my $feed = create_record_feed( $type, $list, $unapi);
	$feed->root($root);

	$feed->title("$limit most recent $rtype changes from $date forward");
	$feed->creator($host);
	$feed->update_ts(gmtime_ISO8601());

	$feed->link(atom => $base . "/atom/$rtype/$axis/$date/$limit" => 'application/atom+xml');
	$feed->link(rss2 => $base . "/rss2/$rtype/$axis/$date/$limit");
	$feed->link(html => $base . "/html/$rtype/$axis/$date/$limit" => 'text/html');
	$feed->link(unapi => $unapi);

	$feed->link(
		OPAC =>
		'/opac/en-US/skin/default/xml/rresult.xml?rt=list&' .
			join('&', map { 'rl=' . $_} @$list ),
		'text/html'
	);


	print "Content-type: ". $feed->type ."; charset=utf-8\n\n";
	print entityize($feed->toString) . "\n";

	return Apache2::Const::OK;
}

sub opensearch_osd {
	my $version = shift;
	my $lib = shift;
	my $class = shift;
	my $base = shift;

	if ($version eq '1.0') {
		print <<OSD;
Content-type: application/opensearchdescription+xml; charset=utf-8

<?xml version="1.0" encoding="UTF-8"?>
<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearchdescription/1.0/">
  <Url>$base/1.0/$lib/-/$class/{searchTerms}?startPage={startPage}&amp;startIndex={startIndex}&amp;count={count}</Url>
  <Format>http://a9.com/-/spec/opensearchrss/1.0/</Format>
  <ShortName>$lib</ShortName>
  <LongName>Search $lib</LongName>
  <Description>Search the $lib OPAC by $class.</Description>
  <Tags>$lib book library</Tags>
  <SampleSearch>harry+potter</SampleSearch>
  <Developer>Mike Rylander for GPLS/PINES</Developer>
  <Contact>feedback\@open-ils.org</Contact>
  <SyndicationRight>open</SyndicationRight>
  <AdultContent>false</AdultContent>
</OpenSearchDescription>
OSD
	} else {
		print <<OSD;
Content-type: application/opensearchdescription+xml; charset=utf-8

<?xml version="1.0" encoding="UTF-8"?>
<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
  <ShortName>$lib</ShortName>
  <Description>Search the $lib OPAC by $class.</Description>
  <Tags>$lib book library</Tags>
  <Url type="application/atom+xml"
       template="$base/1.1/$lib/atom/$class/{searchTerms}?startPage={startPage?}&amp;startIndex={startIndex?}&amp;count={count?}&amp;language={language?}"/>
  <Url type="application/x-rss+xml"
       template="$base/1.1/$lib/rss2/$class/{searchTerms}?startPage={startPage?}&amp;startIndex={startIndex?}&amp;count={count?}&amp;language={language?}"/>
  <Url type="application/x-mods3+xml"
       template="$base/1.1/$lib/mods3/$class/{searchTerms}?startPage={startPage?}&amp;startIndex={startIndex?}&amp;count={count?}&amp;language={language?}"/>
  <Url type="application/x-mods+xml"
       template="$base/1.1/$lib/mods/$class/{searchTerms}?startPage={startPage?}&amp;startIndex={startIndex?}&amp;count={count?}&amp;language={language?}"/>
  <Url type="application/x-marcxml+xml"
       template="$base/1.1/$lib/marcxml/$class/{searchTerms}?startPage={startPage?}&amp;startIndex={startIndex?}&amp;count={count?}&amp;language={language?}"/>
  <LongName>Search $lib</LongName>
  <Query role="example" searchTerms="harry+potter" />
  <Developer>Mike Rylander for GPLS/PINES</Developer>
  <SyndicationRight>open</SyndicationRight>
  <AdultContent>false</AdultContent>
  <Language>en-US</Language>
  <OutputEncoding>UTF-8</OutputEncoding>
  <InputEncoding>UTF-8</InputEncoding>
</OpenSearchDescription>
OSD
	}

	return Apache2::Const::OK;
}

sub opensearch_feed {
	my $apache = shift;
	return Apache2::Const::DECLINED if (-e $apache->filename);

	my $cgi = new CGI;
	my $year = (gmtime())[5] + 1900;

	my $host = $cgi->virtual_host || $cgi->server_name;

	my $rel_name = quotemeta($cgi->url(-relative=>1));

	my $add_path = 1;
	$add_path = 0 if ($cgi->url(-path_info=>1) =~ /$rel_name$/);

	my $url = $cgi->url(-path_info=>$add_path);
	my $root = (split 'opensearch', $url)[0];
	my $base = (split 'opensearch', $url)[0] . 'opensearch';
	my $unapi = (split 'opensearch', $url)[0] . 'unapi';


	my $path = (split 'opensearch', $url)[1];

	#warn "URL breakdown: $url ($rel_name) -> $root -> $base -> $path -> $unapi";

	if ($path =~ m{^/?(1\.\d{1})/(?:([^/]+)/)?([^/]+)/osd.xml}o) {
		
		my $version = $1;
		my $lib = $2;
		my $class = $3;

		if (!$lib) {
		 	$lib = $actor->request(
				'open-ils.actor.org_unit_list.search' => parent_ou => undef
			)->gather(1)->[0]->shortname;
		}

		if ($class eq '-') {
			$class = 'keyword';
		}

		return opensearch_osd($version, $lib, $class, $base);
	}


	my $page = $cgi->param('startPage') || 1;
	my $offset = $cgi->param('startIndex') || 1;
	my $limit = $cgi->param('count') || 10;
	my $lang = $cgi->param('language') || 'en-US';

	$page = 1 if ($page !~ /^\d+$/);
	$offset = 1 if ($offset !~ /^\d+$/);
	$limit = 10 if ($limit !~ /^\d+$/); $limit = 25 if ($limit > 25);
	$lang = 'en-US' if ($lang =~ /^{/ or $lang eq '*');

	if ($page > 1) {
		$offset = ($page - 1) * $limit;
	} else {
		$offset -= 1;
	}

	my (undef,$version,$org,$type,$class,$terms) = split '/', $path;

	$terms ||= $cgi->param('searchTerms');
	$class ||= $cgi->param('searchClass') || '-';
	$type ||= $cgi->param('responseType') || '-';
	$org ||= $cgi->param('searchOrg') || '-';

	if ($version eq '1.0') {
		$type = 'rss2';
	} elsif ($type eq '-') {
		$type = 'atom';
	}


	$terms = decode_utf8($terms);
	$terms =~ s/\+/ /go;
	$terms =~ s/'//go;
	my $term_copy = $terms;

	if ($terms eq 'help') {
		print $cgi->header(-type => 'text/html');
		print <<HTML;
<html>
 <head>
  <title>just type something!</title>
 </head>
 <body>
  <p>You are in a maze of dark, twisty stacks, all alike.</p>
 </body>
</html>
HTML
	return Apache2::Const::OK;
	}

	my $cache_key = '';
	my $searches = {};
	while ($term_copy =~ /(keyword|title|author|subject|series):(.+)/ogc) {
		my $c = $1;
		my $t = $2;
		($term_copy = $t) =~ s/(keyword|title|author|subject|series):(.+)//o;
		$$searches{$c} = { term => $term_copy };
		$cache_key .= $c . $term_copy;
		warn "searching for $c -> [$term_copy] via OS $version, response type $type";
		$term_copy = $t;
	}

	if (!keys(%$searches)) {
		$class = 'keyword' if ($class eq '-');
		$$searches{$class} = { term => $terms };
		$cache_key .= $class . $terms;
	}

	my $org_unit;
	if ($org eq '-') {
	 	$org_unit = $actor->request(
			'open-ils.actor.org_unit_list.search' => parent_ou => undef
		)->gather(1);
	} else {
	 	$org_unit = $actor->request(
			'open-ils.actor.org_unit_list.search' => shortname => $org
		)->gather(1);
	}

	$cache_key .= $org;

	my $rs_name = $cgi->cookie('os_session');
	my $cached_res = OpenSRF::Utils::Cache->new->get_cache( "os_session:$rs_name" ) if ($rs_name);

	my $recs;
	if (!($recs = $$cached_res{os_results}{$cache_key})) {
		warn "NOT pulling results from cache";
		$rs_name = $cgi->remote_host . '::' . rand(time);
		$recs = $search->request(
			'open-ils.search.biblio.multiclass' => {
				searches	=> $searches,
				org_unit	=> $org_unit->[0]->id,
				offset		=> 0,
				limit		=> 5000,
			}
		)->gather(1);
		try {
			$$cached_res{os_results}{$cache_key} = $recs;
			OpenSRF::Utils::Cache->new->put_cache( "os_session:$rs_name", $cached_res, 1800 );
		} catch Error with {
			warn shift();
		};
	}

	my $feed = create_record_feed(
		$type,
		[ map { $_->[0] } @{$recs->{ids}}[$offset .. $offset + $limit - 1] ],
		$unapi,
		$org
	);
	$feed->root($root);
	$feed->lib($org);
	$feed->search($terms);
	$feed->class($class);

	if (keys(%$searches) > 1) {
		$feed->title("Search results for [$terms] at ".$org_unit->[0]->name);
	} else {
		$feed->title("Search results for [$class => $terms] at ".$org_unit->[0]->name);
	}

	$feed->creator($host);
	$feed->update_ts(gmtime_ISO8601());

	$feed->_create_node(
		$feed->{item_xpath},
		'http://a9.com/-/spec/opensearch/1.1/',
		'totalResults',
		$recs->{count},
	);

	$feed->_create_node(
		$feed->{item_xpath},
		'http://a9.com/-/spec/opensearch/1.1/',
		'startIndex',
		$offset + 1,
	);

	$feed->_create_node(
		$feed->{item_xpath},
		'http://a9.com/-/spec/opensearch/1.1/',
		'itemsPerPage',
		$limit,
	);

	$feed->link(
		next =>
		$base . "/$version/$org/$type/$class?searchTerms=$terms&startIndex=" . int($offset + $limit + 1) . "&count=" . $limit =>
		'application/opensearch+xml'
	) if ($offset + $limit < $recs->{count});

	$feed->link(
		previous =>
		$base . "/$version/$org/$type/$class?searchTerms=$terms&startIndex=" . int(($offset - $limit) + 1) . "&count=" . $limit =>
		'application/opensearch+xml'
	) if ($offset);

	$feed->link(
		self =>
		$base .  "/$version/$org/$type/$class?searchTerms=$terms" =>
		'application/opensearch+xml'
	);

	$feed->link( unapi => $unapi);

#	$feed->link(
#		alternate =>
#		$root . "../$lang/skin/default/xml/rresult.xml?rt=list&" .
#			join('&', map { 'rl=' . $_->[0] } @{$recs->{ids}} ),
#		'text/html'
#	);

	$feed->link(
		opac =>
		$root . "../$lang/skin/default/xml/rresult.xml?rt=list&" .
			join('&', map { 'rl=' . $_->[0] } grep { ref $_ && defined $_->[0] } @{$recs->{ids}} ),
		'text/html'
	);

	print $cgi->header(
		-type		=> $feed->type,
		-charset	=> 'UTF-8',
		-cookie		=> $cgi->cookie( -name => 'os_session', -value => $rs_name, -expires => '+30m' ),
	);

	print entityize($feed->toString) . "\n";

	return Apache2::Const::OK;
}

sub create_record_feed {
	my $type = shift;
	my $records = shift;
	my $unapi = shift;

	my $lib = shift || '';

	my $cgi = new CGI;
	my $base = $cgi->url;
	my $host = $cgi->virtual_host || $cgi->server_name;

	my $year = (gmtime())[5] + 1900;

	my $feed = new OpenILS::WWW::SuperCat::Feed ($type);
	$feed->base($base);
	$feed->unapi($unapi);

	$type = 'atom' if ($type eq 'html');
	$type = 'marcxml' if ($type eq 'htmlcard' or $type eq 'htmlholdings');

	for my $rec (@$records) {
		next unless($rec);

		my $item_tag = "tag:$host,$year:biblio-record_entry/$rec/$lib";


		my $xml = $supercat->request(
			"open-ils.supercat.record.$type.retrieve",
			$rec
		)->gather(1);

		my $node = $feed->add_item($xml);

		if ($lib && $type eq 'marcxml') {
			$xml = $supercat->request( "open-ils.supercat.record.holdings_xml.retrieve", $rec, $lib )->gather(1);
			$node->add_holdings($xml);
		}

		$node->id($item_tag);
		$node->link(alternate => $feed->unapi . "?id=$item_tag&format=htmlholdings" => 'text/html');
		$node->link(opac => $feed->unapi . "?id=$item_tag&format=opac");
		$node->link(unapi => $feed->unapi . "?id=$item_tag");
		$node->link('unapi-id' => $item_tag);
	}

	return $feed;
}

sub entityize {
	my $stuff = NFC(shift());
	$stuff =~ s/&(?!\S+;)/&amp;/gso;
	$stuff =~ s/([\x{0080}-\x{fffd}])/sprintf('&#x%X;',ord($1))/sgoe;
	return $stuff;
}

1;
