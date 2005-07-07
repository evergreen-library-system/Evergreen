#!/usr/bin/perl -w
use strict;use warnings;
use OpenSRF::EX qw/:try/;
use OpenSRF::System;
use OpenILS::Utils::Fieldmapper;

die "USAGE:\n\t$0 config_file\n" unless @ARGV;

OpenSRF::System->bootstrap_client( config_file => $ARGV[0] );
my $session = OpenSRF::AppSession->create('open-ils.storage');
my $circ = OpenSRF::AppSession->create('open-ils.circ');

my $statuses = $session->request(
	'open-ils.storage.direct.config.copy_status.search.holdable.atomic',
	't')->gather(1);

my $locations = $session->request(
	'open-ils.storage.direct.asset.copy_location.search.holdable.atomic',
	't')->gather(1);

my $holds;

try {
	if ($ARGV[1]) {
		$holds = $session->request(
				'open-ils.storage.direct.action.hold_request.search.atomic',
				id => $ARGV[1] )->gather(1);
	} else {
		$holds = $session->request(
				'open-ils.storage.direct.action.hold_request.search.atomic',
				capture_time => undef )->gather(1);
	}
} catch Error with {
	my $e = shift;
	die "Could not retrieve uncaptured hold requests:\n\n$e\n";
};


for my $hold (@$holds) {
	metarecord_hold_capture($hold) if ($hold->hold_type eq 'M');
	title_hold_capture($hold) if ($hold->hold_type eq 'T');
	volume_hold_capture($hold) if ($hold->hold_type eq 'V');
	copy_hold_capture($hold) if ($hold->hold_type eq 'C');
	print '-'x80 . "\n";
}

sub copy_hold_capture {
	my $hold = shift;
	my $cps = shift;

	if (!defined($cps)) {
		try {
			$cps = $session->request(
				'open-ils.storage.direct.asset.copy.search.id.atomic',
				$hold->target )->gather(1);
	
		} catch Error with {
			my $e = shift;
			die "Could not retrieve initial volume list:\n\n$e\n";
		};
	}

	my @copies = grep { $_->holdable == 1  and $_->ref == 0 } @$cps;

	$circ->connect;
	print "Applying user defined filters for hold ".$hold->id."...\n";
	for (my $i = 0; $i < @copies; $i++) {
		$copies[$i] = undef if ($copies[$i] && !grep{ $copies[$i]->status eq $_->id}@$statuses);
		$copies[$i] = undef if ($copies[$i] && !grep{ $copies[$i]->location eq $_->id}@$locations);
		$copies[$i] = undef if (
			$copies[$i] &&
			!$circ->request(
				'open-ils.circ.permit_hold',
				$hold, $copies[$i] )->gather(1)
		);
	}
	$circ->disconnect;

	@copies = grep { defined $_ } @copies;

	my @prox_list;
	my $count = @copies;
	print "Found $count eligible copies for hold ".$hold->id.":\n";
	for my $cp (@copies) {
		my $prox = $session->request(
			'open-ils.storage.asset.copy.proximity',
			$cp->id, $hold->pickup_lib )->gather(1);
		print "\t".$cp->id." -> ".$cp->barcode." :: Proximity -> $prox\n";
		$prox_list[$prox] = [] unless defined($prox_list[$prox]);
		push @{$prox_list[$prox]}, $cp;
	}
	print "\n";

}

sub volume_hold_capture {
	my $hold = shift;
	my $vols = shift;

	if (!defined($vols)) {
		try {
			$vols = $session->request(
				'open-ils.storage.direct.asset.call_number.search.id.atomic',
				$hold->target )->gather(1);
	
		} catch Error with {
			my $e = shift;
			die "Could not retrieve initial volume list:\n\n$e\n";
		};
	}

	my @v_ids = map { $_->id } @$vols;

	my $cp_list;
	try {
		$cp_list = $session->request(
			'open-ils.storage.direct.asset.copy.search.call_number.atomic',
			\@v_ids )->gather(1);
	
	} catch Error with {
		my $e = shift;
		warn "Could not retrieve copy list:\n\n$e\n";
	};

	if (ref $cp_list) {
		my $count = @$cp_list;
		print "Found $count possible copies for hold ".$hold->id.":\n";
		for my $cp (@$cp_list) {
			print "\t".$cp->id." -> ".$cp->barcode."\n";
		}
		print "\n";
	}

	copy_hold_capture($hold,$cp_list) if (ref $cp_list and @$cp_list);
}

sub title_hold_capture {
	my $hold = shift;
	my $titles = shift;

	if (!defined($titles)) {
		try {
			$titles = $session->request(
				'open-ils.storage.direct.biblio.record_entry.search.id.atomic',
				$hold->target )->gather(1);
	
		} catch Error with {
			my $e = shift;
			die "Could not retrieve initial title list:\n\n$e\n";
		};
	}

	my @t_ids = map { $_->id } @$titles;
	my $cn_list;
	try {
		$cn_list = $session->request(
			'open-ils.storage.direct.asset.call_number.search.record.atomic',
			\@t_ids )->gather(1);
	
	} catch Error with {
		my $e = shift;
		warn "Could not retrieve volume list:\n\n$e\n";
	};

	if (ref $cn_list) {
		my $count = @$cn_list;
		print "Found $count volumes for hold ".$hold->id.":\n";
		for my $cn (@$cn_list) {
			print "\t".$cn->id." -> ".$cn->label."\n";
		}
		print "\n";
	}

	volume_hold_capture($hold,$cn_list) if (ref $cn_list and @$cn_list);
}

sub metarecord_hold_capture {
	my $hold = shift;

	my $titles;
	try {
		$titles = $session->request(
				'open-ils.storage.ordered.metabib.metarecord.records.atomic',
				$hold->target
			)->gather(1);
	
	} catch Error with {
		my $e = shift;
		die "Could not retrieve initial title list:\n\n$e\n";
	};

	try {
		my @recs = map {$_->record}
				@{$session->request(
					'open-ils.storage.direct.metabib.record_descriptor.search.atomic',
					record => $titles,
					item_type => [split '', $hold->holdable_formats],
				)->gather(1)};

		$titles = [];
		$titles = $session->request(
			'open-ils.storage.direct.biblio.record_entry.search.id.atomic',
			\@recs )->gather(1) if (@recs);
	
	} catch Error with {
		my $e = shift;
		die "Could not retrieve format-pruned title list:\n\n$e\n";
	};


	if (ref $titles) {
		my $count = @$titles;
		print "Found $count titles for hold ".$hold->id.":\n";
		for my $title (@$titles) {
			print "\t".$title->tcn_value." -> ".$title->fingerprint."\n";
		}
		print "\n";
	}

	title_hold_capture($hold,$titles) if (ref $titles and @$titles);
}


