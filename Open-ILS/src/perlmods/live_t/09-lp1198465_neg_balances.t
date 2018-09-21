#!perl

use Test::More tests => 133;

diag("Test features of Conditional Negative Balances code.");

use constant WORKSTATION_NAME => 'BR1-test-09-lp1198465_neg_balances.t';
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

sub void_bills {
    my $billing_ids = shift; #array ref
    my $resp = $apputils->simplereq(
        'open-ils.circ',
        'open-ils.circ.money.billing.void',
        $script->authtoken,
        @$billing_ids
    );

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
    'circ.max_item_price' => 50,
    'circ.min_item_price' => 50,
    'circ.void_lost_on_checkin' => 1
};

$apputils->simplereq(
    'open-ils.actor',
    'open-ils.actor.org_unit.settings.update',
    $script->authtoken,
    $org_id,
    $settings
);

# Setup first patron
$patron_id = 4;
$patron_usrname = '99999355250';

# Look up the patron
if ($user_obj = retrieve_patron($patron_id)) {
    is(
        ref $user_obj,
        'Fieldmapper::actor::user',
        'open-ils.storage.direct.actor.user.retrieve returned aou object'
    );
    is(
        $user_obj->usrname,
        $patron_usrname,
        'Patron with id = ' . $patron_id . ' has username ' . $patron_usrname
    );
}


##############################
# 1. No Prohibit Negative Balance Settings Are Enabled, Payment Made
##############################

### Setup use case variables
$xact_id = 1;
$item_id = 2;
$item_barcode = 'CONC4000037';

$summary = fetch_billable_xact_summary($xact_id);
ok( $summary, 'CASE 1: Found the transaction summary');
is(
    $summary->balance_owed,
    '50.00',
    'Starting balance owed is 50.00 for lost item'
);

### pay the whole bill
$payment_blob = {
    userid => $patron_id,
    note => '09-lp1198465_neg_balances.t',
    payment_type => 'cash_payment',
    patron_credit => '0.00',
    payments => [ [ $xact_id, '50.00' ] ]
};
$pay_resp = pay_bills($payment_blob);

is(
    scalar( @{ $pay_resp->{payments} } ),
    1,
    'Payment response included one payment id'
);

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '0.00',
    'Remaining balance of 0.00 after payment'
);

### check-in the lost copy

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        is(
            ref $item,
            'Fieldmapper::asset::copy',
            'open-ils.storage.direct.asset.copy.retrieve returned acp object'
        );
        is(
            $item->status,
            3,
            'Item with id = ' . $item_id . ' has status of LOST'
        );
    }
}

$checkin_resp = $script->do_checkin_override({
    barcode => $item_barcode});
is(
    $checkin_resp->{ilsevent},
    0,
    'Checkin returned a SUCCESS event'
);

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        ok(
            $item->status == 7 || $item->status == 0,
            'Item with id = ' . $item_id . ' has status of Reshelving or Available after fresh Storage request'
        );
    }
}

### verify ending state

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '-50.00',
    'Patron has a negative balance (credit) of 50.00 due to overpayment'
);


##############################
# 2. Negative Balance Settings Are Unset, No Payment Made
##############################

### Setup use case variables
$xact_id = 2;
$item_id = 3;
$item_barcode = 'CONC4000038';

$summary = fetch_billable_xact_summary($xact_id);
ok( $summary, 'CASE 2: Found the transaction summary');
is(
    $summary->balance_owed,
    '50.00',
    'Starting balance owed is 50.00 for lost item'
);

### check-in the lost copy

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        is(
            $item->status,
            3,
            'Item with id = ' . $item_id . ' has status of LOST'
        );
    }
}

$checkin_resp = $script->do_checkin_override({
    barcode => $item_barcode});
is(
    $checkin_resp->{ilsevent},
    0,
    'Checkin returned a SUCCESS event'
);

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        ok(
            $item->status == 7 || $item->status == 0,
            'Item with id = ' . $item_id . ' has status of Reshelving or Available after fresh Storage request'
        );
    }
}

