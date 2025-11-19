package OpenILS::Application::Acq::Lineitem::BatchUpdate;

use strict;
use warnings;

use base qw/OpenILS::Application/;

# All of the packages we might 'use' are already imported in
# OpenILS::Application::Acq::Lineitem.  Only those that export symbols
# need to be mentioned explicitly here.

use List::Util qw/reduce/;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenILS::Utils::CStoreEditor q/:funcs/;

my $U = "OpenILS::Application::AppUtils";


# lineitem_batch_update_perm_test(), helper for lineitem_batch_update_api()
#
# Tests permissions on targeted lineitems, purchase orders, and picklists.
# Returns undef on success, event on perm failure.
# Responsible for calling $e->die_event.
# Also sanitizes values in $target.
#
sub lineitem_batch_update_perm_test {
    my ($e, $target) = @_;

    return $e->die_event(new OpenILS::Event("BAD_PARAMS", note => "target"))
        unless ref $target eq "HASH";

    my $perm_for = {
        ordering_agency => "CREATE_PURCHASE_ORDER",
        org_unit => "UPDATE_PICKLIST"
    };

    if (ref $target->{lineitems} eq "ARRAY") {
        # Sanitization
        $target->{lineitems} = [ map { int $_ } @{$target->{lineitems}} ];

        return $e->die_event(
            new OpenILS::Event(
                "BAD_PARAMS", note => "target (lineitems list empty)"
            )
        ) unless @{$target->{lineitems}};

        # Get all PO & picklist linkings from lineitems in question.
        my $li_rows = $e->json_query({
            select => {
                jub => ["id"],
                acqpo => ["ordering_agency"],
                acqpl => ["org_unit"]
            },
            from => {
                jub => {acqpl => {type => "left"}, acqpo => {type => "left"}}
            },
            where => {
                "+jub" => {id => $target->{lineitems}}
            }
        }) or return $e->die_event;

        # Fail loudly rather than giving user any surprises if they asked to
        # update lineitems that don't exist.  This is an asymmetric difference
        # calculation.
        my %present = map { $_->{id} => 1 } @$li_rows;
        my @missing = grep { not exists $present{$_} } @{$target->{lineitems}};
        return $e->die_event(
            new OpenILS::Event("ACQ_LINEITEM_NOT_FOUND", payload => \@missing)
        ) if @missing;

        # To avoid repetition of perm tests, track them here.
        my $already_done = {
            ordering_agency => {},
            org_unit => {}
        };

        # Test all lineitems based on the context OU of all linked POs AND PLs.
        foreach my $row (@$li_rows) {
            foreach my $field (keys %$already_done) {
                if ($row->{$field}) {
                    if (not $already_done->{$row}{$field}) {
                        my $perm = $perm_for->{$field};
                        my $context = $row->{$field};

                        if (not $e->allowed($perm, $context)) {
                            my $evt = $e->die_event;

                            # Take the PERM_FAILURE event and annotate it with
                            # a list of the targeted lineitems that would fail
                            # the same permission check (i.e. that have the
                            # same context).
                            $evt->{payload} = [
                                map { $_->{id} } (
                                    grep { $_->{$field} == $context } @$li_rows
                                )
                            ];
                            return $evt;
                        } else {
                            $already_done->{$row}{$field} = 1;
                        }
                    }
                }
            }
        }
    } elsif ($target->{purchase_order}) {
        $target->{purchase_order} = int($target->{purchase_order});

        my $po = $e->retrieve_acq_purchase_order($target->{purchase_order}) or
            return $e->die_event;

        return $e->die_event unless
            $e->allowed($perm_for->{ordering_agency}, $po->ordering_agency);
    } elsif ($target->{picklist}) {
        $target->{picklist} = int($target->{picklist});

        my $pl = $e->retrieve_acq_picklist($target->{picklist}) or
            return $e->die_event;

        return $e->die_event unless
            $e->allowed($perm_for->{org_unit}, $pl->org_unit);
    } else {
        return $e->die_event(
            new OpenILS::Event("BAD_PARAMS", note => "target")
        );
    }

    return; # perm check pass
}


