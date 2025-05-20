package OpenILS::Application::Circ::CircCommon;
use strict; use warnings;
use DateTime;
use DateTime::Format::ISO8601;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::DateTime qw/:datetime/;
use OpenILS::Event;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Const qw/:const/;
use POSIX qw(ceil);
use List::MoreUtils qw(uniq);

my $U = "OpenILS::Application::AppUtils";
my $parser = DateTime::Format::ISO8601->new;

# -----------------------------------------------------------------
# Do not publish methods here.  This code is shared across apps.
# -----------------------------------------------------------------


# -----------------------------------------------------------------
# Voids (or zeros) overdue fines on the given circ.  if a backdate is 
# provided, then we only void back to the backdate, unless the
# backdate is to within the grace period, in which case we void all
# overdue fines.
# -----------------------------------------------------------------
sub void_overdues {
#compatibility layer - TODO
}
sub void_or_zero_overdues {
    my($class, $e, $circ, $opts) = @_;

    my $bill_search = { 
        xact => $circ->id, 
        btype => 1 
    };

    if( $opts->{backdate} ) {
        my $backdate = $opts->{backdate};
        $opts->{note} = 'System: OVERDUE REVERSED FOR BACKDATE' if !$opts->{note};
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
        my $interval = OpenILS::Utils::DateTime->interval_to_seconds($duration);

        my $date = DateTime::Format::ISO8601->parse_datetime(clean_ISO8601($backdate));
        my $due_date = DateTime::Format::ISO8601->parse_datetime(clean_ISO8601($circ->due_date))->epoch;
        my $grace_period = extend_grace_period( $class, $circ->circ_lib, $circ->due_date, OpenILS::Utils::DateTime->interval_to_seconds($circ->grace_period), $e);
        if($date->epoch <= $due_date + $grace_period) {
            $logger->info("backdate $backdate is within grace period, voiding all");
        } else {
            $backdate = $U->epoch2ISO8601($date->epoch + $interval);
            $logger->info("applying backdate $backdate in overdue voiding");
            $$bill_search{billing_ts} = {'>=' => $backdate};
        }
    }

    my $billids = $e->search_money_billing([$bill_search, {idlist=>1}]);
    if ($billids && @$billids) {
        # overdue settings come from transaction org unit
        my $prohibit_neg_balance_overdues = (
            $U->ou_ancestor_setting_value($circ->circ_lib(), 'bill.prohibit_negative_balance_on_overdues')
            ||
            $U->ou_ancestor_setting_value($circ->circ_lib(), 'bill.prohibit_negative_balance_default')
        );
        my $neg_balance_interval_overdues = (
            $U->ou_ancestor_setting_value($circ->circ_lib(), 'bill.negative_balance_interval_on_overdues')
            ||
            $U->ou_ancestor_setting_value($circ->circ_lib(), 'bill.negative_balance_interval_default')
        );
        my $result;
        # if we prohibit negative overdue balances and all payments
        # are outside the refund interval (if given), zero the transaction
        if ($opts->{force_zero}
            or (!$opts->{force_void}
                and (
                    $U->is_true($prohibit_neg_balance_overdues)
                    and !_has_refundable_payments($e, $circ->id, $neg_balance_interval_overdues)
                )
            )
        ) {
            $result = $class->adjust_bills_to_zero($e, $billids, $opts->{note}, $neg_balance_interval_overdues);
        } else {
            # otherwise, just void the usual way
            $result = $class->void_bills($e, $billids, $opts->{note});
        }
        if (ref($result)) {
            return $result;
        }
    }

    return undef;
}

# ------------------------------------------------------------------
# remove charge from patron's account if lost item is returned
# ------------------------------------------------------------------
sub void_lost {
    my ($class, $e, $circ, $btype) = @_;

    my $bills = $e->search_money_billing(
        {
            xact => $circ->id,
            btype => $btype,
            voided => 'f'
        }
    );

    $logger->debug("voiding lost item charge of  ".scalar(@$bills));
    for my $bill (@$bills) {
        if( !$U->is_true($bill->voided) ) {
            $logger->info("lost item returned - voiding bill ".$bill->id);
            $bill->voided('t');
            $bill->void_time('now');
            $bill->voider($e->requestor->id);
            my $note = ($bill->note) ? $bill->note . "\n" : '';
            $bill->note("${note}System: VOIDED FOR LOST ITEM RETURNED");

            return $e->event
                unless $e->update_money_billing($bill);
        }
    }
    return undef;
}