### verify ending state

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '0.00',
    'Patron has a balance of 0.00'
);


##############################
# 13. RERUN of Case 1. No Prohibit Negative Balance Settings Are Enabled, Payment Made
# SETTINGS: Prohibit negative balances on bills for lost materials
##############################

# Setup next patron
$patron_id = 6;
$patron_usrname = '99999335859';

# Look up the patron
if ($user_obj = retrieve_patron($patron_id)) {
    is(
        ref $user_obj,
        'Fieldmapper::actor::user',
        'open-ils.storage.direct.actor.user.retrieve returned aou object'
    );
    is(
        $user_obj->usrname,
        $patron_usrname,
        'Patron with id = ' . $patron_id . ' has username ' . $patron_usrname
    );
}

### Setup use case variables
$xact_id = 13;
$item_id = 14;
$item_barcode = 'CONC4000049';

# Setup Org Unit Settings
$settings = {
    'bill.prohibit_negative_balance_on_lost' => 1
};
$apputils->simplereq(
    'open-ils.actor',
    'open-ils.actor.org_unit.settings.update',
    $script->authtoken,
    $org_id,
    $settings
);

$summary = fetch_billable_xact_summary($xact_id);
ok( $summary, 'CASE 13a: Found the transaction summary');
is(
    $summary->balance_owed,
    '50.00',
    'Starting balance owed is 50.00 for lost item'
);

### pay the whole bill
$payment_blob = {
    userid => $patron_id,
    note => '09-lp1198465_neg_balances.t',
    payment_type => 'cash_payment',
    patron_credit => '0.00',
    payments => [ [ $xact_id, '50.00' ] ]
};
$pay_resp = pay_bills($payment_blob);

is(
    scalar( @{ $pay_resp->{payments} } ),
    1,
    'Payment response included one payment id'
);

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '0.00',
    'Remaining balance of 0.00 after payment'
);

### check-in the lost copy

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        is(
            ref $item,
            'Fieldmapper::asset::copy',
            'open-ils.storage.direct.asset.copy.retrieve returned acp object'
        );
        is(
            $item->status,
            3,
            'Item with id = ' . $item_id . ' has status of LOST'
        );
    }
}

$checkin_resp = $script->do_checkin_override({
    barcode => $item_barcode});
is(
    $checkin_resp->{ilsevent},
    0,
    'Checkin returned a SUCCESS event'
);

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        ok(
            $item->status == 7 || $item->status == 0,
            'Item with id = ' . $item_id . ' has status of Reshelving or Available after fresh Storage request'
        );
    }
}

### verify ending state

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '0.00',
    'Patron has a balance of 0.00 (negative balance prevented)'
);


##############################
# 13. RERUN of Case 12. Test negative balance settings on fines
# SETTINGS: Prohibit negative balances on bills for lost materials
##############################

### Setup use case variables
$xact_id = 14;
$item_id = 15;
$item_barcode = 'CONC4000050';

# Setup Org Unit Settings
# ALREADY SET:
#    'bill.prohibit_negative_balance_on_lost' => 1

$summary = fetch_billable_xact_summary($xact_id);
ok( $summary, 'CASE 13b: Found the transaction summary');
is(
    $summary->balance_owed,
    '0.70',
    'Starting balance owed is 0.70 for overdue fines'
);

### partially pay the bill
$payment_blob = {
    userid => $patron_id,
    note => '09-lp1198465_neg_balances.t',
    payment_type => 'cash_payment',
    patron_credit => '0.00',
    payments => [ [ $xact_id, '0.20' ] ]
};
$pay_resp = pay_bills($payment_blob);

is(
    scalar( @{ $pay_resp->{payments} } ),
    1,
    'Payment response included one payment id'
);

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '0.50',
    'Remaining balance of 0.50 after payment'
);

