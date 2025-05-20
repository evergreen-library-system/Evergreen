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
use OpenILS::Application::Circ::CircCommon;
my $apputils = "OpenILS::Application::AppUtils";
my $U = "OpenILS::Application::AppUtils";
my $CC = "OpenILS::Application::Circ::CircCommon";

use OpenSRF::EX qw(:try);
use OpenSRF::Utils::JSON;
use OpenILS::Perm;
use Data::Dumper;
use OpenILS::Event;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Penalty;
use Business::Stripe;
$Data::Dumper::Indent = 0;
use OpenILS::Const qw/:const/;
use OpenILS::Utils::DateTime qw/:datetime/;
use DateTime::Format::ISO8601;
my $parser = DateTime::Format::ISO8601->new;

my $cache;
my $cache_timeout;

sub get_processor_settings {
    my $e = shift;
    my $org_unit = shift;
    my $processor = lc shift;

    # Get the names of every credit processor setting for our given processor.
    # They're a little different per processor.
    my $setting_names = $e->json_query({
        select => {coust => ["name"]},
        from => {coust => {}},
        where => {name => {like => "credit.processor.${processor}.%"}}
    }) or return $e->die_event;

    # Make keys for a hash we're going to build out of the last dot-delimited
    # component of each setting name.
    ($_->{key} = $_->{name}) =~ s/.+\.(\w+)$/$1/ for @$setting_names;

    # Return a hash with those short keys, and for values the value of
    # the corresponding OU setting within our scope.
    return {
        map {
            $_->{key} => $U->ou_ancestor_setting_value($org_unit, $_->{name})
        } @$setting_names
    };
}

