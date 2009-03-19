package OpenILS::Application::Trigger::Reactor::ApplyCircFee;
use base 'OpenILS::Application::Trigger::Reactor';
use strict; use warnings;
use Error qw/:try/;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor q/:funcs/;


sub ABOUT {
    return <<ABOUT;
    
    Creates a bill (money.billing) for the configured amount, 
    linked to the circulation.

    Required event parameters:
        "amount" The amount to bill
        "btype" The config.billing_type ID
    Optional event parameters:
        "note" Billing note

ABOUT
}

sub handler {
    my $self = shift;
    my $env = shift;

    my $circ = $$env{target};
    my $amount = $$env{params}{amount};
    my $btype = $$env{params}{btype};
    my $note = $$env{params}{note};

    unless($circ and $amount and $btype) {
        $logger->error("ApplyCircFee requires 'amount' and 'btype' params");
        return 0;
    }
        
    my $e = new_editor(xact => 1);
    my $type = $e->retrieve_config_billing_type($btype);

    unless($type) {
        $logger->error("'$btype' is not a valid config.billing_type ID");
        $e->rollback;
        return 0;
    }

    my $bill = Fieldmapper::money::billing->new;
    $bill->xact($circ->id);
    $bill->amount($amount);
    $bill->note($note);
    $bill->btype($btype);
    $bill->billing_type($type->name);

    unless( $e->create_money_billing($bill) ) {
        $e->rollback;
        return 0;
    }
        
    $e->commit;
    return 1;
}

1;
