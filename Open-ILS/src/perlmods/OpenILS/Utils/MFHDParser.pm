#!/usr/bin/perl -w
use strict;
use Date::Manip;

# Parse MFHD patterns for http://www.loc.gov/marc/holdings/hd853855.html

# Primary goal:
# Expected input: a chunk of MFHD, a start date, and # of issuances to project
# Expected output: a set of issuances projected forward from the start date,
#   with issue/volume/dates/captions conforming to what the MFHD actually says

# The thought had been to use Date::Manip to generate the actual dates for
# each issuance, like:
#
#   # To find the 2nd Tuesday of every month
#   @date = ParseRecur("0:1*2:2:0:0:0",$base,$start,$stop);

# Secondary goal: generate automatic summary holdings
#   (a la http://www.loc.gov/marc/holdings/hd863865.html)

# Compressability comes from first indicator
sub parse_compressability {
	my $c = shift || return undef;

	my %compressability = (
		'0' => 'Cannot compress or expand',
		'1' => 'Can compress but cannot expand',
		'2' => 'Can compress or expand',
		'3' => 'Unknown',
		'#' => 'Undefined'
	);

	if (exists $compressability{$c}) {
		return $compressability{$c};
	}
	# 'Unknown compressability indicator - expected one of (0,1,2,3,#)';
	return undef;
}

# Caption evaluation comes from second indicator
sub caption_evaluation {
	my $ce = shift || return undef;

	my %caption_evaluation = (
		'0' => 'Captions verified; all levels present',
		'1' => 'Captions verified; all levels may not be present',
		'2' => 'Captions unverified; all levels present',
		'3' => 'Captions unverified; all levels may not be present',
		'#' => 'Undefined',
	);

	if (exists $caption_evaluation{$ce}) {
		return $caption_evaluation{$ce};
	}
	# 'Unknown caption evaluation indicator - expected one of (0,1,2,3,#)';
	return undef;
}

# Start with frequency ($w)
# then overlay number of pieces of issuance ($p)
# then regularity pattern ($y)
my %frequency = (
	'a' => 'annual',
	'b' => 'bimonthly',
	'c' => 'semiweekly',
	'd' => 'daily',
	'e' => 'biweekly',
	'f' => 'semiannual',
	'g' => 'biennial',
	'h' => 'triennial',
	'i' => 'three times a week',
	'j' => 'three times a month',
	'k' => 'continuously updated',
	'm' => 'monthly',
	'q' => 'quarterly',
	's' => 'semimonthly',
	't' => 'three times a year',
	'w' => 'weekly',
	'x' => 'completely irregular',
);

sub parse_frequency {
	my $freq = shift || return undef;

	if ($freq =~ m/^\d+$/) {
		return "$freq times a year";
	} elsif (exists $frequency{$freq}) {
		return $frequency{$freq};
	}
	# unrecognized frequency specification
	return undef;
}

# $x - Point at which the highest level increments or changes
# Interpretation of two-digit numbers in the 01-12 range depends on the publishing frequency
# More than one change can be passed in the subfield and are delimited by commas
sub chronology_change {
	my $chronology_change = shift || return undef;
	my @c_changes = split /,/, $chronology_change;
	foreach my $change (@c_changes) {
		if ($change == 21) {
			
		}
	}
	return undef;
}

# Publication code : first character in regularity pattern ($y)
sub parse_publication_code {
	my $c = shift || return undef;

	my %publication_code = (
		'c' => 'combined',
		'o' => 'omitted',
		'p' => 'published',
		'#' => 'undefined',
	);

	if (exists $publication_code{$c}) {
		return $publication_code{$c};
	}
	return undef;
}

# Chronology code : part of regularity pattern ($y)
sub parse_chronology_code {
	my $c = shift || return undef;

	my %chronology_code = (
		'd' => 'Day',
		'm' => 'Month',
		's' => 'Season',
		'w' => 'Week',
		'y' => 'Year',
		'e' => 'Enumeration',
	);

	if (exists $chronology_code{$c}) {
		return $chronology_code{$c};
	}
	return undef;
}

sub parse_regularity_pattern {
	my $pattern = shift;
	my ($pc, $cc, $cd) = $pattern =~ m{^(\w)(\w)(.+)$};
	
	my $pub_code = parse_publication_code($pc);
	my $chron_code = parse_chronology_code($cc);
	my $chron_def = parse_chronology_definition($cd);
	
	return ($pub_code, $chron_code, $chron_def);
}

sub parse_chronology_definition {
	my $chron_def = shift || return undef;
	# Well, this is where it starts to get hard, doesn't it?
	return $chron_def;
}

print parse_regularity_pattern("cddd");
print "\n";
print parse_regularity_pattern("38dd");
print "\n";

1;

# :vim:noet:ts=4:sw=4:
