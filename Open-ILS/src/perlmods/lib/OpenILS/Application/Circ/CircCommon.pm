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
use POSIX qw(ceil);

my $U = "OpenILS::Application::AppUtils";
my $parser = DateTime::Format::ISO8601->new;

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

        my $date = DateTime::Format::ISO8601->parse_datetime(cleanse_ISO8601($backdate));
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
        $e = new_editor(xact => 1);
        $commit = 1;
    }

    my %hoo = map { ( $_->id => $_ ) } @{ $e->retrieve_all_actor_org_unit_hours_of_operation };

    my $penalty = OpenSRF::AppSession->create('open-ils.penalty');
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
#            if ($self->method_lookup('open-ils.storage.transaction.current')->run) {
#                $logger->debug("Cleaning up after previous transaction\n");
#                $self->method_lookup('open-ils.storage.transaction.rollback')->run;
#            }
#            $self->method_lookup('open-ils.storage.transaction.begin')->run( $client );
            $logger->info(
                sprintf("Processing %s %d...",
                    ($is_reservation ? "reservation" : "circ"), $c->id
                )
            );


            my $due_dt = $parser->parse_datetime( cleanse_ISO8601( $c->$due_date_method ) );
    
            my $due = $due_dt->epoch;
            my $now = time;

            my $fine_interval = $c->fine_interval;
            $fine_interval =~ s/(\d{2}):(\d{2}):(\d{2})/$1 h $2 m $3 s/o;
            $fine_interval = interval_to_seconds( $fine_interval );
    
            if ( $fine_interval == 0 || int($c->$recurring_fine_method * 100) == 0 || int($c->max_fine * 100) == 0 ) {
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
    
            my @fines = @{$e->search_money_billing(
                { xact => $c->id,
                  btype => 1,
                  billing_ts => { '>' => $c->$due_date_method } },
                { order_by => 'billing_ts DESC'}
            )};

            my $f_idx = 0;
            my $fine = $fines[$f_idx] if (@fines);
            my $current_fine_total = 0;
            $current_fine_total += int($_->amount * 100) for (grep { $_ and !$U->is_true($_->voided) } @fines);
    
            my $last_fine;
            if ($fine) {
                $conn->respond( "Last billing time: ".$fine->billing_ts." (clensed format: ".cleanse_ISO8601( $fine->billing_ts ).")") if $conn;
                $last_fine = $parser->parse_datetime( cleanse_ISO8601( $fine->billing_ts ) )->epoch;
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

            my $recurring_fine = int($c->$recurring_fine_method * 100);
            my $max_fine = int($c->max_fine * 100);

            my $skip_closed_check = $U->ou_ancestor_setting_value(
                $c->$circ_lib_method, 'circ.fines.charge_when_closed');
            $skip_closed_check = $U->is_true($skip_closed_check);

            my $truncate_to_max_fine = $U->ou_ancestor_setting_value(
                $c->$circ_lib_method, 'circ.fines.truncate_to_max_fine');
            $truncate_to_max_fine = $U->is_true($truncate_to_max_fine);

            my ($latest_billing_ts, $latest_amount) = ('',0);
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
                
                # XXX Use org time zone (or default to 'local') once we have the ou setting built for that
                my $billing_ts = DateTime->from_epoch( epoch => $last_fine, time_zone => 'local' );
                my $current_bill_count = $bill;
                while ( $current_bill_count ) {
                    $billing_ts->add( seconds_to_interval_hash( $fine_interval ) );
                    $current_bill_count--;
                }

                my $timestamptz = $billing_ts->strftime('%FT%T%z');
                if (!$skip_closed_check) {
                    my $dow = $billing_ts->day_of_week_0();
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
                $latest_billing_ts = $timestamptz;

                my $bill = Fieldmapper::money::billing->new;
                $bill->xact($c->id);
                $bill->note("System Generated Overdue Fine");
                $bill->billing_type("Overdue materials");
                $bill->btype(1);
                $bill->amount(sprintf('%0.2f', $this_billing_amount/100));
                $bill->billing_ts($timestamptz);
                $e->create_money_billing($bill);

            }

            $conn->respond( "\t\tAdding fines totaling $latest_amount for overdue up to $latest_billing_ts\n" )
                if ($conn and $latest_billing_ts and $latest_amount);

#            $self->method_lookup('open-ils.storage.transaction.commit')->run;

            # Calculate penalties inline
            OpenILS::Utils::Penalty->calculate_penalties(
                $e, $c->usr, $c->$circ_lib_method);

        };

        if ($@) {
            my $e = $@;
            $conn->respond( "Error processing overdue $ctype [".$c->id."]:\n\n$e\n" ) if $conn;
            $logger->error("Error processing overdue $ctype [".$c->id."]:\n$e\n");
#            $self->method_lookup('open-ils.storage.transaction.rollback')->run;
            last if ($e =~ /IS NOT CONNECTED TO THE NETWORK/o);
        }
    }

    $e->commit if ($commit);

    return undef;
}

1;
