# ---------------------------------------------------------------
# Copyright (C) 2016 King County Library System
# Author: Bill Erickson <berickxx@gmail.com>
#
# Copied heavily from Application/Trigger/Reactor.pm
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------
package OpenILS::Utils::EDIWriter;
use strict; use warnings;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Application::AppUtils;
use DateTime;
my $U = 'OpenILS::Application::AppUtils';

sub new {
    my ($class, $args) = @_;
    $args ||= {};
    return bless($args, $class);
}

# Returns EDI string on success, undef on error.
sub write {
    my ($self, $po_id, $msg_type) = @_;
    $msg_type ||= 'order';

    my $po = $self->get_po($po_id);
    return undef unless $po;

    $self->compile_po($po);
    return undef unless $self->{compiled};

    my $edi = $self->build_order_edi if $msg_type eq 'order';

    # remove the newlines unless we are pretty printing
    $edi =~ s/\n//g unless $self->{pretty};

    return $edi;
}

sub get_po {
    my ($self, $po_id) = @_;
    return new_editor()->retrieve_acq_purchase_order([
        $po_id, {
            flesh => 5,
            flesh_fields => {
                acqpo   => [qw/lineitems ordering_agency provider/],
                acqpro  => [qw/edi_default/],
                acqedi  => [qw/attr_set/],
                aeas    => [qw/attr_maps/],
                jub     => [qw/lineitem_details lineitem_notes attributes/],
                acqlid  => [qw/owning_lib location fund eg_copy_id/],
                acp     => [qw/location call_number/],
                aou     => [qw/mailing_address/]
            }
        }
    ]);
}

