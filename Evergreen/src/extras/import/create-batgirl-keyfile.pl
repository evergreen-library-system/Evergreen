#!/usr/bin/perl

use strict;
use DBI;

my $dbh = DBI->connect('DBI:mysql:database=reports;host=batgirl.gsu.edu','miker','poopie');

warn "going for the data...";

my $sth = $dbh->prepare('select CAT_KEY,FLEX_KEY from CATALOG');
$sth->execute;

warn "got it, writing file...";

while (my $data = $sth->fetchrow_arrayref) {
	print join('|', @$data) . "\n";
}