### Check in using Amnesty Mode
$checkin_resp = $script->do_checkin_override({
    barcode => $item_barcode,
    void_overdues => 1
});
is(
    $checkin_resp->{ilsevent},
    0,
    'Checkin returned a SUCCESS event'
);

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        ok(
            $item->status == 7 || $item->status == 0,
            'Item with id = ' . $item_id . ' has status of Reshelving or Available after fresh Storage request'
        );
    }
}

### verify ending state
$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '-0.20',
    'Patron has a negative balance of -0.20 (refund of overdue fine payment)'
);


### adjust to zero, manually
$apputils->simplereq(
    'open-ils.circ',
    'open-ils.circ.money.billable_xact.adjust_to_zero',
    $script->authtoken,
    [$xact_id]
);

### verify 2nd ending state
$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '0.00',
    'Case 13 (bonus): Patron has a balance of 0.00 (after manual adjustment of negative balance)'
);


##############################
# 14. RERUN of Case 1. No Prohibit Negative Balance Settings Are Enabled, Payment Made
# SETTINGS: Prohibit negative balances on bills for overdue materials
##############################

### Setup use case variables
$xact_id = 15;
$item_id = 16;
$item_barcode = 'CONC4000051';

# Setup Org Unit Settings
$settings = {
    'bill.prohibit_negative_balance_on_lost' => 0, #unset from previous test
    'bill.prohibit_negative_balance_on_overdues' => 1
};
$apputils->simplereq(
    'open-ils.actor',
    'open-ils.actor.org_unit.settings.update',
    $script->authtoken,
    $org_id,
    $settings
);

$summary = fetch_billable_xact_summary($xact_id);
ok( $summary, 'CASE 14a: Found the transaction summary');
is(
    $summary->balance_owed,
    '50.00',
    'Starting balance owed is 50.00 for lost item'
);

### pay the whole bill
$payment_blob = {
    userid => $patron_id,
    note => '09-lp1198465_neg_balances.t',
    payment_type => 'cash_payment',
    patron_credit => '0.00',
    payments => [ [ $xact_id, '50.00' ] ]
};
$pay_resp = pay_bills($payment_blob);

is(
    scalar( @{ $pay_resp->{payments} } ),
    1,
    'Payment response included one payment id'
);

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '0.00',
    'Remaining balance of 0.00 after payment'
);

ok(
    $summary->xact_finish ne '',
    'xact_finish is set due to 0.00 balance'
);

### check-in the lost copy

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        is(
            ref $item,
            'Fieldmapper::asset::copy',
            'open-ils.storage.direct.asset.copy.retrieve returned acp object'
        );
        is(
            $item->status,
            3,
            'Item with id = ' . $item_id . ' has status of LOST'
        );
    }
}

$checkin_resp = $script->do_checkin_override({
    barcode => $item_barcode});
is(
    $checkin_resp->{ilsevent},
    0,
    'Checkin returned a SUCCESS event'
);

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        ok(
            $item->status == 7 || $item->status == 0,
            'Item with id = ' . $item_id . ' has status of Reshelving or Available after fresh Storage request'
        );
    }
}

### verify ending state

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '-50.00',
    'Patron has a negative balance (credit) of 50.00 due to overpayment'
);

ok(
    !defined($summary->xact_finish),
    'xact_finish is not set due to non-zero balance'
);


##############################
# 14. RERUN of Case 12. Test negative balance settings on fines
# SETTINGS: Prohibit negative balances on bills for overdue materials
##############################

### Setup use case variables
$xact_id = 16;
$item_id = 17;
$item_barcode = 'CONC4000052';

# Setup Org Unit Settings
# ALREADY SET:
#    'bill.prohibit_negative_balance_on_overdues' => 1

$summary = fetch_billable_xact_summary($xact_id);
ok( $summary, 'CASE 14b: Found the transaction summary');
is(
    $summary->balance_owed,
    '0.70',
    'Starting balance owed is 0.70 for overdue fines'
);

