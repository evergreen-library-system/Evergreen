# ---------------------------------------------------------------
# Copyright (C) 2012-2024 Equinox Software, Inc
# Author: Bill Erickson <berickr@esilibrary.com>
# Author: Mike Rylander <mrylander@gmail.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------
package OpenILS::Utils::EDIReader;
use strict; use warnings;
use OpenILS::Utils::X12;

my $X12_MSG_RE = '^ISA'; # starts a new X12 message
my $NEW_MSG_RE = '^UNH'; # starts a new message
my $NEW_LIN_RE = '^LIN'; # starts a new line item
my $END_ALL_LIN = '^UNS'; # no more lineitems after this

my %x12_to_edi_type_map = (
    856 => 'DESADV'
);

my %x12_fields = (
    M => { # M(essage) level data ... for x12, this is "outside any shipment block", so really file-level
        message_type => { extract => '$XACT->elements->First->data' },
        buyer_san => { extract => '$GROUP->elements->Reset(2)->Current->data' },
        vendor_san => { extract => '$GROUP->elements->Reset(1)->Current->data' },
    },
    S => { # S(hipment) level data
        invoice_date => { # bad name, but it's correct
            type => 'DTM',
            test => '$DATA->elements->findByLabel("DTM01")->First->data eq "011"',
            extract => '$DATA->elements->findByLabel("DTM02")->First->data'
        }
    },
    O => { # O(rder) level data -- PO-wide info
        invoice_date => { # bad name, but it's correct
            type => 'PRF',
            test => '$$current_xact{invoice_date}',
            extract => '$$current_xact{invoice_date}'
        },
        purchase_order => {
            type => 'PRF',
            test => '$DATA->elements->First->data',
            extract => '$DATA->elements->First->data'
        }
    },
    P => { # P(ackage) level data
        container_code => {
            type => 'MAN',
            test => '$DATA->type eq "MAN"',
            extract => '$DATA->elements->findByLabel("MAN02")->First->data'
        }
    },
    I => { # I(tem) level data
        identifiers => {
            type => 'LIN',
            test => '$DATA->elements->findByLabel("LIN0[246]")->First',
            extract => '[{ code => $DATA->elements->findByLabel("LIN0[246]")->First->data, value => $DATA->elements->findByLabel("LIN0[246]")->First->Peers->Next->data }]'
        },
        container_code => {
            type => 'LIN',
            test => '$$current_message{container_code}',
            extract => '$$current_message{container_code}'
        },
        purchase_order => {
            type => 'LIN',
            test => '$$current_message{purchase_order} || $DATA->elements->findByData("PO")->First',
            extract => '$DATA->elements->findByData("PO")->First->Peers->Next->data || $$current_message{purchase_order}'
        },
        quantities => { # ugh, much EDIFACT assumption :(
            type => 'LIN',
            test => '$DATA->Peers->Next->type eq "SN1"',
            extract => '[{ code => 12, quantity =>$DATA->Peers->Next->elements->findByLabel("SN102")->First->data}]'
        }
    }
);

my %edi_fields = (
    message_type    => qr/^UNH\+[A-z0-9]+\+(\S{6})/,
    buyer_san       => qr/^NAD\+BY\+([^:]+)::31B/,
    buyer_acct      => qr/^NAD\+BY\+([^:]+)::91/,
    buyer_ident     => qr/^NAD\+BY\+([^:]+)::9$/, # alternate SAN
    buyer_code      => qr/^RFF\+API:(\S+)/,
    vendor_san      => qr/^NAD\+SU\+([^:]+)::31B/,
    vendor_acct     => qr/^NAD\+SU\+([^:]+)::91/,
    vendor_ident    => qr/^NAD\+SU\+([^:]+)::9$/, # alternate SAN
    purchase_order  => qr/^RFF\+ON:(\S+)/,
    invoice_ident   => qr/^BGM\+380\+([^\+]+)/,
    total_billed    => qr/^MOA\+86:([^:]+)/,
    invoice_date    => qr/^DTM\+137:([^:]+)/, # This is really "messge date"
    # We don't retain a top-level container code -- they can repeat.
    _container_code => qr/^GIN\+BJ\+([^:]+)/,
    _container_code_alt => qr/^PCI\+33E\+([^:]+)/,
    lading_number   => qr/^RFF\+BM:([^:]+)/
);

