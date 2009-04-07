package MFHD::Caption;
use strict;
use integer;
use Carp;

use Data::Dumper;

use DateTime;

use base 'MARC::Field';

sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = shift;
    my $last_enum = undef;

    $self->{_mfhdc_ENUMS} = {};
    $self->{_mfhdc_CHRONS} = {};
    $self->{_mfhdc_PATTERN} = {};
    $self->{_mfhdc_COPY} = undef;
    $self->{_mfhdc_UNIT} = undef;
    $self->{_mfhdc_COMPRESSIBLE} = 1;	# until proven otherwise

    foreach my $subfield ($self->subfields) {
	my ($key, $val) = @$subfield;
	if ($key eq '8') {
	    $self->{LINK} = $val;
	} elsif ($key =~ /[a-h]/) {
	    # Enumeration Captions
	    $self->{_mfhdc_ENUMS}->{$key} = {CAPTION => $val,
					     COUNT => undef,
					     RESTART => undef};
	    if ($key =~ /[ag]/) {
		$last_enum = undef;
	    } else {
		$last_enum = $key;
	    }
	} elsif ($key =~ /[i-m]/) {
	    # Chronology captions
	    $self->{_mfhdc_CHRONS}->{$key} = $val;
	} elsif ($key eq 'u') {
	    # Bib units per next higher enumeration level
	    carp('$u specified for top-level enumeration')
	      unless defined($last_enum);
	    $self->{_mfhdc_ENUMS}->{$last_enum}->{COUNT} = $val;
	} elsif ($key eq 'v') {
	    carp '$v specified for top-level enumeration'
	      unless defined($last_enum);
	    $self->{_mfhdc_ENUMS}->{$last_enum}->{RESTART} = ($val eq 'r');
	} elsif ($key =~ /[npwz]/) {
	    # Publication Pattern info ('o' == type of unit, 'q'..'t' undefined)
	    $self->{_mfhdc_PATTERN}->{$key} = $val;
	} elsif ($key =~ /x/) {
	    # Calendar change can have multiple comma-separated values
	    $self->{_mfhdc_PATTERN}->{x} = [split /,/, $val];
	} elsif ($key eq 'y') {
	    $self->{_mfhdc_PATTERN}->{y} = []
	      unless exists $self->{_mfhdc_PATTERN}->{y};
	    push @{$self->{_mfhdc_PATTERN}->{y}}, $val;
	} elsif ($key eq 'o') {
	    # Type of unit
	    $self->{_mfhdc_UNIT} = $val;
	} elsif ($key eq 't') {
	    $self->{_mfhdc_COPY} = $val;
	} else {
	    carp "Unknown caption subfield '$key'";
	}
    }

    # subsequent levels of enumeration (primary and alternate)
    # If an enumeration level doesn't document the number
    # of "issues" per "volume", or whether numbering of issues
    # restarts, then we can't compress.
    foreach my $key ('b', 'c', 'd', 'e', 'f', 'h') {
	if (exists $self->{_mfhdc_ENUMS}->{$key}) {
	    my $pattern = $self->{_mfhdc_ENUMS}->{$key};
	    if (!$pattern->{RESTART} || !$pattern->{COUNT}
		|| ($pattern->{COUNT} eq 'var')
		|| ($pattern->{COUNT} eq 'und')) {
		$self->{_mfhdc_COMPRESSIBLE} = 0;
		last;
	    }
	}
    }

    # If there's a $x subfield and a $j, then it's compressible
    if (exists $self->{_mfhdc_PATTERN}->{x} && exists $self->{_mfhdc_CHRONS}->{'j'}) {
	$self->{_mfhdc_COMPRESSIBLE} = 1;
    }

    bless ($self, $class);

    if (exists $self->{_mfhdc_PATTERN}->{y}) {
	$self->decode_pattern;
    }

    return $self;
}

