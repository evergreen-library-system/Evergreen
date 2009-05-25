package MFHD::Holding;
use strict;
use integer;
use Carp;

use DateTime;

use Data::Dumper;

use base 'MARC::Field';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $seqno = shift;
    my $self = shift;
    my $caption = shift;
    my $last_enum = undef;

    $self->{_mfhdh_SEQNO} = $seqno;
    $self->{_mfhdh_CAPTION} = $caption;
    $self->{_mfhdh_DESCR} = {};
    $self->{_mfhdh_COPY} = undef;
    $self->{_mfhdh_BREAK} = undef;
    $self->{_mfhdh_NOTES} = {};
    $self->{_mfhdh_COPYRIGHT} = [];

    foreach my $subfield ($self->subfields) {
	my ($key, $val) = @$subfield;

	if (($caption && $caption->enumeration_is_chronology && $key =~ /[a-h]/) || $key =~ /[i-m]/) {
	    # Chronology
	    $self->{_mfhdh_SUBFIELDS}->{$key} = $val;
	} elsif ($key =~ /[a-h]/) {
	    # Enumeration details of holdings
	    $self->{_mfhdh_SUBFIELDS}->{$key} = {HOLDINGS => $val,
						 UNIT     => undef,};
	    $last_enum = $key;
	} elsif ($key =~ /[i-m]/) {
	} elsif ($key eq 'o') {
	    warn '$o specified prior to first enumeration'
	      unless defined($last_enum);
	    $self->{_mfhdh_SUBFIELDS}->{$last_enum}->{UNIT} = $val;
	    $last_enum = undef;
	} elsif ($key =~ /[npq]/) {
	    $self->{_mfhdh_DESCR}->{$key} = $val;
	} elsif ($key eq 's') {
	    push @{$self->{_mfhdh_COPYRIGHT}}, $val;
	} elsif ($key eq 't') {
	    $self->{_mfhdh_COPY} = $val;
	} elsif ($key eq 'w') {
	    carp "Unrecognized break indicator '$val'"
	      unless $val =~ /^[gn]$/;
	    $self->{_mfhdh_BREAK} = $val;
	}
    }

    bless ($self, $class);
    return $self;
}

sub seqno {
    my $self = shift;

    return $self->{_mfhdh_SEQNO};
}

sub caption {
    my $self = shift;

    return $self->{_mfhdh_CAPTION};
}

sub format_chron {
    my $self = shift;
    my $caption = $self->{_mfhdh_CAPTION};
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

	last if !defined $caption->capstr($key);

	$capstr = $caption->capstr($key);
	if (substr($capstr,0,1) eq '(') {
	    # a caption enclosed in parentheses is not displayed
	    $capstr = '';
	}

	# If this is the second level of chronology, then it's
	# likely to be a month or season, so we should use the
	# string name rather than the number given.
	if (($i == 1) && exists $month{$self->{_mfhdh_SUBFIELDS}->{$key}}) {
	    $chron = $month{$self->{_mfhdh_SUBFIELDS}->{$key}};
	} else {
	    $chron = $self->{_mfhdh_SUBFIELDS}->{$key};
	}


	$str .= (($i == 0 || $str =~ /[. ]$/) ? '' : ':') . $capstr . $chron;
    }

    return $str;
}

sub format {
    my $self = shift;
    my $caption = $self->{_mfhdh_CAPTION};
    my $str = '';

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
	    my $chron;
	    my $sep;

	    last if !defined $caption->capstr($key);

	    $capstr = $caption->capstr($key);
	    if (substr($capstr, 0, 1) eq '(') {
		# a caption enclosed in parentheses is not displayed
		$capstr = '';
	    }
	    $str .= ($key eq 'a' ? '' : ':') . $capstr . $self->{_mfhdh_SUBFIELDS}->{$key}->{HOLDINGS};
	}

	# Chronology
	if (defined $caption->capstr('i')) {
	    $str .= '(';
	    $str .= $self->format_chron('i'..'l');
	    $str .= ')';
	}

	if ($caption->capstr('g')) {
	    # There's at least one level of alternative enumeration
	    $str .= '=';
	    foreach my $key ('g', 'h') {
		$str .= ($key eq 'g' ? '' : ':') . $caption->capstr($key) . $self->{_mfhdh_SUBFIELDS}->{$key}->{HOLDINGS};
	    }

	    # This assumes that alternative chronology is only ever
	    # provided if there is an alternative enumeration.
	    if ($caption->capstr('m')) {
		# Alternative Chronology
		$str .= '(';
		$str .= $caption->capstr('m') . $self->{_mfhdh_SUBFIELDS}->{m}->{HOLDINGS};
		$str .= ')';
	    }
	}
    }

    # Public Note
    $str .= ' '. $caption->capstr('z') if (defined $caption->capstr('z'));

    # Breaks in the sequence
    if (defined($self->{_mfhdh_BREAK})) {
        if ($self->{_mfhdh_BREAK} eq 'n') {
            $str .= ' non-gap break';
        } elsif ($self->{_mfhdh_BREAK} eq 'g') {
            $str .= ' gap';
        } else {
            warn "unrecognized break indicator '$self->{_mfhdh_BREAK}'";
        }
    }

    return $str;
}


# next: Given a holding statement, return a hash containing the
# enumeration values for the next issues, whether we hold it or not
# Just pass through to Caption::next
#
sub next {
    my $self = shift;
    my $caption = $self->{_mfhdh_CAPTION};

    return $caption->next($self);
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
    my $caption = $self->{_mfhdh_CAPTION};

    foreach my $key ('a'..'f') {
	my $nextkey;

	($nextkey = $key)++;
	# If the next smaller enumeration exists, and is numbered
	# continuously, then we don't need to check this one, because
	# gaps in issue numbering matter, not changes in volume numbering
	next if (exists $self->{_mfhdh_SUBFIELDS}->{$nextkey}
		 && !$caption->capfield($nextkey)->{RESTART});

	# If a subfield exists in $self but not in $pat, or vice versa
	# or if the field has different values, then fail
	if (exists($self->{_mfhdh_SUBFIELDS}->{$key}) != exists($pat->{$key})
	    || (exists $pat->{$key}
		&& ($self->{_mfhdh_SUBFIELDS}->{$key}->{HOLDINGS} ne $pat->{$key}))) {
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

    foreach my $key (keys %{$self->{_mfhdh_SUBFIELDS}}) {
	if (!$self->{_mfhdh_CAPTION} || !$self->{_mfhdh_CAPTION}->capfield($key)) {
	    return 0;
	}
    }
    return 1;
}
1;
