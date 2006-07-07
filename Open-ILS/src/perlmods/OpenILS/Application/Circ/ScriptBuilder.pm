package OpenILS::Application::Circ::ScriptBuilder;
use strict; use warnings;
use OpenILS::Utils::ScriptRunner;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Application::AppUtils;
use OpenILS::Application::Actor;
use OpenSRF::Utils::Logger qw/$logger/;
my $U = "OpenILS::Application::AppUtils";
use Data::Dumper;

my $evt = "environment";
my @COPY_STATUSES;
my @COPY_LOCATIONS;
my %GROUP_SET;
my $GROUP_TREE;
my $ORG_TREE;
my @ORG_LIST;


# -----------------------------------------------------------------------
# Possible Args:
#  copy
#  copy_id
#  copy_barcode
#
#  patron
#  patron_id
#  patron_barcode
#
#  fetch_patron_circ_info - load info on items out, overdues, and fines.
#
#  _direct - this is a hash of key/value pairs to shove directly into the 
#  script runner.  Use this to cover data not covered by this module
# -----------------------------------------------------------------------
sub build {
	my( $class, $args ) = @_;

	my $evt;
	my @evts;

	my $editor = $$args{editor} || new_editor();

	$args->{_direct} = {} unless $args->{_direct};
	
	$evt = fetch_bib_data($editor, $args);
	push(@evts, $evt) if $evt;
	$evt = fetch_user_data($editor, $args);
	push(@evts, $evt) if $evt;
	$args->{_event} = \@evts;
	return build_runner($editor, $args);
}


sub build_runner {
	my $editor	= shift;
	my $ctx		= shift;

	my $runner = OpenILS::Utils::ScriptRunner->new;

	$runner->insert( "$evt.groupTree",	$GROUP_TREE, 1);

	$runner->insert( "$evt.patron",		$ctx->{patron}, 1);
	$runner->insert( "$evt.copy",			$ctx->{copy}, 1);
	$runner->insert( "$evt.volume",		$ctx->{volume}, 1);
	$runner->insert( "$evt.title",		$ctx->{title}, 1);
	$runner->insert( "$evt.requestor",	$ctx->{requestor}, 1);
	$runner->insert( "$evt.titleDescriptor", $ctx->{titleDescriptor}, 1);

	$runner->insert( "$evt.patronItemsOut", $ctx->{patronItemsOut}, 1 );
	$runner->insert( "$evt.patronOverdueCount", $ctx->{patronOverdue}, 1 );
	$runner->insert( "$evt.patronFines", $ctx->{patronFines}, 1 );

	$runner->insert("$evt.$_", $ctx->{_direct}->{$_}) for keys %{$ctx->{_direct}};

	$ctx->{runner} = $runner;

	insert_org_methods( $editor, $ctx );

	return $runner;
}

sub fetch_bib_data {
	my $e = shift;
	my $ctx = shift;

	if(!$ctx->{copy}) {

		if($ctx->{copy_id}) {
			$ctx->{copy} = $e->retrieve_asset_copy($ctx->{copy_id})
				or return $e->event;

		} elsif( $ctx->{copy_barcode} ) {

			$ctx->{copy} = $e->search_asset_copy(
				{barcode => $ctx->{copy_barcode}}) or return $e->event;
			$ctx->{copy} = $ctx->{copy}->[0];
		}
	}

	return undef unless my $copy = $ctx->{copy};

	# --------------------------------------------------------------------
	# Fetch/Cache the copy status and location objects
	# --------------------------------------------------------------------
	if(!@COPY_STATUSES) {
		my $s = $e->retrieve_all_config_copy_status();
		@COPY_STATUSES = @$s;
		$s = $e->retrieve_all_asset_copy_location();
		@COPY_LOCATIONS = @$s;
	}

	# Flesh the status and location
	$copy->status( 
		grep { $_->id == $copy->status } @COPY_STATUSES ) 
		unless ref $copy->status;

	$copy->location( 
		grep { $_->id == $copy->location } @COPY_LOCATIONS ) 
		unless ref $copy->location;

	$copy->circ_lib( 
		$e->retrieve_actor_org_unit($copy->circ_lib)) 
		unless ref $copy->circ_lib;

	$ctx->{volume} = $e->retrieve_asset_call_number(
		$ctx->{copy}->call_number) or return $e->event;

	$ctx->{title} = $e->retrieve_biblio_record_entry(
		$ctx->{volume}->record) or return $e->event;

	if(!$ctx->{titleDescriptor}) {
		$ctx->{titleDescriptor} = $e->search_metabib_record_descriptor( 
			{ record => $ctx->{title}->id }) or return $e->event;

		$ctx->{titleDescriptor} = $ctx->{titleDescriptor}->[0];
	}

	return undef;
}



