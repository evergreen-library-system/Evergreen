package OpenILS::Utils::PermitHold;
use strict; use warnings;
use Data::Dumper;
use OpenSRF::Utils;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::ScriptRunner;
use OpenILS::Application::AppUtils;
use OpenSRF::Utils::Logger qw(:logger);
my $U	= "OpenILS::Application::AppUtils";

my $script;			# - the permit script
my $script_libs;	# - extra script libs

# mental note:  open-ils.storage.biblio.record_entry.ranged_tree


# params within a hash are: copy, patron, 
# requestor, request_lib, title, title_descriptor
sub permit_copy_hold {

	my $params	= shift;
	my $k			= 'environment';
	my $runner	= OpenILS::Utils::ScriptRunner->new;

	$runner->insert( "$k.patron",				$$params{patron},				1);
	$runner->insert( "$k.title",				$$params{title},				1);
	$runner->insert( "$k.copy",				$$params{copy},				1);
	$runner->insert( "$k.requestor",			$$params{requestor},			1);
	$runner->insert( "$k.requestLib",		$$params{request_lib},		1);
	$runner->insert( "$k.titleDescriptor",	$$params{title_descriptor},1);

	# we get the script result from the event 
	$runner->insert( "result.event",	'SUCCESS' );

	load_scripts($runner);
	$runner->run or throw OpenSRF::EX::ERROR ("Hold Copy Permit Script Died: $@");
	my $evtname = $runner->retrieve('result.event');

	return 1 if $evtname eq 'SUCCESS';
	return 0;
}


sub load_scripts {
	my $runner = shift;

	if(!$script) {
		my $conf = OpenSRF::Utils::SettingsClient->new;
		my @pfx	= ( "apps", "open-ils.circ","app_settings" );
		my $libs	= $conf->config_value(@pfx, 'script_path');
		$script	= $conf->config_value(@pfx, 'scripts', 'circ_permit_hold');
		$script_libs = (ref($libs)) ? $libs : [$libs];
	}

	$runner->add_path($_) for(@$script_libs);
	$runner->load($script);
}



23;
