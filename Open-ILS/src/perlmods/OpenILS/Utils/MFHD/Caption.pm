package MFHD::Caption;
use strict;
use integer;
use Carp;

use Data::Dumper;

use OpenILS::Utils::MFHD::Date;

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
	    $self->{_mfhdc_PATTERN}->{y} = {}
	      unless exists $self->{_mfhdc_PATTERN}->{y};
	    update_pattern($self, $val);
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

    my $pat = $self->{_mfhdc_PATTERN};

    # Sanity check publication frequency vs publication pattern:
    # if the frequency is a number, then the pattern better
    # have that number of values associated with it.
    if (exists($pat->{w}) && ($pat->{w} =~ /^\d+$/)
	&& ($pat->{w} != scalar(@{$pat->{y}->{p}}))) {
	carp("Caption::new: publication frequency '$pat->{w}' != publication pattern @{$pat->{y}->{p}}");
    }


    # If there's a $x subfield and a $j, then it's compressible
    if (exists $pat->{x} && exists $self->{_mfhdc_CHRONS}->{'j'}) {
	$self->{_mfhdc_COMPRESSIBLE} = 1;
    }

    bless ($self, $class);

    return $self;
}

sub update_pattern {
    my $self = shift;
    my $val = shift;
    my $pathash = $self->{_mfhdc_PATTERN}->{y};
    my ($pubcode, $pat) = unpack("a1a*", $val);

    $pathash->{$pubcode} = [] unless exists $pathash->{$pubcode};
    push @{$pathash->{$pubcode}}, $pat;
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

sub regularity_match {
    my $self = shift;
    my $pubcode = shift;
    my @date = @_;

    # we can't match something that doesn't exist.
    return 0 if !exists $self->{_mfhdc_PATTERN}->{y}->{$pubcode};

    foreach my $regularity (@{$self->{_mfhdc_PATTERN}->{y}->{$pubcode}}) {
	my $chroncode= substr($regularity, 0, 1);
	my $matchfunc = MFHD::Date::dispatch($chroncode);
	my @pats = split(/,/, substr($regularity, 1));

	if (!defined $matchfunc) {
	    carp "Unrecognized chroncode '$chroncode'";
	    return 0;
	}

	# XXX WRITE ME
	foreach my $pat (@pats) {
	    $pat =~ s|/.+||;	# If it's a combined date, match the start
	    if ($matchfunc->($pat, @date)) {
		return 1;
	    }
	}
    }

    return 0;
}

sub is_omitted {
    my $self = shift;
    my @date = @_;

#     printf("# is_omitted: testing date %s: %d\n", join('/', @date),
# 	   $self->regularity_match('o', @date));
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

    return 0 if !exists $self->{_mfhdc_PATTERN}->{y}->{c};

    foreach my $regularity (@{$self->{_mfhdc_PATTERN}->{y}->{c}}) {
	next unless $regularity =~ m/^e$level/o;

	my @pats = split(/,/, substr($regularity, 2));

	foreach my $pat (@pats) {
	    $pat =~ s|/.+||;	# if it's a combined issue, match the start
	    return 1 if ($iss eq $pat);
	}
    }

    return 0;
}


# Test to see if $dt1 is on or after $dt2
# if length(@{$dt2} == 2, then just month/day are compared
# if length(@{$dt2} == 1, then just the months are compared
sub on_or_after {
    my $dt1 = shift;
    my $dt2 = shift;

#     printf("# on_or_after(%s, %s): ", join('/', @{$dt1}), join('/', @{$dt2}));

    foreach my $i (0..(scalar(@{$dt2})-1)) {
	if ($dt1->[$i] > $dt2->[$i]) {
	    # $dt1 occurs AFTER $dt2
	    return 1;
	} elsif ($dt1->[$i] < $dt2->[$i]) {
	    # $dt1 occurs BEFORE $dt2
	    return 0;
	}
	# both are still equal, keep going
    }

    # We fell out of the loop with them being equal, so it's 'on'
    return 1;
}

sub calendar_increment {
    my $self = shift;
    my $cur = shift;
    my $new = shift;
    my $cal_change = $self->calendar_change;
    my $month;
    my $day;
    my $cur_before;
    my $new_on_or_after;

    # A calendar change is defined, need to check if it applies
    if ((scalar(@{$new}) == 2 && $new->[1] > 20) || (scalar(@{$new}) == 1)) {
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

# 	printf("# calendar_increment('%s', '%s'): change on '%s/%s'\n",
# 	       join('/', @{$cur}), join('/', @{$new}),
# 	       $month, defined($day) ? $day : 'UNDEF');

	if ($cur->[0] == $new->[0]) {
	    # Same year, so a 'simple' month/day comparison will be fine
	    $incr = (!on_or_after([$cur->[1], $cur->[2]], [$month, $day])
		     && on_or_after([$new->[1], $new->[2]], [$month, $day]));
	} else {
	    # @cur is in the year before @new. There are
	    # two possible cases for the calendar change date that
	    # indicate that it's time to change the volume:
	    # (1) the change date is AFTER @cur in the year, or
	    # (2) the change date is BEFORE @new in the year.
	    # 
	    #  -------|------|------X------|------|
	    #       @cur    (1)   Jan 1   (2)   @new

	    $incr = (on_or_after([$new->[1], $new->[2]], [$month, $day])
		     || !on_or_after([$cur->[1], $cur->[2]], [$month, $day]));
	}
	return $incr if $incr;
    }

    return 0;
}

sub next_date {
    my $self = shift;
    my $next = shift;
    my $carry = shift;
    my @keys = @_;
    my @cur;
    my @new;
    my @newend; # only used for combined issues
    my $incr;

    my $reg = $self->{_mfhdc_REGULARITY};
    my $pattern = $self->{_mfhdc_PATTERN};
    my $freq = $pattern->{w};

    foreach my $i (0..$#keys) {
	$cur[$i] = $next->{$keys[$i]} if exists $next->{$keys[$i]};
    }

    # If the current issue has a combined date (eg, May/June)
    # get rid of the first date and base the calculation
    # on the final date in the combined issue.
    $cur[-1] =~ s|^[^/]+/||;

    if (defined $pattern->{y}->{p}) {
	# There is a $y publication pattern defined in the record:
	# use it to calculate the next issue date.

	# XXX TODO: need to handle combined issues.
	foreach my $pubpat (@{$pattern->{y}->{p}}) {
	    my $chroncode = substr($pubpat, 0, 1);
	    my $genfunc = MFHD::Date::generator($chroncode);
	    my @pats = split(/,/, substr($pubpat, 1));

	    if (!defined $genfunc) {
		carp "Unrecognized chroncode '$chroncode'";
		return undef;
	    }

	    foreach my $pat (@pats) {
# 		printf("# next_date: generating with pattern '%s'\n", $pat);
		my @candidate = $genfunc->($pat, @cur);

		while ($self->is_omitted(@candidate)) {
# 		    printf("# pubpat omitting date '%s'\n",
# 			   join('/', @candidate));
		    @candidate = $genfunc->($pat, @candidate);
		}

# 		printf("# testing new candidate '%s' against '%s'\n",
# 		       join('/', @candidate), join('/', @new));
		if (!defined($new[0])
		    || !on_or_after(\@candidate, \@new)) {
		    # first time through the loop
		    # or @candidate is before @new => @candidate is the next
		    # issue.
		    @new = @candidate;
# 		    printf("# selecting candidate date '%s'\n", join('/', @new));
		}
	    }
	}

	# Now check for combined issues, like "May/June"
	foreach my $combpat (@{$pattern->{y}->{c}}) {
	    my $chroncode = substr($combpat, 0, 1);
	    my $genfunc = MFHD::Date::generator($chroncode);
	    my @pats = split(/,/, substr($combpat, 1));

	    foreach my $combined (@pats) {
		my ($start, $end) = split('/', $combined, 2);
		my @candidate = $genfunc->($start, @cur);

		# We don't need to check for omitted issues because
		# combined issues are always published. OR ARE THEY????
		if (!defined($new[0])
		    || !on_or_after(\@candidate, \@new)) {
		    # Haven't found a next issue at all yet, or
		    # this one is before the best guess so far
		    @new = @candidate;
		    @newend = $genfunc->($end, @cur);
		}
	    }
	}

	if (defined($newend[0])) {
	    # The best match was a combined issue
	    foreach my $i (0..$#new) {
		# don't combine identical fields
		next if $new[$i] eq $newend[$i];
		$new[$i] .= '/' . $newend[$i];
	    }
	}
    } else {
	# There is no $y publication pattern defined, so use
	# the $w frequency to figure out the next date

	if (!defined($freq)) {
	    carp "Undefined frequency in next_date!";
	} elsif (!MFHD::Date::can_increment($freq)) {
	    carp "Don't know how to deal with frequency '$freq'!";
	} else {
	    #
	    # One of the standard defined issue frequencies
	    #
	    @new = MFHD::Date::incr_date($freq, @cur);

	    while ($self->is_omitted(@new)) {
		@new = MFHD::Date::incr_date($freq, @new);
	    }

	    if ($self->is_combined(@new)) {
		my @second_date = MFHD::Date::incr_date($freq, @new);

		# I am cheating: This code assumes that only the smallest
		# time increment is combined. So, no "Apr 15/May 1" allowed.
		$new[-1] = $new[-1] . '/' . $second_date[-1];
	    }
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
    } elsif (defined $pattern->{x}) {
	$next->{a} += $self->calendar_increment(\@cur, \@new);
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
