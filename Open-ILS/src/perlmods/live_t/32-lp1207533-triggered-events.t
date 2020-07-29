#!perl

use strict; use warnings;
use Test::More tests => 10;
use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Application::AppUtils;

diag("Test patron triggered event log infrastructure");

use constant WORKSTATION_NAME => 'BR4-test-02-simple-circ.t'; # we'll just re-use this
use constant WORKSTATION_LIB => 7;
use constant ITEM_BARCODE => 'CONC70000345';
use constant ITEM_ID => 310;

my $script = OpenILS::Utils::TestUtils->new();
our $apputils = 'OpenILS::Application::AppUtils';

# -----------------------------------------------------------------------------
# 0. Let's get our auth token
# -----------------------------------------------------------------------------

$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff',
    workstation => WORKSTATION_NAME});
my $authtoken = $script->authtoken;
ok(
    $authtoken,
    'Have an authtoken associated with the workstation'
);

# -----------------------------------------------------------------------------
# 1. Let's create an easy A/T event definition template for circs
# -----------------------------------------------------------------------------

my $e = new_editor(xact => 1);
$e->init;

my $atevdef = Fieldmapper::action_trigger::event_definition->new;
$atevdef->active(1);
$atevdef->owner(1);
$atevdef->name('circ event test');
$atevdef->hook('checkout');
$atevdef->validator('NOOP_True');
$atevdef->reactor('NOOP_True');
$atevdef->delay('0');
$atevdef->delay_field('xact_start');
$atevdef->group_field('usr');
$atevdef->context_usr_path('usr');
$atevdef->context_library_path('circ_lib');
$atevdef->context_bib_path('target_copy.call_number.record');

$e->create_action_trigger_event_definition( $atevdef );
$e->commit;

my $defs = $e->search_action_trigger_event_definition({name => 'circ event test'});
is(scalar(@$defs), 1, 'Successfully created atevdef');

my $def_id = $defs->[0]->id;
diag("def id = $def_id");

# ---------------------------------------------------------------------------------
# 3. Let's redo an earlier circulation from another test and get an event this time
# ---------------------------------------------------------------------------------

my $checkout_resp = $script->do_checkout({
    patron => 1,
    barcode => ITEM_BARCODE});
is(
    ref $checkout_resp,
    'HASH',
    'Checkout request returned a HASH'
);
is(
    $checkout_resp->{ilsevent},
    0,
    'Checkout returned a SUCCESS event'
);

my $circ_id = $checkout_resp->{payload}->{circ}->id;

diag("circ id = $circ_id");
 
# -----------------------------------------------------------------------------
# 4. Let's find said event
# -----------------------------------------------------------------------------

sleep 2; # race condition

my $events = $e->search_action_trigger_event({event_def => $def_id, target => $circ_id});
is(scalar(@$events), 1, 'Found event');

# -----------------------------------------------------------------------------
# 5. Let's run action_trigger_runner to flesh said event
# -----------------------------------------------------------------------------

my $command = '/openils/bin/action_trigger_runner.pl --osrf-config /openils/conf/opensrf_core.xml --run-pending --verbose';
chomp(my $output = `$command`);
like($output, qr/run_pending: NON-GRANULAR/, 'action_trigger_runner.pl ran correctly');

# -----------------------------------------------------------------------------
# 6. Let's re-fetch the event and see if it's fleshed
# -----------------------------------------------------------------------------

sleep 2; # race condition

$events = $e->search_action_trigger_event({event_def => $def_id, target => $circ_id});
is(scalar(@$events), 1, 'Found event');

my $event = $events->[0];

is($event->context_user, 1, 'context_user is correct');
is($event->context_library, 7, 'context_library is correct');
is($event->context_bib, 10, 'context_bib is correct');

#use Data::Dumper::Perltidy;
#diag( Dumper($event) );