### partially pay the bill
$payment_blob = {
    userid => $patron_id,
    note => '09-lp1198465_neg_balances.t',
    payment_type => 'cash_payment',
    patron_credit => '0.00',
    payments => [ [ $xact_id, '0.20' ] ]
};
$pay_resp = pay_bills($payment_blob);

is(
    scalar( @{ $pay_resp->{payments} } ),
    1,
    'Payment response included one payment id'
);

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '0.50',
    'Remaining balance of 0.50 after payment'
);

### Check in using Amnesty Mode
$checkin_resp = $script->do_checkin_override({
    barcode => $item_barcode,
    void_overdues => 1
});
is(
    $checkin_resp->{ilsevent},
    0,
    'Checkin returned a SUCCESS event'
);

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        ok(
            $item->status == 7 || $item->status == 0,
            'Item with id = ' . $item_id . ' has status of Reshelving or Available after fresh Storage request'
        );
    }
}

### verify ending state
$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '0.00',
    'Patron has a balance of 0.00 (negative balance prevented)'
);


##############################
# 3. Basic No Negative Balance Test
##############################

# Re-setup first patron
$patron_id = 4;
$patron_usrname = '99999355250';

# Look up the patron
if ($user_obj = retrieve_patron($patron_id)) {
    is(
        ref $user_obj,
        'Fieldmapper::actor::user',
        'open-ils.storage.direct.actor.user.retrieve returned aou object'
    );
    is(
        $user_obj->usrname,
        $patron_usrname,
        'Patron with id = ' . $patron_id . ' has username ' . $patron_usrname
    );
}


### Setup use case variables
$xact_id = 3;
$item_id = 4;
$item_barcode = 'CONC4000039';

# Setup Org Unit Settings
$settings = {
    'bill.prohibit_negative_balance_on_overdues' => 0, #unset from previous test
    'bill.prohibit_negative_balance_default' => 1
};
$apputils->simplereq(
    'open-ils.actor',
    'open-ils.actor.org_unit.settings.update',
    $script->authtoken,
    $org_id,
    $settings
);

$summary = fetch_billable_xact_summary($xact_id);
ok( $summary, 'CASE 3: Found the transaction summary');
is(
    $summary->balance_owed,
    '50.00',
    'Starting balance owed is 50.00 for lost item'
);

### check-in the lost copy

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        is(
            $item->status,
            3,
            'Item with id = ' . $item_id . ' has status of LOST'
        );
    }
}

$checkin_resp = $script->do_checkin_override({
    barcode => $item_barcode});
is(
    $checkin_resp->{ilsevent},
    0,
    'Checkin returned a SUCCESS event'
);

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        ok(
            $item->status == 7 || $item->status == 0,
            'Item with id = ' . $item_id . ' has status of Reshelving or Available after fresh Storage request'
        );
    }
}

### verify ending state

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '0.00',
    'Patron has a balance of 0.00 (negative balance prevented)'
);

##############################
# 4. Prohibit Negative Balances with Partial Payment
##############################

### Setup use case variables
$xact_id = 4;
$item_id = 5;
$item_barcode = 'CONC4000040';

# Setup Org Unit Settings
# ALREADY SET:
#     'bill.prohibit_negative_balance_default' => 1

$summary = fetch_billable_xact_summary($xact_id);
ok( $summary, 'CASE 4: Found the transaction summary');
is(
    $summary->balance_owed,
    '50.00',
    'Starting balance owed is 50.00 for lost item'
);

### confirm the copy is lost
$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        is(
            $item->status,
            3,
            'Item with id = ' . $item_id . ' has status of LOST'
        );
    }
}

### partially pay the bill
$payment_blob = {
    userid => $patron_id,
    note => '09-lp1198465_neg_balances.t',
    payment_type => 'cash_payment',
    patron_credit => '0.00',
    payments => [ [ $xact_id, '10.00' ] ]
};
$pay_resp = pay_bills($payment_blob);

