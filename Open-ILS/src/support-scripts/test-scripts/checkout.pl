#!/usr/bin/perl

#----------------------------------------------------------------
# Code for testing the container API
#----------------------------------------------------------------

require '../oils_header.pl';
use vars qw/ $apputils $memcache $user $authtoken $authtime /;
use strict; use warnings;
use Time::HiRes qw/time/;

#----------------------------------------------------------------
err("\nusage: $0 <config> <oils_login_username> ".
	" <oils_login_password> <patronid> <copy_barcode> [<type>, <noncat_type>]\n".
	"Where <type> is one of:\n".
	"\t'permit' to run the permit only\n".
	"\t'noncat_permit' to run the permit script against a noncat item\n".
	"\t'noncat' to check out a noncat item\n".
	"\t(blank) to do a regular checkout\n" ) unless $ARGV[4];
#----------------------------------------------------------------

my $config		= shift; 
my $username	= shift;
my $password	= shift;
my $patronid	= shift;
my $barcode		= shift;
my $type			= shift || "";
my $nc_type		= shift;

my $start;

sub go {
	osrf_connect($config);
	oils_login($username, $password);

	if($type eq 'renew') {
		do_renew($patronid, $barcode);

	} elsif( $type eq 'transit_receive' ) {
		do_transit_receive($barcode);

	} elsif( $type eq 'checkin' ) {
		do_checkin($barcode);
	} else {
		my($key,$precat) = do_permit($patronid, $barcode, $type =~ /noncat/ ); 
		printl("Item is pre-cataloged...") if $precat;
		do_checkout($key, $patronid, $barcode, 
			$precat, $type =~ /noncat/, $nc_type ) unless ($type =~ /permit/);
	}
	#oils_logout(); # - this will break the post-method db updates
}

go();

#----------------------------------------------------------------

sub do_permit {
	my( $patronid, $barcode, $noncat ) = @_;

	my $precat = 0;
	my $args = { patron => $patronid, barcode => $barcode };
	if($noncat) {
		$args->{noncat} = 1;
		$args->{noncat_type} = $nc_type;
	}

	$start = time();
	my $resp = simplereq( 
		CIRC(), 'open-ils.circ.checkout.permit', $authtoken, $args );

	if( oils_event_equals($resp, 'ITEM_NOT_CATALOGED') ) {
		$precat = 1;


	} else {

		oils_event_die($resp);	 
	
		if( ref($resp) eq 'ARRAY' ) { # we received a list of non-success events
			if( oils_event_equals($$resp[0], 'COPY_ALERT_MESSAGE') ) {
				printl("copy has alert attached: " . $$resp[0]->{payload});
				printl("");
				debug($resp);
				printl("");
			}

			printl("received event: ".$_->{textcode}) for @$resp;
			return undef;
		} 
	}

	my $e = time() - $start;
	my $key = $resp->{payload};
	printl("Permit OK: \n\ttime =\t$e\n\tkey =\t$key" );
	
	return ( $key, $precat );
}

sub do_checkout {
	my( $key, $patronid, $barcode, $precat, $noncat, $nc_type ) = @_;

	my $args = { permit_key => $key, patron => $patronid, barcode => $barcode };

	if($noncat) {
		$args->{noncat} = 1;
		$args->{noncat_type} = $nc_type;
	}

	if($precat) {
		$args->{precat} = 1;
		$args->{dummy_title} = "Dummy Title";
		$args->{dummy_author} = "Dummy Author";
	}

	my $start_checkout = time();
	my $resp = osrf_request(
		'open-ils.circ', 
		'open-ils.circ.checkout', $authtoken, $args );
	my $finish = time();

	oils_event_die($resp);

	my $d = $finish - $start_checkout;
	my $dd = $finish - $start;

	printl("Checkout OK:");
	printl("\ttime = $d");
	printl("\ttotal time = $dd");
	printl("\ttitle = " . $resp->{payload}->{record}->title ) unless($noncat or $precat);
	printl("\tdue_date = " . $resp->{payload}->{circ}->due_date ) unless $noncat;
}



sub do_renew {
	my( $patronid, $barcode ) = @_;
	#my $args = { patron => $patronid, barcode => $barcode };
	my $args = { barcode => $barcode };
	my $t = time();
	my $resp = simplereq( 
		CIRC(), 'open-ils.circ.renew', $authtoken, $args );
	my $e = time() - $t;
	oils_event_die($resp);
	printl("Renewal succeeded\nTime: $t");
}

sub do_checkin {
	my $barcode  = shift;
	my $args = { barcode => $barcode };
	my $t = time();
	my $resp = simplereq( 
		CIRC(), 'open-ils.circ.checkin', $authtoken, $args );
	my $e = time() - $t;
	oils_event_die($resp);
	debug($resp) if(ref($resp) eq 'ARRAY');
	printl("Checkin succeeded\nTime: $t");

}

sub do_transit_receive {
	my $barcode = shift;
	my $args = { barcode => $barcode };
	my $t = time();
	my $resp = simplereq( 
		CIRC(), 'open-ils.circ.copy_transit.receive', $authtoken, $args );
	my $e = time() - $t;
	oils_event_die($resp);
	printl("Transit receive succeeded\nTime: $t");
}
