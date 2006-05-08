#!/usr/bin/perl
use strict; use warnings;
use Data::Dumper; 
use OpenILS::Utils::Fieldmapper;  

my $map = $Fieldmapper::fieldmap;

# if a true value is provided, we generate the web (light) version of the fieldmapper
my $web = $ARGV[0];
if(!$web) { $web = ""; }


my @web_core = qw/ 
	aou au perm_ex ex aout 
	mvr ccs ahr aua ac actscecm cbreb acpl 
	cbrebi acpn acp acnn acn bren asc asce 
	clfm cifm citm cam ahtc
	asv asva asvr asvq 
	circ ccs ahn bre
	crcd crmf crrf mbts aoc aus 
	mous mobts mb ancc cnct
	/;

my @reports = qw/ perm_ex ex ao aou aout /;


print "var _c = {};\n";

for my $object (keys %$map) {

	my $hint = $map->{$object}->{hint};

	if($web eq "web_core") {
		next unless (grep { $_ eq $hint } @web_core );
	}

	if($web eq "reports") {
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

