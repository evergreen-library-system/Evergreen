#!/usr/bin/perl
use lib '../../perlmods/';
use lib '../../../../OpenSRF/src/perlmods/';

use OpenSRF::System;
use OpenSRF::Application;
use OpenSRF::AppSession;
use OpenILS::Utils::Fieldmapper;

OpenSRF::System->bootstrap_client(config_file => '/pines/conf/bootstrap.conf');

my $storage = OpenSRF::AppSession->create('open-ils.storage');
die "Can't connect to storage!!" unless ($storage->connect);

my $worm_count = 15;
my @worms;
for (1 .. $worm_count) {
	my $worm = OpenSRF::AppSession->create('open-ils.worm');
	die "Can't connect to worm!!" unless ($worm->connect);
	push @worms, $worm;
}

print "Connected to the WORM ".scalar(@worms)." time\n";


my $wid = 0;
my @reqs;
while (my $line = <>) {
	chomp $line;
	$line =~ s/(\d+)/$1/o;
	my $req = $storage->request('open-ils.storage.biblio.record_marc.retrieve' => $line);
	my $resp = $req->recv;
	if ($resp and !$resp->isa('Error')) {
		my $record = $resp->content;
		push @reqs, $worms[$wid]->request('open-ils.worm.wormize.marc', $record->id, $record->marc);
		print "  Sent record $line to the WORM for munching\n";
	}
	$wid++;
	if ($wid == $worm_count) {
		while (my $r = shift(@reqs)) {
			$r->wait_complete;
			$r->finish;
		}
		$wid = 0;
	}
}