# $changes->{item_count} wins over distribution formula if both are present.
# It's also ok for neither to be present.
sub pick_winning_item_count {
    my ($changes, $dist_formula) = @_;

    if (exists $changes->{item_count}) {
        return $changes->{item_count};
    } elsif ($dist_formula) {
        return reduce { $a + $b->item_count } 0, @{$dist_formula->entries};
    }

    return;
}


# pick_winning_change() should be called in list context, so the caller can
# distinguish between empty result (no change at all) and undef result (clear
# field).
sub pick_winning_change {
    my ($changes, $dist_formula, $field, $position) = @_;

    if (exists $changes->{$field}) {
        # Remember: in $changes, not exists means no change, while undef
        # means clear.

        return $changes->{$field} if $position >= $changes->{position};
    }

    if ($dist_formula) {
        my $hit;

        my $count_over_entries = 0;
        foreach my $entry (@{$dist_formula->entries}) {
            $count_over_entries += $entry->item_count;

            if ($count_over_entries > $position) {
                # Abuse this virtual field on the distribution formula
                # to let the caller know we actually used it.

                $dist_formula->use_count(($dist_formula->use_count || 0) + 1);
                $hit = $entry->$field;
                last;
            }
        }

        # The database doesn't give us a way to distinguish between "not exists"
        # and undef like a hash does, so for dist formulas, undef (null) has
        # to mean no change, and so if we come up with nothing defined, we
        # don't return anything, not even the undef, since that would be
        # misunderstood by the caller.
        return $hit if defined $hit;
    }

    return; # return nothing, not even undef (in list context, anyway)
}


# adjust_lineitem_copy_counts() directly changes contents of @$lineitems
sub adjust_lineitem_copy_counts {
    my ($lineitems, $item_count) = @_;

    # Count how many lineitem details we have per lineitem, and for
    # each lineitem add or remove lineitems to match $item_count, as needed.

    my %counts;

    foreach my $jub (@$lineitems) {
        $counts{$jub->id} = scalar @{$jub->lineitem_details};

        if ($counts{$jub->id} > $item_count) {
            # Take care of excess lineitem details.

            for (my $i = $item_count; $i < $counts{$jub->id}; $i++) {
                $jub->lineitem_details->[$i]->isdeleted(1);
            }
        } elsif ($counts{$jub->id} < $item_count) {
            # Add missing lineitem details.

            for (my $i = $counts{$jub->id}; $i < $item_count; $i++) {
                my $lid = new Fieldmapper::acq::lineitem_detail;
                $lid->isnew(1);
                $lid->lineitem($jub->id);

                push @{$jub->lineitem_details}, $lid;
            }
        }
    }
}