# process_stripe_or_bop_payment()
# This is a helper method to make_payments() below (specifically,
# the credit-card part). It's the first point in the Perl code where
# we need to care about the distinction between Stripe and the
# Paypal/PayflowPro/AuthorizeNet kinds of processors (the latter group
# uses B::OP and handles payment card info, whereas Stripe doesn't use
# B::OP and doesn't require us to know anything about the payment card
# info).
#
# Return an event in all cases.  That means a success returns a SUCCESS
# event.
sub process_stripe_or_bop_payment {
    my ($e, $user_id, $this_ou, $total_paid, $cc_args) = @_;

    # A few stanzas to determine which processor we're using and whether we're
    # really adequately set up for it.
    if (!$cc_args->{processor}) {
        if (!($cc_args->{processor} =
                $U->ou_ancestor_setting_value(
                    $this_ou, 'credit.processor.default'
                )
            )
        ) {
            return OpenILS::Event->new('CREDIT_PROCESSOR_NOT_SPECIFIED');
        }
    }

    # Make sure the configured credit processor has a safe/correct name.
    return OpenILS::Event->new('CREDIT_PROCESSOR_NOT_ALLOWED')
        unless $cc_args->{processor} =~ /^[a-z0-9_\-]+$/i;

    # Get the settings for the processor and make sure they're serviceable.
    my $psettings = get_processor_settings($e, $this_ou, $cc_args->{processor});
    return $psettings if defined $U->event_code($psettings);
    return OpenILS::Event->new('CREDIT_PROCESSOR_NOT_ENABLED')
        unless $psettings->{enabled};

    # Now we branch. Stripe is one thing, and everything else is another.
    # TODO: rename/refactor these methods, we're layering in Smartpay as well

    if ($cc_args->{processor} eq 'Stripe') { # Stripe
        my $stripe = Business::Stripe->new(-api_key => $psettings->{secretkey});
        $stripe->api('post','payment_intents/' . $cc_args->{stripe_payment_intent});
        if ($stripe->success) {
            $logger->debug('Stripe payment intent retrieved');
            my $intent = $stripe->success;
            if ($intent->{status} eq 'succeeded') {
                $logger->info('Stripe payment succeeded');
                return OpenILS::Event->new(
                    'SUCCESS', payload => {
                        invoice => $intent->{invoice},
                        customer => $intent->{customer},
                        balance_transaction => 'N/A',
                        id => $intent->{id},
                        created => $intent->{created},
                        card => 'N/A'
                    }
                );
            } else {
                $logger->info('Stripe payment failed');
                return OpenILS::Event->new(
                    'CREDIT_PROCESSOR_DECLINED_TRANSACTION',
                    payload => $intent->{last_payment_error}
                );
            }
        } else {
            $logger->debug('Stripe payment intent not retrieved');
            $logger->info('Stripe payment failed');
            return OpenILS::Event->new(
                "CREDIT_PROCESSOR_DECLINED_TRANSACTION",
                payload => $stripe->error  # XXX what happens if this contains
                                           # JSON::backportPP::* objects?
            );
        }

    } elsif ($cc_args->{processor} eq 'SmartPAY') { # SmartPAY
        my $smartpay_secret = $cc_args->{smartpay_secret};
        my $smartpay_session = $cc_args->{smartpay_session};
        if ($smartpay_secret =~ /^smartpay/) {
            my $cache = OpenSRF::Utils::Cache->new('global');
            my $secret_data = $cache->get_cache( $smartpay_secret );
            $logger->debug("SmartPAY secret_data: " . Dumper($secret_data));
            my $sessionA = $secret_data->{session_key};
            my $sessionB = $smartpay_session;
            if ($sessionA =~ /([A-Za-z0-9]+)/) {
                $sessionA = $1;
            }
            if ($sessionB =~ /([A-Za-z0-9]+)/) {
                $sessionB = $1;
            }
            if ($sessionA ne $sessionB) {
                $logger->info("SmartPAY payment failed: session_key mismatch: <$sessionA> vs <$sessionB>");
                return OpenILS::Event->new(
                    'CREDIT_PROCESSOR_DECLINED_TRANSACTION',
                    payload => { 'result' => 'session_key mismatch' }
                );
            }
            if ($cc_args->{smartpay_result} == 1) {
                $logger->info('SmartPAY payment succeeded');
                return OpenILS::Event->new(
                    'SUCCESS', payload => {
                        invoice => 'N/A',
                        customer => 'N/A',
                        balance_transaction => 'N/A',
                        id => 'N/A',
                        created => 'N/A',
                        card => 'N/A'
                    }
                );
            } else {
                $logger->info('SmartPAY payment failed: ' . $cc_args->{smartpay_result});
                return OpenILS::Event->new(
                    'CREDIT_PROCESSOR_DECLINED_TRANSACTION',
                    payload => { 'result' => $cc_args->{Result} }
                );
            }
        } else {
            $logger->info('SmartPAY payment failed: secret key malformed');
            return OpenILS::Event->new(
                'CREDIT_PROCESSOR_DECLINED_TRANSACTION',
                payload => { 'result' => 'secret key malformed' }
            );
        }
    } else { # B::OP style (Paypal/PayflowPro/AuthorizeNet)
        return OpenILS::Event->new('BAD_PARAMS', note => 'Need CC number')
            unless $cc_args->{number};

        return OpenILS::Application::Circ::CreditCard::process_payment({
            "processor" => $cc_args->{processor},
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
            %$psettings
        });

    }
}

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
                        stripe_token    (for call to Stripe payment processor)
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
    my ($approval_code, $cc_processor, $cc_order_number) = (undef,undef,undef, undef);

    my $patron = $e->retrieve_actor_user($user_id) or return $e->die_event;

    # If a Stripe payment intent gets here, it has succeeded and the patron's cc has been charged
    # Apply the payment regardless of differing last_xact_id (lp2077343)
    if($patron->last_xact_id ne $last_xact_id) {
	if (!exists $cc_args->{stripe_payment_intent}) {
            $e->rollback;
            return OpenILS::Event->new('INVALID_USER_XACT_ID');
        }
    }

    # A user is allowed to make credit card payments on his/her own behalf
    # All other scenarious require permission
    unless($type eq 'credit_card_payment' and $user_id == $e->requestor->id) {
        return $e->die_event unless $e->allowed('CREATE_PAYMENT', $patron->home_ou);
    }

    # first collect the transactions and make sure the transaction
    # user matches the requested user
    my %xacts;

    # We rewrite the payments array for sanity's sake, to avoid more
    # than one payment per transaction per call, which is not legitimate
    # but has been seen in the wild coming from the staff client.  This
    # is presumably a staff client (xulrunner) bug.
    my @unique_xact_payments;
    for my $pay (@{$payments->{payments}}) {
        my $xact_id = $pay->[0];
        if (exists($xacts{$xact_id})) {
            $e->rollback;
            return OpenILS::Event->new('MULTIPLE_PAYMENTS_FOR_XACT');
        }

        my $xact = $e->retrieve_money_billable_transaction_summary($xact_id)
            or return $e->die_event;
        
        if($xact->usr != $user_id) {
            $e->rollback;
            return OpenILS::Event->new('BAD_PARAMS', note => q/user does not match transaction/);
        }

        $xacts{$xact_id} = $xact;
        push @unique_xact_payments, $pay;
    }
    $payments->{payments} = \@unique_xact_payments;

    my @payment_objs;

    for my $pay (@{$payments->{payments}}) {
        my $transid = $pay->[0];
        my $amount = $pay->[1];
        $amount =~ s/\$//og; # just to be safe
        my $trans = $xacts{$transid};

        # add amounts as integers
        $total_paid += (100 * $amount);

        my $org_id = $U->xact_org($transid, $e);

        if (!$orgs{$org_id}) {
            $orgs{$org_id} = 1;

            # patron credit has to be allowed at all orgs receiving payment
            if ($type eq 'credit_payment' and $U->ou_ancestor_setting_value(
                    $org_id, 'circ.disable_patron_credit', $e)) {
                $e->rollback;
                return OpenILS::Event->new('PATRON_CREDIT_DISABLED');
            }
        }

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

            # Otherwise, make sure the refund does not exceed
            # REFUNDABLE desk payments. This is also not allowed.
            my $desk_total = 0;
            my $desk_payments = $e->search_money_desk_payment({xact => $transid, voided => 'f', refundable => 't'});
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
        if ($payobj->has_field('check_number')) { $payobj->check_number($check_number); }

        # Store the last 4 digits of the CC number
        if ($payobj->has_field('cc_number')) {
            $payobj->cc_number(substr($cc_args->{number}, -4));
        }

        # Note: It is important not to set approval_code
        # on the fieldmapper object yet.

        push(@payment_objs, $payobj);

    } # all payment objects have been created and inserted. 

    # return to decimal format, forcing X.YY format for consistency.
    $total_paid = sprintf("%.2f", $total_paid / 100);

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
            my $response = process_stripe_or_bop_payment(
                $e, $user_id, $this_ou, $total_paid, $cc_args
            );

            if ($U->event_code($response)) { # non-success (success is 0)
                $logger->info(
                    "Credit card payment for user $user_id failed: " .
                    $response->{textcode} . " " .
                    ($response->{payload}->{error_message} ||
                        $response->{payload}{message})
                );
                return $response;
            } else {
                # We need to save this for later in case there's a failure on
                # the EG side to store the processor's result.

                $cc_payload = $response->{"payload"};   # also used way later

                {
                    no warnings 'uninitialized';
                    $approval_code = $cc_payload->{authorization} ||
                        $cc_payload->{id};
                    $cc_processor = $cc_payload->{processor} ||
                        $cc_args->{processor};
                    $cc_order_number = $cc_payload->{order_number} ||
                        $cc_payload->{invoice};
                };
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

            # Attempt to close the transaction.
            my $close_xact_fail = $CC->maybe_close_xact($e, $transid);
            if ($close_xact_fail) {
                return _recording_failure(
                    $e, $close_xact_fail->{message},
                    $payment, $cc_payload
                );
            }
        }

        # Urgh, clean up this mega-function one day.
        if ($cc_processor eq 'Stripe' and $approval_code and $cc_payload) {
            $payment->cc_number($cc_payload->{card}); # not actually available :)
        }

        $payment->approval_code($approval_code) if $approval_code;
        $payment->cc_order_number($cc_order_number) if $cc_order_number;
        $payment->cc_processor($cc_processor) if $cc_processor;
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
        my $refundable = $_->refundable;
        my $meth = "retrieve_money_$type";
        my $p = $e->$meth($_->id) or return $e->event;
        $p->payment_type($type);
        $p->refundable($refundable);
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
    $evt = $U->check_open_xact($e, $transid);
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

    $evt = $U->check_open_xact($e, $xact->id, $xact);
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
    my $editor = new_editor(authtoken=>$authtoken, xact=>1);
    return $editor->die_event unless $editor->checkauth;
    return $editor->die_event unless $editor->allowed('VOID_BILLING');
    my $rv = $CC->void_bills($editor, \@billids);
    if (ref($rv) eq 'HASH') {
        # We got an event.
        $editor->rollback();
    } else {
        # We should have gotten 1.
        $editor->commit();
    }
    return $rv;
}


