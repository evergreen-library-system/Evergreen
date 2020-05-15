#!perl
use strict; use warnings;
use Test::More tests => 10;
use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Application::Acq::Order;

use constant WORKSTATION_LIB => 4;
use constant WORKSTATION_NAME => 'BR1-test-30-age-protect-hold-capture';

diag("Tests hold capture with age protected items");

my $apputils = 'OpenILS::Application::AppUtils';
my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;
my $e = new_editor();
$e->init;

my $workstation = $e->search_actor_workstation(
    {name => WORKSTATION_NAME, owning_lib => WORKSTATION_LIB})->[0];

if (!$workstation) {
    $script->authenticate({
        username => 'admin',
        password => 'demo123',
        type => 'staff'
    });

    my $ws = $script->register_workstation(WORKSTATION_NAME, WORKSTATION_LIB);
    $script->logout();
}

$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff',
    workstation => WORKSTATION_NAME
});

my $ses = $script->session('open-ils.storage');
my $req = $ses->request('open-ils.storage.direct.actor.user.retrieve', 87);
if (my $resp = $req->recv) {
    if (my $user = $resp->content) {
# -----------------------------------------------------------------------------
# 1. We'll use Smith, Sarah (with usrname 99999303411 and home lib SL1)
# -----------------------------------------------------------------------------
        is(
            $user->usrname,
            '99999303411',
            'User with id = 87 is 99999303411'
        );
    }
}

# -----------------------------------------------------------------------------
# 2. Check for auth
# -----------------------------------------------------------------------------
ok($script->authtoken, 'Have an authtoken');


my $bre;
$req = $script->session('open-ils.cat')->request(
    'open-ils.cat.biblio.record.xml.create',
    $script->authtoken, '<record xmlns="http://www.loc.gov/MARC21/slim"><leader>00620cam a2200205Ka 4500</leader><controlfield tag="005">20200515120426.0</controlfield><controlfield tag="008">070101s                            eng d</controlfield><datafield tag="245" ind1=" " ind2=" "><subfield code="a">test 30</subfield> </datafield></record>','TEST');
if (my $resp = $req->recv) {
    if ($bre = $resp->content) {
# -----------------------------------------------------------------------------
# 3. Check for created bib
# -----------------------------------------------------------------------------
        ok($bre->id > 0,'Created bib record');
        diag('Bib ID = ' . $bre->id);
    }
}

my $acn = Fieldmapper::asset::call_number->new;
$acn->isnew(1);
$acn->deleted(0);
$acn->record($bre->id);
$acn->creator(1);          # admin
$acn->editor(1);           # admin
$acn->owning_lib(5);       # BR2 -- our test patron is at SL1, we want to set up age protection that'll kick in
$acn->label( 'test' );
$acn->create_date('now');
$acn->edit_date('now');

my $pcrud_ses = $script->session('open-ils.pcrud');
$pcrud_ses->connect();
my $xact = $pcrud_ses->request(
    'open-ils.pcrud.transaction.begin',
    $script->authtoken
)->gather(1);
my $acn_obj = $pcrud_ses->request(
    'open-ils.pcrud.create.acn',
    $script->authtoken,
    $acn
)->gather(1);
$pcrud_ses->request(
    'open-ils.pcrud.transaction.commit',
    $script->authtoken
)->gather(1);
$pcrud_ses->disconnect();
undef($pcrud_ses);
isa_ok(ref($acn_obj), 'Fieldmapper::asset::call_number', 'call number created');

my $acp = Fieldmapper::asset::copy->new;
$acp->isnew(1);
$acp->deleted(0);
$acp->call_number($acn_obj->id);
$acp->creator(1);           # admin
$acp->editor(1);            # admin
$acp->circ_lib(5);          # BR2 -- our test patron is at SL1, we want to set up age protection that'll kick in
$acp->age_protect(1);       # 3month    
$acp->barcode( $bre->id . '-1' );
$acp->create_date('now');
$acp->edit_date('now');
$acp->active_date('now');
$acp->status_changed_time('now');
$acp->status(0);            # available
$acp->location(1);          # stacks
$acp->loan_duration(2);     # normal
$acp->fine_level(2);        # normal
$acp->deposit(0);
$acp->deposit_amount(0.00);
$acp->ref(0);
$acp->holdable(1);
$acp->opac_visible(1);
$acp->mint_condition(1);
$pcrud_ses = $script->session('open-ils.pcrud');
$pcrud_ses->connect();
$xact = $pcrud_ses->request(
    'open-ils.pcrud.transaction.begin',
    $script->authtoken
)->gather(1);
my $acp_obj = $pcrud_ses->request(
    'open-ils.pcrud.create.acp',
    $script->authtoken,
    $acp
)->gather(1);
$pcrud_ses->request(
    'open-ils.pcrud.transaction.commit',
    $script->authtoken
)->gather(1);
$pcrud_ses->disconnect();
undef($pcrud_ses);
isa_ok(ref($acp_obj), 'Fieldmapper::asset::copy', 'copy created');

diag('creating 200 holds... will take a moment');

my $hold;
my $start_time = [Time::HiRes::gettimeofday()];
foreach my $i (1..200) {
    $hold = $apputils->simplereq(
        'open-ils.circ',
        'open-ils.circ.holds.test_and_create.batch.override',
        $script->authtoken,
        {   
            hold_type => 'T',
            patronid => 87, # our SL1 patron
            pickup_lib => $i == 200 ? 5 : 8 # SL1 for every hold request but the last one, which is BR2
        },
        [$bre->id]
    );
    if (ref($hold->{result})) {
        my $event = (ref($hold->{result}) eq 'ARRAY') ? $hold->{result}->[0] : $hold->{result};
        if ($event->{textcode} eq 'HOLD_EXISTS') {
            BAIL_OUT('.override did not work');
        } else {
            BAIL_OUT('Cannot place hold');
        }
    } else {
        $hold = $apputils->simplereq(
            'open-ils.pcrud',
            'open-ils.pcrud.retrieve.ahr',
            $script->authtoken,
            $hold->{result}
        );  
    }
}
my $diff = Time::HiRes::tv_interval($start_time);
diag("took $diff seconds");

# Check that last hold exists.
isa_ok(ref($hold), 'Fieldmapper::action::hold_request', 'Got last hold') or BAIL_OUT('Need hold');


diag('attempting checkin');

$start_time = [Time::HiRes::gettimeofday()];
my $checkin_resp = $script->do_checkin({
    barcode => $bre->id . '-1'});
$diff = Time::HiRes::tv_interval($start_time);

diag("took $diff seconds");

is(
    ref $checkin_resp,
    'HASH',
    'Checkin request returned a HASH'
);
is(
    $checkin_resp->{ilsevent},
    7000,
    'Checkin returned a ROUTE ITEM event'
);
is(
    $checkin_resp->{payload}->{copy}->barcode,
    $bre->id . '-1',
    'Checkin returned correct item in payload'
);
is(
    $checkin_resp->{payload}->{hold}->id,
    $hold->id,
    'Checkin returned correct hold in payload'
);

#use Data::Dumper::Perltidy;
#diag( Dumper($checkin_resp) );


