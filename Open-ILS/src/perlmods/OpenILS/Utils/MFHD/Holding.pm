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
		carp "Holding specified enumeration level '$key' not included in caption $caption->{LINK}";
	    }
	} elsif ($key eq 'o') {
	    carp '$o specified prior to first enumeration'
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

    return $str;
}

sub next {
    my $self = shift;
    my $caption = $self->{CAPTION};
}

1;
