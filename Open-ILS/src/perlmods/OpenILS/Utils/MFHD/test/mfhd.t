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
	my $field;
	my @subfields;

	@subfields = ();
	foreach my $subfield (split(/\$/, $rest)) {
	    next unless $subfield;

	    my ($key, $val) = unpack('aa*', $subfield);
	    push @subfields, $key, $val;
	}

	$field = MARC::Field->new($fieldno, $inds[0], $inds[1],
				  a => 'scratch', @subfields);

	$marc->append_fields($field);

	$line = <DATA>;
	chomp $line if $line;
    }
    return $marc;
}

my $rec;
my @captions;

while ($rec = load_MARC_rec) {
    $rec = MFHD->new($rec);

    foreach my $cap  (sort {$a->tag <=> $b->tag} $rec->field('85.')) {
	my $htag;
	my @holdings;

	($htag = $cap->tag) =~ s/^85/86/;
	@holdings = $rec->holdings($htag, $cap->subfield('8'));

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
863 41 $811.1$a1$b12$i1990$j12$x|a2|b1/2|i1991|j01/02$znew vol at year end regular iss to combined
863 41 $811.2$a2$b1/2$i1991$j01/02$x|a2|b3|i1991|j03$zcombined iss to regular

245 00 $aMonthly, iss no. restarts, Calendar change: Jan, Combined iss: 11/12 Nov/Dec
853 20 $812$av.$bno.$u12$vr$i(year)$j(month)$wm$x01$ycm11/12$yce211/12
863 41 $812.1$a1$b10$i1990$j10$x|a1|b11/12|i1990|j11/12$zregular to combined iss
863 41 $812.2$a1$b11/12$i1990$j11/12$x|a2|b1|i1991|j01$zend of vol: combined to regular issue

245 00 $aMonthly, iss no. restarts, Cal. change: Jan, Combined iss: 1/2 Jan/Feb, 11/12 Nov/Dec
853 20 $813$av.$bno.$u12$vr$i(year)$j(month)$wm$x01$ycm01/02,11/12$yce21/2,11/12
863 41 $813.1$a1$b10$i1990$j10$x|a1|b11/12|i1990|j11/12$zend of vol regular to combined iss
863 41 $813.2$a1$b11/12$i1990$j11/12$x|a2|b1/2|i1991|j01/02$zwrap at volume end: combined to combined
863 41 $813.3$a2$b1/2$i1991$j01/02$x|a2|b3|i1991|j03$zbeginning of vol: combined to regular

245 00 $aMonthly, iss no. restarts, Cal. change: Jan, Combined iss: 5/6 May/Jun, 7/8 Jul/Aug 
853 20 $814$av.$bno.$u12$vr$i(year)$j(month)$wm$x01$ycm05/06,07/08$yce25/6,7/8
863 41 $814.1$a1$b4$i1990$j04$x|a1|b5/6|i1990|j05/06$zmid year: reg to combined
863 41 $814.2$a1$b5/6$i1990$j05/06$x|a1|b7/8|i1990|j07/08$zmid year: combined to combined
863 41 $814.3$a1$b7/8$i1990$j07/08$x|a1|b9|i1990|j09$zmid year: combined to regular

245 00 $aMonthly, iss no. restarts, Cal change: Jan, July issue omitted
853 20 $815$av.$bno.$u11$vr$i(year)$j(month)$wm$x01$yom07
863 41 $815.1$a1$b6$i1990$j06$x|a1|b7|i1990|j08$zskip july issue

245 00 $aQuarterly, chronology in enumeration fields
853 20 $816$a(year)$b(season)$wq$yps21,22,23,24
863 41 $816.1$a2007$b21$x|a2007|b22$zChron in enum: simple case: quarterly in mid-volume
863 41 $816.2$a2007$b24$x|a2008|b21$zChron in enum: Roll over to new year

245 00 $aFour issues a year, chronology in enum fields, combined Sum/Fall issue
853 20 $817$a(year)$b(season)$wq$ycs22/23
863 41 $817.1$a2007$b21$x|a2007|b22/23$zChron in enum: Spring to Summer/Fall
863 41 $817.2$a2007$b22/23$x|a2007|b24$zChron in enum: Summer/Fall to Winter

245 00 $aLibrary Journal: 20 times a year, semimonthly except Jan, Jul, Aug, Dec
853 20 $818$av.$bno.$u20$vr$i(year)$j(month)$k(day)$ws$x01$ypd01,15$yod0115,0715,0815,1215
863 41 $818.1$a132$b20$i2007$j12$k1$x|a133|b1|i2008|j01|k01$zSkipping over missed date to beginning of next year/volume.
863 41 $818.2$a133$b1$i2008$j01$k01$x|a133|b2|i2008|j02|k01$zSkipping over missed date at beginning of year
863 41 $818.3$a133$b2$i2008$j02$k01$x|a133|b3|i2008|j02|k15$zPublished semimonthly, going from 1st to 15th
863 41 $818.4$a133$b3$i2008$j02$k15$x|a133|b4|i2008|j03|k01$zPublished semimonthly, going from 15th to 1st

245 00 $aBimonthly: Feb, Apr, June, Aug, Oct, Dec
853 20 $819$av.$bno.$u6$vr$i(year)$j(month)$wb$x02$ypm02,04,06,08,10,12
863 41 $819.1$a1$b3$i1990$j06$x|a1|b4|i1990|j08$zMiddle of year, middle of vol.
863 41 $819.2$a1$b5$i1990$j10$x|a1|b6|i1990|j12$zEnd of year, end of vol.
863 41 $819.3$a1$b6$i1990$j12$x|a2|b1|i1991|j02$zWrap at end of year/vol.

245 00 $aBimonthly, published 5 times with combined summer issue: Feb, Apr, June/Aug, Oct, Dec
853 20 $820$av.$bno.$u5$vr$i(year)$j(month)$wb$x02$ypm02,04,10,12$ycm06/08
863 41 $820.1$a1$b2$i1990$j04$x|a1|b3|i1990|j06/08$zFrom Apr to Jun/Aug
863 41 $820.2$a1$b3$i1990$j06/08$x|a1|b4|i1990|j10$zFrom Jun/Aug to Oct
863 41 $820.3$a1$b5$i1990$j12$x|a2|b1|i1991|j02$zWrap at end of year/vol.

245 00 $aEconomist: pub. w on Sa, except combined iss on last two weeks of year
853 20 $821$av.$bno.$u12$vc$i(year)$j(month)$k(day)$ww$x01,04,07,10$ypdsa$yow1299
863 41 $821.1$a100$b1200$i2008$j12$k06$x|a100|b1201|i2008|j12|k13$zwithin vol.
863 41 $821.2$a100$b1201$i2008$j12$k13$x|a100|b1202|i2008|j12|k20$zwithin vol. combined iss.
863 41 $821.3$a100$b1202$i2008$j12$k20$x|a101|b1203|i2009|j01|k03$zvolume change over omitted iss.

245 00 $aMFHD example: monthly, pub. 2nd Wed of month except in April: 2nd Thu; May:1st Wednesday.
853 20 $822$av.$bno.$u12$vr$i(year)$j(month)$k(day)$wm$x01$ypw02we$ypw0402th,0501we$yow0402we,0502we
863 41 $822.1$a1$b2$i2009$j02$k11$x|a1|b3|i2009|j03|k11$zpublished on 2nd Wed in Mar
863 41 $822.2$a1$b3$i2009$j03$k11$x|a1|b4|i2009|j04|k09$zpublished on 2nd Thu in Apr
863 41 $822.3$a1$b4$i2009$j04$k09$x|a1|b5|i2009|j05|k06$zpublished on 1st Wed in May
863 41 $822.4$a2$b4$i2013$j04$k11$x|a2|b5|i2013|j05|k01$zpublished on Wed May 1st

245 00 $aMFHD example: pub. every Mon, Thu, except on New Years, July 4, Labor Day, Thanksgiving, Christmas
853 20 $823$av.$bno.$uvar$vr$i(year)$j(month)$k(day)$wc$x07$ypw00mo,00th$yod0101,0704,1225$yow0901mo,1104th
863 41 $823.1$a1$b100$i2009$j02$k02$x|a1|b101|i2009|j02|k05$znormal: Mon to Thu
863 41 $823.2$a1$b101$i2009$j02$k05$x|a1|b102|i2009|j02|k09$znormal: Thu to Mon
863 41 $823.3$a1$b150$i2009$j06$k29$x|a2|b151|i2009|j07|k02$znormal: calendar change
863 41 $823.4$a2$b180$i2009$j09$k03$x|a2|b181|i2009|j09|k10$zSkip Labor Day
863 41 $823.5$a2$b200$i2009$j11$k23$x|a2|b201|i2009|j11|k30$zSkip (US) Thanksgiving

#
# According to the specification and the examples at
# http://www.loc.gov/marc/chrono_patterns.html it is possible to
# document a combined issue in a $yp publication regularity definition,
# like this: $yps21,22/23,24
245 00 $aCombined date documented in publication pattern rather than combined pattern
853 20 $824$av.$bno.$u3$vr$i(year)$j(season)$wq$x21$yps21,22/23,24
863 41 $824.1$a1$b1$i2009$j21$x|a1|b2|i2009|j22/23$zSpring to Summer/Fall
863 41 $824.2$a1$b2$i2009$j22/23$x|a1|b3|i2009|j24$zSummer/Fall to Winter

# Item is published 6 times/year whose enumeration "skips" numbers
# at the second level using only odd numbers that restart
# at the turn of the calendar year.
# (From www.loc.gov/marc/chrono_patterns.html)
245 00 $aFunky enumeration
853 20 $825$av.$bno.$u6$vr$i(year)$j(month)$wb$ype21,3,5,7,9,11
863 41 $825.1$a1$b1$i1990$j01$x|a1|b3|i1990|j03$zJan to Mar
863 41 $825.2$a1$b11$i1990$j11$x|a2|b1|i1991|j01$zNov to Jan, year & vol wrap


# Monthly, one volume per year, issue numbering restarts in January
# Annual supplement published in September, annual index published in
# February
245 00 $aSupplements and Indexes: Oh My
853 20 $826$av.$bno.$u12$vr$i(year)$j(month)$wm
854 20 $827$av.$i(year)$j(month)$wa$ypm09$oSupplement
855 20 $828$av.$i(year)$j(month)$ypm02$oIndex
863 41 $826.1$a1$b1$i1990$j01$x|a1|b2|i1990|j02$znormal issue
864 41 $827.1$a1$i1990$j09$x|a2|i1991|j09$zAnnual supplement
865 41 $828.1$a1$i1990$j02$x|a2|i1991|j02$zAnnual Index
