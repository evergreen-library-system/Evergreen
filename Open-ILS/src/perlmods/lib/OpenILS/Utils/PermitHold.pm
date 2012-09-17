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
use OpenILS::Utils::CStoreEditor qw/:funcs/;
my $U	= "OpenILS::Application::AppUtils";

my $script;			# - the permit script
my $script_libs;	# - extra script libs
my $legacy_script_support;

# mental note:  open-ils.storage.biblio.record_entry.ranged_tree


# params within a hash are: copy, patron, 
# requestor, request_lib, title, title_descriptor
sub permit_copy_hold {
	my $params	= shift;
	my @allevents;

    unless(defined $legacy_script_support) {
        my $conf = OpenSRF::Utils::SettingsClient->new;
        $legacy_script_support = $conf->config_value(
            apps => 'open-ils.circ' => app_settings => 'legacy_script_support');
        $legacy_script_support = ($legacy_script_support and 
            $legacy_script_support =~ /true/i) ? 1 : 0;
    }

    return indb_hold_permit($params) unless $legacy_script_support;

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
            newHold    => $$params{new_hold},
		}
	};

	my $runner = OpenILS::Application::Circ::ScriptBuilder->build($ctx);

	my $ets = $ctx->{_events};

	# --------------------------------------------------------------
	# Strip the expired event since holds are still allowed to be
	# captured on expired patrons.  
	# --------------------------------------------------------------
	if( $ets and @$ets ) {
		$ets = [ grep { $_->{textcode} ne 'PATRON_ACCOUNT_EXPIRED' } @$ets ];
	} else { $ets = []; }

	if( @$ets ) {
		push( @allevents, @$ets);

		# --------------------------------------------------------------
		# If scriptbuilder returned any events, then the script context
		# is undefined and should not be used
		# --------------------------------------------------------------

	} else {

		# check the various holdable flags
		push( @allevents, OpenILS::Event->new('ITEM_NOT_HOLDABLE') )
			unless $U->is_true($ctx->{copy}->holdable);
	
		push( @allevents, OpenILS::Event->new('ITEM_NOT_HOLDABLE') )
			unless $U->is_true($ctx->{copy}->location->holdable);
	
		push( @allevents, OpenILS::Event->new('ITEM_NOT_HOLDABLE') )
			unless $U->is_true($ctx->{copy}->status->holdable);
	
      my $evt;

      # grab the data safely
      my $rlib = ref($$params{request_lib}) ? $$params{request_lib}->id : $$params{request_lib};
      my $olib = ref($ctx->{volume}) ? $ctx->{volume}->owning_lib : -1;
      my $rid  = ref($ctx->{requestor}) ? $ctx->{requestor}->id : -2;
		my $pid  = ($params->{patron}) ? $params->{patron}->id : $params->{patron_id};

      if( ($rid ne $pid) and ($olib eq $rlib) ) {
         $logger->info("Item owning lib $olib is the same as the request lib.  No age_protection will be checked");
      } else {
         $logger->info("item owning lib = $olib, request lib = $rlib, requestor=$rid, patron=$pid. checking age_protection");
		   $evt = check_age_protect($ctx->{patron}, $ctx->{copy});
		   push( @allevents, $evt ) if $evt;
      }
	
		$logger->debug("Running permit_copy_hold on copy " . $$params{copy}->id);
	
		load_scripts($runner);
		my $result = $runner->run or 
			throw OpenSRF::EX::ERROR ("Hold Copy Permit Script Died: $@");

		# --------------------------------------------------------------
		# Extract and uniquify the event list
		# --------------------------------------------------------------
		my $events = $result->{events};
		$logger->debug("circ_permit_hold for user $pid returned events: [@$events]");
	
		push( @allevents, OpenILS::Event->new($_)) for @$events;
	}

	my %hash = map { ($_->{ilsevent} => $_) } @allevents;
	@allevents = values %hash;

	$runner->cleanup;

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

	return undef unless $copy and $copy->age_protect and $patron;

	my $hou = (ref $patron->home_ou) ? $patron->home_ou->id : $patron->home_ou;

	my $prox = $U->storagereq(
		'open-ils.storage.asset.copy.proximity', $copy->id, $hou );

	# If this copy is within the appropriate proximity, 
	# age protect does not apply
	return undef if $prox <= $copy->age_protect->prox;

	my $protection_list = $U->storagereq(
		'open-ils.storage.direct.config.rules.age_hold_protect.search_where.atomic', 
		{ age  => { '>=' => $copy->age_protect->age  },
		  prox => { '>=' => $copy->age_protect->prox },
		},
		{ order_by => 'age' }
	);

    # circ_lib may be fleshed
    my $context_org = ref $copy->circ_lib ? $copy->circ_lib->id : $copy->circ_lib;
    my $age_protect_date = $copy->create_date;
    $age_protect_date = $copy->active_date if($U->ou_ancestor_setting_value($context_org, 'circ.holds.age_protect.active_date'));

    my $age = 0;
    my $age_protect_parsed;
    if($age_protect_date) {
    	# Now, now many seconds old is this copy
	    $age_protect_parsed = DateTime::Format::ISO8601
		    ->new
    		->parse_datetime( OpenSRF::Utils::cleanse_ISO8601($age_protect_date) )
	    	->epoch;
	    $age = time - $age_protect_parsed;
    }

	for my $protection ( @$protection_list ) {

		$logger->info("analyzing age protect ".$protection->name);

		# age protect does not apply if within the proximity
		last if $prox <= $protection->prox;

		# How many seconds old does the copy have to be to escape age protection
		my $interval = OpenSRF::Utils::interval_to_seconds($protection->age);

		$logger->info("age_protect interval=$interval, age_protect_date=$age_protect_parsed, age=$age");

		if( $interval > $age ) { 
			# if age of the item is less than the protection interval, 
			# the item falls within the age protect range
			$logger->info("age_protect prevents copy from having a hold placed on it: ".$copy->id);
			return OpenILS::Event->new('ITEM_AGE_PROTECTED', copy => $copy->id );
		}
	}
		
	return undef;
}

