#!/usr/bin/perl

#----------------------------------------------------------------
# Print PO
#----------------------------------------------------------------

require '../oils_header.pl';
use strict;
my $config		= shift; 
my $username	= shift || 'admin';
my $password	= shift || 'open-ils';
my $po_id       = shift;

osrf_connect($config);
oils_login($username, $password);
my $e = OpenILS::Utils::CStoreEditor->new;

my $po = $e->retrieve_acq_purchase_order(
    [
        $po_id,
        {
            flesh => 3,
            flesh_fields => {
                acqpo => [qw/lineitems ordering_agency provider/],
                acqpro => [qw/addresses/],
                jub => [qw/attributes lineitem_details/],
                acqlid => [qw/fund location owning_lib/],
                aou => [qw/mailing_address billing_address/]
            }
        }
    ]
);

die "No PO with id $po_id\n" unless $po;


print 'PO ID: ' . $po->id . "\n";
print 'Ordering Agency: ' . $po->ordering_agency->shortname . "\n";

if(my $addr = $po->ordering_agency->mailing_address) {
    print "Mailing Address: \n";
    print '  street1: ' . $addr->street1 . "\n";
    print '  street2: ' . $addr->street2 . "\n";
    print '  city: ' . $addr->city . "\n";
    print '  county: ' . $addr->county . "\n";
    print '  state: ' . $addr->state . "\n";
    print '  country: ' . $addr->country . "\n";
    print '  post_code: ' . $addr->post_code . "\n";
}

if(my $addr = $po->ordering_agency->billing_address) {
    print "Billing Address: \n";
    print '  street1: ' . $addr->street1 . "\n";
    print '  street2: ' . $addr->street2 . "\n";
    print '  city: ' . $addr->city . "\n";
    print '  county: ' . $addr->county . "\n";
    print '  state: ' . $addr->state . "\n";
    print '  country: ' . $addr->country . "\n";
    print '  post_code: ' . $addr->post_code . "\n";
}

print 'Provider: ' . $po->provider->code . "\n";
if(my $addr = $po->provider->addresses->[0]) {
    print "Provider Address:\n";
    print '  street1: ' . $addr->street1 . "\n";
    print '  street2: ' . $addr->street2 . "\n";
    print '  city: ' . $addr->city . "\n";
    print '  county: ' . $addr->county . "\n";
    print '  state: ' . $addr->state . "\n";
    print '  country: ' . $addr->country . "\n";
    print '  post_code: ' . $addr->post_code . "\n";
}

for my $li (@{$po->lineitems}) {

    print "Lineitem:------------------\n";
    for my $li_attr (@{$li->attributes}) {
        print "  " . $li_attr->attr_name . ': ' . $li_attr->attr_value . "\n";
    }

    for my $li_det (@{$li->lineitem_details}) {
        print "  Copy----------------------\n";
        print "    Owning Lib: " . $li_det->owning_lib->shortname . "\n";
        print "    Fund: " . $li_det->fund->code . "\n";
        print "    Location: " . $li_det->location->name . "\n";
    }
}