# ------------------------------------------------------------------
# Void (or zero) all bills of a given type on a circulation.
#
# Takes an editor, a circ object, the btype number for the bills you
# want to void, and an optional note.
#
# Returns undef on success or the result from void_bills.
# ------------------------------------------------------------------
sub void_or_zero_bills_of_type {
    my ($class, $e, $circ, $copy, $btype, $for_note) = @_;

    my $billids = $e->search_money_billing(
        {xact => $circ->id(), btype => $btype},
        {idlist=>1}
    );
    if ($billids && @$billids) {
        # settings for lost come from copy circlib.
        my $prohibit_neg_balance_lost = (
            $U->ou_ancestor_setting_value($copy->circ_lib(), 'bill.prohibit_negative_balance_on_lost')
            ||
            $U->ou_ancestor_setting_value($copy->circ_lib(), 'bill.prohibit_negative_balance_default')
        );
        my $neg_balance_interval_lost = (
            $U->ou_ancestor_setting_value($copy->circ_lib(), 'bill.negative_balance_interval_on_lost')
            ||
            $U->ou_ancestor_setting_value($copy->circ_lib(), 'bill.negative_balance_interval_default')
        );
        my $result;
        if (
            $U->is_true($prohibit_neg_balance_lost)
            and !_has_refundable_payments($e, $circ->id, $neg_balance_interval_lost)
        ) {
            $result = $class->adjust_bills_to_zero($e, $billids, "System: ADJUSTED $for_note");
        } else {
            $result = $class->void_bills($e, $billids, "System: VOIDED $for_note");
        }
        if (ref($result)) {
            return $result;
        }
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
    my($class, $e, $amount, $btype, $type, $xactid, $note, $period_start, $period_end) = @_;

    $logger->info("The system is charging $amount [$type] on xact $xactid");
    $note ||= 'SYSTEM GENERATED';

    # -----------------------------------------------------------------
    # now create the billing
    my $bill = Fieldmapper::money::billing->new;
    $bill->xact($xactid);
    $bill->amount($amount);
    $bill->period_start($period_start);
    $bill->period_end($period_end);
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
        my $due_dt = $parser->parse_datetime( clean_ISO8601( $due_date ) );
        my $due = $due_dt->epoch;

        my $grace_extend = $U->ou_ancestor_setting_value($circ_lib, 'circ.grace.extend');
        $e = new_editor() if (!$e);
        $h = $e->retrieve_actor_org_unit_hours_of_operation($circ_lib) if (!$h);
        if ($grace_extend and $h) { 
            my $new_grace_period = $grace_period;

            $logger->info( "Circ lib has an hours-of-operation entry and grace period extension is enabled." );

            my $closed = 0;
            my %h_closed;
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
                                my $cl_dt = $parser->parse_datetime( clean_ISO8601( $_->close_end ) );
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

    } elsif ($reason eq OILS_STOP_FINES_LONGOVERDUE) {
        # Check the copy circ_lib to see if they close
        # transactions when long-overdue are paid.
        my $copy = $e->retrieve_asset_copy($circ->target_copy);
        if ($copy) {
            $can_close = !$U->is_true(
                $U->ou_ancestor_setting_value(
                    $copy->circ_lib,
                    'circ.longoverdue.xact_open_on_zero',
                    $e
                )
            );
        }
    }

    return $can_close;
}

sub maybe_close_xact {
    my ($class, $e, $xact_id) = @_;

    my $circ = $e->retrieve_action_circulation(
        [
            $xact_id,
            {
                flesh => 1,
                flesh_fields => {circ => ['target_copy','billings']}
            }
        ]
    ); # Flesh the copy, so we can monkey with the status if
       # necessary.

    # Whether or not we close the transaction. We definitely close if no
    # circulation transaction is present, otherwise we check if the circulation
    # is in a state that allows itself to be closed.
    if (!$circ || can_close_circ($class, $e, $circ)) {
        my $billable_xact = $e->retrieve_money_billable_transaction($xact_id);
        $billable_xact->xact_finish("now");
        if (!$e->update_money_billable_transaction($billable_xact)) {
            return {
                message => "update_money_billable_transaction() failed",
                evt => $e->die_event
            };
        }

        # If we have a circ, we need to check if the copy status is lost or
        # long overdue.  If it is then we check org_unit_settings for the copy
        # owning library and adjust and possibly adjust copy status to lost and
        # paid.
        if ($circ && ($circ->stop_fines eq 'LOST' || $circ->stop_fines eq 'LONGOVERDUE')) {
            # We need the copy to check settings and to possibly
            # change its status.
            my $copy = $circ->target_copy();
            # Library where we'll check settings.
            my $check_lib = $copy->circ_lib();

            # check the copy status
            if (($copy->status() == OILS_COPY_STATUS_LOST || $copy->status() == OILS_COPY_STATUS_LONG_OVERDUE)
                    && $U->is_true($U->ou_ancestor_setting_value($check_lib, 'circ.use_lost_paid_copy_status', $e))) {
                $copy->status(OILS_COPY_STATUS_LOST_AND_PAID);
                if (!$e->update_asset_copy($copy)) {
                    return {
                        message => "update_asset_copy_failed()",
                        evt => $e->die_event
                    };
                }
            }
        }
    }
}


sub seconds_to_interval_hash {
        my $interval = shift;
        my $limit = shift || 's';
        $limit =~ s/^(.)/$1/o;

        my %output;

        my ($y,$ym,$M,$Mm,$w,$wm,$d,$dm,$h,$hm,$m,$mm,$s);
        my ($year, $month, $week, $day, $hour, $minute, $second) =
                ('years','months','weeks','days', 'hours', 'minutes', 'seconds');

        if ($y = int($interval / (60 * 60 * 24 * 365))) {
                $output{$year} = $y;
                $ym = $interval % (60 * 60 * 24 * 365);
        } else {
                $ym = $interval;
        }
        return %output if ($limit eq 'y');

        if ($M = int($ym / ((60 * 60 * 24 * 365)/12))) {
                $output{$month} = $M;
                $Mm = $ym % ((60 * 60 * 24 * 365)/12);
        } else {
                $Mm = $ym;
        }
        return %output if ($limit eq 'M');

        if ($w = int($Mm / 604800)) {
                $output{$week} = $w;
                $wm = $Mm % 604800;
        } else {
                $wm = $Mm;
        }
        return %output if ($limit eq 'w');

        if ($d = int($wm / 86400)) {
                $output{$day} = $d;
                $dm = $wm % 86400;
        } else {
                $dm = $wm;
        }
        return %output if ($limit eq 'd');

        if ($h = int($dm / 3600)) {
                $output{$hour} = $h;
                $hm = $dm % 3600;
        } else {
                $hm = $dm;
        }
        return %output if ($limit eq 'h');

        if ($m = int($hm / 60)) {
                $output{$minute} = $m;
                $mm = $hm % 60;
        } else {
                $mm = $hm;
        }
        return %output if ($limit eq 'm');

        if ($s = int($mm)) {
                $output{$second} = $s;
        } else {
                $output{$second} = 0 unless (keys %output);
        }
        return %output;
}

sub generate_fines {
    my ($class, $args) = @_;
    my $circs = $args->{circs};
    return unless $circs and @$circs;
    my $e = $args->{editor};
    # if a client connection is passed in, this will be chatty like
    # the old storage version
    my $conn = $args->{conn};

    my $commit = 0;
    unless ($e) {
        # Transactions are opened/closed with each circ, reservation, etc.
        # The first $e->xact_begin (below) will cause a connect.
        $e = new_editor();
        $commit = 1;
    }

    my %hoo = map { ( $_->id => $_ ) } @{ $e->retrieve_all_actor_org_unit_hours_of_operation };

    my $handling_resvs = 0;
    for my $c (@$circs) {

        my $ctype = ref($c);

        if (!$ctype) { # we received only an idlist, not objects
            if ($handling_resvs) {
                $c = $e->retrieve_booking_reservation($c);
            } elsif (not defined $c) {
                # an undef value is the indicator that we are moving
                # from processing circulations to reservations.
                $handling_resvs = 1;
                next;
            } else {
                $c = $e->retrieve_action_circulation($c);
            }
            $ctype = ref($c);
        }

        $ctype =~ s/^.+::(\w+)$/$1/;
    
        my $due_date_method = 'due_date';
        my $target_copy_method = 'target_copy';
        my $circ_lib_method = 'circ_lib';
        my $recurring_fine_method = 'recurring_fine';
        my $is_reservation = 0;
        if ($ctype eq 'reservation') {
            $is_reservation = 1;
            $due_date_method = 'end_time';
            $target_copy_method = 'current_resource';
            $circ_lib_method = 'pickup_lib';
            $recurring_fine_method = 'fine_amount';
            next unless ($c->fine_interval);
        }
        #TODO: reservation grace periods
        my $grace_period = ($is_reservation ? 0 : interval_to_seconds($c->grace_period));

        eval {

            # Clean up after previous transaction.  
            # This is a no-op if there is no open transaction.
            $e->xact_rollback if $commit;

            $logger->info(sprintf("Processing $ctype %d...", $c->id));

            # each (ils) transaction is processed in its own (db) transaction
            $e->xact_begin if $commit;

            my $due_dt = $parser->parse_datetime( clean_ISO8601( $c->$due_date_method ) );
    
            my $due = $due_dt->epoch;
            my $now = time;

            my $fine_interval = $c->fine_interval;
            $fine_interval =~ s/(\d{2}):(\d{2}):(\d{2})/$1 h $2 m $3 s/o;
            $fine_interval = interval_to_seconds( $fine_interval );
    
            if ( $fine_interval == 0 || $c->$recurring_fine_method * 100 == 0 || $c->max_fine * 100 == 0 ) {
                $conn->respond( "Fine Generator skipping circ due to 0 fine interval, 0 fine rate, or 0 max fine.\n" ) if $conn;
                $logger->info( "Fine Generator skipping circ " . $c->id . " due to 0 fine interval, 0 fine rate, or 0 max fine." );
                return;
            }

            if ( $is_reservation and $fine_interval >= interval_to_seconds('1d') ) {    
                my $tz_offset_s = 0;
                if ($due_dt->strftime('%z') =~ /(-|\+)(\d{2}):?(\d{2})/) {
                    $tz_offset_s = $1 . interval_to_seconds( "${2}h ${3}m"); 
                }
    
                $due -= ($due % $fine_interval) + $tz_offset_s;
                $now -= ($now % $fine_interval) + $tz_offset_s;
            }
    
            $conn->respond(
                "ARG! Overdue $ctype ".$c->id.
                " for item ".$c->$target_copy_method.
                " (user ".$c->usr.").\n".
                "\tItem was due on or before: ".localtime($due)."\n") if $conn;
    
            my @fines = @{$e->search_money_billing([
                { xact => $c->id,
                  btype => 1,
                  billing_ts => { '>' => $c->$due_date_method } },
                { order_by => {mb => 'billing_ts DESC'},
                  flesh => 1,
                  flesh_fields => {mb => ['adjustments']} }
            ])};

            my $f_idx = 0;
            my $fine = $fines[$f_idx] if (@fines);
            my $current_fine_total = 0;
            $current_fine_total += $_->amount * 100 for (grep { $_ and !$U->is_true($_->voided) } @fines);
            $current_fine_total -= $_->amount * 100 for (map { @{$_->adjustments} } @fines);
    
            my $last_fine;
            if ($fine) {
                $conn->respond( "Last billing time: ".$fine->billing_ts." (clensed format: ".clean_ISO8601( $fine->billing_ts ).")") if $conn;
                $last_fine = $parser->parse_datetime( clean_ISO8601( $fine->billing_ts ) )->epoch;
            } else {
                $logger->info( "Potential first billing for circ ".$c->id );
                $last_fine = $due;

                $grace_period = extend_grace_period($class, $c->$circ_lib_method,$c->$due_date_method,$grace_period,undef,$hoo{$c->$circ_lib_method});
            }

            return if ($last_fine > $now);
            # Generate fines for each past interval, including the one we are inside
            my $pending_fine_count = ceil( ($now - $last_fine) / $fine_interval );

            if ( $last_fine == $due                         # we have no fines yet
                 && $grace_period                           # and we have a grace period
                 && $now < $due + $grace_period             # and some date math says were are within the grace period
            ) {
                $conn->respond( "Still inside grace period of: ". seconds_to_interval( $grace_period )."\n" ) if $conn;
                $logger->info( "Circ ".$c->id." is still inside grace period of: $grace_period [". seconds_to_interval( $grace_period ).']' );
                return;
            }

            $conn->respond( "\t$pending_fine_count pending fine(s)\n" ) if $conn;
            return unless ($pending_fine_count);

            my $recurring_fine = $c->$recurring_fine_method * 100;
            my $max_fine = $c->max_fine * 100;

            my $skip_closed_check = $U->ou_ancestor_setting_value(
                $c->$circ_lib_method, 'circ.fines.charge_when_closed');
            $skip_closed_check = $U->is_true($skip_closed_check);

            my $truncate_to_max_fine = $U->ou_ancestor_setting_value(
                $c->$circ_lib_method, 'circ.fines.truncate_to_max_fine');
            $truncate_to_max_fine = $U->is_true($truncate_to_max_fine);

            my $tz = $U->ou_ancestor_setting_value(
                $c->$circ_lib_method, 'lib.timezone') || 'local';

            my ($latest_period_end, $latest_amount) = ('',0);
            for (my $bill = 1; $bill <= $pending_fine_count; $bill++) {
    
                if ($current_fine_total >= $max_fine) {
                    if ($ctype eq 'circulation') {
                        $c->stop_fines('MAXFINES');
                        $c->stop_fines_time('now');
                        $e->update_action_circulation($c);
                    }
                    $conn->respond(
                        "\tMaximum fine level of ".$c->max_fine.
                        " reached for this $ctype.\n".
                        "\tNo more fines will be generated.\n" ) if $conn;
                    last;
                }
                
                # Use org time zone (or default to 'local')
                my $period_end = DateTime->from_epoch( epoch => $last_fine, time_zone => $tz );
                my $current_bill_count = $bill;
                while ( $current_bill_count ) {
                    $period_end->add( seconds_to_interval_hash( $fine_interval ) );
                    $current_bill_count--;
                }
                my $period_start = $period_end->clone->subtract( seconds_to_interval_hash( $fine_interval - 1 ) );

                my $timestamptz = $period_end->strftime('%FT%T%z');
                if (!$skip_closed_check) {
                    my $dow = $period_end->day_of_week_0();
                    my $dow_open = "dow_${dow}_open";
                    my $dow_close = "dow_${dow}_close";

                    if (my $h = $hoo{$c->$circ_lib_method}) {
                        next if ( $h->$dow_open eq '00:00:00' and $h->$dow_close eq '00:00:00');
                    }
    
                    my @cl = @{$e->search_actor_org_unit_closed_date(
                            { close_start   => { '<=' => $timestamptz },
                              close_end => { '>=' => $timestamptz },
                              org_unit  => $c->$circ_lib_method }
                    )};
                    next if (@cl);
                }

                # The billing amount for this billing normally ought to be the recurring fine amount.
                # However, if the recurring fine amount would cause total fines to exceed the max fine amount,
                # we may wish to reduce the amount for this billing (if circ.fines.truncate_to_max_fine is true).
                my $this_billing_amount = $recurring_fine;
                if ( $truncate_to_max_fine && ($current_fine_total + $this_billing_amount) > $max_fine ) {
                    $this_billing_amount = ($max_fine - $current_fine_total);
                }
                $current_fine_total += $this_billing_amount;
                $latest_amount += $this_billing_amount;
                $latest_period_end = $timestamptz;

                my $bill = Fieldmapper::money::billing->new;
                $bill->xact($c->id);
                $bill->note("System Generated Overdue Fine");
                $bill->billing_type("Overdue materials");
                $bill->btype(1);
                $bill->amount(sprintf('%0.2f', $this_billing_amount/100));
                $bill->period_start($period_start->strftime('%FT%T%z'));
                $bill->period_end($timestamptz);
                $e->create_money_billing($bill);

            }

            $conn->respond( "\t\tAdding fines totaling $latest_amount for overdue up to $latest_period_end\n" )
                if ($conn and $latest_period_end and $latest_amount);


            # Calculate penalties inline
            OpenILS::Utils::Penalty->calculate_penalties(
                $e, $c->usr, $c->$circ_lib_method);

            $e->xact_commit if $commit;

        };

        if ($@) {
            my $e = $@;
            $conn->respond( "Error processing overdue $ctype [".$c->id."]:\n\n$e\n" ) if $conn;
            $logger->error("Error processing overdue $ctype [".$c->id."]:\n$e\n");
            last if ($e =~ /IS NOT CONNECTED TO THE NETWORK/o);
        }
    }

    # roll back any (potentially) orphaned transaction and disconnect.
    $e->rollback if $commit;

    return undef;
}

# -----------------------------------------------------------------
# Given an editor and a xact (or id), return a reference to an array of
# hashrefs that map billing objects to payment objects.  Returns undef
# if no bills are found for the given transaction.
#
# The bill amounts are adjusted to reflect the application of the
# payments to the bills.  The original bill amounts are retained in
# the mapping.
#
# The payment objects may or may not have their amounts adjusted
# depending on whether or not they apply to more than one bill.  We
# could really use a better logic here, perhaps, but if it was
# consistent, it wouldn't be Evergreen.
#
# The data structure used in the array is a hashref that has the
# following fields:
#
# bill => the adjusted bill object
# adjustments => an arrayref of account adjustments that apply directly
#                to the bill
# payments => an arrayref of payment objects applied to the bill
# refundable_payments => an arrayref of payment objects applied to the
#                        bill that can be refunded
# non_refundable_payments => an arrayref of payment objects applied to
#                            the bill that CANNOT be refunded
# bill_amount => original amount from the billing object
# adjustment_amount => total of the account adjustments that apply
#                      directly to the bill
#
# Each bill is only mapped to payments one time.  However, a single
# payment may be mapped to more than one bill if the payment amount is
# greater than the amount of each individual bill, such as a $3.00
# payment for 30 $0.10 overdue bills.  There is an attempt made to
# first pay bills with payments that match the billing amount.  This
# is intended to catch payments for lost and/or long overdue bills so
# that they will match up.
#
# This function is heavily adapted from code written by Jeff Godin of
# Traverse Area District Library and submitted on LaunchPad bug
# #1009049.
# -----------------------------------------------------------------
sub bill_payment_map_for_xact {
    my ($class, $e, $xact) = @_;
    $xact = $xact->id if ref($xact);

    # Check for CStoreEditor and make a new one if we have to. This
    # allows one-off calls to this subroutine to pass undef as the
    # CStoreEditor and not have to create one of their own.
    $e = OpenILS::Utils::CStoreEditor->new unless ($e);

    # find all bills in order
    my $bill_search = [
        { xact => $xact, voided => 'f' },
        { order_by => { mb => { billing_ts => { direction => 'asc' } } } },
    ];

    # At some point, we should get rid of the voided column on
    # money.payment and family.  It is not exposed in the client at
    # the moment, and should be replaced with a void_bill type.  The
    # descendants of money.payment don't expose the voided field in
    # the fieldmapper, only the mp object, based on the money.payment
    # view, does.  However, I want to leave that complication for
    # later.  I wonder if I'm not slowing things down too much with
    # the current account_adjustment logic.  It would probably be faster if
    # we had direct Pg access at this layer.  I can probably wrangle
    # something via the drivers or store interfaces, but I haven't
    # really figured those out, yet.

    my $bills = $e->search_money_billing($bill_search);

    # return undef if there are no bills.
    return undef unless ($bills && @$bills);

    # map the bills into our bill_payment_map entry format:
    my @entries = map {
        {
            bill => $_,
            bill_amount => $_->amount(),
            payments => [],
            adjustments => [],
            adjustment_amount => 0
        }
    } @$bills;

    # Find all unvoided payments in order.  Flesh account adjustments
    # so that we don't have to retrieve them later.
    my $payments = $e->search_money_payment(
        [
            { xact => $xact, voided=>'f' },
            {
                order_by => { mp => { payment_ts => { direction => 'asc' } } },
                flesh => 1,
                flesh_fields => { mp => ['account_adjustment'] }
            }
        ]
    );

    # If there were no payments, then we just return the bills.
    return \@entries unless ($payments && @$payments);

    # Now, we go through the rigmarole of mapping payments to bills
    # and adjusting the bill balances.

    # Apply the adjustments before "paying" other bills.
    foreach my $entry (@entries) {
        my $bill = $entry->{bill};
        # Find only the adjustments that apply to individual bills.
        my @adjustments = map {$_->account_adjustment()} grep {$_->payment_type() eq 'account_adjustment' && $_->account_adjustment()->billing() == $bill->id()} @$payments;
        if (@adjustments) {
            foreach my $adjustment (@adjustments) {
                my $new_amount = $U->fpdiff($bill->amount(),$adjustment->amount());
                if ($new_amount >= 0) {
                    push @{$entry->{adjustments}}, $adjustment;
                    $entry->{adjustment_amount} += $adjustment->amount();
                    $bill->amount($new_amount);
                    # Remove the used up adjustment from list of payments:
                    my @p = grep {$_->id() != $adjustment->id()} @$payments;
                    $payments = \@p;
                } else {
                    # It should never happen that we have more adjustment
                    # payments on a single bill than the amount of the
                    # bill.  However, experience shows that the things
                    # that should never happen actually do happen with
                    # surprising regularity in a library setting.

                    # Clone the adjustment to say how much of it actually
                    # applied to this bill.
                    my $new_adjustment = $adjustment->clone();
                    $new_adjustment->amount($bill->amount());
                    $new_adjustment->amount_collected($bill->amount());
                    push (@{$entry->{adjustments}}, $new_adjustment);
                    $entry->{adjustment_amount} += $new_adjustment->amount();
                    $bill->amount(0);
                    $adjustment->amount(-$new_amount);
                    # Could be a candidate for YAOUS about what to do
                    # with excess adjustment amounts on a bill.
                }
                last if ($bill->amount() == 0);
            }
        }
    }

    # Try to map payments to bills by amounts starting with the
    # largest payments.
    # To avoid modifying the array we're iterating over (which can result in a
    # "Use of freed value in iteration" error), we create a copy of the
    # payments array and remove handled payments from that instead.
    my @handled_payments = @$payments;
    foreach my $payment (sort {$b->amount() <=> $a->amount()} @$payments) {
        my @bills2pay = grep {$_->{bill}->amount() == $payment->amount()} @entries;
        if (@bills2pay) {
            my $entry = $bills2pay[0];
            $entry->{bill}->amount(0);
            push @{$entry->{payments}}, $payment;
            # Remove the payment from the master list.
            my @p = grep {$_->id() != $payment->id()} @handled_payments;
            @handled_payments = @p;
        }
    }
    # Now, update our list of payments so that it only includes unhandled
    # (unmapped) payments.
    $payments = \@handled_payments;

    # Map remaining bills to payments in whatever order.
    foreach  my $entry (grep {$_->{bill}->amount() > 0} @entries) {
        my $bill = $entry->{bill};
        # We could run out of payments before bills.
        if ($payments && @$payments) {
            while ($bill->amount() > 0) {
                my $payment = shift @$payments;
                last unless $payment;
                my $new_amount = $U->fpdiff($bill->amount(),$payment->amount());
                if ($new_amount < 0) {
                    # Clone the payment so we can say how much applied
                    # to this bill.
                    my $new_payment = $payment->clone();
                    $new_payment->amount($bill->amount());
                    $bill->amount(0);
                    push @{$entry->{payments}}, $new_payment;
                    # Reset the payment amount and put it back on the
                    # list for later use.
                    $payment->amount(-$new_amount);
                    unshift @$payments, $payment;
                } else {
                    $bill->amount($new_amount);
                    push @{$entry->{payments}}, $payment;
                }
            }
        }

        $entry->{refundable_payments} = [ grep {$U->is_true($_->refundable)} @{$entry->{payments}} ];
        $entry->{non_refundable_payments} = [ grep {!$U->is_true($_->refundable)} @{$entry->{payments}} ];
    }

    return \@entries;
}


# This subroutine actually handles voiding of bills.  It takes a
# CStoreEditor, an arrayref of bill ids or bills, and an optional note.
sub void_bills {
    my ($class, $e, $billids, $note) = @_;

    my %users;
    my $bills;
    if (ref($billids->[0])) {
        $bills = $billids;
    } else {
        $bills = $e->search_money_billing([{id => $billids}])
            or return $e->die_event;
    }
    for my $bill (@$bills) {

        my $xact = $e->retrieve_money_billable_transaction($bill->xact)
            or return $e->die_event;

        if($U->is_true($bill->voided)) {
            # For now, it is not an error to attempt to re-void a bill, but
            # don't actually do anything
            #$e->rollback;
            #return OpenILS::Event->new('BILL_ALREADY_VOIDED', payload => $bill)
            next;
        }

        my $org = $U->xact_org($bill->xact, $e);
        $users{$xact->usr} = {} unless $users{$xact->usr};
        $users{$xact->usr}->{$org} = 1;

        $bill->voided('t');
        $bill->voider($e->requestor->id);
        $bill->void_time('now');
        my $n = ($bill->note) ? sprintf("%s\n", $bill->note) : "";
        $bill->note(sprintf("$n%s", $note));

        $e->update_money_billing($bill) or return $e->die_event;
        my $evt = $U->check_open_xact($e, $bill->xact, $xact);
        return $evt if $evt;
    }

    # calculate penalties for all user/org combinations
    for my $user_id (keys %users) {
        for my $org_id (keys %{$users{$user_id}}) {
            OpenILS::Utils::Penalty->calculate_penalties($e, $user_id, $org_id)
        }
    }

    return 1;
}


# This subroutine actually handles "adjusting" bills to zero.  It takes a
# CStoreEditor, an arrayref of bill ids or bills, and an optional note.
sub adjust_bills_to_zero {
    my ($class, $e, $billids, $note) = @_;

    my %users;

    # Let's get all the billing objects and handle them by
    # transaction.
    my $bills;
    if (ref($billids->[0])) {
        $bills = $billids;
    } else {
        $bills = $e->search_money_billing([{id => $billids}])
            or return $e->die_event;
    }

    my @xactids = uniq map {$_->xact()} @$bills;

    foreach my $xactid (@xactids) {
        my $mbt = $e->retrieve_money_billable_transaction(
            [
                $xactid,
                {
                    flesh=> 2,
                    flesh_fields=> {
                        mbt=>['grocery','circulation'],
                        circ=>['target_copy']
                    }
                }
            ]
        ) or return $e->die_event;
        # Flesh grocery bills and circulations so we don't have to
        # retrieve them later.
        my ($circ, $grocery, $copy);
        $grocery = $mbt->grocery();
        $circ = $mbt->circulation();
        $copy = $circ->target_copy() if ($circ);



        # Get the bill_payment_map for the transaction.
        my $bpmap = $class->bill_payment_map_for_xact($e, $mbt);

        # Get the bills for this transaction from the main list of bills.
        my @xact_bills = grep {$_->xact() == $xactid} @$bills;
        # Handle each bill in turn.
        foreach my $bill (@xact_bills) {
            # As the total open amount on the transaction will change
            # as each bill is adjusted, we'll just recalculate it for
            # each bill.
            my $xact_total = 0;
            map {$xact_total += $_->{bill}->amount()} @$bpmap;
            last if $xact_total == 0;

            # Get the bill_payment_map entry for this bill:
            my ($bpentry) = grep {$_->{bill}->id() == $bill->id()} @$bpmap;

            # From here on out, use the bill object from the bill
            # payment map entry.
            $bill = $bpentry->{bill};

            # The amount to adjust is the non-adjusted balance on the
            # bill. It should never be less than zero.
            my $amount_to_adjust = $U->fpdiff($bpentry->{bill_amount},$bpentry->{adjustment_amount});

            # Check if this bill is already adjusted.  We don't allow
            # "double" adjustments regardless of settings.
            if ($amount_to_adjust <= 0) {
                #my $event = OpenILS::Event->new('BILL_ALREADY_VOIDED', payload => $bill);
                #$e->event($event);
                #return $event;
                next;
            }

            if ($amount_to_adjust > $xact_total) {
                $amount_to_adjust = $xact_total;
            }

            # Create the account adjustment
            my $payobj = Fieldmapper::money::account_adjustment->new;
            $payobj->amount($amount_to_adjust);
            $payobj->amount_collected($amount_to_adjust);
            $payobj->xact($xactid);
            $payobj->accepting_usr($e->requestor->id);
            $payobj->payment_ts('now');
            $payobj->billing($bill->id());
            $payobj->note($note) if ($note);
            $e->create_money_account_adjustment($payobj) or return $e->die_event;
            # Adjust our bill_payment_map
            $bpentry->{adjustment_amount} += $amount_to_adjust;
            push @{$bpentry->{adjustments}}, $payobj;
            # Should come to zero:
            my $new_bill_amount = $U->fpdiff($bill->amount(),$amount_to_adjust);
            $bill->amount($new_bill_amount);
        }

        my $org = $U->xact_org($xactid, $e);
        $users{$mbt->usr} = {} unless $users{$mbt->usr};
        $users{$mbt->usr}->{$org} = 1;

        my $evt = $U->check_open_xact($e, $xactid, $mbt);
        return $evt if $evt;
    }

    # calculate penalties for all user/org combinations
    for my $user_id (keys %users) {
        for my $org_id (keys %{$users{$user_id}}) {
            OpenILS::Utils::Penalty->calculate_penalties($e, $user_id, $org_id);
        }
    }

    return 1;
}

# A helper function to check if the payments on a bill are inside the
# range of a given interval.
# TODO: here is one simple place we could do voids in the absence
# of any payments
sub _has_refundable_payments {
    my ($e, $xactid, $interval) = @_;

    # for now, just short-circuit with no interval
    return 0 if (!$interval);

    my $last_payment = $e->search_money_payment(
        {
            xact => $xactid,
            refundable => 't',
            # NOTE: now handled via refundable global flag
            # payment_type => {"!=" => 'account_adjustment'}
        },{
            limit => 1,
            order_by => { mp => "payment_ts DESC" }
        }
    );

    if ($last_payment->[0]) {
        my $interval_secs = interval_to_seconds($interval);
        my $payment_ts = DateTime::Format::ISO8601->parse_datetime(clean_ISO8601($last_payment->[0]->payment_ts))->epoch;
        my $now = time;
        return 1 if ($payment_ts + $interval_secs >= $now);
    }

    return 0;
}

1;
