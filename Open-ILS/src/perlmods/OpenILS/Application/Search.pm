package OpenILS::Application::Search;
use base qw/OpenSRF::Application/;
use strict; use warnings;
use JSON;
use OpenSRF::Utils::Logger qw(:logger);

use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::ModsParser;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Cache;


#use OpenILS::Application::Search::StaffClient;
use OpenILS::Application::Search::Biblio;
use OpenILS::Application::Search::Authority;
#use OpenILS::Application::Search::Actor;
use OpenILS::Application::Search::Z3950;
use OpenILS::Application::Search::Zips;


use OpenILS::Application::AppUtils;

use Time::HiRes qw(time);
use OpenSRF::EX qw(:try);

use Text::Aspell; # spell checking...

# Houses generic search utilites 

sub initialize {
	OpenILS::Application::Search::Z3950->initialize();
	OpenILS::Application::Search::Zips->initialize();

	# try to load the added content handler
	my $conf = OpenSRF::Utils::SettingsClient->new;
	my $implementation = $conf->config_value(					
		"apps", "open-ils.search","app_settings", "added_content", "implementation" );

	$implementation = "OpenILS::Application::Search::AddedContent" unless $implementation;

	$logger->debug("Attempting to load Added Content handler: $implementation");

	eval "use $implementation";

	if($@) {	
		$logger->error("Unable to load Added Content handler [$implementation]: $@"); 
		return; 
	}

	eval { $implementation->initialize(); };
}
	


__PACKAGE__->register_method(
	method	=> "check_spelling",
	api_name	=> "open-ils.search.spell_check");

sub check_spelling {
	my( $self, $client, $phrase ) = @_;

	my @resp_objects = ();
	my $speller = Text::Aspell->new();
	$speller->set_option('lang', 'en_US');
	my $return_something = 0;

	my $return_phrase = "";

	for my $word (split(' ',$phrase) ) {
		if( ! $speller->check($word) ) {
			if( $speller->suggest($word) ) { $return_something = 1; }
			my $word_stuff = {};
			$word_stuff->{'word'} = $word;
			$word_stuff->{'suggestions'} = [ $speller->suggest( $word ) ];
			if( ! $return_phrase ) { $return_phrase = ($speller->suggest($word))[0]; }
			else { $return_phrase .= " " . ($speller->suggest($word))[0];}
			
		} else { 
			if( ! $return_phrase ) { $return_phrase = $word; }
			else { $return_phrase .= " $word"; }
		}
	}

	if( $return_something ) { return $return_phrase; }
	return 0;

}



__PACKAGE__->register_method(
	method	=> "spellcheck",
	api_name	=> "open-ils.search.spellcheck");

my $speller = Text::Aspell->new();

sub spellcheck {
	my( $self, $client, $phrase ) = @_;

	my $conf = OpenSRF::Utils::SettingsClient->new;

	if( my $dict = $conf->config_value(
			"apps", "open-ils.search", "app_settings", "spelling_dictionary")) {
		$speller->set_option('master', $dict);
		$logger->debug("spelling dictionary set to $dict");
	}

	my @resp;
	return \@resp unless $phrase;
	for my $word (split(/\s+/,$phrase) ) {
		push( @resp, 
			{
				word => $word, 
				suggestions => ($speller->check($word)) ? undef : [$speller->suggest($word)]
			} 
		); 
	}
	return \@resp;
}



1;
