package MFHD;
use strict;
use warnings;
use integer;
use Carp;
use DateTime::Format::Strptime;
use Data::Dumper;

use base 'MARC::Record';

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

#
# generate_predictions() is an initial attempt at a function which can be used
# to populate an issuance table with a list of predicted issues.  It accepts
# a hash ref of options initially defined as:
# field : the caption field to predict on (853, 854, or 855)
# num_to_predict : the number of issues you wish to predict
# last_rec_date : the date of the last received issue, to be used as an offset
#                 for predicting future issues
#
# The basic method is to first convert to a single holding if compressed, then
# increment the holding and save the resulting values to @predictions.
# 
# returns @preditions, an array of array refs containing (link id, formatted
# label, formatted chronology date, formatted estimated arrival date, and an
# array ref of holding subfields as (key, value, key, value ...)) (not a hash
# to protect order and possible duplicate keys).
#
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

        if ($last_holding->is_compressed) {
            $last_holding->compressed_to_last; # convert to last in range
        }

        my $pub_date  = $strp->parse_datetime($last_holding->chron_to_date);
        my $date_diff = $receival_date - $pub_date;

        $last_holding->notes('public',  []);
        # add a note marker for system use
        $last_holding->notes('private', ['AUTOGEN']);

        for (my $i = 0; $i < $num_to_predict; $i++) {
            $last_holding->increment;
            $pub_date = $strp->parse_datetime($last_holding->chron_to_date);
            my $arrival_date = $pub_date + $date_diff;
            push(
                @predictions,
                [
                    $link_id,
                    $last_holding->format,
                    $pub_date->strftime('%F'),
                    $arrival_date->strftime('%F'),
                    [$last_holding->subfields_list]
                ]
            );
        }
    }
    return @predictions;
}

#
# format_holdings(): Generate textual display of all holdings in record
# for given type of caption (853--855) taking into account all the
# captions, holdings statements, and textual
# holdings.
#
# returns string formatted holdings as one very long line.
# Caller must provide any label (such as "library has:" and insert
# line breaks as appropriate.

# Translate caption field labels to the corresponding textual holdings
# statement labels. That is, convert 853 "Basic bib unit" caption to
# 866 "basic bib unit" text holdings label.

my %cap_to_txt = (
                  '853' => '866',
                  '854' => '867',
                  '855' => '868',
                 );

sub format_holdings {
    my $self = shift;
    my $field = shift;
    my $holdings_field;
    my @txt_holdings;
    my %txt_link_ids;
    my $holdings_stmt = '';
    my ($l, $start);

    # convert caption field id to holdings field id
    ($holdings_field = $field) =~ s/5/6/;

    # Textual holdings statements complicate the basic algorithm for
    # formatting the holdings: If there's a textual holdings statement
    # with the subfield "$80", then that overrides ALL the MFHD holdings
    # information and is all that is displayed. Otherwise, the textual
    # holdings statements will either replace some of the MFHD holdings
    # information, or supplement it, depending on the value of the
    # $8 linkage subfield.

    if (defined $self->field($cap_to_txt{$field})) {
        @txt_holdings = $self->field($cap_to_txt{$field});

        foreach my $txt (@txt_holdings) {

            # if there's a $80 subfield, then we're done, it's
            # all the formatted holdings
            if ($txt->subfield('8') eq '0') {
                # textual holdings statement that completely
                # replaces MFHD holdings in 853/863, etc.
                $holdings_stmt = $txt->subfield('a');

                if (defined $txt->subfield('z')) {
                    $holdings_stmt .= ' -- ' . $txt->subfield('z');
                }

                printf("# format_holdings() returning %s txt holdings\n",
                       $cap_to_txt{$field});
                return $holdings_stmt;
            }

            # If there are non-$80 subfields in the textual holdings
            # then we need to keep track of the subfields, so we can
            # intersperse the textual holdings in with the the calculated
            # holdings from the 853/863 fields.
            foreach my $linkid ($txt->subfield('8')) {
                $txt_link_ids{$linkid} = $txt;
            }
        }
    }

    # Now loop through all the captions, finding the corresponding
    # holdings statements (either MFHD or textual), and build up the
    # complete formatted holdings statement. The textual holdings statements
    # have either the same link id field as a caption, which means that
    # the text holdings win, or they have ids that are interfiled with
    # the captions, which mean they go into the middle.

    my @ids = sort($self->caption_link_ids($field), keys %txt_link_ids);
    foreach my $cap_id (@ids) {
        my $last_txt = undef;

        if (exists $txt_link_ids{$cap_id}) {
            # there's a textual holding statement with this caption ID,
            # so just use that. This covers both the "replaces" and
            # the "supplements" holdings information options.

            # a single textual holdings statement can replace multiple
            # captions. If the _last_ caption we saw had a textual
            # holdings statement, and this caption has the same one, then
            # we don't add the holdings again.
            if (!defined $last_txt || ($last_txt != $txt_link_ids{$cap_id})) {
                $holdings_stmt .= ',' if $holdings_stmt;
                $holdings_stmt .= $txt_link_ids{$cap_id}->subfield('a');
                $last_txt = $txt_link_ids{$cap_id};
            }
            next;
        }

        # We found a caption that doesn't have a corresponding textual
        # holdings statement, so reset $last_txt to undef.
        $last_txt = undef;

        my @holdings = $self->holdings($holdings_field, $cap_id);

        next unless scalar @holdings;

        # XXX Need to format compressed holdings. see code in test.pl
        # for example. Try to do it without indexing?
        $holdings_stmt .= ',' if $holdings_stmt;

        if ($self->compressible) {
            $start = $l = shift @holdings;
            $holdings_stmt .= $l->format;

            while (my $h = shift @holdings) {
                if (!$h->matches($l->next)) {
                    # this item is not part of the current run
                    # close out the run and record this item
                    if ($l != $start) {
                        $holdings_stmt .= '-' . $l->format;
                    }

                    $holdings_stmt .= ',' . $h->format;
                    $start = $h
                } elsif (!scalar(@holdings)) {
                    # This is the end of the holdings for this caption
                    $holdings_stmt .= '-' . $h->format;
                }

                $l = $h;
            }
        } else {
            $holdings_stmt .= ',' if $holdings_stmt;
            $holdings_stmt .= (shift @holdings)->format;
            foreach my $h (@holdings) {
                $holdings_stmt .= ',' . $h->format;
            }
        }
    }

    return $holdings_stmt;
}

1;