is(
    scalar( @{ $pay_resp->{payments} } ),
    1,
    'Payment response included one payment id'
);

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '40.00',
    'Remaining balance of 40.00 after payment'
);

### check-in the lost copy
$checkin_resp = $script->do_checkin_override({
    barcode => $item_barcode});
is(
    $checkin_resp->{ilsevent},
    0,
    'Checkin returned a SUCCESS event'
);

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        ok(
            $item->status == 7 || $item->status == 0,
            'Item with id = ' . $item_id . ' has status of Reshelving or Available after fresh Storage request'
        );
    }
}

### verify ending state

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '0.00',
    'Patron has a balance of 0.00 (negative balance prevented)'
);


##############################
# Restore then generate new overdues on xact with adjustments
##############################

### Setup use case variables
$xact_id = 5;
$item_id = 6;
$item_barcode = 'CONC4000041';

# Setup Org Unit Settings
# ALREADY SET:
#     'bill.prohibit_negative_balance_default' => 1
$settings = {
    'circ.restore_overdue_on_lost_return' => 1,
    'circ.lost.generate_overdue_on_checkin' => 1
};

$apputils->simplereq(
    'open-ils.actor',
    'open-ils.actor.org_unit.settings.update',
    $script->authtoken,
    $org_id,
    $settings
);

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '50.00',
    'Starting balance owed is 50.00 for lost item'
);

$checkin_resp = $script->do_checkin_override({
    barcode => $item_barcode
});
is(
    $checkin_resp->{ilsevent},
    0,
    'Checkin returned a SUCCESS event'
);

### verify ending state
$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '3.00',
    'Patron has a balance of 3.00 (newly generated fines, up to maxfines)'
);


##############################
# 12. Test negative balance settings on fines
##############################

# Setup next patron
$patron_id = 5;
$patron_usrname = '99999387993';

# Look up the patron
if ($user_obj = retrieve_patron($patron_id)) {
    is(
        ref $user_obj,
        'Fieldmapper::actor::user',
        'open-ils.storage.direct.actor.user.retrieve returned aou object'
    );
    is(
        $user_obj->usrname,
        $patron_usrname,
        'Patron with id = ' . $patron_id . ' has username ' . $patron_usrname
    );
}

### Setup use case variables
$xact_id = 7;
$item_id = 8;
$item_barcode = 'CONC4000043';

# Setup Org Unit Settings
# ALREADY SET:
#     'bill.prohibit_negative_balance_default' => 1

$summary = fetch_billable_xact_summary($xact_id);
ok( $summary, 'CASE 12: Found the transaction summary');
is(
    $summary->balance_owed,
    '0.70',
    'Starting balance owed is 0.70 for overdue fines'
);

### partially pay the bill
$payment_blob = {
    userid => $patron_id,
    note => '09-lp1198465_neg_balances.t',
    payment_type => 'cash_payment',
    patron_credit => '0.00',
    payments => [ [ $xact_id, '0.20' ] ]
};
$pay_resp = pay_bills($payment_blob);

is(
    scalar( @{ $pay_resp->{payments} } ),
    1,
    'Payment response included one payment id'
);

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '0.50',
    'Remaining balance of 0.50 after payment'
);

### Check in using Amnesty Mode
$checkin_resp = $script->do_checkin_override({
    barcode => $item_barcode,
    void_overdues => 1
});
is(
    $checkin_resp->{ilsevent},
    0,
    'Checkin returned a SUCCESS event'
);

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        ok(
            $item->status == 7 || $item->status == 0,
            'Item with id = ' . $item_id . ' has status of Reshelving or Available after fresh Storage request'
        );
    }
}

### verify ending state
$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '0.00',
    'Patron has a balance of 0.00 (remaining fines forgiven)'
);


