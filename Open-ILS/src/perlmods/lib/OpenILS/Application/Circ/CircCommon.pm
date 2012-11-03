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
# provided, then we only void back to the backdate, unless the
# backdate is to within the grace period, in which case we void all
# overdue fines.
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
        my $due_date = DateTime::Format::ISO8601->parse_datetime(cleanse_ISO8601($circ->due_date))->epoch;
        my $grace_period = extend_grace_period( $class, $circ->circ_lib, $circ->due_date, OpenSRF::Utils->interval_to_seconds($circ->grace_period), $e);
        if($date->epoch <= $due_date + $grace_period) {
            $logger->info("backdate $backdate is within grace period, voiding all");
        } else {
            $backdate = $U->epoch2ISO8601($date->epoch + $interval);
            $logger->info("applying backdate $backdate in overdue voiding");
            $$bill_search{billing_ts} = {'>=' => $backdate};
        }
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

sub extend_grace_period {
    my($class, $circ_lib, $due_date, $grace_period, $e, $h) = @_;
    if ($grace_period >= 86400) { # Only extend grace periods greater than or equal to a full day
        my $parser = DateTime::Format::ISO8601->new;
        my $due_dt = $parser->parse_datetime( cleanse_ISO8601( $due_date ) );
        my $due = $due_dt->epoch;

        my $grace_extend = $U->ou_ancestor_setting_value($circ_lib, 'circ.grace.extend');
        $e = new_editor() if (!$e);
        $h = $e->retrieve_actor_org_unit_hours_of_operation($circ_lib) if (!$h);
        if ($grace_extend and $h) { 
            my $new_grace_period = $grace_period;

            $logger->info( "Circ lib has an hours-of-operation entry and grace period extension is enabled." );

            my $closed = 0;
            my %h_closed = {};
            for my $i (0 .. 6) {
                my $dow_open = "dow_${i}_open";
                my $dow_close = "dow_${i}_close";
                if($h->$dow_open() eq '00:00:00' and $h->$dow_close() eq '00:00:00') {
                    $closed++;
                    $h_closed{$i} = 1;
                } else {
                    $h_closed{$i} = 0;
                }
            }

            if($closed == 7) {
                $logger->info("Circ lib is closed all week according to hours-of-operation entry. Skipping grace period extension checks.");
            } else {
                # Extra nice grace periods
                # AKA, merge closed dates trailing the grace period into the grace period
                my $grace_extend_into_closed = $U->ou_ancestor_setting_value($circ_lib, 'circ.grace.extend.into_closed');
                $due += 86400 if $grace_extend_into_closed;

                my $grace_extend_all = $U->ou_ancestor_setting_value($circ_lib, 'circ.grace.extend.all');

                if ( $grace_extend_all ) {
                    # Start checking the day after the item was due
                    # This is "The grace period only counts open days"
                    # NOTE: Adding 86400 seconds is not the same as adding one day. This uses seconds intentionally.
                    $due_dt = $due_dt->add( seconds => 86400 );
                } else {
                    # Jump to the end of the grace period
                    # This is "If the grace period ends on a closed day extend it"
                    # NOTE: This adds grace period as a number of seconds intentionally
                    $due_dt = $due_dt->add( seconds => $grace_period );
                }

                my $count = 0; # Infinite loop protection
                do {
                    $closed = 0; # Starting assumption for day: We are not closed
                    $count++; # We limit the number of loops below.

                    # get the day of the week for the day we are looking at
                    my $dow = $due_dt->day_of_week_0;

                    # Check hours of operation first.
                    if ($h_closed{$dow}) {
                        $closed = 1;
                        $new_grace_period += 86400;
                        $due_dt->add( seconds => 86400 );
                    } else {
                        # Check for closed dates for this period
                        my $timestamptz = $due_dt->strftime('%FT%T%z');
                        my $cl = $e->search_actor_org_unit_closed_date(
                                { close_start => { '<=' => $timestamptz },
                                  close_end   => { '>=' => $timestamptz },
                                  org_unit    => $circ_lib }
                        );
                        if ($cl and @$cl) {
                            $closed = 1;
                            foreach (@$cl) {
                                my $cl_dt = $parser->parse_datetime( cleanse_ISO8601( $_->close_end ) );
                                while ($due_dt <= $cl_dt) {
                                    $due_dt->add( seconds => 86400 );
                                    $new_grace_period += 86400;
                                }
                            }
                        } else {
                            $due_dt->add( seconds => 86400 );
                        }
                    }
                } while ( $count <= 366 and ( $closed or $due_dt->epoch <= $due + $new_grace_period ) );
                if ($new_grace_period > $grace_period) {
                    $grace_period = $new_grace_period;
                    $logger->info( "Grace period for circ extended to $grace_period [" . seconds_to_interval( $grace_period ) . "]" );
                }
            }
        }
    }
    return $grace_period;
}

# check if a circulation transaction can be closed
# takes a CStoreEditor and a circ transaction.
# Returns 1 if the circ should be closed, 0 if not.
sub can_close_circ {
    my ($class, $e, $circ) = @_;
    my $can_close = 0;

    my $reason = $circ->stop_fines;

    # We definitely want to close if this circulation was
    # checked in or renewed.
    if ($circ->checkin_time) {
        $can_close = 1;
    } elsif ($reason eq OILS_STOP_FINES_LOST) {
        # Check the copy circ_lib to see if they close
        # transactions when lost are paid.
        my $copy = $e->retrieve_asset_copy($circ->target_copy);
        if ($copy) {
            $can_close = !$U->is_true(
                $U->ou_ancestor_setting_value(
                    $copy->circ_lib,
                    'circ.lost.xact_open_on_zero',
                    $e
                )
            );
        }
    }
    return $can_close;
}

1;
