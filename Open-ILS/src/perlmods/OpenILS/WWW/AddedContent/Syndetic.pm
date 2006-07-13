package OpenILS::WWW::AddedContent::Syndetic;
use strict; use warnings;
use LWP::UserAgent;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenSRF::Utils::SettingsParser;
use JSON;
use OpenSRF::EX qw/:try/;



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
	return $self->send_html(
		$self->fetch_content('toc.html', $key));
}

sub toc_xml {
	my( $self, $key ) = @_;
	return $self->send_xml(
		$self->fetch_content('toc.xml', $key));
}

sub toc_json {
	my( $self, $key ) = @_;
	return $self->send_json(
		$self->fetch_content('toc.xml', $key));
}

# --------------------------------------------------------------------------

sub anotes_html {
	my( $self, $key ) = @_;
	return $self->send_html(
		$self->fetch_content('anotes.html', $key));
}

sub anotes_xml {
	my( $self, $key ) = @_;
	return $self->send_xml(
		$self->fetch_content('anotes.xml', $key));
}

sub anotes_json {
	my( $self, $key ) = @_;
	return $self->send_json(
		$self->fetch_content('anotes.xml', $key));
}


# --------------------------------------------------------------------------

sub excerpt_html {
	my( $self, $key ) = @_;
	return $self->send_html(
		$self->fetch_content('dbchapter.html', $key));
}

sub excerpt_xml {
	my( $self, $key ) = @_;
	return $self->send_xml(
		$self->fetch_content('dbchapter.xml', $key));
}

sub excerpt_json {
	my( $self, $key ) = @_;
	return $self->send_json(
		$self->fetch_content('dbchapter.xml', $key));
}

# --------------------------------------------------------------------------

sub reviews_html {
	my( $self, $key ) = @_;

	my %reviews;

	$reviews{ljreview} = $self->fetch_content('ljreview.html', $key);
	$reviews{pwreview} = $self->fetch_content('pwreview.html', $key);
	$reviews{slreview} = $self->fetch_content('slreview.html', $key);
	$reviews{chreview} = $self->fetch_content('chreview.html', $key);
	$reviews{blreview} = $self->fetch_content('blreview.html', $key);
	$reviews{hbreview} = $self->fetch_content('hbreview.html', $key);
	$reviews{kirkreview} = $self->fetch_content('kirkreview.html', $key);

	for(keys %reviews) {
		if( ! $self->data_exists($reviews{$_}) ) {
			delete $reviews{$_};
			next;
		}
		$reviews{$_} =~ s/<!.*?>//og; # Strip any doctype declarations
	}

	return 0 if scalar(keys %reviews) == 0;
	
	#my $html = "<div>";
	my $html;
	$html .= $reviews{$_} for keys %reviews;
	#$html .= "</div>";

	return $self->send_html($html);
}

# we have to aggregate the reviews
sub reviews_xml {
	my( $self, $key ) = @_;
	my %reviews;

	$reviews{ljreview} = $self->fetch_content('ljreview.xml', $key);
	$reviews{pwreview} = $self->fetch_content('pwreview.xml', $key);
	$reviews{slreview} = $self->fetch_content('slreview.xml', $key);
	$reviews{chreview} = $self->fetch_content('chreview.xml', $key);
	$reviews{blreview} = $self->fetch_content('blreview.xml', $key);
	$reviews{hbreview} = $self->fetch_content('hbreview.xml', $key);
	$reviews{kirkreview} = $self->fetch_content('kirkreview.xml', $key);

	for(keys %reviews) {
		if( ! $self->data_exists($reviews{$_}) ) {
			delete $reviews{$_};
			next;
		}
		# Strip the xml and doctype declarations
		$reviews{$_} =~ s/<\?xml.*?>//og;
		$reviews{$_} =~ s/<!.*?>//og;
	}

	return 0 if scalar(keys %reviews) == 0;
	
	my $xml = "<reviews>";
	$xml .= $reviews{$_} for keys %reviews;
	$xml .= "</reviews>";

	return $self->send_xml($xml);
}


sub reviews_json {
	my( $self, $key ) = @_;
	return $self->send_json(
		$self->fetch_content('dbchapter.xml', $key));
}

# --------------------------------------------------------------------------


sub data_exists {
	my( $self, $data ) = @_;
	return 0 if $data =~ m/<title>error<\/title>/iog;
	return 1;
}


sub send_json {
	my( $self, $xml ) = @_;
	return 0 unless $self->data_exists($xml);
	my $doc;

	try {
		$doc = XML::LibXML->new->parse_string($xml);
	} catch Error with {
		my $err = shift;
		$logger->error("added content XML parser error: $err\n\n$xml");
		$doc = undef;
	};

	return 0 unless $doc;
	my $perl = OpenSRF::Utils::SettingsParser::XML2perl($doc->documentElement);
	my $json = JSON->perl2JSON($perl);
	print "Content-type: text/plain\n\n";
	print $json;
	return 1;
}

sub send_xml {
	my( $self, $xml ) = @_;
	return 0 unless $self->data_exists($xml);
	print "Content-Type: application/xml\n\n";
	print $xml;
	return 1;
}

sub send_html {
	my( $self, $content ) = @_;
	return 0 unless $self->data_exists($content);

	# Hide anything that might contain a link since it will be broken
	my $HTML = <<"	HTML";
		<div>
			<style type='text/css'>
				div.ac input, div.ac a[href],div.ac img, div.ac button { display: none; visibility: hidden }
			</style>
			<div class='ac'>
				$content
			</div>
		</div>
	HTML

	print "Content-type: text/html\n\n";
	print $HTML;

	return 1;
}

sub fetch_content {
	my( $self, $page, $key ) = @_;
	my $uname = $self->userid;
	my $url = $self->base_url . "?isbn=$key/$page&client=$uname&type=rw12";
	$logger->info("added content URL = $url");
	my $agent = LWP::UserAgent->new;
	my $res = $agent->get($url);
	die "added content request failed: " . $res->status_line ."\n" unless $res->is_success;
	return $res->content;
}


1;
