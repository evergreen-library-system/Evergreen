#!perl
use strict; use warnings;
use Test::More tests => 7;
use OpenILS::Utils::TestUtils;
use OpenILS::Const qw(:const);

diag('Magic statuses should not apply via item alert next_status checkin');

my $script = OpenILS::Utils::TestUtils->new();
my $apputils = 'OpenILS::Application::AppUtils';

use constant {
    WORKSTATION => 'BR1-test-lp2161007',
    ORG_ID => 4,
    COPY_BARCODE => 'CONC4000036' # owned at BR1
};

sub authenticate {
    my $ws = shift;
    my $credentials = {
        username => 'br1vcampbell',
        password => 'demo123',
        type => 'staff'
    };
    $credentials->{workstation} = $ws if $ws;
    return $script->authenticate($credentials);
}

sub pcrud_write {
    my ($method, $obj, $auth) = @_;
    my $ses = $script->session('open-ils.pcrud');
    $ses->connect();
    $ses->request('open-ils.pcrud.transaction.begin', $auth)->gather(1);
    my $res = $ses->request($method, $auth, $obj)->gather(1);
    $ses->request('open-ils.pcrud.transaction.commit', $auth)->gather(1);
    $ses->disconnect();
    return $res;
}

sub set_copy_status {
    my ($copy, $status, $auth) = @_;
    $copy->status($status);
    $copy->ischanged(1);
    return pcrud_write('open-ils.pcrud.update.acp', $copy, $auth);
}

sub get_copy_by_id {
    my ($id, $auth) = @_;
    return $apputils->simplereq('open-ils.pcrud',
        'open-ils.pcrud.retrieve.acp', $auth, $id
    );
}


# Login
my $authtoken = authenticate;
ok($authtoken, 'Initial login'
) or BAIL_OUT('Must login initially');


# Register workstation
my $ws = $script->find_or_register_workstation(WORKSTATION, ORG_ID);
ok(!ref $ws, 'Found or registered workstation'
) or BAIL_OUT('Need workstation');


# Logout
$script->logout($authtoken);
ok(!$script->authtoken, 'Logged out');


# Login as staff at BR1 using workstation.
$authtoken = authenticate(WORKSTATION);
ok($authtoken, 'Staff login'
) or BAIL_OUT('Must login as staff');


# get copy
my $copy = $apputils->simplereq('open-ils.search',
    'open-ils.search.asset.copy.find_by_barcode',
    COPY_BARCODE
);
isa_ok(ref $copy, 'Fieldmapper::asset::copy', 'Got copy'
) or BAIL_OUT('Must get copy');
my $orig_status = $copy->status;


# create alert type
my $type = Fieldmapper::config::copy_alert_type->new();
$type->scope_org(ORG_ID);
$type->active('t');
$type->name('test-lp2161007 magic');
$type->state('DAMAGED');
$type->event('CHECKIN');
$type->next_status('{6,5}'); # magic status first, then non-magic
$type = pcrud_write('open-ils.pcrud.create.ccat', $type, $authtoken);
isa_ok(ref $type, 'Fieldmapper::config::copy_alert_type',
    'Created alert type'
) or BAIL_OUT('Must create alert type');

set_copy_status($copy, OILS_COPY_STATUS_DAMAGED, $authtoken);


# override checkin to test if the first non-magic status is applied
$apputils->simplereq('open-ils.circ',
    'open-ils.circ.checkin.override',
    $authtoken,
    {
        barcode => COPY_BARCODE,
        new_copy_alerts => 1,
        capture => 'nocapture' # just in case...
    }
);
my $acp = get_copy_by_id($copy->id, $authtoken);
is($acp->status, OILS_COPY_STATUS_IN_PROCESS,
    'non-magic status in process applied'
);


# cleanup
set_copy_status(
    get_copy_by_id($copy->id, $authtoken),
    OILS_COPY_STATUS_AVAILABLE,
    $authtoken
);

$type->isdeleted(1);
pcrud_write('open-ils.pcrud.delete.ccat', $type, $authtoken);

$script->logout($authtoken);
