#!/usr/bin/perl
# ---------------------------------------------------------------
# Generates the overdue notices XML file
# ./eg_gen_overdue.pl <bootstap> 0
#		generates today's notices
# ./eg_gen_overdue.pl <bootstap> 1 0
#		generates notices for today - 1 and today
# ./eg_gen_overdue.pl <bootstap> 2 1 0  
# ./eg_gen_overdue.pl <bootstap> 3 2 1 0  etc...
# ---------------------------------------------------------------



use strict; use warnings;
require '../../../Open-ILS/src/support-scripts/oils_header.pl';
use vars qw/$logger $apputils/;
use Data::Dumper;
use OpenILS::Const qw/:const/;
use DateTime;
use DateTime::Format::ISO8601;
use OpenSRF::Utils qw/:datetime/;
use Unicode::Normalize;

my $bsconfig = shift || die "usage: $0 <bootstrap_config>\n";
my @goback = @ARGV;
@goback = (0) unless @goback;
osrf_connect($bsconfig);
my $e = OpenILS::Utils::CStoreEditor->new;

my @date = CORE::localtime;
my $sec  = $date[0];
my $min  = $date[1];
my $hour = $date[2];
my $day  = $date[3];
my $mon  = $date[4] + 1;
my $year = $date[5] + 1900;

my %USER_CACHE;
my %ORG_CACHE;


print <<XML;
<?xml version='1.0' encoding='UTF-8'?>
<file type="notice" date="$day/$mon/$year" time="$hour:$min:$sec">
	<agency name="PINES">
XML

print_notices($_) for @goback;

print <<XML;
	</agency>
</file>
XML


# -----------------------------------------------------------------------
# -----------------------------------------------------------------------


sub print_notices {
	my $goback = shift || 0;

	for my $day ( qw/ 7 14 30 / ) {
		my ($start, $end) = make_date_range($day + $goback);
		$logger->debug("OD_notice: process date range $start -> $end");

		my $circs = $e->search_action_circulation(
			[
				{
					stop_fines => undef,
					due_date => { between => [ $start, $end ] }
				},
				{
					order_by => { circ => 'usr, circ_lib' }
				}
			],
			{ idlist => 1 }
		);

		process_circs( $circs, "${day}day" );
	}
}


sub process_circs {
	my $circs = shift;
	my $range = shift;

	return unless @$circs;

	$logger->debug("OD_notice: processing range $range and circs @$circs");

	my $org; 
	my $patron;
	my @current;

	for my $circ (@$circs) {
		$circ = $e->retrieve_action_circulation($circ);

		if( !defined $org or 
				$circ->circ_lib != $org  or $circ->usr ne $patron ) {
			$org = $circ->circ_lib;
			$patron = $circ->usr;
			print_notice( $range, \@current ) if @current;
			@current = ();
		}

		push( @current, $circ );
	}

	print_notice( $range, \@current );
}

sub make_date_range {
	my $daysback = shift;

	my $date = DateTime->from_epoch( 
		epoch => ( CORE::time - ($daysback * 24 * 60 * 60) ) );

	$date->set_hour(0);
	$date->set_minute(0);
	$date->set_second(0);
	my $start = "$date";

	$date->set_hour(23);
	$date->set_minute(59);
	$date->set_second(59);

	return ($start, "$date");
}


sub print_notice {
	my( $range, $circs ) = @_;
	return unless @$circs;
	my $org = $circs->[0]->circ_lib;
	my $usr = $circs->[0]->usr;
	$logger->debug("OD_notice: printing $range user:$usr org:$org");
	print "\t\t<notice type='overdue' count='$range'>\n";
	print_patron_chunk($usr);
	print_org_chunk($org);
	print_circ_chunk($_) for @$circs;
	print "\t\t</notice>\n";
}



