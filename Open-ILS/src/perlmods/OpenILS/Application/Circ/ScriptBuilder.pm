package OpenILS::Application::Circ::ScriptBuilder;
use strict; use warnings;
use OpenILS::Utils::ScriptRunner;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Application::AppUtils;
use OpenILS::Application::Actor;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Application::Circ::Holds;
use DateTime::Format::ISO8601;
use OpenSRF::Utils qw/:datetime/;
use Scalar::Util qw/weaken/;
my $U = "OpenILS::Application::AppUtils";
use Data::Dumper;

my $holdcode = "OpenILS::Application::Circ::Holds";

my $evt = "environment";
my %GROUP_SET;
my $GROUP_TREE;
my $ORG_TREE;
my @ORG_LIST;
my @OU_TYPES;


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

	my $editor = $$args{editor} || new_editor(xact => 1);

	$args->{_direct} = {} unless $args->{_direct};
	$args->{editor} = $editor;
	
	$evt = fetch_bib_data($editor, $args);
	push(@evts, $evt) if $evt;
	$evt = fetch_user_data($editor, $args);
	push(@evts, $evt) if $evt;

	if(@evts) {
		my @e;
		push( @e, $_->{textcode} ) for @evts;
		$logger->info("script_builder: some events occurred: @e");
		$logger->debug("script_builder: some events occurred: " . Dumper(\@evts));
		$args->{_events} = \@evts;
	}

	return build_runner($editor, $args);
}


sub build_runner {
	my $editor	= shift;
	my $ctx		= shift;

	my $runner = OpenILS::Utils::ScriptRunner->new;

	my $gt = $GROUP_TREE;
	$runner->insert( "$evt.groupTree",	$gt, 1);


	$runner->insert( "$evt.patron",		$ctx->{patron}, 1);
	$runner->insert( "$evt.copy",			$ctx->{copy}, 1);
	$runner->insert( "$evt.volume",		$ctx->{volume}, 1);
	$runner->insert( "$evt.title",		$ctx->{title}, 1);

	if( ref $ctx->{requestor} ) {
		$runner->insert( "$evt.requestor",	$ctx->{requestor}, 1);
		if($ctx->{requestor}->ws_ou) {
			$runner->insert( "$evt.location",	
				$editor->retrieve_actor_org_unit($ctx->{requestor}->ws_ou), 1);
		}
	}

	$runner->insert( "$evt.patronItemsOut", $ctx->{patronItemsOut}, 1 );
	$runner->insert( "$evt.patronOverdueCount", $ctx->{patronOverdue}, 1 );
	$runner->insert( "$evt.patronFines", $ctx->{patronFines}, 1 );

	$runner->insert("$evt.$_", $ctx->{_direct}->{$_}, 1) for keys %{$ctx->{_direct}};

	insert_org_methods( $editor, $runner );
	insert_copy_methods( $editor, $ctx, $runner );

	return $runner;
}

sub fetch_bib_data {
	my $e = shift;
	my $ctx = shift;

	if(!$ctx->{copy}) {

		my $flesh = { flesh => 1, flesh_fields => { acp => [ 'location', 'status', 'circ_lib' ] } };

		if($ctx->{copy_id}) {
			$ctx->{copy} = $e->retrieve_asset_copy(
				[$ctx->{copy_id}, $flesh ]) or return $e->event;

		} elsif( $ctx->{copy_barcode} ) {

			$ctx->{copy} = $e->search_asset_copy(
				[{barcode => $ctx->{copy_barcode}, deleted => 'f'}, $flesh ])->[0]
				or return $e->event;
		}
	}

	return undef unless my $copy = $ctx->{copy};

	$copy->location($e->retrieve_asset_copy_location($copy->location))
		unless( ref $copy->location );

	$copy->status($e->retrieve_config_copy_status($copy->status))
		unless( ref $copy->status );

	$copy->circ_lib( 
		$e->retrieve_actor_org_unit($copy->circ_lib)) 
		unless ref $copy->circ_lib;

	$ctx->{volume} = $e->retrieve_asset_call_number(
		$ctx->{copy}->call_number) or return $e->event;

	$ctx->{title} = $e->retrieve_biblio_record_entry(
		$ctx->{volume}->record) or return $e->event;

	$copy->age_protect(
		$e->retrieve_config_rules_age_hold_protect($copy->age_protect))
		if $ctx->{flesh_age_protect} and $copy->age_protect;

	return undef;
}



