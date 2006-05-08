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
use base qw/OpenSRF::Application/;
use strict; use warnings;
use OpenILS::Application::AppUtils;
my $apputils = "OpenILS::Application::AppUtils";
my $U = "OpenILS::Application::AppUtils";

use OpenSRF::EX qw(:try);
use OpenILS::Perm;
use Data::Dumper;
use OpenSRF::Utils::Logger qw/:logger/;


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

	my( $self, $client, $login, $payments ) = @_;

	my( $user, $trans, $evt );

	( $user, $evt ) = $apputils->checkses($login);
	return $evt if $evt;
	$evt = $apputils->check_perms($user->id, $user->home_ou, 'CREATE_PAYMENT');
	return $evt if $evt;

	$logger->info("Creating payment objects: " . Dumper($payments) );

	my $session = $apputils->start_db_session;
	my $type		= $payments->{payment_type};
	my $credit	= $payments->{patron_credit} || 0;
	my $drawer	= $user->wsid;
	my $userid	= $payments->{userid};
	my $note		= $payments->{note};
	my $cc_type = $payments->{cc_type} || 'n/a';
	my $cc_number		= $payments->{cc_number} || 'n/a';
	my $expire_month	= $payments->{expire_month};
	my $expire_year	= $payments->{expire_year};
	my $approval_code = $payments->{approval_code} || 'n/a';
	my $check_number	= $payments->{check_number} || 'n/a';

	for my $pay (@{$payments->{payments}}) {

		my $transid = $pay->[0];
		my $amount = $pay->[1];
		($trans, $evt) = $apputils->fetch_open_billable_transaction($transid);
		return $evt if $evt;

		if($trans->usr != $userid) { # Do we need to restrict this in some way ??
			$logger->info( " * User $userid is making a payment for " . 
				"a different user: " .  $trans->usr . ' for transaction ' . $trans->id  );
		}

		if($type == 'credit_payment') {
			$credit -= $amount;
			$logger->activity("user ".$user->id." reducing patron credit to ".
				"$credit by making a credit_payment on transaction ".$trans->id);
		}


		# A negative payment is a refund.  If the refund causes the transaction 
		# balance to exceed 0 dollars, we are in effect loaning the patron
		# money.  This is not allowed.
		if( $amount < 0 and ($trans->balance_owed - $amount > 0) ) {
			return OpenILS::Event->new('REFUND_EXCEEDS_BALANCE');
		}

		my $payobj = "Fieldmapper::money::$type";
		$payobj = $payobj->new;

		$payobj->amount($amount);
		$payobj->amount_collected($amount);
		$payobj->accepting_usr($user->id);
		$payobj->xact($transid);
		$payobj->note($note);

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
			$logger->activity("user ".$user->id." applying credit ".
				"of $cred on transaction ".$trans->id. " because of overpayment");

			$logger->debug("Transactin " . $trans->id . ' is complete');
			$trans = $session->request(
				"open-ils.storage.direct.money.billable_transaction.retrieve", $transid )->gather(1);

			$trans->xact_finish("now");
			my $s = $session->request(
				"open-ils.storage.direct.money.billable_transaction.update", $trans )->gather(1);

			if(!$s) { throw OpenSRF::EX::ERROR 
				("Error updating billable_xact in circ.money.payment"); }
					
		}


		$logger->debug("Creating new $payobj for \$$amount\n");

		my $s = $session->request(
			"open-ils.storage.direct.money.$type.create", $payobj )->gather(1);
		if(!$s) { throw OpenSRF::EX::ERROR ("Error creating new $type"); }

	}


	$logger->activity("user ".$user->id." applying total ".
		"credit of $credit to user $userid") if $credit != 0;

	_update_patron_credit( $session, $userid, $credit );

	$apputils->commit_db_session($session);

	$client->respond_complete(1);	

	# ------------------------------------------------------------------------------
	# Update the patron penalty info in the DB
	# ------------------------------------------------------------------------------
	$U->update_patron_penalties( 
		authtoken => $login,
		patronid  => $userid,
	);

	return undef;
}


sub _update_patron_credit {
	my( $session, $userid, $credit ) = @_;
	#return if $credit <= 0;

	my $patron = $session->request( 
		'open-ils.storage.direct.actor.user.retrieve', $userid )->gather(1);

	$patron->credit_forward_balance( 
		$patron->credit_forward_balance + $credit);
	
	$logger->info("Total patron credit for $userid is now " . $patron->credit_forward_balance );

	$session->request( 
		'open-ils.storage.direct.actor.user.update', $patron )->gather(1);
}


__PACKAGE__->register_method(
	method	=> "retrieve_payments",
	api_name	=> "open-ils.circ.money.payment.retrieve.all",
	notes		=> "Returns a list of payments attached to a given transaction"
	);
	
sub retrieve_payments {
	my( $self, $client, $login, $transid ) = @_;

	my( $staff, $evt ) =  
		$apputils->checksesperm($login, 'VIEW_TRANSACTION');
	return $evt if $evt;

	# XXX the logic here is wrong.. we need to check the owner of the transaction
	# to make sure the requestor has access

	return $apputils->simplereq(
		'open-ils.storage',
		'open-ils.storage.direct.money.payment.search.xact.atomic', $transid );
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

	return $transid;
}

__PACKAGE__->register_method(
	method	=> "billing_items",
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
	
	return $apputils->simplereq( 'open-ils.storage',
		'open-ils.storage.direct.money.billing.search.xact.atomic', $transid )
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

	my( $staff, $evt ) = $apputils->checksesperm($login, 'CREATE_BILL');
	return $evt if $evt;

	my $session = $apputils->start_db_session;

	my $id = $session->request(
		'open-ils.storage.direct.money.billing.create', $billing )->gather(1);

	return $U->DB_UPDATE_FAILED($billing) unless defined $id;

	$apputils->commit_db_session($session);

	return $id;
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
	my( $s, $c, $authtoken, $billid ) = @_;

	my $reqr;
	my( $bill, $evt ) = $U->fetch_bill($billid);
	return $evt if $evt;


	($reqr, $evt) = $U->checkses($authtoken);
	return $evt if $evt;
	$evt = $U->check_perms($reqr->id, $reqr->ws_ou, 'VOID_BILLING');
	return $evt if $evt;

	$bill->voided('t');
	$bill->voider($reqr->id);
	$bill->void_time('now');

	my $stat = $U->storagereq(
		'open-ils.storage.direct.money.billing.update', $bill);
	return $U->DB_UPDATE_FAILED($bill) unless defined $stat;

	return 1;
}

__PACKAGE__->register_method (
	method => 'fetch_mbts',
	api_name => 'open-ils.circ.money.billable_xact_summary.retrieve'
);
sub fetch_mbts {
	my($s, $c, $authtoken, $id) = @_;

	my $sum = $U->storagereq(
		'open-ils.storage.direct.money.billable_transaction_summary.retrieve', $id );
	return OpenILS::Event->new('MONEY_BILLABLE_TRANSACTION_SUMMARY_NOT_FOUND', id => $id) unless $sum;

	my ($reqr, $evt) = $U->checkses($authtoken);
	return $evt if $evt;

	my $usr;
	($usr, $evt) = $U->fetch_user($sum->usr);
	return $evt if $evt;

	$evt = $U->check_perms($reqr->id, $usr->home_ou, 'VIEW_TRANSACTION');
	return $evt if $evt;

	return $sum;
}





1;