sub print_patron_chunk {
	my $user_id = shift;

	my $patron = $USER_CACHE{$user_id};

	if( ! $patron ) {
		$logger->debug("OD_notice:   fetching patron $user_id");

		$patron = $e->retrieve_actor_user(
			[
				$user_id,
				{
					flesh => 1,
					flesh_fields => { 
						'au' => [qw/ card billing_address mailing_address /] 
					}
				}
			]
		) or return handle_event($e->event);

		$USER_CACHE{$user_id} = $patron;
	}

	my $bc = $patron->card->barcode;
	my $fn = $patron->first_given_name;
	my $mn = $patron->second_given_name;
	my $ln = $patron->family_name;

	my ( $s1, $s2, $city, $state, $zip );
	my $baddr = $patron->billing_address || $patron->mailing_address;
	if( $baddr ) {
		$s1		= $baddr->street1;
		$s2		= $baddr->street2;
		$city		= $baddr->city;
		$state	= $baddr->state;
		$zip		= $baddr->post_code;
	}

	$bc = entityize($bc);
	$fn = entityize($fn);
	$mn = entityize($mn);
	$ln = entityize($ln);
	$s1 = entityize($s1);
	$s2 = entityize($s2);
	$city  = entityize($city);
	$state = entityize($state);
	$zip	 = entityize($zip);

	
	print <<"	XML";
			<patron>
				<id type="barcode">$bc</id>
				<fullname>$fn $mn $ln</fullname>
				<street1>$s1 $s2</street1>
				<city_state_zip>$city, $state $zip</city_state_zip>
			</patron>
	XML

}

sub print_org_chunk {
	my $org_id = shift;

	my $org = $ORG_CACHE{$org_id};

	if( ! $org ) {
		$logger->debug("OD_notice:   fetching org $org_id");

		$org = $e->retrieve_actor_org_unit(
			[
				$org_id,
				{
					flesh => 1, 
					flesh_fields => 
						{ aou => [ qw/billing_address mailing_address/ ] }
				}
			]
		) or return handle_event($e->event);

		$ORG_CACHE{$org_id} = $org;
	}

	my $name = $org->name;

	my( $phone, $s1, $s2, $city, $state, $zip );
	my $baddr = $org->billing_address || $org->mailing_address;
	if( $baddr ) {
		$s1		= $baddr->street1;
		$s2		= $baddr->street2;
		$city		= $baddr->city;
		$state	= $baddr->state;
		$zip		= $baddr->post_code;
	}

	$name  = entityize($name);
	$phone = entityize($phone);
	$s1	 = entityize($s1);
	$s2	 = entityize($s2);
	$city  = entityize($city);
	$state = entityize($state);
	$zip	 = entityize($zip);


	print <<"	XML";
			<library>
				<libname>$name</libname>
				<libphone>$phone</libphone>
				<libstreet1>$s1 $s2</libstreet1>
				<libcity_state_zip>$city, $state $zip</libcity_state_zip>
			</library>
	XML
}

sub print_circ_chunk {
	my $circ = shift;

	my $title;
	my $author;
	my $cn;

	my $d = $circ->due_date;
	$d =~ s/[T ].*//og; # just for logging
	$logger->debug("OD_notice:   processing circ ".$circ->id." $d");

	my $due = DateTime::Format::ISO8601->new->parse_datetime(
		clense_ISO8601($circ->due_date));

	my $day  = $due->day;
	my $mon  = $due->month;
	my $year = $due->year;

	my $copy = $e->retrieve_asset_copy($circ->target_copy)
		or return handle_event($e->event);

	my $bc = $copy->barcode;

	if( $copy->call_number == OILS_PRECAT_CALL_NUMBER ) {
		$title = $copy->dummy_title || "";
		$author = $copy->dummy_author || "";

	} else {

		my $volume = $e->retrieve_asset_call_number(
			[
				$copy->call_number,
				{
					flesh => 1,
					flesh_fields => {
						acn => [ qw/record/ ]
					}
				}
			]
		) or return handle_event($e->event);

		$cn = $volume->label;
		my $mods = $apputils->record_to_mvr($volume->record);
		if( $mods ) {
			$title = $mods->title || "";
			$author = $mods->author || "";
		}
	}

	$title = entityize($title);
	$author = entityize($author);
	$cn = entityize($cn);
	$bc = entityize($bc);

	print <<"	XML";
			<item>
				<title>$title</title>
				<author>$author</author>
				<duedate>$day/$mon/$year</duedate>
				<callno>$cn</callno>
				<barcode>$bc</barcode>
			</item>
	XML
}



sub handle_event {
	my $evt = shift;
	warn "OD_notice: ".Dumper($evt) . "\n";
	$logger->error("OD_notice: ".Dumper($evt));
}


sub entityize {
	my $stuff = shift || return "";
	$stuff = NFC($stuff);
	$stuff =~ s/([\x{0080}-\x{fffd}])/sprintf('&#x%X;',ord($1))/sgoe;
	$stuff =~ s/\</&lt;/og;
	$stuff =~ s/\>/&gt;/og;
	$stuff =~ s/\&/&amp;/og;
	return $stuff;
}




