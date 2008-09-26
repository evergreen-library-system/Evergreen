# --------------------------------------------------------------------
# Copyright (C) 2008 Niles Ingalls 
# Niles Ingalls <nilesi@zionsville.lib.in.us>
# Bill Erickson <erickson@esilibrary.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# --------------------------------------------------------------------
package OpenILS::Application::CreditCard;
use base qw/OpenSRF::Application/;
use strict; use warnings;

use DateTime;
use DateTime::Format::ISO8601;
use OpenILS::Application::AppUtils;
use OpenSRF::Utils qw/:datetime/;
use OpenILS::Event;
use OpenSRF::EX qw(:try);
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Const qw/:const/;
use OpenSRF::Utils::SettingsClient;
use Business::CreditCard;
use Business::CreditCard::Object;
use Business::OnlinePayment;
my $U = "OpenILS::Application::AppUtils";


__PACKAGE__->register_method(
    method    => 'process_payment',
    api_name  => 'open-ils.credit.process',
    signature => {
        desc   => 'Creates a new provider',
        params => [
            { desc => 'Authentication token', type => 'string' },
            { desc => q/Hash of arguments.  Options include:
                XXX add docs as API stablilizes...
                /, type => 'hash' }
        ],
        return => { desc => 'Hash of status information', type=>'hash' }
    }
);

sub process_payment {
    my $self     = shift;
    my $client   = shift;
    my $argshash = shift;

    my $e = new_editor();
    my $patron = $e->retrieve_actor_user(
        [
            $argshash->{patron_id},
            {
                flesh        => 1,
                flesh_fields => { au => ["mailing_address"] }
            }
        ]
    ) or return $e->event;

    return OpenILS::Event->new('BAD_PARAMS')
      unless $argshash->{login}
          and $argshash->{password}
          and $argshash->{action};

    if ( $argshash->{processor} eq 'PayPal' ) {    
        #  XXX not ready for prime time
        return handle_paypal($e, $argshash, $patron);

    } elsif ( $argshash->{processor} eq 'AuthorizeNet' ) {
        return handle_authorizenet($e, $argshash, $patron);
    }
}

sub handle_paypal {
    my($e, $argshash, $patron) = @_;

    require Business::PayPal::API;
    require Business::OnlinePayment::PayPal;
    my $card = Business::CreditCard::Object->new( $argshash->{cc} );

    $logger->debug("applying paypal payment");

    if ( !$card->is_valid ) {
        return {
            statusText       => "should return address:(patron_id):",
            processor        => $argshash->{processor},
            testmode         => $argshash->{testmode},
            card             => $card->number(),
            expiration       => $argshash->{expiration},
            name             => $patron->first_given_name,
            patron_id        => $patron->id,
            patron_patron_id => $patron->mailing_address,
            statusCode       => 500
        };
    }

    my $type = $card->type();

    if ( substr( $type, -5, 5 ) =~ / card/ ) {
        $type = substr( $type, 0, -5 );
    }

    my $transaction = Business::OnlinePayment->new(
        $argshash->{processor},
        "Username"  => $argshash->{PayPal_Username},
        "Password"  => $argshash->{PayPal_Password},
        "Signature" => $argshash->{PayPal_Signature}
    );

    $transaction->content(
        action      => $argshash->{action},
        amount      => $argshash->{amount},
        type        => "$type",
        card_number => $card->number(),
        expiration  => $argshash->{expiration},
        cvv2        => $argshash->{cvv2},
        name => $patron->first_given_name . ' ' . $patron->family_name,
        address => $patron->mailing_address->street1,
        city    => $patron->mailing_address->city,
        state   => $patron->mailing_address->state,
        zip     => $patron->mailing_address->post_code
    );

    $transaction->test_transaction(1); # XXX
    $transaction->submit;

    if ( $transaction->is_success ) {
        return {
            statusText => "Card approved: ".$transaction->authorization,
            statusCode    => 200,
            approvalCode  => $transaction->authorization,
            CorrelationID => $transaction->correlationid
        };

    } else {
        return {
            statusText => "Card declined: " . $transaction->error_message,
            statusCode => 500

        };
    }
}

