#!/usr/bin/perl

use strict;
use warnings;

print "CREATE TEMP TABLE legacy_hoo (lib text, d0o time, d0c time, d1o time, d1c time, d2o time, d2c time, d3o time, d3c time, d4o time, d4c time, d5o time, d5c time, d6o time, d6c time);\n";
print "COPY legacy_hoo (lib,d0o,d0c,d1o,d1c,d2o,d2c,d3o,d3c,d4o,d4c,d5o,d5c,d6o,d6c) FROM STDIN;\n";

while (<>) {
	my ($lib,@dow) = split '\|';
	@dow = @dow[1,2,3,4,5,6,0];
	
	print "$lib";
	for my $c (@dow) {
		if ($c == 1) {
			print "\t00:00:00\t00:00:00";
		} else {
			print "\t09:00:00\t17:00:00";
		}
	}
	print "\n";
}

print "\\.\n";

print <<SQL;

DELETE FROM actor.hours_of_operation;

CREATE TEMP VIEW legacy_hoo_view AS
	SELECT	au.id AS id, l.d0o, l.d0c, l.d1o, l.d1c, l.d2o, l.d2c, l.d3o, l.d3c, l.d4o, l.d4c, l.d5o, l.d5c, l.d6o, l.d6c
	  FROM	legacy_hoo l
		JOIN actor.org_unit au ON (au.shortname = l.lib);

INSERT INTO actor.hours_of_operation (id, dow_0_open, dow_0_close, dow_1_open, dow_1_close, dow_2_open, dow_2_close, dow_3_open, dow_3_close, dow_4_open, dow_4_close, dow_5_open, dow_5_close, dow_6_open, dow_6_close)
	SELECT * from legacy_hoo_view;

SQL

