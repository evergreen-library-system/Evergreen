# ---------------------------------------------------------------
# Copyright (C) 2005  Georgia Public Library Service 
# Bill Erickson <billserickson@gmail.com>

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------

package OpenILS::Application::Circ::Money;
use base qw/OpenILS::Application/;
use strict; use warnings;
use OpenILS::Application::AppUtils;
my $apputils = "OpenILS::Application::AppUtils";
my $U = "OpenILS::Application::AppUtils";

use OpenSRF::EX qw(:try);
use OpenILS::Perm;
use Data::Dumper;
use OpenILS::Event;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Penalty;
$Data::Dumper::Indent = 0;

__PACKAGE__->register_method(
    method => "make_payments",
    api_name => "open-ils.circ.money.payment",
    signature => {
        desc => q/Create payments for a given user and set of transactions,
            login must have CREATE_PAYMENT privileges.
            If any payments fail, all are reverted back./,
        params => [
            {desc => 'Authtoken', type => 'string'},
            {desc => q/Arguments Hash, supporting the following params:
                { 
                    payment_type
                    userid
                    patron_credit
                    note
                    cc_args: {
                        where_process   1 to use processor, !1 for out-of-band
                        approval_code   (for out-of-band payment)
                        type            (for out-of-band payment)
                        number          (for call to payment processor)
                        expire_month    (for call to payment processor)
                        expire_year     (for call to payment processor)
                        billing_first   (for out-of-band payments and for call to payment processor)
                        billing_last    (for out-of-band payments and for call to payment processor)
                        billing_address (for call to payment processor)
                        billing_city    (for call to payment processor)
                        billing_state   (for call to payment processor)
                        billing_zip     (for call to payment processor)
                        note            (if payments->{note} is blank, use this)
                    },
                    check_number
                    payments: [ 
                        [trans_id, amt], 
                        [...]
                    ], 
                }/, type => 'hash'
            },
            {
                desc => q/Last user transaction ID.  This is the actor.usr.last_xact_id value/, 
                type => 'string'
            }
        ],
        "return" => {
            "desc" =>
                q{Array of payment IDs on success, event on failure.  Event possibilities include:
                BAD_PARAMS
                    Bad parameters were given to this API method itself.
                    See note field.
                INVALID_USER_XACT_ID
                    The last user transaction ID does not match the ID in the database.  This means
                    the user object has been updated since the last retrieval.  The client should
                    be instructed to reload the user object and related transactions before attempting
                    another payment
                REFUND_EXCEEDS_BALANCE
                REFUND_EXCEEDS_DESK_PAYMENTS
                CREDIT_PROCESSOR_NOT_SPECIFIED
                    Evergreen has not been set up to process CC payments.
                CREDIT_PROCESSOR_NOT_ALLOWED
                    Evergreen has been incorrectly setup for CC payments.
                CREDIT_PROCESSOR_NOT_ENABLED
                    Evergreen has been set up for CC payments, but an admin
                    has not explicitly enabled them.
                CREDIT_PROCESSOR_BAD_PARAMS
                    Evergreen has been incorrectly setup for CC payments;
                    specifically, the login and/or password for the CC
                    processor weren't provided.
                CREDIT_PROCESSOR_INVALID_CC_NUMBER
                    You have supplied a credit card number that Evergreen
                    has judged to be invalid even before attempting to contact
                    the payment processor.
                CREDIT_PROCESSOR_DECLINED_TRANSACTION
                    We contacted the CC processor to attempt the charge, but
                    they declined it.
                        The error_message field of the event payload will
                        contain the payment processor's response.  This
                        typically includes a message in plain English intended
                        for human consumption.  In PayPal's case, the message
                        is preceded by an integer, a colon, and a space, so
                        a caller might take the 2nd match from /^(\d+: )?(.+)$/
                        to present to the user.
                        The payload also contains other fields from the payment
                        processor, but these are generally not user-friendly
                        strings.
                CREDIT_PROCESSOR_SUCCESS_WO_RECORD
                    A payment was processed successfully, but couldn't be
                    recorded in Evergreen.  This is _bad bad bad_, as it means
                    somebody made a payment but isn't getting credit for it.
                    See errors in the system log if this happens.  Info from
                    the credit card transaction will also be available in the
                    event payload, although this probably won't be suitable for
                    staff client/OPAC display.
},
            "type" => "number"
        }
    }
);
sub make_payments {
    my($self, $client, $auth, $payments, $last_xact_id) = @_;

    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;

    my $type = $payments->{payment_type};
    my $user_id = $payments->{userid};
    my $credit = $payments->{patron_credit} || 0;
    my $drawer = $e->requestor->wsid;
    my $note = $payments->{note};
    my $cc_args = $payments->{cc_args};
    my $check_number = $payments->{check_number};
    my $total_paid = 0;
    my $this_ou = $e->requestor->ws_ou || $e->requestor->home_ou;
    my %orgs;

    # unless/until determined by payment processor API
    my ($approval_code, $cc_processor, $cc_type, $cc_order_number) = (undef,undef,undef, undef);

    my $patron = $e->retrieve_actor_user($user_id) or return $e->die_event;

    if($patron->last_xact_id ne $last_xact_id) {
        $e->rollback;
        return OpenILS::Event->new('INVALID_USER_XACT_ID');
    }

    # A user is allowed to make credit card payments on his/her own behalf
    # All other scenarious require permission
    unless($type eq 'credit_card_payment' and $user_id == $e->requestor->id) {
        return $e->die_event unless $e->allowed('CREATE_PAYMENT', $patron->home_ou);
    }

    # first collect the transactions and make sure the transaction
    # user matches the requested user
    my %xacts;
    for my $pay (@{$payments->{payments}}) {
        my $xact_id = $pay->[0];
        my $xact = $e->retrieve_money_billable_transaction_summary($xact_id)
            or return $e->die_event;
        
        if($xact->usr != $user_id) {
            $e->rollback;
            return OpenILS::Event->new('BAD_PARAMS', note => q/user does not match transaction/);
        }

        $xacts{$xact_id} = $xact;
    }

    my @payment_objs;

    for my $pay (@{$payments->{payments}}) {
        my $transid = $pay->[0];
        my $amount = $pay->[1];
        $amount =~ s/\$//og; # just to be safe
        my $trans = $xacts{$transid};

        $total_paid += $amount;

        $orgs{$U->xact_org($transid, $e)} = 1;

        # A negative payment is a refund.  
        if( $amount < 0 ) {

            # Negative credit card payments are not allowed
            if($type eq 'credit_card_payment') {
                $e->rollback;
                return OpenILS::Event->new(
                    'BAD_PARAMS', 
                    note => q/Negative credit card payments not allowed/
                );
            }

            # If the refund causes the transaction balance to exceed 0 dollars, 
            # we are in effect loaning the patron money.  This is not allowed.
            if( ($trans->balance_owed - $amount) > 0 ) {
                $e->rollback;
                return OpenILS::Event->new('REFUND_EXCEEDS_BALANCE');
            }

            # Otherwise, make sure the refund does not exceed desk payments
            # This is also not allowed
            my $desk_total = 0;
            my $desk_payments = $e->search_money_desk_payment({xact => $transid, voided => 'f'});
            $desk_total += $_->amount for @$desk_payments;

            if( (-$amount) > $desk_total ) {
                $e->rollback;
                return OpenILS::Event->new(
                    'REFUND_EXCEEDS_DESK_PAYMENTS', 
                    payload => { allowed_refund => $desk_total, submitted_refund => -$amount } );
            }
        }

        my $payobj = "Fieldmapper::money::$type";
        $payobj = $payobj->new;

        $payobj->amount($amount);
        $payobj->amount_collected($amount);
        $payobj->xact($transid);
        $payobj->note($note);
        if ((not $payobj->note) and ($type eq 'credit_card_payment')) {
            $payobj->note($cc_args->{note});
        }

        if ($payobj->has_field('accepting_usr')) { $payobj->accepting_usr($e->requestor->id); }
        if ($payobj->has_field('cash_drawer')) { $payobj->cash_drawer($drawer); }
        if ($payobj->has_field('cc_type')) { $payobj->cc_type($cc_args->{type}); }
        if ($payobj->has_field('check_number')) { $payobj->check_number($check_number); }

        # Store the last 4 digits of the CC number
        if ($payobj->has_field('cc_number')) {
            $payobj->cc_number(substr($cc_args->{number}, -4));
        }
        if ($payobj->has_field('expire_month')) { $payobj->expire_month($cc_args->{expire_month}); }
        if ($payobj->has_field('expire_year')) { $payobj->expire_year($cc_args->{expire_year}); }
        
        # Note: It is important not to set approval_code
        # on the fieldmapper object yet.

        push(@payment_objs, $payobj);

    } # all payment objects have been created and inserted. 

    #### NO WRITES TO THE DB ABOVE THIS LINE -- THEY'LL ONLY BE DISCARDED  ###
    $e->rollback;

    # After we try to externally process a credit card (if desired), we'll
    # open a new transaction.  We cannot leave one open while credit card
    # processing might be happening, as it can easily time out the database
    # transaction.

    my $cc_payload;

    if($type eq 'credit_card_payment') {
        $approval_code = $cc_args->{approval_code};
        # If an approval code was not given, we'll need
        # to call to the payment processor ourselves.
        if ($cc_args->{where_process} == 1) {
            return OpenILS::Event->new('BAD_PARAMS', note => 'Need CC number')
                if not $cc_args->{number};
            my $response =
                OpenILS::Application::Circ::CreditCard::process_payment({
                    "desc" => $cc_args->{note},
                    "amount" => $total_paid,
                    "patron_id" => $user_id,
                    "cc" => $cc_args->{number},
                    "expiration" => sprintf(
                        "%02d-%04d",
                        $cc_args->{expire_month},
                        $cc_args->{expire_year}
                    ),
                    "ou" => $this_ou,
                    "first_name" => $cc_args->{billing_first},
                    "last_name" => $cc_args->{billing_last},
                    "address" => $cc_args->{billing_address},
                    "city" => $cc_args->{billing_city},
                    "state" => $cc_args->{billing_state},
                    "zip" => $cc_args->{billing_zip},
                    "cvv2" => $cc_args->{cvv2},
                });

            if ($U->event_code($response)) { # non-success
                $logger->info(
                    "Credit card payment for user $user_id failed: " .
                    $response->{"textcode"} . " " .
                    $response->{"payload"}->{"error_message"}
                );

                return $response;
            } else {
                # We need to save this for later in case there's a failure on
                # the EG side to store the processor's result.
                $cc_payload = $response->{"payload"};

                $approval_code = $cc_payload->{"authorization"};
                $cc_type = $cc_payload->{"card_type"};
                $cc_processor = $cc_payload->{"processor"};
                $cc_order_number = $cc_payload->{"order_number"};
                $logger->info("Credit card payment for user $user_id succeeded");
            }
        } else {
            return OpenILS::Event->new(
                'BAD_PARAMS', note => 'Need approval code'
            ) if not $cc_args->{approval_code};
        }
    }

    ### RE-OPEN TRANSACTION HERE ###
    $e->xact_begin;
    my @payment_ids;

    # create payment records
    my $create_money_method = "create_money_" . $type;
    for my $payment (@payment_objs) {
        # update the transaction if it's done
        my $amount = $payment->amount;
        my $transid = $payment->xact;
        my $trans = $xacts{$transid};
        # making payment with existing patron credit.
        $credit -= $amount if $type eq 'credit_payment';
        if( (my $cred = ($trans->balance_owed - $amount)) <= 0 ) {
            # Any overpay on this transaction goes directly into patron
            # credit
            $cred = -$cred;
            $credit += $cred;
            my $circ = $e->retrieve_action_circulation($transid);

            # Whether or not we close the transaction. We definitely
            # close is no circulation transaction is present,
            # otherwise we check if the circulation is in a state that
            # allows itself to be closed.
            if (!$circ || OpenILS::Application::Circ::CircCommon->can_close_circ($e, $circ)) {
                $trans = $e->retrieve_money_billable_transaction($transid);
                $trans->xact_finish("now");
                if (!$e->update_money_billable_transaction($trans)) {
                    return _recording_failure(
                        $e, "update_money_billable_transaction() failed",
                        $payment, $cc_payload
                    )
                }
            }
        }

        $payment->approval_code($approval_code) if $approval_code;
        $payment->cc_order_number($cc_order_number) if $cc_order_number;
        $payment->cc_type($cc_type) if $cc_type;
        $payment->cc_processor($cc_processor) if $cc_processor;
        $payment->cc_first_name($cc_args->{'billing_first'}) if $cc_args->{'billing_first'};
        $payment->cc_last_name($cc_args->{'billing_last'}) if $cc_args->{'billing_last'};
        if (!$e->$create_money_method($payment)) {
            return _recording_failure(
                $e, "$create_money_method failed", $payment, $cc_payload
            );
        }

        push(@payment_ids, $payment->id);
    }

    my $evt = _update_patron_credit($e, $patron, $credit);
    if ($evt) {
        return _recording_failure(
            $e, "_update_patron_credit() failed", undef, $cc_payload
        );
    }

    for my $org_id (keys %orgs) {
        # calculate penalties for each of the affected orgs
        $evt = OpenILS::Utils::Penalty->calculate_penalties(
            $e, $user_id, $org_id
        );
        if ($evt) {
            return _recording_failure(
                $e, "calculate_penalties() failed", undef, $cc_payload
            );
        }
    }

    # update the user to create a new last_xact_id
    $e->update_actor_user($patron) or return $e->die_event;
    $patron = $e->retrieve_actor_user($patron) or return $e->die_event;
    $e->commit;

    # update the cached user object if a user is making a payment toward 
    # his/her own account
    $U->simplereq('open-ils.auth', 'open-ils.auth.session.reset_timeout', $auth, 1)
        if $user_id == $e->requestor->id;

    return {last_xact_id => $patron->last_xact_id, payments => \@payment_ids};
}

