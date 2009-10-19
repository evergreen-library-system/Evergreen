# --------------------------------------------------------------------
# Copyright (C) 2008 Niles Ingalls 
# Niles Ingalls <nilesi@zionsville.lib.in.us>
# Bill Erickson <erickson@esilibrary.com>
# Joe Atzberger <atz@esilibrary.com>
# Lebbeous Fogle-Weekley <lebbeous@esilibrary.com>
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

use Business::CreditCard;
use Business::OnlinePayment;
use Locale::Country;

use OpenILS::Event;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Application::AppUtils;
my $U = "OpenILS::Application::AppUtils";

use constant CREDIT_NS => "credit";

# Given the argshash from process_payment(), this helper function just finds
# a function in the current namespace named "bop_args_{processor}" and calls
# it with $argshash as an argument, returning the result, or returning an
# empty hash if it can't find such a function.
sub get_bop_args_filler {
    no strict 'refs';

    my $argshash = shift;
    my $funcname = "bop_args_" . $argshash->{processor};
    return &{$funcname}($argshash) if defined &{$funcname};
    return ();
}

# Provide default arguments for calls using the AuthorizeNet processor
sub bop_args_AuthorizeNet {
    my $argshash = shift;
    if ($argshash->{server}) {
        return (
            # One might provide "test.authorize.net" here.
            Server => $argshash->{server},
        );
    }
    else {
        return ();
    }
}

# Provide default arguments for calls using the PayPal processor
sub bop_args_PayPal {
    my $argshash = shift;
    return (
        Username => $argshash->{login},
        Password => $argshash->{password},
        Signature => $argshash->{signature}
    );
}

sub get_processor_settings {
    my $org_unit = shift;
    my $processor = lc shift;

    +{ map { ($_ =>
        $U->ou_ancestor_setting_value(
            $org_unit, CREDIT_NS . ".processor.${processor}.${_}"
        )) } qw/enabled login password signature server testmode/
    };
}

