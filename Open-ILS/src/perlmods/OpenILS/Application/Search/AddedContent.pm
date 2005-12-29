package OpenILS::Application::Search::AddedContent;
use base qw/OpenSRF::Application/;
use strict; use warnings;

sub initialize { return 1; }


__PACKAGE__->register_method(
	method	=> "summary",
	api_name	=> "open-ils.search.added_content.summary.retrieve",
	notes		=> <<"	NOTE");
		Returns an object like so:
			{
				Review		: true/false
				Inventory	: true/false
				Annotation	: true/false
				Jacket		: true/false
				TOC			: true/false
				Product		: true/false
			}
		This object indicates the existance of each type of added content for the given ISBN
		PARAMS( ISBN ),
	NOTE

sub summary {
	return { 
		Review		=> "false",
		Inventory	=> "false",
		Annotation	=> "false",
		Jacket		=> "false",
		TOC			=> "false",
		Product		=> "false",
	};
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

sub reviews { return []; }


__PACKAGE__->register_method(
	method	=> "toc",
	api_name	=> "open-ils.search.added_content.toc.retrieve",
	notes		=> <<"	NOTE");
		Returns the table of contents for the given ISBN
		PARAMS( ISBN ),
	NOTE

sub toc { return ""; }


1;