sub handle_authorizenet {
    my($e, $argshash, $patron) = @_;

    require Business::OnlinePayment::AuthorizeNet;
    my $card = Business::CreditCard::Object->new( $argshash->{cc} );

    $logger->debug("applying authorize.net payment");

    if ( ! $card->is_valid ) {
        $logger->warn("authorize.net card number is invalid");

        return {
            statusText       => "should return address:(patron_id):",
            processor        => $argshash->{processor},
            testmode         => $argshash->{testmode},
            card             => $card->number(),
            expiration       => $argshash->{expiration},
            name             => $patron->first_given_name,
            patron_id        => $patron->id,
            patron_patron_id => $patron->mailing_address,
            statusCode       => 500
        };
    }

    my $type = $card->type();

    if ( substr( $type, -5, 5 ) =~ / card/ ) {
        $type = substr( $type, 0, -5 );
    }

    my $transaction = new Business::OnlinePayment( 
        $argshash->{processor}, 'test_transaction' => $argshash->{testmode});

    $transaction->content(
        type        => "$type", #'American Express', 'VISA', 'MasterCard'
        login       => $argshash->{login},
        password    => $argshash->{password},
        action      => $argshash->{action},
        description => $argshash->{description},
        amount      => $argshash->{amount},
        card_number => $card->number(),
        expiration  => $argshash->{expiration},
        cvv2        => $argshash->{cvv2},
        first_name  => $patron->first_given_name,
        last_name   => $patron->family_name,
        address     => $patron->mailing_address->street1,
        city        => $patron->mailing_address->city,
        state       => $patron->mailing_address->state,
        zip         => $patron->mailing_address->post_code,
        customer_id => $patron->id
    );

    $transaction->submit();

    if ( $transaction->is_success() ) {
        $logger->info("authorize.net payment succeeded");
        return {
            statusText => "Card approved: "
              . $transaction->authorization,
            statusCode      => 200,
            approvalCode    => $transaction->authorization,
            server_response => $transaction->server_response

        };

    } else {
        $logger->info("authorize.net card declined");
        return {
            statusText => "Card decliined: " . $transaction->error_message,
            statusCode      => 500,
            approvalCode    => $transaction->error_message,
            server_response => $transaction->server_response
        };
    }
}


__PACKAGE__->register_method(
    method    => 'retrieve_payable_balance',
    api_name  => 'open-ils.credit.payable_balance.retrieve',
    signature => {
        desc   => q/Returns the total amount of the patron can pay via credit card/,
        params => [
            { desc => 'Authentication token',      type => 'string' },
            { desc => 'Authentication token', type => 'string' },
            { desc => 'User id', type => 'number' }
        ],
        return => { desc => 'The ID of the new provider' }
    }
);

sub retrieve_payable_balance {
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
    my @orgs;
    for my $org ( @$circ_orgs, @$groc_orgs ) {
        my $o = $org->{billing_location};
        $o = $org->{circ_lib} unless $o;
        next if $hash{$org};
        $hash{$o} = $U->ou_ancestor_setting_value($o, 'global.credit.allow', $e);
    }

    my @credit_orgs = map { $hash{$_} ? ($_) : () } keys %hash;
    $logger->debug("credit: relevent orgs that allow credit payments => @credit_orgs");

    my $xact_summaries =
      OpenILS::Application::AppUtils->simplereq('open-ils.actor',
        'open-ils.actor.user.transactions.have_charge', $auth, $user_id);

    my $sum = 0.0;

    for my $xact (@$xact_summaries) {

        # make two lists and grab them in batch XXX
        if ( $xact->xact_type eq 'circulation' ) {
            my $circ = $e->retrieve_action_circulation($xact->id) or return $e->event;
            next unless grep { $_ == $circ->circ_lib } @credit_orgs;

        } else {
            my $bill = $e->retrieve_money_grocery($xact->id) or return $e->event;
            next unless grep { $_ == $bill->billing_location } @credit_orgs;
        }
        $sum += $xact->balance_owed();
    }

    return $sum;
}

1;
