#!perl
use strict; use warnings;
use Test::More tests => 26;
use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Application::Acq::Order;

use constant WORKSTATION_LIB => 4;
use constant WORKSTATION_NAME => 'BR1-test-22-acq-reqs';

diag("Tests ACQ purchase requests");

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

$req = $script->session('open-ils.pcrud')->request(
    'open-ils.pcrud.retrieve.acqcr',
    $script->authtoken, 1015);
if (my $resp = $req->recv) {
    if (my $new_cr = $resp->content) {
# -----------------------------------------------------------------------------
# 3. Check for Canceled: Fulfilled
# -----------------------------------------------------------------------------
        is($new_cr->label,'Canceled: Fulfilled','New cancel reason for fulfilled requests');
    }
}

$req = $script->session('open-ils.pcrud')->request(
    'open-ils.pcrud.retrieve.aurt',
    $script->authtoken, 1);
if (my $resp = $req->recv) {
    if (my $aurt = $resp->content) {
# -----------------------------------------------------------------------------
# 4. Check for user request type Books
# -----------------------------------------------------------------------------
        is($aurt->label,'Books','Found user request type Books');
    }
}

my $aur;
my $aur_hash = {};
$aur_hash->{'request_type'} = 1; # Books
$aur_hash->{'usr'} = 87;         # Smith
$aur_hash->{'pickup_lib'} = 8;   # SL1
$aur_hash->{'email_notify'} = 'f';
$aur_hash->{'hold'} = 'f';
$aur_hash->{'title'} = 'test';

$req = $script->session('open-ils.acq')->request(
    'open-ils.acq.user_request.create',
    $script->authtoken, $aur_hash);
if (my $resp = $req->recv) {
    if ($aur = $resp->content) {
# -----------------------------------------------------------------------------
# 5. Check for created user request
# -----------------------------------------------------------------------------
        is(ref $aur, 'Fieldmapper::acq::user_request', 'User request created');
        diag('User Request ID = ' . $aur->id);
    }
}

$req = $script->session('open-ils.pcrud')->request(
    'open-ils.pcrud.retrieve.aurs',
    $script->authtoken, $aur->id);
if (my $resp = $req->recv) {
    if (my $aurs = $resp->content) {
# -----------------------------------------------------------------------------
# 6,7,8. Check for status-enhanced user request
# -----------------------------------------------------------------------------
        is($aurs->id,$aur->id,'Found status-enhanced user request');
        is($aurs->request_status,1,'Request Status = New');
        is($aurs->home_ou,8,'Home Lib = SL1');
    }
}

# open-ils.acq.picklist.create
# {"__c":"acqpl","__p":[null,1,"4","test",null,null,null,null,1,1]}
# {"__c":"acqpl","__p":[1,1,4,"test","2018-07-31T16:33:39-0400","now",null,null,1,1]}

my $picklist_id;
my $picklist = Fieldmapper::acq::picklist->new;
$picklist->isnew(1);
$picklist->owner(1);            # admin
$picklist->creator(1);          # admin
$picklist->editor(1);           # admin
$picklist->org_unit(8);         # SL1
$picklist->name( $script->authtoken ); # $picklist->name('22-acq-requests.t');
$picklist->create_time('now');
$picklist->edit_time('now');

$req = $script->session('open-ils.acq')->request(
    'open-ils.acq.picklist.create',
    $script->authtoken, $picklist);
if (my $resp = $req->recv) {
    if ($picklist_id = $resp->content) {
# -----------------------------------------------------------------------------
# 9. Check for created picklist
# -----------------------------------------------------------------------------
        ok($picklist_id > 0,'Created picklist aka selection list');
        diag('Picklist ID = ' . $picklist_id);
    }
}