__PACKAGE__->register_method(
    method => 'adjust_bills_to_zero_manual',
    api_name => 'open-ils.circ.money.billable_xact.adjust_to_zero',
    signature => {
        desc => q/
            Given a list of billable transactions, manipulate the
            transaction using account adjustments to result in a
            balance of $0.
            /,
        params => [
            {desc => 'Authtoken', type => 'string'},
            {desc => 'Array of transaction IDs', type => 'array'}
        ],
        return => {
            desc => q/Array of IDs for each transaction updated,
            Event on error./
        }
    }
);

sub _rebill_xact {
    my ($e, $xact) = @_;

    my $xact_id = $xact->id;
    # the plan: rebill voided billings until we get a positive balance
    #
    # step 1: get the voided/adjusted billings
    my $billings = $e->search_money_billing([
        {
            xact => $xact_id,
        },
        {
            order_by => {mb => 'amount desc'},
            flesh => 1,
            flesh_fields => {mb => ['adjustments']},
        }
    ]);
    my @billings = grep { $U->is_true($_->voided) or @{$_->adjustments} } @$billings;

    my $xact_balance = $xact->balance_owed;
    $logger->debug("rebilling for xact $xact_id with balance $xact_balance");

    my $rebill_amount = 0;
    my @rebill_ids;
    # step 2: generate new bills just like the old ones
    for my $billing (@billings) {
        my $amount = 0;
        if ($U->is_true($billing->voided)) {
            $amount = $billing->amount;
        } else { # adjusted billing
            map { $amount = $U->fpsum($amount, $_->amount) } @{$billing->adjustments};
        }
        my $evt = $CC->create_bill(
            $e,
            $amount,
            $billing->btype,
            $billing->billing_type,
            $xact_id,
            "System: MANUAL ADJUSTMENT, BILLING #".$billing->id." REINSTATED\n(PREV: ".$billing->note.")",
            $billing->period_start(),
            $billing->period_end()
        );
        return $evt if $evt;
        $rebill_amount += $billing->amount;

        # if we have a postive (or zero) balance now, stop
        last if ($xact_balance + $rebill_amount >= 0);
    }
}