##############################
# 10. Interval Testing
##############################

# Setup Org Unit Settings
# ALREADY SET:
#     'bill.prohibit_negative_balance_default' => 1

# Setup Org Unit Settings
$settings = {
    'bill.negative_balance_interval_default' => '1 hour'
};

$apputils->simplereq(
    'open-ils.actor',
    'open-ils.actor.org_unit.settings.update',
    $script->authtoken,
    $org_id,
    $settings
);

### Setup use case variables
$xact_id = 8;
$item_id = 9;
$item_barcode = 'CONC4000044';

$summary = fetch_billable_xact_summary($xact_id);
ok( $summary, 'CASE 10.1: Found the transaction summary');
is(
    $summary->balance_owed,
    '0.00',
    'Starting balance owed is 0.00 (LOST fee paid)'
);

### Check in first item (right after its payment)
$checkin_resp = $script->do_checkin_override({
    barcode => $item_barcode,
});
is(
    $checkin_resp->{ilsevent},
    0,
    'Checkin returned a SUCCESS event'
);

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        ok(
            $item->status == 7 || $item->status == 0,
            'Item with id = ' . $item_id . ' has status of Reshelving or Available after fresh Storage request'
        );
    }
}

### verify ending state for 10.1
$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '-50.00',
    'Patron has a balance of -50.00 (lost item returned during interval)'
);

### Setup use case variables
$xact_id = 9;
$item_id = 10;
$item_barcode = 'CONC4000045';

$summary = fetch_billable_xact_summary($xact_id);
ok( $summary, 'CASE 10.2: Found the transaction summary');
is(
    $summary->balance_owed,
    '0.00',
    'Starting balance owed is 0.00 (LOST fee paid)'
);

### Check in second item (2 hours after its payment)
$checkin_resp = $script->do_checkin_override({
    barcode => $item_barcode,
});
is(
    $checkin_resp->{ilsevent},
    0,
    'Checkin returned a SUCCESS event'
);

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        ok(
            $item->status == 7 || $item->status == 0,
            'Item with id = ' . $item_id . ' has status of Reshelving or Available after fresh Storage request'
        );
    }
}

### verify ending state
$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '0.00',
    'Patron has a balance of 0.00 (lost item returned after interval)'
);


#############################
# 6. Restores Overdue Fines Appropriately, No Previous "Voids", Patron Will Not Owe On Lost Item Return
#############################

### Setup use case variables
$xact_id = 10;
$item_id = 11;
$item_barcode = 'CONC4000046';

# Setup Org Unit Settings
$settings = {
    'bill.negative_balance_interval_default' => 0, #unset previous setting
    'circ.void_overdue_on_lost' => 1,
    'circ.restore_overdue_on_lost_return' => 1,
    'circ.lost.generate_overdue_on_checkin' => 1
};

$apputils->simplereq(
    'open-ils.actor',
    'open-ils.actor.org_unit.settings.update',
    $script->authtoken,
    $org_id,
    $settings
);

$summary = fetch_billable_xact_summary($xact_id);
ok( $summary, 'CASE 6: Found the transaction summary');
is(
    $summary->balance_owed,
    '40.00',
    'Starting balance owed is 40.00 for partially paid lost item'
);

### check-in the lost copy

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        is(
            ref $item,
            'Fieldmapper::asset::copy',
            'open-ils.storage.direct.asset.copy.retrieve returned acp object'
        );
        is(
            $item->status,
            3,
            'Item with id = ' . $item_id . ' has status of LOST'
        );
    }
}

$checkin_resp = $script->do_checkin_override({
    barcode => $item_barcode});
is(
    $checkin_resp->{ilsevent},
    0,
    'Checkin returned a SUCCESS event'
);

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        ok(
            $item->status == 7 || $item->status == 0,
            'Item with id = ' . $item_id . ' has status of Reshelving or Available after fresh Storage request'
        );
    }
}