my %edi_li_fields = (
    id      => qr/^RFF\+LI:(?:[^\/]+\/)?(\d+)/,
    index   => qr/^LIN\+([^\+]+)/,
    amount_billed   => qr/^MOA\+203:([^:]+)/,
    net_unit_price  => qr/^PRI\+AAA:([^:]+)/,
    gross_unit_price=> qr/^PRI\+AAB:([^:]+)/,
    expected_date   => qr/^DTM\+44:([^:]+)/,
    avail_status    => qr/^FTX\+LIN\++([^:]+):8B:28/,
    # "1B" codes are deprecated, but still in use.  
    # Pretend it's "12B" and it should just work
    order_status    => qr/^FTX\+LIN\++([^:]+):12?B:28/,
    # DESADV messages have multiple PO ID's, one RFF+ON per LIN.
    purchase_order  => qr/^RFF\+ON:(\S+)/
);

my %edi_li_ident_fields = (
    ident  => qr/^LIN\+\S+\++([^:]+):?(\S+)?/,
    ident2 => qr/^PIA\+0*5\+([^:]+):?(\S+)?/, 
);

my %edi_li_quant_fields = (
    code     => qr/^QTY\+(\d+):/,
    quantity => qr/^QTY\+\d+:(\d+)/
);

my %edi_charge_fields = (
    type   => qr/^ALC\+C\++([^\+]+)/,
    amount => qr/^MOA\+(?:8|131|304):([^:]+)/
);

# This may need to be liberalized later, but it works for the only example I
# have so far.
my %edi_tax_fields = (
    type   => qr/^TAX\+7\+([^\+]+)/,
    amount => qr/^MOA\+124:([^:]+)/
);

sub new {
    return bless({}, shift());
}

# see read()
sub read_file {
    my $self = shift;
    my $file = shift;

    open(EDI_FILE, $file) or die "Cannot open $file: $!\n";
    my $edi = join('', <EDI_FILE>);
    close EDI_FILE;

    return $self->read($edi);
}

# Reads an EDI string and parses the package one "line" at a time, extracting 
# needed information via regular expressions.  Returns an array of messages, 
# each represented as a hash.  See %edi_*fields above for lists of which fields 
# may be present within a message.