__PACKAGE__->register_method(
    method    => 'process_payment',
    api_name  => 'open-ils.credit.process',
    signature => {
        desc   => 'Process a payment via a supported processor (AuthorizeNet, Paypal)',
        params => [
            { desc => q/Hash of arguments with these keys:
                patron_id: Not a barcode, but a patron's internal ID
                       ou: Org unit where transaction happens
                processor: Payment processor to use (AuthorizeNet, PayPal, etc)
                       cc: credit card number
                     cvv2: 3 or 4 digits from back of card
                   amount: transaction value
                   action: optional (default: Normal Authorization)
               first_name: optional (default: patron's first_given_name field)
                last_name: optional (default: patron's family_name field)
                  address: optional (default: patron's street1 field)
                     city: optional (default: patron's city field)
                    state: optional (default: patron's state field)
                      zip: optional (default: patron's zip field)
                  country: optional (some processor APIs: 2 letter code.)
              description: optional
                /, type => 'hash' }
        ],
        return => { desc => 'Hash of status information', type =>'hash' }
    }
);

sub process_payment {
    my ($self, $client, $argshash) = @_; # $client is unused in this sub

    # Confirm some required arguments.
    return OpenILS::Event->new('BAD_PARAMS')
        unless $argshash
            and $argshash->{cc}
            and $argshash->{amount}
            and $argshash->{expiration}
            and $argshash->{ou};

    if (!$argshash->{processor}) {
        if (!($argshash->{processor} =
                $U->ou_ancestor_setting_value(
                    $argshash->{ou}, CREDIT_NS . '.processor.default'))) {
            return OpenILS::Event->new('CREDIT_PROCESSOR_NOT_SPECIFIED');
        }
    }
    # Basic sanity check on processor name.
    if ($argshash->{processor} !~ /^[a-z0-9_\-]+$/i) {
        return OpenILS::Event->new('CREDIT_PROCESSOR_NOT_ALLOWED');
    }

    # Get org unit settings related to our processor
    my $psettings = get_processor_settings(
        $argshash->{ou}, $argshash->{processor}
    );

    if (!$psettings->{enabled}) {
        return OpenILS::Event->new('CREDIT_PROCESSOR_NOT_ENABLED');
    }

    # Add the org unit settings for the chosen processor to our argshash.
    $argshash = +{ %{$argshash}, %{$psettings} };

    # At least the following (derived from org unit settings) are required.
    return OpenILS::Event->new('CREDIT_PROCESSOR_BAD_PARAMS')
        unless $argshash->{login}
            and $argshash->{password};

    # A valid patron_id is also required.
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

    return dispatch($argshash, $patron);
}

sub prepare_bop_content {
    my ($argshash, $patron, $cardtype) = @_;

    my %content;
    foreach (qw/
        login
        password
        description
        first_name
        last_name
        amount
        expiration
        cvv2
        address
        city
        state
        zip
        country/) {
        if (exists $argshash->{$_}) {
            $content{$_} = $argshash->{$_};
        }
    }
    
    $content{action}       = $argshash->{action} || "Normal Authorization";
    $content{type}         = $cardtype;      #'American Express', 'VISA', 'MasterCard'
    $content{card_number}  = $argshash->{cc};
    $content{customer_id}  = $patron->id;
    
    $content{first_name} ||= $patron->first_given_name;
    $content{last_name}  ||= $patron->family_name;

    $content{FirstName}    = $content{first_name};   # kludge mcugly for PP
    $content{LastName}     = $content{last_name};


    # Especially for the following fields, do we need to support different
    # mapping of fields for different payment processors, particularly ones
    # in other countries?
    $content{address}    ||= $patron->mailing_address->street1;
    $content{city}       ||= $patron->mailing_address->city;
    $content{state}      ||= $patron->mailing_address->state;
    $content{zip}        ||= $patron->mailing_address->post_code;
    $content{country}    ||= $patron->mailing_address->country;

    # Yet another fantastic kludge. country2code() comes from Locale::Country.
    # PayPal must have 2 letter country field (ISO 3166) that's uppercase.
    if (length($content{country}) > 2 && $argshash->{processor} eq 'PayPal') {
        $content{country} = uc country2code($content{country});
    }

    %content;
}

sub dispatch {
    my ($argshash, $patron) = @_;
    
    # The validate() sub is exported by Business::CreditCard.
    if (!validate($argshash->{cc})) {
        # Although it might help a troubleshooter, it's probably not a good
        # idea to put the credit card number in the log file.
        $logger->warn("Credit card number invalid");

        # The idea of returning a hashref with statusText and statusCode
        # comes from an older version handle_authorizenet(), but I'm not
        # sure it's the best thing to do, really.
        return {
            statusText => "Credit card number invalid",
            statusCode => 500
        };
    }

    # cardtype() also comes from Business::CreditCard.  It is not certain that
    # a) the card type returned by this method will be suitable input for
    #   a payment processor, nor that
    # b) it is even necessary to supply this argument to processors in all
    #   cases.  Testing this with several processors would be a good idea.
    (my $cardtype = cardtype($argshash->{cc})) =~ s/ card//;

    $logger->debug(
        "applying payment via processor '" . $argshash->{processor} . "'"
    );

    # Find B:OP constructor arguments specific to our payment processor.
    my %bop_args = get_bop_args_filler($argshash);

    # We're assuming that all B:OP processors accept this argument to the
    # contstructor.
    $bop_args{test_transaction} = $argshash->{testmode};

    my $transaction = new Business::OnlinePayment(
        $argshash->{processor}, %bop_args
    );

    $transaction->content(prepare_bop_content($argshash, $patron, $cardtype));
    $transaction->submit();

    # The data structures that we return based on success or failure are still
    # basically from earlier code.  These might should be improved/reduced.
    if ($transaction->is_success()) {
        $logger->info($argshash->{processor} . " payment succeeded");

        my $retval = {
            statusText => "Transaction approved: " . $transaction->authorization,
            statusCode => 200,
            approvalCode => $transaction->authorization,
            server_response => $transaction->server_response
        };

        # These result fields may be important in PayPal xactions? Not sure.
        foreach (qw/correlationid avs_code cvv2_code/) {
            if ($transaction->can($_)) {
                $retval->{$_} = $transaction->$_;
            }
        }
        return $retval;
    }
    else {
        $logger->info($argshash->{processor} . " payment failed");
        return {
            statusText => "Transaction declined: " . $transaction->error_message,
            statusCode => 500,
            errorMessage => $transaction->error_message,
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
    for my $org ( @$circ_orgs, @$groc_orgs ) {
        my $o = $org->{billing_location};
        $o = $org->{circ_lib} unless $o;
        next if $hash{$o};    # was $hash{$org}, but that doesn't make sense.  $org is a hashref and $o gets added in the next line.
        $hash{$o} = $U->ou_ancestor_setting_value($o, CREDIT_NS . '.payments.allow', $e);
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

        } else {
            my $bill = $e->retrieve_money_grocery($xact->id) or return $e->event;
            next unless grep { $_ == $bill->billing_location } @credit_orgs;
        }
        $sum += $xact->balance_owed();
    }

    return $sum;
}

1;
