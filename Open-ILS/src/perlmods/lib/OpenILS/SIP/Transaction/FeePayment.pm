# ---------------------------------------------------------------
# Copyright (C) 2011 Merrimack Valley Library Consortium
# Jason Stephenson <jstephenson@mvlc.org>

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------
#
# An object to handle fee payment
#

package OpenILS::SIP::Transaction::FeePayment;

use warnings;
use strict;

use POSIX qw(strftime);

use OpenILS::SIP;
use OpenILS::SIP::Transaction;
use OpenILS::SIP::Msg qw/:const/;
use Sys::Syslog qw(syslog);

use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';


our @ISA = qw(OpenILS::SIP::Transaction);

# Most fields are handled by the Transaction superclass
my %fields = (
              sip_payment_type => undef,
              fee_id => 0,
              patron_password => undef,
             );

sub new {
    my $class = shift;

    my $self = $class->SUPER::new(@_);

    foreach my $element (keys %fields) {
        $self->{_permitted}->{$element} = $fields{$element};
    }

    @{$self}{keys %fields} = values %fields;
    return bless $self, $class;
}

sub do_fee_payment {
    my $self = shift;

    # Just in case something completely unexpected happens, we'll
    # reject the payment to be 'safe.'
    $self->ok(0);

    # If the SC sends over a fee id, we try to pay that
    # fee/transaction on the patron's record.
    if ($self->fee_id) {
        my $bill;
        $bill = $U->simplereq('open-ils.actor', 'open-ils.actor.user.transaction.retrieve', $self->{authtoken}, $self->fee_id);
        syslog('LOG_DEBUG', 'OILS: open-ils.actor.user.transaction.retrieve returned ' . OpenSRF::Utils::JSON->perl2JSON($bill));
        # If we got an event or the bill belongs to another patron, set bill to undef.
        $bill = undef if ($U->event_code($bill) || $bill->usr != $self->patron->internal_id);

        # Attempt the payment here.
        if ($bill && $bill->balance_owed >= $self->fee_amount) {
            # We only attempt payment if the balance_owed on the bill
            # is greater than or equal to the amount paid by the
            # client.
            my $payref = [ [$bill->id, $self->fee_amount] ];
            my $resp = $self->pay_bills($payref);
            syslog('LOG_INFO', 'OILS: pay_bills returned ' . OpenSRF::Utils::JSON->perl2JSON($resp));
            if ($U->event_code($resp)) {
                $self->ok(0);
                $self->screen_msg(($resp->{descr} || $resp->{textcode}));
            } else {
                $self->ok(1);
            }
        } else {
            $self->ok(0);
            if ($bill) {
                # The payment had to be greater than the bill balance
                # to end up here. We don't allow credits or
                # overpayment.
                $self->sreen_msg(OILS_SIP_MSG_OVERPAYMENT);
            }
            else {
                # In this case, the bill was not found or did not
                # belong to the patron.
                $self->screen_msg(OILS_SIP_MSG_NO_BILL);
            }
        }
    } else {
        # We attempt to pay as many of the patron's bills as possible with the payment provided.
        my $results = $U->simplereq('open-ils.actor', 'open-ils.actor.user.transactions.history.have_balance', $self->{authtoken}, $self->patron->internal_id);
        if ($results && ref($results) eq 'ARRAY') {
            syslog('LOG_INFO', 'OILS: ' . scalar @$results . " bills found for " . $self->patron->internal_id);

            # If we get an empty array, we report not bills found and
            # quit.
            unless (@$results) {
                $self->ok(0);
                $self->screen_msg(OILS_SIP_MSG_NO_BILL);
                return $self->ok;
            }

            # We fill an array with the payment information as
            # open-ils.circ.money.payment expects it, i.e. an arrayref
            # with the bill_id and payment amount of its members. To
            # actually pay the bils, we pass the reference to this
            # array to our pay_bils method.
            my @payments = ();

            # Pay each bill from the fee_amount provided until we
            # either run out of bills or the input payment balance
            # hits zero.
            my $amount_paid = $self->fee_amount; # If this hits zero, we're done.
            foreach my $bill (@{$results}) {
                my $payment;
                syslog('LOG_INFO', 'OILS: bill '. $bill->id . ' amount ' . $bill->balance_owed);
                # Skip negative or zero-balance bills. (Not that I've
                # ever seen any.)
                next if ($bill->balance_owed <= 0);
                if ($bill->balance_owed >= $amount_paid) {
                    # We owe as much as or more than we have money
                    # left, so pay what we have left.
                    $payment = $amount_paid;
                    $amount_paid = 0;
                } else {
                    # This bill is for less than the amount we have
                    # left, so pay the full bill amount.
                    $payment = $bill->balance_owed;
                    $amount_paid -= $bill->balance_owed;
                }
                # Add the payment to our array.
                push(@payments, [$bill->id, $payment]);
                # Attempt to round $amount_paid to avoid floating point error.
                $amount_paid = sprintf("%.2f", $amount_paid);
                syslog('LOG_INFO', "OILS: paid $payment on " . $bill->id . " with balance " . $bill->balance_owed . " and $amount_paid remaining");
                # Leave if we ran out of money.
                last if ($amount_paid == 0.00);
            }
            if (@payments && $amount_paid == 0.00) {
                # pay the bills with a reference to our payments
                # array.
                my $resp = $self->pay_bills(\@payments);
                syslog('LOG_INFO', 'OILS: pay_bills returned ' . OpenSRF::Utils::JSON->perl2JSON($resp));
                if ($U->event_code($resp)) {
                    $self->ok(0);
                    $self->screen_msg(($resp->{descr} || $resp->{textcode}));
                } else {
                    $self->ok(1);
                }
            } else {
                $self->ok(0);
                if (scalar(@payments) == 0) {
                    # We didn't find any bills for the patron.
                    $self->screen_msg(OILS_SIP_MSG_NO_BILL);
                } else {
                    # We have an overpayment
                    $self->screen_msg(OILS_SIP_MSG_OVERPAYMENT);
                }
            }
        } else {
            $self->ok(0);
            if ($results && $U->event_code($results)) {
                syslog('LOG_INFO', 'OILS: open-ils.actor.user.transactions.history.have_balance returned '
                       . OpenSRF::Utils::JSON->perl2JSON($results));
                $self->screen_msg(OILS_SIP_MSG_BILL_ERR);
            } else {
                syslog('LOG_INFO', 'OILS: open-ils.actor.user.transactions.history.have_balance returned nothing');
                $self->screen_msg(OILS_SIP_MSG_NO_BILL);
            }
        }
    }
    return $self->ok;
}

# Takes array ref of array ref of [billid, payment_amount] to pay in
# batch.
sub pay_bills {
    my ($self, $paymentref) = @_;
    my $user = $self->patron->{user};
    if ($self->sip_payment_type eq '02') {
        # '02' is "credit card"
        my $transaction_id = $self->transaction_id ? $self->transaction_id : 'Not provided by SIP client';
        return $U->simplereq('open-ils.circ', 'open-ils.circ.money.payment', $self->{authtoken},
                             { payment_type => "credit_card_payment", userid => $user->id, note => "via SIP2",
                               cc_args => { approval_code => $transaction_id, },
                               payments => $paymentref}, $user->last_xact_id);
    } else {
        # record as "cash"
        return $U->simplereq('open-ils.circ', 'open-ils.circ.money.payment', $self->{authtoken},
                             { payment_type => "cash_payment", userid => $user->id, note => "via SIP2",
                               payments => $paymentref}, $user->last_xact_id);
    }
}


1;
