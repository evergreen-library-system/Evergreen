#!/usr/bin/perl -w
use strict;
use OpenSRF::EX qw/:try/;
use OpenSRF::System;
use OpenSRF::Application;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils;

die "USAGE:\n\t$0 config_file\n" unless @ARGV;


# hard coded for now, option later

my $time = time;
my $check_expire = OpenSRF::Utils::interval_to_seconds( '10m' );

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time - $check_expire);
$year += 1900;
$mon += 1;
my $expire_threshold = sprintf(
	'%s-%0.2d-%0.2d %s:%0.2d:%0.s2-00',
	$year, $mon, $mday, $hour, $min, $sec
);

OpenSRF::System->bootstrap_client( config_file => $ARGV[0] );
my $session = OpenSRF::AppSession->create('open-ils.storage');

my $module = OpenSRF::Utils::SettingsClient
	->new
	->config_value('apps','open-ils.circ','implementation');

eval "use $module; $module->initialize;";
die "Can't load the open-ils.circ module [$module] : $@\n" if ($@);

my $user_filter = OpenSRF::Application->method_lookup('open-ils.circ.permit_hold');

my $statuses = $session->request(
	'open-ils.storage.direct.config.copy_status.search.holdable.atomic',
	't')->gather(1);

my $locations = $session->request(
	'open-ils.storage.direct.asset.copy_location.search.holdable.atomic',
	't')->gather(1);

my $holds;

my %cache = (titles => {}, cns => {});

try {
	if ($ARGV[1]) {
		$holds = $session->request(
				'open-ils.storage.direct.action.hold_request.search.atomic',
				id => $ARGV[1] )->gather(1);
	} else {
		$holds = $session->request(
				'open-ils.storage.direct.action.hold_request.search_where.atomic',
				{ capture_time => undef,
				  prev_check_time => { '<=' => $expire_threshold },
				},
				{ order_by => 'request_time,prev_check_time' } )->gather(1);
		push @$holds, @{
			$session->request(
				'open-ils.storage.direct.action.hold_request.search.atomic',
				{ capture_time => undef,
				  prev_check_time => undef },
				{ order_by => 'request_time,prev_check_time' } )->gather(1)
		};
	}
} catch Error with {
	my $e = shift;
	die "Could not retrieve uncaptured hold requests:\n\n$e\n";
};

$_->clear_current_copy for (@$holds);

for my $hold (@$holds) {
	my $copies;

	my @captured_copies = [ map {$_->current_copy} @$holds ];

	if (0) { # hold isn't check-expired
		# get the copies from the hold-map
		# and filter on "avialable"
	} else {
		$copies = metarecord_hold_capture($hold) if ($hold->hold_type eq 'M');
		$copies = title_hold_capture($hold) if ($hold->hold_type eq 'T');
		$copies = volume_hold_capture($hold) if ($hold->hold_type eq 'V');
		$copies = copy_hold_capture($hold) if ($hold->hold_type eq 'C');
	}

	next unless (ref $copies);

	my @good_copies;
	for my $c (@$copies) {
		next if ( grep {$c->id == $_} @captured_copies);
		push @good_copies, $c;
	}

	my $prox_list;
	$$prox_list[0] = [grep {$_->circ_lib == $hold->pickup_lib } @$copies];
	$copies = [grep {$_->circ_lib != $hold->pickup_lib } @$copies];

	my $best = choose_nearest_copy($hold, $prox_list);

	if (!$best) {
		$prox_list = create_prox_list( $hold->pickup_lib, $copies );
		$best = choose_nearest_copy($hold, $prox_list);
	}

	if ($best) {
		print "Updating hold ".$hold->id." with current_copy ".$best->id."\n";
		$hold->current_copy( $best->id );
	}

	$hold->prev_check_time( 'now');
	$session->request(
		'open-ils.storage.direct.action.hold_request.update',
		$hold )->gather(1) ||
			warn "Could not save hold ".$hold->id."\n";
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

	print "Applying user defined filters for hold ".$hold->id."...\n";
	for (my $i = 0; $i < @copies; $i++) {
		
		my $cn = $cache{cns}{$copies[0]->call_number};
		my $rec = $cache{titles}{$cn->record};
		$copies[$i] = undef if ($copies[$i] && !grep{ $copies[$i]->status eq $_->id}@$statuses);
		$copies[$i] = undef if ($copies[$i] && !grep{ $copies[$i]->location eq $_->id}@$locations);
		$copies[$i] = undef if (
			$copies[$i] &&
			!$user_filter->run( $hold, $copies[$i], { title => $rec, call_number => $cn } )
		);
	}

	@copies = grep { defined $_ } @copies;

	my $count = @copies;

	return unless ($count);
	
	print "Saving $count eligible copies for hold ".$hold->id.":\n";

	my $old_maps = $session->request(
		'open-ils.storage.direct.action.hold_copy_map.search.hold.atomic',
		$hold->id )->gather(1);

	$session->request( 'open-ils.storage.direct.action.hold_copy_map.batch.delete', @$old_maps )
		->gather(1) if (defined($old_maps) and @$old_maps);
	
	my @maps;
	for my $c (@copies) {
		my $m = new Fieldmapper::action::hold_copy_map;
		$m->hold( $hold->id );
		$m->target_copy( $c->id );
		$m->isnew( 1 );
		push @maps, $m;
	}

	$session->request(
		'open-ils.storage.direct.action.hold_copy_map.batch.create',
		@maps )->gather(1) ||
			warn "Could not save copies for hold ".$hold->id."\n";

	return \@copies;
}


sub choose_nearest_copy {
	my $hold = shift;
	my $prox_list = shift;

	for my $p ( 0 .. int( scalar(@$prox_list) - 1) ) {
		next unless (ref $$prox_list[$p]);
		my @capturable = grep { $_->status == 0 } @{ $$prox_list[$p] };
		next unless (@capturable);
		return $capturable[rand(scalar(@capturable))];
	}
}

sub create_prox_list {
	my $lib = shift;
	my $copies = shift;

	my @prox_list;
	print "Creating proximity list :\n";
	for my $cp (@$copies) {
		my $prox = $session->request(
			'open-ils.storage.asset.copy.proximity',
			$cp->id, $lib )->gather(1);
		print "\t".$cp->id." -> ".$cp->barcode." :: Proximity -> $prox\n";
		$prox_list[$prox] = [] unless defined($prox_list[$prox]);
		push @{$prox_list[$prox]}, $cp;
	}
	print "\n";
	return \@prox_list;
}

sub volume_hold_capture {
	my $hold = shift;
	my $vols = shift;

	if (!defined($vols)) {
		try {
			$vols = $session->request(
				'open-ils.storage.direct.asset.call_number.search.id.atomic',
				$hold->target )->gather(1);
	
			$cache{cns}{$_->id} = $_ for (@$vols);

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
	
			$cache{titles}{$_->id} = $_ for (@$titles);
	
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

	$cache{cns}{$_->id} = $_ for (@$cn_list);

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

	$cache{titles}{$_->id} = $_ for (@$titles);

	title_hold_capture($hold,$titles) if (ref $titles and @$titles);
}


