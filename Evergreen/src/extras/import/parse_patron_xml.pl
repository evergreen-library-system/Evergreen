#!/usr/bin/perl
use strict;
use warnings;

use lib '/openils/lib/perl5';

use OpenSRF::System;
use OpenSRF::EX qw/:try/;
use OpenSRF::AppSession;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::Fieldmapper;
use Digest::MD5 qw/md5_hex/;
use Getopt::Long;
use JSON;
use DateTime;
use Time::HiRes qw/time/;
use XML::LibXML;

my ($file,$config,$profileid,$identtypeid,$default_profile,$profile_map,$usermap) =
	('return_file_0623-2.xml', '/openils/conf/bootstrap.conf', 1, 3, 'User', 'profile.map');

GetOptions(
        'usermap=s'        => \$usermap,
        'file=s'        => \$file,
        'config=s'      => \$config,
        'default_profile=i'      => \$default_profile,
        'profile_map=s'      => \$profile_map,
        'profile_statcat_id=i'      => \$profileid,
        'identtypeid=i'      => \$identtypeid,
);

my %u_map;
if ($usermap) {
	open F, $usermap;
	while (my $line = <F>) {
		chomp($line);
		my ($b,$i) = split(/\|/, $line);
		$b =~ s/^\s*(\S+)\s*$/$1/o;
		$i =~ s/^\s*(\S+)\s*$/$1/o;
		$u_map{$b} = $i;
	}
	close F;
}

my %p_map;
if ($profile_map) {
	open F, $profile_map;
	while (my $line = <F>) {
		chomp($line);
		my ($b,$i) = split(/\|/, $line);
		$b =~ s/^\s*(\S+)\s*$/$1/o;
		$i =~ s/^\s*(\S+)\s*$/$1/o;
		$p_map{$b} = $i;
	}
	close F;
}

my $doc = XML::LibXML->new->parse_file($file);

OpenSRF::System->bootstrap_client( config_file => $config );
Fieldmapper->import(IDL => OpenSRF::Utils::SettingsClient->new->config_value("IDL"));

my $cstore = OpenSRF::AppSession->create( 'open-ils.cstore' );

my $profiles = $cstore->request(
		'open-ils.cstore.direct.permission.grp_tree.search.atomic',
		{ id => { '!=' => undef } },
)->gather(1);

my $orgs = $cstore->request(
		'open-ils.cstore.direct.actor.org_unit.search.atomic',
		{ id => { '!=' => undef } },
)->gather(1);

$profiles = { map { ($_->name => $_->id) } @$profiles };
$orgs = { map { ($_->shortname => $_->id) } @$orgs };