sub _recording_failure {
    my ($e, $msg, $payment, $payload) = @_;

    if ($payload) { # If the payment processor already accepted a payment:
        $logger->error($msg);
        $logger->error("Payment processor payload: " . Dumper($payload));
        # payment shouldn't contain CC number
        $logger->error("Payment: " . Dumper($payment)) if $payment;

        $e->rollback;

        return new OpenILS::Event(
            "CREDIT_PROCESSOR_SUCCESS_WO_RECORD",
            "payload" => $payload
        );
    } else { # Otherwise, the problem is somewhat less severe:
        $logger->warn($msg);
        $logger->warn("Payment: " . Dumper($payment)) if $payment;
        return $e->die_event;
    }
}

sub _update_patron_credit {
    my($e, $patron, $credit) = @_;
    return undef if $credit == 0;
    $patron->credit_forward_balance($patron->credit_forward_balance + $credit);
    return OpenILS::Event->new('NEGATIVE_PATRON_BALANCE') if $patron->credit_forward_balance < 0;
    $e->update_actor_user($patron) or return $e->die_event;
    return undef;
}


__PACKAGE__->register_method(
    method    => "retrieve_payments",
    api_name    => "open-ils.circ.money.payment.retrieve.all_",
    notes        => "Returns a list of payments attached to a given transaction"
    );