my $jub_id;
my $jub = Fieldmapper::acq::lineitem->new;
$jub->selector(1);          # admin
$jub->picklist($picklist_id);
$jub->create_time('now');
$jub->edit_time('now');
$jub->marc('<record xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://www.loc.gov/MARC21/slim" xmlns:marc="http://www.loc.gov/MARC21/slim" xsi:schemaLocation="http://www.loc.gov/MARC21/slim http://www.loc.gov/ standards/marcxml/schema/MARC21slim.xsd"><leader>00000nam a22000007a 4500</leader><marc:datafield tag="245" ind1=" " ind2=" "><marc:subfield code="a">test  </marc:subfield></marc:datafield></record>');
$jub->state('new');
$jub->creator(1);           # admin
$jub->editor(1);            # admin
$jub->estimated_unit_price(1.00);
$jub->isnew(1);

$req = $script->session('open-ils.acq')->request(
    'open-ils.acq.lineitem.create',
    $script->authtoken, $jub);
if (my $resp = $req->recv) {
    if ($jub_id = $resp->content) {
# -----------------------------------------------------------------------------
# 10. Check for created lineitem
# -----------------------------------------------------------------------------
        ok($jub_id > 0,'Created lineitem');
        diag('Lineitem ID = ' . $jub_id);
    }
}

$req = $script->session('open-ils.pcrud')->request(
    'open-ils.pcrud.retrieve.aur',
    $script->authtoken, $aur->id);
if (my $resp = $req->recv) {
    if ($aur = $resp->content) {
# -----------------------------------------------------------------------------
# 11. Retrieve bare user request
# -----------------------------------------------------------------------------
        is(ref $aur,'Fieldmapper::acq::user_request','Retrieved bare user request');
    }
}

$aur->ischanged(1);
$aur->lineitem($jub_id);

diag('Updating aur->lineitem');
my $pcrud_ses = $script->session('open-ils.pcrud');
$pcrud_ses->connect();
my $xact = $pcrud_ses->request(
    'open-ils.pcrud.transaction.begin',
    $script->authtoken
)->gather(1);
my $aur_id = $pcrud_ses->request(
    'open-ils.pcrud.update.aur',
    $script->authtoken,
    $aur
)->gather(1);
# -----------------------------------------------------------------------------
# 12. Updated user request with lineitem
# -----------------------------------------------------------------------------
is($aur_id,$aur->id,'Updated user request with lineitem');

$pcrud_ses->request(
    'open-ils.pcrud.transaction.commit',
    $script->authtoken
)->gather(1);
$pcrud_ses->disconnect();
undef($pcrud_ses);

$req = $script->session('open-ils.acq')->request(
    'open-ils.acq.lineitem.batch_update',
    $script->authtoken, { 'lineitems' => [$jub_id] }, {
        "item_count" => 1, "location" => 118, "owning_lib" => 4, "fund" => 1});
if (my $resp = $req->recv) {
    if (my $return = $resp->content) {
# -----------------------------------------------------------------------------
# 13. Check adding of copy to line
# -----------------------------------------------------------------------------
        is($return,$jub_id,'Added copy to lineitem');
    }
}

$req = $script->session('open-ils.pcrud')->request(
    'open-ils.pcrud.retrieve.aurs',
    $script->authtoken, $aur->id);
if (my $resp = $req->recv) {
    if (my $aurs = $resp->content) {
# -----------------------------------------------------------------------------
# 14,15,16. Check user request status and lineitem
# -----------------------------------------------------------------------------
        is($aurs->id,$aur->id,'Re-retrieved status-enhanced user request');
        is($aurs->request_status,2,'Request Status = Pending');
        is($aurs->lineitem,$jub_id,'Lineitem matches');
    }
}

my $purchase_order_id;
my $purchase_order = Fieldmapper::acq::purchase_order->new;
$purchase_order->owner(1);                   # admin
$purchase_order->create_time('now');
$purchase_order->edit_time('now');
$purchase_order->provider(2);                # BRODART
$purchase_order->state('pending');
$purchase_order->ordering_agency(4);         # BR1
$purchase_order->creator(1);                 # admin
$purchase_order->editor(1);                  # admin
$purchase_order->name( $script->authtoken ); # $purchase_order->name('22-acq-requests.t');
$purchase_order->isnew(1);

$req = $script->session('open-ils.acq')->request(
    'open-ils.acq.purchase_order.create',
    $script->authtoken, $purchase_order, { 'lineitems' => [$jub_id] });
