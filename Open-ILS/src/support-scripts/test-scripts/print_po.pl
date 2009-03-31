#!/usr/bin/perl

#----------------------------------------------------------------
# Print PO
#----------------------------------------------------------------

require '../oils_header.pl';
use strict; use warnings;
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
                jub => [qw/attributes lineitem_details/],
                acqlid => [qw/fund location/]
            }
        }
    ]
);

die "No PO with id $po_id\n" unless $po;


print 'PO ID: ' . $po->id . "\n";
print 'Ordering Agency: ' . $po->ordering_agency->shortname . "\n";
print 'Provider: ' . $po->provider->code . "\n";
for my $li (@{$po->lineitems}) {
    print "  Lineitem:------------------\n";
    for my $li_attr (@{$li->attributes}) {
        print "  " . $li_attr->attr_name . ': ' . $li_attr->attr_value . "\n";
    }
    for my $li_det (@{$li->lineitem_details}) {
        print "    Copy----------------------\n";
        print "    Fund: " . $li_det->fund->code . "\n";
        print "    Location: " . $li_det->location->name . "\n";
    }
}
