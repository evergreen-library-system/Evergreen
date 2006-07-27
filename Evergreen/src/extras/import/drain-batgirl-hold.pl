#!/usr/bin/perl

use strict;
use DBI;

my $dbh = DBI->connect('DBI:mysql:database=reports;host=batgirl.gsu.edu','miker','poopie');

print <<SQL;

DROP TABLE legacy_hold;
CREATE TABLE legacy_hold (available text, status text, notified text, num_of_notices int, cat_key int, call_key int, item_key int, hold_key int, user_key int, hold_date date, hold_range text, pickup_lib text, placing_lib text, owning_lib text, inactive_date text, inactive_reason text, hold_level text);
COPY legacy_hold (available, status, notified, num_of_notices, cat_key, call_key, item_key, hold_key, user_key, hold_date, hold_range, pickup_lib, placing_lib, owning_lib, inactive_date, inactive_reason, hold_level) FROM STDIN;
SQL

warn "going for the data...";

my $sth = $dbh->prepare("select * from HOLD where STATUS = 'ACTIVE'");
$sth->execute;

warn "got it, writing file...";

while (my $cn = $sth->fetchrow_hashref) {
	my @data = map { $$cn{uc($_)} } qw/available status notified num_of_notices cat_key call_key item_key hold_key user_key hold_date hold_range pickup_lib placing_lib owning_lib inactive_date inactive_reason hold_level/;
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

print <<SQL
\\.

UPDATE legacy_hold SET notified = null where notified = '0';
UPDATE legacy_hold SET inactive_date = null where inactive_date = '0';

ALTER TABLE legacy_hold ALTER COLUMN notified TYPE DATE USING notified::DATE;
ALTER TABLE legacy_hold ALTER COLUMN inactive_date TYPE DATE USING inactive_date::DATE;

SQL


