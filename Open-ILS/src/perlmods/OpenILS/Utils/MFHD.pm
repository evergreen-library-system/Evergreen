package MFHD;
use strict;
use integer;
use Carp;

use MARC::Record;
use MFHD::Caption;
use MFHD::Holding;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};
    my $rec = shift;

    $self->{CAPTIONS} = {};
    foreach my $caption ($rec->field('853')) {
	my $cap_id;
	$cap_id = $caption->subfield('8') || '0';
	if (exists $self->{CAPTIONS}->{$cap_id}) {
	    carp "Multiple unlabelled MFHD captions";
	}
	$self->{CAPTIONS}->{$cap_id} = new MFHD::Caption($caption);
    }

    $self->{HOLDINGS} = {};
    foreach my $holding ($rec->field('863')) {
	my $linkage;
	my ($link_id, $seqno);

	$linkage = $holding->subfield('8');
	($link_id, $seqno) = split(/\./, $linkage);

	if (!exists $self->{HOLDINGS}->{$link_id}) {
	    $self->{HOLDINGS}->{$link_id} = {};
	}
	$self->{HOLDINGS}->{$link_id}->{$seqno} =
	  new MFHD::Holding($seqno, $holding, $self->{CAPTIONS}->{$link_id});
    }

    bless ($self, $class);
    return $self;
}

sub captions {
    my $self = shift;

    return sort keys %{$self->{CAPTIONS}}
}

sub holdings {
    my $self = shift;
    my $capid = shift;

    return sort {$a->{SEQNO} cmp $b->{SEQNO}} values %{$self->{HOLDINGS}->{$capid}};
}

1;
