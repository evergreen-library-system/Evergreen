package OpenILS::WWW::AddedContent::Syndetic;
use strict; use warnings;
use LWP::UserAgent;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenSRF::Utils::SettingsParser;
use JSON;


sub new {
	my( $class, $args ) = @_;
	$class = ref $class || $class;
	return bless($args, $class);
}

sub base_url {
	my $self = shift;
	return $self->{base_url};
}

sub userid {
	my $self = shift;
	return $self->{userid};
}


# --------------------------------------------------------------------------

sub toc_html {
	my( $self, $key ) = @_;
	return $self->handle_html(
		$self->fetch_content('toc.html', $key));
}

sub toc_xml {
	my( $self, $key ) = @_;
	return $self->handle_xml(
		$self->fetch_content('toc.xml', $key));
}

sub toc_json {
	my( $self, $key ) = @_;
	return $self->handle_json(
		$self->fetch_content('toc.xml', $key));
}


# --------------------------------------------------------------------------

sub excerpt_html {
	my( $self, $key ) = @_;
	return $self->handle_html(
		$self->fetch_content('dbchapter.html', $key));
}

sub excerpt_xml {
	my( $self, $key ) = @_;
	return $self->handle_xml(
		$self->fetch_content('dbchapter.xml', $key));
}

sub excerpt_json {
	my( $self, $key ) = @_;
	return $self->handle_json(
		$self->fetch_content('dbchapter.xml', $key));
}


# --------------------------------------------------------------------------

sub handle_json {
	my( $self, $xml ) = @_;
	return 0 if $xml =~ m/<title>error<\/title>/og;
	my $doc = XML::LibXML->new->parse_string($xml);
	return 0 unless $doc;
	my $perl = OpenSRF::Utils::SettingsParser::XML2perl($doc->documentElement);
	my $json = JSON->perl2JSON($perl);
	print "Content-type: text/plain\n\n";
	print $json;
	return 1;
}

sub handle_xml {
	my( $self, $xml ) = @_;
	return 0 if $xml =~ m/<title>error<\/title>/og;
	print "Content-Type: application/xml\n\n";
	print $xml;
	return 1;
}


sub handle_html {
	my( $self, $content ) = @_;
	return 0 if $content =~ m/<title>error<\/title>/og;

	# Strip images because they lead to broken links
	$content =~ s#<img.*?>.*?</img>##iog;
	$content =~ s#<img.*?/>##iog;
	$content =~ s#<img.*?>##iog; # - it may not be valid xml

	print "Content-type: text/html\n\n";
	print $content;

	return 1;
}

sub fetch_content {
	my( $self, $page, $key ) = @_;
	my $uname = $self->userid;
	my $url = $self->base_url . "?isbn=$key/$page&client=$uname&type=rw12";
	$logger->info("added content URL = $url");
	my $agent = LWP::UserAgent->new;
	my $res = $agent->get($url);
	die "added content request failed: $res->status_line\n" unless $res->is_success;
	return $res->content;
}


1;
