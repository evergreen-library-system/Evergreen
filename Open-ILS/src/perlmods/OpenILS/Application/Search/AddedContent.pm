package OpenILS::Application::Search::AddedContent;
use base qw/OpenSRF::Application/;
use strict; use warnings;
use OpenILS::Application::AppUtils;
use OpenSRF::Utils::SettingsClient;
my $apputils = "OpenILS::Application::AppUtils";
use XML::LibXML;
use LWP::UserAgent;
use OpenSRF::EX qw(:try);


my $host;
my $username;
my $password;
my $urlbase = "ContentCafe";
my $types = {
	toc			=> "TOC.asmx",
	review		=> "Review.asmx",
	annotation	=> "Annotation.asmx",
	};

sub initialize {
	my $conf = OpenSRF::Utils::SettingsClient->new;
	$host = $conf->config_value(					
		"apps", "open-ils.search","app_settings", "added_content", "host");
	$username = $conf->config_value(					
		"apps", "open-ils.search","app_settings", "added_content", "username");
	$password = $conf->config_value(					
		"apps", "open-ils.search","app_settings", "added_content", "password");
}



__PACKAGE__->register_method(
	method	=> "added_content",
	api_name	=> "open-ils.search.added_content.retrieve",
	notes		=> <<"	NOTE");
		Returns a list values based on the added content type. 
		types include: toc, review, annotation
		PARAMS( ISBN ),
	NOTE

sub added_content {
	my( $self, $client, $isbn, $type ) = @_;

	my $url = "$host/$urlbase/" . $types->{$type} . 
		"/fnDetailByItemKey?UserId=$username&Password=$password&ItemKey=$isbn";

	warn "Added Content URL: $url\n";

	my $data;
	try {
		alarm(15);
		$data = LWP::UserAgent->new->get($url)->content;
		alarm(0);
	} catch Error with {
		alarm(0);
		$data = [];
	};
	alarm(0);

	warn "received content data:\n$data\n";

	return $data if(ref($data));

	return _parse_content($type, $data);
}

sub _parse_content {
	my( $type, $data ) = @_;

	my $doc = XML::LibXML->new->parse_string($data);
	my $ret = [];
	return $ret unless $doc;

	if( $type eq "review" ) {

		warn '-'x50 . "\n";
		warn $doc->toString(1) . "\n";
		warn '-'x50 . "\n";

		my $nodelist = $doc->findnodes("//*[local-name()='ReviewText']");
		for my $rev ( $nodelist->get_nodelist() ) {
			push( @$ret, $rev->textContent );
		}
	}

	return $ret;
}


1;
