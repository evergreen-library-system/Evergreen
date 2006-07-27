#!/usr/bin/perl

use strict;
use DBI;

my $dbh = DBI->connect('DBI:mysql:database=reports;host=batgirl.gsu.edu','miker','poopie');

print <<SQL;

DROP TABLE legacy_transit;
CREATE TABLE legacy_transit (destination_lib text, owning_lib text, starting_lib text, transit_date timestamptz, transit_reason text, cat_key int, call_key int, item_key int, hold_key int);
COPY legacy_transit (destination_lib, owning_lib, starting_lib, transit_date, transit_reason, cat_key, call_key, item_key, hold_key) FROM STDIN;
SQL

warn "going for the data...";

my $sth = $dbh->prepare("select CAT_KEY, CALL_KEY, ITEM_KEY, HOLD_KEY, DESTINATION_LIB, OWNING_LIB, STARTING_LIB, concat(substring(TRANSIT_DATE,1,8),'T',substring(TRANSIT_DATE,9,4)) AS TRANSIT_DATE, TRANSIT_REASON from INTRANSIT");
$sth->execute;

warn "got it, writing file...";

while (my $cn = $sth->fetchrow_hashref) {
	my @data = map { $$cn{uc($_)} } qw/destination_lib owning_lib starting_lib transit_date transit_reason cat_key call_key item_key hold_key/;
	for (@data) {
		if (defined($_)) {
			s/\\/\\\\/go;
			s/\t/ /go;
		} else {
			$_ = '\N';
		}
	}
	print join("\t", @data) . "\n";
}

print "\\.\n";


