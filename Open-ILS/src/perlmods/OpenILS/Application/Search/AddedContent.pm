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
	member		=> "Member.asmx",
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



# Fetches the added content and returns the data as a string.
# If not data is retrieved (or timeout occurs), undef is returned
sub retrieve_added_content {
	my( $type, $isbn, $summary ) = @_;

	my $func = "fnDetailByItemKey";
	if($summary) { $func = "fnContentByItemKey"; }

	my $url = "$host/$urlbase/" . $types->{$type} . 
		"/$func?UserId=$username&Password=$password&ItemKey=$isbn";


	warn "Added Content URL: $url\n";

	my $data = undef;
	try {
		alarm(15);
		$data = LWP::UserAgent->new->get($url)->content;
		alarm(0);
	} catch Error with {
		alarm(0);
	};
	alarm(0);

	warn "received content data:\n$data\n";
	return $data;
}

__PACKAGE__->register_method(
	method	=> "summary",
	api_name	=> "open-ils.search.added_content.summary.retrieve",
	notes		=> <<"	NOTE");
		Returns an object like so:
			{
				Review : true/false,
				Inventory : true/false,
				Annotation : true/false,
				Jacket : true/false
				TOC : true/false
				Product : true/false
			}
		This object indicates the existance of each type of added content for the given ISBN
		PARAMS( ISBN ),
	NOTE

sub summary {
	my( $self, $client, $isbn ) = @_;
	my $data = retrieve_added_content( "member", $isbn, 1 );
	my $doc = XML::LibXML->new->parse_string($data);
	my $summary = {};
	return $summary unless $doc;

	for my $node ( $doc->getDocumentElement->childNodes ) {
		if( $node->localName ) {
			$summary->{$node->localName} = $node->textContent;	
		}
	}
	return $summary;
}





__PACKAGE__->register_method(
	method	=> "reviews",
	api_name	=> "open-ils.search.added_content.review.retrieve.random",
	notes		=> <<"	NOTE");
		Returns a singe random review article object
		PARAMS( ISBN ),
	NOTE

__PACKAGE__->register_method(
	method	=> "reviews",
	api_name	=> "open-ils.search.added_content.review.retrieve.all",
	notes		=> <<"	NOTE");
		Returns an array review article objects
		PARAMS( ISBN ),
	NOTE

sub reviews {
	my( $self, $client, $isbn ) = @_;

	my $data = retrieve_added_content( "review", $isbn );
	my $doc = XML::LibXML->new->parse_string($data);
	my $ret = [];

	if(!$doc) {
		if( $self->api_name =~ /random/ ) { return undef; }
		return $ret;
	}

	my $reviews = $doc->findnodes("//*[local-name()='Review']");

	for my $rev ( $reviews->get_nodelist() ) {
		my $revobj = {};
		for my $node ($rev->childNodes) {

			if( $node->localName ) {
				if( $node->localName eq "ReviewText" ) {
					$revobj ->{'text'} = $node->textContent;
				}
				if( $node->localName eq "ReviewLiteral" ) {
					$revobj->{'info'} = $node->textContent;
				}

			}
		}

		if( $self->api_name =~ /random/ ) { return $revobj; }
		push( @$ret, $revobj );
	}

	return $ret;
}


__PACKAGE__->register_method(
	method	=> "toc",
	api_name	=> "open-ils.search.added_content.toc.retrieve",
	notes		=> <<"	NOTE");
		Returns the table of contents for the given ISBN
		PARAMS( ISBN ),
	NOTE

sub toc {
	my( $self, $client, $isbn ) = @_;

	my $data = retrieve_added_content( "toc", $isbn );
	my $doc = XML::LibXML->new->parse_string($data);
	my $ret = {};

	my @nodes =  $doc->findnodes("//*[local-name()='TOCText']")->get_nodelist();
		
	if($nodes[0]) {
		return $nodes[0]->textContent;
	}

	return "";
}


1;
