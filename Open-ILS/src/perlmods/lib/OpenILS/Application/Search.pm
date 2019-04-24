package OpenILS::Application::Search;
use OpenILS::Application;
use base qw/OpenILS::Application/;
use strict; use warnings;
use OpenSRF::Utils::JSON;
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
use OpenILS::Application::Search::Serial;
use OpenILS::Application::Search::Browse;


use OpenILS::Application::AppUtils;

use Time::HiRes qw(time);
use OpenSRF::EX qw(:try);

use Text::Aspell; 

# Houses generic search utilites 

sub initialize {
    OpenILS::Application::Search::Zips->initialize();
    OpenILS::Application::Search::Biblio->initialize();
}

sub child_init {
    OpenILS::Application::Search::Z3950->child_init;
    OpenILS::Application::Search::Browse->child_init;
}
    


# ------------------------------------------------------------------
# Create custom dictionaries like so:
# aspell --lang=en create  master ./oils_authority.dict < /tmp/words
# where /tmp/words is a space separated list of words
# ------------------------------------------------------------------

__PACKAGE__->register_method(
    method    => "spellcheck",
    api_name  => "open-ils.search.spellcheck",
    signature => {
        desc  => 'Returns alternate spelling suggestions',
        param => [
            {
                name => 'phrase',
                desc => 'Word or phrase to return alternate spelling suggestions for',
                type => 'string'
            },
            {
                name => 'Dictionary class',
                desc => 'Alternate configured dictionary to use (optional)',
                type => 'string'
            },
        ],
        return => {
            desc => 'Array with a suggestions hash for each word in the phrase, like: '
                  . q# [{ word: original_word, suggestions: [sug1, sug2, ...], found: 1 }, ... ] #
                  . 'The "found" value will be 1 if the word was found in the dictionary, 0 otherwise.',
            type => 'array',
        }
    }
);

my $speller = Text::Aspell->new();

sub spellcheck {
    my( $self, $client, $phrase, $class ) = @_;

    return [] unless $phrase;   # nothing to check, abort.

    my $conf = OpenSRF::Utils::SettingsClient->new;
    $class ||= 'default';

    my @conf_path = (apps => 'open-ils.search' => app_settings => spelling_dictionary => $class);

    if( my $dict = $conf->config_value(@conf_path) ) {
        $speller->set_option('master', $dict);
        $logger->debug("spelling dictionary set to $dict");
    }

    $speller->set_option('ignore-case', 'true');

    my @resp;

    for my $word (split(/\s+/,$phrase) ) {

        my @suggestions = $speller->suggest($word);
        my @trimmed;

        for my $sug (@suggestions) {

            # suggestion matches alternate case of original word
            next if lc($sug) eq lc($word); 

            # suggestion matches alternate case of already suggested word
            next if grep { lc($sug) eq lc($_) } @trimmed;

            push(@trimmed, $sug);
        }

        push( @resp, 
            {
                word => $word, 
                suggestions => (@trimmed) ? [@trimmed] : undef,
                found => $speller->check($word)
            } 
        ); 
    }
    return \@resp;
}



1;
