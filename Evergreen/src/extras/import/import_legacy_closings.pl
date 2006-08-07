#!/usr/bin/perl

use strict;
use warnings;

print "CREATE TEMP TABLE legacy_closing (lib text, cstart int, cend int, reason text);\n";
print "COPY legacy_closing (lib,cstart,cend,reason) FROM STDIN;\n";

while (<>) {
	my ($lib,$s,$e) = split '\|';
	my @start = split ' ', $s;
	my @end = split ' ', $e;

	for (my $x = 0; $x < @start; $x++) {
		print "$lib\t$start[$x]\t$end[$x]\tLegacy Closing\n";
	}
}

print "\\.\n";

print <<SQL;

DELETE FROM actor.org_unit_closed;

CREATE TEMP VIEW legacy_closing_view AS
	SELECT	au.id AS org_unit,
		('epoch'::TIMESTAMPTZ + (l.cstart || ' seconds')::INTERVAL)::DATE AS close_start,
		('epoch'::TIMESTAMPTZ + (l.cend || ' seconds')::INTERVAL + '1 day'::INTERVAL)::DATE - '1 second'::INTERVAL AS close_end,
		l.reason AS reason
	  FROM	legacy_closing l
		JOIN actor.org_unit au ON (au.shortname = l.lib);

INSERT INTO actor.org_unit_closed (org_unit, close_start, close_end, reason)
	SELECT * from legacy_closing_view;

INSERT INTO actor.org_unit_closed (org_unit, close_start, close_end, reason)
	SELECT	au.id AS org_unit,
		'2006-09-02' AS close_start,
		'2006-09-05'::DATE - '1 second'::INTERVAL AS close_end,
		'Evergreen Migration' AS reason
	FROM	actor.org_unit au;

SQL

