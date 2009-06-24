#!/usr/bin/perl
#----------------------------------------------------------------
# Simple cstore example
#----------------------------------------------------------------

require '../oils_header.pl';
use strict; use warnings;
use OpenSRF::AppSession;
use OpenILS::Utils::Fieldmapper;

my $config = shift; # path to opensrf_core.xml
osrf_connect($config); # connect to jabber

my $ses = OpenSRF::AppSession->create("open-ils.cstore");
$ses->connect;

my $req = $ses->request('open-ils.cstore.transaction.begin');
my $stat = $req->gather(1);
die "cannot start transaction\n" unless $stat;

my $btype = Fieldmapper::config::billing_type->new;
$btype->name('Test 1');
$btype->owner(1);

$req = $ses->request('open-ils.cstore.direct.config.billing_type.create', $btype);
$stat = $req->gather(1);
die "cannot create object\n" unless $stat;
print "create returned $stat\n";

$req = $ses->request('open-ils.cstore.transaction.rollback');
$stat = $req->gather(1);
die "cannot rollback transaction\n" unless $stat;

$ses->disconnect;


