#!/usr/bin/perl

use strict;
use DBI;

my $dbh = DBI->connect('DBI:mysql:database=reports;host=batgirl.gsu.edu','miker','poopie');

print <<SQL;

DROP TABLE legacy_item;

CREATE TABLE legacy_item (CAT_1 text,CREATION_DATE date,CAT_2 text,CURRENT_LOCATION text,ITEM_ID text,CAT_KEY int,CALL_KEY int,ITEM_KEY int,PRICE numeric(8,2),ITEM_TYPE text,OWNING_LIBRARY text,SHADOW bool,ITEM_COMMENT text,LAST_IMPORT_DATE date,HOME_LOCATION text);

COPY legacy_item (CAT_1,CREATION_DATE,CAT_2,CURRENT_LOCATION,ITEM_ID,CAT_KEY,CALL_KEY,ITEM_KEY,PRICE,ITEM_TYPE,OWNING_LIBRARY,SHADOW,ITEM_COMMENT,LAST_IMPORT_DATE,HOME_LOCATION) FROM STDIN;
SQL

warn "going for the data...";

my $sth = $dbh->prepare('select * from ITEM');
$sth->execute;

warn "got it, writing file...";

while (my $cn = $sth->fetchrow_hashref) {
	my @data = map { $$cn{$_} } qw/CAT_1 CREATION_DATE CAT_2 CURRENT_LOCATION ITEM_ID CAT_KEY CALL_KEY ITEM_KEY PRICE ITEM_TYPE OWNING_LIBRARY SHADOW ITEM_COMMENT LAST_IMPORT_DATE HOME_LOCATION/;
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
print "CREATE INDEX cat_call_idx ON legacy_item (cat_key,call_key);\n";