if (my $resp = $req->recv) {
    if (my $return = $resp->content) {
#FIXME: open-ils.acq.purchase_order.create docs needs to be updated with correct return value 
#FIXME: open-ils.acq.purchase_order.create docs needs to be updated for lineitem_ids argument
# -----------------------------------------------------------------------------
# 17. Check for created purchase_order
# -----------------------------------------------------------------------------
        $purchase_order_id = $$return{'purchase_order'}->id;
        ok($purchase_order_id > 0,'Created purchase_order');
        diag('Purchase Order ID = ' . $purchase_order_id);
    }
}

$req = $script->session('open-ils.pcrud')->request(
    'open-ils.pcrud.retrieve.aurs',
    $script->authtoken, $aur->id);
if (my $resp = $req->recv) {
    if (my $aurs = $resp->content) {
# -----------------------------------------------------------------------------
# 18, 19. Check user request status is still Pending
# -----------------------------------------------------------------------------
        is($aurs->id,$aur->id,'Re-retrieved status-enhanced user request');
        is($aurs->request_status,2,'Request Status = Pending');
    }
}


# open-ils.acq.purchase_order.assets.create
my $vlArgs = {
    'vandelay' => {
        'auto_overlay_1match' => 0,
        'match_quality_ratio' => '0.0',
        'queue_name' => $script->authtoken, #'queue_name' => '22-acq-requests.t',
        'import_no_match' => 'on',
        'bib_source' => '',
        'fall_through_merge_profile' => '',
        'merge_profile' => '',
        'auto_overlay_best_match' => 0,
        'strip_field_groups' => [],
        'auto_overlay_exact' => 0,
        'existing_queue' => '',
        'match_set' => ''
    }
};
$req = $script->session('open-ils.acq')->request(
    'open-ils.acq.purchase_order.assets.create',
    $script->authtoken, $purchase_order_id, $vlArgs);
if (my $resp = $req->recv) {
    if (my $return = $resp->content) {
# -----------------------------------------------------------------------------
# 20. Check for created assets
# -----------------------------------------------------------------------------
        is($return->{'complete'},1,'Assets created');
    }
}
$req = $script->session('open-ils.acq')->request(
    'open-ils.acq.purchase_order.activate',
    $script->authtoken, $purchase_order_id, {
        'no_assets' => 0, 'zero_copy_activate' => 0});
if (my $resp = $req->recv) {
    if (my $return = $resp->content) {
# -----------------------------------------------------------------------------
# 21. Check for activated purchase order
# -----------------------------------------------------------------------------
        is($return,1,'Purchase order activated');
    }
}

$req = $script->session('open-ils.pcrud')->request(
    'open-ils.pcrud.retrieve.aurs',
    $script->authtoken, $aur->id);
if (my $resp = $req->recv) {
    if (my $aurs = $resp->content) {
# -----------------------------------------------------------------------------
# 22, 23. Check user request status Ordered, No Hold Placed
# -----------------------------------------------------------------------------
        is($aurs->id,$aur->id,'Re-retrieved status-enhanced user request');
        is($aurs->request_status,3,'Request Status = Ordered, Hold Not Placed');
    }
}

$req = $script->session('open-ils.acq')->request(
    'open-ils.acq.user_request.cancel.batch.atomic',
    $script->authtoken, [ $aur_id ], 1015); # Canceled: Fulfilled
if (my $resp = $req->recv) {
    if (my $return = $resp->content) {
# -----------------------------------------------------------------------------
# 24. Check for activated purchase order
# -----------------------------------------------------------------------------
        is($return->[1]->{'complete'},1,'User request canceled with Canceled: Fulfilled');
    }
}

$req = $script->session('open-ils.pcrud')->request(
    'open-ils.pcrud.retrieve.aurs',
    $script->authtoken, $aur->id);
if (my $resp = $req->recv) {
    if (my $aurs = $resp->content) {
# -----------------------------------------------------------------------------
# 25, 26. Check user request status Ordered, No Hold Placed
# -----------------------------------------------------------------------------
        is($aurs->id,$aur->id,'Re-retrieved status-enhanced user request');
        is($aurs->request_status,7,'Request Status = Canceled');
    }
}