sub add_release_characters {
    my ($self, $value) = @_;
    return '' if (not defined $value || ref($value));

    # escape ? ' + : with the release character ?
    $value =~ s/([\?'\+:])/?$1/g;

    return $value;
}
sub escape_edi_imd {
    my ($self, $value) = @_;
    return '' if (not defined $value || ref($value));

    # Typical vendors dealing with EDIFACT (or is the problem with
    # our EDI translator itself?) would seem not to want
    # any characters outside the ASCII range, so trash them.
    $value =~ s/[^[:ascii:]]//g;

    # What the heck, get rid of [ ] too (although I couldn't get them
    # to cause any problems for me, problems have been reported. See
    # LP #812593).
    $value =~ s/[\[\]]//g;

    # Characters [\ <newline>] are all potentially problematic for 
    # EDI messages, regardless of their position in the string.
    # Safest to simply remove them. Note that unlike escape_edi(),
    # we're not stripping out +, ', :, and + because we'll escape
    # them when buidling IMD segments
    $value =~ s/[\\]//g;

    # Replace newlines with spaces.
    $value =~ s/\n/ /g;

    return $value;
}
sub escape_edi {
    my ($self, $value) = @_;

    my $str = $self->escape_edi_imd($value);

    # further strip + ' : +
    $str =~ s/[\?\+':]//g;

    return $str;
}

# Returns an EDI-escaped version of the requested lineitem attribute
# value.  If $attr_type is not set, the first attribute found matching 
# the requested $attr_name will be used.
sub get_li_attr {
    my ($self, $li, $attr_name, $attr_type) = @_;

    for my $attr (@{$li->attributes}) {
        next unless $attr->attr_name eq $attr_name;
        next if $attr_type && $attr->attr_type ne $attr_type;
        return $self->escape_edi($attr->attr_value);
    }

    return '';
}

# Like get_li_attr, but don't strip out ? + : ' as we'll
# escape them later
sub get_li_attr_imd {
    my ($self, $li, $attr_name, $attr_type) = @_;

    for my $attr (@{$li->attributes}) {
        next unless $attr->attr_name eq $attr_name;
        next if $attr_type && $attr->attr_type ne $attr_type;
        return $self->escape_edi_imd($attr->attr_value);
    }

    return '';
}

# Generates a HASH version of the PO with all of the data necessary
# to generate an EDI message from the PO.
sub compile_po {
    my ($self, $po) = @_;

    # Cannot generate EDI if the PO has no linked EDI account.
    return undef unless $po->provider->edi_default;

    my %compiled = (
        po_id => $po->id,
        po_name => $self->escape_edi($po->name),
        provider_id => $po->provider->id,
        vendor_san => $po->provider->san || '',
        org_unit_san => defined($po->ordering_agency->mailing_address) ? ($po->ordering_agency->mailing_address->san || '') : '',
        currency_type => $po->provider->currency_type,
        edi_attrs => {},
        lineitems => []
    );

    $self->{compiled} = \%compiled;
    
    if ($po->provider->edi_default->attr_set) {
        $compiled{edi_attrs}{$_->attr} = 1 
            for @{$po->provider->edi_default->attr_set->attr_maps}
    }

    $compiled{buyer_code} = $po->provider->edi_default->vendacct;

    $compiled{buyer_code} = # B&T
        $compiled{org_unit_san}.' '.$po->provider->edi_default->vendcode
        if $compiled{edi_attrs}->{BUYER_ID_INCLUDE_VENDCODE};

    $compiled{buyer_code} = $po->provider->edi_default->vendcode
        if $compiled{edi_attrs}->{BUYER_ID_ONLY_VENDCODE}; # MLS

    push(@{$compiled{lineitems}}, 
        $self->compile_li($_)) for @{$po->lineitems};

    return \%compiled;
}

# Translate a lineitem order identifier attribute into an 
# EDI ID value and ID qualifier.
sub set_li_order_ident {
    my ($self, $li, $li_hash) = @_;

    my $idqual = 'EN'; # ISBN13
    my $idval = '';

    if ($self->{compiled}->{edi_attrs}->{LINEITEM_IDENT_VENDOR_NUMBER}) {
        # See if we have a vendor-specific lineitem identifier value
        $idval = $self->get_li_attr($li, 'vendor_num');
    }

    if (!$idval) {

        my $attr = $self->get_li_order_ident_attr($li->attributes);

        if ($attr) {
            my $name = $attr->attr_name;
            $idval = $attr->attr_value;

            if ($name eq 'isbn' && length($idval) != 13) {
                $idqual = 'IB';
            } elsif ($name eq 'issn') {
                $idqual = 'IS';
            }
        } else {
            $idqual = 'IN';
            $idval = $li->id;
        }
    }

    $li_hash->{idqual} = $idqual;
    $li_hash->{idval} = $idval;
}

# Find the acq.lineitem_attr object that represents the identifier 
# for a lineitem.
sub get_li_order_ident_attr {
    my ($self, $attrs) = @_;

    # preferred identifier
    my ($attr) =  grep { $U->is_true($_->order_ident) } @$attrs;
    return $attr if $attr;

    # note we're not using get_li_attr, since we need the 
    # attr object and not just the attr value

    # isbn-13
    ($attr) = grep { 
        $_->attr_name eq 'isbn' and 
        $_->attr_type eq 'lineitem_marc_attr_definition' and
        length($_->attr_value) == 13
    } @$attrs;
    return $attr if $attr;

    for my $name (qw/isbn issn upc/) {
        ($attr) = grep { 
            $_->attr_name eq $name and 
            $_->attr_type eq 'lineitem_marc_attr_definition'
        } @$attrs;
        return $attr if $attr;
    }

    # any 'identifier' attr
    return (grep { $_->attr_name eq 'identifier' } @$attrs)[0];
}

# Collect FTX notes and chop them into FTX-compatible values.
sub get_li_ftx {
    my ($self, $li) = @_;

    # all vendor-public, non-empty lineitem notes
    my @notes = 
        map {$_->value} 
        grep { $U->is_true($_->vendor_public) && $_->value } 
        @{$li->lineitem_notes};

    if ($self->{compiled}->{edi_attrs}->{COPY_SPEC_CODES}) {
        for my $lid (@{$li->lineitem_details}) {
            push(@notes, $lid->note) 
                if ($lid->note || '') =~ /spec code [a-zA-Z0-9_]/;
        }
    }

    my @trimmed_notes;

    if (!@notes && $self->{compiled}->{edi_attrs}->{INCLUDE_EMPTY_LI_NOTE}) {
        # lineitem has no notes.  Add a blank note if needed.
        push(@trimmed_notes, '');

    } else {
        # EDI FTX fields have a max length of 512
        # While we're in here, EDI-escape the note values
        for my $note (@notes) {
            $note = $self->escape_edi($note);
            my @parts = ($note =~ m/.{1,512}/g);
            push(@trimmed_notes, @parts);
        }
    }

    return \@trimmed_notes;
}

sub compile_li {
    my ($self, $li) = @_;

    my $li_hash = {
        id => $li->id,
        quantity => scalar(@{$li->lineitem_details}),
        estimated_unit_price => $li->estimated_unit_price || '0.00',
        notes => $self->get_li_ftx($li),
        copies => []
    };

    $self->set_li_order_ident($li, $li_hash);

    for my $name (qw/title author edition pubdate publisher pagination/) {
        $li_hash->{$name} = $self->get_li_attr_imd($li, $name);
    }

    $self->compile_copies($li, $li_hash);

    return $li_hash;
}

sub compile_copies { 
    my ($self, $li, $li_hash) = @_;

    # does this EDI account want copy data?
    return unless $self->{compiled}->{edi_attrs}->{INCLUDE_COPIES};

    for my $copy (@{$li->lineitem_details}) {
        $self->compile_copy($li, $li_hash, $copy);
    }
}

sub compile_copy {
    my ($self, $li, $li_hash, $copy) = @_;

    my $fund = $copy->fund ? $copy->fund->code : '';
    my $item_type = $copy->circ_modifier || '';
    my $call_number = $copy->cn_label || '';
    my $owning_lib = $copy->owning_lib ?
                        $self->{compiled}->{edi_attrs}->{USE_ID_FOR_OWNING_LIB} ?
                        $copy->owning_lib->id :
                        $copy->owning_lib->shortname :
                     '';
    my $location = $copy->location ? $copy->location->name : '';
    my $collection_code = $copy->collection_code || '';
    my $barcode = $copy->barcode || '';

   
    # When an ACQ copy links to a real copy (acp), treat the real
    # copy as authoritative for certain fields.
    my $acp = $copy->eg_copy_id;
    if ($acp) {
        $item_type = $acp->circ_modifier || '';
        $call_number = $acp->call_number->label;
        $location = $acp->location->name;
    }

    my $found_match = 0;

    # Collapse like copies into groups with a quantity value.
    # INCLUDE_COPY_ID implies one GIR row per copy, no collapsing.
    if (!$self->{compiled}->{edi_attrs}->{INCLUDE_COPY_ID}) {
        
        for my $e_copy (@{$li_hash->{copies}}) {
            if (
                ($fund eq $e_copy->{fund}) &&
                ($item_type eq $e_copy->{item_type}) &&
                ($call_number eq $e_copy->{call_number}) &&
                ($owning_lib eq $e_copy->{owning_lib}) &&
                ($location eq $e_copy->{location}) &&
                ($barcode eq $e_copy->{barcode}) &&
                ($collection_code eq $e_copy->{collection_code})
            ) {
                $e_copy->{quantity}++;
                $found_match = 1;
                last;
            }
        }
    }

    return if $found_match; # nothing left to do.

    # No matching copy found.  Add it as a new copy to the lineitem
    # copies array.

    push(@{$li_hash->{copies}}, {
        fund => $self->escape_edi($fund),
        item_type => $self->escape_edi($item_type),
        call_number => $self->escape_edi($call_number),
        owning_lib => $self->escape_edi($owning_lib),
        location => $self->escape_edi($location),
        barcode => $self->escape_edi($barcode),
        collection_code => $self->escape_edi($collection_code),
        copy_id => $copy->id, # for INCLUDE_COPY_ID
        quantity => 1
    });
}

# IMD fields are limited to 70 chars per value over two DEs.
# Any values longer # should be carried via repeating IMD fields.
# IMD fields should only display the +::: when a value is present
sub IMD {
    my ($self, $code, $value) = @_;

    $value = ' ' if (
        $value eq '' &&
        $self->{compiled}->{edi_attrs}->{INCLUDE_EMPTY_IMD_VALUES}
    );

    if ($value) {
        my $s = '';
        for my $part ($value =~ m/.{1,70}/g) {
            my $de;
            if (length($part) > 35) {
                $de = $self->add_release_characters(substr($part, 0, 35)) .
                      ':' .
                      $self->add_release_characters(substr($part, 35));
            } else {
                $de = $self->add_release_characters($part);
            }
            $s .= "IMD+F+$code+:::$de'\n";
        }
        return $s;

    } else {
        return "IMD+F+$code'\n"
    }
}

# EDI Segments: --
# UNA
# UNB
# UNH
# BGM
# DTM
# NAD+BY
# NAD+SU...::31B
# NAD+SU...::92
# CUX
# <lineitems and copies>
# UNS
# CNT
# UNT
# UNZ
sub build_order_edi {
    my ($self) = @_;
    my %c = %{$self->{compiled}};
    my $date = DateTime->now->strftime("%Y%m%d");
    my $datetime = DateTime->now->strftime("%y%m%d:%H%M");
    my @lis = @{$c{lineitems}};

    # EDI header
    my $edi = <<EDI;
UNA:+.? '
UNB+UNOB:3+$c{org_unit_san}:31B+$c{vendor_san}:31B+$datetime+1'
UNH+1+ORDERS:D:96A:UN'
BGM+220+$c{po_id}+9'
DTM+137:$date:102'
EDI

    $edi .= "NAD+BY+$c{org_unit_san}::31B'\n" unless (
        $self->{compiled}->{edi_attrs}->{BUYER_ID_ONLY_VENDCODE} ||
        $self->{compiled}->{edi_attrs}->{BUYER_ID_INCLUDE_VENDCODE}
    );

    $edi .= <<EDI;
NAD+BY+$c{buyer_code}::91'
NAD+SU+$c{vendor_san}::31B'
NAD+SU+$c{provider_id}::92'
CUX+2:$c{currency_type}:9'
EDI

    # EDI lineitem segments
    $edi .= $self->build_lineitem_segments($_) for @lis;

    my $li_count = scalar(@lis);

    # Count the number of segments in the EDI message by counting the
    # number of newlines.  Add to count for lines below, not including
    # the UNZ segment.
    my $segments = $edi =~ tr/\n//;
    $segments += 1; # UNS, CNT, UNT, but not UNA or UNB

    # EDI Trailer
    $edi .= <<EDI;
UNS+S'
CNT+2:$li_count'
UNT+$segments+1'
UNZ+1+1'
EDI

    return $edi;
}

# EDI Segments: --
# LIN
# PIA+5
# IMD+F+BTI
# IMD+F+BPD
# IMD+F+BPU
# IMD+F+BAU
# IMD+F+BEN
# IMD+F+BPH
# QTY+21
# FTX+LIN
# PRI+AAB
# RFF+LI
sub build_lineitem_segments {
    my ($self, $li_hash) = @_;
    my %c = %{$self->{compiled}};

    my $id = $li_hash->{id};
    my $idval = $li_hash->{idval};
    my $idqual = $li_hash->{idqual};
    my $quantity = $li_hash->{quantity};
    my $price = $li_hash->{estimated_unit_price};

    # Line item identifier segments
    my $edi = "LIN+$id++$idval:$idqual'\n";
    $edi .= "PIA+5+$idval:$idqual'\n";

    $edi .= $self->IMD('BTI', $li_hash->{title});
    $edi .= $self->IMD('BPU', $li_hash->{publisher});
    $edi .= $self->IMD('BPD', $li_hash->{pubdate});

    $edi .= $self->IMD('BEN', $li_hash->{edition})
        if $c{edi_attrs}->{INCLUDE_BIB_EDITION};

    $edi .= $self->IMD('BAU', $li_hash->{author})
        if $c{edi_attrs}->{INCLUDE_BIB_AUTHOR};

    $edi .= $self->IMD('BPH', $li_hash->{pagination})
        if $c{edi_attrs}->{INCLUDE_BIB_PAGINATION};

    $edi .= "QTY+21:$quantity'\n";

    $edi .= $self->build_gir_segments($li_hash);

    for my $note (@{$li_hash->{notes}}) {
        if ($note) {
            $edi .= "FTX+LIN+1+$note'\n"
        } else {
            $edi .= "FTX+LIN+1'\n"
        }
    }

    $edi .= "PRI+AAB:$price'\n";

    # Standard RFF
    my $rff = "$c{po_id}/$id";

    if ($c{edi_attrs}->{LINEITEM_REF_ID_ONLY}) {
        # RFF with lineitem ID only (typically B&T)
        $rff = $id;
    } elsif ($c{edi_attrs}->{INCLUDE_PO_NAME}) {
        # RFF with PO name instead of PO ID
        $rff = "$c{po_name}/$id";
    }

    $edi .= "RFF+LI:$rff'\n";

    return $edi;
}


# Map of GIR segment codes, copy field names, inclusion attributes,
# and include-if-empty attributes for encoding copy data.
my @gir_fields = (
    {   code => 'LLO', 
        field => 'owning_lib', 
        attr => 'INCLUDE_OWNING_LIB'},
    {   code => 'LSQ', 
        field => 'collection_code', 
        attr => 'INCLUDE_COLLECTION_CODE', 
        empty_attr => 'INCLUDE_EMPTY_COLLECTION_CODE'},
    {   code => 'LQT', 
        field => 'quantity', 
        attr => 'INCLUDE_QUANTITY'},
    {   code => 'LCO',
        field => 'copy_id',
        attr => 'INCLUDE_COPY_ID'},
    {   code => 'LST', 
        field => 'item_type', 
        attr => 'INCLUDE_ITEM_TYPE',
        empty_attr => 'INCLUDE_EMPTY_ITEM_TYPE'},
    {   code => 'LSM', 
        field => 'call_number', 
        attr => 'INCLUDE_CALL_NUMBER', 
        empty_attr => 'INCLUDE_EMPTY_CALL_NUMBER'},
    {   code => 'LFN', 
        field => 'fund', 
        attr => 'INCLUDE_FUND'},
    {   code => 'LFH', 
        field => 'location', 
        attr => 'INCLUDE_LOCATION',
        empty_attr => 'INCLUDE_EMPTY_LOCATION'},
    {   code => 'LAC',
        field => 'barcode',
        attr => 'INCLUDE_ITEM_BARCODE'}
);

# EDI Segments: --
# GIR
# Sub-Segments: --
# LLO
# LFN
# LSM
# LST
# LSQ
# LFH
# LQT
sub build_gir_segments {
    my ($self, $li_hash) = @_;
    my %c = %{$self->{compiled}};
    my $gir_index = 0;
    my $edi = '';

    for my $copy (@{$li_hash->{copies}}) {
        $gir_index++;
        my $gir_idx_str = sprintf("%03d", $gir_index);

        my $field_count = 0;
        for my $field (@gir_fields) {
            next unless $c{edi_attrs}->{$field->{attr}};

            my $val = $copy->{$field->{field}};
            my $code = $field->{code};

            # include the GIR component if we have a value or this
            # EDI account is configured to include the empty value
            next unless $val || $c{edi_attrs}->{$field->{empty_attr} || ''};

            # EDI only allows 5 fields per GIR segment.  When we exceed
            # 5, finalize the in-process GIR segment and add a new one
            # as needed.
            if ($field_count == 5) {
                $field_count = 0;
                # Finalize this GIR segment with a ' and newline
                $edi .= "'\n";
            }

            $field_count++;

            # Starting a new GIR line for the current copy.
            $edi .= "GIR+$gir_idx_str" if $field_count == 1;

            # Add the field-specific value
            $edi .= "+$val:$code";
        }

        # End the final GIR segment with a ' and newline
        $edi .= "'\n";
    }

    return $edi;
}

1;