sub _is_fully_adjusted {
    my ($billing) = @_;

    my $amount_adj = 0;
    map { $amount_adj = $U->fpsum($amount_adj, $_->amount) } @{$billing->adjustments}; # XXX Looks like a bug, should be += instead of = ?

    return $billing->amount == $amount_adj;
}

sub adjust_bills_to_zero_manual {
    my ($self, $client, $auth, $xact_ids) = @_;

    my $e = new_editor(xact => 1, authtoken => $auth);
    return $e->die_event unless $e->checkauth;

    # in case a bare ID is passed
    $xact_ids = [$xact_ids] unless ref $xact_ids;

    my @modified;
    for my $xact_id (@$xact_ids) {

        my $xact =
            $e->retrieve_money_billable_transaction_summary([
                $xact_id,
                {flesh => 1, flesh_fields => {mbts => ['usr']}}
            ]) or return $e->die_event;

        if ($xact->balance_owed == 0) {
            # zero already, all done
            next;
        }

        return $e->die_event unless
            $e->allowed('ADJUST_BILLS', $xact->usr->home_ou);

        if ($xact->balance_owed < 0) {
            my $evt = _rebill_xact($e, $xact);
            return $evt if $evt;
            # refetch xact to get new balance
            $xact =
                $e->retrieve_money_billable_transaction_summary([
                    $xact_id,
                    {flesh => 1, flesh_fields => {mbts => ['usr']}}
                ]) or return $e->die_event;
        }

        if ($xact->balance_owed > 0) {
            # it's positive and needs to be adjusted
            # (it either started positive, or we rebilled it positive)
            my $billings = $e->search_money_billing([
                {
                    xact => $xact_id,
                },
                {
                    order_by => {mb => 'amount desc'},
                    flesh => 1,
                    flesh_fields => {mb => ['adjustments']},
                }
            ]);

            my @billings_to_zero = grep { !$U->is_true($_->voided) or !_is_fully_adjusted($_) } @$billings;
            $CC->adjust_bills_to_zero($e, \@billings_to_zero, "System: MANUAL ADJUSTMENT");
        }

        push(@modified, $xact->id);

        # now we see if we can close the transaction
        # same logic as make_payments();
        my $close_xact_fail = $CC->maybe_close_xact($e, $xact_id);
        if ($close_xact_fail) {
            return $close_xact_fail->{evt};
        }
    }

    $e->commit;
    return \@modified;
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


__PACKAGE__->register_method(
    method    => "retrieve_statement",
    authoritative => 1,
    api_name    => "open-ils.circ.money.statement.retrieve",
    notes        => "Returns an organized summary of a billable transaction, including all bills, payments, adjustments, and voids."
    );

sub _to_epoch {
    my $ts = shift @_;

    return $parser->parse_datetime(clean_ISO8601($ts))->epoch;
}

my %_statement_sort = (
    'billing' => 0,
    'account_adjustment' => 1,
    'void' => 2,
    'payment' => 3
);

sub retrieve_statement {
    my ( $self, $client, $auth, $xact_id ) = @_;

    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('VIEW_TRANSACTION');

    # XXX: move this lookup login into a DB query?
    my @line_prep;

    # collect all payments/adjustments
    my $payments = $e->search_money_payment({ xact => $xact_id });
    foreach my $payment (@$payments) {
        my $type = $payment->payment_type;
        $type = 'payment' if $type ne 'account_adjustment';
        push(@line_prep, [$type, _to_epoch($payment->payment_ts), $payment->payment_ts, $payment->id, $payment]);
    }

    # collect all billings
    my $billings = $e->search_money_billing({ xact => $xact_id });
    foreach my $billing (@$billings) {
        if ($U->is_true($billing->voided)){
            push(@line_prep, ['void', _to_epoch($billing->void_time), $billing->void_time, $billing->id, $billing]); # voids get two entries, one to represent the bill event, one for the void event
        }
        push(@line_prep, ['billing', _to_epoch($billing->billing_ts), $billing->billing_ts, $billing->id, $billing]);
    }

    # order every event by timestamp, then bills/adjustments/voids/payments order, then id
    my @ordered_line_prep = sort {
        $a->[1] <=> $b->[1]
            ||
        $_statement_sort{$a->[0]} <=> $_statement_sort{$b->[0]}
            ||
        $a->[3] <=> $b->[3]
    } @line_prep;

    # let's start building the statement structure
    my (@lines, %current_line, $running_balance);
    foreach my $event (@ordered_line_prep) {
        my $obj = $event->[4];
        my $type = $event->[0];
        my $ts = $event->[2];
        my $billing_type = $type =~ /billing|void/ ? $obj->billing_type : ''; # TODO: get non-legacy billing type
        my $note = $obj->note || '';
        # last line should be void information, try to isolate it
        if ($type eq 'billing' and $obj->voided) {
            $note =~ s/\n.*$//;
        } elsif ($type eq 'void') {
            $note = (split(/\n/, $note))[-1];
        }

        # if we have new details, start a new line
        if ($current_line{amount} and (
                $type ne $current_line{type}
                or ($note ne $current_line{note})
                or ($billing_type ne $current_line{billing_type})
            )
        ) {
            push(@lines, {%current_line}); # push a copy of the hash, not the real thing
            %current_line = ();
        }
        if (!$current_line{type}) {
            $current_line{type} = $type;
            $current_line{billing_type} = $billing_type;
            $current_line{note} = $note;
        }
        if (!$current_line{start_date}) {
            $current_line{start_date} = $ts;
        } elsif ($ts ne $current_line{start_date}) {
            $current_line{end_date} = $ts;
        }
        $current_line{amount} += $obj->amount;
        if ($current_line{details}) {
            push(@{$current_line{details}}, $obj);
        } else {
            $current_line{details} = [$obj];
        }
    }
    push(@lines, {%current_line}); # push last one on

    # get/update totals, format notes
    my %totals = (
        billing => 0,
        payment => 0,
        account_adjustment => 0,
        void => 0,
        nonrefundable => 0
    );
    foreach my $line (@lines) {
        $totals{$line->{type}} += $line->{amount};
        if ($line->{type} eq 'billing') {
            $running_balance += $line->{amount};
        } else { # not a billing; balance goes down for everything else
            if ($line->{type} eq 'payment') {
                $totals{nonrefundable} += $_->amount for grep {!$U->is_true($_->refundable)} @{$line->{details}};
            }
            $running_balance -= $line->{amount};
        }
        $line->{running_balance} = $running_balance;
        $line->{note} = $line->{note} ? [split(/\n/, $line->{note})] : [];
    }

    my $xact = $e->retrieve_money_billable_transaction([
        $xact_id, {
            flesh => 5,
            flesh_fields => {
                mbt =>  [qw/circulation grocery/],
                circ => [qw/target_copy/],
                acp =>  [qw/call_number location status age_protect total_circ_count/],
                acn =>  [qw/record prefix suffix/],
                bre =>  [qw/wide_display_entry/]
            },
            select => {bre => ['id']} 
        }
    ]);

    my $title;
    my $billing_location;
    my $title_id;
    if ($xact->circulation) {
        $billing_location = $xact->circulation->circ_lib;
        my $copy = $xact->circulation->target_copy;
        if ($copy->call_number->id == -1) {
            $title = $copy->dummy_title;
        } else {
            $title_id = $copy->call_number->record->id;
            $title = OpenSRF::Utils::JSON->JSON2perl(
                $copy->call_number->record->wide_display_entry->title);
        }
    } else {
        $billing_location = $xact->grocery->billing_location;
        $title = $xact->grocery->note;
    }

    my $balance_due = $totals{billing} - ($totals{payment} + $totals{account_adjustment} + $totals{void});
    if ($balance_due < 0) { # make sure we don't refund non-refundables
        if ($balance_due + $totals{nonrefundable} < 0) {
            $balance_due += $totals{nonrefundable};
        } else {
            $balance_due = 0;
        }
    }

    return {
        xact_id => $xact_id,
        xact => $xact,
        title => $title,
        title_id => $title_id,
        billing_location => $billing_location,
        summary => {
            balance_due => $balance_due,
            billing_total => $totals{billing},
            credit_total => $totals{payment} + $totals{account_adjustment},
            payment_total => $totals{payment},
            account_adjustment_total => $totals{account_adjustment},
            nonrefundable_total => $totals{nonrefundable},
            void_total => $totals{void}
        },
        lines => \@lines
    }
}


1;
