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

	$logger->activity("Creating payment objects: " . Dumper($payments) );

	my $session = $apputils->start_db_session;
	my $type		= $payments->{payment_type};
	my $credit	= $payments->{patron_credit};
	my $drawer	= $payments->{cash_drawer};
	my $userid	= $payments->{userid};
	my $note		= $payments->{note};
	my $cc_type = $payments->{cc_type} || 'n/a';
	my $cc_number = $payments->{cc_number} || 'n/a';
	my $expire_month = $payments->{expire_month};
	my $expire_year = $payments->{expire_year};
	my $approval_code = $payments->{approval_code} || 'n/a';
	my $check_number = $payments->{check_number} || 'n/a';

	for my $pay (@{$payments->{payments}}) {

		my $transid = $pay->[0];
		my $amount = $pay->[1];
		($trans, $evt) = $apputils->fetch_open_billable_transaction($transid);
		return $evt if $evt;

		if($trans->usr != $userid) { # Do we need to restrict this in some way ??
			$logger->info( " * User $userid is making a payment for " . 
				"a different user: " .  $trans->usr . ' for transaction ' . $trans->id  );
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
		if( ($trans->balance_owed - $amount) <= 0 ) {

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

	_update_patron_credit( $session, $userid, $credit );

	$apputils->commit_db_session($session);
	return 1;
		
}

sub _update_patron_credit {
	my( $session, $userid, $credit ) = @_;
	return if $credit <= 0;

	my $patron = $session->request( 
		'open-ils.storage.direct.actor.user.retrieve', $userid )->gather(1);

	$logger->activity( "Adding to patron [$userid] credit: $credit" );

	$patron->credit_forward_balance( 
		$patron->credit_forward_balance + $credit);
	
	$logger->debug("Total patron credit is now " . $patron->credit_forward_balance );

	my $res = $session->request(
		'open-ils.storage.direct.actor.user.update', $patron )->gather(1);

	if(!$res) {
		throw OpenSRF::EX("Error updating patron credit");
	}
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

	my( $staff, $evt ) = $apputils->checksesperm($login, 'VIEW_TRANSACTION');
	return $evt if $evt;

# we need to grab the transaction by id and check the billing location
# to determin the permissibility XXX

#	$evt = $apputils->check_perms($staff->id, 
#		$transaction->billing_location, 'VIEW_TRANSACTION' );
#	return $evt if $evt;

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

	throw OpenSRF::EX ("Error creating new bill") unless defined $id;

	$apputils->commit_db_session($session);

	return $id;
}





1;



