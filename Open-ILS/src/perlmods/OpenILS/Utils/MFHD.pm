package MFHD;
use strict;
use warnings;
use integer;
use Carp;
use DateTime::Format::Strptime;
use Data::Dumper;

use base 'MARC::Record';

# use OpenSRF::Utils::JSON;
use OpenILS::Utils::MFHD::Caption;
use OpenILS::Utils::MFHD::Holding;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = shift;

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
                $self->{_mfhd_COMPRESSIBLE} &&=
                  $captions->{$cap_id}->compressible;
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
            $holding =
              new MFHD::Holding($seqno, $hfield,
                $self->{_mfhd_CAPTIONS}->{$cap_field}->{$link_id});
            $holdings->{$link_id}->{$seqno} = $holding;

            if ($self->{_mfhd_COMPRESSIBLE}) {
                $self->{_mfhd_COMPRESSIBLE} &&= $holding->validate;
            }
        }
        $self->{_mfhd_HOLDINGS}->{$field} = $holdings;
    }

    bless($self, $class);
    return $self;
}

sub compressible {
    my $self = shift;

    return $self->{_mfhd_COMPRESSIBLE};
}

sub caption_link_ids {
    my $self  = shift;
    my $field = shift;

    return sort keys %{$self->{_mfhd_CAPTIONS}->{$field}};
}

sub captions {
    my $self  = shift;
    my $field = shift;

    # TODO: add support for caption types as argument? (base, index, supplement)
    my @captions;
    my @sorted_ids = $self->caption_link_ids($field);

    foreach my $link_id (@sorted_ids) {
        push(@captions, $self->{_mfhd_CAPTIONS}{$field}{$link_id});
    }

    return @captions;
}

sub active_captions {
    my $self  = shift;
    my $field = shift;

    # TODO: add support for caption types as argument? (base, index, supplement)
    my @captions;
    my @active_captions;

    @captions = $self->captions($field);

    # TODO: for now, we will assume the last 85X field is active
    # and the rest are historical.  The standard is hazy about
    # how multiple active patterns of the same 85X type should be
    # handled.  We will, however, return as an array for future
    # use.
    push(@active_captions, $captions[-1]);

    return @active_captions;
}

sub holdings {
    my $self  = shift;
    my $field = shift;
    my $capid = shift;

    return
      sort { $a->seqno <=> $b->seqno }
      values %{$self->{_mfhd_HOLDINGS}->{$field}->{$capid}};
}

sub generate_predictions {
    my ($self, $options) = @_;
    my $field          = $options->{field};
    my $num_to_predict = $options->{num_to_predict};
    my $last_rec_date =
      $options->{last_rec_date};   # expected or actual, according to preference

    # TODO: add support for predicting serials with no chronology by passing in
    # a last_pub_date option?

    my $strp = new DateTime::Format::Strptime(pattern => '%F');

    my $receival_date = $strp->parse_datetime($last_rec_date);

    my @active_captions = $self->active_captions($field);

    my @predictions;
    foreach my $caption (@active_captions) {
        my $htag    = $caption->tag;
        my $link_id = $caption->link_id;
        $htag =~ s/^85/86/;
        my @holdings = $self->holdings($htag, $link_id);
        my $last_holding = $holdings[-1];

        my $pub_date  = $strp->parse_datetime($last_holding->chron_to_date);
        my $date_diff = $receival_date - $pub_date;

        $last_holding->notes('public',  []);
        $last_holding->notes('private', ['AUTOGEN']);

        for (my $i = 0; $i < $num_to_predict; $i++) {
            $last_holding->increment;
            $pub_date = $strp->parse_datetime($last_holding->chron_to_date);
            $pub_date = $pub_date + $date_diff;
            push(
                @predictions,
                [
                    $link_id,
                    $last_holding->format,
                    $pub_date->strftime('%F'),
#                     OpenSRF::Utils::JSON->perl2JSON(
#                         [$last_holding->subfields_list]
#                     )
                ]
            );
        }
    }
    return @predictions;
}

1;