### verify ending state

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '0.00',
    'Patron has a balance of 0.00 (negative balance prevented)'
);


#############################
# 7. Restores Overdue Fines Appropriately, No Previous "Voids", Patron Will Still Owe On Lost Item Return
#############################

### Setup use case variables
$xact_id = 11;
$item_id = 12;
$item_barcode = 'CONC4000047';

# Setup Org Unit Settings
# ALREADY SET:
#     'bill.prohibit_negative_balance_default' => 1
#     'circ.void_overdue_on_lost' => 1,
#     'circ.restore_overdue_on_lost_return' => 1,
#     'circ.lost.generate_overdue_on_checkin' => 1

$apputils->simplereq(
    'open-ils.actor',
    'open-ils.actor.org_unit.settings.update',
    $script->authtoken,
    $org_id,
    $settings
);

$summary = fetch_billable_xact_summary($xact_id);
ok( $summary, 'CASE 7: Found the transaction summary');
is(
    $summary->balance_owed,
    '0.70',
    'Starting balance owed is 0.70 for overdues'
);

### mark item as LOST
$apputils->simplereq(
    'open-ils.circ',
    'open-ils.circ.circulation.set_lost',
    $script->authtoken,
    {barcode => $item_barcode}
);

$summary = fetch_billable_xact_summary($xact_id);
ok( $summary, 'Found the transaction summary');
is(
    $summary->balance_owed,
    '50.00',
    'New balance owed is 50.00 for LOST fee'
);

### partially pay the bill
$payment_blob = {
    userid => $patron_id,
    note => '09-lp1198465_neg_balances.t',
    payment_type => 'cash_payment',
    patron_credit => '0.00',
    payments => [ [ $xact_id, '0.10' ] ]
};
$pay_resp = pay_bills($payment_blob);

is(
    scalar( @{ $pay_resp->{payments} } ),
    1,
    'Payment response included one payment id'
);

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '49.90',
    'Remaining balance of 49.90 after payment'
);

### check-in the lost copy

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        is(
            ref $item,
            'Fieldmapper::asset::copy',
            'open-ils.storage.direct.asset.copy.retrieve returned acp object'
        );
        is(
            $item->status,
            3,
            'Item with id = ' . $item_id . ' has status of LOST'
        );
    }
}

$checkin_resp = $script->do_checkin_override({
    barcode => $item_barcode});
is(
    $checkin_resp->{ilsevent},
    0,
    'Checkin returned a SUCCESS event'
);

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        ok(
            $item->status == 7 || $item->status == 0,
            'Item with id = ' . $item_id . ' has status of Reshelving or Available after fresh Storage request'
        );
    }
}

### verify ending state

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '0.60',
    'Patron has a balance of 0.60 due to reinstated overdue fines'
);


#############################
# 9. Restore Overdue Fines Appropriately, Previous Voids, Negative Balance Allowed
#############################

### Setup use case variables
$xact_id = 12;
$item_id = 13;
$item_barcode = 'CONC4000048';

# Setup Org Unit Settings
# ALREADY SET:
#     'bill.prohibit_negative_balance_default' => 1
#     'circ.void_overdue_on_lost' => 1,
#     'circ.restore_overdue_on_lost_return' => 1,
#     'circ.lost.generate_overdue_on_checkin' => 1

$apputils->simplereq(
    'open-ils.actor',
    'open-ils.actor.org_unit.settings.update',
    $script->authtoken,
    $org_id,
    $settings
);

$summary = fetch_billable_xact_summary($xact_id);
ok( $summary, 'CASE 9: Found the transaction summary');
is(
    $summary->balance_owed,
    '50.00',
    'Starting balance owed is 50.00 for lost item'
);

### partially pay the bill
$payment_blob = {
    userid => $patron_id,
    note => '09-lp1198465_neg_balances.t',
    payment_type => 'cash_payment',
    patron_credit => '0.00',
    payments => [ [ $xact_id, '10.00' ] ]
};
$pay_resp = pay_bills($payment_blob);

