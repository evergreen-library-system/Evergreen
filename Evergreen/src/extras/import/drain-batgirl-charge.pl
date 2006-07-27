#!/usr/bin/perl

use strict;
use DBI;

my $dbh = DBI->connect('DBI:mysql:database=reports;host=batgirl.gsu.edu','miker','poopie');

print <<SQL;

DROP TABLE legacy_charge;
CREATE TABLE legacy_charge (charge_date text, due_date text, renewal_date text, charge_key1 int, charge_key2 int, charge_key3 int, charge_key4 int, user_key int, overdue bool, library text, claim_return_date text);
COPY legacy_charge (charge_date, due_date, renewal_date, charge_key1, charge_key2, charge_key3, charge_key4, user_key, overdue, library, claim_return_date) FROM STDIN;
SQL

warn "going for the data...";

my $sth = $dbh->prepare('select * from CHARGE');
$sth->execute;

warn "got it, writing file...";

while (my $cn = $sth->fetchrow_hashref) {
	my @data = map { $$cn{uc($_)} } qw/charge_date due_date renewal_date charge_key1 charge_key2 charge_key3 charge_key4 user_key overdue library claim_return_date/;
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


