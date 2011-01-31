package OpenILS::Application::Trigger::Reactor::ApplyCircFee;
use base 'OpenILS::Application::Trigger::Reactor';
use strict; use warnings;
use Error qw/:try/;
use OpenILS::Const qw/:const/;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenILS::Utils::CStoreEditor q/:funcs/;


sub ABOUT {
    return <<ABOUT;
    
    Creates a bill (money.billing) for the configured amount, linked to the circulation.
    This reactor uses the Notification Fee billing type.
    If an event definition template is defined, it will be used to generate the bill note.

    Required event parameters:
        "amount" The amount to bill

ABOUT
}

sub handler {
    my $self = shift;
    my $env = shift;

    my $e = new_editor(xact => 1);
    my $btype = $e->retrieve_config_billing_type(OILS_BILLING_TYPE_NOTIFICATION_FEE);

    my $circ = $$env{target};
    my $amount = $$env{params}{amount} || $btype->default_price;

    unless($amount) {
        $logger->error("ApplyCircFee needs a fee amount");
        $e->rollback;
        return 0;
    }

    my $bill = Fieldmapper::money::billing->new;
    $bill->xact($circ->id);
    $bill->amount($amount);
    $bill->btype(OILS_BILLING_TYPE_NOTIFICATION_FEE);
    $bill->billing_type($btype->name);
    $bill->note($self->run_TT($env));

    unless( $e->create_money_billing($bill) ) {
        $e->rollback;
        return 0;
    }
        
    $e->commit;
    return 1;
}

1;
