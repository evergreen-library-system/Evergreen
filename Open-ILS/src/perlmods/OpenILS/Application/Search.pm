package OpenILS::Application::Search;
use base qw/OpenSRF::Application/;
use strict; use warnings;
use JSON;
use OpenSRF::Utils::Logger qw(:logger);

use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::ModsParser;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Cache;

use OpenILS::Application::Search::Biblio;
use OpenILS::Application::Search::Authority;
use OpenILS::Application::Search::Z3950;
use OpenILS::Application::Search::Zips;
use OpenILS::Application::Search::CNBrowse;


use OpenILS::Application::AppUtils;

use Time::HiRes qw(time);
use OpenSRF::EX qw(:try);

use Text::Aspell; 

# Houses generic search utilites 

sub initialize {
	OpenILS::Application::Search::Z3950->initialize();
	OpenILS::Application::Search::Zips->initialize();
	OpenILS::Application::Search::Biblio->initialize();
}
	


# ------------------------------------------------------------------
# Create custome dictionaries like so:
# aspell --lang=en create  master ./oils_authority.dict < /tmp/words
# where /tmp/words is a space separated list of words
# ------------------------------------------------------------------

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