sub retrieve_payments {
    my( $self, $client, $login, $transid ) = @_;

    my( $staff, $evt ) =  
        $apputils->checksesperm($login, 'VIEW_TRANSACTION');
    return $evt if $evt;

    # XXX the logic here is wrong.. we need to check the owner of the transaction
    # to make sure the requestor has access

    # XXX grab the view, for each object in the view, grab the real object

    return $apputils->simplereq(
        'open-ils.cstore',
        'open-ils.cstore.direct.money.payment.search.atomic', { xact => $transid } );
}


__PACKAGE__->register_method(
    method    => "retrieve_payments2",
    authoritative => 1,
    api_name    => "open-ils.circ.money.payment.retrieve.all",
    notes        => "Returns a list of payments attached to a given transaction"
    );
    
sub retrieve_payments2 {
    my( $self, $client, $login, $transid ) = @_;

    my $e = new_editor(authtoken=>$login);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('VIEW_TRANSACTION');

    my @payments;
    my $pmnts = $e->search_money_payment({ xact => $transid });
    for( @$pmnts ) {
        my $type = $_->payment_type;
        my $meth = "retrieve_money_$type";
        my $p = $e->$meth($_->id) or return $e->event;
        $p->payment_type($type);
        $p->cash_drawer($e->retrieve_actor_workstation($p->cash_drawer))
            if $p->has_field('cash_drawer');
        push( @payments, $p );
    }

    return \@payments;
}

