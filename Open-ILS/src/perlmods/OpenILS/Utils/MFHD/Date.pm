package MFHD::Date;
use strict;
use integer;
use Carp;

use Data::Dumper;
use DateTime;

use base 'Exporter';

our @EXPORT_OK =qw(dispatch generator incr_date can_increment);

my %daynames = (
		'mo' => 1,
		'tu' => 2,
		'we' => 3,
		'th' => 4,
		'fr' => 5,
		'sa' => 6,
		'su' => 7,
	       );

my $daypat = '(mo|tu|we|th|fr|sa|su)';
my $weekpat = '(99|98|97|00|01|02|03|04|05)';
my $weeknopat;
my $monthpat = '(01|02|03|04|05|06|07|08|09|10|11|12)';
my $seasonpat = '(21|22|23|24)';

# Initialize $weeknopat to be '(01|02|03|...|51|52|53)'
$weeknopat = '(';
foreach my $weekno (1..52) {
    $weeknopat .= sprintf('%02d|', $weekno);
}
$weeknopat .= '53)';

sub match_day {
    my $pat = shift;
    my @date = @_;
    # Translate daynames into day of week for DateTime
    # also used to check if dayname is valid.

    if (exists $daynames{$pat}) {
	# dd
	# figure out day of week for date and compare
	my $dt = DateTime->new(year  => $date[0],
			       month => $date[1],
			       day   => $date[2]);
	return ($dt->day_of_week == $daynames{$pat});
    } elsif (length($pat) == 2) {
	# DD
	return $pat == $date[2];
    } elsif (length($pat) == 4) {
	# MMDD
	my ($mon, $day) = unpack("a2a2", $pat);

	return (($mon == $date[1]) && ($day == $date[2]));
    } else {
	carp "Invalid day pattern '$pat'";
	return 0;
    }
}

sub subsequent_day {
    my $pat = shift;
    my @cur = @_;
    my $dt = DateTime->new(year  => $cur[0],
			   month => $cur[1],
			   day   => $cur[2]);

#     printf("# subsequent_day: pat='%s' cur='%s'\n", $pat, join('/', @cur));

    if (exists $daynames{$pat}) {
	# dd: published on the given weekday
	my $dow = $dt->day_of_week;
	my $corr = ($dow - $daynames{$pat} + 7) % 7;

	if ($dow == $daynames{$pat}) {
	    # the next one is one week hence
	    $dt->add(days => 7);
	} else {
	    # the next one is later this week,
	    # or it is next week (ie, on or after next Monday)
	    # $corr will take care of it.
	    $dt->add(days => $corr);
	}
	@cur = ($dt->year, $dt->month, $dt->day);
    } elsif (length($pat) == 2) {
	# DD: published on the give day of every month
	if ($dt->day >= $pat) {
	    # current date is on or after $pat: next one is next month
	    $dt->set(day => $pat);
	    $dt->add(months => 1);
	    @cur = ($dt->year, $dt->month, $dt->day);
	} else {
	    # current date is before $pat: set day to pattern
	    $cur[2] = $pat;
	}
    } elsif (length($pat) == 4) {
	# MMDD: published on the given day of the given month
	my ($mon, $day) = unpack("a2a2", $pat);

	if (on_or_after($mon, $day, $cur[1], $cur[2])) {
	    # Current date is on or after pattern; next one is next year
	    $cur[0] += 1;
	}
	# Year is now right. Either it's next year (because of on_or_after)
	# or it's this year, because the current date is NOT on or after
	# the pattern. Just fix the month and day
	$cur[1] = $mon;
	$cur[2] = $day;
    } else {
	carp "Invalid day pattern '$pat'";
	return undef;
    }

    foreach my $i (0..$#cur) {
	$cur[$i] = '0' . (0+$cur[$i]) if $cur[$i] < 10;
    }

#     printf("subsequent_day: returning '%s'\n", join('/', @cur));

    return @cur;
}


# Calculate date of 3rd Friday of the month (for example)
# 1-5: count from beginning of month
# 99-97: count back from end of month
sub nth_week_of_month {
    my $dt = shift;
    my $week = shift;
    my $day = shift;
    my ($nth_day, $dow, $day);

    $day = $daynames{$day};

    if (0 < $week && $week <= 5) {
	$nth_day = DateTime->clone($dt)->set(day => 1);
    } elsif ($week >= 97) {
	$nth_day = DateTime->last_day_of_month(year  => $dt->year,
					       month => $dt->month);
    } else {
	return undef;
    }

    $dow = $nth_day->day_of_week();

    if ($week <= 5) {
	# count forwards
	$nth_day->add(days => ($day - $dow + 7) % 7,
		      weeks=> $week - 1);
    } else {
	# count backwards
	$nth_day->subtract(days => ($day - $nth_day->day_of_week + 7) % 7);

	# 99: last week of month, 98: second last, etc.
	for (my $i = 99 - $week; $i > 0; $i--) {
	    $nth_day->subtract(weeks => 1);
	}
    }

    # There is no nth "day" in the month!
    return undef if ($dt->month != $nth_day->month);

    return $nth_day;
}