is(
    scalar( @{ $pay_resp->{payments} } ),
    1,
    'Payment response included one payment id'
);

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '40.00',
    'Remaining balance of 40.00 after payment'
);

### check-in the lost copy

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        is(
            ref $item,
            'Fieldmapper::asset::copy',
            'open-ils.storage.direct.asset.copy.retrieve returned acp object'
        );
        is(
            $item->status,
            3,
            'Item with id = ' . $item_id . ' has status of LOST'
        );
    }
}

$checkin_resp = $script->do_checkin_override({
    barcode => $item_barcode});
is(
    $checkin_resp->{ilsevent},
    0,
    'Checkin returned a SUCCESS event'
);

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        ok(
            $item->status == 7 || $item->status == 0,
            'Item with id = ' . $item_id . ' has status of Reshelving or Available after fresh Storage request'
        );
    }
}

### verify ending state

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '0.00',
    'Patron has a balance of 0.00 (negative balance prevented)'
);


#############################
# 8. Restore Overdue Fines Appropriately, Previous Voids, Negative Balance Allowed
#############################

## TODO: consider using a later xact_id/item_id, instead of reverting back to user 4

# Setup first patron (again)
$patron_id = 4;
$patron_usrname = '99999355250';

# Look up the patron
if ($user_obj = retrieve_patron($patron_id)) {
    is(
        ref $user_obj,
        'Fieldmapper::actor::user',
        'open-ils.storage.direct.actor.user.retrieve returned aou object'
    );
    is(
        $user_obj->usrname,
        $patron_usrname,
        'Patron with id = ' . $patron_id . ' has username ' . $patron_usrname
    );
}

### Setup use case variables
$xact_id = 6;
$item_id = 7;
$item_barcode = 'CONC4000042';

# Setup Org Unit Settings
# ALREADY SET:
#     'circ.void_overdue_on_lost' => 1,
#     'circ.restore_overdue_on_lost_return' => 1,
#     'circ.lost.generate_overdue_on_checkin' => 1
$settings = {
    'bill.prohibit_negative_balance_default' => 0
};

$apputils->simplereq(
    'open-ils.actor',
    'open-ils.actor.org_unit.settings.update',
    $script->authtoken,
    $org_id,
    $settings
);

$summary = fetch_billable_xact_summary($xact_id);
ok( $summary, 'CASE 8: Found the transaction summary');
is(
    $summary->balance_owed,
    '50.00',
    'Starting balance owed is 50.00 for lost item'
);

### partially pay the bill
$payment_blob = {
    userid => $patron_id,
    note => '09-lp1198465_neg_balances.t',
    payment_type => 'cash_payment',
    patron_credit => '0.00',
    payments => [ [ $xact_id, '10.00' ] ]
};
$pay_resp = pay_bills($payment_blob);

is(
    scalar( @{ $pay_resp->{payments} } ),
    1,
    'Payment response included one payment id'
);

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '40.00',
    'Remaining balance of 40.00 after payment'
);

### check-in the lost copy

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        is(
            ref $item,
            'Fieldmapper::asset::copy',
            'open-ils.storage.direct.asset.copy.retrieve returned acp object'
        );
        is(
            $item->status,
            3,
            'Item with id = ' . $item_id . ' has status of LOST'
        );
    }
}

$checkin_resp = $script->do_checkin_override({
    barcode => $item_barcode});
is(
    $checkin_resp->{ilsevent},
    0,
    'Checkin returned a SUCCESS event'
);

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        ok(
            $item->status == 7 || $item->status == 0,
            'Item with id = ' . $item_id . ' has status of Reshelving or Available after fresh Storage request'
        );
    }
}

### verify ending state

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '-7.00',
    'Patron has a negative balance of 7.00 due to overpayment'
);



$script->logout();


