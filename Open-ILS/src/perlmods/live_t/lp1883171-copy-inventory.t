#!perl
use strict; use warnings;
use Test::More;
use OpenILS::Utils::TestUtils;
use OpenILS::Const qw(:const);

my $script = OpenILS::Utils::TestUtils->new();
my $U = 'OpenILS::Application::AppUtils';

diag('LP1883171&1940663 Copy Inventory Date');

use constant {
    BR1_ID => 4,
    BR2_ID => 5,
    SYS1_ID => 2,
    SYS1_FGROUP => "Sys1 Floating Group",
    CIRC_USER => 'br1mtownsend',
    CIRC_USER_PWD => 'demo123',
    CIRC_WORKSTATION => 'BR1-lp1883171-live_t',
};

# Login as staff
my $credentials = {
    username => CIRC_USER,
    password => CIRC_USER_PWD,
    type => 'staff'
};
my $authtoken = $script->authenticate($credentials);
ok(
    $authtoken,
    'Logged in'
) or BAIL_OUT('Must log in');

# Find or register the workstation:
my $ws = $script->find_or_register_workstation(CIRC_WORKSTATION, BR1_ID);
ok(
    ! ref $ws,
    'Found or registered workstation'
) or BAIL_OUT('Need workstation');

# Logout so we can use the workstation.
$script->logout();
ok(
    ! $script->authtoken,
    'Logged out'
);

# Login with workstation
$credentials->{workstation} = CIRC_WORKSTATION;
$credentials->{password} = CIRC_USER_PWD; # Have to reset the password.
$authtoken = $script->authenticate($credentials);
ok(
    $script->authtoken,
    'Logged in with workstation'
) or BAIL_OUT('Must log in with workstation');

# Create an cstore editor with our current authtoken
my $editor = $script->editor(authtoken=>$authtoken);

# Create a floating group for SYS1:
my $cfg = Fieldmapper::config::floating_group->new;
$cfg->name(SYS1_FGROUP);
$cfg->manual('f');
$editor->xact_begin();
$cfg = $editor->create_config_floating_group($cfg);
ok(
    $cfg,
    'Floating Group created successfully'
) or BAIL_OUT('Need Floating Group');
$cfg = $editor->search_config_floating_group({name=>SYS1_FGROUP})->[0];
# Add SYS1 as a member:
my $cfgm = Fieldmapper::config::floating_group_member->new;
$cfgm->floating_group($cfg->id());
$cfgm->org_unit(SYS1_ID);
$cfgm->stop_depth(1);
$cfgm = $editor->create_config_floating_group_member($cfgm);
ok(
    $cfgm,
    'Floating group member created successfully'
) or BAIL_OUT('Need floating group member');
$editor->xact_commit;

# find 2 BR1 copies checked out at BR1:
my $copies = $editor->search_asset_copy([
    {
        circ_lib => BR1_ID,
        status => 1
    },
    {
        join => {
            circ => {
                filter => {
                    circ_lib => BR1_ID,
                    checkin_scan_time => undef
                }
            }
        },
        limit=>2
    }
]);
ok(
    $copies && scalar(@$copies) == 2,
    'Got two checked out copies'
);
# Check first in without inventory update and the other with:
my $do_inventory = 0;
foreach my $copy (@$copies) {
    my $args = {
        barcode => $copy->barcode,
        do_inventory_update => $do_inventory
    };
    my $resp = $script->do_checkin($args);
    is(
        $resp->{textcode},
        'SUCCESS',
        'Copy checked in'
    );
    my $circ = $resp->{payload}->{circ};
    isa_ok(
        $circ,
        'Fieldmapper::action::circulation'
    );
    my $scan_time = substr($circ->checkin_scan_time, 0, 19);
    $copy = $resp->{payload}->{copy};
    isa_ok(
        $copy,
        'Fieldmapper::asset::copy'
    );
    my $inventory = $copy->latest_inventory();
    if ($inventory) {
        my $inv_time = substr($inventory->inventory_date(), 0, 19);
        if ($do_inventory) {
            is(
                $inv_time,
                $scan_time,
                'Inventory date equals checkin scan time'
            );
        } else {
            isnt(
                $inv_time,
                $scan_time,
                'Inventory date does not equal checkin scan time'
            );
        }
    } else {
        if ($do_inventory) {
            BAIL_OUT('Inventory not created on checkin');
        }
    }

    $do_inventory++;
}

