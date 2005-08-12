#!/usr/bin/perl
use strict; use warnings;
use Data::Dumper; 
use OpenILS::Utils::Fieldmapper;  

my $map = $Fieldmapper::fieldmap;

# if a true value is provided, we generate the web (light) version of the fieldmapper
my $web = $ARGV[0];
if(!$web) { $web = ""; }

# List of classes needed by the opac
my @web_hints = qw/asv asva asvr asvq 
		circ acp acpl acn ccs ahn ahr aua ac 
		actscecm crcd crmf crrf mus mbts aoc aus/;

my @web_core = qw/ aou au perm_ex ex aout mvr /;


print "var _c = {};\n";

for my $object (keys %$map) {

	if($web eq "web") {
		my $hint = $map->{$object}->{hint};
		next unless (grep { $_ eq $hint } @web_hints );
	}

	if($web eq "web_core") {
		my $hint = $map->{$object}->{hint};
		next unless (grep { $_ eq $hint } @web_core );
	}

	my $short_name = $map->{$object}->{hint};

	my @fields;
	for my $field (keys %{$map->{$object}->{fields}}) {
		my $position = $map->{$object}->{fields}->{$field}->{position};
		$fields[$position] = $field;
	}

	print "_c[\"$short_name\"] = [";
	for my $f (@fields) { 
		if( $f ne "isnew" and $f ne "ischanged" and $f ne "isdeleted" ) {
			print "\"$f\","; 
		}
	}
	print "];\n";


}

print "fmclasses = _c;\n";