sub decode_pattern {
    my $self = shift;
    my $pattern = $self->{_mfhdc_PATTERN}->{y};

    # XXX WRITE ME (?)
}

sub compressible {
    my $self = shift;

    return $self->{_mfhdc_COMPRESSIBLE};
}

sub chrons {
    my $self = shift;
    my $key = shift;

    if (exists $self->{_mfhdc_CHRONS}->{$key}) {
	return $self->{_mfhdc_CHRONS}->{$key};
    } else {
	return undef;
    }
}

sub capfield {
    my $self = shift;
    my $key = shift;

    if (exists $self->{_mfhdc_ENUMS}->{$key}) {
	return $self->{_mfhdc_ENUMS}->{$key};
    } elsif (exists $self->{_mfhdc_CHRONS}->{$key}) {
	return $self->{_mfhdc_CHRONS}->{$key};
    } else {
	return undef;
    }
}

sub capstr {
    my $self = shift;
    my $key = shift;
    my $val = $self->capfield($key);

    if (ref $val) {
	return $val->{CAPTION};
    } else {
	return $val;
    }
}

sub calendar_change {
    my $self = shift;

    return $self->{_mfhdc_PATTERN}->{x};
}

# If items are identified by chronology only, with no separate
# enumeration (eg, a newspaper issue), then the chronology is
# recorded in the enumeration subfields $a - $f.  We can tell
# that this is the case if there are $a - $f subfields and no
# chronology subfields ($i-$k), and none of the $a-$f subfields
# have associated $u or $v subfields, but there's a $w and no $x

sub enumeration_is_chronology {
    my $self = shift;

    # There is always a '$a' subfield in well-formed fields.
    return 0 if exists $self->{_mfhdc_CHRONS}->{i}
      || exists $self->{_mfhdc_PATTERN}->{x};

    foreach my $key ('a' .. 'f') {
	my $enum;

	last if !exists $self->{_mfhdc_ENUMS}->{$key};

	$enum = $self->{_mfhdc_ENUMS}->{$key};
	return 0 if defined $enum->{COUNT} || defined $enum->{RESTART};
    }

    return (exists $self->{_mfhdc_PATTERN}->{w});
}

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
	# MM
	return $pat == $date[3];
    } elsif (length($pat) == 4) {
	# MMDD
	my ($mon, $day);
	$mon = substr($pat, 0, 2);
	$day = substr($pat, 2, 2);

	return (($mon == $date[1]) && ($day == $date[2]));
    } else {
	carp "Invalid day pattern '$pat'";
	return 0;
    }
}

# Calcuate date of "n"th last "dayname" of month: second last Tuesday
sub last_week_of_month {
    my $dt = shift;
    my $week = shift;
    my $day = shift;
    my $end_dt = DateTime->last_day_of_month(year  => $dt->year,
					     month => $dt->month);

    $day = $daynames{$day};
    while ($end_dt->day_of_week != $day) {
	$end_dt->subtract(days => 1);
    }

    # 99: last week of month, 98: second last, etc.
    for (my $i = 99 - $week; $i > 0; $i--) {
	$end_dt->subtract(weeks => 1);
    }

    return $end_dt;
}

