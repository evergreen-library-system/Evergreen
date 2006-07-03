package OpenILS::Utils::PermitHold;
use strict; use warnings;
use Data::Dumper;
use OpenSRF::Utils;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::ScriptRunner;
use OpenILS::Application::AppUtils;
use OpenILS::Application::Circ::ScriptBuilder;
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

	my $runner = OpenILS::Application::Circ::ScriptBuilder->build(
		{
			patron		=> $$params{patron},
			copy			=> $$params{copy},
			requestor	=> $$params{requestor},
			titleDescriptor	=> $$params{title_descriptor},
			_direct	=> {
				requestLib	=> $$params{request_lib},
				pickupLib	=> $$params{pickup_lib},
			}
		}
	);

	$logger->debug("Running permit_copy_hold on copy " . $$params{copy}->id);

	load_scripts($runner);
	my $result = $runner->run or throw OpenSRF::EX::ERROR ("Hold Copy Permit Script Died: $@");

	# --------------------------------------------------------------
	# Extract and uniquify the event list
	# --------------------------------------------------------------
	my $events = $result->{events};
	$logger->debug("circ_permit_hold for user ".$params->{patron}->id." returned events: @$events");

	my @allevents;
	push( @allevents, OpenILS::Event->new($_)) for @$events;
	my %hash = map { ($_->{ilsevent} => $_) } @allevents;
	@allevents = values %hash;

	return \@allevents if $$params{show_event_list};
	return 1 unless @allevents;
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
