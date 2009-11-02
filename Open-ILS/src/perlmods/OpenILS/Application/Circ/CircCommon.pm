package OpenILS::Application::Circ::CircCommon;
use strict; use warnings;
use DateTime;
use DateTime::Format::ISO8601;
use OpenILS::Application::AppUtils;
use OpenSRF::Utils qw/:datetime/;
use OpenILS::Event;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Const qw/:const/;

my $U = "OpenILS::Application::AppUtils";

# -----------------------------------------------------------------
# Do not publish methods here.  This code is shared across apps.
# -----------------------------------------------------------------


# -----------------------------------------------------------------
# Voids overdue fines on the given circ.  if a backdate is 
# provided, then we only void back to the backdate
# -----------------------------------------------------------------
sub void_overdues {
    my($class, $e, $circ, $backdate, $note) = @_;

    my $bill_search = { 
        xact => $circ->id, 
        btype => 1 
    };

    if( $backdate ) {
        # ------------------------------------------------------------------
        # Fines for overdue materials are assessed up to, but not including,
        # one fine interval after the fines are applicable.  Here, we add
        # one fine interval to the backdate to ensure that we are not 
        # voiding fines that were applicable before the backdate.
        # ------------------------------------------------------------------

        # if there is a raw time component (e.g. from postgres), 
        # turn it into an interval that interval_to_seconds can parse
        my $duration = $circ->fine_interval;
        $duration =~ s/(\d{2}):(\d{2}):(\d{2})/$1 h $2 m $3 s/o;
        my $interval = OpenSRF::Utils->interval_to_seconds($duration);

        my $date = DateTime::Format::ISO8601->parse_datetime($backdate);
        $backdate = $U->epoch2ISO8601($date->epoch + $interval);
        $logger->info("applying backdate $backdate in overdue voiding");
        $$bill_search{billing_ts} = {'>=' => $backdate};
    }

    my $bills = $e->search_money_billing($bill_search);
    
    for my $bill (@$bills) {
        next if $U->is_true($bill->voided);
        $logger->info("voiding overdue bill ".$bill->id);
        $bill->voided('t');
        $bill->void_time('now');
        $bill->voider($e->requestor->id);
        my $n = ($bill->note) ? sprintf("%s\n", $bill->note) : "";
        $bill->note(sprintf("$n%s", ($note) ? $note : "System: VOIDED FOR BACKDATE"));
        $e->update_money_billing($bill) or return $e->die_event;
    }

	return undef;
}


sub reopen_xact {
    my($class, $e, $xactid) = @_;

    # -----------------------------------------------------------------
    # make sure the transaction is not closed
    my $xact = $e->retrieve_money_billable_transaction($xactid)
        or return $e->die_event;

    if( $xact->xact_finish ) {
        my ($mbts) = $U->fetch_mbts($xactid, $e);
        if( $mbts->balance_owed != 0 ) {
            $logger->info("* re-opening xact $xactid, orig xact_finish is ".$xact->xact_finish);
            $xact->clear_xact_finish;
            $e->update_money_billable_transaction($xact)
                or return $e->die_event;
        } 
    }

    return undef;
}


sub create_bill {
	my($class, $e, $amount, $btype, $type, $xactid, $note) = @_;

	$logger->info("The system is charging $amount [$type] on xact $xactid");
    $note ||= 'SYSTEM GENERATED';

    # -----------------------------------------------------------------
    # now create the billing
	my $bill = Fieldmapper::money::billing->new;
	$bill->xact($xactid);
	$bill->amount($amount);
	$bill->billing_type($type); 
	$bill->btype($btype); 
	$bill->note($note);
    $e->create_money_billing($bill) or return $e->die_event;

	return undef;
}

1;
