#!perl
use strict;
use warnings;

use Test::More tests => 7;
diag 'Hold Reset Test for a serial unit';

use OpenILS::Utils::TestUtils;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;

my $script = OpenILS::Utils::TestUtils->new;
my $U = 'OpenILS::Application::AppUtils';
my $e = new_editor;

$script->bootstrap;
$e->init;

use constant {
    BR1_WORKSTATION => 'BR1-test-lp2107581-hold-reset-serial-unit.t',
    BR1_ID => 4,
};

# Login as admin at BR1.
my $authtoken = $script->authenticate({
    username=>'admin',
    password=>'demo123',
    type=>'staff'
});
ok(
    $script->authtoken,
    'Have an authtoken'
);

# Register workstation.
my $ws = $script->find_or_register_workstation(BR1_WORKSTATION, BR1_ID);
ok(
    ! ref $ws,
    'Found or registered workstation'
);

# Logout.
$script->logout();
ok(
    ! $script->authtoken,
    'Successfully logged out'
);

# Login as admin at BR1 using the workstation.
$authtoken = $script->authenticate({
    username=>'admin',
    password=>'demo123',
    type=>'staff',
    workstation => BR1_WORKSTATION
});
ok(
    $script->authtoken,
    'Have an authtoken'
);

# Set up a serials bib record and subscription
$e->xact_begin;
my $bre = Fieldmapper::biblio::record_entry->new;
$bre->marc('<record></record>');
$bre->tcn_source('serial-record-for-hold');
$e->create_biblio_record_entry($bre) or die $e->die_event;
$e->commit;

$e->xact_begin;
my $act = Fieldmapper::asset::copy_template->new;
$act->owning_lib(BR1_ID);
$act->creator(1);
$act->editor(1);
$act->name('My template');
$act->loan_duration(2);
$act->fine_level(2);
$e->create_asset_copy_template($act) or die $e->die_event;
$e->commit;

$e->xact_begin;
my $ssub = Fieldmapper::serial::subscription->new;
$ssub->start_date('2015-01-01');
$ssub->record_entry($bre->id);
$e->create_serial_subscription($ssub);
$e->commit;

$e->xact_begin;
my $sdist = Fieldmapper::serial::distribution->new;
$sdist->subscription($ssub->id);
$sdist->holding_lib(BR1_ID);
$sdist->label('My distribution');
$sdist->receive_unit_template($act->id);
$e->create_serial_distribution($sdist);
$e->commit;

$e->xact_begin;
my $sstr = Fieldmapper::serial::stream->new;
$sstr->distribution($sdist->id);
$e->create_serial_stream($sstr);
$e->commit;

$e->xact_begin;
my $siss = Fieldmapper::serial::issuance->new;
$siss->creator(1);
$siss->editor(1);
$siss->subscription($ssub->id);
$siss->date_published('now');
$e->create_serial_issuance($siss);
$e->commit;

$e->xact_begin;
my $sitem = Fieldmapper::serial::item->new;
$sitem->create_date('now');
$sitem->edit_date('now');
$sitem->creator(1);
$sitem->editor(1);
$sitem->issuance($siss->id);
$sitem->stream($sstr->id);
$sitem->shadowed(0);
$sitem->date_expected('now');
$e->create_serial_item($sitem);
$e->commit;

my $fleshed_sitem = $U->simplereq(
    'open-ils.serial',
    'open-ils.serial.items.receivable.by_subscription',
    $authtoken,
    $ssub->id
);
# serial.receive_items expects us to provide an in-memory sunit with an id
# of -1, to indicate that we'd like the method to create a new sunit for us
my $sunit = Fieldmapper::serial::unit->new;
$sunit->id(-1);
$fleshed_sitem->unit($sunit);

my $receive_response = $U->simplereq(
    'open-ils.serial',
    'open-ils.serial.receive_items',
    $authtoken,
    [$fleshed_sitem],
    {$sitem->id => rand(99_999)}, # barcode
    {$sitem->id => ['', 'AB123.45', '']}, # call number
    {},
    {circ_mods => {$sitem->id => undef}, copy_locations => {$sitem->id => undef}}
);
if ($U->event_code($receive_response)) {
    diag explain $receive_response;
    fail 'could not receive the serial item';
} else {
    pass 'received the serial item';
}

# Now we are finally ready to place and attempt to retarget a hold

my $hold_response = $U->simplereq(
    'open-ils.circ',
    'open-ils.circ.holds.test_and_create.batch',
    $authtoken,
    {
        patronid => 145,
        pickup_lib => BR1_ID,
        hold_type => 'T',
        email_notify => 0,
        phone_notify => undef,
        thaw_date => undef,
        frozen => 0,
        sms_notify => undef,
        sms_carrier => undef,
        holdable_formats_map => undef,
    },
    [$bre->id]
);
my $hold_id = $hold_response->{'result'};
ok($hold_id, 'placed a hold');

my $hold_reset_response = $U->simplereq(
    'open-ils.circ',
    'open-ils.circ.hold.reset',
    $authtoken,
    $hold_id
);

if ($U->event_code($hold_reset_response)) {
    diag explain $hold_reset_response;
    fail 'could not retarget the hold';
} else {
    pass 're-targeted the hold';
}

