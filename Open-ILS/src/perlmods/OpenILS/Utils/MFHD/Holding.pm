package MFHD::Holding;
use strict;
use integer;
use Carp;

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

sub format {
    my $self = shift;
    my $caption = $self->{CAPTION};
    my $str = "";

    foreach my $key ('a'..'f') {
	last if !exists $caption->{ENUMS}->{$key};
# 	printf("fmt %s: '%s'\n", $key, $caption->caption($key));

	$str .= ($key eq 'a' ? "" : ':') . $caption->caption($key) . $self->{ENUMS}->{$key}->{HOLDINGS};
    }

    if (exists $caption->{ENUMS}->{'g'}) {
	# There's at least one level of alternative enumeration
	$str .= ' ';
	foreach my $key ('g', 'h') {
	    $str .= ($key eq 'g' ? '' : ':') . $caption->enum($key) . $self->{ENUMS}->{$key}->{HOLDINGS};
	}
    }

    # Public Note
    $str .= ' '. $caption->{ENUMS}->{'z'} if (exists $caption->{ENUMS}->{'z'});

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

# next: Given a holding statement, return a hash containing the 
# enumeration values for the next issues, whether we hold it or not
#
sub next {
    my $self = shift;
    my $caption = $self->{CAPTION};
    my $next = {};

    foreach my $key ('a' .. 'h') {
	next if !exists $self->{ENUMS}->{$key};
	$next->{$key} = $self->{ENUMS}->{$key}->{HOLDINGS};
    }

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
    foreach my $key (reverse('a'.. 'f')) {
	next if !exists $next->{$key};
	if (!exists $caption->{ENUMS}->{$key}) {
	    # Just assume that it increments continuously and give up
	    warn "Holding data exists for $key, but no caption specified";
	    $next->{$key} += 1;
	    last;
	}

	my $cap = $caption->{ENUMS}->{$key};
	if ($cap->{RESTART} && $cap->{COUNT}
	    && ($next->{$key} eq $cap->{COUNT})) {
	    $next->{$key} = 1;
	    # I increment the next higher level of enumeration by continuing
	    # the loop.
	} else {
	    # If I don't need to "carry" beyond here, then I just increment
	    # this level of the enumeration and stop looping, since the
	    # "next" hash has been initialized with the current values

	    # NOTE: This DOES NOT take into account the incrementing
	    # of enumerations based on the calendar. (eg: The Economist)
	    $next->{$key} += 1;
	    last;
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

    foreach my $key ('a'..'f') {
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

1;