# lineitem_batch_update_impl() should be handed everything pre-perm-checked
# and ready-to-go. $e is in a transaction.
sub lineitem_batch_update_impl {
    my ($conn, $e, $dry_run, $target, $changes, $dist_formula) = @_;

    # Keep client's attention.
    $conn->status(new OpenSRF::DomainObject::oilsContinueStatus);

    # First, retrieve existing lineitems with lineitem details.  We could do
    # with the lineitem details only if not for having to catch lineitems
    # with zero current lineitem details, so that we can augment those if
    # requested by the user via $changes->{item_count}.

    # The right ordering is important for adjusting lineitem detail counts.
    my %order_by = (order_by => [
        {class => "jub", field => "id"},
        {class => "acqlid", field => "id"}
    ]);

    # XXX The following could be refactored only to retrieve one lineitem at a
    # time, since the list of fleshed lineitem_details could conceivably be
    # very long for each one. We'd then update each lineitem_detail on that
    # lineitem before proceeding to the next.

    my $lineitems;

    if ($target->{lineitems}) {
        $lineitems = $e->search_acq_lineitem(
            [
                {id => $target->{lineitems}},
                {flesh => 1,
                    flesh_fields => {"jub" => ["lineitem_details"]}, %order_by}
            ], {substream => 1}
        ) or return $e->die_event;
    } else {
        my $where;

        if ($target->{purchase_order}) {
            $where = {purchase_order => $target->{purchase_order}};
        } else {
            $where = {picklist => $target->{picklist}};
        }

        $lineitems = $e->search_acq_lineitem(
            [
                $where,
                {flesh => 1,
                    flesh_fields => {"jub" => ["lineitem_details"]}, %order_by}
            ], {substream => 1}
        ) or return $e->die_event;
    }

    $conn->status(new OpenSRF::DomainObject::oilsContinueStatus);
    $logger->info(
        "lineitem_batch_update_impl() working with " .
        scalar(@$lineitems) . " lineitems"
    );

    my $item_count = pick_winning_item_count($changes, $dist_formula);
    adjust_lineitem_copy_counts($lineitems, $item_count) if defined $item_count;

    # Now, going through all our lineitem details, make the updates
    # called for in $changes, other than the 'item_count' field (handled above).

    my %fund_cache;
    my @fields = qw/owning_lib fund location collection_code circ_modifier note/;
    foreach my $jub (@$lineitems) {
        # We use the counting style of loop below because we need to know our
        # position for dist_formula application.

        my $starting_use_count =
            $dist_formula ? $dist_formula->use_count : undef;

        for (my $i = 0; $i < scalar @{$jub->lineitem_details}; $i++) {
            my $lid = $jub->lineitem_details->[$i];

            # Handle copies needing a delete.
            if ($lid->isdeleted) {
                $e->delete_acq_lineitem_detail($lid) or return $e->die_event;
                next;
            }

            # Handle existing and new copies.
            my $fund_changed = 0;
            foreach my $field (@fields) {
                # Calling pick_winning_change() in list context gets us an
                # empty list for "no change to make", (undef) for "clear the
                # field", and ($value) for "set the field to $value".

                my @change =
                    pick_winning_change($changes, $dist_formula, $field, $i);

                if (scalar @change) {
                    my $change = pop @change;

                    if (not defined $change) {
                        my $meth = "clear_$field";
                        $lid->$meth;
                    } else {

                        $fund_changed = 1 if 
                            !$lid->isnew and 
                            $field eq 'fund' and 
                            $lid->$field ne $change;

                        $lid->$field($change);
                    }
                }
            }

            my $method = ($lid->isnew ? "create" : "update") .
                "_acq_lineitem_detail";

            if ($fund_changed) {
                # handle_changed_lid updates any existing fund debits
                # linked to the LID to use the new fund.  If the fund
                # balance reaches a stop/warn percent (or error), 
                # processing exits early and returns an event.
                my $evt = 
                    OpenILS::Application::Acq::Order::handle_changed_lid(
                        $e, $lid, 0, \%fund_cache);
                return $evt if $evt;
            } else {
                $e->$method($lid) or return $e->die_event;
            }
        }

        if (defined $starting_use_count and
            $dist_formula->use_count > $starting_use_count) {

            # Record the application of the distribution formula.
            my $dfa = new Fieldmapper::acq::distribution_formula_application;

            $dfa->lineitem($jub->id);
            $dfa->formula($dist_formula->id);
            $dfa->creator($e->requestor->id);

            $e->create_acq_distribution_formula_application($dfa) or
                return $e->die_event;
        }

        $conn->respond($jub->id);
    }

    # Explicit bare return statements below avoid sending extra data to client.
    if ($dry_run) {
        $e->rollback;
        return;
    } else {
        $e->commit or return $e->die_event;
        return;
    }
}