sub fetch_user_data {
	my( $e, $ctx ) = @_;
	
	if(!$ctx->{patron}) {

		if( $ctx->{patron_id} ) {
			$ctx->{patron} = $e->retrieve_actor_user($ctx->{patron_id});

		} elsif( $ctx->{patron_barcode} ) {

			my $card = $e->search_actor_card( 
				{ barcode => $ctx->{patron_barcode} } )->[0] or return $e->event;

			$ctx->{patron} = $e->search_actor_user( 
				{ card => $card->id })->[0] or return $e->event;

		} elsif( $ctx->{fetch_patron_by_circ_copy} ) {

			if( my $copy = $ctx->{copy} ) {
				my $circs = $e->search_action_circulation(
					{ target_copy => $copy->id, checkin_time => undef });

				if( my $circ = $circs->[0] ) {
					$ctx->{patron} = $e->retrieve_actor_user($circ->usr)
						or return $e->event;
				}
			}
		}
	}

	return undef unless my $patron = $ctx->{patron};

	unless( $ctx->{ignore_user_status} ) {
		return OpenILS::Event->new('PATRON_INACTIVE')
			unless $U->is_true($patron->active);
	
		$patron->card($e->retrieve_actor_card($patron->card))
			unless ref $patron->card;
	
		return OpenILS::Event->new('PATRON_CARD_INACTIVE')
			unless $U->is_true($patron->card->active);
	
		my $expire = DateTime::Format::ISO8601->new->parse_datetime(
			clense_ISO8601($patron->expire_date));
	
		return OpenILS::Event->new('PATRON_ACCOUNT_EXPIRED')
			if( CORE::time > $expire->epoch ) ;
	}

	$patron->home_ou( 
		$e->retrieve_actor_org_unit($patron->home_ou) ) 
		unless ref $patron->home_ou;

	$patron->home_ou->ou_type(
		$patron->home_ou->ou_type->id) 
		if ref $patron->home_ou->ou_type;

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
		$logger->debug("script_builder: patron overdue count is " . $ctx->{patronOverdue});
	}

	if( $ctx->{fetch_patron_money_info} ) {
		# Grab the fines
#		my $fxacts = $e->search_money_billable_transaction_summary(
#			{ usr => $patron->id, balance_owed => { "!=" => 0 }, xact_finish => undef });
#
#		my $fines = 0;
#		$fines += $_->balance_owed for @$fxacts;
#		$ctx->{patronFines} = $fines;
		$ctx->{patronFines} = $U->patron_money_owed($patron->id);
		$logger->debug("script_builder: patron fines determined to be ".$ctx->{patronFines});
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
	my ( $editor, $runner ) = @_;

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

	my $r = $runner;
	weaken($r);

	$r->insert(__OILS_FUNC_isOrgDescendent  => 
		sub {
			my( $write_key, $sname, $id ) = @_;
			my ($parent)	= grep { $_->shortname eq $sname } @ORG_LIST;
			my ($child)		= grep { $_->id == $id } @ORG_LIST;
			my $val = is_org_descendent( $parent, $child );
			$logger->debug("script_builder: is_org_desc returned val $val, writing to $write_key");
			$r->insert($write_key, $val, 1) if $val;
			return $val;
		}
	);

	$r->insert(__OILS_FUNC_hasCommonAncestor  => 
		sub {
			my( $write_key, $orgid1, $orgid2, $depth ) = @_;
			my $val = has_common_ancestor( $orgid1, $orgid2, $depth );
			$logger->debug("script_builder: has_common_ancestor resturned $val");
			$r->insert($write_key, $val, 1) if $val;
			return $val;
		}
	);
}


sub is_org_descendent {
	my( $parent, $child ) = @_;
	return 0 unless $parent and $child;
	$logger->debug("script_builder: is_org_desc checking parent=".$parent->id.", child=".$child->id);
	do {
		return 0 unless defined $child->parent_ou;
		return 1 if $parent->id == $child->id;
	} while( ($child) = grep { $_->id == $child->parent_ou } @ORG_LIST );
	return 0;
}

sub has_common_ancestor {
	my( $org1, $org2, $depth ) = @_;
	return 0 unless $org1 and $org2;
	$logger->debug("script_builder: has_common_ancestor checking orgs $org1 : $org2");

	return 1 if $org1 == $org2;
	($org1) = grep { $_->id == $org1 } @ORG_LIST;
	($org2) = grep { $_->id == $org2 } @ORG_LIST;

	my $p1 = find_parent_at_depth($org1, $depth);
	my $p2 = find_parent_at_depth($org2, $depth);

	return 1 if $p1->id == $p2->id;
	return 0;
}


sub find_parent_at_depth {
	my $org = shift;
	my $depth = shift;
	fetch_ou_types();
	do {
		my ($t) = grep { $_->id == $org->ou_type } @OU_TYPES;
		return $org if $t->depth == $depth;
	} while( ($org) = grep { $_->id == $org->parent_ou } @ORG_LIST );
	return undef;	
}


sub fetch_ou_types {
	return if @OU_TYPES;
	@OU_TYPES = @{new_editor()->retrieve_all_actor_org_unit_type()};
}

sub insert_copy_methods {
	my( $e, $ctx,  $runner ) = @_;
	if( my $copy = $ctx->{copy} ) {
		$runner->insert_method( 'environment.copy', '__OILS_FUNC_fetch_best_hold', sub {
				my $key = shift;
				$logger->debug("script_builder: searching for permitted hold for copy ".$copy->barcode);
				my ($hold) = $holdcode->find_nearest_permitted_hold(
					OpenSRF::AppSession->create('open-ils.storage'), $copy, $e->requestor );
				$runner->insert( $key, $hold, 1 );
			}
		);
	}
}





1;
