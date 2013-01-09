package MFHD;
use strict;
use warnings;
use integer;
use Carp;
use DateTime::Format::Strptime;
use Data::Dumper;

# for inherited methods to work properly, we need to force a
# MARC::Record version greater than 2.0.0
use MARC::Record "2.0.1";
use base 'MARC::Record';

use OpenILS::Utils::MFHD::Caption;
use OpenILS::Utils::MFHD::Holding;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = shift;

    $self->{_strp_date} = new DateTime::Format::Strptime(pattern => '%F');

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

# optional argument to get back a 'hashref' or an 'array' (default)
sub captions {
    my $self  = shift;
    my $tag = shift;
    my $return_type = shift;

    # TODO: add support for caption types as argument? (base, index, supplement)
    my @sorted_ids = $self->caption_link_ids($tag);

    if (defined($return_type) and $return_type eq 'hashref') {
        my %captions;
        foreach my $link_id (@sorted_ids) {
            $captions{$link_id} = $self->{_mfhd_CAPTIONS}{$tag}{$link_id};
        }
        return \%captions;
    } else {
        my @captions;
        foreach my $link_id (@sorted_ids) {
            push(@captions, $self->{_mfhd_CAPTIONS}{$tag}{$link_id});
        }
        return @captions;
    }
}

sub append_fields {
    my $self = shift;

    my $field_count = $self->SUPER::append_fields(@_);
    if ($field_count) {
        foreach my $field (@_) {
            $self->_avoid_link_collision($field);
            my $field_type = ref $field;
            if ($field_type eq 'MFHD::Holding') {
                $self->{_mfhd_HOLDINGS}{$field->tag}{$field->caption->link_id}{$field->seqno} = $field;
            } elsif ($field_type eq 'MFHD::Caption') {
                $self->{_mfhd_CAPTIONS}{$field->tag}{$field->link_id} = $field;
            }
        }
        return $field_count;
    } else {
        return;
    }   
}

sub delete_field {
    my $self = shift;
    my $field = shift;

    my $field_count = $self->SUPER::delete_field($field);
    if ($field_count) {
        my $field_type = ref($field);
        if ($field_type eq 'MFHD::Holding') {
            delete($self->{_mfhd_HOLDINGS}{$field->tag}{$field->caption->link_id}{$field->seqno});
        } elsif ($field_type eq 'MFHD::Caption') {
            delete($self->{_mfhd_CAPTIONS}{$field->tag}{$field->link_id});
        }
        return $field_count;
    } else {
        return;
    }
}

sub insert_fields_before {
    my $self = shift;
    my $before = shift;

    my $field_count = $self->SUPER::insert_fields_before($before, @_);
    if ($field_count) {
        foreach my $field (@_) {
            $self->_avoid_link_collision($field);
            my $field_type = ref $field;
            if ($field_type eq 'MFHD::Holding') {
                $self->{_mfhd_HOLDINGS}{$field->tag}{$field->caption->link_id}{$field->seqno} = $field;
            } elsif ($field_type eq 'MFHD::Caption') {
                $self->{_mfhd_CAPTIONS}{$field->tag}{$field->link_id} = $field;
            }
        }
        return $field_count;
    } else {
        return;
    }
}

sub insert_fields_after {
    my $self = shift;
    my $after = shift;

    my $field_count = $self->SUPER::insert_fields_after($after, @_);
    if ($field_count) {
        foreach my $field (@_) {
            $self->_avoid_link_collision($field);
            my $field_type = ref $field;
            if ($field_type eq 'MFHD::Holding') {
                $self->{_mfhd_HOLDINGS}{$field->tag}{$field->caption->link_id}{$field->seqno} = $field;
            } elsif ($field_type eq 'MFHD::Caption') {
                $self->{_mfhd_CAPTIONS}{$field->tag}{$field->link_id} = $field;
            }
        }
        return $field_count;
    } else {
        return;
    }
}