sub read {
    my $self = shift;
    my $edi = shift or return [];
    my @msgs;

    if ($edi =~ /$X12_MSG_RE/) { # looks like an x12 message!
        my $content = $edi;
        while (my $x12 = OpenILS::Utils::X12::message->new( content => $content )) {
            while (my $GROUP = $x12->groups->Next) {
                my $buyer_san = eval $x12_fields{M}{buyer_san}{extract};
                my $vendor_san = eval $x12_fields{M}{vendor_san}{extract};
                last unless ($buyer_san and $vendor_san);

                while (my $XACT = $GROUP->transactions->Next) {
                    my $mtype = eval $x12_fields{M}{message_type}{extract};
                    last unless $mtype = $x12_to_edi_type_map{$mtype};

                    my $current_xact = {};
                    my $current_li;
                    my $current_message;
                    X12SEG: while (my $SEG = $XACT->segments->Next) {
                        if ($SEG->type eq 'HL') { # hierarchical level change

                            # This is the set of relevant segments for the HL
                            my $HLpeers = $XACT->segments->untilNext('HL');

                            my $level = $SEG->elements->Last->data;
                            if ($level eq 'O') {
                                $current_message = {
                                    buyer_san => $buyer_san,
                                    vendor_san => $vendor_san,
                                    message_type => $mtype,
                                    lineitems => [],
                                    misc_charges => [],
                                    taxes => []
                                };
                                push(@msgs, $current_message);
                            } elsif ($level eq 'I') {
                                $current_li = {};
                                push(@{$$current_message{lineitems}}, $current_li);
                            }

                            # fields that belong at this HL level (S(hipment), O(rder), P(kg), I(tem))
                            my @fields = keys %{$x12_fields{$level}};

                            for my $f (@fields) {
                                my $field = $x12_fields{$level}{$f};
                                my $segs = $HLpeers->findByType($$field{type});
                                while (my $DATA = $segs->Next) {
                                    next unless eval $$field{test};
                                    if ($level eq 'S') { # not ready to fill orders or items yet
                                        last if $current_xact->{$f} = eval $$field{extract}
                                    } elsif ($level eq 'I') { # building a lineitem
                                        last if $current_li->{$f} = eval $$field{extract}
                                    } else {
                                        last if $current_message->{$f} = eval $$field{extract};
                                    }
                                }
                            }

                        }
                    }
                }
            }

            $content = $x12->remainder;
            last unless $content;
        }

        return \@msgs if (@msgs); # else, we'll try EDIFACT, I guess
    }

    $edi =~ s/\n//og;

    foreach (split(/'/, $edi)) {
        my $msg = $msgs[-1];

        # - starting a new message

        if (/$NEW_MSG_RE/) { 
            $msg = {lineitems => [], misc_charges => [], taxes => []};
            push(@msgs, $msg);
        }

        # extract top-level message fields

        next unless $msg;

        for my $field (keys %edi_fields) {
            ($msg->{$field}) = $_ =~ /$edi_fields{$field}/
                if /$edi_fields{$field}/;
        }

        # - starting a new lineitem

        if (/$NEW_LIN_RE/) {
            $msg->{_current_li} = {};

            # In DESADV messages there may be multiple container codes
            # per message.  They precede the lineitems contained within
            # each container.  Instead of restructuring the messages to
            # be containers of lineitems, just tag each lineitem with
            # its container if one is specified.
            my $ccode = $msg->{_container_code} || $msg->{_container_code_alt};
            $msg->{_current_li}->{container_code} = $ccode if $ccode;

            push(@{$msg->{lineitems}}, $msg->{_current_li});
        }

        # - extract lineitem fields

        if (my $li = $msg->{_current_li}) {

            for my $field (keys %edi_li_fields) {
                ($li->{$field}) = $_ =~ /$edi_li_fields{$field}/g
                    if /$edi_li_fields{$field}/;
            }

            for my $field (keys %edi_li_ident_fields) {
                if (/$edi_li_ident_fields{$field}/) {
                    my ($ident, $type) = $_ =~ /$edi_li_ident_fields{$field}/;
                    push(@{$li->{identifiers}}, {code => $type, value => $ident});
                }
            }

            if (/$edi_li_quant_fields{quantity}/) {
                my $quant = {};
                ($quant->{quantity}) = $_ =~ /$edi_li_quant_fields{quantity}/;
                ($quant->{code}) = $_ =~ /$edi_li_quant_fields{code}/;
                push(@{$li->{quantities}}, $quant);
            }

        }

        # - starting a new misc. charge

        if (/$edi_charge_fields{type}/) {
            $msg->{_current_charge} = {};
            push (@{$msg->{misc_charges}}, $msg->{_current_charge});
        }

        # - extract charge fields

        if (my $charge = $msg->{_current_charge}) {
            for my $field (keys %edi_charge_fields) {
                ($charge->{$field}) = $_ =~ /$edi_charge_fields{$field}/
                    if /$edi_charge_fields{$field}/;
            }
        }

        # - starting a new tax charge.  Taxes wind up on current lineitem if
        # any, otherwise in the top-level taxes array

        if (/$edi_tax_fields{type}/) {
            $msg->{_current_tax} = {};
            if ($msg->{_current_li}) {
                $msg->{_current_li}{tax} = $msg->{_current_tax}
            } else {
                push (@{$msg->{taxes}}, $msg->{_current_tax});
            }
        }

        # - extract tax field

        if (my $tax = $msg->{_current_tax}) {
            for my $field (keys %edi_tax_fields) {
                ($tax->{$field}) = $_ =~ /$edi_tax_fields{$field}/
                    if /$edi_tax_fields{$field}/;
            }
        }

        # This helps avoid associating taxes and charges at the end of the
        # message with the final lineitem inapporiately.
        if (/$END_ALL_LIN/) {
            # remove the state-maintenance keys
            foreach (grep /^_/, keys %$msg) {
                delete $msg->{$_};
            }
        }
    }

    # remove the state-maintenance keys
    for my $msg (@msgs) {
        foreach (grep /^_/, keys %$msg) {
            delete $msg->{$_};
        }
    }

    return \@msgs;
}
