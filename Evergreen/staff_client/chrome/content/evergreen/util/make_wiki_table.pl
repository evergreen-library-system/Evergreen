#!/usr/bin/perl

print "^ file ^ functions ^\n";
while ($f = pop @ARGV) {
	print("|" . $f . "|");
	open FILE, $f;
	while ($line = <FILE>) {
		if ($line =~ /^function\s+(\w+)\s*(\(.*\))/) {
			print $1 . $2 . '\\' . '\\' . ' ';
		}
	}
	print "|\n";
	close FILE;
}