__PACKAGE__->register_method(
    method    => "format_payment_receipt",
    api_name  => "open-ils.circ.money.payment_receipt.print",
    signature => {
        desc   => 'Returns a printable receipt for the specified payments',
        params => [
            { desc => 'Authentication token',  type => 'string'},
            { desc => 'Payment ID or array of payment IDs', type => 'number' },
        ],
        return => {
            desc => q/An action_trigger.event object or error event./,
            type => 'object',
        }
    }
);
__PACKAGE__->register_method(
    method    => "format_payment_receipt",
    api_name  => "open-ils.circ.money.payment_receipt.email",
    signature => {
        desc   => 'Emails a receipt for the specified payments to the user associated with the first payment',
        params => [
            { desc => 'Authentication token',  type => 'string'},
            { desc => 'Payment ID or array of payment IDs', type => 'number' },
        ],
        return => {
            desc => q/Undefined on success, otherwise an error event./,
            type => 'object',
        }
    }
);

sub format_payment_receipt {
    my($self, $conn, $auth, $mp_id) = @_;

    my $mp_ids;
    if (ref $mp_id ne 'ARRAY') {
        $mp_ids = [ $mp_id ];
    } else {
        $mp_ids = $mp_id;
    }

    my $for_print = ($self->api_name =~ /print/);
    my $for_email = ($self->api_name =~ /email/);

    # manually use xact (i.e. authoritative) so we can kill the cstore
    # connection before sending the action/trigger request.  This prevents our cstore
    # backend from sitting idle while A/T (which uses its own transactions) runs.
    my $e = new_editor(xact => 1, authtoken => $auth);
    return $e->die_event unless $e->checkauth;

    my $payments = [];
    for my $id (@$mp_ids) {

        my $payment = $e->retrieve_money_payment([
            $id,
            {   flesh => 2,
                flesh_fields => {
                    mp => ['xact'],
                    mbt => ['usr']
                }
            }
        ]) or return $e->die_event;

        return $e->die_event unless 
            $e->requestor->id == $payment->xact->usr->id or
            $e->allowed('VIEW_TRANSACTION', $payment->xact->usr->home_ou); 

        push @$payments, $payment;
    }

    $e->rollback;

    if ($for_print) {

        return $U->fire_object_event(undef, 'money.format.payment_receipt.print', $payments, $$payments[0]->xact->usr->home_ou);

    } elsif ($for_email) {

        for my $p (@$payments) {
            $U->create_events_for_hook('money.format.payment_receipt.email', $p, $p->xact->usr->home_ou, undef, undef, 1);
        }
    }

    return undef;
}

