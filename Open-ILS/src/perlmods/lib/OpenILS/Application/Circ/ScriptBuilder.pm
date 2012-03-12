package OpenILS::Application::Circ::ScriptBuilder;
use strict; use warnings;
use OpenILS::Utils::ScriptRunner;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Application::AppUtils;
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

	my $rollback;
	my $editor = $$args{editor};

	unless($editor) {
		$editor = new_editor(xact => 1);
		$rollback = 1;
	}

	$args->{_direct} = {} unless $args->{_direct};
	#$args->{editor} = $editor;
	
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

	my $r = build_runner($editor, $args);
	$editor->rollback if $rollback;
	return $r;
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
   insert_user_funcs( $editor, $ctx, $runner );

	return $runner;
}

sub fetch_bib_data {
	my $e = shift;
	my $ctx = shift;

	my $flesh = { 
		flesh => 2, 
		flesh_fields => { 
			acp => [ 'location', 'status', 'circ_lib', 'age_protect', 'call_number' ],
			acn => [ 'record' ]
		} 
	};

	if( $ctx->{copy} ) {
		$ctx->{copy_id} = $ctx->{copy}->id 
			unless $ctx->{copy_id} or $ctx->{copy_barcode};
	}

	my $copy;

	if($ctx->{copy_id}) {
		$copy = $e->retrieve_asset_copy(
			[$ctx->{copy_id}, $flesh ]) or return $e->event;

	} elsif( $ctx->{copy_barcode} ) {

		$copy = $e->search_asset_copy(
			[{barcode => $ctx->{copy_barcode}, deleted => 'f'}, $flesh ])->[0]
			or return $e->event;
	}

	return undef unless $copy;

	my $vol = $copy->call_number;
	my $rec = $vol->record;
	$ctx->{copy} = $copy;
	$ctx->{volume} = $vol;
	$copy->call_number($vol->id);
	$ctx->{title} = $rec;
	$vol->record($rec->id);

	return undef;
}



sub fetch_user_data {
	my( $e, $ctx ) = @_;

	my $flesh = {
		flesh => 2,
		flesh_fields => {
			au => [ qw/ profile home_ou card / ],
			aou => [ 'ou_type' ],
		}
	};

	if( $ctx->{patron} ) {
		$ctx->{patron_id} = $ctx->{patron}->id unless $ctx->{patron_id};
	}

	my $patron;
	
	if( $ctx->{patron_id} ) {
		$patron = $e->retrieve_actor_user([$ctx->{patron_id}, $flesh]);

	} elsif( $ctx->{patron_barcode} ) {

		my $card = $e->search_actor_card( 
			{ barcode => $ctx->{patron_barcode} } )->[0] or return $e->event;

		$patron = $e->search_actor_user( 
			[{ card => $card->id }, $flesh ]
			)->[0] or return $e->event;

	} elsif( $ctx->{fetch_patron_by_circ_copy} ) {

		if( my $copy = $ctx->{copy} ) {
			my $circs = $e->search_action_circulation(
				{ target_copy => $copy->id, checkin_time => undef });

			if( my $circ = $circs->[0] ) {
				$patron = $e->retrieve_actor_user([$circ->usr, $flesh])
					or return $e->event;
			}
		}
	}

	return undef unless $ctx->{patron} = $patron;

	flatten_groups($e);

	$ctx->{requestor} = $ctx->{requestor} || $e->requestor;

	if( $ctx->{fetch_patron_circ_info} ) {
		my $circ_counts = $U->storagereq('open-ils.storage.actor.user.checked_out.count', $patron->id);

		$ctx->{patronOverdue} = $circ_counts->{overdue}  + $circ_counts->{long_overdue};
		my $out = $ctx->{patronOverdue} + $circ_counts->{out};

		$ctx->{patronItemsOut} = $out 
			unless( $ctx->{patronItemsOut} and $ctx->{patronItemsOut} > $out );

		$logger->debug("script_builder: patron overdue count is " . $ctx->{patronOverdue});
	}

	if( $ctx->{fetch_patron_money_info} ) {
		$ctx->{patronFines} = $U->patron_money_owed($patron->id);
		$logger->debug("script_builder: patron fines determined to be ".$ctx->{patronFines});
	}

	unless( $ctx->{ignore_user_status} ) {
		return OpenILS::Event->new('PATRON_INACTIVE')
			unless $U->is_true($patron->active);
	
		return OpenILS::Event->new('PATRON_CARD_INACTIVE')
			unless $U->is_true($patron->card->active);
	
		my $expire = DateTime::Format::ISO8601->new->parse_datetime(
			cleanse_ISO8601($patron->expire_date));
	
		return OpenILS::Event->new('PATRON_ACCOUNT_EXPIRED')
			if( CORE::time > $expire->epoch ) ;
	}

	return undef;
}


