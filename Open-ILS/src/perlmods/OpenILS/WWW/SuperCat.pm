package OpenILS::WWW::SuperCat;
use strict; use warnings;

use Apache2::Log;
use Apache2::Const -compile => qw(OK REDIRECT DECLINED NOT_FOUND :log);
use APR::Const    -compile => qw(:error SUCCESS);
use Apache2::RequestRec ();
use Apache2::RequestIO ();
use Apache2::RequestUtil;
use CGI;
use Data::Dumper;
use SRU::Request;
use SRU::Response;

use OpenSRF::EX qw(:try);
use OpenSRF::Utils qw/:datetime/;
use OpenSRF::Utils::Cache;
use OpenSRF::System;
use OpenSRF::AppSession;
use XML::LibXML;
use XML::LibXSLT;

use Encode;
use Unicode::Normalize;
use OpenILS::Utils::Fieldmapper;
use OpenILS::WWW::SuperCat::Feed;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Application::AppUtils;

use MARC::Record;
use MARC::File::XML;

my $log = 'OpenSRF::Utils::Logger';
my $U = 'OpenILS::Application::AppUtils';

# set the bootstrap config when this module is loaded
my ($bootstrap, $supercat, $actor, $parser, $search, $xslt, $cn_browse_xslt, %browse_types);

$browse_types{call_number}{xml} = sub {
	my $tree = shift;

	my $year = (gmtime())[5] + 1900;
	my $content = '';

	$content .= "<volumes  xmlns='http://open-ils.org/spec/holdings/v1'>";

	for my $cn (@$tree) {
		(my $cn_class = $cn->class_name) =~ s/::/-/gso;
		$cn_class =~ s/Fieldmapper-//gso;

		my $cn_tag = "tag:open-ils.org,$year:$cn_class/".$cn->id;
		my $cn_lib = $cn->owning_lib->shortname;
		my $cn_label = $cn->label;

		$cn_label =~ s/\n//gos;
		$cn_label =~ s/'/&apos;/go;

		(my $ou_class = $cn->owning_lib->class_name) =~ s/::/-/gso;
		$ou_class =~ s/Fieldmapper-//gso;

		my $ou_tag = "tag:open-ils.org,$year:$ou_class/".$cn->owning_lib->id;
		my $ou_name = $cn->owning_lib->name;

		$ou_name =~ s/\n//gos;
		$ou_name =~ s/'/&apos;/go;

		(my $rec_class = $cn->record->class_name) =~ s/::/-/gso;
		$rec_class =~ s/Fieldmapper-//gso;

		my $rec_tag = "tag:open-ils.org,$year:$rec_class/".$cn->record->id.'/'.$cn->owning_lib->shortname;

		$content .= "<volume id='$cn_tag' lib='$cn_lib' label='$cn_label'>";
		$content .= "<owning_lib xmlns:act='http://open-ils.org/spec/actors/v1' id='$ou_tag' name='$ou_name'/>";

		my $r_doc = $parser->parse_string($cn->record->marc);
		$r_doc->documentElement->setAttribute( id => $rec_tag );
		$content .= $U->entityize($r_doc->documentElement->toString);

		$content .= "</volume>";
	}

	$content .= '</volumes>';
	return ("Content-type: application/xml\n\n",$content);
};


$browse_types{call_number}{html} = sub {
	my $tree = shift;
	my $p = shift;
	my $n = shift;

	if (!$cn_browse_xslt) {
	        $cn_browse_xslt = $parser->parse_file(
        	        OpenSRF::Utils::SettingsClient
                	        ->new
                        	->config_value( dirs => 'xsl' ).
	                "/CNBrowse2HTML.xsl"
        	);
		$cn_browse_xslt = $xslt->parse_stylesheet( $cn_browse_xslt );
	}

	my (undef,$xml) = $browse_types{call_number}{xml}->($tree);

	return (
		"Content-type: text/html\n\n",
		$U->entityize(
			$cn_browse_xslt->transform(
				$parser->parse_string( $xml ),
				'prev' => "'$p'",
				'next' => "'$n'"
			)->toString(1)
		)
	);
};

sub import {
	my $self = shift;
	$bootstrap = shift;
}


