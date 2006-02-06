#!/usr/bin/perl
use strict;
use lib '../perlmods/';

my $map = {};
eval "
	use lib '../perlmods/';
	use lib '../../../OpenSRF/src/perlmods/';
	use OpenILS::Utils::Fieldmapper;  
";
$map = $Fieldmapper::fieldmap unless ($@);

die $@ if ($@);


if(!$ARGV[0]) {
	print "usage: $0 <source_file>\n";
	exit;
}

warn "Generating fieldmapper-c code...\n";


print $ARGV[0] . "\n";

open(SOURCE, ">$ARGV[0]");

print SOURCE <<C;
#include "fieldmapper_lookup.h"


char * fm_pton(char * class, int pos) {
	if (class == NULL) return NULL;
C


for my $object (keys %$map) {
	my $short_name= $map->{$object}->{hint};
	print SOURCE <<"	C";
	else if (!strcmp(class, "$short_name")) {
		switch (pos) {
	C
	for my $field (keys %{$map->{$object}->{fields}}) {
		my $position = $map->{$object}->{fields}->{$field}->{position};
		print SOURCE <<"		C";
			case $position:
				return strdup("$field");
				break;
		C
	}
	print SOURCE "		}\n";
	print SOURCE "	}\n";
}
print SOURCE <<C;
	return NULL;
}

int isFieldmapper(char* class) {
	if (class == NULL) return 0;
C

for my $object (keys %$map) {
	my $short_name= $map->{$object}->{hint};
	print SOURCE "	else if (!strcmp(class, \"$short_name\")) return 1;\n";
}
print SOURCE <<C;
	return 0;
}

int fm_ntop(char* class, char* field) {
	if (class == NULL) return -1;
C


for my $object (keys %$map) {
	my $short_name= $map->{$object}->{hint};
	print SOURCE "	else if (!strcmp(class, \"$short_name\")) {\n";
	for my $field (keys %{$map->{$object}->{fields}}) {
		my $position = $map->{$object}->{fields}->{$field}->{position};
		print SOURCE "		if (!strcmp(field,\"$field\")) return $position;\n";
	}
	print SOURCE "	}\n"
}

print SOURCE "	return -1;\n}\n";

