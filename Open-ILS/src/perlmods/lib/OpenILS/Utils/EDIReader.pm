# ---------------------------------------------------------------
# Copyright (C) 2012 Equinox Software, Inc
# Author: Bill Erickson <berickr@esilibrary.com>
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

my $NEW_MSG_RE = '^UNH'; # starts a new message
my $NEW_LIN_RE = '^LIN'; # starts a new line item

my %edi_fields = (
    message_type    => qr/^UNH\+\d+\+(\S{6})/,
    buyer_san       => qr/^NAD\+BY\+([^:]+)::31B/,
    buyer_acct      => qr/^NAD\+BY\+([^:]+)::91/,
    vendor_san      => qr/^NAD\+SU\+([^:]+)::31B/,
    vendor_acct     => qr/^NAD\+SU\+([^:]+)::91/,
    purchase_order  => qr/^RFF\+ON:(\S+)/,
    invoice_ident   => qr/^BGM\+380\+([^\+]+)/,
    total_billed    => qr/^MOA\+86:([^:]+)/,
    invoice_date    => qr/^DTM\+137:([^:]+)/
);

my %edi_li_fields = (
    id      => qr/^RFF\+LI:\S+\/(\S+)/,
    index   => qr/^LIN\+([^\+]+)/,
    amount_billed   => qr/^MOA\+203:([^:]+)/,
    net_unit_price  => qr/^PRI\+AAA:([^:]+)/,
    gross_unit_price=> qr/^PRI\+AAB:([^:]+)/,
    expected_date   => qr/^DTM\+44:([^:]+)/,
    avail_status    => qr/^FTX\+LIN\++([^:]+):8B:28/,
    # "1B" codes are deprecated, but still in use.  
    # Pretend it's "12B" and it should just work
    order_status    => qr/^FTX\+LIN\++([^:]+):12?B:28/
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
    charge_type   => qr/^ALC\+C\++([^\+]+)/,
    charge_amount => qr/^MOA\+(8|131):([^:]+)/
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

    $edi =~ s/\n//og;

    foreach (split(/'/, $edi)) {
        my $msg = $msgs[-1];

        # - starting a new message

        if (/$NEW_MSG_RE/) { 
            $msg = {lineitems => [], misc_charges => []};
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

        if (/$edi_charge_fields{charge_type}/) {
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
    }

    # remove the state-maintenance keys
    for my $msg (@msgs) {
        foreach (grep /^_/, keys %$msg) {
            delete $msg->{$_};
        }
    }

    return \@msgs;
}
