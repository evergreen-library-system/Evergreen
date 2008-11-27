package MFHD::Holding;
use strict;
use integer;
use Carp;

use Data::Dumper;

use MARC::Record;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $seqno = shift;
    my $holding = shift;
    my $caption = shift;
    my $self = {};
    my $last_enum = undef;

    $self->{SEQNO} = $seqno;
    $self->{HOLDING} = $holding;
    $self->{CAPTION} = $caption;
    $self->{ENUMS} = {};
    $self->{CHRON} = {};
    $self->{DESCR} = {};
    $self->{COPY} = undef;
    $self->{BREAK} = undef;
    $self->{NOTES} = {};
    $self->{COPYRIGHT} = [];

    foreach my $subfield ($holding->subfields) {
	my ($key, $val) = @$subfield;
	if ($key =~ /[a-h]/) {
	    # Enumeration details of holdings
	    $self->{ENUMS}->{$key} = {HOLDINGS => $val,
				     UNIT     => undef,};
	    $last_enum = $key;
	} elsif ($key =~ /[i-m]/) {
	    $self->{CHRON}->{$key} = $val;
	    if (!exists $caption->{CHRONS}->{$key}) {
		warn "Holding '$seqno' specified enumeration level '$key' not included in caption $caption->{LINK}";
	    }
	} elsif ($key eq 'o') {
	    warn '$o specified prior to first enumeration'
	      unless defined($last_enum);
	    $self->{ENUMS}->{$last_enum}->{UNIT} = $val;
	    $last_enum = undef;
	} elsif ($key =~ /[npq]/) {
	    $self->{DESCR}->{$key} = $val;
	} elsif ($key eq 's') {
	    push @{$self->{COPYRIGHT}}, $val;
	} elsif ($key eq 't') {
	    $self->{COPY} = $val;
	} elsif ($key eq 'w') {
	    carp "Unrecognized break indicator '$val'"
	      unless $val =~ /^[gn]$/;
	    $self->{BREAK} = $val;
	}
    }

    bless ($self, $class);
    return $self;
}

sub format_chron {
    my $self = shift;
    my $caption = $self->{CAPTION};
    my @keys;
    my $str = '';
    my %month = ( '01' => 'Jan.', '02' => 'Feb.', '03' => 'Mar.',
		  '04' => 'Apr.', '05' => 'May ', '06' => 'Jun.',
		  '07' => 'Jul.', '08' => 'Aug.', '09' => 'Sep.',
		  '10' => 'Oct.', '11' => 'Nov.', '12' => 'Dec.',
		  '21' => 'Spring', '22' => 'Summer',
		  '23' => 'Autumn', '24' => 'Winter' );

    @keys = @_;
    foreach my $i (0 .. @keys) {
	my $key = $keys[$i];
	my $capstr;
	my $chron;
	my $sep;

	last if !defined $caption->caption($key);

	$capstr = $caption->caption($key);
	if (substr($capstr,0,1) eq '(') {
	    # a caption enclosed in parentheses is not displayed
	    $capstr = '';
	}

	# If this is the second level of chronology, then it's
	# likely to be a month or season, so we should use the
	# string name rather than the number given.
	if (($i == 1) && exists $month{$self->{CHRON}->{$key}}) {
	    $chron = $month{$self->{CHRON}->{$key}};
	} else {
	    $chron = $self->{CHRON}->{$key};
	}


	$str .= (($i == 0 || $str =~ /[. ]$/) ? '' : ':') . $capstr . $chron;
    }

    return $str;
}

sub format {
    my $self = shift;
    my $caption = $self->{CAPTION};
    my $str = "";

    if ($caption->enumeration_is_chronology) {
	# if issues are identified by chronology only, then the
	# chronology data is stored in the enumeration subfields,
	# so format those fields as if they were chronological.
	$str = $self->format_chron('a'..'f');
    } else {
	# OK, there is enumeration data and maybe chronology
	# data as well, format both parts appropriately

	# Enumerations
	foreach my $key ('a'..'f') {
	    my $capstr;

	    last if !defined $caption->caption($key);

	    # 	printf("fmt %s: '%s'\n", $key, $caption->caption($key));

	    $capstr = $caption->caption($key);
	    if (substr($capstr, 0, 1) eq '(') {
		# a caption enclosed in parentheses is not displayed
		$capstr = '';
	    }
	    $str .= ($key eq 'a' ? "" : ':') . $capstr . $self->{ENUMS}->{$key}->{HOLDINGS};
	}

	# Chronology
	if (defined $caption->caption('i')) {
	    $str .= '(';
	    $str .= $self->format_chron('i'..'l');
	    $str .= ')';
	}

	if (exists $caption->{ENUMS}->{'g'}) {
	    # There's at least one level of alternative enumeration
	    $str .= '=';
	    foreach my $key ('g', 'h') {
		$str .= ($key eq 'g' ? '' : ':') . $caption->caption($key) . $self->{ENUMS}->{$key}->{HOLDINGS};
	    }

	    # This assumes that alternative chronology is only ever
	    # provided if there is an alternative enumeration.
	    if (exists $caption->{CHRONS}->{m}) {
		# Alternative Chronology
		$str .= '(';
		$str .= $caption->caption('m') . $self->{ENUMS}->{m}->{HOLDINGS};
		$str .= ')';
	    }
	}
    }

    # Public Note
    $str .= ' '. $caption->{ENUMS}->{'z'} if (defined $caption->caption('z'));

    # Breaks in the sequence
    if ($self->{BREAK} eq 'n') {
	$str .= ' non-gap break';
    } elsif ($self->{BREAK} eq 'g') {
	$str .= ' gap';
    } elsif ($self->{BREAK}) {
	warn "unrecognized break indicator '$self->{BREAK}'";
    }

    return $str;
}