__PACKAGE__->register_method(
    method    => "create_grocery_bill",
    api_name    => "open-ils.circ.money.grocery.create",
    notes        => <<"    NOTE");
    Creates a new grocery transaction using the transaction object provided
    PARAMS: (login_session, money.grocery (mg) object)
    NOTE

sub create_grocery_bill {
    my( $self, $client, $login, $transaction ) = @_;

    my( $staff, $evt ) = $apputils->checkses($login);
    return $evt if $evt;
    $evt = $apputils->check_perms($staff->id, 
        $transaction->billing_location, 'CREATE_TRANSACTION' );
    return $evt if $evt;


    $logger->activity("Creating grocery bill " . Dumper($transaction) );

    $transaction->clear_id;
    my $session = $apputils->start_db_session;
    $apputils->set_audit_info($session, $login, $staff->id, $staff->wsid);
    my $transid = $session->request(
        'open-ils.storage.direct.money.grocery.create', $transaction)->gather(1);

    throw OpenSRF::EX ("Error creating new money.grocery") unless defined $transid;

    $logger->debug("Created new grocery transaction $transid");
    
    $apputils->commit_db_session($session);

    my $e = new_editor(xact=>1);
    $evt = _check_open_xact($e, $transid);
    return $evt if $evt;
    $e->commit;

    return $transid;
}


__PACKAGE__->register_method(
    method => 'fetch_reservation',
    api_name => 'open-ils.circ.booking.reservation.retrieve'
);
sub fetch_reservation {
    my( $self, $conn, $auth, $id ) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('VIEW_TRANSACTION'); # eh.. basically the same permission
    my $g = $e->retrieve_booking_reservation($id)
        or return $e->event;
    return $g;
}

