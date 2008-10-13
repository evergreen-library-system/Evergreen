#!/usr/bin/perl

use strict;
use Data::Dumper;

while (<STDIN>) {
	chomp;
	my @parts = split '\|';
#	@parts = @parts[
#			PRIV_EXP_DATE	CREATION_DATE	PRIV_GRANT_DATE	DELINQ_STATUS
#			3,		4,		5,		7,
#
#			USER_BARCODE	PROFILE		COUNTY(CAT1)	BIRTH_YEAR
#			10,		12,		13,	 	15,
#
#			HOME_LIB	ZIP		ALTID		ADDRESS1
#			16,		17,		18,		19,
#			
#			ADDRESS2	PHONE		EMAIL		NAME
#			20,		21,		22,		23,
#			
#			NUM_CLAIMED_RETURNED
#			24
#	];

	my $addr = parse_addr(@parts[19,20]);

	$$addr{county} = $parts[13];
	$$addr{zip} ||= $parts[17];

	print Dumper($addr);
}

sub parse_addr {
	my $addr1 = shift;
	my $addr2 = shift;

	$addr1 =~ s/^\s*(.+)\s*$/$1/gso;
	$addr2 =~ s/^\s*(.+)\s*$/$1/gso;

	$addr1 =~ s/\s+/ /gso;
	$addr2 =~ s/\s+/ /gso;

	my %hash;

	if ($addr1 =~ /^(\d+\s+[^,]+)/o) {
		$hash{address1} = $1;
		if ($addr1 =~ /,\s+(.+)$/o) {
			my $a2 = $1;
			if ($a2 =~ /^(\w{2})\.?\s+(\d+)$/o) {
				$hash{state} = uc($1);
				$hash{zip} = $2;
			} elsif (lc($a2) !~ /^(?:s\.?e\.?|s\.?w\.?|n\.?e\.?|n\.?w\.?|south|north|east|west|n\.?|s\.?|e\.?|w\.?)$/) {
				$hash{address2} = $a2;
			} else {
				$hash{address1} .= " $a2";
			}
		}
	} else {
		$hash{address1} = $addr1;
	}

	if ($addr2 =~ /^([^,]+),\s*(\w{2}).*\s+(\w+)$/o) {
		$hash{city} = $1;
		$hash{state} = uc($2);
		$hash{zip} = $3;
	}

	return \%hash;
}
