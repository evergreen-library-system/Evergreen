package OpenILS::Application::SIP2::Payment;
use strict; use warnings;
use DateTime;
use DateTime::Format::ISO8601;
use OpenSRF::System;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenSRF::Utils::Logger q/$logger/;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::DateTime qw/:datetime/;
use OpenILS::Const qw/:const/;
use OpenILS::Application::SIP2::Common;
use OpenILS::Application::SIP2::Session;
my $U = 'OpenILS::Application::AppUtils';
my $SC = 'OpenILS::Application::SIP2::Common';


sub apply_payment {
    my ($class, $session, %params) = @_;

    my $details = {ok => 0};

    my $card = $session->editor->search_actor_card([
        {barcode => $params{patron_barcode}}, 
        {flesh => 1, flesh_fields => {ac => [qw/usr/]}}
    ])->[0];

    return $details unless $card;

    my $user = $card->usr;

    if ($params{fee_id}) {
        pay_one_transaction($session, $details, $user, %params);

    } else {
        # No transaction was specified, pay whatever we can.
        pay_multi_transactions($session, $details, $user, %params);
    }

    return $details;
}

sub pay_one_transaction {
    my ($session, $details, $user, %params) = @_;

    my $fee_id = $params{fee_id};  # action.billable_xact.id

    my $xact = 
        $session->editor->retrieve_money_billable_transaction_summary($fee_id);

    return unless $xact && $xact->usr == $user->id;

    my $pay_amount = $params{pay_amount};

    return unless $pay_amount > 0;

    if ($pay_amount > $xact->balance_owed) {
        my $msg = $session->editor
            ->retrieve_sip_screen_message('payment.overpayment_not_allowed');

        $details->{screen_msg} = $msg ? $msg->message : 'Overpayment not allowed';
        return;
    }

    my $payments = [[$xact->id, $pay_amount]];

    send_payments($session, $details, $user, $payments, %params);
}

sub pay_multi_transactions {
    my ($session, $details, $user, %params) = @_;
    my $payments = [];

    # See if we can find some find some transactions to pay.
    my $xacts = $U->simplereq('open-ils.actor', 
        'open-ils.actor.user.transactions.history.have_balance', 
        $session->editor->authtoken, $user->id);

    if (!$xacts || !@$xacts) { # nothing to pay
        my $msg = $session->editor->
            retrieve_sip_screen_message('payment.transaction_not_found');

        $details->{screen_msg} = $msg ? $msg->message : 'Bill not found';
        return;
    }

    my $pay_amount = $params{pay_amount};
    my $amount_remaining = $pay_amount;

    for my $xact (@$xacts) {
        next if $xact->balance_owed <= 0;

        my $payment;
        my $xact_id = $xact->id;
        my $balance_owed = $xact->balance_owed;

        if ($balance_owed >= $amount_remaining) {

            # We owe as much as or more than we have money left, 
            # so pay what we have left.
            $payment = $amount_remaining;
            $amount_remaining = 0;

        } else {

            # This bill is for less than the amount we have
            # left, so pay the full bill amount.
            $payment = $balance_owed;
            $amount_remaining = $U->fpdiff($amount_remaining, $balance_owed);
        }

        push(@$payments, [$xact->id, $payment]);

        $amount_remaining = sprintf("%.2f", $amount_remaining);
        $balance_owed = sprintf("%.2f", $balance_owed);

        $logger->info("SIP paid $payment on $xact_id with a ".
            "balance of $balance_owed and $amount_remaining remaining");

        # Leave if we ran out of money.
        last if $amount_remaining == 0;
    }

    if ($amount_remaining > 0) {
        my $msg = $session->editor
            ->retrieve_sip_screen_message('payment.overpayment_not_allowed');

        $details->{screen_msg} = $msg ? $msg->message : 'Overpayment not allowed';
        return;
    }

    send_payments($session, $details, $user, $payments, %params);
}

# Takes array ref of array ref of [xact_id, payment_amount] to pay in batch.
sub send_payments {
    my ($session, $details, $user, $payments, %params) = @_;

    my $pay_type = $params{pay_type};
    my $register_login = $params{register_login};

    if ($register_login) {
        $logger->debug("SIP register login sent as '$register_login'");

        if ($register_login =~ /\\.+/) { # Windows domain login DOMAIN\user
            my @parts = split(/\\/, $register_login);
            $register_login = $parts[1];
        }
    }
    
    my $args = {
        userid => $user->id,
        note => $register_login ? 
            "Via SIP2: Register login '$register_login'" : "Via SIP2",
        payments => $payments,
        payment_type => 'cash_payment'
    };

    if ($pay_type eq '01' || $pay_type eq '02') {
        # '01' is "VISA"
        # '02' is "credit card"

        $args->{payment_type} = 'credit_card_payment';
        $args->{cc_args} = {
            approval_code => 
                $params{terminal_xact} || 'Not provided by SIP client'
        };

    } elsif ($pay_type eq '05') {

        $args->{payment_type} = 'check_payment';
        $args->{check_number} = 
            $params{check_number} || 'Not Provided by SIP Client';
    }

    my $resp = $U->simplereq(
        'open-ils.circ', 'open-ils.circ.money.payment', 
        $session->editor->authtoken, $args, $user->last_xact_id);

    if ($U->event_code($resp)) {
        $details->{screen_msg} = $resp->{descr} || $resp->{textcode};
    } else {
        $details->{ok} = 1;
    }
}