sub _avoid_link_collision {
    my $self = shift;
    my $field = shift;

    my $fieldref = ref($field);
    if ($fieldref eq 'MFHD::Holding') {
        my $seqno = $field->seqno;
        my $changed_seqno = 0;
        if (exists($self->{_mfhd_HOLDINGS}{$field->tag}{$field->caption->link_id}{$seqno})) {
            $changed_seqno = 1;
            do {
                $seqno++;
            } while (exists($self->{_mfhd_HOLDINGS}{$field->tag}{$field->caption->link_id}{$seqno}));
        }
        $field->seqno($seqno) if $changed_seqno;
    } elsif ($fieldref eq 'MFHD::Caption') {
        my $link_id = $field->link_id;
        my $changed_link_id = 0;
        if (exists($self->{_mfhd_CAPTIONS}{$field->tag}{$link_id})) {
            $link_id++;
            $changed_link_id = 1;
            do {
                $link_id++;
            } while (exists($self->{_mfhd_CAPTIONS}{$field->tag}{$link_id}));
        }
        $field->link_id($link_id) if $changed_link_id;
    }
}

sub active_captions {
    my $self  = shift;
    my $tag = shift;

    # TODO: add support for caption types as argument? (basic, index, supplement)
    my @captions;
    my @active_captions;

    @captions = $self->captions($tag);

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

sub holdings_by_caption {
    my $self  = shift;
    my $caption = shift;

    my $htag    = $caption->tag;
    my $link_id = $caption->link_id;
    $htag =~ s/^85/86/;
    return $self->holdings($htag, $link_id);
}

sub _holding_date {
    my $self = shift;
    my $holding = shift;

    return $self->{_strp_date}->parse_datetime($holding->chron_to_date);
}

#
# generate_predictions()
# Accepts a hash ref of options initially defined as:
# base_holding : reference to the holding field to predict from
# num_to_predict : the number of issues you wish to predict
# OR
# end_holding : holding field ref, keep predicting until you meet or exceed it
# OR
# end_date : keep predicting until you exceed this
#
# The basic method is to first convert to a single holding if compressed, then
# increment the holding and save the resulting values to @predictions.
# 
# returns @predictions, an array of holding field refs (including end_holding
# if applicable but NOT base_holding)
# 
sub generate_predictions {
    my ($self, $options) = @_;

    my $base_holding   = $options->{base_holding};
    my $num_to_predict = $options->{num_to_predict};
    my $end_holding    = $options->{end_holding};
    my $end_date       = $options->{end_date};
    my $max_to_predict = $options->{max_to_predict} || 10000; # fail-safe

    if (!defined($base_holding)) {
        carp("Base holding not defined in generate_predictions, returning empty set");
        return ();
    }
    if ($base_holding->is_compressed) {
        carp("Ambiguous compressed base holding in generate_predictions, returning empty set");
        return ();
    }
    my $curr_holding = $base_holding->clone; # prevent side-effects
    
    my @predictions;
        
    if ($num_to_predict) {
        for (my $i = 0; $i < $num_to_predict; $i++) {
            push(@predictions, $curr_holding->increment->clone);
        }
    } elsif (defined($end_holding)) {
        $end_holding = $end_holding->clone; # prevent side-effects
        my $next_holding = $curr_holding->increment->clone;
        my $num_predicted = 0;
        while ($next_holding le $end_holding) {
            push(@predictions, $next_holding);
            $num_predicted++;
            if ($num_predicted >= $max_to_predict) {
                carp("Maximum prediction count exceeded");
                last;
            }
            $next_holding = $curr_holding->increment->clone;
        }
    } elsif (defined($end_date)) {
        my $next_holding = $curr_holding->increment->clone;
        my $num_predicted = 0;
        while ($self->_holding_date($next_holding) <= $end_date) {
            push(@predictions, $next_holding);
            $num_predicted++;
            if ($num_predicted >= $max_to_predict) {
                carp("Maximum prediction count exceeded");
                last;
            }
            $next_holding = $curr_holding->increment->clone;
        }
    }

    return @predictions;
}

#
# create an array of compressed holdings from all holdings for a given caption,
# compressing as needed
#
# Optionally you can skip sorting, but the resulting compression will be compromised
# if the current holdings are out of order
#
# TODO: gap marking, gap preservation
#
# TODO: some of this could be moved to the Caption object to allow for 
# decompression in the absense of an overarching MFHD object
#
sub get_compressed_holdings {
    my $self = shift;
    my $caption = shift;
    my $opts = shift;
    my $skip_sort = $opts->{'skip_sort'};

    # basic check for necessary pattern information
    if (!scalar keys %{$caption->pattern}) {
        carp "Cannot compress without pattern data, returning original holdings";
        return $self->holdings_by_caption($caption);
    }

    # make sure none are compressed (except for open-ended)
    my @decomp_holdings;
    if ($skip_sort) {
        @decomp_holdings = $self->get_decompressed_holdings($caption, {'skip_sort' => 1, 'passthru_open_ended' => 1});
    } else {
        # sort for best algorithm
        @decomp_holdings = $self->get_decompressed_holdings($caption, {'dedupe' => 1, 'passthru_open_ended' => 1});
    }

    return () if !@decomp_holdings;

    # if first holding is open-ended, it 'includes' all the rest, so return
    if ($decomp_holdings[0]->is_open_ended) {
        return ($decomp_holdings[0]);
    }

    my $runner = $decomp_holdings[0]->clone->increment;   
    my $curr_holding = shift(@decomp_holdings);
    $curr_holding = $curr_holding->clone;
    my $seqno = 1;
    $curr_holding->seqno($seqno);
    my @comp_holdings;
    foreach my $holding (@decomp_holdings) {
        if ($runner eq $holding) {
            $curr_holding->extend;
            $runner->increment;
        } elsif ($runner gt $holding) { # should not happen unless holding is not in series
            carp("Found unexpected holding, skipping");
        } elsif ($holding->is_open_ended) { # special case, as it will always be the last
            if ($runner eq $holding->clone->compressed_to_first) {
                $curr_holding->compressed_end();
            } else {
                push(@comp_holdings, $curr_holding);
                $curr_holding = $holding->clone;
                $seqno++;
                $curr_holding->seqno($seqno);
            }
            last;
        } else {
            push(@comp_holdings, $curr_holding);
            while ($runner le $holding) {
                # Here is where we used to get stuck in an infinite loop
                # until the "Don't know how to deal with frequency" was
                # elevated from a carp to a croak.
                $runner->increment;
            }
            $curr_holding = $holding->clone;
            $seqno++;
            $curr_holding->seqno($seqno);
        }
    }
    push(@comp_holdings, $curr_holding);

    return @comp_holdings;
}

#
# create an array of single holdings from all holdings for a given caption,
# decompressing as needed
#
# optional arguments:
#    skip_sort: do not sort the returned holdings
#    dedupe: remove any duplicate holdings from the set
#    passthru_open_ended: open-ended compressed holdings cannot be logically
#    decompressed (they are infinite); if set to true these holdings are passed
#    thru rather than skipped
# TODO: some of this could be moved to the Caption (and/or Holding) object to
# allow for decompression in the absense of an overarching MFHD object
#
sub get_decompressed_holdings {
    my $self = shift;
    my $caption = shift;
    my $opts = shift;
    my $skip_sort = $opts->{'skip_sort'};
    my $dedupe = $opts->{'dedupe'};
    my $passthru_open_ended = $opts->{'passthru_open_ended'};

    if ($dedupe and $skip_sort) {
        carp("Attempted deduplication without sorting, failure likely");
    }

    my @holdings = $self->holdings_by_caption($caption);

    return () if !@holdings;

    my @decomp_holdings;

    foreach my $holding (@holdings) {
        if (!$holding->is_compressed) {
            push(@decomp_holdings, $holding->clone);
        } elsif ($holding->is_open_ended) {
            if ($passthru_open_ended) {
                push(@decomp_holdings, $holding->clone);
            } else {
                carp("Open-ended holdings cannot be decompressed, skipping");
            }
        } else {
            my $base_holding = $holding->clone->compressed_to_first;
            my @new_holdings = $self->generate_predictions(
                {'base_holding' => $base_holding,
                 'end_holding' => $holding->clone->compressed_to_last});
            push(@decomp_holdings, $base_holding, @new_holdings);
        }
    }

    unless ($skip_sort) {
        my @temp_holdings = sort {$a cmp $b} @decomp_holdings;
        @decomp_holdings = @temp_holdings;
    }

    my @return_holdings = (shift(@decomp_holdings));
    $return_holdings[0]->seqno(1);
    my $seqno = 2;
    foreach my $holding (@decomp_holdings) { # renumber sequence
        if ($holding eq $return_holdings[-1] and $dedupe) {
            carp("Found duplicate holding in decompression set, discarding");
            next;
        }
        $holding->seqno($seqno);
        $seqno++;
        push(@return_holdings, $holding);
    }

    return @return_holdings;
}

##
## close any open-ended holdings which are followed by another holding by
## combining them
##
## This needs more thought about concerning usability (e.g. should it be a
## mutator?), commenting out for now
#sub _get_truncated_holdings {
#    my $self = shift;
#    my $caption = shift;
#
#    my @holdings = $self->holdings_by_caption($caption);
#
#    return () if !@holdings;
#
#    @holdings = sort {$a cmp $b} @holdings;
#    
#    my $current_open_holding;
#    my @truncated_holdings;
#    foreach my $holding (@holdings) {
#        if ($current_open_holding) {
#            if ($holding->is_open_ended) {
#                next; # consecutive open holdings are meaningless, as they are contained by the previous
#            } elsif ($holding->is_compressed) {
#                $current_open_holding->compressed_end($holding->compressed_to_last);
#            } else {
#                $current_open_holding->compressed_end($holding);
#            }
#            push(@truncated_holdings, $current_open_holding);
#            $current_open_holding = undef;
#        } elsif ($holding->is_open_ended) {
#            $current_open_holding = $holding;
#        } else {
#            push(@truncated_holdings, $holding);
#        }
#    }
#    
#    # catch possible open holding at end
#    push(@truncated_holdings, $current_open_holding) if $current_open_holding;
#
#    my $seqno = 1;
#    foreach my $holding (@truncated_holdings) { # renumber sequence
#        $holding->seqno($seqno);
#        $seqno++;
#    }
#
#    return @truncated_holdings;
#}

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
                my $txt = $txt_link_ids{$cap_id};
                $holdings_stmt .= ',' if $holdings_stmt;
                $holdings_stmt .= $txt->subfield('a');
                if (defined $txt->subfield('z')) {
                    $holdings_stmt .= ' -- ' . $txt->subfield('z');
                }

                $last_txt = $txt;
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
                    # this item is not part of the current run,
                    # close out the run and record this item
                    if ($l != $start) {
                        $holdings_stmt .= '-' . $l->format;
                    }

                    $holdings_stmt .= ',' . $h->format;
                    $start = $h
                } elsif (!scalar(@holdings) || defined($h->subfield('z'))) {
                    # This is the end of the holdings for this caption
                    # or this item has a public note that we want
                    # to display
                    $holdings_stmt .= '-' . $h->format;
                }

                if (defined $h->subfield('z')) {
                    $holdings_stmt .= ' -- ' . $h->subfield('z');
                }

                $l = $h;
            }
        } else {
            $holdings_stmt .= ',' if $holdings_stmt;
            $holdings_stmt .= (shift @holdings)->format;
            foreach my $h (@holdings) {
                $holdings_stmt .= ',' . $h->format;
                if (defined $h->subfield('z')) {
                    $holdings_stmt .= ' -- ' . $h->subfield('z');
                }
            }
        }
    }

    return $holdings_stmt;
}

1;