my $starttime = time;
my $count = 1;
for my $patron ( $doc->documentElement->childNodes ) {
	next if ($patron->nodeType == 3);
	my $p = new Fieldmapper::actor::user;
	my $card = new Fieldmapper::actor::card;
	my $profile_sce = new Fieldmapper::actor::stat_cat_entry_user_map;

	my $old_profile = $patron->findvalue( 'user_profile' );

	my $bc = $patron->findvalue( 'user_id' );

	unless (defined($bc)) {
		my $xml = $patron->toString;
		warn "!!! no barcode found in UMS data, user number $count, xml => $xml \n";
		$count++;
		next;
	}

	my $uid;
	if (keys %u_map) {
		$uid = $u_map{$bc};
		unless ($uid) {
			$count++;
			warn "!!! no uid mapping found for barcode $bc\n";
			next;
		}
	} else {
		next;
	}

	unless ($uid > 1) {
		$count++;
		warn "!!! user id lower than 2\n";
		next;
	}
	
	$card->barcode( $bc );
	$card->usr( $uid );
	$card->active( 't' );

	$p->id( $uid );
	$p->usrname( $bc );
	$p->passwd( $patron->findvalue( 'user_pin' ) );

	my $new_profile = $p_map{$old_profile} || $default_profile;

	$p->profile( $$profiles{$new_profile} );
	if (!$p->profile) {
		$count++;
		warn "!!! no new profile found for $old_profile\n";
		next;
	}

	# some defaults
	$p->standing(1);
	$p->active('t');
	$p->deleted('f');
	$p->master_account('f');
	$p->super_user('f');
	$p->usrgroup($uid);
	$p->claims_returned_count(0);
	$p->credit_forward_balance(0);
	$p->last_xact_id('IMPORT-'.$starttime);

	$p->barred('f');
	$p->barred('t') if ( $patron->findvalue( 'user_status' ) eq 'BARRED' );

	$p->ident_type( $identtypeid );
	my $id_val = $patron->findvalue( 'user_altid' );
	$p->ident_value( $id_val ) if ($id_val);

	my ($fname,$mname,$lname) = ($patron->findvalue('first_name'),$patron->findvalue('middle_name'),$patron->findvalue('last_name'));

	$fname =~ s/^\s*//o;
	$mname =~ s/^\s*//o;
	$lname =~ s/^\s*//o;

	$fname =~ s/\s*$//o;
	$mname =~ s/\s*$//o;
	$lname =~ s/\s*$//o;

	$p->first_given_name( $fname );
	$p->second_given_name( $mname );
	$p->family_name( $lname );

	$p->day_phone( $patron->findvalue( 'Address/dayphone' ) );
	$p->evening_phone( $patron->findvalue( 'Address/homephone' ) );
	$p->other_phone( $patron->findvalue( 'Address/workphone' ) );

	my $hlib = $$orgs{$patron->findvalue( 'user_library' )};
	unless ($hlib) {
		$count++;
		warn "!!! no home library found in patron record\n";
		next;
	}
	$p->home_ou( $hlib );

	$p->dob( parse_date( $patron->findvalue( 'birthdate' ) ) );
	$p->create_date( parse_date( $patron->findvalue( 'user_priv_granted' ) ) );
	$p->expire_date( parse_date( $patron->findvalue( 'user_priv_expires' ) ) );

	$p->alert_message("Legacy Import Message: old profile was FIXME")
		if ($old_profile eq 'FIXME');

	my $net_access = 1;
	$net_access = 2 if ($old_profile =~ /^U.I/o);
	$net_access = 3 if ($old_profile =~ /^X.I/o);

	$p->net_access_level( $net_access );

	$profile_sce->target_usr( $uid );
	$profile_sce->stat_cat( $profileid );
	$profile_sce->stat_cat_entry( $old_profile );

	my @addresses;
	my $mailing_addr_id = $patron->findvalue( 'user_mailingaddr' );

	my $all_valid = 't';
	for my $addr ( $patron->findnodes( "Address" ) ) {
		if (!$p->email) {
			$p->email( $patron->findvalue( 'email' ) );
		}

		my $prefix = 'coa_';

		my $line1 = $addr->findvalue( "${prefix}line1" );
		$prefix = 'std_' if (!$line1);

		$line1 = $addr->findvalue( "${prefix}line1" );
		next unless ($line1);

		my $a = new Fieldmapper::actor::user_address;
		$a->usr( $uid );
		$a->street1( $line1 );
		$a->street2( $addr->findvalue( "${prefix}line2" ) );
		$a->city( $addr->findvalue( "${prefix}city" ) );
		$a->state( $addr->findvalue( "${prefix}state" ) );
		$a->post_code(
			$addr->findvalue( "${prefix}zip" ) .
			'-' . $addr->findvalue( "${prefix}zip4" )
		);
		
		$a->valid( 'f' );
		$a->valid( 't' ) if ($prefix eq 'std_');
		$a->valid( 'f' ) if ($prefix eq 'std_' and $a->findvalue( "${prefix}dpvscore" ) < 3);
		
		$a->within_city_limits( 'f' );
		$a->country('USA');

		if ($addr->getAttribute('addr_type') == $mailing_addr_id) {
			$a->address_type( 'LEGACY MAILING' );
		} else {
			$a->address_type( 'LEGACY' );
		}

		push @addresses, $a;

		if ($prefix eq 'coa_') {
			$all_valid = 'f';
			$prefix = 'std_';

			$line1 = $addr->findvalue( "${prefix}line1" );
			next unless ($line1);

			$a = new Fieldmapper::actor::user_address;
			$a->usr( $uid );
			$a->street1( $line1 );
			$a->street2( $addr->findvalue( "${prefix}line2" ) );
			$a->city( $addr->findvalue( "${prefix}city" ) );
			$a->state( $addr->findvalue( "${prefix}state" ) );
			$a->post_code(
				$addr->findvalue( "${prefix}zip" ) .
				'-' . $addr->findvalue( "${prefix}zip4" )
			);
		
			$a->valid( 'f' );
		
			$a->within_city_limits( 'f' );
			$a->country('USA');

			$a->address_type( 'LEGACY' );

			push @addresses, $a;
		}
	}

	if ($all_valid eq 'f') {
		$_->valid('f') for (@addresses);
	}

	my @notes;
	for my $note_field ( qw#note comment voter bus_school Address/phone1 Address/phone2# ) {
		for my $note ( $patron->findnodes( $note_field) ) {
			my $a = new Fieldmapper::actor::usr_note;

			$a->creator(1);
			$a->create_date('now');
			$a->usr( $uid );
			$a->title( "Legacy ".$note->localName );
			$a->value( $note->textContent );
			$a->pub( 'f' );
			push @notes, $a;
		}
	}

	print STDERR "\r$count     ".$count/(time - $starttime) unless ($count % 100);
	print JSON->perl2JSON( $_ )."\n" for ($p,$card,$profile_sce,@addresses,@notes);

	$count++;
}

