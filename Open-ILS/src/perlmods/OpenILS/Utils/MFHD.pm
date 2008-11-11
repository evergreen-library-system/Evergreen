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
    $self->{COMPRESSIBLE} = (substr($rec->leader, 17, 1) =~ /[45]/);

    foreach my $field ('853', '854', '855') {
	my $captions = {};
	foreach my $caption ($rec->field($field)) {
	    my $cap_id;

	    $cap_id = $caption->subfield('8') || '0';
	    if (exists $captions->{$cap_id}) {
		carp "Multiple unlabelled MFHD captions";
	    }
	    $captions->{$cap_id} = new MFHD::Caption($caption);
	    if ($self->{COMPRESSIBLE}) {
		$self->{COMPRESSIBLE} &&= $captions->{$cap_id}->compressible;
	    }
	}
	$self->{CAPTIONS}->{$field} = $captions;
    }

    foreach my $field ('863', '864', '865') {
	my $holdings = {};
	my $cap_field;

	($cap_field = $field) =~ s/6/5/;

	foreach my $hfield ($rec->field($field)) {
	    my $linkage;
	    my ($link_id, $seqno);
	    my $holding;

	    $linkage = $hfield->subfield('8');
	    ($link_id, $seqno) = split(/\./, $linkage);

	    if (!exists $holdings->{$link_id}) {
		$holdings->{$link_id} = {};
	    }
	    $holding = new MFHD::Holding($seqno, $hfield,
					 $self->{CAPTIONS}->{$cap_field}->{$link_id});
	    $holdings->{$link_id}->{$seqno} = $holding;

	    if ($self->{COMPRESSIBLE}) {
		$self->{COMPRESSIBLE} &&= $holding->validate;
	    }
	}
	$self->{HOLDINGS}->{$field} = $holdings;
    }

    bless ($self, $class);
    return $self;
}

sub compressible {
    my $self = shift;

    return $self->{COMPRESSIBLE};
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
