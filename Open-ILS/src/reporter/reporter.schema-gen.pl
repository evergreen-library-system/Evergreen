#!/usr/bin/perl
use strict; use warnings;
use XML::LibXML;
use Date::Manip;

my %chunkmap =
	(	doy => '%j',
		woy => '%U',
		month => '%m',
		year => '%Y',
	);


my $parser = XML::LibXML->new;
my $doc = $parser->parse_file($ARGV[0]);
$parser->process_xincludes($doc);

print "BEGIN;\n\n";
for my $table ($doc->findnodes('/reporter/tables/table')) {
	my $tname = $table->getElementsByTagName('tablename')->string_value;
	
	(my $pkey_name = $tname) =~ s/\./_/gso;
	$pkey_name .= '_pkey';
	warn "$tname\n";

	my (@primary,@other,@indexed);
	for my $field ($table->findnodes('fields/field')) {
		my $fname = $field->getAttribute('name');
		my $fdatatype = $field->getAttribute('create-type') || $field->getAttribute('datatype');
		warn "\t$fname\n";
		
		if ($field->getAttribute('indexed')) {
			my $itype = $field->getAttribute('index-type') || 'BTREE';
			push @indexed, [$fname, $itype];
		}

		if ($field->getAttribute('primary')) {
			push @primary, [$fname, $fdatatype];
		} else {
			push @other, [$fname, $fdatatype];
		}
	}

	warn "\n";
	print	"DROP TABLE $tname CASCADE;\n";
	print	"CREATE TABLE $tname (\n\t".
		join(",\n\t",
			map { join("\t", @$_) } (@primary, @other)
		). ",\n\tCONSTRAINT $pkey_name PRIMARY KEY (".join(", ", map { $$_[0] } @primary).
		")\n);\n";

	for my $i (@indexed) {
		print	"CREATE INDEX \"${tname}_$$i[0]_idx\" ON $tname USING $$i[1] ($$i[0]);\n";
	}
	print "\n";

	if ($table->getAttribute('partition')) {
		my ($part) = $table->getElementsByTagName('partition')->get_nodelist;
		my ($field) = $part->getElementsByTagName('field')->get_nodelist;
		my ($chunk) = $part->getElementsByTagName('chunk')->get_nodelist;
		my ($start) = $part->getElementsByTagName('start')->get_nodelist;
		my ($end) = $part->getElementsByTagName('end')->get_nodelist;

		$field = $field->textContent;
		$chunk = $chunk->textContent;
		$start = UnixDate(ParseDate($start->textContent),$chunkmap{$chunk});
		$end = UnixDate(ParseDate($end->textContent),$chunkmap{$chunk});

		for my $tpart ( $start .. $end ) {
			print	"CREATE TABLE ${tname}_${chunk}_$tpart () INHERITS ($tname);\n";
			print	"ALTER TABLE ${tname}_${chunk}_$tpart\n".
				"\tADD CONSTRAINT \"${tname}_${chunk}_${tpart}_test\"\n".
				"\tCHECK (EXTRACT('$chunk' FROM $field) = $tpart);\n";
			print	"CREATE RULE \"${tname}_${chunk}_${tpart}_ins_rule\" AS\n\tON INSERT TO ".
				"$tname \n\tWHERE EXTRACT('$chunk' FROM NEW.$field) = $tpart ".
				"\n\tDO INSTEAD INSERT INTO ${tname}_${chunk}_$tpart VALUES (NEW.*);\n";
			for my $i (@indexed) {
				print	"CREATE INDEX \"${tname}_${chunk}_${tpart}_$$i[0]_idx\" ".
					"ON ${tname}_${chunk}_$tpart USING $$i[1] ($$i[0]);\n";
			}
			print "\n";
		}
	}
	print "\n";

}
print "COMMIT;\n";