sub fetch_user_data {
	my( $e, $ctx ) = @_;
	
	if(!$ctx->{patron}) {

		if( $ctx->{patron_id} ) {
			$ctx->{patron} = $e->retrieve_actor_user($ctx->{patron_id});

		} elsif( $ctx->{patron_barcode} ) {

			my $card = $e->search_actor_card( 
				{ barcode => $ctx->{patron_barcode} } ) or return $e->event;

			$ctx->{patron} = $e->search_actor_user( 
				{ card => $card->[0]->id }) or return $e->event;
			$ctx->{patron} = $ctx->{patron}->[0];
		}
	}

	return undef unless my $patron = $ctx->{patron};

	$patron->home_ou( 
		$e->retrieve_actor_org_unit($patron->home_ou) ) 
		unless ref $patron->home_ou;


	if(!%GROUP_SET) {
		$GROUP_TREE = $e->search_permission_grp_tree(
			[
				{ parent => undef }, 
				{ 
					flesh => 100,
					flesh_fields => { pgt => ['children'] }
				} 
			]
		)->[0];

		flatten_groups($GROUP_TREE);
	}

	$patron->profile( $GROUP_SET{$patron->profile} )
		unless ref $patron->profile;

	$patron->card($e->retrieve_actor_card($patron->card));

	$ctx->{requestor} = $ctx->{requestor} || $e->requestor;

	# this could alter the requestor object within the editor..
	#if( my $req = $ctx->{requestor} ) {
	#	$req->home_ou( $e->retrieve_actor_org_unit($requestor->home_ou) );	
	#	$req->ws_ou( $e->retrieve_actor_org_unit($requestor->ws_ou) );	
	#}

	if( $ctx->{fetch_patron_circ_info} ) {

		my $circ_counts = 
			OpenILS::Application::Actor::_checked_out(1, $e, $patron->id);

		$ctx->{patronOverdue} = $circ_counts->{overdue} || 0;
		$ctx->{patronItemsOut} = $ctx->{patronOverdue} + $circ_counts->{out};

		# Grab the fines
		my $fxacts = $e->search_money_open_billable_transaction_summary(
			{ usr => $patron->id, balance_owed => { ">" => 0 } });

		my $fines = 0;
		$fines += $_->balance_owed for @$fxacts;
		$ctx->{patronFines} = $fines;

		$logger->debug("script_builder: patron fines determined to be $fines");
		$logger->debug("script_builder: patron overdue count is " . $ctx->{patronOverdue});
	}

	return undef;
}


sub flatten_groups {
	my $tree = shift;
	return undef unless $tree;
	$GROUP_SET{$tree->id} = $tree;
	if( $tree->children ) {
		flatten_groups($_) for @{$tree->children};
	}
}

sub flatten_org_tree {
	my $tree = shift;
	return undef unless $tree;
	push( @ORG_LIST, $tree );
	if( $tree->children ) {
		flatten_org_tree($_) for @{$tree->children};
	}
}



sub insert_org_methods {
	my ( $editor, $ctx ) = @_;
	my $runner = $ctx->{runner};

	if(!$ORG_TREE) {
		$ORG_TREE = $editor->search_actor_org_unit(
			[
				{"parent_ou" => undef },
				{
					flesh				=> 2,
					flesh_fields	=> { aou =>  ['children'] },
					order_by			=> { aou => 'name'}
				}
			]
		)->[0];
		flatten_org_tree($ORG_TREE);
	}

	$runner->insert(__OILS_FUNC_isOrgDescendent  => 
		sub {
			my( $write_key, $sname, $id ) = @_;
			$logger->debug("script_builder: org descendent: $sname - $id");
			my ($parent)	= grep { $_->shortname eq $sname } @ORG_LIST;
			my ($child)		= grep { $_->id == $id } @ORG_LIST;
			$logger->debug("script_builder: org descendent: $parent = $child");
			my $val = is_org_descendent( $parent, $child );
			$logger->debug("script_builder: ord desc = $val");
			$runner->insert($write_key, $val);
			return $val;
		}
	);
}


sub is_org_descendent {
	my( $parent, $child ) = @_;
	return 0 unless $parent and $child;
	do {
		return 1 if $parent->id == $child->id;
	} while( ($child) = grep { $_->id == $child->parent_ou } @ORG_LIST );
	return 0;
}

1;