__PACKAGE__->register_method(
    method   => 'fetch_grocery',
    api_name => 'open-ils.circ.money.grocery.retrieve'
);
sub fetch_grocery {
    my( $self, $conn, $auth, $id ) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('VIEW_TRANSACTION'); # eh.. basically the same permission
    my $g = $e->retrieve_money_grocery($id)
        or return $e->event;
    return $g;
}


__PACKAGE__->register_method(
    method        => "billing_items",
    api_name      => "open-ils.circ.money.billing.retrieve.all",
    authoritative => 1,
    signature     => {
        desc   => 'Returns a list of billing items for the given transaction ID.  ' .
                  'If the operator is not the owner of the transaction, the VIEW_TRANSACTION permission is required.',
        params => [
            { desc => 'Authentication token', type => 'string'},
            { desc => 'Transaction ID',       type => 'number'}
        ],
        return => {
            desc => 'Transaction object, event on error'
        },
    }
);

sub billing_items {
    my( $self, $client, $login, $transid ) = @_;

    my( $trans, $evt ) = $U->fetch_billable_xact($transid);
    return $evt if $evt;

    my $staff;
    ($staff, $evt ) = $apputils->checkses($login);
    return $evt if $evt;

    if($staff->id ne $trans->usr) {
        $evt = $U->check_perms($staff->id, $staff->home_ou, 'VIEW_TRANSACTION');
        return $evt if $evt;
    }
    
    return $apputils->simplereq( 'open-ils.cstore',
        'open-ils.cstore.direct.money.billing.search.atomic', { xact => $transid } )
}


__PACKAGE__->register_method(
    method   => "billing_items_create",
    api_name => "open-ils.circ.money.billing.create",
    notes    => <<"    NOTE");
    Creates a new billing line item
    PARAMS( login, bill_object (mb) )
    NOTE

sub billing_items_create {
    my( $self, $client, $login, $billing ) = @_;

    my $e = new_editor(authtoken => $login, xact => 1);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('CREATE_BILL');

    my $xact = $e->retrieve_money_billable_transaction($billing->xact)
        or return $e->die_event;

    # if the transaction was closed, re-open it
    if($xact->xact_finish) {
        $xact->clear_xact_finish;
        $e->update_money_billable_transaction($xact)
            or return $e->die_event;
    }

    my $amt = $billing->amount;
    $amt =~ s/\$//og;
    $billing->amount($amt);

    $e->create_money_billing($billing) or return $e->die_event;
    my $evt = OpenILS::Utils::Penalty->calculate_penalties($e, $xact->usr, $U->xact_org($xact->id,$e));
    return $evt if $evt;

    $evt = _check_open_xact($e, $xact->id, $xact);
    return $evt if $evt;

    $e->commit;

    return $billing->id;
}


__PACKAGE__->register_method(
    method        =>    'void_bill',
    api_name        => 'open-ils.circ.money.billing.void',
    signature    => q/
        Voids a bill
        @param authtoken Login session key
        @param billid Id for the bill to void.  This parameter may be repeated to reference other bills.
        @return 1 on success, Event on error
    /
);
sub void_bill {
    my( $s, $c, $authtoken, @billids ) = @_;

    my $e = new_editor( authtoken => $authtoken, xact => 1 );
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('VOID_BILLING');

    my %users;
    for my $billid (@billids) {

        my $bill = $e->retrieve_money_billing($billid)
            or return $e->die_event;

        my $xact = $e->retrieve_money_billable_transaction($bill->xact)
            or return $e->die_event;

        if($U->is_true($bill->voided)) {
            $e->rollback;
            return OpenILS::Event->new('BILL_ALREADY_VOIDED', payload => $bill);
        }

        my $org = $U->xact_org($bill->xact, $e);
        $users{$xact->usr} = {} unless $users{$xact->usr};
        $users{$xact->usr}->{$org} = 1;

        $bill->voided('t');
        $bill->voider($e->requestor->id);
        $bill->void_time('now');
    
        $e->update_money_billing($bill) or return $e->die_event;
        my $evt = _check_open_xact($e, $bill->xact, $xact);
        return $evt if $evt;
    }

    # calculate penalties for all user/org combinations
    for my $user_id (keys %users) {
        for my $org_id (keys %{$users{$user_id}}) {
            OpenILS::Utils::Penalty->calculate_penalties($e, $user_id, $org_id);
        }
    }
    $e->commit;
    return 1;
}