#
# Internal utility function to match the various different patterns
# of month, week, and day
#
sub check_date {
    my $dt = shift;
    my $month = shift;
    my $weekno = shift;
    my $day = shift;

    if (!defined $day) {
	# MMWW
	return (($dt->month == $month)
		&& (($dt->week_of_month == $weekno)
		    || ($weekno >= 97
			&& ($dt->week_of_month == nth_week_of_month($dt, $weekno, $day)->week_of_month))));
    }

    # simple cases first
    if ($daynames{$day} != $dt->day_of_week) {
	# if it's the wrong day of the week, rest doesn't matter
	return 0;
    }

    if (!defined $month) {
	# WWdd
	return (($weekno == 0)	# Every week
		|| ($dt->weekday_of_month == $weekno) # this week
		|| (($weekno >= 97) && ($dt->weekday_of_month == nth_week_of_month($dt, $weekno, $day)->weekday_of_month)));
    }

    # MMWWdd
    if ($month != $dt->month) {
	# If it's the wrong month, then we're done
	return 0;
    }

    # It's the right day of the week
    # It's the right month

    if (($weekno == 0) ||($weekno == $dt->weekday_of_month)) {
	# If this matches, then we're counting from the beginning
	# of the month and it matches and we're done.
	return 1;
    }

    # only case left is that the week number is counting from
    # the end of the month: eg, second last wednesday
    return (($weekno >= 97)
	    && (nth_week_of_month($dt, $weekno, $day)->weekday_of_month == $dt->weekday_of_month));
}

sub match_week {
    my $pat = shift;
    my @date = @_;
    my $dt = DateTime->new(year  => $date[0],
			   month => $date[1],
			   day   => $date[2]);

    if ($pat =~ m/^$weekpat$daypat$/) {
	# WWdd: 03we = Third Wednesday
	return check_date($dt, undef, $1, $2);
    } elsif ($pat =~ m/^$monthpat$weekpat$daypat$/) {
	# MMWWdd: 0599tu Last Tuesday in May XXX WRITE ME
	return check_date($dt, $1, $2, $3);
    } elsif ($pat =~ m/^$monthpat$weekpat$/) {
	# MMWW: 1204: Fourth week in December XXX WRITE ME
	return check_date($dt, $1, $2, undef);
    } else {
	carp "invalid week pattern '$pat'";
	return 0;
    }
}

#
# Use $pat to calcuate the date of the issue following $cur
#
sub subsequent_week {
    my $pat = shift;
    my @cur = @_;
    my $candidate;
    my $dt = DateTime->new(year => $cur[0],
			   month=> $cur[1],
			   day  => $cur[2]);

    if ($pat =~ m/^$weekpat$daypat$/) {
	# WWdd: published on given weekday of given week of every month
	my ($week, $day) = ($1, $2);

	if ($week eq '00') {
	    # Every week
	    $candidate = DateTime->clone($dt);
	    if ($dt->day_of_week == $daynames{$day}) {
		# Current is right day, next one is a week hence
		$candidate->add(days => 7);
	    } else {
		$candidate->add(days => ($dt->day_of_week - $daynames{$day} + 7) % 7);
	    }
	} else {
	    # 3rd Friday of the month (eg)
	    $candidate = nth_week_of_month($dt, $week, $day);
	}

	if ($candidate < $dt) {
	    # If the n'th week of the month happens before the
	    # current issue, then the next issue is published next
	    # month, otherwise, it's published this month.
	    # This will never happen for the "00: every week" pattern
	    $candidate = DateTime->clone($dt)->add(months => 1)->set(day => 1);
	    $candidate = nth_week_of_month($dt, $week, $day);
	}
    } elsif ($pat =~ m/^$monthpat$weekpat$daypat$/) {
	# MMWWdd: published on given weekday of given week of given month
	my ($month, $week, $day) = ($1, $2, $3);

	$candidate = DateTime->new(year => $dt->year,
				   month=> $month,
				   day  => 1);
	$candidate = nth_week_of_month($candidate, $week, $day);
	if ($candidate < $dt) {
	    # We've missed it for this year, next one that matches
	    # will be next year
	    $candidate->add(years => 1)->set(day => 1);
	    $candidate = nth_week_of_month($candidate, $week, $day);
	}
    } elsif ($pat =~ m/^$monthpat$weekpat$/) {
	# MMWW: published during given week of given month
	my ($month, $week) = ($1, $2);

	$candidate = nth_week_of_month(DateTime->new(year => $dt->year,
						     month=> $month,
						     day  => 1),
				       $week,
				       'th');
	if ($candidate < $dt) {
	    # Already past the pattern date this year, move to next year
	    $candidate->add(years => 1)->set(day => 1);
	    $candidate = nth_week_of_month($candidate, $week, 'th');
	}
    } else {
	carp "invalid week pattern '$pat'";
	return undef;
    }

    $cur[0] = $candidate->year;
    $cur[1] = $candidate->month;
    $cur[2] = $candidate->day;

    foreach my $i (0..$#cur) {
	$cur[$i] = '0' . (0+$cur[$i]) if $cur[$i] < 10;
    }

    return @cur;
}

