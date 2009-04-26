package OpenILS::Utils::MFHD;
use strict;
use integer;
use Carp;
use Data::Dumper;

use base 'MARC::Record';

use OpenILS::Utils::MFHD::Caption;
use OpenILS::Utils::MFHD::Holding;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = shift;

    $self->{_mfhd_CAPTIONS} = {};
    $self->{_mfhd_COMPRESSIBLE} = (substr($self->leader, 17, 1) =~ /[45]/);

    foreach my $field ('853', '854', '855') {
	my $captions = {};
	foreach my $caption ($self->field($field)) {
	    my $cap_id;

	    $cap_id = $caption->subfield('8') || '0';

	    if (exists $captions->{$cap_id}) {
		carp "Multiple MFHD captions with label '$cap_id'";
	    }

	    $captions->{$cap_id} = new MFHD::Caption($caption);
	    if ($self->{_mfhd_COMPRESSIBLE}) {
		$self->{_mfhd_COMPRESSIBLE} &&= $captions->{$cap_id}->compressible;
	    }
	}
	$self->{_mfhd_CAPTIONS}->{$field} = $captions;
    }

    foreach my $field ('863', '864', '865') {
	my $holdings = {};
	my $cap_field;

	($cap_field = $field) =~ s/6/5/;

	foreach my $hfield ($self->field($field)) {
	    my ($linkage, $link_id, $seqno);
	    my $holding;

	    $linkage = $hfield->subfield('8');
	    ($link_id, $seqno) = split(/\./, $linkage);

	    if (!exists $holdings->{$link_id}) {
		$holdings->{$link_id} = {};
	    }
	    $holding = new MFHD::Holding($seqno, $hfield,
					 $self->{_mfhd_CAPTIONS}->{$cap_field}->{$link_id});
	    $holdings->{$link_id}->{$seqno} = $holding;

	    if ($self->{_mfhd_COMPRESSIBLE}) {
		$self->{_mfhd_COMPRESSIBLE} &&= $holding->validate;
	    }
	}
	$self->{_mfhd_HOLDINGS}->{$field} = $holdings;
    }

    bless ($self, $class);
    return $self;
}

sub compressible {
    my $self = shift;

    return $self->{_mfhd_COMPRESSIBLE};
}

sub captions {
    my $self = shift;
    my $field = shift;

    return sort keys %{$self->{_mfhd_CAPTIONS}->{$field}}
}

sub holdings {
    my $self = shift;
    my $field = shift;
    my $capid = shift;

    return sort {$a->seqno <=> $b->seqno} values %{$self->{_mfhd_HOLDINGS}->{$field}->{$capid}};
}

1;
