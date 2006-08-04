#!/usr/bin/perl

use strict;
use DBI;

my $dbh = DBI->connect('DBI:mysql:database=reports;host=batgirl.gsu.edu','miker','poopie');

print <<SQL;

DROP TABLE legacy_bill;
CREATE TABLE legacy_bill (bill_amount int, balance int, bill_date date, cat_key int, call_key int, item_key int, user_key int, paid bool, reason text, library text, bill_key1 int, bill_key2 int);
COPY legacy_bill (bill_amount, balance, bill_date, cat_key, call_key, item_key, user_key, paid, reason, library, bill_key1, bill_key2) FROM STDIN;
SQL

warn "going for the data...";

my $sth = $dbh->prepare('select * from BILL');
$sth->execute;

warn "got it, writing file...";

while (my $cn = $sth->fetchrow_hashref) {
	my @data = map { $$cn{uc($_)} } qw/bill_amount balance bill_date cat_key call_key item_key user_key paid reason library bill_key1 bill_key2/;
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
print "CREATE INDEX lb_bk1_idx ON legacy_bill (bill_key1);\n";
print "CREATE INDEX lb_usr_idx ON legacy_bill (user_key);\n";