my $LEGACY_HOLD_EVENT_MAP = {
    'config.hold_matrix_test.holdable' => 'ITEM_NOT_HOLDABLE',
    'item.holdable' => 'ITEM_NOT_HOLDABLE',
    'location.holdable' => 'ITEM_NOT_HOLDABLE',
    'status.holdable' => 'ITEM_NOT_HOLDABLE',
    'transit_range' => 'ITEM_NOT_HOLDABLE',
    'no_matchpoint' => 'NO_POLICY_MATCHPOINT',
    'config.hold_matrix_test.max_holds' => 'MAX_HOLDS',
    'config.rule_age_hold_protect.prox' => 'ITEM_AGE_PROTECTED'
};

sub indb_hold_permit {
    my $params = shift;

    my $function = $$params{retarget} ? 'action.hold_retarget_permit_test' : 'action.hold_request_permit_test';
    my $patron_id = 
        ref($$params{patron}) ? $$params{patron}->id : $$params{patron_id};
    my $request_lib = 
        ref($$params{request_lib}) ? $$params{request_lib}->id : $$params{request_lib};

    my $HOLD_TEST = {
        from => [
            $function,
            $$params{pickup_lib}, 
            $request_lib,
            $$params{copy}->id, 
            $patron_id,
            $$params{requestor}->id 
        ]
    };

    my $e = new_editor(xact=>1);
    my $results = $e->json_query($HOLD_TEST);
    $e->rollback;

    unless($$params{show_event_list}) {
        return 1 if $U->is_true($results->[0]->{success});
        return 0;
    }

    return [
        new OpenILS::Event(
            "NO_POLICY_MATCHPOINT",
            "payload" => {"fail_part" => "no_matchpoint"}
        )
    ] unless @$results;

    return [] if $U->is_true($results->[0]->{success});

    return [
        map {
            my $event = new OpenILS::Event(
                $LEGACY_HOLD_EVENT_MAP->{$_->{"fail_part"}} || $_->{"fail_part"}
            );
            $event->{"payload"} = {"fail_part" => $_->{"fail_part"}};
            $event;
        } @$results
    ];
}


23;
