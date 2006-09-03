#!/usr/bin/perl

use strict;
use DBI;

my $dbh = DBI->connect('DBI:mysql:database=reports;host=batgirl.gsu.edu','miker','poopie');

print <<SQL;

DROP TABLE legacy_bill;
CREATE TABLE legacy_email (user_key int, email text);
COPY legacy_email (user_key, email) FROM STDIN;
SQL

warn "going for the data...";

my $sth = $dbh->prepare('select USER_KEY, EMAIL from USER');
$sth->execute;

warn "got it, writing file...";

while (my $cn = $sth->fetchrow_hashref) {
	my @data = map { $$cn{uc($_)} } qw/user_key email/;
	print join("\t", @data) . "\n";
}

print "\\.\n";