sub child_init {
	OpenSRF::System->bootstrap_client( config_file => $bootstrap );
	
	my $idl = OpenSRF::Utils::SettingsClient->new->config_value("IDL");
	Fieldmapper->import(IDL => $idl);

	$supercat = OpenSRF::AppSession->create('open-ils.supercat');
	$actor = OpenSRF::AppSession->create('open-ils.actor');
	$search = OpenSRF::AppSession->create('open-ils.search');
	$parser = new XML::LibXML;
	$xslt = new XML::LibXSLT;

        $cn_browse_xslt = $parser->parse_file(
                OpenSRF::Utils::SettingsClient
                        ->new
                        ->config_value( dirs => 'xsl' ).
                "/CNBrowse2HTML.xsl"
        );

	$cn_browse_xslt = $xslt->parse_stylesheet( $cn_browse_xslt );

	my $list = $supercat
		->request("open-ils.supercat.record.formats")
		->gather(1);

    $list = [ map { (keys %$_)[0] } @$list ];
    push @$list, 'htmlholdings','html';

    for my $browse_axis ( qw/title author subject topic series item-age/ ) {
        for my $record_browse_format ( @$list ) {
            {
                my $__f = $record_browse_format;
                my $__a = $browse_axis;

                $browse_types{$__a}{$__f} = sub {
                	my $record_list = shift;
                	my $prev = shift;
                	my $next = shift;
                	my $real_format = shift || $__f;
                	my $unapi = shift;
                	my $base = shift;
                	my $site = shift;

                	my $feed = create_record_feed( 'record', $real_format, $record_list, $unapi, $site, $real_format =~ /-full$/o ? 1 : 0 );
                	$feed->root( "$base/../" );
                	$feed->lib( $site );
                	$feed->link( next => $next => $feed->type );
                	$feed->link( previous => $prev => $feed->type );

                	return (
                        "Content-type: ". $feed->type ."; charset=utf-8\n\n",
                        $feed->toString
                    );
                };
            }
        }
    }
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

	my $add_path = 0;
	if ( $cgi->server_software !~ m|^Apache/2.2| ) {
		my $rel_name = $cgi->url(-relative=>1);
		$add_path = 1 if ($cgi->url(-path_info=>1) !~ /$rel_name$/);
	}

	my $url = $cgi->url(-path_info=>$add_path);
	my $root = (split 'unapi', $url)[0];
	my $base = (split 'unapi', $url)[0] . 'unapi';


	my $uri = $cgi->param('id') || '';
	my $host = $cgi->virtual_host || $cgi->server_name;

	my $format = $cgi->param('format');
	my $flesh_feed = ($format =~ /-full$/o) ? 1 : 0;
	(my $base_format = $format) =~ s/-full$//o;
	my ($id,$type,$command,$lib) = ('','','');

	if (!$format) {
		my $body = "Content-type: application/xml; charset=utf-8\n\n";
	
		if ($uri =~ m{^tag:[^:]+:([^\/]+)/([^/]+)(?:/(.+))$}o) {
			$id = $2;
			$lib = uc($3);
			$type = 'record';
			$type = 'metarecord' if ($1 =~ /^m/o);

			my $list = $supercat
				->request("open-ils.supercat.$type.formats")
				->gather(1);

			if ($type eq 'record' or $type eq 'isbn') {
				$body .= <<"				FORMATS";
<formats id='$uri'>
	<format name='opac' type='text/html'/>
	<format name='html' type='text/html'/>
	<format name='htmlholdings' type='text/html'/>
	<format name='html-full' type='text/html'/>
	<format name='htmlholdings-full' type='text/html'/>
				FORMATS
			} elsif ($type eq 'metarecord') {
				$body .= <<"				FORMATS";
				<formats id='$uri'>
					<format name='opac' type='text/html'/>
				FORMATS
			}

			for my $h (@$list) {
				my ($type) = keys %$h;
				$body .= "\t<format name='$type' type='application/xml'";

				for my $part ( qw/namespace_uri docs schema_location/ ) {
					$body .= " $part='$$h{$type}{$part}'"
						if ($$h{$type}{$part});
				}
				
				$body .= "/>\n";

				if (OpenILS::WWW::SuperCat::Feed->exists($type)) {
					$body .= "\t<format name='$type-full' type='application/xml'";

					for my $part ( qw/namespace_uri docs schema_location/ ) {
						$body .= " $part='$$h{$type}{$part}'"
							if ($$h{$type}{$part});
					}
				
					$body .= "/>\n";
				}
			}

			$body .= "</formats>\n";

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

			$body .= <<"			FORMATS";
<formats>
	<format name='opac' type='text/html'/>
	<format name='html' type='text/html'/>
	<format name='htmlholdings' type='text/html'/>
	<format name='html-full' type='text/html'/>
	<format name='htmlholdings-full' type='text/html'/>
			FORMATS


			for my $h (@$list) {
				my ($type) = keys %$h;
				$body .= "\t<format name='$type' type='application/xml'";

				for my $part ( qw/namespace_uri docs schema_location/ ) {
					$body .= " $part='$$h{$type}{$part}'"
						if ($$h{$type}{$part});
				}
				
				$body .= "/>\n";

				if (OpenILS::WWW::SuperCat::Feed->exists($type)) {
					$body .= "\t<format name='$type-full' type='application/xml'";

					for my $part ( qw/namespace_uri docs schema_location/ ) {
						$body .= " $part='$$h{$type}{$part}'"
							if ($$h{$type}{$part});
					}
				
					$body .= "/>\n";
				}
			}

			$body .= "</formats>\n";

		}
		print $body;
		return Apache2::Const::OK;
	}

	if ($uri =~ m{^tag:[^:]+:([^\/]+)/([^/]+)(?:/(.+))?}o) {
		$id = $2;
		$lib = uc($3);
		$type = 'record';
		$type = 'metarecord' if ($1 =~ /^metabib/o);
		$type = 'isbn' if ($1 =~ /^isbn/o);
		$type = 'call_number' if ($1 =~ /^call_number/o);
		$command = 'retrieve';
		$command = 'browse' if ($type eq 'call_number');
	}

	if (!$lib || $lib eq '-') {
	 	$lib = $actor->request(
			'open-ils.actor.org_unit_list.search' => parent_ou => undef
		)->gather(1)->[0]->shortname;
	}

	my $lib_object = $actor->request(
		'open-ils.actor.org_unit_list.search' => shortname => $lib
	)->gather(1)->[0];
	my $lib_id = $lib_object->id;

	my $ou_types = $actor->request( 'open-ils.actor.org_types.retrieve' )->gather(1);
	my $lib_depth = (grep { $_->id == $lib_object->ou_type } @$ou_types)[0]->depth;

	if ($type eq 'call_number' and $command eq 'browse') {
		print "Location: $root/browse/$base_format/call_number/$lib/$id\n\n";
		return 302;
	}

	if ($type eq 'isbn') {
		my $rec = $supercat->request('open-ils.supercat.isbn.object.retrieve',$id)->gather(1);
		if (!@$rec) {
			print "Content-type: text/html; charset=utf-8\n\n";
			$apache->custom_response( 404, <<"			HTML");
			<html>
				<head>
					<title>Type [$type] with id [$id] not found!</title>
				</head>
				<body>
					<br/>
					<center>Sorry, we couldn't $command a $type with the id of $id in format $format.</center>
				</body>
			</html>
			HTML
			return 404;
		}
		$id = $rec->[0]->id;
		$type = 'record';
	}

	if ( !grep
	       { (keys(%$_))[0] eq $base_format }
	       @{ $supercat->request("open-ils.supercat.$type.formats")->gather(1) }
	     and !grep
	       { $_ eq $base_format }
	       qw/opac html htmlholdings/
	) {
		print "Content-type: text/html; charset=utf-8\n\n";
		$apache->custom_response( 406, <<"		HTML");
		<html>
			<head>
				<title>Invalid format [$format] for type [$type]!</title>
			</head>
			<body>
				<br/>
				<center>Sorry, format $format is not valid for type $type.</center>
			</body>
		</html>
		HTML
		return 406;
	}

	if ($format eq 'opac') {
		print "Location: $root/../../en-US/skin/default/xml/rresult.xml?m=$id&l=$lib_id&d=$lib_depth\n\n"
			if ($type eq 'metarecord');
		print "Location: $root/../../en-US/skin/default/xml/rdetail.xml?r=$id&l=$lib_id&d=$lib_depth\n\n"
			if ($type eq 'record');
		return 302;
	} elsif (OpenILS::WWW::SuperCat::Feed->exists($base_format)) {
		my $feed = create_record_feed(
			$type,
			$format => [ $id ],
			$base,
			$lib,
			$flesh_feed
		);

		if (!$feed->count) {
			print "Content-type: text/html; charset=utf-8\n\n";
			$apache->custom_response( 404, <<"			HTML");
			<html>
				<head>
					<title>Type [$type] with id [$id] not found!</title>
				</head>
				<body>
					<br/>
					<center>Sorry, we couldn't $command a $type with the id of $id in format $format.</center>
				</body>
			</html>
			HTML
			return 404;
		}

		$feed->root($root);
		$feed->creator($host);
		$feed->update_ts();
		$feed->link( unapi => $base) if ($flesh_feed);

		print "Content-type: ". $feed->type ."; charset=utf-8\n\n";
		print $U->entityize($feed->toString) . "\n";

		return Apache2::Const::OK;
	}

	my $req = $supercat->request("open-ils.supercat.$type.$format.$command",$id);
	my $data = $req->gather(1);

	if ($req->failed || !$data) {
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

	print "Content-type: application/xml; charset=utf-8\n\n$data";

	return Apache2::Const::OK;
}

sub supercat {

	my $apache = shift;
	return Apache2::Const::DECLINED if (-e $apache->filename);

	my $cgi = new CGI;

	my $add_path = 0;
	if ( $cgi->server_software !~ m|^Apache/2.2| ) {
		my $rel_name = $cgi->url(-relative=>1);
		$add_path = 1 if ($cgi->url(-path_info=>1) !~ /$rel_name$/);
	}

	my $url = $cgi->url(-path_info=>$add_path);
	my $root = (split 'supercat', $url)[0];
	my $base = (split 'supercat', $url)[0] . 'supercat';
	my $unapi = (split 'supercat', $url)[0] . 'unapi';

	my $host = $cgi->virtual_host || $cgi->server_name;

	my $path = $cgi->path_info;
	my ($id,$type,$format,$command) = reverse split '/', $path;
	my $flesh_feed = ($type =~ /-full$/o) ? 1 : 0;
	(my $base_format = $format) =~ s/-full$//o;
	
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

			if ($1 eq 'record' or $1 eq 'isbn') {
				print "<format>
				     <name>htmlholdings</name>
				     <type>text/html</type>
				   </format>
				   <format>
				     <name>html</name>
				     <type>text/html</type>
				   </format>
				   <format>
				     <name>htmlholdings-full</name>
				     <type>text/html</type>
				   </format>
				   <format>
				     <name>html-full</name>
				     <type>text/html</type>
				   </format>";
			}

			for my $h (@$list) {
				my ($type) = keys %$h;
				print "<format><name>$type</name><type>application/xml</type>";

				for my $part ( qw/namespace_uri docs schema_location/ ) {
					print "<$part>$$h{$type}{$part}</$part>"
						if ($$h{$type}{$part});
				}
				
				print '</format>';

				if (OpenILS::WWW::SuperCat::Feed->exists($type)) {
					print "<format><name>$type-full</name><type>application/xml</type>";

					for my $part ( qw/namespace_uri docs schema_location/ ) {
						print "<$part>$$h{$type}{$part}</$part>"
							if ($$h{$type}{$part});
					}
				
					print '</format>';
				}

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
			   </format>
			   <format>
			     <name>htmlholdings</name>
			     <type>text/html</type>
			   </format>
			   <format>
			     <name>html</name>
			     <type>text/html</type>
			   </format>
			   <format>
			     <name>htmlholdings-full</name>
			     <type>text/html</type>
			   </format>
			   <format>
			     <name>html-full</name>
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

			if (OpenILS::WWW::SuperCat::Feed->exists($type)) {
				print "<format><name>$type-full</name><type>application/xml</type>";

				for my $part ( qw/namespace_uri docs schema_location/ ) {
					print "<$part>$$h{$type}{$part}</$part>"
						if ($$h{$type}{$part});
				}
				
				print '</format>';
			}

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

	} elsif ($base_format eq 'marc21') {

		my $ret = 200;    
		try {
			my $bib = $supercat->request( "open-ils.supercat.record.object.retrieve", $id )->gather(1)->[0];
        
			my $r = MARC::Record->new_from_xml( $bib->marc, 'UTF-8', 'USMARC' );
			$r->delete_field( $_ ) for ($r->field(901));
                
			$r->append_fields(
				MARC::Field->new(
					901, '', '',
					a => $bib->tcn_value,
					b => $bib->tcn_source,
					c => $bib->id
				)
			);

			print "Content-type: application/octet-stream\n\n";
			print $r->as_usmarc;

		} otherwise {
			warn shift();
			
			print "Content-type: text/html; charset=utf-8\n\n";
			$apache->custom_response( 404, <<"			HTML");
			<html>
				<head>
					<title>ERROR</title>
				</head>
				<body>
					<br/>
					<center>Couldn't fetch $id as MARC21.</center>
				</body>
			</html>
			HTML
			$ret = 404;
		};

		return Apache2::Const::OK;

	} elsif (OpenILS::WWW::SuperCat::Feed->exists($base_format)) {
		my $feed = create_record_feed(
			$type,
			$format => [ $id ],
			undef, undef,
			$flesh_feed
		);

		$feed->root($root);
		$feed->creator($host);

		$feed->update_ts();

		$feed->link( unapi => $base) if ($flesh_feed);

		print "Content-type: ". $feed->type ."; charset=utf-8\n\n";
		print $U->entityize($feed->toString) . "\n";

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
	print $U->entityize( $parser->parse_string( $req->gather(1) )->documentElement->toString );

	return Apache2::Const::OK;
}


sub bookbag_feed {
	my $apache = shift;
	return Apache2::Const::DECLINED if (-e $apache->filename);

	my $cgi = new CGI;

	my $year = (gmtime())[5] + 1900;
	my $host = $cgi->virtual_host || $cgi->server_name;

	my $add_path = 0;
	if ( $cgi->server_software !~ m|^Apache/2.2| ) {
		my $rel_name = $cgi->url(-relative=>1);
		$add_path = 1 if ($cgi->url(-path_info=>1) !~ /$rel_name$/);
	}

	my $url = $cgi->url(-path_info=>$add_path);
	my $root = (split 'feed', $url)[0] . '/';
	my $base = (split 'bookbag', $url)[0] . '/bookbag';
	my $unapi = (split 'feed', $url)[0] . '/unapi';

	$root =~ s{(?<!http:)//}{/}go;
	$base =~ s{(?<!http:)//}{/}go;
	$unapi =~ s{(?<!http:)//}{/}go;

	my $path = $cgi->path_info;
	#warn "URL breakdown: $url -> $root -> $base -> $path -> $unapi";

	my ($id,$type) = reverse split '/', $path;
	my $flesh_feed = ($type =~ /-full$/o) ? 1 : 0;

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
		'record',
		$type,
		[ map { $_->target_biblio_record_entry } @{ $bucket->items } ],
		$unapi,
		undef,
		$flesh_feed
	);
	$feed->root($root);
	$feed->id($bucket_tag);

	$feed->title("Items in Book Bag [".$bucket->name."]");
	$feed->creator($host);
	$feed->update_ts();

	$feed->link(alternate => $base . "/rss2-full/$id" => 'application/rss+xml');
	$feed->link(atom => $base . "/atom-full/$id" => 'application/atom+xml');
	$feed->link(html => $base . "/html-full/$id" => 'text/html');
	$feed->link(unapi => $unapi);

	$feed->link(
		OPAC =>
		$host . '/opac/en-US/skin/default/xml/rresult.xml?rt=list&' .
			join('&', map { 'rl=' . $_->target_biblio_record_entry } @{$bucket->items} ),
		'text/html'
	);


	print "Content-type: ". $feed->type ."; charset=utf-8\n\n";
	print $U->entityize($feed->toString) . "\n";

	return Apache2::Const::OK;
}

sub changes_feed {
	my $apache = shift;
	return Apache2::Const::DECLINED if (-e $apache->filename);

	my $cgi = new CGI;

	my $year = (gmtime())[5] + 1900;
	my $host = $cgi->virtual_host || $cgi->server_name;

	my $add_path = 0;
	if ( $cgi->server_software !~ m|^Apache/2.2| ) {
		my $rel_name = $cgi->url(-relative=>1);
		$add_path = 1 if ($cgi->url(-path_info=>1) !~ /$rel_name$/);
	}

	my $url = $cgi->url(-path_info=>$add_path);
	my $root = (split 'feed', $url)[0];
	my $base = (split 'freshmeat', $url)[0] . '/freshmeat';
	my $unapi = (split 'feed', $url)[0] . 'unapi';

	my $path = $cgi->path_info;
	#warn "URL breakdown: $url ($rel_name) -> $root -> $base -> $path -> $unapi";

	$path =~ s/^\/(?:feed\/)?freshmeat\///og;
	
	my ($type,$rtype,$axis,$limit,$date) = split '/', $path;
	my $flesh_feed = ($type =~ /-full$/o) ? 1 : 0;
	$limit ||= 10;

	my $list = $supercat->request("open-ils.supercat.$rtype.record.$axis.recent", $date, $limit)->gather(1);

	#if ($type eq 'opac') {
	#	print "Location: $root/../../en-US/skin/default/xml/rresult.xml?rt=list&" .
	#		join('&', map { "rl=" . $_ } @$list) .
	#		"\n\n";
	#	return 302;
	#}

	my $feed = create_record_feed( 'record', $type, $list, $unapi, undef, $flesh_feed);
	$feed->root($root);

	if ($date) {
		$feed->title("Up to $limit recent $rtype ${axis}s from $date forward");
	} else {
		$feed->title("$limit most recent $rtype ${axis}s");
	}

	$feed->creator($host);
	$feed->update_ts();

	$feed->link(alternate => $base . "/rss2-full/$rtype/$axis/$limit/$date" => 'application/rss+xml');
	$feed->link(atom => $base . "/atom-full/$rtype/$axis/$limit/$date" => 'application/atom+xml');
	$feed->link(html => $base . "/html-full/$rtype/$axis/$limit/$date" => 'text/html');
	$feed->link(unapi => $unapi);

	$feed->link(
		OPAC =>
		$host . '/opac/en-US/skin/default/xml/rresult.xml?rt=list&' .
			join('&', map { 'rl=' . $_} @$list ),
		'text/html'
	);


	print "Content-type: ". $feed->type ."; charset=utf-8\n\n";
	print $U->entityize($feed->toString) . "\n";

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
  <Url>$base/1.0/$lib/-/$class/?searchTerms={searchTerms}&amp;startPage={startPage}&amp;startIndex={startIndex}&amp;count={count}</Url>
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
  <Url type="application/rss+xml"
       template="$base/1.1/$lib/rss2-full/$class/?searchTerms={searchTerms}&amp;startPage={startPage?}&amp;startIndex={startIndex?}&amp;count={count?}&amp;searchLang={language?}"/>
  <Url type="application/atom+xml"
       template="$base/1.1/$lib/atom-full/$class/?searchTerms={searchTerms}&amp;startPage={startPage?}&amp;startIndex={startIndex?}&amp;count={count?}&amp;searchLang={language?}"/>
  <Url type="application/x-mods3+xml"
       template="$base/1.1/$lib/mods3/$class/?searchTerms={searchTerms}&amp;startPage={startPage?}&amp;startIndex={startIndex?}&amp;count={count?}&amp;searchLang={language?}"/>
  <Url type="application/x-mods+xml"
       template="$base/1.1/$lib/mods/$class/?searchTerms={searchTerms}&amp;startPage={startPage?}&amp;startIndex={startIndex?}&amp;count={count?}&amp;searchLang={language?}"/>
  <Url type="application/x-marcxml+xml"
       template="$base/1.1/$lib/marcxml/$class/?searchTerms={searchTerms}&amp;startPage={startPage?}&amp;startIndex={startIndex?}&amp;count={count?}&amp;searchLang={language?}"/>
  <Url type="text/html"
       template="$base/1.1/$lib/html-full/$class/?searchTerms={searchTerms}&amp;startPage={startPage?}&amp;startIndex={startIndex?}&amp;count={count?}&amp;searchLang={language?}"/>
  <LongName>Search $lib</LongName>
  <Query role="example" searchTerms="harry+potter" />
  <Developer>Mike Rylander for GPLS/PINES</Developer>
  <Contact>feedback\@open-ils.org</Contact>
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

	my $add_path = 0;
	if ( $cgi->server_software !~ m|^Apache/2.2| ) {
		my $rel_name = $cgi->url(-relative=>1);
		$add_path = 1 if ($cgi->url(-path_info=>1) !~ /$rel_name$/);
	}

	my $url = $cgi->url(-path_info=>$add_path);
	my $root = (split 'opensearch', $url)[0];
	my $base = (split 'opensearch', $url)[0] . 'opensearch';
	my $unapi = (split 'opensearch', $url)[0] . 'unapi';

	my $path = $cgi->path_info;
	#warn "URL breakdown: $url ($rel_name) -> $root -> $base -> $path -> $unapi";

	if ($path =~ m{^/?(1\.\d{1})/(?:([^/]+)/)?([^/]+)/osd.xml}o) {
		
		my $version = $1;
		my $lib = uc($2);
		my $class = $3;

		if (!$lib || $lib eq '-') {
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

	$page = 1 if ($page !~ /^\d+$/);
	$offset = 1 if ($offset !~ /^\d+$/);
	$limit = 10 if ($limit !~ /^\d+$/); $limit = 25 if ($limit > 25);

	if ($page > 1) {
		$offset = ($page - 1) * $limit;
	} else {
		$offset -= 1;
	}

	my ($version,$org,$type,$class,$terms,$sort,$sortdir,$lang) = ('','','','','','','','');
	(undef,$version,$org,$type,$class,$terms,$sort,$sortdir,$lang) = split '/', $path;

	$lang = $cgi->param('searchLang') if $cgi->param('searchLang');
	$lang = '' if ($lang eq '*');

	$sort = $cgi->param('searchSort') if $cgi->param('searchSort');
	$sort ||= '';
	$sortdir = $cgi->param('searchSortDir') if $cgi->param('searchSortDir');
	$sortdir ||= '';

	$terms .= " " if ($terms && $cgi->param('searchTerms'));
	$terms .= $cgi->param('searchTerms') if $cgi->param('searchTerms');

	$class = $cgi->param('searchClass') if $cgi->param('searchClass');
	$class ||= '-';

	$type = $cgi->param('responseType') if $cgi->param('responseType');
	$type ||= '-';

	$org = $cgi->param('searchOrg') if $cgi->param('searchOrg');
	$org ||= '-';


	my $kwt = $cgi->param('kw');
	my $tit = $cgi->param('ti');
	my $aut = $cgi->param('au');
	my $sut = $cgi->param('su');
	my $set = $cgi->param('se');

	$terms .= " " if ($terms && $kwt);
	$terms .= "keyword: $kwt" if ($kwt);
	$terms .= " " if ($terms && $tit);
	$terms .= "title: $tit" if ($tit);
	$terms .= " " if ($terms && $aut);
	$terms .= "author: $aut" if ($aut);
	$terms .= " " if ($terms && $sut);
	$terms .= "subject: $sut" if ($sut);
	$terms .= " " if ($terms && $set);
	$terms .= "series: $set" if ($set);

	if ($version eq '1.0') {
		$type = 'rss2';
	} elsif ($type eq '-') {
		$type = 'atom';
	}
	my $flesh_feed = ($type =~ /-full$/o) ? 1 : 0;

	$terms = decode_utf8($terms);
	$lang = 'eng' if ($lang eq 'en-US');

	$log->debug("OpenSearch terms: $terms");

	my $org_unit;
	if ($org eq '-') {
	 	$org_unit = $actor->request(
			'open-ils.actor.org_unit_list.search' => parent_ou => undef
		)->gather(1);
	} elsif ($org !~ /^\d+$/o) {
	 	$org_unit = $actor->request(
			'open-ils.actor.org_unit_list.search' => shortname => uc($org)
		)->gather(1);
	} else {
	 	$org_unit = $actor->request(
			'open-ils.actor.org_unit_list.search' => id => $org
		)->gather(1);
	}

	# Apostrophes break search and get indexed as spaces anyway
	my $safe_terms = $terms;
	$safe_terms =~ s{'}{ }go;

	my $recs = $search->request(
		'open-ils.search.biblio.multiclass.query' => {
			org_unit	=> $org_unit->[0]->id,
			offset		=> $offset,
			limit		=> $limit,
			sort		=> $sort,
			sort_dir	=> $sortdir,
            default_class => $class,
			($lang ?    ( 'language' => $lang    ) : ()),
		} => $safe_terms => 1
	)->gather(1);

	$log->debug("Hits for [$terms]: $recs->{count}");

	my $feed = create_record_feed(
		'record',
		$type,
		[ map { $_->[0] } @{$recs->{ids}} ],
		$unapi,
		$org,
		$flesh_feed
	);

	$log->debug("Feed created...");

	$feed->root($root);
	$feed->lib($org);
	$feed->search($safe_terms);
	$feed->class($class);

	$feed->title("Search results for [$terms] at ".$org_unit->[0]->name);

	$feed->creator($host);
	$feed->update_ts();

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

	$log->debug("...basic feed data added...");

	$feed->link(
		next =>
		$base . "/$version/$org/$type/$class?searchTerms=$terms&searchSort=$sort&searchSortDir=$sortdir&searchLang=$lang&startIndex=" . int($offset + $limit + 1) . "&count=" . $limit =>
		'application/opensearch+xml'
	) if ($offset + $limit < $recs->{count});

	$feed->link(
		previous =>
		$base . "/$version/$org/$type/$class?searchTerms=$terms&searchSort=$sort&searchSortDir=$sortdir&searchLang=$lang&startIndex=" . int(($offset - $limit) + 1) . "&count=" . $limit =>
		'application/opensearch+xml'
	) if ($offset);

	$feed->link(
		self =>
		$base .  "/$version/$org/$type/$class?searchTerms=$terms&searchSort=$sort&searchSortDir=$sortdir&searchLang=$lang" =>
		'application/opensearch+xml'
	);

	$feed->link(
		alternate =>
		$base .  "/$version/$org/rss2-full/$class?searchTerms=$terms&searchSort=$sort&searchSortDir=$sortdir&searchLang=$lang" =>
		'application/rss+xml'
	);

	$feed->link(
		atom =>
		$base .  "/$version/$org/atom-full/$class?searchTerms=$terms&searchSort=$sort&searchSortDir=$sortdir&searchLang=$lang" =>
		'application/atom+xml'
	);

	$feed->link(
		'html' =>
		$base .  "/$version/$org/html/$class?searchTerms=$terms&searchSort=$sort&searchSortDir=$sortdir&searchLang=$lang" =>
		'text/html'
	);

	$feed->link(
		'html-full' =>
		$base .  "/$version/$org/html-full/$class?searchTerms=$terms&searchSort=$sort&searchSortDir=$sortdir&searchLang=$lang" =>
		'text/html'
	);

	$feed->link( 'unapi-server' => $unapi);

	$log->debug("...feed links added...");

#	$feed->link(
#		opac =>
#		$root . "../$lang/skin/default/xml/rresult.xml?rt=list&" .
#			join('&', map { 'rl=' . $_->[0] } grep { ref $_ && defined $_->[0] } @{$recs->{ids}} ),
#		'text/html'
#	);

	#print $cgi->header( -type => $feed->type, -charset => 'UTF-8') . entityize($feed->toString) . "\n";
	print $cgi->header( -type => $feed->type, -charset => 'UTF-8') . $feed->toString . "\n";

	$log->debug("...and feed returned.");

	return Apache2::Const::OK;
}

sub create_record_feed {
	my $search = shift;
	my $type = shift;
	my $records = shift;
	my $unapi = shift;

	my $lib = uc(shift()) || '-';
	my $flesh = shift;
	$flesh = 1 if (!defined($flesh));

	my $cgi = new CGI;
	my $base = $cgi->url;
	my $host = $cgi->virtual_host || $cgi->server_name;

	my $year = (gmtime())[5] + 1900;

	my $flesh_feed = ($type =~ s/-full$//o) ? 1 : 0;

	my $feed = new OpenILS::WWW::SuperCat::Feed ($type);
	$feed->base($base) if ($flesh);
	$feed->unapi($unapi) if ($flesh);

	$type = 'atom' if ($type eq 'html');
	$type = 'marcxml' if ($type eq 'htmlholdings');

	#$records = $supercat->request( "open-ils.supercat.record.object.retrieve", $records )->gather(1);

	my $count = 0;
	for my $record (@$records) {
		next unless($record);

		#my $rec = $record->id;
		my $rec = $record;

		my $item_tag = "tag:$host,$year:biblio-record_entry/$rec/$lib";
		$item_tag = "tag:$host,$year:isbn/$rec/$lib" if ($search eq 'isbn');

		my $xml = $supercat->request(
			"open-ils.supercat.$search.$type.retrieve",
			$rec
		)->gather(1);
		next unless $xml;

		my $node = $feed->add_item($xml);
		next unless $node;

		$xml = '';
		if ($lib && $type eq 'marcxml' &&  $flesh) {
			my $r = $supercat->request( "open-ils.supercat.$search.holdings_xml.retrieve", $rec, $lib );
			while ( !$r->complete ) {
				$xml .= join('', map {$_->content} $r->recv);
			}
			$xml .= join('', map {$_->content} $r->recv);
			$node->add_holdings($xml);
		}

		$node->id($item_tag);
		#$node->update_ts(clense_ISO8601($record->edit_date));
		$node->link(alternate => $feed->unapi . "?id=$item_tag&format=htmlholdings-full" => 'text/html') if ($flesh);
		$node->link(opac => $feed->unapi . "?id=$item_tag&format=opac") if ($flesh);
		$node->link(unapi => $feed->unapi . "?id=$item_tag") if ($flesh);
		$node->link('unapi-id' => $item_tag) if ($flesh);
	}

	return $feed;
}

sub string_browse {
	my $apache = shift;
	return Apache2::Const::DECLINED if (-e $apache->filename);

	my $cgi = new CGI;
	my $year = (gmtime())[5] + 1900;

	my $host = $cgi->virtual_host || $cgi->server_name;

	my $add_path = 0;
	if ( $cgi->server_software !~ m|^Apache/2.2| ) {
		my $rel_name = $cgi->url(-relative=>1);
		$add_path = 1 if ($cgi->url(-path_info=>1) !~ /$rel_name$/);
	}

	my $url = $cgi->url(-path_info=>$add_path);
	my $root = (split 'browse', $url)[0];
	my $base = (split 'browse', $url)[0] . 'browse';
	my $unapi = (split 'browse', $url)[0] . 'unapi';

	my $path = $cgi->path_info;
	$path =~ s/^\///og;

	my ($format,$axis,$site,$string,$page,$page_size) = split '/', $path;
	#warn " >>> $format -> $axis -> $site -> $string -> $page -> $page_size ";

    return item_age_browse($apache) if ($axis eq 'item-age'); # short-circut to the item-age sub

	$site ||= $cgi->param('searchOrg');
	$page ||= $cgi->param('startPage') || 0;
	$page_size ||= $cgi->param('count') || 9;

	$page = 0 if ($page !~ /^-?\d+$/);

	my $prev = join('/', $base,$format,$axis,$site,$string,$page - 1,$page_size);
	my $next = join('/', $base,$format,$axis,$site,$string,$page + 1,$page_size);

	unless ($string and $axis and grep { $axis eq $_ } keys %browse_types) {
		warn "something's wrong...";
		warn " >>> $format -> $axis -> $site -> $string -> $page -> $page_size ";
		return undef;
	}

	$string = decode_utf8($string);
	$string =~ s/\+/ /go;
	$string =~ s/'//go;

	my $tree = $supercat->request(
		"open-ils.supercat.$axis.browse",
		$string,
		$site,
		$page_size,
		$page
	)->gather(1);

    (my $norm_format = $format) =~ s/-full$//o;

	my ($header,$content) = $browse_types{$axis}{$norm_format}->($tree,$prev,$next,$format,$unapi,$base,$site);
	print $header.$content;
	return Apache2::Const::OK;
}

sub item_age_browse {
	my $apache = shift;
	return Apache2::Const::DECLINED if (-e $apache->filename);

	my $cgi = new CGI;
	my $year = (gmtime())[5] + 1900;

	my $host = $cgi->virtual_host || $cgi->server_name;

	my $add_path = 0;
	if ( $cgi->server_software !~ m|^Apache/2.2| ) {
		my $rel_name = $cgi->url(-relative=>1);
		$add_path = 1 if ($cgi->url(-path_info=>1) !~ /$rel_name$/);
	}

	my $url = $cgi->url(-path_info=>$add_path);
	my $root = (split 'browse', $url)[0];
	my $base = (split 'browse', $url)[0] . 'browse';
	my $unapi = (split 'browse', $url)[0] . 'unapi';

	my $path = $cgi->path_info;
	$path =~ s/^\///og;

	my ($format,$axis,$site,$page,$page_size) = split '/', $path;
	#warn " >>> $format -> $axis -> $site -> $page -> $page_size ";

	unless ($axis eq 'item-age') {
		warn "something's wrong...";
		warn " >>> $format -> $axis -> $site -> $page -> $page_size ";
		return undef;
	}

	$site ||= $cgi->param('searchOrg') || '-';
	$page ||= $cgi->param('startPage') || 1;
	$page_size ||= $cgi->param('count') || 10;

	$page = 1 if ($page !~ /^-?\d+$/ || $page < 1);

	my $prev = join('/', $base,$format,$axis,$site,$page - 1,$page_size);
	my $next = join('/', $base,$format,$axis,$site,$page + 1,$page_size);

	my $recs = $supercat->request(
		"open-ils.supercat.new_book_list",
		$site,
		$page_size,
		$page
	)->gather(1);

    (my $norm_format = $format) =~ s/-full$//o;

	my ($header,$content) = $browse_types{$axis}{$norm_format}->($recs,$prev,$next,$format,$unapi,$base,$site);
	print $header.$content;
	return Apache2::Const::OK;
}

our %qualifier_map = (

    # Some EG qualifiers
    'eg.site'               => 'site',
    'eg.sort'               => 'sort',
    'eg.direction'          => 'dir',
    'eg.available'          => 'available',

    # Title class:
    'eg.title'              => 'title',
    'dc.title'              => 'title',
    'bib.titleabbreviated'  => 'title|abbreviated',
    'bib.titleuniform'      => 'title|uniform',
    'bib.titletranslated'   => 'title|translated',
    'bib.titlealternative'  => 'title',
    'bib.titleseries'       => 'series',
    'eg.series'             => 'title',

    # Author/Name class:
    'eg.author'             => 'author',
    'eg.name'               => 'author',
    'creator'               => 'author',
    'dc.creator'            => 'author',
    'dc.contributer'        => 'author',
    'dc.publisher'          => 'keyword',
    'bib.name'              => 'author',
    'bib.namepersonal'      => 'author|personal',
    'bib.namepersonalfamily'=> 'author|personal',
    'bib.namepersonalgiven' => 'author|personal',
    'bib.namecorporate'     => 'author|corporate',
    'bib.nameconference'    => 'author|conference',

    # Subject class:
    'eg.subject'            => 'subject',
    'dc.subject'            => 'subject',
    'bib.subjectplace'      => 'subject|geographic',
    'bib.subjecttitle'      => 'keyword',
    'bib.subjectname'       => 'subject|name',
    'bib.subjectoccupation' => 'keyword',

    # Keyword class:
    'eg.keyword'            => 'keyword',
    'srw.serverchoice'      => 'keyword',

    # Identifiers:
    'dc.identifier'         => 'keyword',

    # Dates:
    'bib.dateissued'        => undef,
    'bib.datecreated'       => undef,
    'bib.datevalid'         => undef,
    'bib.datemodified'      => undef,
    'bib.datecopyright'     => undef,

    # Resource Type:
    'dc.type'               => undef,

    # Format:
    'dc.format'             => undef,

    # Genre:
    'bib.genre'             => 'keyword',

    # Target Audience:
    'bib.audience'          => undef,

    # Place of Origin:
    'bib.originplace'       => undef,

    # Language
    'dc.language'           => 'lang',

    # Edition
    'bib.edition'           => 'keyword',

    # Part:
    'bib.volume'            => 'keyword',
    'bib.issue'             => 'keyword',
    'bib.startpage'         => 'keyword',
    'bib.endpage'           => 'keyword',

    # Issuance:
    'bib.issuance'          => 'keyword',
);

our %qualifier_ids = (
		eg => 'http://open-ils.org/spec/SRU/context-set/evergreen/v1',
		dc => 'info:srw/cql-context-set/1/dc-v1.1',
		bib => 'info:srw/cql-context-set/1/bib-v1.0',
		srw	=> ''
);

our %nested_qualifier_map = (
		eg => {
			site		=> ['site','Evergreen Site Code (shortname)'],
			sort		=> ['sort','Sort on relevance, title, author, pubdate, create_date or edit_date'],
			direction	=> ['dir','Sort direction (asc|desc)'],
			available	=> ['available','Filter to available (true|false)'],
			title		=> ['title'],
			author		=> ['author'],
			name		=> ['author'],
			subject		=> ['subject'],
			keyword		=> ['keyword'],
			series		=> ['series'],
		},
		dc => {
			title		=> ['title'],
			creator		=> ['author'],
			contributor	=> ['author'],
			publisher	=> ['keyword'],
			subject		=> ['subject'],
			identifier	=> ['keyword'],
			type		=> [undef],
			format		=> [undef],
			language	=> ['lang'],
		},
		bib => {
		# Title class:
	        titleAbbreviated	=> ['title'],
		    titleUniform		=> ['title'],
			titleTranslated		=> ['title'],
	        titleAlternative	=> ['title'],
		    titleSeries			=> ['series'],

    # Author/Name class:
			name				=> ['author'],
			namePersonal		=> ['author'],
			namePersonalFamily	=> ['author'],
			namePersonalGiven	=> ['author'],
			nameCorporate		=> ['author'],
			nameConference		=> ['author'],

		# Subject class:
			subjectPlace		=> ['subject'],
			subjectTitle		=> ['keyword'],
			subjectName			=> ['subject|name'],
			subjectOccupation	=> ['keyword'],

    # Keyword class:

    # Dates:
			dateIssued			=> [undef],
			dateCreated			=> [undef],
			dateValid			=> [undef],
			dateModified		=> [undef],
			dateCopyright		=> [undef],

    # Genre:
			genre				=> ['keyword'],

    # Target Audience:
			audience			=> [undef],

    # Place of Origin:
			originPlace			=> [undef],

    # Edition
			edition				=> ['keyword'],

    # Part:
			volume				=> ['keyword'],
			issue				=> ['keyword'],
			startPage			=> ['keyword'],
			endPage				=> ['keyword'],

    # Issuance:
			issuance			=> ['keyword'],
		},
		srw	=> {
			serverChoice		=> ['keyword'],
		},
);


my $base_explain = <<XML;
<explain
		id="evergreen-sru-explain-full"
		authoritative="true"
		xmlns:z="http://explain.z3950.org/dtd/2.0/"
		xmlns="http://explain.z3950.org/dtd/2.0/">
	<serverInfo transport="http" protocol="SRU" version="1.1">
		<host/>
		<port/>
		<database/>
	</serverInfo>

	<databaseInfo>
		<title primary="true"/>
		<description primary="true"/>
	</databaseInfo>

	<indexInfo>
		<set identifier="info:srw/cql-context-set/1/cql-v1.2" name="cql"/>
	</indexInfo>

	<schemaInfo>
		<schema
				identifier="info:srw/schema/1/marcxml-v1.1"
				location="http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd"
				sort="true"
				retrieve="true"
				name="marcxml">
			<title>MARC21Slim (marcxml)</title>
		</schema>
	</schemaInfo>

	<configInfo>
		<default type="numberOfRecords">10</default>
		<default type="contextSet">eg</default>
		<default type="index">keyword</default>
		<default type="relation">all</default>
		<default type="sortSchema">marcxml</default>
		<default type="retrieveSchema">marcxml</default>
		<setting type="maximumRecords">10</setting>
		<supports type="relationModifier">relevant</supports>
		<supports type="relationModifier">stem</supports>
		<supports type="relationModifier">fuzzy</supports>
		<supports type="relationModifier">word</supports>
	</configInfo>

</explain>
XML


my $ex_doc;
sub sru_search {
	my $cgi = new CGI;

	my $req = SRU::Request->newFromCGI( $cgi );
	my $resp = SRU::Response->newFromRequest( $req );

	# Find the org_unit shortname, if passed as part of the URL
	# http://example.com/opac/extras/sru/SHORTNAME
	my $url = $cgi->path_info;
	my ($shortname, $holdings) = $url =~ m#/?([^/]*)(/holdings)?#;

	if ( $resp->type eq 'searchRetrieve' ) {
		my $cql_query = $req->query;
		my $search_string = $req->cql->toEvergreen;

		# Ensure the search string overrides the default site
		if ($shortname and $search_string !~ m#site:#) {
			$search_string .= " site:$shortname";
		}

        my $offset = $req->startRecord;
        $offset-- if ($offset);
        $offset ||= 0;

        my $limit = $req->maximumRecords;
        $limit ||= 10;

        $log->info("SRU search string [$cql_query] converted to [$search_string]\n");

 		my $recs = $search->request(
			'open-ils.search.biblio.multiclass.query' => {offset => $offset, limit => $limit} => $search_string => 1
		)->gather(1);

        my $bre = $supercat->request( 'open-ils.supercat.record.object.retrieve' => [ map { $_->[0] } @{$recs->{ids}} ] )->gather(1);

		foreach my $record (@$bre) {
			my $marcxml = $record->marc;
			# Make the beast conform to a VDX-supported format
			# See http://vdxipedia.oclc.org/index.php/Holdings_Parsing
			# Trying to implement LIBSOL_852_A format; so much for standards
			if ($holdings) {
				my $bib_holdings = $supercat->request('open-ils.supercat.record.basic_holdings.retrieve', $record->id, $shortname || '-')->gather(1);
				my $marc = MARC::Record->new_from_xml($marcxml, 'UTF8', 'XML');

				# Expects the record ID in the 001
				$marc->delete_field($_) for ($marc->field('001'));
				if (!$marc->field('001')) {
					$marc->insert_fields_ordered(
						MARC::Field->new( '001', $record->id )
					);
				}
				foreach my $cn (keys %$bib_holdings) {
					foreach my $cp (@{$bib_holdings->{$cn}->{'copies'}}) {
						$marc->insert_fields_ordered(
							MARC::Field->new(
								'852', '4', '',
								a => $cp->{'location'},
								b => $bib_holdings->{$cn}->{'owning_lib'},
								c => $cn,
								d => $cp->{'circlib'},
								g => $cp->{'barcode'},
								n => $cp->{'status'},
							)
						);
					}
				}

				$marc->delete_field( $_ ) for ($marc->field(901));
				$marc->append_fields(
					MARC::Field->new(
						901, '', '', 
						a => $record->tcn_value,
						b => $record->tcn_source,
						c => $record->id
					)
				);

				$marcxml = $marc->as_xml();
				$marcxml =~ s/^<\?xml version="1.0" encoding="UTF-8"\?>//o;

			}
			$resp->addRecord(
				SRU::Response::Record->new(
					recordSchema    => 'info:srw/schema/1/marcxml-v1.1',
					recordData => $marcxml
				)
			);
		}

        $resp->numberOfRecords($recs->{count});

    } elsif ( $resp->type eq 'explain' ) {
		if (!$ex_doc) {
			my $host = $cgi->virtual_host || $cgi->server_name;

			my $add_path = 0;
			if ( $cgi->server_software !~ m|^Apache/2.2| ) {
				my $rel_name = $cgi->url(-relative=>1);
				$add_path = 1 if ($cgi->url(-path_info=>1) !~ /$rel_name$/);
			}
			my $base = $cgi->url(-base=>1);
			my $url = $cgi->url(-path_info=>$add_path);
			$url =~ s/^$base\///o;

			my $doc = $parser->parse_string($base_explain);
			my $e = $doc->documentElement;
			$e->findnodes('/z:explain/z:serverInfo/z:host')->shift->appendText( $host );
			$e->findnodes('/z:explain/z:serverInfo/z:port')->shift->appendText( $cgi->server_port );
			$e->findnodes('/z:explain/z:serverInfo/z:database')->shift->appendText( $url );

			for my $name ( keys %OpenILS::WWW::SuperCat::nested_qualifier_map ) {

				my $identifier = $OpenILS::WWW::SuperCat::qualifier_ids{ $name };

				next unless $identifier;

				my $set_node = $doc->createElementNS( 'http://explain.z3950.org/dtd/2.0/', 'set' );
				$set_node->setAttribute( identifier => $identifier );
				$set_node->setAttribute( name => $name );

				$e->findnodes('/z:explain/z:indexInfo')->shift->appendChild( $set_node );

				for my $index ( keys %{ $OpenILS::WWW::SuperCat::nested_qualifier_map{$name} } ) {
					my $desc = $OpenILS::WWW::SuperCat::nested_qualifier_map{$name}{$index}[1] || $index;

					my $name_node = $doc->createElementNS( 'http://explain.z3950.org/dtd/2.0/', 'name' );

					my $map_node = $doc->createElementNS( 'http://explain.z3950.org/dtd/2.0/', 'map' );
					$map_node->appendChild( $name_node );

					my $title_node = $doc->createElementNS( 'http://explain.z3950.org/dtd/2.0/', 'title' );

					my $index_node = $doc->createElementNS( 'http://explain.z3950.org/dtd/2.0/', 'index' );
					$index_node->appendChild( $title_node );
					$index_node->appendChild( $map_node );

					$index_node->setAttribute( id => $name . '.' . $index );
					$title_node->appendText( $desc );
					$name_node->setAttribute( set => $name );
					$name_node->appendText($index );

					$e->findnodes('/z:explain/z:indexInfo')->shift->appendChild( $index_node );
				}
			}

			$ex_doc = $e->toString;
		}

		$resp->record(
			SRU::Response::Record->new(
				recordSchema	=> 'info:srw/cql-context-set/2/zeerex-1.1',
				recordData		=> $ex_doc
			)
		);
	}

   	print $cgi->header( -type => 'application/xml' );
   	print $U->entityize($resp->asXML) . "\n";
    return Apache2::Const::OK;
}


{
    package CQL::BooleanNode;

    sub toEvergreen {
        my $self     = shift;
        my $left     = $self->left();
        my $right    = $self->right();
        my $leftStr  = $left->toEvergreen;
        my $rightStr = $right->toEvergreen();

        my $op =  '||' if uc $self->op() eq 'OR';
        $op ||=  '&&';

        return  "$leftStr $rightStr";
    }

    package CQL::TermNode;

    sub toEvergreen {
        my $self      = shift;
        my $qualifier = $self->getQualifier();
        my $term      = $self->getTerm();
        my $relation  = $self->getRelation();

        my $query;
        if ( $qualifier ) {
			my ($qset, $qname) = split(/\./, $qualifier);

			$log->debug("SRU toEvergreen: $qset, $qname   $OpenILS::WWW::SuperCat::nested_qualifier_map{$qset}{$qname}[0]\n");

            if ( exists($OpenILS::WWW::SuperCat::nested_qualifier_map{$qset}{$qname}) ) {
                $qualifier = $OpenILS::WWW::SuperCat::nested_qualifier_map{$qset}{$qname}[0] || 'kw';
			}

            my @modifiers = $relation->getModifiers();

            my $base = $relation->getBase();
            if ( grep { $base eq $_ } qw/= scr exact all/ ) {

                my $quote_it = 1;
                foreach my $m ( @modifiers ) {
                    if( grep { $m->[ 1 ] eq $_ } qw/cql.fuzzy cql.stem cql.relevant cql.word/ ) {
                        $quote_it = 0;
                        last;
                    }
                }

                $quote_it = 0 if ( $base eq 'all' );
                $term = maybeQuote($term) if $quote_it;

            } else {
                croak( "Evergreen doesn't support the $base relations" );
            }


        } else {
            $qualifier = "kw";
        }

        return "$qualifier:$term";
    }
}

1;

# vim: noet:ts=4:sw=4