sub check_date {
    my $dt = shift;
    my $month = shift;
    my $weekno = shift;
    my $day = shift;

    if (!defined $day) {
	# MMWW
	return (($dt->month == $month)
		&& (($dt->week_of_month == $weekno)
		    || ($dt->week_of_month == last_day_of_month($dt, $weekno, 'th')->week_of_month)));
    }

    # simple cases first
    if ($daynames{$day} != $dt->day_of_week) {
	# if it's the wrong day of the week, rest doesn't matter
	return 0;
    }

    if (!defined $month) {
	# WWdd
	return (($dt->weekday_of_month == $weekno)
		|| ($dt->weekday_of_month == last_day_of_month($dt, $weekno, $day)->weekday_of_month));
    }

    # MMWWdd
    if ($month != $dt->month) {
	# If it's the wrong month, then we're done
	return 0;
    }

    # It's the right day of the week
    # It's the right month

    if ($weekno == $dt->weekday_of_month) {
	# If this matches, then we're counting from the beginning
	# of the month and it matches and we're done.
	return 1;
    }

    # only case left is that the week number is counting from
    # the end of the month: eg, second last wednesday
    return (last_week_of_month($weekno, $day)->weekday_of_month == $dt->weekday_of_month);
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

sub match_month {
    my $pat = shift;
    my @date = @_;

    return ($pat eq $date[1]);
}

sub match_season {
    my $pat = shift;
    my @date = @_;

    return ($pat eq $date[1]);
}

sub match_year {
    my $pat = shift;
    my @date = @_;

    # XXX WRITE ME
    return 0;
}

sub match_issue {
    my $pat = shift;
    my @date = @_;

    # We handle enumeration patterns separately. This just
    # ensures that when we're processing chronological patterns
    # we don't match an enumeration pattern.
    return 0;
}

my %dispatch = (
		'd' => \&match_day,
		'e' => \&match_issue, # not really a "chron" code
		'w' => \&match_week,
		'm' => \&match_month,
		's' => \&match_season,
		'y' => \&match_year,
);

sub regularity_match {
    my $self = shift;
    my $pubcode = shift;
    my @date = @_;

    # we can't match something that doesn't exist.
    return 0 if !exists $self->{_mfhdc_PATTERN}->{y};

    foreach my $regularity (@{$self->{_mfhdc_PATTERN}->{y}}) {
	next unless $regularity =~ m/^$pubcode/;

	my $chroncode= substr($regularity, 1, 1);
	my @pats = split(/,/, substr($regularity, 2));

	if (!exists $dispatch{$chroncode}) {
	    carp "Unrecognized chroncode '$chroncode'";
	    return 0;
	}

	# XXX WRITE ME
	foreach my $pat (@pats) {
	    $pat =~ s|/.+||;	# If it's a combined date, match the start
	    if ($dispatch{$chroncode}->($pat, @date)) {
		return 1;
	    }
	}
    }

    return 0;
}

sub is_omitted {
    my $self = shift;
    my @date = @_;

    return $self->regularity_match('o', @date);
}

sub is_published {
    my $self = shift;
    my @date = @_;

    return $self->regularity_match('p', @date);
}

sub is_combined {
    my $self = shift;
    my @date = @_;

    return $self->regularity_match('c', @date);
}

sub enum_is_combined {
    my $self = shift;
    my $subfield = shift;
    my $iss = shift;
    my $level = ord($subfield) - ord('a') + 1;

    return 0 if !exists $self->{_mfhdc_PATTERN}->{y};

    foreach my $regularity (@{$self->{_mfhdc_PATTERN}->{y}}) {
	next unless $regularity =~ m/^ce$level/o;

	my @pats = split(/,/, substr($regularity, 3));

	foreach my $pat (@pats) {
	    $pat =~ s|/.+||;	# if it's a combined issue, match the start
	    return 1 if ($iss eq $pat);
	}
    }

    return 0;
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

sub incr_date {
    my $incr = shift;
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
	    $new[1] = '0' . $new[1] if ($new[1] < 10);
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
	$new[1] = '0' . $new[1] if ($new[1] < 10);
	$new[2] = '0' . $new[2] if ($new[2] < 10);
    } else {
	warn("Don't know how to cope with @new");
    }

    return @new;
}

# Test to see if $m1/$d1 is on or after $m2/$d2
# if $d2 is undefined, test is based on just months
sub on_or_after {
    my ($m1, $d1, $m2, $d2) = @_;

    return (($m1 > $m2)
	    || ($m1 == $m2 && ((!defined $d2) || ($d1 >= $d2))));
}

sub calendar_increment {
    my $self = shift;
    my $cur = shift;
    my @new = @_;
    my $cal_change = $self->calendar_change;
    my $month;
    my $day;
    my $cur_before;
    my $new_on_or_after;

    # A calendar change is defined, need to check if it applies
    if ((scalar(@new) == 2 && $new[1] > 20) || (scalar(@new) == 1)) {
	carp "Can't calculate date change for ", $self->as_string;
	return;
    }

    foreach my $change (@{$cal_change}) {
	my $incr;

	if (length($change) == 2) {
	    $month = $change;
	} elsif (length($change) == 4) {
	    ($month, $day) = unpack("a2a2", $change);
	}

	if ($cur->[0] == $new[0]) {
	    # Same year, so a 'simple' month/day comparison will be fine
	    $incr = (!on_or_after($cur->[1], $cur->[2], $month, $day)
		     && on_or_after($new[1], $new[2], $month, $day));
	} else {
	    # @cur is in the year before @new. There are
	    # two possible cases for the calendar change date that
	    # indicate that it's time to change the volume:
	    # (1) the change date is AFTER @cur in the year, or
	    # (2) the change date is BEFORE @new in the year.
	    # 
	    #  -------|------|------X------|------|
	    #       @cur    (1)   Jan 1   (2)   @new

	    $incr = (on_or_after($new[1], $new[2], $month, $day)
		     || !on_or_after($cur->[1], $cur->[2], $month, $day));
	}
	return $incr if $incr;
    }
}

sub next_date {
    my $self = shift;
    my $next = shift;
    my $carry = shift;
    my @keys = @_;
    my @cur;
    my @new;
    my $incr;

    my $reg = $self->{_mfhdc_REGULARITY};
    my $pattern = $self->{_mfhdc_PATTERN};
    my $freq = $pattern->{w};

    foreach my $i (0..$#keys) {
	$new[$i] = $cur[$i] = $next->{$keys[$i]} if exists $next->{$keys[$i]};
    }

    # If the current issue has a combined date (eg, May/June)
    # get rid of the first date and base the calculation
    # on the final date in the combined issue.
    $new[-1] =~ s|^[^/]+/||;

    # If $frequency is not one of the standard codes defined in %increments
    # then there has to be a $yp publication regularity pattern that
    # lists the dates of publication. Use that that list to find the next
    # date following the current one.
    # XXX: the code doesn't handle this case yet.
    if (!defined($freq)) {
	carp "Undefined frequency in next_date!";
    } elsif (!exists $increments{$freq}) {
	carp "Don't know how to deal with frequency '$freq'!";
    } else {
	#
	# One of the standard defined issue frequencies
	#
	@new = incr_date($increments{$freq}, @new);

	while ($self->is_omitted(@new)) {
	    @new = incr_date($increments{$freq}, @new);
	}

	if ($self->is_combined(@new)) {
	    my @second_date = incr_date($increments{$freq}, @new);

	    # I am cheating: This code assumes that only the smallest
	    # time increment is combined. So, no "Apr 15/May 1" allowed.
	    $new[-1] = $new[-1] . '/' . $second_date[-1];
	}
    }

    for my $i (0..$#new) {
	$next->{$keys[$i]} = $new[$i];
    }

    # Figure out if we need to adust volume number
    # right now just use the $carry that was passed in.
    # in long run, need to base this on ($carry or date_change)
    if ($carry) {
	# if $carry is set, the date doesn't matter: we're not
	# going to increment the v. number twice at year-change.
	$next->{a} += $carry;
    } elsif (defined $self->{_mfhdc_PATTERN}->{x}) {
	$next->{a} += $self->calendar_increment(\@cur, @new);
    }
}

sub next_alt_enum {
    my $self = shift;
    my $next = shift;

    # First handle any "alternative enumeration", since they're
    # a lot simpler, and don't depend on the the calendar
    foreach my $key ('h', 'g') {
	next if !exists $next->{$key};
	if (!$self->capstr($key)) {
	    warn "Holding data exists for $key, but no caption specified";
	    $next->{$key} += 1;
	    last;
	}

	my $cap = $self->capfield($key);
	if ($cap->{RESTART} && $cap->{COUNT}
	    && ($next->{$key} == $cap->{COUNT})) {
	    $next->{$key} = 1;
	} else {
	    $next->{$key} += 1;
	    last;
	}
    }
}

sub next_enum {
    my $self = shift;
    my $next = shift;
    my $carry;

    # $carry keeps track of whether we need to carry into the next
    # higher level of enumeration. It's not actually necessary except
    # for when the loop ends: if we need to carry from $b into $a
    # then $carry will be set when the loop ends.
    #
    # We need to keep track of this because there are two different
    # reasons why we might increment the highest level of enumeration ($a)
    # 1) we hit the correct number of items in $b (ie, 5th iss of quarterly)
    # 2) it's the right time of the year.
    #
    $carry = 0;
    foreach my $key (reverse('b'..'f')) {
	next if !exists $next->{$key};

	if (!$self->capstr($key)) {
	    # Just assume that it increments continuously and give up
	    warn "Holding data exists for $key, but no caption specified";
	    $next->{$key} += 1;
	    $carry = 0;
	    last;
	}

	# If the current issue has a combined issue number (eg, 2/3)
	# get rid of the first issue number and base the calculation
	# on the final issue number in the combined issue.
	if ($next->{$key} =~ m|/|) {
	    $next->{$key} =~ s|^[^/]+/||;
	}

	my $cap = $self->capfield($key);
	if ($cap->{RESTART} && $cap->{COUNT}
	    && ($next->{$key} eq $cap->{COUNT})) {
	    $next->{$key} = 1;
	    $carry = 1;
	} else {
	    # If I don't need to "carry" beyond here, then I just increment
	    # this level of the enumeration and stop looping, since the
	    # "next" hash has been initialized with the current values

	    $next->{$key} += 1;
	    $carry = 0;
	}

	# You can't have a combined issue that spans two volumes: no.12/1
	# is forbidden
	if ($self->enum_is_combined($key, $next->{$key})) {
	    $next->{$key} .= '/' . ($next->{$key} + 1);
	}

	last if !$carry;
    }

    # The easy part is done. There are two things left to do:
    # 1) Calculate the date of the next issue, if necessary
    # 2) Increment the highest level of enumeration (either by date
    #    or because $carry is set because of the above loop

    if (!$self->subfield('i')) {
	# The simple case: if there is no chronology specified
	# then just check $carry and return
	$next->{'a'} += $carry;
    } else {
	# Figure out date of next issue, then decide if we need
	# to adjust top level enumeration based on that
	$self->next_date($next, $carry, ('i'..'m'));
    }
}

sub next {
    my $self = shift;
    my $holding = shift;
    my $next = {};

    # Initialize $next with current enumeration & chronology, then
    # we can just operate on $next, based on the contents of the caption

    if ($self->enumeration_is_chronology) {
	foreach my $key ('a' .. 'h') {
	    $next->{$key} = $holding->{_mfhdh_SUBFIELDS}->{$key}
	      if defined $holding->{_mfhdh_SUBFIELDS}->{$key};
	}
	$self->next_date($next, 0, ('a' .. 'h'));

	return $next;
    }

    foreach my $key ('a' .. 'h') {
	$next->{$key} = $holding->{_mfhdh_SUBFIELDS}->{$key}->{HOLDINGS}
	  if defined $holding->{_mfhdh_SUBFIELDS}->{$key};
    }

    foreach my $key ('i'..'m') {
	$next->{$key} = $holding->{_mfhdh_SUBFIELDS}->{$key}
	  if defined $holding->{_mfhdh_SUBFIELDS}->{$key};
    }

    if (exists $next->{'h'}) {
	$self->next_alt_enum($next);
    }

    $self->next_enum($next);

    return($next);
}

1;