sub match_month {
    my $pat = shift;
    my @date = @_;

    return ($pat eq $date[1]);
}

sub subsequent_month {
    my $pat = shift;
    my @cur = @_;

    if ($cur[1] >= $pat) {
	# Current date is on or after the patter date, so the next
	# occurence is next year
	$cur[0] += 1;
    }

    # The year is right, just set the month to the pattern date.
    $cur[1] = $pat;

    return @cur;
}

sub match_season {
    my $pat = shift;
    my @date = @_;

    return ($pat eq $date[1]);
}

sub subsequent_season {
    my $pat = shift;
    my @cur = @_;

    if (($pat < 21) || ($pat > 24)) {
	carp "Unexpected season '$pat'";
	return undef;
    }

    if ($cur[1] >= $pat) {
	# current season is on or past pattern season in this year,
	# advance to next year
	$cur[0] += 1;
    }
    # Either we've advanced to the next year or the current season
    # is before the pattern season in the current year. Either way,
    # all that remains is to set the season properly
    $cur[1] = $pat;

    return @cur;
}

sub match_year {
    my $pat = shift;
    my @date = @_;

    # XXX WRITE ME
    return 0;
}

sub subsequent_year {
    my $pat = shift;
    my $cur = shift;

    # XXX WRITE ME
    return undef;
}

sub match_issue {
    my $pat = shift;
    my @date = @_;

    # We handle enumeration patterns separately. This just
    # ensures that when we're processing chronological patterns
    # we don't match an enumeration pattern.
    return 0;
}

sub subsequent_issue {
    my $pat = shift;
    my $cur = shift;

    # Issue generation is handled separately
    return undef;
}

my %dispatch = (
		d => \&match_day,
		e => \&match_issue, # not really a "chron" code
		w => \&match_week,
		m => \&match_month,
		s => \&match_season,
		y => \&match_year,
);

my %generators = (
		  d => \&subsequent_day,
		  e => \&subsequent_issue, # not really a "chron" code
		  w => \&subsequent_week,
		  m => \&subsequent_month,
		  s => \&subsequent_season,
		  y => \&subsequent_year,
);

sub dispatch {
    my $chroncode = shift;

    return $dispatch{$chroncode};
}

sub generator {
    my $chroncode = shift;

    return $generators{$chroncode};
}

my %increments = (
		  a => {years => 1}, # annual
		  b => {months => 2}, # bimonthly
		  c => {days => 3}, # semiweekly
		  d => {days => 1}, # daily
		  e => {weeks => 2}, # biweekly
		  f => {months => 6}, # semiannual
		  g => {years => 2},  # biennial
		  h => {years => 3},  # triennial
		  i => {days => 2}, # three times / week
		  j => {days => 10}, # three times /month
		  # k => continuous
		  m => {months => 1}, # monthly
		  q => {months => 3}, # quarterly
		  s => {days => 15},  # semimonthly
		  t => {months => 4}, # three times / year
		  w => {weeks => 1},  # weekly
		  # x => completely irregular
);

sub can_increment {
    my $freq = shift;

    return exists $increments{$freq};
}

sub incr_date {
    my $freq = shift;
    my $incr = $increments{$freq};
    my @new = @_;

    if (scalar(@new) == 1) {
	# only a year is specified. Next date is easy
	$new[0] += $incr->{years} || 1;
    } elsif (scalar(@new) == 2) {
	# Year and month or season
	if ($new[1] > 20) {
	    # season
	    $new[1] += ($incr->{months}/3) || 1;
	    if ($new[1] > 24) {
		# carry
		$new[0] += 1;
		$new[1] -= 4;	# 25 - 4 == 21 == Spring after Winter
	    }
	} else {
	    # month
	    $new[1] += $incr->{months} || 1;
	    if ($new[1] > 12) {
		# carry
		$new[0] += 1;
		$new[1] -= 12;
	    }
	}
    } elsif (scalar(@new) == 3) {
	# Year, Month, Day: now it gets complicated.

	if ($new[2] =~ /^[0-9]+$/) {
	    # A single number for the day of month, relatively simple
	    my $dt = DateTime->new(year => $new[0],
				   month=> $new[1],
				   day  => $new[2]);
	    $dt->add(%{$incr});
	    $new[0] = $dt->year;
	    $new[1] = $dt->month;
	    $new[2] = $dt->day;
	}
    } else {
	warn("Don't know how to cope with @new");
    }

    foreach my $i (0..$#new) {
	$new[$i] = '0' . (0+$new[$i]) if $new[$i] < 10;
    }

    return @new;
}

1;
