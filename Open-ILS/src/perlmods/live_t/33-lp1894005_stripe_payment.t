#!perl

use Test::More tests => 9;

diag("Stripe relies on client-side code, but we can test a fail condition.");

use constant WORKSTATION_NAME => 'BR1-test-33-lp1894005_stripe_payment.t';
use constant WORKSTATION_LIB => 4;

use strict; use warnings;

use DateTime;
use DateTime::Format::ISO8601;
use OpenILS::Utils::DateTime qw/clean_ISO8601/;
use OpenILS::Utils::TestUtils;
my $script = OpenILS::Utils::TestUtils->new();
use Data::Dumper;

our $apputils   = "OpenILS::Application::AppUtils";

my ($patron_id, $patron_usrname, $xact_id, $item_id, $item_barcode);
my ($summary, $payment_blob, $pay_resp, $item_req, $checkin_resp);
my $user_obj;
my $storage_ses = $script->session('open-ils.storage');


sub retrieve_patron {
    my $patron_id = shift;

    my $user_req = $storage_ses->request('open-ils.storage.direct.actor.user.retrieve', $patron_id);
    if (my $user_resp = $user_req->recv) {
        if (my $patron_obj = $user_resp->content) {
            return $patron_obj;
        }
    }
    return 0;
}

sub fetch_billable_xact_summary {
    my $xact_id = shift;
    my $ses = $script->session('open-ils.cstore');
    my $req = $ses->request(
        'open-ils.cstore.direct.money.billable_transaction_summary.retrieve',
        $xact_id);

    if (my $resp = $req->recv) {
        return $resp->content;
    } else {
        return 0;
    }
}

sub pay_bills {
    my $payment_blob = shift;
    my $resp = $apputils->simplereq(
        'open-ils.circ',
        'open-ils.circ.money.payment',
        $script->authtoken,
        $payment_blob,
        $user_obj->last_xact_id
    );

    #refetch user_obj to get latest last_xact_id
    $user_obj = retrieve_patron($patron_id)
        or die 'Could not refetch patron';

    return $resp;
}

#----------------------------------------------------------------
# The tests...  assumes stock sample data
#----------------------------------------------------------------

# Connect to Evergreen
$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff'});
ok( $script->authtoken, 'Have an authtoken');

my $ws = $script->register_workstation(WORKSTATION_NAME,WORKSTATION_LIB);
ok( ! ref $ws, 'Registered a new workstation');

$script->logout();
$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff',
    workstation => WORKSTATION_NAME});
ok( $script->authtoken, 'Have an authtoken associated with the workstation');


### TODO: verify that stock data is ready for testing

### Setup Org Unit Settings that apply to all test cases

my $org_id = 1; #CONS
my $settings = {
    'credit.payments.allow' => 1,
    'credit.processor.default' => 'Stripe',
    'credit.processor.stripe.enabled' => 1
};

$apputils->simplereq(
    'open-ils.actor',
    'open-ils.actor.org_unit.settings.update',
    $script->authtoken,
    $org_id,
    $settings
);

# Setup first patron
$patron_id = 71;
$patron_usrname = '99999376864';

# Look up the patron
if ($user_obj = retrieve_patron($patron_id)) {
    is(
        ref $user_obj,
        'Fieldmapper::actor::user',
        'open-ils.storage.direct.actor.user.retrieve returned au object'
    );
    is(
        $user_obj->usrname,
        $patron_usrname,
        'Patron with id = ' . $patron_id . ' has username ' . $patron_usrname
    );
}


##############################
# 1. create a grocery bill
##############################

my $grocery = Fieldmapper::money::grocery->new();
$grocery->billing_location(4);
$grocery->note('lp1894005');
$grocery->usr(71);

$xact_id = $apputils->simplereq(
    'open-ils.circ',
    'open-ils.circ.money.grocery.create',
    $script->authtoken,
    $grocery
);

use Scalar::Util qw(looks_like_number);
ok( looks_like_number($xact_id), 'Created a grocery transaction' );

my $billing = Fieldmapper::money::billing->new();
$billing->xact($xact_id);
$billing->amount(100);
$billing->btype(101);
$billing->billing_type('Misc');
$billing->note('lp1894005');

my $billing_id = $apputils->simplereq(
    'open-ils.circ',
    'open-ils.circ.money.billing.create',
    $script->authtoken,
    $billing
);

ok( looks_like_number($billing_id), 'Created a billing' );

#refetch user_obj to get latest last_xact_id
$user_obj = retrieve_patron($patron_id)
    or die 'Could not refetch patron';

$summary = fetch_billable_xact_summary($xact_id);
ok( $summary, 'Found the transaction summary');

### pay the whole bill
$payment_blob = {
    userid => $patron_id,
    note => 'lp1894005',
    payment_type => 'credit_card_payment',
    patron_credit => '0.00',
    payments => [ [ $xact_id, '100.00' ] ],
    cc_args => {
        where_process => 1
    }
};
$pay_resp = pay_bills($payment_blob);
diag( 'pay_resp = ' . Dumper($pay_resp) );
is(
    $pay_resp->{textcode},
    'CREDIT_PROCESSOR_DECLINED_TRANSACTION',
    'received expected CREDIT_PROCESSOR_DECLINED_TRANSACTION'
);

$script->logout();