__PACKAGE__->register_method(
    method => "lineitem_batch_update_api",
    api_name => "open-ils.acq.lineitem.batch_update",
    signature => {
        desc => "Apply changes to the lineitem details realted to specified lineitems in batch",
        params => [
            {desc => "Authentication token", type => "string"},
            {desc => "Target. Object key must be one of lineitems, purchase_order or picklist.  The value for 'lineitems' must be an array of IDs, and the values for either of the other two must be single IDs.", type => "object"},
            {desc => "Changes (optional).  If these changes conflict with distribution formula, these changes win.", type => "object"},
            {desc => "Distribution formula ID (optional). Note that a distribution formula's 'skip_count' field does nothing, but the 'position' and 'item_count' fields of distribution formula *entries* do what they ought to. ", type => "number"}
        ],
        return => {
            desc => q/A stream of lineitem IDs affected upon success.  Events
                on failure.  ANY events in the results, even after any number
                of lineitem IDs, should be interpreted by the client to mean
                that a rollback has happened and nothing has changed./,
            type => "mixed"
        }
    }
);

__PACKAGE__->register_method(
    method => "lineitem_batch_update_api",
    api_name => "open-ils.acq.lineitem.batch_update.dry_run",
    signature => {
        desc => "Impotent version of open-ils.acq.lineitem.batch_update that always ends in a rollback",
        params => "See open-ils.acq.lineitem.batch_update",
        return => "See open-ils.acq.lineitem.batch_update"
    }
);

sub lineitem_batch_update_api {
    my ($self, $conn, $auth, $target, $changes, $dist_formula) = @_;

    # Make sure that $changes->{item_count}, if it exists, is a natural number.
    # Other things in $change are safe to treat somewhat more casually,
    # except fund, which is handled later.
    $changes ||= {};
    if (exists $changes->{item_count}) {
        $changes->{item_count} = int($changes->{item_count});
        return new OpenILS::Event("BAD_PARAMS", note => "changes (item_count)")
            unless $changes->{item_count} >= 0;
    }

    # We want to do our perm tests and everything within a transaction.
    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;

    # If any distribution formula ID is given, fetch distribution formula
    # (with entries fleshed) early so we can get a quick permission check
    # out of the way.
    if ($dist_formula) {

        # It's important that we NOT flesh use_count here, if that [ever]
        # does anything.  We're going to abuse that field internally.

        $dist_formula = $e->retrieve_acq_distribution_formula([
            int($dist_formula), {
                flesh=>2, 
                flesh_fields=>{
                    acqdf => ["entries"],
                    acqdfe => ["fund"]
                }
            }
        ]) or return $e->die_event;

        return $e->die_event unless
            $e->allowed("ADMIN_ACQ_DISTRIB_FORMULA", $dist_formula->owner);

        # If the distribution formula has a fund, there's an additional perm
        # test to do before proceeding.
        for my $entry (@{$dist_formula->entries}) {
            if ($entry->fund) {
                return $e->die_event unless $e->allowed(
                    ["ADMIN_FUND", "MANAGE_FUND"],
                    $entry->fund->org, $entry->fund
                );
            }
        }

        # The following sort is crucial later.
        $dist_formula->entries([
            sort { $a->position cmp $b->position } @{$dist_formula->entries}
        ]);
    }

    # Next, test permissions on fund to set, if any, from $changes.
    if ($changes->{fund}) {
        my $fund = $e->retrieve_acq_fund($changes->{fund}) or
            return $e->die_event;

        return $e->die_event unless
            $e->allowed(["ADMIN_FUND", "MANAGE_FUND"], $fund->org, $fund);
    }

    # Now test permissions on the targets.  lineitem_batch_update_perm_test()
    # calls die_event() for us if needed.  Has side-effect of target
    # sanitization.
    my $evt = lineitem_batch_update_perm_test($e, $target);
    return $evt if $U->event_code($evt);

    # Finally do the actual work.
    return lineitem_batch_update_impl(
        $conn, $e, scalar($self->api_name =~ /dry_run/),
        $target, $changes, $dist_formula
    );
}

1;
