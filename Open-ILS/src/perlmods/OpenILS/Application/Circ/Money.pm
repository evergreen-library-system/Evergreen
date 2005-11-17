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
	my $user = $apputils->check_user_session($login);

	if($apputils->check_user_perms($user->id, $user->home_ou, "CREATE_PAYMENT")) {
		return OpenILS::Perm->new("CREATE_PAYMENT");
	} 

	use Data::Dumper;
	warn Dumper $payments;

	my $session = $apputils->start_db_session;
	my $type		= $payments->{payment_type};
	my $credit	= $payments->{patron_credit};
	my $drawer	= $payments->{cash_drawer};
	my $userid	= $payments->{userid};
	my $note		= $payments->{note};

	for my $pay (@{$payments->{payments}}) {

		my $transid = $pay->[0];
		my $amount = $pay->[1];
		my $trans = $session->request(
			"open-ils.storage.direct.money.billable_transaction_summary.retrieve", 
			$transid )->gather(1);

		return OpenILS::EX->new("NO_TRANSACTION_FOUND")->ex unless $trans; 

		if($trans->usr != $userid) { # XXX exception
			warn "Userid $userid does not match the user " . $trans->usr .
				"attached to transaction " . $trans->id . "\n";
		}

		my $payobj = "Fieldmapper::money::$type";
		$payobj = $payobj->new;

		$payobj->amount($amount);
		$payobj->amount_collected($amount);
		$payobj->accepting_usr($user->id);
		$payobj->xact($transid);
		$payobj->note($note);
		$payobj->cash_drawer($drawer);
		
		# update the transaction if it's done 
		if( ($trans->balance_owed - $amount) <= 0 ) {

			warn "Transaction is complete, updating...\n";
			$trans = $session->request(
				"open-ils.storage.direct.money.billable_transaction.retrieve", $transid )->gather(1);

			$trans->xact_finish("now");
			my $s = $session->request(
				"open-ils.storage.direct.money.billable_transaction.update", $trans )->gather(1);
			if(!$s) { throw OpenSRF::EX::ERROR 
				("Error updating billable_xact in circ.money.payment"); }
					
		}

		warn "Creating new $type object for \$$amount\n";

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
	return if $credit < 0;

	my $patron = $session->request( 
		'open-ils.storage.direct.actor.user.retrieve', $userid )->gather(1);

	$patron->credit_forward_balance( 
		$patron->credit_forward_balance + $credit);

	my $res = $session->request(
		'open-ils.storage.direct.actor.user.update', $patron )->gather(1);

	if(!$res) {
		throw OpenSRF::EX("Error updating patron credit");
	}
}




1;



