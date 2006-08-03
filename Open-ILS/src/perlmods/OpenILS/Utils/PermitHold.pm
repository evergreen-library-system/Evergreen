package OpenILS::Utils::PermitHold;
use strict; use warnings;
use Data::Dumper;
use OpenSRF::Utils;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::ScriptRunner;
use OpenILS::Application::AppUtils;
use DateTime::Format::ISO8601;
use OpenILS::Application::Circ::ScriptBuilder;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Event;
my $U	= "OpenILS::Application::AppUtils";

my $script;			# - the permit script
my $script_libs;	# - extra script libs

# mental note:  open-ils.storage.biblio.record_entry.ranged_tree


# params within a hash are: copy, patron, 
# requestor, request_lib, title, title_descriptor
sub permit_copy_hold {
	my $params	= shift;
	my @allevents;

	my $ctx = {
		patron_id	=> $$params{patron_id},
		patron		=> $$params{patron},
		copy			=> $$params{copy},
		requestor	=> $$params{requestor},
		title			=> $$params{title},
		volume		=> $$params{volume},
		flesh_age_protect => 1,
		_direct	=> {
			requestLib	=> $$params{request_lib},
			pickupLib	=> $$params{pickup_lib},
		}
	};

	my $runner = OpenILS::Application::Circ::ScriptBuilder->build($ctx);

	my $evt = check_age_protect($ctx->{patron}, $ctx->{copy});
	push( @allevents, $evt ) if $evt;

	$logger->debug("Running permit_copy_hold on copy " . $$params{copy}->id);

	load_scripts($runner);
	my $result = $runner->run or 
		throw OpenSRF::EX::ERROR ("Hold Copy Permit Script Died: $@");

	$runner->cleanup;

	# --------------------------------------------------------------
	# Extract and uniquify the event list
	# --------------------------------------------------------------
	my $events = $result->{events};
	my $pid = ($params->{patron}) ? $params->{patron}->id : $params->{patron_id};
	$logger->debug("circ_permit_hold for user $pid returned events: [@$events]");

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


sub check_age_protect {
	my( $patron, $copy ) = @_;

	return undef unless $copy->age_protect;

	my $prox = $U->storagereq(
		'open-ils.storage.asset.copy.proximity', 
		$copy->id, $patron->home_ou->id );

	# If this copy is within the appropriate proximity, 
	# age protect does not apply
	return undef if $prox <= $copy->age_protect->prox;

	# How many seconds old does the copy have to be to escape age protection
	my $interval = OpenSRF::Utils::interval_to_seconds($copy->age_protect->age);
	my $start_date = time - $interval;

	# Now, now many seconds old is this copy
	my $dparser = DateTime::Format::ISO8601->new;
	my $create_date = $dparser->parse_datetime(
		OpenSRF::Utils::clense_ISO8601($copy->create_date));
	my $age = $create_date->epoch;

	$logger->debug("age_protect create_date = $create_date : age=$age, start_date=$start_date");

	unless( $start_date < $age ) {
		$logger->info("age_protect prevents copy from having a hold placed on it: ".$copy->id);
		return OpenILS::Event->new('ITEM_AGE_PROTECTED', copy => $copy->id );
	}

	return undef;
}







23;
