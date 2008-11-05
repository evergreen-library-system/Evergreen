package MFHD;
use strict;
use integer;
use Carp;
use Data::Dumper;

use MARC::Record;
use MFHD::Caption;
use MFHD::Holding;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};
    my $rec = shift;

    $self->{RECORD} = $rec;
    $self->{CAPTIONS} = {};

    foreach my $field ('853', '854', '855') {
	my $captions = {};
	foreach my $caption ($rec->field($field)) {
	    my $cap_id;

	    $cap_id = $caption->subfield('8') || '0';
	    if (exists $captions->{$cap_id}) {
		carp "Multiple unlabelled MFHD captions";
	    }
	    $captions->{$cap_id} = new MFHD::Caption($caption);
	}
	$self->{CAPTIONS}->{$field} = $captions;
    }

    foreach my $field ('863', '864', '865') {
	my $holdings = {};
	my $cap_field;

	($cap_field = $field) =~ s/6/5/;

	foreach my $holding ($rec->field($field)) {
	    my $linkage;
	    my ($link_id, $seqno);

	    $linkage = $holding->subfield('8');
	    ($link_id, $seqno) = split(/\./, $linkage);

	    if (!exists $holdings->{$link_id}) {
		$holdings->{$link_id} = {};
	    }
	    $holdings->{$link_id}->{$seqno} =
	      new MFHD::Holding($seqno, $holding, $self->{CAPTIONS}->{$cap_field}->{$link_id});
	}
	$self->{HOLDINGS}->{$field} = $holdings;
    }

    bless ($self, $class);
    return $self;
}

# 
# validate_captions: confirm that fields specified for holdings
# data all have captions assigned to them
# 
sub validate_captions {
    my $self = shift;

    foreach my $cap_fieldno ('853' .. '855') {
	foreach my $cap_id ($self->captions($cap_fieldno)) {
	    my $enum_fieldno;
	    ($enum_fieldno = $cap_fieldno) =~ s/5/6/;
	    foreach my $enum ($self->holdings($enum_fieldno, $cap_id)) {
		foreach my $key (keys %{$enum->{ENUMS}}) {
		    if (!exists $enum->{CAPTION}->{ENUMS}->{$key}) {
			print "$key doesn't exist: ", Dumper($enum);
			return 0;
		    }
		}
	    }
	}
	return 1;
    }
}

sub compressible {
    my $self = shift;
    my $leader = $self->{RECORD}->leader;
    my $holdings_level = substr($leader, 17, 1);

    # Can only compress level 4 detailed holdings
    # or detailed holdings with piece designation
    return 0 unless (($holdings_level == 4) || ($holdings_level = 5));

    # Can only compress if fields specified in each enumeration are
    # defined in the corresponding caption
    return 0 unless $self->validate_captions;

    return 1;
}

sub captions {
    my $self = shift;
    my $field = shift;

    return sort keys %{$self->{CAPTIONS}->{$field}}
}

sub holdings {
    my $self = shift;
    my $field = shift;
    my $capid = shift;

    return sort {$a->{SEQNO} <=> $b->{SEQNO}} values %{$self->{HOLDINGS}->{$field}->{$capid}};
}

1;