sub next_date {
    my $self = shift;
    my $next = shift;
    my @keys = @_;

    my $caption = $self->{CAPTION};
}


# next: Given a holding statement, return a hash containing the 
# enumeration values for the next issues, whether we hold it or not
#
sub next {
    my $self = shift;
    my $caption = $self->{CAPTION};
    my $next = {};
    my $carry;

    # Initialize $next with current enumeration & chronology, then
    # we can just operate on $next, based on the contents of the caption
    foreach my $key ('a' .. 'h') {
	$next->{$key} = $self->{ENUMS}->{$key}->{HOLDINGS}
	  if exists $self->{ENUMS}->{$key};
    }

    foreach my $key ('i'..'m') {
	$next->{$key} = $self->{CHRON}->{$key}
	  if exists $self->{CHRON}->{$key};
    }

    if ($caption->enumeration_is_chronology) {
	$self->next_date($caption, $next, ('a'..'h'));
    } else {
	# First handle any "alternative enumeration", since they're
	# a lot simpler, and don't depend on the the calendar
	foreach my $key ('h', 'g') {
	    next if !exists $next->{$key};
	    if (!exists $caption->{ENUMS}->{$key}) {
		warn "Holding data exists for $key, but no caption specified";
		$next->{$key} += 1;
		last;
	    }

	    my $cap = $caption->{ENUMS}->{$key};
	    if ($cap->{RESTART} && $cap->{COUNT}
		&& ($next->{$key} == $cap->{COUNT})) {
		$next->{$key} = 1;
	    } else {
		$next->{$key} += 1;
		last;
	    }
	}

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
	foreach my $key (reverse('b'.. 'f')) {
	    next if !exists $next->{$key};
	    if (!exists $caption->{ENUMS}->{$key}) {
		# Just assume that it increments continuously and give up
		warn "Holding data exists for $key, but no caption specified";
		$next->{$key} += 1;
		$carry = 0;
		last;
	    }

	    my $cap = $caption->{ENUMS}->{$key};
	    if ($cap->{RESTART} && $cap->{COUNT}
		&& ($next->{$key} eq $cap->{COUNT})) {
		$next->{$key} = 1;
		$carry = 1;
	    } else {
		# If I don't need to "carry" beyond here, then I just increment
		# this level of the enumeration and stop looping, since the
		# "next" hash has been initialized with the current values

		# NOTE: This DOES NOT take into account the incrementing
		# of enumerations based on the calendar. (eg: The Economist)
		$next->{$key} += 1;
		$carry = 0;
		last;
	    }
	}

	# The easy part is done. There are two things left to do:
	# 1) Calculate the date of the next issue, if necessary
	# 2) Increment the highest level of enumeration (either by date
	#    or because $carry is set because of the above loop

	if (!%{$caption->{CHRONS}}) {
	    # The simple case: if there is no chronology specified
	    # then just check $carry and return
	    $next->{'a'} += $carry;
	} else {
	    # Figure out date of next issue, then decide if we need
	    # to adjust top level enumeration based on that
	    $self->next_date($caption, $next, ('i'..'m'));
	}
    }

    return($next);
}

# match($pat): check to see if $self matches the enumeration passed
# in as $pat. This is expected to be used in conjunction with the next()
# function defined above.
#
#
#
sub match {
    my $self = shift;
    my $pat = shift;
    my $caption = $self->{CAPTION};

    foreach my $key ('a'..'f') {
	my $nextkey;

	($nextkey = $key)++;
	# If the next smaller enumeration exists, and is numbered
	# continuously, then we don't need to check this one, because
	# gaps in issue numbering matter, not changes in volume numbering
	next if (exists $self->{ENUMS}->{$nextkey}
		 && !$caption->{ENUMS}->{$nextkey}->{RESTART});

	# If a subfield exists in $self but not in $pat, or vice versa
	# or if the field has different values, then fail
	if (exists($self->{ENUMS}->{$key}) != exists($pat->{$key})
	    || (exists $pat->{$key}
		&& ($self->{ENUMS}->{$key}->{HOLDINGS} ne $pat->{$key}))) {
	    return 0;
	}
    }
    return 1;
}

# 
# Check that all the fields in a holdings statement are
# included in the corresponding caption.
# 
sub validate {
    my $self = shift;

    foreach my $key (keys %{$self->{ENUMS}}) {
	if (!exists $self->{CAPTION}->{ENUMS}->{$key}) {
	    return 0;
	}
    }
    return 1;
}
1;