sub flatten_groups {
	my $e = shift;
	my $tree = shift;

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
		$tree = $GROUP_TREE;
	}

	return undef unless $tree;
	$GROUP_SET{$tree->id} = $tree;
	if( $tree->children ) {
		flatten_groups($e, $_) for @{$tree->children};
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
		$ORG_TREE = $U->get_org_tree;
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
			$logger->debug("script_builder: is_org_desc $sname:$id returned val $val, writing to $write_key");
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
	return undef unless $org and $depth;
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
	my $reqr = $ctx->{requestor} || $e->requestor;
	if( my $copy = $ctx->{copy} ) {
		$runner->insert_method( 'environment.copy', '__OILS_FUNC_fetch_best_hold', sub {
				my $key = shift;
				$logger->debug("script_builder: searching for permitted hold for copy ".$copy->barcode);
				my ($hold) = $holdcode->find_nearest_permitted_hold( $e, $copy, $reqr, 1 );  # do we need a new editor here since the xact may be dead??
				$runner->insert( $key, $hold, 1 );
			}
		);
	}
}

sub insert_user_funcs {
   my( $e, $ctx, $runner ) = @_;

   # tells how many holds a user has
	$runner->insert(__OILS_FUNC_userHoldCount  => 
		sub {
			my( $write_key, $userid ) = @_;
         my $val = $holdcode->__user_hold_count(new_editor(), $userid);
         $logger->info("script_runner: user hold count is $val");
			$runner->insert($write_key, $val, 1) if $val;
			return $val;
		}
	);

	$runner->insert(__OILS_FUNC_userCircsByCircmod  => 
		sub {
			my( $write_key, $userid ) = @_;
            use OpenSRF::Utils::JSON;

            # this bug ugly thing generates a count of checkouts by circ_modifier
             my $query = {
                "select" => {
                    "acp" => ["circ_modifier"],
                    "circ"=>[{
                        "aggregate"=> OpenSRF::Utils::JSON->true,
                        "transform"=>"count",
                        "alias"=>"count",
                        "column"=>"id"
                    }],
                },
                "from"=>{"acp"=>{"circ"=>{"field"=>"target_copy","fkey"=>"id"}}},
                "where"=>{
                    "+circ"=>{
                        "checkin_time"=>undef,
                        "usr"=>$userid,
                        "-or"=>[
                            {"stop_fines"=>["MAXFINES","LONGOVERDUE"]},
                            {"stop_fines"=>undef}
                        ]
                    }
                }
            };

            my $mods = $e->json_query($query);
            my $breakdown = {};
            $breakdown->{$_->{circ_modifier}} = $_->{count} for @$mods;
            $logger->info("script_runner: Loaded checkouts by circ_modifier breakdown:". 
                OpenSRF::Utils::JSON->perl2JSON($breakdown));
			$runner->insert($write_key, $breakdown, 1) if (keys %$breakdown);
		}
	);

}




1;
