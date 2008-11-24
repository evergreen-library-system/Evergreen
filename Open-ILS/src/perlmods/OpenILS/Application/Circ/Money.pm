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

__PACKAGE__->register_method(
	method	=> "make_payments",
	api_name	=> "open-ils.circ.money.payment",
	notes		=> <<"	NOTE");
	Pass in a structure like so:
		{ 
			cash_drawer: <string>, 
			payment_type : <string>, 
			note : <string>, 
			userid : <id>,
			payments: [ 
				[trans_id, amt], 
				[...]
			], 
			patron_credit : <credit amt> 
		}
	login must have CREATE_PAYMENT priveleges.
	If any payments fail, all are reverted back.
	NOTE

sub make_payments {
	my($self, $client, $login, $payments) = @_;
	my($user, $trans, $evt);

	my $e = new_editor(authtoken => $login, xact => 1);
    return $e->die_event unless $e->checkauth;
    my $patron = $e->retrieve_actor_user($payments->{userid}) or return $e->die_event;
	return $e->die_event unless $e->allowed('CREATE_PAYMENT', $patron->home_ou);

	my $type		= $payments->{payment_type};
	my $credit	= $payments->{patron_credit} || 0;
	my $drawer	= $e->requestor->wsid;
	my $userid	= $payments->{userid};
	my $note		= $payments->{note};
	my $cc_type = $payments->{cc_type} || 'n/a';
	my $cc_number		= $payments->{cc_number} || 'n/a';
	my $expire_month	= $payments->{expire_month};
	my $expire_year	= $payments->{expire_year};
	my $approval_code = $payments->{approval_code} || 'n/a';
	my $check_number	= $payments->{check_number} || 'n/a';

	my $total_paid = 0;

    my %orgs;

	for my $pay (@{$payments->{payments}}) {

		my $transid = $pay->[0];
		my $amount = $pay->[1];
		$amount =~ s/\$//og; # just to be safe

		$total_paid += $amount;

        $orgs{$U->xact_org($transid, $e)} = 1;

		$trans = fetch_mbts($self, $client, $login, $transid);
		return $trans if $U->event_code($trans);

        # making payment with existing patron credit
		$credit -= $amount if $type eq 'credit_payment';

		# A negative payment is a refund.  
		if( $amount < 0 ) {
			# If the refund causes the transaction balance to exceed 0 dollars, 
			# we are in effect loaning the patron money.  This is not allowed.
			if( ($trans->balance_owed - $amount) > 0 ) {
				return OpenILS::Event->new('REFUND_EXCEEDS_BALANCE');
			}

			# Otherwise, make sure the refund does not exceed desk payments
			# This is also not allowed
			my $desk_total = 0;
			my $desk_payments = $e->search_money_desk_payment(
				{ xact => $transid, voided => 'f' });
			$desk_total += $_->amount for @$desk_payments;

			if( (-$amount) > $desk_total ) {
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

		if ($payobj->has_field('accepting_usr')) { $payobj->accepting_usr($e->requestor->id); }
		if ($payobj->has_field('cash_drawer')) { $payobj->cash_drawer($drawer); }
		if ($payobj->has_field('cc_type')) { $payobj->cc_type($cc_type); }
		if ($payobj->has_field('cc_number')) { $payobj->cc_number($cc_number); }
		if ($payobj->has_field('expire_month')) { $payobj->expire_month($expire_month); }
		if ($payobj->has_field('expire_year')) { $payobj->expire_year($expire_year); }
		if ($payobj->has_field('approval_code')) { $payobj->approval_code($approval_code); }
		if ($payobj->has_field('check_number')) { $payobj->check_number($check_number); }
		
		# update the transaction if it's done 
		if( (my $cred = ($trans->balance_owed - $amount)) <= 0 ) {

			# Any overpay on this transaction goes directly into patron credit 
			$cred = -$cred;
			$credit += $cred;
            my $circ = $e->retrieve_action_circulation($transid);

			if(!$circ || $circ->stop_fines) {
			    # If this is a circulation, we can't close the transaction unless stop_fines is set
                $trans = $e->retrieve_money_billable_transaction($transid);
				$trans->xact_finish("now");
                $e->update_money_billable_transaction($trans) or return $e->die_event;
			}
		}

        my $method = "create_money_$type";
        $e->$method($payobj) or return $e->die_event;
	}

	$evt = _update_patron_credit($e, $patron, $credit);
	return $evt if $evt;

    for my $org_id (keys %orgs) {
        # calculate penalties for each of the affected orgs
        $evt = OpenILS::Utils::Penalty->calculate_penalties($e, $userid, $org_id);
        return $evt if $evt;
    }

    $e->commit;
    return 1;
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
	method	=> "retrieve_payments",
	api_name	=> "open-ils.circ.money.payment.retrieve.all_",
	notes		=> "Returns a list of payments attached to a given transaction"
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
	method	=> "retrieve_payments2",
    authoritative => 1,
	api_name	=> "open-ils.circ.money.payment.retrieve.all",
	notes		=> "Returns a list of payments attached to a given transaction"
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
	method	=> "create_grocery_bill",
	api_name	=> "open-ils.circ.money.grocery.create",
	notes		=> <<"	NOTE");
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
	method => 'fetch_grocery',
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
	method	=> "billing_items",
    authoritative => 1,
	api_name	=> "open-ils.circ.money.billing.retrieve.all",
	notes		=><<"	NOTE");
	Returns a list of billing items for the given transaction.
	PARAMS( login, transaction_id )
	NOTE

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
	method	=> "billing_items_create",
	api_name	=> "open-ils.circ.money.billing.create",
	notes		=><<"	NOTE");
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
    my $evt = OpenILS::Utils::Penalty->calculate_penalties($e, $xact->usr, $U->xact_org($xact->id));
    return $evt if $evt;
	$e->commit;

	return $billing->id;
}

__PACKAGE__->register_method(
	method		=>	'void_bill',
	api_name		=> 'open-ils.circ.money.billing.void',
	signature	=> q/
		Voids a bill
		@param authtoken Login session key
		@param billid The id of the bill to void
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




1;



