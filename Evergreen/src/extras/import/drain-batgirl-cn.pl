#!/usr/bin/perl

use strict;
use DBI;

my $dbh = DBI->connect('DBI:mysql:database=reports;host=batgirl.gsu.edu','miker','poopie');

print <<SQL;

DROP TABLE legacy_callnum;
CREATE TABLE legacy_callnum (call_num text, cat_key int, call_key int, shadow bool);
COPY legacy_callnum (call_num, cat_key, call_key, shadow) FROM STDIN;
SQL

warn "going for the data...";

my $sth = $dbh->prepare('select * from CALLNUM');
$sth->execute;

warn "got it, writing file...";

while (my $cn = $sth->fetchrow_hashref) {
	my @data = map { $$cn{$_} } qw/CALL_NUM CAT_KEY CALL_KEY SHADOW/;
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


