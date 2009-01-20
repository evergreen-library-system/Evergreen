package MFHD::Caption;
use strict;
use integer;
use Carp;

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

1;
