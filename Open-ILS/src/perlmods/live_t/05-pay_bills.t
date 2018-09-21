#!perl

use Test::More tests => 10;

diag("Test bill payment against the admin user.");

use constant WORKSTATION_NAME => 'BR4-test-05-pay-bills.t';
use constant WORKSTATION_LIB => 7;
use constant USER_ID => 1;
use constant USER_USRNAME => 'admin';

use strict; use warnings;

use OpenILS::Utils::TestUtils;
my $script = OpenILS::Utils::TestUtils->new();

use DateTime;
use DateTime::Format::ISO8601;
use OpenILS::Utils::DateTime qw/clean_ISO8601/;

our $apputils   = "OpenILS::Application::AppUtils";

sub fetch_billing_summaries {
    my $resp = $apputils->simplereq(
        'open-ils.actor',
        'open-ils.actor.user.transactions.history.have_balance.authoritative',
        $script->authtoken,
        USER_ID
    );
    return $resp;
}

sub pay_bills {
    my ($user_obj, $payment_blob) = (shift, shift);
    my $resp = $apputils->simplereq(
        'open-ils.circ',
        'open-ils.circ.money.payment',
        $script->authtoken,
        $payment_blob,
        $user_obj->last_xact_id
    );
    return $resp;
}

#----------------------------------------------------------------
# The tests...  assumes stock sample data
#----------------------------------------------------------------

my $storage_ses = $script->session('open-ils.storage');

my $user_obj;
my $user_req = $storage_ses->request('open-ils.storage.direct.actor.user.retrieve', USER_ID);
if (my $user_resp = $user_req->recv) {
    if ($user_obj = $user_resp->content) {
        is(
            ref $user_obj,
            'Fieldmapper::actor::user',
            'open-ils.storage.direct.actor.user.retrieve returned aou object'
        );
        is(
            $user_obj->usrname,
            USER_USRNAME,
            'User with id = ' . USER_ID . ' is ' . USER_USRNAME . ' user'
        );
    }
}

$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff'});
ok(
    $script->authtoken,
    'Have an authtoken'
);
my $ws = $script->register_workstation(WORKSTATION_NAME,WORKSTATION_LIB);
ok(
    ! ref $ws,
    'Registered a new workstation'
);

$script->logout();
$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff',
    workstation => WORKSTATION_NAME});
ok(
    $script->authtoken,
    'Have an authtoken associated with the workstation'
);

my $summaries = fetch_billing_summaries();

is(
    scalar(@{ $summaries }),
    2,
    'Two billable xacts for ' . USER_USRNAME . ' user from previous tests'
);

is(
    @{ $summaries }[0]->balance_owed + @{ $summaries }[1]->balance_owed,
    1.25,
    'Both transactions combined have a balance owed of 1.25'
);

my $payment_blob = {
    userid => USER_ID,
    note => '05-pay_bills.t',
    payment_type => 'cash_payment',
    patron_credit => '0.00',
    payments => [ map { [ $_->id, $_->balance_owed ] } @{ $summaries } ]
};

my $pay_resp = pay_bills($user_obj,$payment_blob);

is(
    ref $pay_resp,
    'HASH',
    'Payment attempt returned HASH'
);

is(
    scalar( @{ $pay_resp->{payments} } ),
    2,
    'Payment response included two payment ids'
);

my $new_summaries = fetch_billing_summaries();
is(
    scalar(@{ $new_summaries }),
    0,
    'Zero billable xacts for ' . USER_USRNAME . ' user after payment'
);

$script->logout();