__PACKAGE__->register_method(
    method        =>    'edit_bill_note',
    api_name        => 'open-ils.circ.money.billing.note.edit',
    signature    => q/
        Edits the note for a bill
        @param authtoken Login session key
        @param note The replacement note for the bills we're editing
        @param billid Id for the bill to edit the note of.  This parameter may be repeated to reference other bills.
        @return 1 on success, Event on error
    /
);
sub edit_bill_note {
    my( $s, $c, $authtoken, $note, @billids ) = @_;

    my $e = new_editor( authtoken => $authtoken, xact => 1 );
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('UPDATE_BILL_NOTE');

    for my $billid (@billids) {

        my $bill = $e->retrieve_money_billing($billid)
            or return $e->die_event;

        $bill->note($note);
        # FIXME: Does this get audited?  Need some way so that the original creator of the bill does not get credit/blame for the new note.
    
        $e->update_money_billing($bill) or return $e->die_event;
    }
    $e->commit;
    return 1;
}


__PACKAGE__->register_method(
    method        =>    'edit_payment_note',
    api_name        => 'open-ils.circ.money.payment.note.edit',
    signature    => q/
        Edits the note for a payment
        @param authtoken Login session key
        @param note The replacement note for the payments we're editing
        @param paymentid Id for the payment to edit the note of.  This parameter may be repeated to reference other payments.
        @return 1 on success, Event on error
    /
);
sub edit_payment_note {
    my( $s, $c, $authtoken, $note, @paymentids ) = @_;

    my $e = new_editor( authtoken => $authtoken, xact => 1 );
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('UPDATE_PAYMENT_NOTE');

    for my $paymentid (@paymentids) {

        my $payment = $e->retrieve_money_payment($paymentid)
            or return $e->die_event;

        $payment->note($note);
        # FIXME: Does this get audited?  Need some way so that the original taker of the payment does not get credit/blame for the new note.
    
        $e->update_money_payment($payment) or return $e->die_event;
    }

    $e->commit;
    return 1;
}

sub _check_open_xact {
    my( $editor, $xactid, $xact ) = @_;

    # Grab the transaction
    $xact ||= $editor->retrieve_money_billable_transaction($xactid);
    return $editor->event unless $xact;
    $xactid ||= $xact->id;

    # grab the summary and see how much is owed on this transaction
    my ($summary) = $U->fetch_mbts($xactid, $editor);

    # grab the circulation if it is a circ;
    my $circ = $editor->retrieve_action_circulation($xactid);

    # If nothing is owed on the transaction but it is still open
    # and this transaction is not an open circulation, close it
    if( 
        ( $summary->balance_owed == 0 and ! $xact->xact_finish ) and
        ( !$circ or $circ->stop_fines )) {

        $logger->info("closing transaction ".$xact->id. ' becauase balance_owed == 0');
        $xact->xact_finish('now');
        $editor->update_money_billable_transaction($xact)
            or return $editor->event;
        return undef;
    }

    # If money is owed or a refund is due on the xact and xact_finish
    # is set, clear it (to reopen the xact) and update
    if( $summary->balance_owed != 0 and $xact->xact_finish ) {
        $logger->info("re-opening transaction ".$xact->id. ' becauase balance_owed != 0');
        $xact->clear_xact_finish;
        $editor->update_money_billable_transaction($xact)
            or return $editor->event;
        return undef;
    }
    return undef;
}


__PACKAGE__->register_method (
    method => 'fetch_mbts',
    authoritative => 1,
    api_name => 'open-ils.circ.money.billable_xact_summary.retrieve'
);
sub fetch_mbts {
    my( $self, $conn, $auth, $id) = @_;

    my $e = new_editor(xact => 1, authtoken=>$auth);
    return $e->event unless $e->checkauth;
    my ($mbts) = $U->fetch_mbts($id, $e);

    my $user = $e->retrieve_actor_user($mbts->usr)
        or return $e->die_event;

    return $e->die_event unless $e->allowed('VIEW_TRANSACTION', $user->home_ou);
    $e->rollback;
    return $mbts
}


