#!/usr/bin/perl
use strict; use warnings;
use Data::Dumper;
use OpenILS::Utils::TestUtils;
use OpenILS::Utils::CStoreEditor (':funcs');
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::Acq::EDI;
$Data::Dumper::Indent = 0;

use Test::More tests => 5;

diag("Tests EDI Shipment Notifications");

use constant {
    BR1_ID => 4,
    BR1_ADDR_ID => 4,
    BR1_SAN => 1234567,
    PROVIDER_SAN => 7654321,
    PROVIDER_ID => 2,
    BIB_ID => 248,
    LOCATION_ID => 1,
    FUND_ID => 1,
    ADMIN_ID => 1,
    ADMIN_USER => 'admin',
    ADMIN_PASS => 'demo123'
};

# Stub MARC with an ISBN as an order identifier
my $LI_MARC = <<MARC;
<record xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://www.loc.gov/MARC21/slim 
  http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd" 
  xmlns="http://www.loc.gov/MARC21/slim">
  <leader>         a              </leader>
  <datafield tag="020" ind1=" " ind2=" "> 
    <subfield code="a">9780307887436</subfield>
  </datafield>
  <datafield tag="245" ind1="1" ind2="0"> 
    <subfield code="a">iReady player one /</subfield>
  </datafield>
</record>
MARC

my $U = 'OpenILS::Application::AppUtils';
my $script = OpenILS::Utils::TestUtils->new();
$script->bootstrap;

my $po_id;
my $li_id;
my $edi_account;
my $e = new_editor;
$e->init;

$script->authenticate({
    username => ADMIN_USER,
    password => ADMIN_PASS,
    type => 'staff'
});

BAIL_OUT('Failed to Login') unless $script->authtoken;

sub main {
    $e->xact_begin;
    create_seed_data();
    create_po();
    BAIL_OUT("Failed to commit transaction") unless $e->commit;
    process_asn();
}


sub create_seed_data {

    my $addr = $e->retrieve_actor_org_address(BR1_ADDR_ID);
    $addr->san(BR1_SAN);

    BAIL_OUT("Could not apply SAN to BR1 " . Dumper($e->die_event))
        unless $e->update_actor_org_address($addr);
    
    $edi_account = Fieldmapper::acq::edi_account->new;
    $edi_account->owner(BR1_ID);
    $edi_account->provider(PROVIDER_ID);
    $edi_account->host("example.org");
    $edi_account->label("ASN TEST");
    $edi_account->use_attrs('f'); # doesn't matter here

    BAIL_OUT("Could not create EDI account " . Dumper($e->die_event))
        unless $e->create_acq_edi_account($edi_account);
}

sub create_po {

    my $po = Fieldmapper::acq::purchase_order->new;
    $po->ordering_agency(BR1_ID);
    $po->provider(PROVIDER_ID);
    $po->name("ASN-Test");

    my $resp = $U->simplereq('open-ils.acq', 
        'open-ils.acq.purchase_order.create', $script->authtoken, $po);

    BAIL_OUT("Failed to create PO: " . Dumper($resp)) if $U->is_event($resp);

    $po_id = $resp->{purchase_order}->id;

    ok($po_id, "Created Purchase Order");
    
    my $li = Fieldmapper::acq::lineitem->new;
    $li->purchase_order($po_id);
    $li->eg_bib_id(BIB_ID);
    $li->marc($LI_MARC);
    $li->creator(ADMIN_ID);
    $li->editor(ADMIN_ID);
    $li->selector(ADMIN_ID);
    $li->provider(PROVIDER_ID);
    $li->estimated_unit_price('25.00');

    $li_id = $U->simplereq('open-ils.acq',
        'open-ils.acq.lineitem.create', $script->authtoken, $li);

    BAIL_OUT("Failed to create Lineitem: " . Dumper($li_id)) if $U->is_event($li_id);

    ok($li_id, "Created Lineitem");

    my $lid = Fieldmapper::acq::lineitem_detail->new;
    $lid->isnew(1);
    $lid->lineitem($li_id);
    $lid->fund(FUND_ID);
    $lid->owning_lib(BR1_ID);
    $lid->location(LOCATION_ID);

    $resp = $U->simplereq('open-ils.acq',
        'open-ils.acq.lineitem_detail.cud.batch', $script->authtoken, [$lid]);

    BAIL_OUT("Failed to create Lineitem Detail: " . Dumper($resp)) if $U->is_event($resp);

    ok($resp->{lid} == 1, 'Created a lineitem detail');

    my $attr = $e->search_acq_lineitem_attr({
        lineitem => $li_id, 
        attr_name => 'isbn',
        attr_type => 'lineitem_marc_attr_definition'
    })->[0];

    BAIL_OUT("Lineitem creation did not create an ISBN attribute")
        unless $attr;

    $attr->order_ident('t');

    BAIL_OUT("Failed apply order_ident to ISBN attr: " . Dumper($e->die_event))
        unless $e->update_acq_lineitem_attr($attr);
}

sub process_asn {

    my $ASN = <<ASN;
UNA:+.?'
UNB+UNOC:3+7654321:31B+1234567:31B+211130:0825+99'
UNG+DESADV+7654321:31B+1234567:31B+211130:0825+94+UN+D:96A:UN'
UNH+193+DESADV:D:96A:UN'
BGM+351+MOM9681366+9'
DTM+137:20211130:102'
DTM+11:20211130:102'
DTM+132:20211207:102'
RFF+BM:2036362399'
NAD+SU+7654321::9'
NAD+BY+1234567 0011::9'
NAD+DP+1234567 0011::9'
CPS+1'
PAC+1+5'
GIN+BJ+00016921002621109648'
LIN+00001++9780307887436:EN'
QTY+12:1'
RFF+ON:$po_id'
CNT+2:1'
UNT+17+193'
UNE+1+94'
UNZ+1+99'
ASN

    my $in = OpenILS::Application::Acq::EDI->process_retrieval(
        $ASN, "remote-file-name",
        OpenILS::Application::Acq::EDI->remote_account($edi_account),
        $edi_account
    );

    my $notification = $e->search_acq_shipment_notification([
        {id => {'<>' => undef}},
        {flesh => 1, flesh_fields => {acqsn => ['entries']}}
    ])->[0];

    ok($notification, 'Created a notification');

    ok($notification->entries->[0]->lineitem eq $li_id, 
        "Created notification for lineitem $li_id");
}

main();

