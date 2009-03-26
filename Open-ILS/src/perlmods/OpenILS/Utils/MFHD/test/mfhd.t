#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;
use Test::More 'no_plan';

use MARC::Record;
use OpenILS::Utils::MFHD;

my $testno = 0;

sub right_answer {
    my $holding = shift;
    my $answer = {};

    foreach my $subfield (split(/\|/, $holding->subfield('x'))) {
	next unless $subfield;

	my ($key, $val) = unpack('aa*', $subfield);
	$answer->{$key} = $val;
    }

    return $answer;
}

sub load_MARC_rec {
    my $rec;
    my $line;
    my $marc = undef;

    # skim to beginning of record (a non-blank, non comment line)
    while ($line = <DATA>) {
	chomp $line;
	last if (!($line =~ /^\s*$/) && !($line =~ /^#/));
    }

    return undef if !$line;

    $testno += 1;
    $marc = MARC::Record->new();
    carp('No record created!') unless $marc;

    $marc->leader('01119nas  2200313 a 4500');
    $marc->append_fields(MARC::Field->new('008', '970701c18439999enkwr p       0   a0eng  '));
    $marc->append_fields(MARC::Field->new('035', '', '',
					  a => sprintf('%04d', $testno)));

    while ($line) {
	next if $line =~ /^#/;	# allow embedded comments

	return $marc if $line =~ /^\s*$/;

	my ($fieldno, $indicators, $rest) = split(/ /, $line, 3);
	my @inds = unpack('cc', $indicators);
	my $field = MARC::Field->new($fieldno, $inds[0], $inds[1],
				     a => 'scratch');

	foreach my $subfield (split(/\$/, $rest)) {
	    next unless $subfield;

	    my ($key, $val) = unpack('aa*', $subfield);
	    $field->update($key => $val);
	}

	$marc->append_fields($field);

	$line = <DATA>;
	chomp $line if $line;
    }
    return $marc;
}

my $rec;

while ($rec = load_MARC_rec) {
    $rec = MFHD->new($rec);

    foreach my $cap_id ($rec->captions('853')) {
	my @holdings = $rec->holdings('863', $cap_id);

	next unless scalar @holdings;
	foreach my $field (@holdings) {
	  TODO: {
		local $TODO = "unimplemented"
		  if ($field->subfield('z') =~ /^TODO/);
		is_deeply($field->next, right_answer($field),
			  $field->subfield('8') . ': ' . $field->subfield('z'));
	    }
	}
    }
}

1;

__END__
#
# load record, then loop over 863 fields calling next().
#

245 00 $aMonthly, issue no. restarts, calendar change: Jan
853 20 $81$av.$bno.$u12$vr$i(year)$j(month)$wm$x01
863 41 $81.1$a1$b6$i1990$j06$x|a1|b7|i1990|j07$zMiddle of year, middle of vol.
863 41 $81.2$a1$b11$i1990$j11$x|a1|b12|i1990|j12$zEnd of year, end of vol.
863 41 $81.3$a1$b12$i1990$j12$x|a2|b1|i1991|j01$zWrap at end of year/vol.

245 00 $aMonthly, issue no. restarts, calendar change: Mar
853 20 $82$av.$bno.$u12$vr$i(year)$j(month)$wm$x03
863 41 $82.1$a1$b6$i1990$j08$x|a1|b7|i1990|j09$zMiddle of year, middle of vol.
863 41 $82.2$a1$b10$i1990$j12$x|a1|b11|i1991|j01$zEnd of year, middle of vol.
863 41 $82.3$a1$b11$i1991$j01$x|a1|b12|i1991|j02$zMiddle of year, end of vol.
863 41 $82.3$a1$b12$i1991$j02$x|a2|b1|i1991|j03$zWrap vol in mid-year

245 00 $aMonthly, issue no. continuous, calendar change: Jan
853 20 $83$av.$bno.$u12$vc$i(year)$j(month)$wm$x01
863 41 $83.1$a1$b6$i1990$j06$x|a1|b7|i1990|j07$zMiddle of year, middle of vol.
863 41 $83.2$a1$b11$i1990$j11$x|a1|b12|i1990|j12$zEnd of year, end of vol.
863 41 $83.3$a1$b12$i1990$j12$x|a2|b13|i1991|j01$zwrap vol @ end of year

245 00 $aMonthly, issue no. continuous, calendar change: Mar
853 20 $84$av.$bno.$u12$vc$i(year)$j(month)$wm$x03
863 41 $84.1$a1$b6$i1990$j08$x|a1|b7|i1990|j09$zMiddle of year, middle of vol.
863 41 $84.2$a1$b10$i1990$j12$x|a1|b11|i1991|j01$zEnd of year, middle of vol.
863 41 $84.3$a1$b11$i1991$j01$x|a1|b12|i1991|j02$zMiddle of year, end of vol.
863 41 $84.4$a1$b12$i1991$j02$x|a2|b13|i1991|j03$zwrap vol mid-year

245 00 $aMonthly, issue no. restarts, Calendar change: Jan, Jul
853 20 $85$av.$bno.$u6$vr$i(year)$j(month)$wm$x01,07
863 41 $85.1$a1$b5$i1990$j05$x|a1|b6|i1990|j06$zMiddle of year, near end of vol.
863 41 $85.2$a1$b6$i1990$j06$x|a2|b1|i1990|j07$zMiddle of year, end of vol.
863 41 $85.3$a2$b6$i1990$j12$x|a3|b1|i1991|j01$zEnd of year, end of vol.

245 00 $aMonthly, issue no. continuous, Calendar change: Jan, Jul
853 20 $86$av.$bno.$u6$vc$i(year)$j(month)$wm$x01,07
863 41 $86.1$a1$b5$i1990$j05$x|a1|b6|i1990|j06$zMiddle of year, end of vol.
863 41 $86.2$a1$b6$i1990$j06$x|a2|b7|i1990|j07$zMiddle of year, end of vol.
863 41 $86.3$a2$b12$i1990$j12$x|a3|b13|i1991|j01$zEnd of year, end of vol.

245 00 $aMonthly, issue no. restarts, Calendar change: Jan, Combined issue: Jan/Feb
853 20 $87$av.$bno.$u11$vr$i(year)$j(month)$wm$x01$ycm01/02
863 41 $87.1$a1$b11$i1990$j12$x|a2|b1|i1991|j01/02$z End of year, end of vol.
863 41 $87.2$a2$b1$i1991$j01/02$x|a2|b2|i1991|j03$z Beginning of year, beginning of vol.

245 00 $aMonthly, iss no. restarts, Calendar change: Jan, Combined iss: Nov/Dec
853 20 $88$av.$bno.$u11$vr$i(year)$j(month)$wm$x01$ycm11/12
863 41 $88.1$a1$b10$i1990$j10$x|a1|b11|i1990|j11/12$z end of year, end of vol.
863 41 $88.2$a1$b11$i1990$j11/12$x|a2|b1|i1991|j01$z wrap vol at year end

245 00 $aMonthly, iss no. restarts, Cal. change: Jan, Combined iss: Jan/Feb, Nov/Dec
853 20 $89$av.$bno.$u10$vr$i(year)$j(month)$wm$x01$ycm01/02,11/12
863 41 $89.1$a1$b1$i1990$j01/02$x|a1|b2|i1990|j03$z beg. of year, beg. of vol.
863 41 $89.2$a1$b9$i1990$j10$x|a1|b10|i1990|j11/12$z end of year, end of vol.
863 41 $89.3$a1$b10$i1990$j11/12$x|a2|b1|i1991|j01/02$z zwrap vol at year end

245 00 $aMonthly, iss no. restarts, Cal. change: Jan, Combined iss: May/Jun, Jul/Aug
853 20 $810$av.$bno.$u10$vr$i(year)$j(month)$wm$x01$ycm05/06,07/08
863 41 $810.1$a1$b4$i1990$j04$x|a1|b5|i1990|j05/06$z next iss is combined.
863 41 $810.2$a1$b5$i1990$j05/06$x|a1|b6|i1990|j07/08$z combined to combined
863 41 $810.3$a1$b6$i1990$j07/08$x|a1|b7|i1990|j09$z combined to reg

245 00 $aMonthly, issue no. restarts, Calendar change: Jan, Combined issue: 1/2 Jan/Feb 
853 20 $811$av.$bno.$u12$vr$i(year)$j(month)$wm$x01$ycm01/02$yce21/2
863 41 $811.1$a1$b12$i1990$j12$x|a2|b1/2|i1991|j01/02$zTODO new vol at year end regular iss to combined
863 41 $811.2$a2$b1/2$i1991$j01/02$x|a2|b3|i1991|j03$zTODO combined iss to regular

245 00 $aMonthly, iss no. restarts, Calendar change: Jan, Combined iss: 11/12 Nov/Dec
853 20 $812$av.$bno.$u12$vr$i(year)$j(month)$wm$x01$ycm11/12$yce211/12
863 41 $812.1$a1$b10$i1990$j10$x|a1|b11/12|i1990|j11/12$zTODO regular to combined iss
863 41 $812.2$a1$b11/12$i1990$j11/12$x|a2|b1|i1991|j01$zTODO end of vol: combined to regular issue

245 00 $aMonthly, iss no. restarts, Cal. change: Jan, Combined iss: 1/2 Jan/Feb, 11/12 Nov/Dec
853 20 $813$av.$bno.$u12$vr$i(year)$j(month)$wm$x01$ycm01/02,11/12$yce21/2,11/12
863 41 $813.1$a1$b10$i1990$j10$x|a1|b11/12|i1990|j11/12$zTODO end of vol regular to combined iss
863 41 $813.2$a1$b11/12$i1990$j11/12$x|a2|b1/2|i1991|j01/02$zTODO wrap at volume end: combined to combined
863 41 $813.3$a2$b1/2$i1991$j01/02$x|a2|b3|i1991|j03$zTODO beginning of vol: combined to regular

245 00 $aMonthly, iss no. restarts, Cal. change: Jan, Combined iss: 5/6 May/Jun, 7/8 Jul/Aug 
853 20 $814$av.$bno.$u12$vr$i(year)$j(month)$wm$x01$ycm05/06,07/08$yce25/6,7/8
863 41 $814.1$a1$b4$i1990$j04$x|a1|b5/6|i1990|j05/06$zTODO mid year: reg to combined
863 41 $814.2$a1$b5/6$i1990$j05/06$x|a1|b7/8|i1990|j07/08$zTODO mid year: combined to combined
863 41 $814.3$a1$b7/8$i1990$j07/08$x|a1|b9|i1990|j09$zTODO mid year: combined to regular

245 00 $aMonthly, iss no. restarts, Cal change: Jan, July issue omitted
853 20 $815$av.$bno.$u11$vr$i(year)$j(month)$wm$x01$yom07

245 00 $aQuarterly, chronology in enumeration fields
853 20 $816$a(year)$b(season)$wq$yps21,22,23,24
863 41 $816.1$a2007$b21$x|a2007|b22$zSimple case: quarterly in mid-volume
863 41 $816.2$a2007$b24$x|a2008|b21$zRoll over to new year

245 00 $aFour issues a year, chronology in enum fields, combined Sum/Fall issue
853 20 $817$a(year)$b(season)$wq$ycs22/23
863 41 $817.1$a2007$b21$x|a2007|b22/23$zSpring to Summer/Fall
863 41 $817.2$a2007$b22/23$x|a2007|b24$zSummer/Fall to Winter
