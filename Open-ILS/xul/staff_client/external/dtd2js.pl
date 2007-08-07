#!/usr/bin/perl
#<!ENTITY common.title "Title">
#<!ENTITY common.author "Author">
#<!ENTITY common.subject "Subject">
#<!ENTITY common.series "Series">
#<!ENTITY common.keyword "Keyword">
#<!ENTITY common.type "Type">
#<!ENTITY tricksy.entity 'Some text with "quoted" content'>

print "var entities = {};";
while( $line = <> ) {

	if ($line =~ /<!ENTITY\s+(\S+)\s+((["']).*\3)\s*>\s*$/) {
		print "entities['$1'] = $2;\n";	
	} else {
		chomp $line;
		if ($line) { print STDERR "Problem with: $line\n"; }
	}
}
