package MFHD::Caption;
use strict;
use integer;
use Carp;

use DateTime;
use MARC::Record;

sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $caption = shift;
    my $self = {};
    my $last_enum = undef;

    $self->{CAPTION} = $caption;
    $self->{ENUMS} = {};
    $self->{CHRONS} = {};
    $self->{PATTERN} = {};
    $self->{COPY} = undef;
    $self->{UNIT} = undef;
    $self->{COMPRESSIBLE} = 1;	# until proven otherwise

    foreach my $subfield ($caption->subfields) {
	my ($key, $val) = @$subfield;
	if ($key eq '8') {
	    $self->{LINK} = $val;
	} elsif ($key =~ /[a-h]/) {
	    # Enumeration Captions
	    $self->{ENUMS}->{$key} = {CAPTION => $val,
				      COUNT => undef,
				      RESTART => undef};
	    if ($key =~ /[ag]/) {
		$last_enum = undef;
	    } else {
		$last_enum = $key;
	    }
	} elsif ($key =~ /[i-m]/) {
	    # Chronology captions
	    $self->{CHRONS}->{$key} = $val;
	} elsif ($key eq 'u') {
	    # Bib units per next higher enumeration level
	    carp('$u specified for top-level enumeration')
	      unless defined($last_enum);
	    $self->{ENUMS}->{$last_enum}->{COUNT} = $val;
	} elsif ($key eq 'v') {
	    carp '$v specified for top-level enumeration'
	      unless defined($last_enum);
	    $self->{ENUMS}->{$last_enum}->{RESTART} = ($val eq 'r');
	} elsif ($key =~ /[npwxz]/) {
	    # Publication Pattern ('o' == type of unit, 'q'..'t' undefined)
	    $self->{PATTERN}->{$key} = $val;
	} elsif ($key eq 'y') {
	    # Publication pattern: 'y' is repeatable
	    $self->{PATTERN}->{y} = [] if (!defined $self->{PATTERN}->{y});
	    push @{$self->{PATTERN}->{y}}, $val;
	} elsif ($key eq 'o') {
	    # Type of unit
	    $self->{UNIT} = $val;
	} elsif ($key eq 't') {
	    $self->{COPY} = $val;
	} else {
	    carp "Unknown caption subfield '$key'";
	}
    }

    # subsequent levels of enumeration (primary and alternate)
    # If an enumeration level doesn't document the number
    # of "issues" per "volume", or whether numbering of issues
    # restarts, then we can't compress.
    foreach my $key ('b', 'c', 'd', 'e', 'f', 'h') {
	if (exists $self->{ENUMS}->{$key}) {
	    my $pattern = $self->{ENUMS}->{$key};
	    if (!$pattern->{RESTART} || !$pattern->{COUNT}
		|| ($pattern->{COUNT} eq 'var')
		|| ($pattern->{COUNT} eq 'und')) {
		$self->{COMPRESSIBLE} = 0;
		last;
	    }
	}
    }

    # If there's a $x subfield and a $j, then it's compressible
    if (exists $self->{PATTERN}->{x} && exists $self->{CHRONS}->{'j'}) {
	$self->{COMPRESSIBLE} = 1;
    }

    bless ($self, $class);

    if (exists $self->{PATTERN}->{y}) {
	$self->decode_pattern;
    }

    return $self;
}

sub decode_pattern {
    my $self = shift;
    my $pattern = $self->{PATTERN}->{y};

    # XXX WRITE ME (?)
}

sub compressible {
    my $self = shift;

    return $self->{COMPRESSIBLE};
}

sub caption {
    my $self = shift;
    my $key;

    if (@_) {
	$key = shift;
	if (exists $self->{ENUMS}->{$key}) {
	    return $self->{ENUMS}->{$key}->{CAPTION};
	} elsif (exists $self->{CHRONS}->{$key}) {
	    return $self->{CHRONS}->{$key};
	} else {
	    return undef;
	}
    } else {
	return $self->{CAPTION};
    }
}

# If items are identified by chronology only, with no separate
# enumeration (eg, a newspaper issue), then the chronology is
# recorded in the enumeration subfields $a - $f.  We can tell
# that this is the case if there are $a - $f subfields and no
# chronology subfields ($i-$k), and none of the $a-$f subfields
# have associated $u or $v subfields, but there are $w and $y
# subfields.

sub enumeration_is_chronology {
    my $self = shift;

    # There is always a '$a' subfield in well-formed fields.
    return 0 if exists $self->{CHRONS}->{i};

    foreach my $key ('a' .. 'f') {
	my $enum;

	last if !exists $self->{ENUMS}->{$key};

	$enum = $self->{ENUMS}->{$key};
	return 0 if defined $enum->{COUNT} || defined $enum->{RESTART};
    }

    return (exists $self->{PATTERN}->{w} && exists $self->{PATTERN}->{y});
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
    $weeknopat .= sprintf("%02d|", $weekno);
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
}

my %dispatch = (
		'd' => \&match_day,
		'w' => \&match_week,
		'm' => \&match_month,
		's' => \&match_season,
		'y' => \&match_year,
);
sub regularity_match {
    my $self = shift;
    my $pubcode = shift;
    my @date = @_;

    foreach my $regularity ($self->{PATTERN}->{y}) {
	next unless $regularity =~ m/^$pubcode/;

	my $chroncode= substr($regularity, 1, 1);
	my @pats = split(/,/, substr($regularity, 2));

	# XXX WRITE ME
	foreach my $pat (@pats) {
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

1;