print STDERR "\n";


sub parse_date {
	my $string = shift;
	my $group = shift;

	my ($y,$m,$d);

	if ($string eq 'NEVER') {
		my (undef,undef,undef,$d,$m,$y) = localtime();
		return sprintf('%04d-%02d-%02d', $y + 1920, $m + 1, $d);
	} elsif (length($string) == 8 && $string =~ /^(\d{4})(\d{2})(\d{2})$/o) {
		($y,$m,$d) = ($1,$2,$3);
	} elsif ($string =~ /(\d+)\D(\d+)\D(\d+)/o) { #looks like it's parsable
		if ( length($3) > 2 )  { # looks like mm.dd.yyyy
			if ( $1 < 99 && $2 < 99 && $1 > 0 && $2 > 0 && $3 > 0) {
				if ($1 > 12 && $1 < 31 && $2 < 13) { # well, actually it looks like dd.mm.yyyy
					($y,$m,$d) = ($3,$2,$1);
				} elsif ($2 > 12 && $2 < 31 && $1 < 13) {
					($y,$m,$d) = ($3,$1,$2);
				}
			}
		} elsif ( length($1) > 3 ) { # format probably yyyy.mm.dd
			if ( $3 < 99 && $2 < 99 && $1 > 0 && $2 > 0 && $3 > 0) {
				if ($2 > 12 && $2 < 32 && $3 < 13) { # well, actually it looks like yyyy.dd.mm -- why, I don't konw
					($y,$m,$d) = ($1,$3,$2);
				} elsif ($3 > 12 && $3 < 31 && $2 < 13) {
					($y,$m,$d) = ($1,$2,$3);
				}
			}
		} elsif ( $1 < 99 && $2 < 99 && $3 < 99 && $1 > 0 && $2 > 0 && $3 > 0) {
			if ($3 < 7) { # probably 2000 or greater, mm.dd.yy
				$y = $3 + 2000;
				if ($1 > 12 && $1 < 32 && $2 < 13) { # well, actually it looks like dd.mm.yyyy
					($m,$d) = ($2,$1);
				} elsif ($2 > 12 && $2 < 32 && $1 < 13) {
					($m,$d) = ($1,$2);
				}
			} else { # probably before 2000, mm.dd.yy
				$y = $3 + 1900;
				if ($1 > 12 && $1 < 32 && $2 < 13) { # well, actually it looks like dd.mm.yyyy
					($m,$d) = ($2,$1);
				} elsif ($2 > 12 && $2 < 32 && $1 < 13) {
					($m,$d) = ($1,$2);
				}
			}
		}
	}

	my $date;
	if ($y && $m && $d) {
		try {
			$date = sprintf('%04d-%02d-%-2d',$y, $m, $d)
				if (new DateTime ( year => $y, month => $m, day => $d ));
		} otherwise {};
	}

	return $date;
}

