#!perl
use strict; use warnings;
use Test::More tests => 25;
use OpenILS::Utils::TestUtils;
use OpenILS::Const qw(:const);

my $U = 'OpenILS::Application::AppUtils';
my $script = OpenILS::Utils::TestUtils->new();

diag("Test LP1929593 Wishlist: need separate permission for editing barcode");

use constant {
    BR1_ID => 4,
    BR3_ID => 6,
    WORKSTATION => 'BR1-lp1929593-ebarc'
};

# We are deliberately NOT using the admin user to check for a perm failure.
my $credentials = {
    username => 'br1mtownsend',
    password => 'demo123',
    type => 'staff'
};

# Log in as staff.
my $authtoken = $script->authenticate($credentials);
ok(
    $authtoken,
    'Logged in'
) or BAIL_OUT('Must log in');

# Find or register workstation.
my $ws = $script->find_or_register_workstation(WORKSTATION, BR1_ID);
ok(
    ! ref $ws,
    'Found or registered workstation'
) or BAIL_OUT('Need Workstation');

# Logout.
$script->logout();
ok(
    ! $script->authtoken,
    'Logged out'
);

# Login with workstation.
$credentials->{workstation} = WORKSTATION;
$credentials->{password} = 'demo123';
$authtoken = $script->authenticate($credentials);
ok(
    $script->authtoken,
    'Logged in with workstation'
) or BAIL_OUT('Must log in');

# Find available copy at BR1
my $acps = $U->simplereq(
    'open-ils.pcrud',
    'open-ils.pcrud.search.acp.atomic',
    $authtoken,
    {circ_lib => BR1_ID, status => OILS_COPY_STATUS_AVAILABLE},
    {limit => 1}
);
my $copy = $acps->[0];
isa_ok(
    ref $copy,
    'Fieldmapper::asset::copy',
    'Got available copy from BR1'
);

sub test_barcode_rename_expecting_success {
    my $copy = shift;

    diag('Testing re-barcoding of ' . $copy->barcode() . ', expecting successful re-barcoding.');
    my $original_barcode = $copy->barcode();

    # Re-barcode it
    my $result = $U->simplereq(
        'open-ils.cat',
        'open-ils.cat.update_copy_barcode',
        $authtoken,
        $copy->id(),
        'new' . $original_barcode
    );
    is(
        $result,
        $copy->id(),
        'open-ils.cat.update_copy_barcode indicates success'
    );

    # Double-check to be sure
    $copy = $U->simplereq(
        'open-ils.pcrud',
        'open-ils.pcrud.retrieve.acp',
        $authtoken,
        $copy->id()
    );
    is(
        $copy->barcode(),
        'new' . $original_barcode,
        'Copy was indeed re-barcoded'
    );
    diag('Current barcode: ' . $copy->barcode());

    # Change it back
    $result = $U->simplereq(
        'open-ils.cat',
        'open-ils.cat.update_copy_barcode',
        $authtoken,
        $copy->id(),
        $original_barcode
    );
    is(
        $result,
        $copy->id(),
        'open-ils.cat.update_copy_barcode indicates success'
    );

    # Double-check to be sure
    $copy = $U->simplereq(
        'open-ils.pcrud',
        'open-ils.pcrud.retrieve.acp',
        $authtoken,
        $copy->id()
    );
    is(
        $copy->barcode(),
        $original_barcode,
        'Copy was indeed re-barcoded'
    );
    diag('Current barcode: ' . $copy->barcode());
}

diag('Testing when user has both UPDATE_COPY and UPDATE_COPY_BARCODE');
test_barcode_rename_expecting_success($copy);

sub changePermCode {
    my $from = shift;
    my $to = shift;
    diag('Changing ' . $from . ' permission to ' . $to);

    # stateful cstore session
    my $cstore_ses = $script->session('open-ils.cstore');
    $cstore_ses->connect;

    # Now let's fetch the $from perm
    my $xact = $cstore_ses->request('open-ils.cstore.transaction.begin')->gather(1);
    my $retrieve_req = $cstore_ses->request(
        'open-ils.cstore.direct.permission.perm_list.search',
        { 'code' => $from }
    );
    my $perm = $retrieve_req->gather(1);
    is(
        $perm->code(),
        $from,
        "Fetched $from permission"
    );

    # now let's change the code
    $perm->code($to);
    my $update_req = $cstore_ses->request(
        'open-ils.cstore.direct.permission.perm_list.update',
        $perm
    );
    my $update_resp = $update_req->gather(1);
    is(
        $update_resp,
        $perm->id(),
        'cstore update successful'
    );

    $cstore_ses->request('open-ils.cstore.transaction.commit')->gather(1);
    $cstore_ses->disconnect();
}

changePermCode('UPDATE_COPY', 'WAS_UPDATE_COPY');
diag('Testing when user only has UPDATE_COPY_BARCODE');
test_barcode_rename_expecting_success($copy);

sub test_barcode_rename_expecting_failure {
    my $copy = shift;

    diag('Testing re-barcoding of ' . $copy->barcode() . ', expecting unsuccessful re-barcoding.');
    my $original_barcode = $copy->barcode();

    # Re-barcode it
    my $result = $U->simplereq(
        'open-ils.cat',
        'open-ils.cat.update_copy_barcode',
        $authtoken,
        $copy->id(),
        'new' . $original_barcode
    );
    isnt(
        $result,
        $copy->id(),
        'open-ils.cat.update_copy_barcode indicates failure'
    );

    # Double-check to be sure
    $copy = $U->simplereq(
        'open-ils.pcrud',
        'open-ils.pcrud.retrieve.acp',
        $authtoken,
        $copy->id()
    );
    is(
        $copy->barcode(),
        $original_barcode,
        'Copy was indeed not re-barcoded'
    );
    diag('Current barcode: ' . $copy->barcode());

    # Attempt to change it back, just in case things are succeeding when they're not supposed to
    $result = $U->simplereq(
        'open-ils.cat',
        'open-ils.cat.update_copy_barcode',
        $authtoken,
        $copy->id(),
        $original_barcode
    );
    isnt(
        $result,
        $copy->id(),
        'open-ils.cat.update_copy_barcode indicates failure'
    );

    # Double-check to be sure
    $copy = $U->simplereq(
        'open-ils.pcrud',
        'open-ils.pcrud.retrieve.acp',
        $authtoken,
        $copy->id()
    );
    is(
        $copy->barcode(),
        $original_barcode,
        'Copy was indeed not re-barcoded'
    );
    diag('Current barcode: ' . $copy->barcode());
}

changePermCode('UPDATE_COPY_BARCODE', 'WAS_UPDATE_COPY_BARCODE');

diag('Testing when user has neither UPDATE_COPY_BARCODE nor UPDATE_COPY');
test_barcode_rename_expecting_failure($copy);

# back to the way they were
changePermCode('WAS_UPDATE_COPY', 'UPDATE_COPY');
changePermCode('WAS_UPDATE_COPY_BARCODE', 'UPDATE_COPY_BARCODE');

# Logout
$script->logout(); # Not a test, just to be pedantic.