__PACKAGE__->register_method(
    method => 'desk_payments',
    api_name => 'open-ils.circ.money.org_unit.desk_payments'
);
sub desk_payments {
    my( $self, $conn, $auth, $org, $start_date, $end_date ) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('VIEW_TRANSACTION', $org);
    my $data = $U->storagereq(
        'open-ils.storage.money.org_unit.desk_payments.atomic',
        $org, $start_date, $end_date );

    $_->workstation( $_->workstation->name ) for(@$data);
    return $data;
}


__PACKAGE__->register_method(
    method => 'user_payments',
    api_name => 'open-ils.circ.money.org_unit.user_payments'
);

sub user_payments {
    my( $self, $conn, $auth, $org, $start_date, $end_date ) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('VIEW_TRANSACTION', $org);
    my $data = $U->storagereq(
        'open-ils.storage.money.org_unit.user_payments.atomic',
        $org, $start_date, $end_date );
    for(@$data) {
        $_->usr->card(
            $e->retrieve_actor_card($_->usr->card)->barcode);
        $_->usr->home_ou(
            $e->retrieve_actor_org_unit($_->usr->home_ou)->shortname);
    }
    return $data;
}


__PACKAGE__->register_method(
    method    => 'retrieve_credit_payable_balance',
    api_name  => 'open-ils.circ.credit.payable_balance.retrieve',
    authoritative => 1,
    signature => {
        desc   => q/Returns the total amount the patron can pay via credit card/,
        params => [
            { desc => 'Authentication token', type => 'string' },
            { desc => 'User id', type => 'number' }
        ],
        return => { desc => 'The ID of the new provider' }
    }
);

sub retrieve_credit_payable_balance {
    my ( $self, $conn, $auth, $user_id ) = @_;
    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    my $user = $e->retrieve_actor_user($user_id) 
        or return $e->event;

    if($e->requestor->id != $user_id) {
        return $e->event unless $e->allowed('VIEW_USER_TRANSACTIONS', $user->home_ou)
    }

    my $circ_orgs = $e->json_query({
        "select" => {circ => ["circ_lib"]},
        from     => "circ",
        "where"  => {usr => $user_id, xact_finish => undef},
        distinct => 1
    });

    my $groc_orgs = $e->json_query({
        "select" => {mg => ["billing_location"]},
        from     => "mg",
        "where"  => {usr => $user_id, xact_finish => undef},
        distinct => 1
    });

    my %hash;
    for my $org ( @$circ_orgs, @$groc_orgs ) {
        my $o = $org->{billing_location};
        $o = $org->{circ_lib} unless $o;
        next if $hash{$o};    # was $hash{$org}, but that doesn't make sense.  $org is a hashref and $o gets added in the next line.
        $hash{$o} = $U->ou_ancestor_setting_value($o, 'credit.payments.allow', $e);
    }

    my @credit_orgs = map { $hash{$_} ? ($_) : () } keys %hash;
    $logger->debug("credit: relevant orgs that allow credit payments => @credit_orgs");

    my $xact_summaries =
      OpenILS::Application::AppUtils->simplereq('open-ils.actor',
        'open-ils.actor.user.transactions.have_charge', $auth, $user_id);

    my $sum = 0.0;

    for my $xact (@$xact_summaries) {

        # make two lists and grab them in batch XXX
        if ( $xact->xact_type eq 'circulation' ) {
            my $circ = $e->retrieve_action_circulation($xact->id) or return $e->event;
            next unless grep { $_ == $circ->circ_lib } @credit_orgs;

        } elsif ($xact->xact_type eq 'grocery') {
            my $bill = $e->retrieve_money_grocery($xact->id) or return $e->event;
            next unless grep { $_ == $bill->billing_location } @credit_orgs;
        } elsif ($xact->xact_type eq 'reservation') {
            my $bill = $e->retrieve_booking_reservation($xact->id) or return $e->event;
            next unless grep { $_ == $bill->pickup_lib } @credit_orgs;
        }
        $sum += $xact->balance_owed();
    }

    return $sum;
}


1;