# Find 2 BR2 copies checked out at BR1:
$copies = $editor->search_asset_copy([
    {
        circ_lib => BR2_ID,
        status => 1
    },
    {
        join => {
            circ => {
                circ_lib => BR1_ID,
                checkin_scan_time => undef
            }
        },
        limit=>2
    }
]);
ok(
    $copies && scalar(@$copies) == 2,
    'Got two checked out copies'
);
# Set the first one to floating:
my $fcopy = $copies->[0];
$fcopy->floating($cfg->id());
$editor->xact_begin;
$fcopy = $editor->update_asset_copy($fcopy);
$editor->xact_commit;
ok(
    $fcopy,
    'First BR2 copy set to floating group'
);
# Check them both in with inventory update.
for (my $i = 0; $i < scalar(@$copies); $i++) {
    my $copy = $copies->[$i];
    my $args = {
        barcode => $copy->barcode,
        do_inventory_update => $do_inventory
    };
    my $resp = $script->do_checkin($args);
    is(
        $resp->{textcode},
        ($i == 0) ? 'SUCCESS' : 'ROUTE_ITEM',
        'Copy checked in'
    );
    my $circ = $resp->{payload}->{circ};
    isa_ok(
        $circ,
        'Fieldmapper::action::circulation'
    );
    my $scan_time = substr($circ->checkin_scan_time, 0, 19);
    $copy = $resp->{payload}->{copy};
    isa_ok(
        $copy,
        'Fieldmapper::asset::copy'
    );
    my $inventory = $copy->latest_inventory();
    if ($i == 0) {
        if ($inventory) {
            my $inv_time = substr($inventory->inventory_date(), 0, 19);
            is(
                $inv_time,
                $scan_time,
                'Inventory date equals checkin scan time'
            );
        } else {
            BAIL_OUT('Inventory not created on checkin');
        }
    } else {
        if ($inventory) {
            my $inv_time = substr($inventory->inventory_date(), 0, 19);
            isnt(
                $inv_time,
                $scan_time,
                'Inventory date does not equal checkin scan time'
            );
        } else {
            pass('Second copy does not have inventory');
        }
    }
}

# Find an available copy at BR1:
$copies = $editor->search_asset_copy([
    {
        circ_lib => BR1_ID,
        status => 0
    },
    {limit=>1}
]);
ok(
    $copies && scalar(@$copies) == 1,
    'Got an available copy'
) or BAIL_OUT('Need an available copy');

my $resp = $U->simplereq(
    'open-ils.circ',
    'open-ils.circ.circulation.update_copy_inventory',
    $authtoken,
    {copy_list=>[$copies->[0]->id()]}
);
is(
    $resp->[0],
    1,
    'Update copy inventory succeeded'
);

my $inventories = $editor->search_asset_copy_inventory([
    {
        copy => $copies->[0]->id
    },
    {
        order_by => [
            {
                class => 'aci',
                field => 'inventory_date',
                direction => 'desc'
            }
        ]
    }
]);
ok(
    $inventories && scalar(@$inventories),
    'Got copy inventory'
) or BAIL_OUT('Need copy inventory');

my $aci = $inventories->[0];

my $alci = $editor->retrieve_asset_latest_inventory($aci->id());
ok(
    $alci,
    'Got latest inventory for copy'
);
is(
    $alci->id(),
    $aci->id(),
    'Inventory IDs match'
);
is(
    $alci->inventory_date(),
    $aci->inventory_date(),
    'Inventory dates match'
);
is(
    $alci->inventory_workstation(),
    $aci->inventory_workstation(),
    'Inventory workstations match'
);
is(
    $alci->copy(),
    $aci->copy(),
    'Inventory copies match'
);

# Now, try 2 copies at BR2
$copies = $editor->search_asset_copy([
    {
        circ_lib => BR2_ID,
        status => 0
    },
    {limit=>2}
]);
ok(
    $copies && scalar(@$copies) == 2,
    'Got two copies'
) or BAIL_OUT('Need 2 copies');

$resp = $U->simplereq(
    'open-ils.circ',
    'open-ils.circ.circulation.update_copy_inventory',
    $authtoken,
    {copy_list=>[$copies->[0]->id()]}
);
is(
    $resp->[0],
    0,
    'Update copy inventory should have 0 success'
);
is(
    $resp->[1],
    1,
    'Update copy inventory should have 1 failure'
);
# Make the second one float and it should succeed.
$fcopy = $copies->[1];
$fcopy->floating($cfg->id());
$editor->xact_begin;
if ($editor->update_asset_copy($fcopy)) {
    $editor->xact_commit;
    $resp = $U->simplereq(
        'open-ils.circ',
        'open-ils.circ.circulation.update_copy_inventory',
        $authtoken,
        {copy_list=>[$fcopy->id()]}
    );
    is(
        $resp->[0],
        1,
        'Update inventory for floating copy'
    );
} else {
    $editor->xact_rollback;
    BAIL_OUT('Set copy floating failed');
}

# Test a batch update where some succeed and some fail.
$resp = $editor->search_asset_copy([
    {circ_lib => BR2_ID, status => 0, floating => undef},
    {limit => 5, idlist => 1}
]);
ok(
    $resp && scalar(@{$resp}) == 5,
    'Got 5 copies from branch 2'
);
undef($copies);
push(@{$copies}, @{$resp});
$resp = $editor->search_asset_copy([
    {circ_lib => BR1_ID, status => 0},
    {limit => 5, idlist => 1}
]);
ok(
    $resp && scalar(@{$resp}) == 5,
    'Got 5 copies from branch 1'
);
push(@{$copies}, @{$resp});
$resp = $U->simplereq(
    'open-ils.circ',
    'open-ils.circ.circulation.update_copy_inventory',
    $authtoken,
    {copy_list=>$copies}
);
is(
    $resp->[0],
    5,
    'Updated inventory on 5 copies'
);
is(
    $resp->[1],
    5,
    'Did not update inventory on 5 copies'
);

# We could run 36 or more tests depending on what we find in the
# database, so we don't specify a number of tests.
done_testing();

# Just to make sure we're done.
$editor->disconnect();
$script->logout();
