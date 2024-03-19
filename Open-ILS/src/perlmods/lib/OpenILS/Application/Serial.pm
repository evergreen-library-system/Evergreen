#!/usr/bin/perl

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

=head1 NAME

OpenILS::Application::Serial - Performs serials-related tasks such as receiving issues and generating predictions

=head1 SYNOPSIS

TBD

=head1 DESCRIPTION

TBD

=head1 AUTHOR

Dan Wells, dbw2@calvin.edu

=cut

package OpenILS::Application::Serial;

use strict;
use warnings;


use OpenILS::Application;
use base qw/OpenILS::Application/;
use OpenILS::Application::AppUtils;
use OpenILS::Event;
use OpenSRF::AppSession;
use OpenILS::Utils::DateTime qw/:datetime/;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::MFHD;
use DateTime::Format::ISO8601;
use MARC::File::XML (BinaryEncoding => 'utf8');

use OpenILS::Application::Serial::OPAC;

my $U = 'OpenILS::Application::AppUtils';
my @MFHD_NAMES = ('basic','supplement','index');
my %MFHD_NAMES_BY_TAG = (  '853' => $MFHD_NAMES[0],
                        '863' => $MFHD_NAMES[0],
                        '854' => $MFHD_NAMES[1],
                        '864' => $MFHD_NAMES[1],
                        '855' => $MFHD_NAMES[2],
                        '865' => $MFHD_NAMES[2] );
my %MFHD_TAGS_BY_NAME = (  $MFHD_NAMES[0] => '853',
                        $MFHD_NAMES[1] => '854',
                        $MFHD_NAMES[2] => '855');
my $_strp_date = new DateTime::Format::Strptime(pattern => '%F');
my %FM_NAME_TO_ID = (
    'subscription' => 'ssub',
    'distribution' => 'sdist',
    'item' => 'sitem'
    );

# helper method for conforming dates to ISO8601
sub _cleanse_dates {
    my $item = shift;
    my $fields = shift;

    foreach my $field (@$fields) {
        $item->$field(clean_ISO8601($item->$field)) if $item->$field;
    }
    return 0;
}

sub _get_mvr {
    $U->simplereq(
        "open-ils.search",
        "open-ils.search.biblio.record.mods_slim.retrieve",
        @_
    );
}


##########################################################################
# item methods
#
__PACKAGE__->register_method(
    method    => "create_item_safely",
    api_name  => "open-ils.serial.item.create",
    api_level => 1,
    stream    => 1,
    argc      => 3,
    signature => {
        desc => q/Creates any number of items, respecting only a few of the
        submitted fields, as the user shouldn't be able to freely set certain
        ones/,
        params => [
            {name=> "authtoken", desc => "Authtoken for current user session",
                type => "string"},
            {name => "item", desc => "serial item",
                type => "object", class => "sitem"},
            {name => "count",
                desc => "optional: how many items to make " .
                    "(default 1; 1-100 permitted)",
                type => "number"}
        ],
        return => {
            desc => "created items (a stream of them)",
            type => "object", class => "sitem"
        }
    }
);
__PACKAGE__->register_method(
    method    => "update_item_safely",
    api_name  => "open-ils.serial.item.update",
    api_level => 1,
    stream    => 1,
    argc      => 2,
    signature => {
        desc => q/Edit a serial item, respecting only a few of the
        submitted fields, as the user shouldn't be able to freely set certain
        ones/,
        params => [
            {name=> "authtoken", desc => "Authtoken for current user session",
                type => "string"},
            {name => "item", desc => "serial item",
                type => "object", class => "sitem"},
        ],
        return => {
            desc => "created item", type => "object", class => "sitem"
        }
    }
);

sub _set_safe_item_fields {
    my $dest = shift;
    my $source = shift;
    my $requestor_id = shift;
    # extra fields remain in @_

    $dest->edit_date("now");
    $dest->editor($requestor_id);

    my @fields = qw/date_expected date_received status/;

    for my $field (@fields, @_) {
        $dest->$field($source->$field);
    }
}

sub update_item_safely {
    my ($self, $client, $auth, $item) = @_;

    my $e = new_editor("xact" => 1, "authtoken" => $auth);
    $e->checkauth or return $e->die_event;

    my $orig = $e->retrieve_serial_item([
        $item->id, {
            "flesh" => 2, "flesh_fields" => {
                "sitem" => ["stream"], "sstr" => ["distribution"]
            }
        }
    ]) or return $e->die_event;

    return $e->die_event unless $e->allowed(
        "ADMIN_SERIAL_ITEM", $orig->stream->distribution->holding_lib
    );

    _set_safe_item_fields($orig, $item, $e->requestor->id);
    $e->update_serial_item($orig) or return $e->die_event;

    $client->respond($e->retrieve_serial_item($item->id));
    $e->commit or return $e->die_event;
    undef;
}

sub create_item_safely {
    my ($self, $client, $auth, $item, $count) = @_;

    $count = int $count;
    $count ||= 1;
    return new OpenILS::Event(
        "BAD_PARAMS", note => "Count should be from 1 to 100"
    ) unless $count >= 1 and $count <= 100;

    my $e = new_editor("xact" => 1, "authtoken" => $auth);
    $e->checkauth or return $e->die_event;

    my $stream = $e->retrieve_serial_stream([
        $item->stream, {
            "flesh" => 1, "flesh_fields" => {"sstr" => ["distribution"]}
        }
    ]) or return $e->die_event;

    return $e->die_event unless $e->allowed(
        "ADMIN_SERIAL_ITEM", $stream->distribution->holding_lib
    );

    for (my $i = 0; $i < $count; $i++) {
        my $actual = new Fieldmapper::serial::item;
        $actual->creator($e->requestor->id);
        _set_safe_item_fields(
            $actual, $item, $e->requestor->id, "issuance", "stream"
        );

        $e->create_serial_item($actual) or return $e->die_event;
        $client->respond($e->data);
    }

    $e->commit or return $e->die_event;
    undef;
}

__PACKAGE__->register_method(
    method    => 'fleshed_item_alter',
    api_name  => 'open-ils.serial.item.fleshed.batch.update',
    api_level => 1,
    argc      => 2,
    signature => {
        desc     => 'Receives an array of one or more items and updates the database as needed',
        'params' => [ {
                 name => 'authtoken',
                 desc => 'Authtoken for current user session',
                 type => 'string'
            },
            {
                 name => 'items',
                 desc => 'Array of fleshed items',
                 type => 'array'
            }

        ],
        'return' => {
            desc => 'Returns 1 if successful, event if failed',
            type => 'mixed'
        }
    }
);

sub fleshed_item_alter {
    my( $self, $conn, $auth, $items ) = @_;
    return 1 unless ref $items;
    my( $reqr, $evt ) = $U->checkses($auth);
    return $evt if $evt;
    my $editor = new_editor(requestor => $reqr, xact => 1);
    my $override = $self->api_name =~ /override/;

    my %found_sdist_ids;
    my %found_sstr_ids;
    my %siss_to_potentially_delete;
    my @deleted_items;
    for my $item (@$items) {
        my $sstr_id = ref $item->stream ? $item->stream->id : $item->stream;
        if (!exists($found_sstr_ids{$sstr_id})) {
            my $sstr;
            if (ref $item->stream) {
                $sstr = $item->stream;
            } else {
                $sstr = $editor->retrieve_serial_stream($item->stream) or return $editor->die_event;
            }
            if (!exists($found_sdist_ids{$sstr->distribution})) {
                my $sdist = $editor->retrieve_serial_distribution($sstr->distribution) or return $editor->die_event;
                return $editor->die_event unless
                    $editor->allowed("ADMIN_SERIAL_STREAM", $sdist->holding_lib);
                $found_sdist_ids{$sstr->distribution} = 1;
            }
            $found_sstr_ids{$sstr_id} = 1;
        }

        $item->editor($editor->requestor->id);
        $item->edit_date('now');

        if( $item->isdeleted ) {
            my $siss_id = ref $item->issuance ? $item->issuance->id : $item->issuance;
            $siss_to_potentially_delete{$siss_id}++;
            # We don't want to do a bunch of resetting churn for multiple items
            # in the same unit/dist, so just gather ids for now
            push(@deleted_items, $item);
        } elsif( $item->isnew ) {
            # TODO: reconsider this
            # if the item has a new issuance, create the issuance first
            if (ref $item->issuance eq 'Fieldmapper::serial::issuance' and $item->issuance->isnew) {
                fleshed_issuance_alter($self, $conn, $auth, [$item->issuance]);
            }
            _cleanse_dates($item, ['date_expected','date_received']);
            $evt = _create_sitem( $editor, $item );
        } else {
            _cleanse_dates($item, ['date_expected','date_received']);
            $evt = _update_sitem( $editor, $override, $item );
        }
    }

    if (@deleted_items) {
        # First, reset as a batch any assigned to units.  This cleans up units
        # and rebuilds summaries as needed
        #
        # XXX: if we ever add a 'deleted' flag to items, we may want to
        # preserve rather than reset the received information
        my @unit_items = grep {$_->unit} @deleted_items;
        my $reset_info = $self->method_lookup('open-ils.serial.reset_items')->run($auth, \@unit_items) if @unit_items;

        # Next, do the actual deletes, unless we got an event
        if ($U->event_code($reset_info)) {
            $evt = $reset_info;
        } else {
            foreach my $item (@deleted_items) {
                $evt = _delete_sitem( $editor, $override, $item);
            }
        }
    }

    if( $evt ) {
        $logger->info("fleshed item-alter failed with event: ".OpenSRF::Utils::JSON->perl2JSON($evt));
        $editor->rollback;
        return $evt;
    }
    if( %siss_to_potentially_delete ) {
        foreach my $id (keys %siss_to_potentially_delete) {
            my $issuance = $editor->retrieve_serial_issuance([
                $id, {
                    "flesh" => 1, "flesh_fields" => {
                        "siss" => ["items"],
                    }
                }
            ]);
            unless ($issuance) {
                $logger->warn("fleshed item-alter failed to retrieve issuance $id to potenitally delete");
                $editor->rollback;
                return $editor->die_event;
            }
            unless (@{ $issuance->items }) {
                $logger->info("fleshed item-alter deleting issuance $id as it has no items left");
                $evt = _delete_siss( $editor, $override, $issuance);
                if( $evt ) {
                    $logger->info("fleshed item-alter failed with event: ".OpenSRF::Utils::JSON->perl2JSON($evt));
                    $editor->rollback;
                    return $evt;
                }
            }
        }
    }
    $logger->debug("item-alter: done updating item batch");
    $editor->commit;
    $logger->info("fleshed item-alter successfully updated ".scalar(@$items)." items");
    return 1;
}

sub _delete_sitem {
    my ($editor, $override, $item) = @_;
    $logger->info("item-alter: delete item ".OpenSRF::Utils::JSON->perl2JSON($item));
    return $editor->event unless $editor->delete_serial_item($item);
    return 0;
}

sub _create_sitem {
    my ($editor, $item) = @_;

    $item->creator($editor->requestor->id);
    $item->create_date('now');

    $logger->info("item-alter: new item ".OpenSRF::Utils::JSON->perl2JSON($item));
    return $editor->event unless $editor->create_serial_item($item);
    return 0;
}

sub _update_sitem {
    my ($editor, $override, $item) = @_;

    $logger->info("item-alter: retrieving item ".$item->id);
    my $orig_item = $editor->retrieve_serial_item($item->id);

    $logger->info("item-alter: original item ".OpenSRF::Utils::JSON->perl2JSON($orig_item));
    $logger->info("item-alter: updated item ".OpenSRF::Utils::JSON->perl2JSON($item));
    return $editor->event unless $editor->update_serial_item($item);
    return 0;
}

__PACKAGE__->register_method(
    method  => "fleshed_serial_item_retrieve_batch",
    authoritative => 1,
    api_name    => "open-ils.serial.item.fleshed.batch.retrieve"
);

sub fleshed_serial_item_retrieve_batch {
    my( $self, $client, $ids ) = @_;
# FIXME: permissions?
    $logger->info("Fetching fleshed serial items @$ids");
    return $U->cstorereq(
        "open-ils.cstore.direct.serial.item.search.atomic",
        { id => $ids },
        { flesh => 2,
          flesh_fields => {sitem => [ qw/issuance creator editor stream unit notes/ ], sunit => ["call_number"], siss => [qw/creator editor subscription/]}
        });
}


##########################################################################
# issuance methods
#
__PACKAGE__->register_method(
    method    => 'fleshed_issuance_alter',
    api_name  => 'open-ils.serial.issuance.fleshed.batch.update',
    api_level => 1,
    argc      => 2,
    signature => {
        desc     => 'Receives an array of one or more issuances and updates the database as needed',
        'params' => [ {
                 name => 'authtoken',
                 desc => 'Authtoken for current user session',
                 type => 'string'
            },
            {
                 name => 'issuances',
                 desc => 'Array of fleshed issuances',
                 type => 'array'
            }

        ],
        'return' => {
            desc => 'Returns 1 if successful, event if failed',
            type => 'mixed'
        }
    }
);

sub fleshed_issuance_alter {
    my( $self, $conn, $auth, $issuances ) = @_;
    return 1 unless ref $issuances;
    my( $reqr, $evt ) = $U->checkses($auth);
    return $evt if $evt;
    my $editor = new_editor(authtoken => $auth, requestor => $reqr, xact => 1);
    my $override = $self->api_name =~ /override/;

    my %found_ssub_ids;
    my %regen_ssub_ids;
    for my $issuance (@$issuances) {
        my $ssub_id = ref $issuance->subscription ? $issuance->subscription->id : $issuance->subscription;
        if (!exists($found_ssub_ids{$ssub_id})) {
            my $owning_lib_id;
            if (ref $issuance->subscription) {
                $owning_lib_id = $issuance->subscription->owning_lib;
            } else {
                my $ssub = $editor->retrieve_serial_subscription($issuance->subscription) or return $editor->die_event;
                $owning_lib_id = $ssub->owning_lib;
            }
            return $editor->die_event unless
                $editor->allowed("ADMIN_SERIAL_SUBSCRIPTION", $owning_lib_id);
            $found_ssub_ids{$ssub_id} = 1;
        }

        my $issuanceid = $issuance->id;
        $issuance->editor($editor->requestor->id);
        $issuance->edit_date('now');

        if( $issuance->isdeleted ) {
            $evt = _delete_siss( $editor, $override, $issuance);
            $regen_ssub_ids{$ssub_id} = 1;
        } elsif( $issuance->isnew ) {
            _cleanse_dates($issuance, ['date_published']);
            $evt = _create_siss( $editor, $issuance );
        } else {
            _cleanse_dates($issuance, ['date_published']);
            $evt = _update_siss( $editor, $override, $issuance );
        }

        last if $evt;
    }

    if (!$evt) {
        # if we deleted any issuances, update the summaries
        # for all dists in those ssubs
        my @ssub_ids = keys %regen_ssub_ids;
        $evt = _regenerate_summaries($editor, {'ssub_ids' => \@ssub_ids}) if @ssub_ids;
    }

    if ( $evt ) {
        $logger->info("fleshed issuance-alter failed with event: ".OpenSRF::Utils::JSON->perl2JSON($evt));
        $editor->rollback;
        return $evt;
    }

    $logger->debug("issuance-alter: done updating issuance batch");
    $editor->commit;
    $logger->info("fleshed issuance-alter successfully updated ".scalar(@$issuances)." issuances");
    return 1;
}

sub _delete_siss {
    my ($editor, $override, $issuance) = @_;
    $logger->info("issuance-alter: delete issuance ".OpenSRF::Utils::JSON->perl2JSON($issuance));
    return $editor->event unless $editor->delete_serial_issuance($issuance);
    return 0;
}

sub _create_siss {
    my ($editor, $issuance) = @_;

    $issuance->creator($editor->requestor->id);
    $issuance->create_date('now');

    $logger->info("issuance-alter: new issuance ".OpenSRF::Utils::JSON->perl2JSON($issuance));
    return $editor->event unless $editor->create_serial_issuance($issuance);
    return 0;
}

sub _update_siss {
    my ($editor, $override, $issuance) = @_;

    $logger->info("issuance-alter: retrieving issuance ".$issuance->id);
    my $orig_issuance = $editor->retrieve_serial_issuance($issuance->id);

    $logger->info("issuance-alter: original issuance ".OpenSRF::Utils::JSON->perl2JSON($orig_issuance));
    $logger->info("issuance-alter: updated issuance ".OpenSRF::Utils::JSON->perl2JSON($issuance));
    return $editor->event unless $editor->update_serial_issuance($issuance);
    return 0;
}

__PACKAGE__->register_method(
    method  => "fleshed_serial_issuance_retrieve_batch",
    authoritative => 1,
    api_name    => "open-ils.serial.issuance.fleshed.batch.retrieve"
);

sub fleshed_serial_issuance_retrieve_batch {
    my( $self, $client, $ids ) = @_;
# FIXME: permissions?
    $logger->info("Fetching fleshed serial issuances @$ids");
    return $U->cstorereq(
        "open-ils.cstore.direct.serial.issuance.search.atomic",
        { id => $ids },
        { flesh => 1,
          flesh_fields => {siss => [ qw/creator editor subscription/ ]}
        });
}

__PACKAGE__->register_method(
    method  => "pub_fleshed_serial_issuance_retrieve_batch",
    api_name    => "open-ils.serial.issuance.pub_fleshed.batch.retrieve",
    signature => {
        desc => q/
            Public (i.e. OPAC) call for getting at the sub and 
            ultimately the record entry from an issuance
        /,
        params => [{name => 'ids', desc => 'Array of IDs', type => 'array'}],
        return => {
            desc => q/
                issuance objects, fleshed with subscriptions
            /,
            class => 'siss'
        }
    }
);
sub pub_fleshed_serial_issuance_retrieve_batch {
    my( $self, $client, $ids ) = @_;
    return [] unless $ids and @$ids;
    return new_editor()->search_serial_issuance([
        { id => $ids },
        { 
            flesh => 1,
            flesh_fields => {siss => [ qw/subscription/ ]}
        }
    ]);
}

sub received_siss_by_bib {
    # XXX this is somewhat wrong in implementation and should not be used in
    # new places - senator
    my $self = shift;
    my $client = shift;
    my $bib = shift;

    my $args = shift || {};
    $$args{order} ||= 'asc';

    my $global = $$args{global} == 0 ? 0 : 1;

    my $e = new_editor();
    my $issuances = $e->json_query({
        select  => {
            siss => [
                $global ? { transform => "min", column => "id", aggregate => 1 } : "id",
                "label",
                "date_published"
            ],
            "sitem" => [
                # We're not really interested in the minimum here.  This is
                # just a way to distinguish issuances whose items have units
                # from issuances whose items have no units, without altogether
                # excluding the latter type of issuances.
                {"transform" => "min", "alias" => "has_units",
                    "column" => "unit", "aggregate" => 1}
            ]
        },
        from => {
            ssub => {
                siss => {
                    field => 'subscription',
                    fkey  => 'id',
                    join  => {
                        sitem => {
                            field  => 'issuance',
                            fkey   => 'id',
                            $$args{ou} ? ( join  => {
                                sstr => {
                                    field => 'id',
                                    fkey  => 'stream',
                                    join  => {
                                        sdist => {
                                            field  => 'id',
                                            fkey   => 'distribution'
                                        }
                                    }
                                }
                            }) : ()
                        }
                    }
                }
            }
        },
        where => {
            '+ssub'  => { record_entry => $bib },
            $$args{type} ? ( '+siss' => { 'holding_type' => $$args{type} } ) : (),
            '+sitem' => {
                # XXX should we also take specific item statuses into account?
                date_received => { '!=' => undef },
                $$args{status} ? ( 'status' => $$args{status} ) : ()
            },
            $$args{ou} ? ( '+sdist' => {
                holding_lib => {
                    'in' => $U->get_org_descendants($$args{ou}, $$args{depth})
                }
            }) : ()
        },
        $$args{limit}  ? ( limit  => $$args{limit}  ) : (),
        $$args{offset} ? ( offset => $$args{offset} ) : (),
        order_by => [{ class => 'siss', field => 'date_published', direction => $$args{order} }],
        distinct => 1
    });

    $client->respond({
        "issuance" => $e->retrieve_serial_issuance($_->{"id"}),
        "has_units" => $_->{"has_units"} ? 1 : 0
    }) for @$issuances;

    return undef;
}
__PACKAGE__->register_method(
    method    => 'received_siss_by_bib',
    api_name  => 'open-ils.serial.received_siss.retrieve.by_bib',
    api_level => 1,
    argc      => 1,
    stream    => 1,
    signature => {
        desc   => 'Receives a Bib ID and other optional params and returns "siss" (issuance) objects',
        params => [
            {   name => 'bibid',
                desc => 'id of the bre to which the issuances belong',
                type => 'number'
            },
            {   name => 'args',
                desc =>
q/A hash of optional arguments.  Valid keys and their meanings:
    global := If true, return only one representative version of a conceptual issuance regardless of the number of subscriptions, otherwise return all issuance objects meeting the requested criteria, including conceptual duplicates. Valid values are 0 (false) and 1 (true, default).
    order  := date_published sort direction, either "asc" (chronological, default) or "desc" (reverse chronological)
    limit  := Number of issuances to return.  Useful for paging results, or finding the oldest or newest
    offset := Number of issuance to skip before returning results.  Useful for paging.
    orgid  := OU id used to scope retrieval, based on distribution.holding_lib
    depth  := OU depth used to range the scope of orgid
    type   := Holding type filter. Valid values are "basic", "supplement" and "index". Can be a scalar (one) or arrayref (one or more).
    status := Item status filter. Valid values are "Bindery", "Bound", "Claimed", "Discarded", "Expected", "Not Held", "Not Published" and "Received". Can be a scalar (one) or arrayref (one or more).
/
            }
        ]
    }
);


sub scoped_bib_holdings_summary {
    # XXX this is somewhat wrong in implementation and should not be used in
    # new places - senator
    my $self = shift;
    my $client = shift;
    my $bibid = shift;
    my $args = shift || {};

    $args->{order} = 'asc';

    my ($issuances) = $self->method_lookup('open-ils.serial.received_siss.retrieve.by_bib.atomic')->run( $bibid => $args );

    # split into issuance type sets
    my %type_blob = (basic => [], supplement => [], index => []);
    push @{ $type_blob{ $_->{"issuance"}->holding_type } }, $_->{"issuance"}
        for (@$issuances);

    # generate a statement list for each type
    my %statement_blob;
    for my $type ( keys %type_blob ) {
        my ($mfhd,$list) = _summarize_contents(new_editor(), $type_blob{$type});

        return {} if $U->event_code($mfhd); # _summarize_contents() failed, bad data?

        $statement_blob{$type} = $list;
    }

    return \%statement_blob;
}
__PACKAGE__->register_method(
    method    => 'scoped_bib_holdings_summary',
    api_name  => 'open-ils.serial.bib.summary_statements',
    api_level => 1,
    argc      => 1,
    signature => {
        desc   => '** DEPRECATED and only used by JSPAC. Somewhat wrong in implementation. *** Receives a Bib ID and other optional params and returns set of holdings statements',
        params => [
            {   name => 'bibid',
                desc => 'id of the bre to which the issuances belong',
                type => 'number'
            },
            {   name => 'args',
                desc =>
q/A hash of optional arguments.  Valid keys and their meanings:
    orgid  := OU id used to scope retrieval, based on distribution.holding_lib
    depth  := OU depth used to range the scope of orgid
    type   := Holding type filter. Valid values are "basic", "supplement" and "index". Can be a scalar (one) or arrayref (one or more).
    status := Item status filter. Valid values are "Bindery", "Bound", "Claimed", "Discarded", "Expected", "Not Held", "Not Published" and "Received". Can be a scalar (one) or arrayref (one or more).
/
            }
        ]
    }
);


##########################################################################
# unit methods
#
__PACKAGE__->register_method(
    method    => 'fleshed_sunit_alter',
    api_name  => 'open-ils.serial.sunit.fleshed.batch.update',
    api_level => 1,
    argc      => 2,
    signature => {
        desc     => 'Receives an array of one or more Units and updates the database as needed',
        'params' => [ {
                 name => 'authtoken',
                 desc => 'Authtoken for current user session',
                 type => 'string'
            },
            {
                 name => 'sunits',
                 desc => 'Array of fleshed Units',
                 type => 'array'
            }

        ],
        'return' => {
            desc => 'Returns 1 if successful, event if failed',
            type => 'mixed'
        }
    }
);

sub fleshed_sunit_alter {
    my( $self, $conn, $auth, $sunits ) = @_;
    return 1 unless ref $sunits;
    my( $reqr, $evt ) = $U->checkses($auth);
    return $evt if $evt;
    my $editor = new_editor(requestor => $reqr, xact => 1);
    my $override = $self->api_name =~ /override/;

    my %found_cn_ids;
    for my $sunit (@$sunits) {
        my $cn_id = ref $sunit->call_number ? $sunit->call_number->id : $sunit->call_number;
        if (!exists($found_cn_ids{$cn_id})) {
            my $owning_lib_id;
            if (ref $sunit->call_number) {
                $owning_lib_id = $sunit->call_number->owning_lib;
            } else {
                my $cn = $editor->retrieve_asset_call_number($sunit->call_number) or return $editor->die_event;
                $owning_lib_id = $cn->owning_lib;
            }
            return $editor->die_event unless
                $editor->allowed("UPDATE_COPY", $owning_lib_id);
            $found_cn_ids{$cn_id} = 1;
        }

        if( $sunit->isdeleted ) {
            $evt = _delete_sunit( $editor, $override, $sunit );
        } else {
            $sunit->default_location( $sunit->default_location->id ) if ref $sunit->default_location;

            if( $sunit->isnew ) {
                $evt = _create_sunit( $editor, $sunit );
            } else {
                $evt = _update_sunit( $editor, $override, $sunit );
            }
        }
    }

    if( $evt ) {
        $logger->info("fleshed sunit-alter failed with event: ".OpenSRF::Utils::JSON->perl2JSON($evt));
        $editor->rollback;
        return $evt;
    }
    $logger->debug("sunit-alter: done updating sunit batch");
    $editor->commit;
    $logger->info("fleshed sunit-alter successfully updated ".scalar(@$sunits)." Units");
    return 1;
}

sub _delete_sunit {
    my ($editor, $override, $sunit) = @_;
    $logger->info("sunit-alter: delete sunit ".OpenSRF::Utils::JSON->perl2JSON($sunit));
    return $editor->event unless $editor->delete_serial_unit($sunit);
    return 0;
}

sub _create_sunit {
    my ($editor, $sunit) = @_;

    # The unique barcode constraint does not span asset.copy and serial.unit.
    # ensure the barcode on the new unit does not collide with an existing
    # asset.copy barcode.
    my $existing = $editor->search_asset_copy(
        {deleted => 'f', barcode => $sunit->barcode})->[0];

    if (!$existing) {
        # The DB will prevent duplicate serial.unit barcodes, but for 
        # consistency (and a more specific error message for the
        # user), prevent creation attempts on serial unit barcode
        # collisions as well.
        $existing = $editor->search_serial_unit(
            {deleted => 'f', barcode => $sunit->barcode})->[0];
    }

    if ($existing) {
        $editor->rollback;
        return new OpenILS::Event(
            'SERIAL_UNIT_BARCODE_COLLISION', note => 
            'Serial unit barcode collides with existing unit/copy barcode',
            payload => {barcode => $sunit->barcode}
        );
    }

    $logger->info("sunit-alter: new Unit ".OpenSRF::Utils::JSON->perl2JSON($sunit));
    return $editor->die_event unless $editor->create_serial_unit($sunit);
    return 0;
}

sub _update_sunit {
    my ($editor, $override, $sunit) = @_;

    $logger->info("sunit-alter: retrieving sunit ".$sunit->id);
    my $orig_sunit = $editor->retrieve_serial_unit($sunit->id);

    $logger->info("sunit-alter: original sunit ".OpenSRF::Utils::JSON->perl2JSON($orig_sunit));
    $logger->info("sunit-alter: updated sunit ".OpenSRF::Utils::JSON->perl2JSON($sunit));
    return $editor->event unless $editor->update_serial_unit($sunit);
    return 0;
}

__PACKAGE__->register_method(
    method  => "retrieve_unit_list",
    authoritative => 1,
    api_name    => "open-ils.serial.unit_list.retrieve"
);

sub retrieve_unit_list {

    my( $self, $client, @sdist_ids ) = @_;

    if(ref($sdist_ids[0])) { @sdist_ids = @{$sdist_ids[0]}; }

    my $e = new_editor();

    my $query = {
        'select' => 
            { 'sunit' => [ 'id', 'summary_contents', 'sort_key' ],
              'sitem' => ['stream'],
              'sstr' => ['distribution'],
              'sdist' => [{'column' => 'label', 'alias' => 'sdist_label'}]
            },
        'from' =>
            { 'sdist' =>
                { 'sstr' =>
                    { 'join' =>
                        { 'sitem' =>
                            { 'join' => { 'sunit' => {} } }
                        }
                    }
                }
            },
        'distinct' => 'true',
        'where' => { '+sdist' => {'id' => \@sdist_ids} },
        'order_by' => [{'class' => 'sunit', 'field' => 'sort_key'}]
    };

    my $unit_list_entries = $e->json_query($query);
    
    my @entries;
    foreach my $entry (@$unit_list_entries) {
        my $value = {'sunit' => $entry->{id}, 'sstr' => $entry->{stream}, 'sdist' => $entry->{distribution}};
        my $label = $entry->{summary_contents};
        if (length($label) > 100) {
            $label = substr($label, 0, 100) . '...'; # limited space in dropdown / menu
        }
        $label = "[$entry->{sdist_label}/$entry->{stream} #$entry->{id}] " . $label;
        push (@entries, [$label, OpenSRF::Utils::JSON->perl2JSON($value)]);
    }

    return \@entries;
}



##########################################################################
# predict and receive methods
#
__PACKAGE__->register_method(
    method    => 'make_predictions',
    api_name  => 'open-ils.serial.make_predictions',
    api_level => 1,
    argc      => 1,
    signature => {
        desc     => 'Receives an ssub id and populates the issuance and item tables',
        'params' => [ {
                 name => 'ssub_id',
                 desc => 'Serial Subscription ID',
                 type => 'int'
            }
        ]
    }
);

sub make_predictions {
    my ($self, $conn, $authtoken, $args) = @_;

    my $ssub_id = $args->{ssub_id};

    my $editor = OpenILS::Utils::CStoreEditor->new();
    my $ssub = $editor->retrieve_serial_subscription([$ssub_id]);
    my $sdists = $editor->search_serial_distribution( [{ subscription => $ssub->id }, { flesh => 1, flesh_fields => {sdist => [ qw/ streams / ]} }] ); #TODO: 'deleted' support?

    return store_predictions(
        $self, $conn, $authtoken, $args, $ssub, $sdists,
        make_prediction_values($self, $conn, $authtoken, $args, $ssub, $sdists, $editor)
    );
}

__PACKAGE__->register_method(
    method    => 'make_prediction_values',
    api_name  => 'open-ils.serial.make_prediction_values',
    api_level => 1,
    argc      => 1,
    signature => {
        desc     => 'Receives an ssub id and returns objects that can be used to populate the issuance and item tables',
        'params' => [ {
                 name => 'ssub_id',
                 desc => 'Serial Subscription ID',
                 type => 'int'
            }
        ]
    }
);

sub make_prediction_values {
    my ($self, $conn, $authtoken, $args, $ssub, $sdists, $editor) = @_;
    $logger->debug('make_prediction_values with args: ' . OpenSRF::Utils::JSON->perl2JSON($args));

    my $ssub_id = $args->{ssub_id};

    $editor ||= OpenILS::Utils::CStoreEditor->new();
    $ssub ||= $editor->retrieve_serial_subscription([$ssub_id]);
    $sdists ||= $editor->search_serial_distribution( [{ subscription => $ssub->id }, { flesh => 1, flesh_fields => {sdist => [ qw/ streams / ]} }] ); #TODO: 'deleted' support?

    my $scaps = $editor->search_serial_caption_and_pattern({ subscription => $ssub_id, active => 't'});
    my $mfhd = MFHD->new(MARC::Record->new());

    my $total_streams = 0;
    foreach (@$sdists) {
        $total_streams += scalar(@{$_->streams});
    }
    if ($total_streams < 1) {
        $editor->disconnect;
        # XXX TODO new event type
        return new OpenILS::Event(
            "BAD_PARAMS", note =>
                "There are no streams to direct items. Can't predict."
        );
    }

    unless (@$scaps) {
        $editor->disconnect;
        # XXX TODO new event type
        return new OpenILS::Event(
            "BAD_PARAMS", note =>
                "There are no active caption-and-pattern objects associated " .
                "with this subscription. Can't predict."
        );
    }

    my @predictions;
    my $link_id = 1;
    foreach my $scap (@$scaps) {
        my $caption_field = _revive_caption($scap);
        $caption_field->update('8' => $link_id);
        my $fake_chron_needed = 0;
        # if we have missing chron pieces, we will add them later for prediction purposes
        if (!$caption_field->enumeration_is_chronology) {
            if (!$caption_field->subfield('i') # no year
                or !$caption_field->subfield('j')) { # we had a year, but no month or season
                $fake_chron_needed = '1';
            }
        }
        $mfhd->append_fields($caption_field);
        my $options = {
                'caption' => $caption_field,
                'scap_id' => $scap->id,
                'include_base_issuance' => $args->{include_base_issuance},
                'num_to_predict' => $args->{num_to_predict},
                'end_date' => defined $args->{end_date} ?
                    $_strp_date->parse_datetime($args->{end_date}) : undef
                };
        my $predict_from_siss;
        if ($args->{base_issuance}) { # predict from a given issuance
            $predict_from_siss = $args->{base_issuance};
        } else { # default to predicting from last published
            my $last_published = $editor->search_serial_issuance([
                    {'caption_and_pattern' => $scap->id,
                    'subscription' => $ssub_id},
                {limit => 1, order_by => { siss => "date_published DESC" }}]
                );
            if ($last_published->[0]) {
                $predict_from_siss = $last_published->[0];
                unless ($predict_from_siss->holding_code) {
                    $editor->disconnect;
                    # XXX TODO new event type
                    return new OpenILS::Event(
                        "BAD_PARAMS", note =>
                            "Last issuance has no holding code. Can't predict."
                    );
                }
            } else {
                $editor->disconnect;
                # XXX TODO make a new event type instead of hijacking this one
                return new OpenILS::Event(
                    "BAD_PARAMS", note => "No issuance from which to predict!"
                );
            }
        }
        $logger->debug('make_prediction_values reviving holdings: ' . OpenSRF::Utils::JSON->perl2JSON($predict_from_siss));
        $options->{predict_from} = _revive_holding($predict_from_siss->holding_code, $caption_field, 1); # fresh MFHD Record, so we simply default to 1 for seqno
        if ($fake_chron_needed) {
            $options->{faked_chron_date} = DateTime::Format::ISO8601->new->parse_datetime(clean_ISO8601($predict_from_siss->date_published));
        }
        $logger->debug('make_prediction_values predicting with options: ' . OpenSRF::Utils::JSON->perl2JSON($options));
        push( @predictions, _generate_issuance_values($mfhd, $options) );
        $link_id++;
    }

    $logger->debug('make_prediction_values predictions: ' . OpenSRF::Utils::JSON->perl2JSON(\@predictions));
    return \@predictions;
}

sub store_predictions {
    my ($self, $conn, $authtoken, $args, $ssub, $sdists, $predictions) = @_;

    my @issuances;
    foreach my $prediction (@$predictions) {
        my $issuance = new Fieldmapper::serial::issuance;
        $issuance->isnew(1);
        $issuance->label($prediction->{label});
        $issuance->date_published($prediction->{date_published}->strftime('%F'));
        $issuance->holding_code(OpenSRF::Utils::JSON->perl2JSON($prediction->{holding_code}));
        $issuance->holding_type($prediction->{holding_type});
        $issuance->caption_and_pattern($prediction->{caption_and_pattern});
        $issuance->subscription($ssub->id);
        push (@issuances, $issuance);
    }

    my $evt = fleshed_issuance_alter($self, $conn, $authtoken, \@issuances);
    return $evt if ref $evt;

    my @items;
    for (my $i = 0; $i < @issuances; $i++) {
        my $date_expected = $$predictions[$i]->{date_published}->add(seconds => interval_to_seconds($ssub->expected_date_offset))->strftime('%F');
        my $issuance = $issuances[$i];
        #$issuance->label(interval_to_seconds($ssub->expected_date_offset));
        foreach my $sdist (@$sdists) {
            my $streams = $sdist->streams;
            foreach my $stream (@$streams) {
                my $item = new Fieldmapper::serial::item;
                $item->isnew(1);
                $item->stream($stream->id);
                $item->date_expected($date_expected);
                $item->issuance($issuance->id);
                push (@items, $item);
            }
        }
    }
    fleshed_item_alter($self, $conn, $authtoken, \@items); # FIXME: catch events
    return \@items;
}

#
# _generate_issuance_values() is an initial attempt at a function which can be used
# to populate an issuance table with a list of predicted issues.  It accepts
# a hash ref of options initially defined as:
# caption : the caption field to predict on
# num_to_predict : the number of issues you wish to predict
# faked_chron_date : if the serial does not actually have a chronology caption (but we need one for prediction's sake), base predictions on this date
#
# The basic method is to first convert to a single holding if compressed, then
# increment the holding and save the resulting values to @issuances.
# 
# returns @issuance_values, an array of hashrefs containing (formatted
# label, formatted chronology date, formatted estimated arrival date, and an
# array ref of holding subfields as (key, value, key, value ...)) (not a hash
# to protect order and possible duplicate keys), and a holding type.
#
sub _generate_issuance_values {
    my ($mfhd, $options) = @_;
    my $caption = $options->{caption};
    my $scap_id = $options->{scap_id};
    my $include_base_issuance = $options->{include_base_issuance};
    my $num_to_predict = $options->{num_to_predict};
    my $end_date = $options->{end_date};
    my $predict_from = $options->{predict_from};   # MFHD::Holding to predict from
    my $faked_chron_date = $options->{faked_chron_date};   # serial does not have a (complete) chronology caption, so add one (temporarily) based on this date 

    $logger->debug('_generate_issuance_values predict_from: ' . OpenSRF::Utils::JSON->perl2JSON($predict_from));

# Only needed for 'real' MFHD records, not our temp records
#    my $link_id = $caption->link_id;
#    if(!$predict_from) {
#        my $htag = $caption->tag;
#        $htag =~ s/^85/86/;
#        my @holdings = $mfhd->holdings($htag, $link_id);
#        my $last_holding = $holdings[-1];
#
#        #if ($last_holding->is_compressed) {
#        #    $last_holding->compressed_to_last; # convert to last in range
#        #}
#        $predict_from = $last_holding;
#    }
#

    $predict_from->notes('public',  []);
# add a note marker for system use (?)
    $predict_from->notes('private', ['AUTOGEN']);

    # our basic method for dealing with 'faked' chronologies will be to add it in, do the predicting, then take it back out
    my @faked_subfield_chars;
    if ($faked_chron_date) {
        my $faked_caption = new MARC::Field($caption->tag, $caption->indicator(1), $caption->indicator(2), $caption->subfields_list);

        my %mfhd_chron_labels = ('i' => 'year', 'j' => 'month', 'k' => 'day');
        foreach my $subfield_char ('i', 'j', 'k') {
            if (!$caption->subfield($subfield_char)) { # if we are missing a piece, add it
                push(@faked_subfield_chars, $subfield_char);
                my $chron_name = $mfhd_chron_labels{$subfield_char};
                $faked_caption->add_subfields($subfield_char => "($chron_name)");
                my $method = $mfhd_chron_labels{$subfield_char};
                $predict_from->add_subfields($subfield_char => $faked_chron_date->$chron_name);
            }
        }
        # because of the way MFHD::Caption and Holding work, it is simplest
        # to recreate rather than try to update
        $faked_caption = new MFHD::Caption($faked_caption);
        $predict_from = new MFHD::Holding($predict_from->seqno, new MARC::Field($predict_from->tag, $predict_from->indicator(1), $predict_from->indicator(2), $predict_from->subfields_list), $faked_caption);
        $logger->debug('_generate_issuance_values fake predict_from: ' . OpenSRF::Utils::JSON->perl2JSON($predict_from));
    }

    my @predictions = $mfhd->generate_predictions({
        'include_base_issuance' => $include_base_issuance,
        'base_holding' => $predict_from,
        'num_to_predict' => $num_to_predict,
        'end_date' => $end_date
    });
    $logger->debug('_generate_issuance_values predictions: ' . OpenSRF::Utils::JSON->perl2JSON(\@predictions));

    my $pub_date;
    my @issuance_values;
    foreach my $prediction (@predictions) {
        $pub_date = $_strp_date->parse_datetime($prediction->chron_to_date);
        if ($faked_chron_date) { # get rid of the chronology portions and restore original caption
            $prediction->delete_subfield(code => \@faked_subfield_chars);
            $prediction = new MFHD::Holding($prediction->seqno, new MARC::Field($prediction->tag, $prediction->indicator(1), $prediction->indicator(2), $prediction->subfields_list), $caption);
        }
        push(
                @issuance_values,
                {
                    #$link_id,
                    label => $prediction->format,
                    date_published => $pub_date,
                    #date_expected => $date_expected->strftime('%F'),
                    holding_code => [$prediction->indicator(1),$prediction->indicator(2),$prediction->subfields_list],
                    holding_type => $MFHD_NAMES_BY_TAG{$caption->tag},
                    caption_and_pattern => $scap_id
                }
            );
    }

    return @issuance_values;
}

sub _revive_caption {
    my $scap = shift;

    my $pattern_code = $scap->pattern_code;

    # build MARC::Field
    my $pattern_parts = OpenSRF::Utils::JSON->JSON2perl($pattern_code);
    unshift(@$pattern_parts, $MFHD_TAGS_BY_NAME{$scap->type});
    my $pattern_field = new MARC::Field(@$pattern_parts);

    # build MFHD::Caption
    return new MFHD::Caption($pattern_field);
}

sub _revive_holding {
    my $holding_code = shift;
    my $caption_field = shift;
    my $seqno = shift;

    # build MARC::Field
    my $holding_parts = OpenSRF::Utils::JSON->JSON2perl($holding_code);
    my $captag = $caption_field->tag;
    $captag =~ s/^85/86/;
    unshift(@$holding_parts, $captag);
    my $holding_field = new MARC::Field(@$holding_parts);

    # build MFHD::Holding
    return new MFHD::Holding($seqno, $holding_field, $caption_field);

    # TODO(?) the underlying MARC and the Holding object end up in conflict concerning subfield '8'
}

__PACKAGE__->register_method(
    method    => 'unitize_items',
    api_name  => 'open-ils.serial.receive_items',
    api_level => 1,
    argc      => 1,
    signature => {
        desc     => 'Marks an item as received, updates the shelving unit (creating a new shelving unit if needed), and updates the summaries',
        'params' => [ {
                 name => 'items',
                 desc => 'array of serial items',
                 type => 'array'
            },
            {
                 name => 'barcodes',
                 desc => 'hash of item_ids => barcodes',
                 type => 'hash'
            },
            {
                 name => 'call_numbers',
                 desc => 'hash of item_ids => call_numbers',
                 type => 'hash'
            },
            {
                 name => 'donor_unit_ids',
                 desc => 'hash of unit_ids => 1, keyed with ids of any units giving up items',
                 type => 'hash'
            },
            {
                 name => 'extras',
                 desc => 'hash of hashes, circ_mod code and copy_location id, keyed as above',
                 type => 'hash'
            }
        ],
        'return' => {
            desc => 'Returns number of received items (num_items) and new unit ID, if applicable (new_unit_id)',
            type => 'hashref'
        }
    }
);

__PACKAGE__->register_method(
    method    => 'unitize_items',
    api_name  => 'open-ils.serial.bind_items',
    api_level => 1,
    argc      => 1,
    signature => {
        desc     => 'Marks an item as bound, updates the shelving unit (creating a new shelving unit if needed)',
        'params' => [ {
                 name => 'items',
                 desc => 'array of serial items',
                 type => 'array'
            },
            {
                 name => 'barcodes',
                 desc => 'hash of item_ids => barcodes',
                 type => 'hash'
            },
            {
                 name => 'call_numbers',
                 desc => 'hash of item_ids => call_numbers',
                 type => 'hash'
            },
            {
                 name => 'donor_unit_ids',
                 desc => 'hash of unit_ids => 1, keyed with ids of any units giving up items',
                 type => 'hash'
            },
            {
                 name => 'extras',
                 desc => 'hash of hashes, circ_mod code and copy_location id, keyed as above',
                 type => 'hash'
            }
        ],
        'return' => {
            desc => 'Returns number of bound items (num_items) and new unit ID, if applicable (new_unit_id)',
            type => 'hashref'
        }
    }
);

# TODO: reset/delete claims information once implemented
# XXX: deal with emptied call numbers here?
__PACKAGE__->register_method(
    method    => 'unitize_items',
    api_name  => 'open-ils.serial.reset_items',
    api_level => 1,
    argc      => 1,
    signature => {
        desc     => 'Resets the items to Expected, updates the shelving unit (deleting the shelving unit if empty), and updates the summaries',
        'params' => [ {
                 name => 'items',
                 desc => 'array of serial items',
                 type => 'array'
            }
        ],
        'return' => {
            desc => 'Returns number of reset items (num_items)',
            type => 'hashref'
        }
    }
);

sub unitize_items {
    my ($self, $conn, $auth, $items, $barcodes, $call_numbers, $donor_unit_ids, $extras) = @_;

    my $editor = new_editor("authtoken" => $auth, "xact" => 1);
    return $editor->die_event unless $editor->checkauth;
    return $editor->die_event unless $editor->allowed("RECEIVE_SERIAL");
    $self->api_name =~ /serial\.(\w*)_items/;
    my $mode = $1;
    
    my %found_unit_ids;
    if ($donor_unit_ids) { # units giving up items need updating as well
        %found_unit_ids = %$donor_unit_ids;
    }
    my %found_stream_ids;
    my %found_types;
    my $prev_loc_setting_map = {};

    my %stream_ids_by_unit_id;

    my %unit_map;
    my %sdist_by_unit_id;
    my %call_number_by_unit_id;
    my %sdist_by_stream_id;

    my $new_unit_id; # id for '-2' units to share
    foreach my $item (@$items) {
        # for debugging only, TODO: delete
        if (!ref $item) { # hopefully we got an id instead
            $item = $editor->retrieve_serial_item($item);
        }
        # get ids
        my $unit_id = ref($item->unit) ? $item->unit->id : $item->unit;
        my $stream_id = ref($item->stream) ? $item->stream->id : $item->stream;
        my $issuance_id = ref($item->issuance) ? $item->issuance->id : $item->issuance;
        #TODO: evt on any missing ids

        if ($mode eq 'receive') {
            $item->date_received('now');
            $item->status('Received');
        } elsif ($mode eq 'reset') {
            # clear date_received
            $item->clear_date_received;
            # Set status to 'Expected'
            $item->status('Expected');
            # remove from unit
            $item->clear_unit;
        }

        # check for types to trigger summary updates
        my $scap;
        if (!ref $item->issuance) {
            my $scaps = $editor->search_serial_caption_and_pattern([{"+siss" => {"id" => $issuance_id}}, { "join" => {"siss" => {}} }]);
            $scap = $scaps->[0];
        } elsif (!ref $item->issuance->caption_and_pattern) {
            $scap = $editor->retrieve_serial_caption_and_pattern($item->issuance->caption_and_pattern);
        } else {
            $scap = $editor->issuance->caption_and_pattern;
        }
        if (!exists($found_types{$stream_id})) {
            $found_types{$stream_id} = {};
        }
        $found_types{$stream_id}->{$scap->type} = 1 if ($scap);

        # create unit if needed
        if ($unit_id == -1 or (!$new_unit_id and $unit_id == -2)) { # create unit per item
            my $unit;
            my $sdists = $editor->search_serial_distribution([
                {"+sstr" => {"id" => $stream_id}},
                {
                    "join" => {"sstr" => {}},
                    "flesh" => 1,
                    "flesh_fields" => {"sdist" => ["subscription"]}
                }]);
            $unit = _build_unit($editor, $sdists->[0], $mode);
            # if _build_unit fails, $unit is an event, so return it
            if ($U->event_code($unit)) {
                $editor->rollback;
                $unit->{"note"} = "Item ID: " . $item->id;
                return $unit;
            }

            $unit->barcode($barcodes->{$item->id}) if exists($barcodes->{$item->id});
            $unit->location($extras->{copy_locations}->{$item->id}) if exists($extras->{copy_locations}->{$item->id});
            $unit->circ_modifier($extras->{circ_mods}->{$item->id}) if exists($extras->{circ_mods}->{$item->id});

            my $evt =  _create_sunit($editor, $unit);
            return $evt if $evt;
            if ($unit_id == -2) {
                $new_unit_id = $unit->id;
                $unit_id = $new_unit_id;
            } else {
                $unit_id = $unit->id;
            }
            $item->unit($unit_id);
            
            # get unit with 'DEFAULT's and save unit, sdist, and call number for later use
            $unit = $editor->retrieve_serial_unit($unit->id);
            $unit_map{$unit_id} = $unit;
            $sdist_by_unit_id{$unit_id} = $sdists->[0];
            $call_number_by_unit_id{$unit_id} = $call_numbers->{$item->id};
            $sdist_by_stream_id{$stream_id} = $sdists->[0];
        } elsif ($unit_id == -2) { # create one unit for all '-2' items
            $unit_id = $new_unit_id;
            $item->unit($unit_id);
        }

        $found_stream_ids{$stream_id} = 1;

        if (defined($unit_id) and $unit_id ne '') {
            $found_unit_ids{$unit_id} = 1;
            # save the stream_id for this unit_id
            # TODO: prevent items from different streams in same unit? (perhaps in interface)
            $stream_ids_by_unit_id{$unit_id} = $stream_id;
        } else {
            $item->clear_unit;
        }

        my $evt = _update_sitem($editor, undef, $item);
        return $evt if $evt;

        if ($mode eq 'receive') {
            my $sdist = $editor->search_serial_distribution([
                {"+sstr" => {"id" => $stream_id}},
                {
                    "join" => {"sstr" => {}},
                    "flesh" => 1,
                    "flesh_fields" => {"sdist" => ["subscription"]}
                }])->[0];

            #-------------------------------------------------------------------------
            # The following is copied from open-ils.serial.receive_items.one_unit_per
    
            # Fetch a list of issuances with received copies already existing
            # on this distribution (and with the same holding type on the
            # issuance).  This will be used in up to two places: once when building
            # a summary, once when changing the copy location of the previous
            # issuance's copy.

            # manually flesh distribution if not present
            #
            # this helps maintain compatiblity with XUL serial control receive
            if (!ref($item->stream->distribution)) {
                $item->stream->distribution($sdist);
            }
            my $issuances_received = _issuances_received($editor, $item);
            if ($U->event_code($issuances_received)) {
                $editor->rollback;
                return $issuances_received;
            }
    
            # Find out if we need to to deal with previous copy location changing.
            my $ou = $sdist->holding_lib;
            unless (exists $prev_loc_setting_map->{$ou}) {
                $prev_loc_setting_map->{$ou} = $U->ou_ancestor_setting_value(
                    $ou, "serial.prev_issuance_copy_location", $editor
                );
            }
    
            # If there is a previous copy location setting, we need the previous
            # issuance, from which we can in turn look up the item attached to the
            # same stream we're on now.
            if ($prev_loc_setting_map->{$ou}) {
                if (my $prev_iss =
                    _previous_issuance($issuances_received, $item->issuance)) {
    
                    # Now we can change the copy location of the previous unit,
                    # if needed.
                    return $editor->event if defined $U->event_code(
                        move_previous_unit(
                            $editor, $prev_iss, $item, $prev_loc_setting_map->{$ou}
                        )
                    );
                }
            }
            #-------------------------------------------------------------------------
        }

    }

    # cleanup 'dead' units (units which are now emptied of their items)
    my $dead_units = $editor->search_serial_unit([{'+sitem' => {'id' => undef}, 'deleted' => 'f'}, {'join' => {'sitem' => {'type' => 'left'}}}]);
    foreach my $unit (@$dead_units) {
        _delete_sunit($editor, undef, $unit);
        delete $found_unit_ids{$unit->id};
    }

    # deal with unit level contents
    foreach my $unit_id (keys %found_unit_ids) {

        # get all the needed issuances for unit
        # TODO remove 'Bindery' from this search (leaving it in for now for backwards compatibility with any current test environment data)
        my $issuances = $editor->search_serial_issuance([ {"+sitem" => {"unit" => $unit_id, "status" => ["Received", "Bindery"]}}, {"join" => {"sitem" => {}}, "order_by" => {"siss" => "date_published"}} ]);
        #TODO: evt on search failure

        # retrieve and update unit contents
        my $sunit;
        my $sdist;
        my $call_number_string;
        my $record_id;
        # if we just created the unit, we will already have it and the distribution stored, and we will need to assign the call number
        if (exists $unit_map{$unit_id}) {
            $sunit = $unit_map{$unit_id};
            $sdist = $sdist_by_unit_id{$unit_id};
            $call_number_string = $call_number_by_unit_id{$unit_id};
            $record_id = $sdist->subscription->record_entry;
        } else {
            # XXX: this code assumes you will not have units which mix streams/distributions, but current code does not enforce this
            $sunit = $editor->retrieve_serial_unit($unit_id);
            if ($stream_ids_by_unit_id{$unit_id}) {
                $sdist = $editor->search_serial_distribution([{"+sstr" => {"id" => $stream_ids_by_unit_id{$unit_id}}}, { "join" => {"sstr" => {}}, 'limit' => 1 }]);
            } else {
                $sdist = $editor->search_serial_distribution([
                    {'+sunit' => {'id' => $unit_id}},
                    { 'join' =>
                        {'sstr' =>
                            { 'join' =>
                                { 'sitem' =>
                                    { 'join' => 'sunit' }
                                } 
                            } 
                        },
                      'limit' => 1
                    }]);
            }
            $sdist = $sdist->[0];
        }

        my $evt = _prepare_unit($editor, $sunit, $sdist, $issuances, $call_number_string, $record_id);
        if ($U->event_code($evt)) {
            $editor->rollback;
            return $evt;
        }

        $evt = _update_sunit($editor, undef, $sunit);
        if ($U->event_code($evt)) {
            $editor->rollback;
            return $evt;
        }
    }

    if ($mode ne 'bind') { # the summary holdings do not change when binding
        # deal with stream level summaries
        # summaries will be built from the "primary" stream only, that is, the stream with the lowest ID per distribution
        # (TODO: consider direct designation)
        my %primary_streams_by_sdist;
        my %streams_by_sdist;

        # see if we have primary streams, and if so, associate them with their distributions
        foreach my $stream_id (keys %found_stream_ids) {
            my $sdist;
            if (exists $sdist_by_stream_id{$stream_id}) {
                $sdist = $sdist_by_stream_id{$stream_id};
            } else {
                $sdist = $editor->search_serial_distribution([{"+sstr" => {"id" => $stream_id}}, { "join" => {"sstr" => {}} }]);
                $sdist = $sdist->[0];
                $sdist_by_stream_id{$stream_id} = $sdist;
            }
            my $streams;
            if (!exists($streams_by_sdist{$sdist->id})) {
                $streams = $editor->search_serial_stream([{"distribution" => $sdist->id}, {"order_by" => {"sstr" => "id"}}]);
                $streams_by_sdist{$sdist->id} = $streams;
            } else {
                $streams = $streams_by_sdist{$sdist->id};
            }
            $primary_streams_by_sdist{$sdist->id} = $streams->[0] if ($stream_id == $streams->[0]->id);
        }

        # retrieve and update summaries for each affected primary stream's distribution
        foreach my $sdist_id (keys %primary_streams_by_sdist) {
            my $stream = $primary_streams_by_sdist{$sdist_id};
            my $stream_id = $stream->id;
            # get all the needed issuances for stream
            # FIXME: search in Bindery/Bound/Not Published? as well as Received
            foreach my $type (keys %{$found_types{$stream_id}}) {
                my $issuances = $editor->search_serial_issuance([ {"+sitem" => {"stream" => $stream_id, "status" => "Received"}, "+scap" => {"type" => $type}}, {"join" => {"sitem" => {}, "scap" => {}}, "order_by" => {"siss" => "date_published"}} ]);
                #TODO: evt on search failure
                my $evt = _prepare_summaries($editor, $issuances, $sdist_by_stream_id{$stream_id}, $type);
                if ($U->event_code($evt)) {
                    $editor->rollback;
                    return $evt;
                }
            }
        }
    }

    $editor->commit;
    return {'num_items' => scalar @$items, 'new_unit_id' => $new_unit_id};
}

sub _find_or_create_call_number {
    my ($e, $lib, $cn_string, $record) = @_;

    my ($prefix,$suffix) = ('','');
    if (ref($cn_string)) {
        ($prefix,$cn_string,$suffix) = @$cn_string;
        # the affix labels can never be NULL/undef
        $prefix //= '';
        $suffix //= '';
    }

    my $existing = $e->search_asset_call_number([{
        owning_lib  => $lib,
        label       => $cn_string,
        record      => $record,
        deleted     => "f",
        '+acnp'     => { label => $prefix },
        '+acns'     => { label => $suffix },
        
    },{
        join => { acnp => {}, acns => {} }
    }]) or return $e->die_event;

    if (@$existing) {
        return $existing->[0]->id;
    } else {
        return $e->die_event unless
            $e->allowed("CREATE_VOLUME", $lib);

        $prefix = -1 if (!$prefix);
        $suffix = -1 if (!$suffix);

        if ($prefix ne '-1') {
            my $acnp = $e->search_asset_call_number_prefix({
                owning_lib  => $lib,
                label       => $prefix,
            })->[0];

            if (!$acnp) {
                $acnp = new Fieldmapper::asset::call_number_prefix;
                $acnp->label($prefix);
                $acnp->owning_lib($lib);
                $e->create_asset_call_number_prefix($acnp) or return $e->die_event;
                $prefix = $e->data->id;
            } else {
                $prefix = $acnp->id;
            }
        }

        if ($suffix ne '-1') {
            my $acns = $e->search_asset_call_number_suffix({
                owning_lib  => $lib,
                label       => $suffix,
            })->[0];

            if (!$acns) {
                $acns = new Fieldmapper::asset::call_number_suffix;
                $acns->label($suffix);
                $acns->owning_lib($lib);
                $e->create_asset_call_number_suffix($acns) or return $e->die_event;
                $suffix = $e->data->id;
            } else {
                $suffix = $acns->id;
            }
        }

        my $acn = new Fieldmapper::asset::call_number;

        $acn->creator($e->requestor->id);
        $acn->editor($e->requestor->id);
        $acn->record($record);
        $acn->label($cn_string);
        $acn->owning_lib($lib);
        $acn->prefix($prefix);
        $acn->suffix($suffix);

        $e->create_asset_call_number($acn) or return $e->die_event;
        return $e->data->id;
    }
}

sub _issuances_received {
    # XXX TODO: Add some caching or something. This is getting called
    # more often than it has to be.
    my ($e, $sitem) = @_;

    my $results = $e->json_query({
        "select" => {"sitem" => ["issuance"]},
        "from" => {"sitem" => {"sstr" => {}, "siss" => {}}},
        "where" => {
            "+sstr" => {"distribution" => $sitem->stream->distribution->id},
            "+siss" => {"holding_type" => $sitem->issuance->holding_type},
            "+sitem" => {"date_received" => {"!=" => undef}}
        },
        "order_by" => {
            "siss" => {"date_published" => {"direction" => "asc"}}
        }
    }) or return $e->die_event;

    my %seen;
    my $issuances = [];
    for my $iss_id (map { $_->{"issuance"} } @$results) {
        next if $seen{$iss_id};
        $seen{$iss_id} = 1;
        push(@$issuances, $e->retrieve_serial_issuance($iss_id));
    }
    return $issuances;
}

# _prepare_unit populates the detailed_contents, summary_contents, and
# sort_key fields for a given unit based on a given set of issuances
# Also finds/creates call number as needed
sub _prepare_unit {
    my ($e, $sunit, $sdist, $issuances, $call_number_string, $record_id) = @_;

    # Handle call number first if we have one
    if ($call_number_string) {
        my $org_unit_id = ref $sdist->holding_lib ? $sdist->holding_lib->id : $sdist->holding_lib;
        my $real_cn = _find_or_create_call_number(
            $e, $org_unit_id,
            $call_number_string, $record_id
        );

        if ($U->event_code($real_cn)) {
            return $real_cn;
        } else {
            $sunit->call_number($real_cn);
        }
    }

    my ($mfhd, $formatted_parts) = _summarize_contents($e, $issuances);
    return $mfhd if $U->event_code($mfhd);

    # special case for single formatted_part (may have summarized version)
    if (@$formatted_parts == 1) {
        #TODO: MFHD.pm should have a 'format_summary' method for this
    }

    $sunit->detailed_contents(
        join(
            " ",
            $sdist->unit_label_prefix,
            join(", ", @$formatted_parts),
            $sdist->unit_label_suffix
        )
    );

    # TODO: change this when real summary contents are available
    $sunit->summary_contents($sunit->detailed_contents);

    # Create sort_key by left padding numbers to 6 digits.
    (my $sort_key = $sunit->detailed_contents) =~
        s/(\d+)/sprintf '%06d', $1/eg;
    $sunit->sort_key($sort_key);
}

# _prepare_summaries populates the generated_coverage field for a given summary 
# type ('basic', 'index', 'supplement') for a given distribution.
# It also creates the summary if it doesn't yet exist.
sub _prepare_summaries {
    my ($e, $issuances, $sdist, $type) = @_;

    my ($mfhd, $formatted_parts) = _summarize_contents($e, $issuances, $sdist, $type);
    return $mfhd if $U->event_code($mfhd);

    my $search_method = "search_serial_${type}_summary";
    my $summary = $e->$search_method([{"distribution" => $sdist->id}]);

    my $cu_method = "update";

    if (@$summary) {
        $summary = $summary->[0];
    } else {
        my $class = "Fieldmapper::serial::${type}_summary";
        $summary = $class->new;
        $summary->distribution($sdist->id);
        $cu_method = "create";
    }

    if (@$formatted_parts) {
        $summary->generated_coverage(OpenSRF::Utils::JSON->perl2JSON($formatted_parts));
    } else {
        # we had no issuances or MFHD data for this type, so clear any
        # generated data which may have existed before
        $summary->generated_coverage('');
    }
    my $method = "${cu_method}_serial_${type}_summary";
    return $e->die_event unless $e->$method($summary);
}


__PACKAGE__->register_method(
    method    => 'regen_summaries',
    api_name  => 'open-ils.serial.regenerate_summaries',
    api_level => 1,
    argc      => 1,
    signature => {
        'desc'   => 'Regenerate all the generated_coverage fields for given distributions or subscriptions (depending on params given). Params are expected to be hash members.',
        'params' => [ {
                 name => 'sdist_ids',
                 desc => 'IDs of the distribution whose coverage you want to regenerate',
                 type => 'array'
            },
            {
                 name => 'ssub_ids',
                 desc => 'IDs of the subscriptions whose coverage you want to regenerate',
                 type => 'array'
            }
        ],
        'return' => {
            desc => 'Returns undef if successful, event if failed',
            type => 'mixed'
        }
#TODO: best practices for return values
    }
);

sub regen_summaries {
    my ($self, $conn, $auth, $opts) = @_;

    my $e = new_editor("authtoken" => $auth, "xact" => 1);
    return $e->die_event unless $e->checkauth;
    # Perm checks not necessary since generated_coverage is akin to
    # caching of data, not actual editing.  XXX This might need more
    # consideration.
    #return $editor->die_event unless $editor->allowed("RECEIVE_SERIAL");

    my $evt = _regenerate_summaries($e, $opts);
    if ($U->event_code($evt)) {
        $e->rollback;
        return $evt;
    }

    $e->commit;

    return undef;
}

sub _regenerate_summaries {
    my ($e, $opts) = @_;

    $logger->debug('_regenerate_summaries with opts: ' . OpenSRF::Utils::JSON->perl2JSON($opts));
    my @sdist_ids;
    if ($opts->{'ssub_ids'}) {
        foreach my $ssub_id (@{$opts->{'ssub_ids'}}) {
            my $sdist_ids_temp = $e->search_serial_distribution(
                { 'subscription' => $ssub_id },
                { 'idlist' => 1 }
            );
            push(@sdist_ids, @$sdist_ids_temp);
        }
    } elsif ($opts->{'sdist_ids'}) {
        @sdist_ids = @$opts->{'sdist_ids'};
    }

    foreach my $sdist_id (@sdist_ids) {
        # get distribution
        my $sdist = $e->retrieve_serial_distribution($sdist_id)
            or return $e->die_event;

# See large comment below
#        my $has_merged_mfhd;
        foreach my $type (@MFHD_NAMES) {
            # get issuances
            my $issuances = $e->search_serial_issuance([
                {
                    "+sdist" => {"id" => $sdist_id},
                    "+sitem" => {"status" => "Received"},
                    "+scap" => {"type" => $type}
                },
                {
                    "join" => {
                        "sitem" => {},
                        "scap" => {},
                        "ssub" => {
                            "join" => {"sdist" =>{}}
                        }
                    },
                    "order_by" => {
                        "siss" => "date_published"
                    }
                }
            ]) or return $e->die_event;

# This level of nuance doesn't appear to be necessary.
# At the moment, we pass down an empty issuance list,
# and the inner methods will "do the right thing" and
# pull in the MFHD if called for, but in some cases not
# ultimately generate any coverage.  The code below is
# broken in cases where we delete the last issuance, since
# the now empty summary never gets updated.
#
# Leaving this code for now (2014/04) in case pushing
# the logic down ends up being too slow or complicates
# the inner methods beyond their scope.
#
#            if (!@$issuances and !$has_merged_mfhd) {
#                if (!defined($has_merged_mfhd)) {
#                    # even without issuances, we can generate a summary
#                    # from a merged MFHD record, so look for one
#                    my $mfhd_ids = $e->search_serial_record_entry(
#                        {
#                            '+sdist' => {
#                                'id' => $sdist_id,
#                                'summary_method' => 'merge_with_sre'
#                            }
#                        },
#                        {
#                            'join' => { 'sdist' => {} },
#                            'idlist' => 1
#                        }
#                    );
#                    if ($mfhd_ids and @$mfhd_ids) {
#                        $has_merged_mfhd = 1;
#                    } else {
#                        next;
#                    }
#                } else {
#                    next; # abort to prevent empty summary creation (i.e. '[]')
#                }
#            }
            my $evt = _prepare_summaries($e, $issuances, $sdist, $type);
            if ($U->event_code($evt)) {
                $e->rollback;
                return $evt;
            }
        }
    }

    return undef;
}

sub _unit_by_iss_and_str {
    my ($e, $issuance, $stream) = @_;

    my $unit = $e->json_query({
        "select" => {"sunit" => ["id"]},
        "from" => {"sitem" => {"sunit" => {}}},
        "where" => {
            "+sitem" => {
                "issuance" => $issuance->id,
                "stream" => $stream->id
            }
        }
    }) or return $e->die_event;
    return 0 if not @$unit;

    $e->retrieve_serial_unit($unit->[0]->{"id"}) or $e->die_event;
}

sub move_previous_unit {
    my ($e, $prev_iss, $curr_item, $new_loc) = @_;

    my $prev_unit = _unit_by_iss_and_str($e,$prev_iss,$curr_item->stream);
    return $prev_unit if defined $U->event_code($prev_unit);
    return 0 if not $prev_unit;

    if ($prev_unit->location != $new_loc) {
        $prev_unit->location($new_loc);
        $e->update_serial_unit($prev_unit) or return $e->die_event;
    }
    0;
}

# _previous_issuance() assumes $existing is an ordered array
sub _previous_issuance {
    my ($existing, $issuance) = @_;

    my $last = $existing->[-1];
    return undef unless $last;
    return ($last->id == $issuance->id ? $existing->[-2] : $last);
}

__PACKAGE__->register_method(
    "method" => "receive_items_one_unit_per",
    "api_name" => "open-ils.serial.receive_items.one_unit_per",
    "stream" => 1,
    "api_level" => 1,
    "argc" => 3,
    "signature" => {
        "desc" => "Marks items in a list as received, creates a new unit for each item if any unit is fleshed on, and updates summaries as needed",
        "params" => [
            {
                 "name" => "auth",
                 "desc" => "authtoken",
                 "type" => "string"
            },
            {
                 "name" => "items",
                 "desc" => "array of serial items, possibly fleshed with units and definitely fleshed with stream->distribution",
                 "type" => "array"
            },
            {
                "name" => "record",
                "desc" => "id of bib record these items are associated with
                    (XXX could/should be derived from items)",
                "type" => "number"
            }
        ],
        "return" => {
            "desc" => "The item ID for each item successfully received",
            "type" => "int"
        }
    }
);

sub receive_items_one_unit_per {
    # XXX This function may be temporary, as it does some of what
    # unitize_items() does, just in a different way.
    my ($self, $client, $auth, $items, $record) = @_;

    my $e = new_editor("authtoken" => $auth, "xact" => 1);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed("RECEIVE_SERIAL");

    my $prev_loc_setting_map = {};
    my $user_id = $e->requestor->id;

    # Get a list of all the non-virtual field names in a serial::unit for
    # merging given unit objects with template-built units later.
    # XXX move this somewhere global so it isn't re-run all the time
    my $all_unit_fields =
        $Fieldmapper::fieldmap->{"Fieldmapper::serial::unit"}->{"fields"};
    my @real_unit_fields = grep {
        not $all_unit_fields->{$_}->{"virtual"}
    } keys %$all_unit_fields;

    foreach my $item (@$items) {
        # Note that we expect a certain fleshing on the items we're getting.
        my $sdist = $item->stream->distribution;

        # Fetch a list of issuances with received copies already existing
        # on this distribution (and with the same holding type on the
        # issuance).  This will be used in up to two places: once when building
        # a summary, once when changing the copy location of the previous
        # issuance's copy.
        my $issuances_received = _issuances_received($e, $item);
        if ($U->event_code($issuances_received)) {
            $e->rollback;
            return $issuances_received;
        }

        # Find out if we need to to deal with previous copy location changing.
        my $ou = $sdist->holding_lib->id;
        unless (exists $prev_loc_setting_map->{$ou}) {
            $prev_loc_setting_map->{$ou} = $U->ou_ancestor_setting_value(
                $ou, "serial.prev_issuance_copy_location", $e
            );
        }

        # If there is a previous copy location setting, we need the previous
        # issuance, from which we can in turn look up the item attached to the
        # same stream we're on now.
        if ($prev_loc_setting_map->{$ou}) {
            if (my $prev_iss =
                _previous_issuance($issuances_received, $item->issuance)) {

                # Now we can change the copy location of the previous unit,
                # if needed.
                return $e->event if defined $U->event_code(
                    move_previous_unit(
                        $e, $prev_iss, $item, $prev_loc_setting_map->{$ou}
                    )
                );
            }
        }

        # Create unit if given by user
        if (ref $item->unit) {
            # detach from the item, as we need to create separately
            my $user_unit = $item->unit;

            # get a unit based on associated template
            my $template_unit = _build_unit($e, $sdist, "receive");
            if ($U->event_code($template_unit)) {
                $e->rollback;
                $template_unit->{"note"} = "Item ID: " . $item->id;
                return $template_unit;
            }

            # merge built unit with provided unit from user
            foreach (@real_unit_fields) {
                unless ($user_unit->$_) {
                    $user_unit->$_($template_unit->$_);
                }
            }

            # Treat call number specially: the provided value from the
            # user will really be a string.
            my $call_number_string;
            if ($user_unit->call_number) {
                $call_number_string = $user_unit->call_number;
                # clear call number for now (replaced in _prepare_unit)
                $user_unit->clear_call_number;
            }

            my $evt = _prepare_unit(
                $e, $user_unit, $sdist, [$item->issuance],
                $call_number_string, $record
            );
            if ($U->event_code($evt)) {
                $e->rollback;
                return $evt;
            }

            # create/update summary objects related to this distribution
            # Make sure @$issuances_received contains current item's issuance
            unless (grep { $_->id == $item->issuance->id } @$issuances_received) {
                push @$issuances_received, $item->issuance;
            }
            $evt = _prepare_summaries($e, $issuances_received, $item->stream->distribution, $item->issuance->holding_type);
            if ($U->event_code($evt)) {
                $e->rollback;
                return $evt;
            }

            # set the incontrovertibles on the unit
            $user_unit->edit_date("now");
            $user_unit->create_date("now");
            $user_unit->editor($user_id);
            $user_unit->creator($user_id);

            $evt = _create_sunit($e, $user_unit);
            return $evt if $evt;

            # save reference to new unit
            $item->unit($e->data->id);
        }

        # Create notes if given by user
        if (ref($item->notes) and @{$item->notes}) {
            foreach my $note (@{$item->notes}) {
                $note->creator($user_id);
                $note->create_date("now");

                return $e->die_event unless $e->create_serial_item_note($note);
            }

            $item->clear_notes; # They're saved; we no longer want them here.
        }

        # Set the incontrovertibles on the item
        $item->status("Received");
        $item->date_received("now");
        $item->edit_date("now");
        $item->editor($user_id);

        return $e->die_event unless $e->update_serial_item($item);

        # send client a response
        $client->respond($item->id);
    }

    $e->commit or return $e->die_event;
    undef;
}

sub _build_unit {
    my $editor = shift;
    my $sdist = shift;
    my $mode = shift;
    #my $skip_call_number = shift;

    my $attr = $mode . '_unit_template';
    my $template = $editor->retrieve_asset_copy_template($sdist->$attr) or
        return new OpenILS::Event("SERIAL_DISTRIBUTION_HAS_NO_COPY_TEMPLATE");

    my @parts = qw( status location loan_duration fine_level age_protect circulate deposit ref holdable deposit_amount price circ_modifier circ_as_type alert_message opac_visible floating mint_condition );

    my $unit = new Fieldmapper::serial::unit;
    foreach my $part (@parts) {
        my $value = $template->$part;
        next if !defined($value);
        $unit->$part($value);
    }

    # ignore circ_lib in template, set to distribution holding_lib
    $unit->circ_lib($sdist->holding_lib);
    $unit->creator($editor->requestor->id);
    $unit->editor($editor->requestor->id);

# XXX: this feature has been pushed back until after 2.0 at least
#    unless ($skip_call_number) {
#        $attr = $mode . '_call_number';
#        my $cn = $sdist->$attr or
#            return new OpenILS::Event("SERIAL_DISTRIBUTION_HAS_NO_CALL_NUMBER");
#
#        $unit->call_number($cn);
#    }
    $unit->call_number('-1'); # default to the dummy call number
    $unit->barcode('@@PLACEHOLDER'); # generic unit will start with a generated placeholder barcode
    $unit->sort_key('');
    $unit->summary_contents('');
    $unit->detailed_contents('');

    return $unit;
}

sub _summarize_contents {
    my $editor = shift;
    my $issuances = shift;
    my $sdist = shift;
    my $type = shift;

    # create or lookup MFHD record
    my $mfhd;
    if ($sdist and defined($sdist->record_entry) and $sdist->summary_method eq 'merge_with_sre') {
        my $sre;
        if (ref $sdist->record_entry) {
            $sre = $sdist->record_entry; 
        } else {
            $sre = $editor->retrieve_serial_record_entry($sdist->record_entry);
        }
        $mfhd = MFHD->new(MARC::Record->new_from_xml($sre->marc)); 
    } else {
        $logger->info($sdist);
        $mfhd = MFHD->new(MARC::Record->new());
    }

    my %scaps;
    my %scap_fields;
    my $seqno = 1;
    # We keep track of these separately to avoid link_id contamination,
    # e.g. a basic issuance, followed by a merging supplement, followed by
    # another basic.  If we could be sure that they were not mixed, one
    # value could suffice.
    my %link_ids = ('basic' => 10000, 'index' => 10000, 'supplement' => 10000);
    my %first_scap = ('basic' => 1, 'index' => 1, 'supplement' => 1);
    foreach my $issuance (@$issuances) {
        my $scap_id = $issuance->caption_and_pattern;
        next if (!$scap_id); # skip issuances with no caption/pattern

        my $scap;
        my $scap_field;
        # if this is the first appearance of this scap, retrieve it and add it to the temporary record
        if (!exists $scaps{$issuance->caption_and_pattern}) {
            $scaps{$scap_id} = $editor->retrieve_serial_caption_and_pattern($scap_id);
            $scap = $scaps{$scap_id};
            $scap_field = _revive_caption($scap);
            my $did_merge = 0;
            if ($first_scap{$scap->type}) { # special merge processing
                $first_scap{$MFHD_TAGS_BY_NAME{$scap->type}} = 0;
                if ($sdist and $sdist->summary_method eq 'merge_with_sre') {
                    # MFHD Caption objects do not yet have a built-in compare (TODO), so let's do a basic one
                    my @field_85xs = $mfhd->field($MFHD_TAGS_BY_NAME{$scap->type});
                    if (@field_85xs) {
                        my $last_caption_field = $field_85xs[-1];
                        my $last_link_id = $last_caption_field->subfield('8');
                        # set the link id to match, temporarily, for comparison
                        $last_caption_field->update('8' => $scap_field->subfield('8'));
                        my $last_caption_json = OpenSRF::Utils::JSON->perl2JSON([$last_caption_field->indicator(1), $last_caption_field->indicator(2), $last_caption_field->subfields_list]);
                        if ($last_caption_json eq $scap->pattern_code) { # merge is possible, they match
                            # restore link id
                            $link_ids{$scap->type} = $last_link_id;
                            # set scap_field to last field
                            $scap_field = $last_caption_field;
                            $did_merge = 1;
                        }
                    }
                }
            }
            $scap_fields{$scap_id} = $scap_field;
            $scap_field->update('8' => $link_ids{$scap->type});
            # TODO: make MFHD/Caption smarter about this
            $scap_field->{_mfhdc_LINK_ID} = $link_ids{$scap->type};
            $mfhd->append_fields($scap_field) if !$did_merge;
            $link_ids{$scap->type}++;
        } else {
            $scap_field = $scap_fields{$scap_id};
        }

        $mfhd->append_fields(_revive_holding($issuance->holding_code, $scap_field, $seqno));
        $seqno++;
    }

    my @formatted_parts;
    my @scap_fields_ordered;
    if ($type) {
        @scap_fields_ordered = $mfhd->field($MFHD_TAGS_BY_NAME{$type});
    } else {
        # if they didn't give a type, send back whatever holdings we have.
        # this is really only sensible right now for summarizing one type,
        # and is used by the unitize code for this purpose
        #
        # TODO: possible future support for binding (unitizing) of multiple
        # types into a sensible summary string
        @scap_fields_ordered = $mfhd->field('85[345]');
    }

    foreach my $scap_field (@scap_fields_ordered) { #TODO: use generic MFHD "summarize" method, once available
        my @updated_holdings;
        eval {
            @updated_holdings = $mfhd->get_combined_holdings($scap_field);
        };
        if ($@) {
            my $msg = "get_combined_holdings(): $@ ; using sdist ID #" .
                ($sdist ? $sdist->id : "<NONE>") . " and " .
                scalar(@$issuances) . " issuances, of which one has ID #" .
                $issuances->[0]->id;

            $msg =~ s/\n//gm;
            $logger->error($msg);
            return new OpenILS::Event("BAD_PARAMS", note => $msg);
        }

        push @formatted_parts, map { $_->format } @updated_holdings;
    }

    return ($mfhd, \@formatted_parts);
}

##########################################################################
# note methods
#
__PACKAGE__->register_method(
    method      => 'fetch_notes',
    api_name        => 'open-ils.serial.item_note.retrieve.all',
    signature   => q/
        Returns an array of copy note objects.  
        @param args A named hash of parameters including:
            authtoken   : Required if viewing non-public notes
            item_id      : The id of the item whose notes we want to retrieve
            pub         : True if all the caller wants are public notes
        @return An array of note objects
    /
);

__PACKAGE__->register_method(
    method      => 'fetch_notes',
    api_name        => 'open-ils.serial.subscription_note.retrieve.all',
    signature   => q/
        Returns an array of copy note objects.  
        @param args A named hash of parameters including:
            authtoken       : Required if viewing non-public notes
            subscription_id : The id of the item whose notes we want to retrieve
            pub             : True if all the caller wants are public notes
        @return An array of note objects
    /
);

__PACKAGE__->register_method(
    method      => 'fetch_notes',
    api_name        => 'open-ils.serial.distribution_note.retrieve.all',
    signature   => q/
        Returns an array of copy note objects.  
        @param args A named hash of parameters including:
            authtoken       : Required if viewing non-public notes
            distribution_id : The id of the item whose notes we want to retrieve
            pub             : True if all the caller wants are public notes
        @return An array of note objects
    /
);

# TODO: revisit this method to consider replacing cstore direct calls
sub fetch_notes {
    my( $self, $connection, $args ) = @_;
    
    $self->api_name =~ /serial\.(\w*)_note/;
    my $type = $1;

    my $id = $$args{object_id};
    my $authtoken = $$args{authtoken};
    my $order_by = $$args{order_by} || 'create_date';
    my( $r, $evt);

    if( $$args{pub} ) {
        return $U->cstorereq(
            'open-ils.cstore.direct.serial.'.$type.'_note.search.atomic',
            { $type => $id, pub => 't' }, {'order_by' => {$FM_NAME_TO_ID{$type}.'n' => $order_by}} );
    } else {
        # FIXME: restore perm check
        # ( $r, $evt ) = $U->checksesperm($authtoken, 'VIEW_COPY_NOTES');
        # return $evt if $evt;
        return $U->cstorereq(
            'open-ils.cstore.direct.serial.'.$type.'_note.search.atomic', {$type => $id}, {'order_by' => {$FM_NAME_TO_ID{$type}.'n' => $order_by}} );
    }

    return undef;
}

__PACKAGE__->register_method(
    method      => 'update_note',
    api_name        => 'open-ils.serial.item_note.update',
    signature   => q/
        Updates or creates an item note
        @param authtoken The login session key
        @param note The note object to update or create
        @return The id of the note object
    /
);

__PACKAGE__->register_method(
    method      => 'update_note',
    api_name        => 'open-ils.serial.subscription_note.update',
    signature   => q/
        Updates or creates a subscription note
        @param authtoken The login session key
        @param note The note object to update or create
        @return The id of the note object
    /
);

__PACKAGE__->register_method(
    method      => 'update_note',
    api_name        => 'open-ils.serial.distribution_note.update',
    signature   => q/
        Updates or creates a distribution note
        @param authtoken The login session key
        @param note The note object to update or create
        @return The id of the note object
    /
);

sub update_note {
    my( $self, $connection, $authtoken, $note ) = @_;

    $self->api_name =~ /serial\.(\w*)_note/;
    my $type = $1;

    my $e = new_editor(xact=>1, authtoken=>$authtoken);
    return $e->event unless $e->checkauth;

    if ($type eq 'item') {
        my $sitem = $e->retrieve_serial_item([
            $note->item, {
                "flesh" => 2, "flesh_fields" => {
                    "sitem" => ["stream"], "sstr" => ["distribution"]
                }
            }
        ]) or return $e->die_event;

        return $e->die_event unless $e->allowed(
            "ADMIN_SERIAL_ITEM", $sitem->stream->distribution->holding_lib
        );
    } elsif ($type eq 'distribution') {
        my $sdist = $e->retrieve_serial_distribution($note->distribution)
            or return $e->die_event;

        return $e->die_event unless
            $e->allowed("ADMIN_SERIAL_DISTRIBUTION", $sdist->holding_lib);
    } else { # subscription
        my $sub = $e->retrieve_serial_subscription($note->subscription)
            or return $e->die_event;

        return $e->die_event unless
            $e->allowed("ADMIN_SERIAL_SUBSCRIPTION", $sub->owning_lib);
    }

    $note->pub( ($U->is_true($note->pub)) ? 't' : 'f' );
    my $method;
    if ($note->isnew) {
        $note->create_date('now');
        $note->creator($e->requestor->id);
        $note->clear_id;
        $method = "create_serial_${type}_note";
    } else {
        $method = "update_serial_${type}_note";
    }
    $e->$method($note) or return $e->event;
    $e->commit;
    return $note->id;
}

__PACKAGE__->register_method(
    method      => 'delete_note',
    api_name        =>  'open-ils.serial.item_note.delete',
    signature   => q/
        Deletes an existing item note
        @param authtoken The login session key
        @param noteid The id of the note to delete
        @return 1 on success - Event otherwise.
        /
);

__PACKAGE__->register_method(
    method      => 'delete_note',
    api_name        =>  'open-ils.serial.subscription_note.delete',
    signature   => q/
        Deletes an existing subscription note
        @param authtoken The login session key
        @param noteid The id of the note to delete
        @return 1 on success - Event otherwise.
        /
);

__PACKAGE__->register_method(
    method      => 'delete_note',
    api_name        =>  'open-ils.serial.distribution_note.delete',
    signature   => q/
        Deletes an existing distribution note
        @param authtoken The login session key
        @param noteid The id of the note to delete
        @return 1 on success - Event otherwise.
        /
);

sub delete_note {
    my( $self, $conn, $authtoken, $noteid ) = @_;

    $self->api_name =~ /serial\.(\w*)_note/;
    my $type = $1;

    my $e = new_editor(xact=>1, authtoken=>$authtoken);
    return $e->die_event unless $e->checkauth;

    my $method = "retrieve_serial_${type}_note";
    my $note = $e->$method([
        $noteid,
    ]) or return $e->die_event;

    if ($type eq 'item') {
        my $sitem = $e->retrieve_serial_item([
            $note->item, {
                "flesh" => 2, "flesh_fields" => {
                    "sitem" => ["stream"], "sstr" => ["distribution"]
                }
            }
        ]) or return $e->die_event;

        return $e->die_event unless $e->allowed(
            "ADMIN_SERIAL_ITEM", $sitem->stream->distribution->holding_lib
        );
    } elsif ($type eq 'distribution') {
        my $sdist = $e->retrieve_serial_distribution($note->distribution)
            or return $e->die_event;

        return $e->die_event unless
            $e->allowed("ADMIN_SERIAL_DISTRIBUTION", $sdist->holding_lib);
    } else { # subscription
        my $sub = $e->retrieve_serial_subscription($note->subscription)
            or return $e->die_event;

        return $e->die_event unless
            $e->allowed("ADMIN_SERIAL_SUBSCRIPTION", $sub->owning_lib);
    }

    $method = "delete_serial_${type}_note";
    $e->$method($note) or return $e->die_event;
    $e->commit;
    return 1;
}


##########################################################################
# subscription methods
#

__PACKAGE__->register_method(
    method      => 'safe_delete',
    api_name        =>  'open-ils.serial.subscription.safe_delete',
    signature   => q/
        Deletes an existing subscription and related records
        (distributions, streams, etc.), but only if there are no serial
        items with a status other than Expected, and no non-deleted 
        serial units.
        @param authtoken The login session key
        @param subid The id of the subscription to delete
        @return 1 on success - Event otherwise.
        /
);

__PACKAGE__->register_method(
    method      => 'safe_delete',
    api_name        =>  'open-ils.serial.distribution.safe_delete',
    signature   => q/
        Deletes an existing distribution and related records
        (streams, etc.), but only if there are no attached serial items
        with a status other than Expected, and no non-deleted serial
        units.
        @param authtoken The login session key
        @param subid The id of the distribution to delete
        @return 1 on success - Event otherwise.
        /
);

__PACKAGE__->register_method(
    method      => 'safe_delete',
    api_name        =>  'open-ils.serial.stream.safe_delete',
    signature   => q/
        Deletes an existing stream and associated routing list, but only
        if there are no attached serial items with a status other than
        Expected, and no non-deleted serial units.
        items and no issuances.
        @param authtoken The login session key
        @param strid The id of the stream to delete
        @return 1 on success - Event otherwise.
        /
);

__PACKAGE__->register_method(
    method      => 'safe_delete',
    api_name        =>  'open-ils.serial.caption_and_pattern.safe_delete',
    signature   => q/
        Deletes an existing caption and pattern object, but only
        if there are no attached serial issuances. 
        @param authtoken The login session key
        @param strid The id of the scap to delete
        @return 1 on success - Event otherwise.
        /
);

__PACKAGE__->register_method(
    method      => 'safe_delete',
    api_name        =>  'open-ils.serial.subscription.safe_delete.dry_run',
);
__PACKAGE__->register_method(
    method      => 'safe_delete',
    api_name        =>  'open-ils.serial.distribution.safe_delete.dry_run',
);
__PACKAGE__->register_method(
    method      => 'safe_delete',
    api_name        =>  'open-ils.serial.stream.safe_delete.dry_run',
);
__PACKAGE__->register_method(
    method      => 'safe_delete',
    api_name        =>  'open-ils.serial.caption_and_pattern.safe_delete.dry_run',
);

sub safe_delete {
    my( $self, $conn, $authtoken, $id ) = @_;

    $self->api_name =~ /serial\.(\w*)\.safe_delete/;
    my $type = $1;

    my $e = new_editor(xact=>1, authtoken=>$authtoken);
    return $e->die_event unless $e->checkauth;

    my $obj;

    if ($type eq 'stream') {
        my $sstr = $e->retrieve_serial_stream([
            $id, {
                "flesh" => 2, "flesh_fields" => {
                    "sstr" => ["items","distribution"],
                    "sitem" => ["unit"]
                }
            }
        ]) or return $e->die_event;

        return $e->die_event unless $e->allowed(
            "ADMIN_SERIAL_STREAM", $sstr->distribution->holding_lib
        );

        foreach my $sitem (@{$sstr->items}) {
            if ($sitem->status ne 'Expected') {
                return $e->die_event(OpenILS::Event->new('SERIAL_STREAM_NOT_EMPTY', payload=>$id));
            }
            if ($sitem->unit && !$U->is_true($sitem->unit->deleted)) {
                return $e->die_event(OpenILS::Event->new('SERIAL_STREAM_NOT_EMPTY', payload=>$id));
            }
        }

        $obj = $sstr;

    } elsif ($type eq 'distribution') {
        my $sdist = $e->retrieve_serial_distribution([
            $id, {
                "flesh" => 3, "flesh_fields" => {
                    "sstr" => ["items"],
                    "sdist" => ["streams"],
                    "sitem" => ["unit"]
                }
            }
        ]) or return $e->die_event;

        return $e->die_event unless
            $e->allowed("ADMIN_SERIAL_DISTRIBUTION", $sdist->holding_lib);

        foreach my $sstr (@{$sdist->streams}) {
            foreach my $sitem (@{$sstr->items}) {
                if ($sitem->status ne 'Expected') {
                    return $e->die_event(OpenILS::Event->new('SERIAL_DISTRIBUTION_NOT_EMPTY', payload=>$id));
                }
                if ($sitem->unit && !$U->is_true($sitem->unit->deleted)) {
                    return $e->die_event(OpenILS::Event->new('SERIAL_DISTRIBUTION_NOT_EMPTY', payload=>$id));
                }
            }
        }

        $obj = $sdist;

    } elsif ($type eq 'caption_and_pattern') {
        my $scap = $e->retrieve_serial_caption_and_pattern([
            $id,
            { flesh => 1, flesh_fields => { scap => ['subscription'] } }
        ]) or return $e->die_event;

        return $e->die_event unless
            $e->allowed("ADMIN_SERIAL_CAPTION_PATTERN", $scap->subscription->owning_lib);

        my $issuances = $e->search_serial_issuance([{
            caption_and_pattern => $id
        },{
            flesh => 2,
            flesh_fields => {
                siss  => ['items'],
                sitem => ['unit']
            }
        }]);

        foreach my $siss (@$issuances) {
            foreach my $sitem (@{$siss->items}) {
                if ($sitem->status ne 'Expected') {
                    return $e->die_event(OpenILS::Event->new('SERIAL_CAPTION_AND_PATTERN_NOT_EMPTY', payload=>$id));
                }
                if ($sitem->unit && !$U->is_true($sitem->unit->deleted)) {
                    return $e->die_event(OpenILS::Event->new('SERIAL_CAPTION_AND_PATTERN_NOT_EMPTY', payload=>$id));
                }
            }
        }

        $obj = $scap;

    } else { # subscription
        my $sub = $e->retrieve_serial_subscription([
            $id, {
                "flesh" => 4, "flesh_fields" => {
                    "ssub" => [qw/distributions issuances/],
                    "sdist" => [qw/streams/],
                    "sstr" => ["items"],
                    "sitem" => ["unit"]
                }
            }
        ]) or return $e->die_event;

        return $e->die_event unless
            $e->allowed("ADMIN_SERIAL_SUBSCRIPTION", $sub->owning_lib);

        foreach my $sdist (@{$sub->distributions}) {
            foreach my $sstr (@{$sdist->streams}) {
                foreach my $sitem (@{$sstr->items}) {
                    if ($sitem->status ne 'Expected') {
                        return $e->die_event(OpenILS::Event->new('SERIAL_SUBSCRIPTION_NOT_EMPTY', payload=>$id));
                    }
                    if ($sitem->unit && !$U->is_true($sitem->unit->deleted)) {
                        return $e->die_event(OpenILS::Event->new('SERIAL_SUBSCRIPTION_NOT_EMPTY', payload=>$id));
                    }
                }
            }
        }

        $obj = $sub;
    }

    if (! ($self->api_name =~ /dry_run/)) {
        my $method = "delete_serial_${type}";
        $e->$method($obj) or return $e->die_event;
        $e->commit;
    }

    return 1;
}

__PACKAGE__->register_method(
    method    => 'fleshed_ssub_alter',
    api_name  => 'open-ils.serial.subscription.fleshed.batch.update',
    api_level => 1,
    argc      => 2,
    signature => {
        desc     => 'Receives an array of one or more subscriptions and updates the database as needed',
        'params' => [ {
                 name => 'authtoken',
                 desc => 'Authtoken for current user session',
                 type => 'string'
            },
            {
                 name => 'subscriptions',
                 desc => 'Array of fleshed subscriptions',
                 type => 'array'
            }

        ],
        'return' => {
            desc => 'Returns 1 if successful, event if failed',
            type => 'mixed'
        }
    }
);

sub fleshed_ssub_alter {
    my( $self, $conn, $auth, $ssubs ) = @_;
    return 1 unless ref $ssubs;
    my( $reqr, $evt ) = $U->checkses($auth);
    return $evt if $evt;
    my $editor = new_editor(requestor => $reqr, xact => 1);
    my $override = $self->api_name =~ /override/;

    for my $ssub (@$ssubs) {
        my $owning_lib_id = ref $ssub->owning_lib ? $ssub->owning_lib->id : $ssub->owning_lib;
        return $editor->die_event unless
            $editor->allowed("ADMIN_SERIAL_SUBSCRIPTION", $owning_lib_id);

        my $ssubid = $ssub->id;

        if( $ssub->isdeleted ) {
            $evt = _delete_ssub( $editor, $override, $ssub);
        } elsif( $ssub->isnew ) {
            _cleanse_dates($ssub, ['start_date','end_date']);
            $evt = _create_ssub( $editor, $ssub );
        } else {
            _cleanse_dates($ssub, ['start_date','end_date']);
            $evt = _update_ssub( $editor, $override, $ssub );
        }
    }

    if( $evt ) {
        $logger->info("fleshed subscription-alter failed with event: ".OpenSRF::Utils::JSON->perl2JSON($evt));
        $editor->rollback;
        return $evt;
    }
    $logger->debug("subscription-alter: done updating subscription batch");
    $editor->commit;
    $logger->info("fleshed subscription-alter successfully updated ".scalar(@$ssubs)." subscriptions");
    return 1;
}

sub _delete_ssub {
    my ($editor, $override, $ssub) = @_;
    $logger->info("subscription-alter: delete subscription ".OpenSRF::Utils::JSON->perl2JSON($ssub));
    my $sdists = $editor->search_serial_distribution(
            { subscription => $ssub->id }, { limit => 1 } ); #TODO: 'deleted' support?
    my $cps = $editor->search_serial_caption_and_pattern(
            { subscription => $ssub->id }, { limit => 1 } ); #TODO: 'deleted' support?
    my $sisses = $editor->search_serial_issuance(
            { subscription => $ssub->id }, { limit => 1 } ); #TODO: 'deleted' support?
    return OpenILS::Event->new(
            'SERIAL_SUBSCRIPTION_NOT_EMPTY', payload => $ssub->id ) if (@$sdists or @$cps or @$sisses);

    return $editor->event unless $editor->delete_serial_subscription($ssub);
    return 0;
}

sub _create_ssub {
    my ($editor, $ssub) = @_;

    $logger->info("subscription-alter: new subscription ".OpenSRF::Utils::JSON->perl2JSON($ssub));
    return $editor->event unless $editor->create_serial_subscription($ssub);
    return 0;
}

sub _update_ssub {
    my ($editor, $override, $ssub) = @_;

    $logger->info("subscription-alter: retrieving subscription ".$ssub->id);
    my $orig_ssub = $editor->retrieve_serial_subscription($ssub->id);

    $logger->info("subscription-alter: original subscription ".OpenSRF::Utils::JSON->perl2JSON($orig_ssub));
    $logger->info("subscription-alter: updated subscription ".OpenSRF::Utils::JSON->perl2JSON($ssub));
    return $editor->event unless $editor->update_serial_subscription($ssub);
    return 0;
}

__PACKAGE__->register_method(
    method  => "fleshed_serial_subscription_retrieve_batch",
    authoritative => 1,
    api_name    => "open-ils.serial.subscription.fleshed.batch.retrieve"
);

sub fleshed_serial_subscription_retrieve_batch {
    my( $self, $client, $ids ) = @_;
# FIXME: permissions?
    $logger->info("Fetching fleshed subscriptions @$ids");
    return $U->cstorereq(
        "open-ils.cstore.direct.serial.subscription.search.atomic",
        { id => $ids },
        { flesh => 1,
          flesh_fields => {ssub => [ qw/owning_lib notes/ ]}
        });
}

__PACKAGE__->register_method(
    method  => "retrieve_sub_tree",
    authoritative => 1,
    api_name    => "open-ils.serial.subscription_tree.retrieve"
);

__PACKAGE__->register_method(
    method  => "retrieve_sub_tree",
    api_name    => "open-ils.serial.subscription_tree.global.retrieve"
);

sub retrieve_sub_tree {

    my( $self, $client, $user_session, $docid, @org_ids ) = @_;

    if(ref($org_ids[0])) { @org_ids = @{$org_ids[0]}; }

    $docid = "$docid";

    # TODO: permission support
    if(!@org_ids and $user_session) {
        my $user_obj = 
            OpenILS::Application::AppUtils->check_user_session( $user_session ); #throws EX on error
            @org_ids = ($user_obj->home_ou);
    }

    if( $self->api_name =~ /global/ ) {
        return _build_subs_list( { record_entry => $docid } ); # TODO: filter for !deleted, or active?

    } else {

        my @all_subs;
        for my $orgid (@org_ids) {
            my $subs = _build_subs_list( 
                    { record_entry => $docid, owning_lib => $orgid } );# TODO: filter for !deleted, or active?
            push( @all_subs, @$subs );
        }
        
        return \@all_subs;
    }

    return undef;
}

sub _build_subs_list {
    my $search_hash = shift;

    #$search_hash->{deleted} = 'f';
    my $e = new_editor();

    my $subs = $e->search_serial_subscription([$search_hash, { 'order_by' => {'ssub' => 'id'} }]);

    my @built_subs;

    for my $sub (@$subs) {

        # TODO: filter on !deleted?
        my $dists = $e->search_serial_distribution(
            [{ subscription => $sub->id }, { 'order_by' => {'sdist' => 'label'} }]
            );

        #$dists = [ sort { $a->label cmp $b->label } @$dists  ];

        $sub->distributions($dists);
        
        # TODO: filter on !deleted?
        my $issuances = $e->search_serial_issuance(
            [{ subscription => $sub->id }, { 'order_by' => {'siss' => 'label'} }]
            );

        #$issuances = [ sort { $a->label cmp $b->label } @$issuances  ];
        $sub->issuances($issuances);

        # TODO: filter on !deleted?
        my $scaps = $e->search_serial_caption_and_pattern(
            [{ subscription => $sub->id }, { 'order_by' => {'scap' => 'id'} }]
            );

        #$scaps = [ sort { $a->id cmp $b->id } @$scaps  ];
        $sub->scaps($scaps);
        push( @built_subs, $sub );
    }

    return \@built_subs;

}

__PACKAGE__->register_method(
    method  => "subscription_orgs_for_title",
    authoritative => 1,
    api_name    => "open-ils.serial.subscription.retrieve_orgs_by_title"
);

sub subscription_orgs_for_title {
    my( $self, $client, $record_id ) = @_;

    my $subs = $U->simple_scalar_request(
        "open-ils.cstore",
        "open-ils.cstore.direct.serial.subscription.search.atomic",
        { record_entry => $record_id }); # TODO: filter on !deleted?

    my $orgs = { map {$_->owning_lib => 1 } @$subs };
    return [ keys %$orgs ];
}


##########################################################################
# distribution methods
#
__PACKAGE__->register_method(
    method    => 'fleshed_sdist_alter',
    api_name  => 'open-ils.serial.distribution.fleshed.batch.update',
    api_level => 1,
    argc      => 2,
    signature => {
        desc     => 'Receives an array of one or more distributions and updates the database as needed',
        'params' => [ {
                 name => 'authtoken',
                 desc => 'Authtoken for current user session',
                 type => 'string'
            },
            {
                 name => 'distributions',
                 desc => 'Array of fleshed distributions',
                 type => 'array'
            }

        ],
        'return' => {
            desc => 'Returns 1 if successful, event if failed',
            type => 'mixed'
        }
    }
);

sub fleshed_sdist_alter {
    my( $self, $conn, $auth, $sdists ) = @_;
    return 1 unless ref $sdists;
    my( $reqr, $evt ) = $U->checkses($auth);
    return $evt if $evt;
    my $editor = new_editor(requestor => $reqr, xact => 1);
    my $override = $self->api_name =~ /override/;

    for my $sdist (@$sdists) {
        my $holding_lib_id = ref $sdist->holding_lib ? $sdist->holding_lib->id : $sdist->holding_lib;
        return $editor->die_event unless
            $editor->allowed("ADMIN_SERIAL_DISTRIBUTION", $holding_lib_id);

        if( $sdist->isdeleted ) {
            $evt = _delete_sdist( $editor, $override, $sdist);
        } elsif( $sdist->isnew ) {
            $evt = _create_sdist( $editor, $sdist );
        } else {
            $evt = _update_sdist( $editor, $override, $sdist );
        }
    }

    if( $evt ) {
        $logger->info("fleshed distribution-alter failed with event: ".OpenSRF::Utils::JSON->perl2JSON($evt));
        $editor->rollback;
        return $evt;
    }
    $logger->debug("distribution-alter: done updating distribution batch");
    $editor->commit;
    $logger->info("fleshed distribution-alter successfully updated ".scalar(@$sdists)." distributions");
    return 1;
}

sub _delete_sdist {
    my ($editor, $override, $sdist) = @_;
    $logger->info("distribution-alter: delete distribution ".OpenSRF::Utils::JSON->perl2JSON($sdist));
    return $editor->event unless $editor->delete_serial_distribution($sdist);
    return 0;
}

sub _create_sdist {
    my ($editor, $sdist) = @_;

    $logger->info("distribution-alter: new distribution ".OpenSRF::Utils::JSON->perl2JSON($sdist));
    return $editor->event unless $editor->create_serial_distribution($sdist);

    # create summaries too
    my $summary = new Fieldmapper::serial::basic_summary;
    $summary->distribution($sdist->id);
    $summary->generated_coverage('');
    return $editor->event unless $editor->create_serial_basic_summary($summary);
    $summary = new Fieldmapper::serial::supplement_summary;
    $summary->distribution($sdist->id);
    $summary->generated_coverage('');
    return $editor->event unless $editor->create_serial_supplement_summary($summary);
    $summary = new Fieldmapper::serial::index_summary;
    $summary->distribution($sdist->id);
    $summary->generated_coverage('');
    return $editor->event unless $editor->create_serial_index_summary($summary);

    # create a starter stream (TODO: reconsider this)
    my $stream = new Fieldmapper::serial::stream;
    $stream->distribution($sdist->id);
    return $editor->event unless $editor->create_serial_stream($stream);

    return 0;
}

sub _update_sdist {
    my ($editor, $override, $sdist) = @_;

    $logger->info("distribution-alter: retrieving distribution ".$sdist->id);
    my $orig_sdist = $editor->retrieve_serial_distribution($sdist->id);

    $logger->info("distribution-alter: original distribution ".OpenSRF::Utils::JSON->perl2JSON($orig_sdist));
    $logger->info("distribution-alter: updated distribution ".OpenSRF::Utils::JSON->perl2JSON($sdist));
    return $editor->event unless $editor->update_serial_distribution($sdist);
    return 0;
}

__PACKAGE__->register_method(
    method  => "fleshed_serial_distribution_retrieve_batch",
    authoritative => 1,
    api_name    => "open-ils.serial.distribution.fleshed.batch.retrieve"
);

sub fleshed_serial_distribution_retrieve_batch {
    my( $self, $client, $ids ) = @_;
# FIXME: permissions?
    $logger->info("Fetching fleshed distributions @$ids");
    return $U->cstorereq(
        "open-ils.cstore.direct.serial.distribution.search.atomic",
        { id => $ids },
        { flesh => 1,
          flesh_fields => {sdist => [ qw/ holding_lib receive_call_number receive_unit_template bind_call_number bind_unit_template streams notes / ]}
        });
}

__PACKAGE__->register_method(
    method  => "retrieve_dist_tree",
    authoritative => 1,
    api_name    => "open-ils.serial.distribution_tree.retrieve"
);

__PACKAGE__->register_method(
    method  => "retrieve_dist_tree",
    api_name    => "open-ils.serial.distribution_tree.global.retrieve"
);

sub retrieve_dist_tree {
    my( $self, $client, $user_session, $docid, @org_ids ) = @_;

    if(ref($org_ids[0])) { @org_ids = @{$org_ids[0]}; }

    $docid = "$docid";

    # TODO: permission support
    if(!@org_ids and $user_session) {
        my $user_obj =
            OpenILS::Application::AppUtils->check_user_session( $user_session ); #throws EX on error
            @org_ids = ($user_obj->home_ou);
    }

    my $e = new_editor();

    if( $self->api_name =~ /global/ ) {
        return $e->search_serial_distribution([{'+ssub' => { record_entry => $docid }},
            {   flesh => 1,
                flesh_fields => {sdist => [ qw/ holding_lib receive_call_number receive_unit_template bind_call_number bind_unit_template streams basic_summary supplement_summary index_summary / ]},
                order_by => {'sdist' => 'id'},
                'join' => {'ssub' => {}}
            }
        ]); # TODO: filter for !deleted?

    } else {
        my @all_dists;
        for my $orgid (@org_ids) {
            my $dists = $e->search_serial_distribution([{'+ssub' => { record_entry => $docid }, holding_lib => $orgid},
                {   flesh => 1,
                    flesh_fields => {sdist => [ qw/ holding_lib receive_call_number receive_unit_template bind_call_number bind_unit_template streams basic_summary supplement_summary index_summary / ]},
                    order_by => {'sdist' => 'id'},
                    'join' => {'ssub' => {}}
                }
            ]); # TODO: filter for !deleted?
            push( @all_dists, @$dists ) if $dists;
        }

        return \@all_dists;
    }

    return undef;
}


__PACKAGE__->register_method(
    method  => "distribution_orgs_for_title",
    authoritative => 1,
    api_name    => "open-ils.serial.distribution.retrieve_orgs_by_title"
);

sub distribution_orgs_for_title {
    my( $self, $client, $record_id ) = @_;

    my $dists = $U->cstorereq(
        "open-ils.cstore.direct.serial.distribution.search.atomic",
        { '+ssub' => { record_entry => $record_id } },
        { 'join' => {'ssub' => {}} }); # TODO: filter on !deleted?

    my $orgs = { map {$_->holding_lib => 1 } @$dists };
    return [ keys %$orgs ];
}


##########################################################################
# caption and pattern methods
#
__PACKAGE__->register_method(
    method    => 'scap_alter',
    api_name  => 'open-ils.serial.caption_and_pattern.batch.update',
    api_level => 1,
    argc      => 2,
    signature => {
        desc     => 'Receives an array of one or more caption and patterns and updates the database as needed',
        'params' => [ {
                 name => 'authtoken',
                 desc => 'Authtoken for current user session',
                 type => 'string'
            },
            {
                 name => 'scaps',
                 desc => 'Array of caption and patterns',
                 type => 'array'
            }

        ],
        'return' => {
            desc => 'Returns 1 if successful, event if failed',
            type => 'mixed'
        }
    }
);

sub scap_alter {
    my( $self, $conn, $auth, $scaps ) = @_;
    return 1 unless ref $scaps;
    my( $reqr, $evt ) = $U->checkses($auth);
    return $evt if $evt;
    my $editor = new_editor(requestor => $reqr, xact => 1);
    my $override = $self->api_name =~ /override/;

    my %found_ssub_ids;
    for my $scap (@$scaps) {
        if (!exists($found_ssub_ids{$scap->subscription})) {
            my $ssub = $editor->retrieve_serial_subscription($scap->subscription) or return $editor->die_event;
            return $editor->die_event unless
                $editor->allowed("ADMIN_SERIAL_CAPTION_PATTERN", $ssub->owning_lib);
            $found_ssub_ids{$scap->subscription} = 1;
        }

        if( $scap->isdeleted ) {
            $evt = _delete_scap( $editor, $override, $scap);
        } elsif( $scap->isnew ) {
            $evt = _create_scap( $editor, $scap );
        } else {
            $evt = _update_scap( $editor, $override, $scap );
        }
    }

    if( $evt ) {
        $logger->info("caption_and_pattern-alter failed with event: ".OpenSRF::Utils::JSON->perl2JSON($evt));
        $editor->rollback;
        return $evt;
    }
    $logger->debug("caption_and_pattern-alter: done updating caption_and_pattern batch");
    $editor->commit;
    $logger->info("caption_and_pattern-alter successfully updated ".scalar(@$scaps)." caption_and_patterns");
    return 1;
}

sub _delete_scap {
    my ($editor, $override, $scap) = @_;
    $logger->info("caption_and_pattern-alter: delete caption_and_pattern ".OpenSRF::Utils::JSON->perl2JSON($scap));
    my $sisses = $editor->search_serial_issuance(
            { caption_and_pattern => $scap->id }, { limit => 1 } ); #TODO: 'deleted' support?
    return OpenILS::Event->new(
            'SERIAL_CAPTION_AND_PATTERN_HAS_ISSUANCES', payload => $scap->id ) if (@$sisses);

    return $editor->event unless $editor->delete_serial_caption_and_pattern($scap);
    return 0;
}

sub _create_scap {
    my ($editor, $scap) = @_;

    $logger->info("caption_and_pattern-alter: new caption_and_pattern ".OpenSRF::Utils::JSON->perl2JSON($scap));
    return $editor->event unless $editor->create_serial_caption_and_pattern($scap);
    return 0;
}

sub _update_scap {
    my ($editor, $override, $scap) = @_;

    $logger->info("caption_and_pattern-alter: retrieving caption_and_pattern ".$scap->id);
    my $orig_scap = $editor->retrieve_serial_caption_and_pattern($scap->id);

    $logger->info("caption_and_pattern-alter: original caption_and_pattern ".OpenSRF::Utils::JSON->perl2JSON($orig_scap));
    $logger->info("caption_and_pattern-alter: updated caption_and_pattern ".OpenSRF::Utils::JSON->perl2JSON($scap));
    return $editor->event unless $editor->update_serial_caption_and_pattern($scap);
    return 0;
}

__PACKAGE__->register_method(
    method  => "serial_caption_and_pattern_retrieve_batch",
    authoritative => 1,
    api_name    => "open-ils.serial.caption_and_pattern.batch.retrieve"
);

sub serial_caption_and_pattern_retrieve_batch {
    my( $self, $client, $ids ) = @_;
    $logger->info("Fetching caption_and_patterns @$ids");
    return $U->cstorereq(
        "open-ils.cstore.direct.serial.caption_and_pattern.search.atomic",
        { id => $ids }
    );
}

##########################################################################
# stream methods
#
__PACKAGE__->register_method(
    method    => 'sstr_alter',
    api_name  => 'open-ils.serial.stream.batch.update',
    api_level => 1,
    argc      => 2,
    signature => {
        desc     => 'Receives an array of one or more streams and updates the database as needed',
        'params' => [ {
                 name => 'authtoken',
                 desc => 'Authtoken for current user session',
                 type => 'string'
            },
            {
                 name => 'sstrs',
                 desc => 'Array of streams',
                 type => 'array'
            }

        ],
        'return' => {
            desc => 'Returns 1 if successful, event if failed',
            type => 'mixed'
        }
    }
);

sub sstr_alter {
    my( $self, $conn, $auth, $sstrs ) = @_;
    return 1 unless ref $sstrs;
    my( $reqr, $evt ) = $U->checkses($auth);
    return $evt if $evt;
    my $editor = new_editor(requestor => $reqr, xact => 1);
    my $override = $self->api_name =~ /override/;

    my %found_sdist_ids;
    for my $sstr (@$sstrs) {
        if (!exists($found_sdist_ids{$sstr->distribution})) {
            my $sdist = $editor->retrieve_serial_distribution($sstr->distribution) or return $editor->die_event;
            return $editor->die_event unless
                $editor->allowed("ADMIN_SERIAL_STREAM", $sdist->holding_lib);
            $found_sdist_ids{$sstr->distribution} = 1;
        }

        if( $sstr->isdeleted ) {
            $evt = _delete_sstr( $editor, $override, $sstr);
        } elsif( $sstr->isnew ) {
            $evt = _create_sstr( $editor, $sstr );
        } else {
            $evt = _update_sstr( $editor, $override, $sstr );
        }
    }

    if( $evt ) {
        $logger->info("stream-alter failed with event: ".OpenSRF::Utils::JSON->perl2JSON($evt));
        $editor->rollback;
        return $evt;
    }
    $logger->debug("stream-alter: done updating stream batch");
    $editor->commit;
    $logger->info("stream-alter successfully updated ".scalar(@$sstrs)." streams");
    return 1;
}

sub _delete_sstr {
    my ($editor, $override, $sstr) = @_;
    $logger->info("stream-alter: delete stream ".OpenSRF::Utils::JSON->perl2JSON($sstr));
    my $sitems = $editor->search_serial_item(
            { stream => $sstr->id }, { limit => 1 } ); #TODO: 'deleted' support?
    return OpenILS::Event->new(
            'SERIAL_STREAM_HAS_ITEMS', payload => $sstr->id ) if (@$sitems);

    return $editor->event unless $editor->delete_serial_stream($sstr);
    return 0;
}

sub _create_sstr {
    my ($editor, $sstr) = @_;

    $logger->info("stream-alter: new stream ".OpenSRF::Utils::JSON->perl2JSON($sstr));
    return $editor->event unless $editor->create_serial_stream($sstr);
    return 0;
}

sub _update_sstr {
    my ($editor, $override, $sstr) = @_;

    $logger->info("stream-alter: retrieving stream ".$sstr->id);
    my $orig_sstr = $editor->retrieve_serial_stream($sstr->id);

    $logger->info("stream-alter: original stream ".OpenSRF::Utils::JSON->perl2JSON($orig_sstr));
    $logger->info("stream-alter: updated stream ".OpenSRF::Utils::JSON->perl2JSON($sstr));
    return $editor->event unless $editor->update_serial_stream($sstr);
    return 0;
}

__PACKAGE__->register_method(
    method  => "serial_stream_retrieve_batch",
    authoritative => 1,
    api_name    => "open-ils.serial.stream.batch.retrieve"
);

sub serial_stream_retrieve_batch {
    my( $self, $client, $ids ) = @_;
    $logger->info("Fetching streams @$ids");
    return $U->cstorereq(
        "open-ils.cstore.direct.serial.stream.search.atomic",
        { id => $ids }
    );
}


##########################################################################
# summary methods
#
__PACKAGE__->register_method(
    method    => 'sum_alter',
    api_name  => 'open-ils.serial.basic_summary.batch.update',
    api_level => 1,
    argc      => 2,
    signature => {
        desc     => 'Receives an array of one or more summaries and updates the database as needed',
        'params' => [ {
                 name => 'authtoken',
                 desc => 'Authtoken for current user session',
                 type => 'string'
            },
            {
                 name => 'sbsums',
                 desc => 'Array of basic summaries',
                 type => 'array'
            }

        ],
        'return' => {
            desc => 'Returns 1 if successful, event if failed',
            type => 'mixed'
        }
    }
);

__PACKAGE__->register_method(
    method    => 'sum_alter',
    api_name  => 'open-ils.serial.supplement_summary.batch.update',
    api_level => 1,
    argc      => 2,
    signature => {
        desc     => 'Receives an array of one or more summaries and updates the database as needed',
        'params' => [ {
                 name => 'authtoken',
                 desc => 'Authtoken for current user session',
                 type => 'string'
            },
            {
                 name => 'sbsums',
                 desc => 'Array of supplement summaries',
                 type => 'array'
            }

        ],
        'return' => {
            desc => 'Returns 1 if successful, event if failed',
            type => 'mixed'
        }
    }
);

__PACKAGE__->register_method(
    method    => 'sum_alter',
    api_name  => 'open-ils.serial.index_summary.batch.update',
    api_level => 1,
    argc      => 2,
    signature => {
        desc     => 'Receives an array of one or more summaries and updates the database as needed',
        'params' => [ {
                 name => 'authtoken',
                 desc => 'Authtoken for current user session',
                 type => 'string'
            },
            {
                 name => 'sbsums',
                 desc => 'Array of index summaries',
                 type => 'array'
            }

        ],
        'return' => {
            desc => 'Returns 1 if successful, event if failed',
            type => 'mixed'
        }
    }
);

sub sum_alter {
    my( $self, $conn, $auth, $sums ) = @_;
    return 1 unless ref $sums;

    $self->api_name =~ /serial\.(\w*)_summary/;
    my $type = $1;

    my( $reqr, $evt ) = $U->checkses($auth);
    return $evt if $evt;
    my $editor = new_editor(requestor => $reqr, xact => 1);
    my $override = $self->api_name =~ /override/;

    my %found_sdist_ids;
    for my $sum (@$sums) {
        if (!exists($found_sdist_ids{$sum->distribution})) {
            my $sdist = $editor->retrieve_serial_distribution($sum->distribution) or return $editor->die_event;
            return $editor->die_event unless
                $editor->allowed("ADMIN_SERIAL_DISTRIBUTION", $sdist->holding_lib);
            $found_sdist_ids{$sum->distribution} = 1;
        }

        # XXX: (for now, at least) summaries should be created/deleted by the distribution functions
        if( $sum->isdeleted ) {
            $evt = OpenILS::Event->new('SERIAL_SUMMARIES_NOT_INDEPENDENT');
        } elsif( $sum->isnew ) {
            $evt = OpenILS::Event->new('SERIAL_SUMMARIES_NOT_INDEPENDENT');
        } else {
            $evt = _update_sum( $editor, $override, $sum, $type );
        }
    }

    if( $evt ) {
        $logger->info("${type}_summary-alter failed with event: ".OpenSRF::Utils::JSON->perl2JSON($evt));
        $editor->rollback;
        return $evt;
    }
    $logger->debug("${type}_summary-alter: done updating ${type}_summary batch");
    $editor->commit;
    $logger->info("${type}_summary-alter successfully updated ".scalar(@$sums)." ${type}_summaries");
    return 1;
}

sub _update_sum {
    my ($editor, $override, $sum, $type) = @_;

    $logger->info("${type}_summary-alter: retrieving ${type}_summary ".$sum->id);
    my $retrieve_method = "retrieve_serial_${type}_summary";
    my $orig_sum = $editor->$retrieve_method($sum->id);

    $logger->info("${type}_summary-alter: original ${type}_summary ".OpenSRF::Utils::JSON->perl2JSON($orig_sum));
    $logger->info("${type}_summary-alter: updated ${type}_summary ".OpenSRF::Utils::JSON->perl2JSON($sum));
    my $update_method = "update_serial_${type}_summary";
    return $editor->event unless $editor->$update_method($sum);
    return 0;
}

__PACKAGE__->register_method(
    method  => "serial_summary_retrieve_batch",
    authoritative => 1,
    api_name    => "open-ils.serial.basic_summary.batch.retrieve"
);

__PACKAGE__->register_method(
    method  => "serial_summary_retrieve_batch",
    authoritative => 1,
    api_name    => "open-ils.serial.supplement_summary.batch.retrieve"
);

__PACKAGE__->register_method(
    method  => "serial_summary_retrieve_batch",
    authoritative => 1,
    api_name    => "open-ils.serial.index_summary.batch.retrieve"
);

sub serial_summary_retrieve_batch {
    my( $self, $client, $ids ) = @_;

    $self->api_name =~ /serial\.(\w*)_summary/;
    my $type = $1;

    $logger->info("Fetching ${type}_summaries @$ids");
    return $U->cstorereq(
        "open-ils.cstore.direct.serial.".$type."_summary.search.atomic",
        { id => $ids }
    );
}


##########################################################################
# other methods
#
__PACKAGE__->register_method(
    "method" => "bre_by_identifier",
    "api_name" => "open-ils.serial.biblio.record_entry.by_identifier",
    "stream" => 1,
    "signature" => {
        "desc" => "Find instances of biblio.record_entry given a search token" .
            " that could be a value for any identifier defined in " .
            "config.metabib_field",
        "params" => [
            {"desc" => "Search token", "type" => "string"},
            {"desc" => "Options: require_subscriptions, add_mvr, is_actual_id" .
                ", id_list (all boolean)", "type" => "object"}
        ],
        "return" => {
            "desc" => "Any matching BREs, or if the add_mvr option is true, " .
                "objects with a 'bre' key/value pair, and an 'mvr' " .
                "key-value pair.  BREs have subscriptions fleshed on.",
            "type" => "object"
        }
    }
);

sub bre_by_identifier {
    my ($self, $client, $term, $options) = @_;

    return new OpenILS::Event("BAD_PARAMS") unless $term;

    $options ||= {};
    my $e = new_editor();

    my @ids;

    if ($options->{"is_actual_id"}) {
        @ids = ($term);
    } else {
        my $cmf =
            $e->search_config_metabib_field({"field_class" => "identifier"})
                or return $e->die_event;

        my @identifiers = map { $_->name } @$cmf;
        my $query = join(" || ", map { "id|$_: $term" } @identifiers);

        my $search = create OpenSRF::AppSession("open-ils.search");
        my $search_result = $search->request(
            "open-ils.search.biblio.multiclass.query.staff", {}, $query
        )->gather(1);
        $search->disconnect;

        # Un-nest results. They tend to look like [[1],[2],[3]] for some reason.
        @ids = map { @{$_}[0] } @{$search_result->{"ids"}};

        unless (@ids) {
            $e->disconnect;
            return undef;
        }

        if ($options->{"id_list"}) {
            $e->disconnect;
            $client->respond($_) foreach (@ids);
            return undef;
        }
    }

    my $bre = $e->search_biblio_record_entry([
        {"id" => \@ids}, {
            "flesh" => 2, "flesh_fields" => {
                "bre" => ["subscriptions"],
                "ssub" => ["owning_lib"]
            }
        }
    ]) or return $e->die_event;

    if (@$bre && $options->{"require_subscriptions"}) {
        $bre = [ grep { @{$_->subscriptions} } @$bre ];
    }

    $e->disconnect;

    if (@$bre) { # re-evaluate after possible grep
        if ($options->{"add_mvr"}) {
            $client->respond(
                {"bre" => $_, "mvr" => _get_mvr($_->id)}
            ) foreach (@$bre);
        } else {
            $client->respond($_) foreach (@$bre);
        }
    }

    undef;
}

__PACKAGE__->register_method(
    "method" => "get_items_by",
    "api_name" => "open-ils.serial.items.receivable.by_subscription",
    "stream" => 1,
    "signature" => {
        "desc" => "Return all receivable items under a given subscription",
        "params" => [
            {"desc" => "Authtoken", "type" => "string"},
            {"desc" => "Subscription ID", "type" => "number"},
        ],
        "return" => {
            "desc" => "All receivable items under a given subscription",
            "type" => "object", "class" => "sitem"
        }
    }
);

__PACKAGE__->register_method(
    "method" => "get_items_by",
    "api_name" => "open-ils.serial.items.receivable.by_issuance",
    "stream" => 1,
    "signature" => {
        "desc" => "Return all receivable items under a given issuance",
        "params" => [
            {"desc" => "Authtoken", "type" => "string"},
            {"desc" => "Issuance ID", "type" => "number"},
        ],
        "return" => {
            "desc" => "All receivable items under a given issuance",
            "type" => "object", "class" => "sitem"
        }
    }
);

__PACKAGE__->register_method(
    "method" => "get_items_by",
    "api_name" => "open-ils.serial.items.by_issuance",
    "stream" => 1,
    "signature" => {
        "desc" => "Return all items under a given issuance",
        "params" => [
            {"desc" => "Authtoken", "type" => "string"},
            {"desc" => "Issuance ID", "type" => "number"},
        ],
        "return" => {
            "desc" => "All items under a given issuance",
            "type" => "object", "class" => "sitem"
        }
    }
);

sub get_items_by {
    my ($self, $client, $auth, $term, $opts)  = @_;

    # Not to be used in the json_query, but after limiting by perm check.
    $opts = {} unless ref $opts eq "HASH";
    $opts->{"limit"} ||= 10000;    # some existing users may want all results
    $opts->{"offset"} ||= 0;
    $opts->{"limit"} = int($opts->{"limit"});
    $opts->{"offset"} = int($opts->{"offset"});

    my $e = new_editor("authtoken" => $auth);
    return $e->die_event unless $e->checkauth;

    my $by = ($self->api_name =~ /by_(\w+)$/)[0];
    my $receivable = ($self->api_name =~ /receivable/);

    my %where = (
        "issuance" => {"issuance" => $term},
        "subscription" => {"+siss" => {"subscription" => $term}}
    );

    my $item_rows = $e->json_query(
        {
            "select" => {"sitem" => ["id"], "sdist" => ["holding_lib"]},
            "from" => {
                "sitem" => {
                    "siss" => {},
                    "sstr" => {"join" => {"sdist" => {}}}
                }
            },
            "where" => {
                %{$where{$by}}, $receivable ? ("date_received" => undef) : ()
            },
            "order_by" => {"sitem" => ["id"]}
        }
    ) or return $e->die_event;

    return undef unless @$item_rows;

    my $skipped = 0;
    my $returned = 0;
    foreach (@$item_rows) {
        last if $returned >= $opts->{"limit"};
        next unless $e->allowed("RECEIVE_SERIAL", $_->{"holding_lib"});
        if ($skipped < $opts->{"offset"}) {
            $skipped++;
            next;
        }

        $client->respond(
            $e->retrieve_serial_item([
                $_->{"id"}, {
                    "flesh" => 3,
                    "flesh_fields" => {
                        "sitem" => [qw/stream issuance notes unit creator editor/],
                        "siss" => [qw/subscription/],
                        "sstr" => [qw/distribution routing_list_users/],
                        "sdist" => [qw/holding_lib notes receive_unit_template/],
                        "ssub" => [qw/notes/]
                    }
                }
            ])
        );
        $returned++;
    }

    $e->disconnect;
    undef;
}

__PACKAGE__->register_method(
    "method" => "get_receivable_issuances",
    "api_name" => "open-ils.serial.issuances.receivable",
    "stream" => 1,
    "signature" => {
        "desc" => "Return all issuances with receivable items given " .
            "a subscription ID",
        "params" => [
            {"desc" => "Authtoken", "type" => "string"},
            {"desc" => "Subscription ID", "type" => "number"},
        ],
        "return" => {
            "desc" => "All issuances with receivable items " .
                "(but not the items themselves)", "type" => "object"
        }
    }
);

sub get_receivable_issuances {
    my ($self, $client, $auth, $sub_id) = @_;

    my $e = new_editor("authtoken" => $auth);
    return $e->die_event unless $e->checkauth;

    # XXX permissions

    my $issuance_ids = $e->json_query({
        "select" => {
            "siss" => [
                {"transform" => "distinct", "column" => "id"},
                "date_published"
            ]
        },
        "from" => {"siss" => "sitem"},
        "where" => {
            "subscription" => $sub_id,
            "+sitem" => {"date_received" => undef}
        },
        "order_by" => {
            "siss" => {"date_published" => {"direction" => "asc"}}
        }

    }) or return $e->die_event;

    $client->respond($e->retrieve_serial_issuance($_->{"id"}))
        foreach (@$issuance_ids);

    $e->disconnect;
    undef;
}


__PACKAGE__->register_method(
    "method" => "get_routing_list_users",
    "api_name" => "open-ils.serial.routing_list_users.fleshed_and_ordered",
    "stream" => 1,
    "signature" => {
        "desc" => "Return all routing list users with reader fleshed " .
            "(with card and home_ou) for a given stream ID, sorted by pos",
        "params" => [
            {"desc" => "Authtoken", "type" => "string"},
            {"desc" => "Stream ID (int or array of ints)", "type" => "mixed"},
        ],
        "return" => {
            "desc" => "Stream of routing list users", "type" => "object",
                "class" => "srlu"
        }
    }
);

sub get_routing_list_users {
    my ($self, $client, $auth, $stream_id) = @_;

    my $e = new_editor("authtoken" => $auth);
    return $e->die_event unless $e->checkauth;

    my $users = $e->search_serial_routing_list_user([
        {"stream" => $stream_id}, {
            "order_by" => {"srlu" => "pos"},
            "flesh" => 2,
            "flesh_fields" => {
                "srlu" => [qw/reader stream/],
                "au" => [qw/card home_ou mailing_address billing_address/],
                "sstr" => ["distribution"]
            }
        }
    ]) or return $e->die_event;

    return undef unless @$users;

    # The ADMIN_SERIAL_STREAM permission is used simply to avoid the
    # need for any new permission.  The context OU will be the same
    # for every result of the above query, so we need only check once.
    return $e->die_event unless $e->allowed(
        "ADMIN_SERIAL_STREAM", $users->[0]->stream->distribution->holding_lib
    );

    $e->disconnect;

    my @users = map { $_->stream($_->stream->id); $_ } @$users;
    @users = sort { $a->stream cmp $b->stream } @users if
        ref $stream_id eq "ARRAY";

    $client->respond($_) for @users;

    undef;
}


__PACKAGE__->register_method(
    "method" => "replace_routing_list_users",
    "api_name" => "open-ils.serial.routing_list_users.replace",
    "signature" => {
        "desc" => "Replace all routing list users on the specified streams " .
            "with those in the list argument",
        "params" => [
            {"desc" => "Authtoken", "type" => "string"},
            {"desc" => "List of srlu objects", "type" => "array"},
        ],
        "return" => {
            "desc" => "event on failure, undef on success"
        }
    }
);

sub replace_routing_list_users {
    my ($self, $client, $auth, $users) = @_;

    return undef unless ref $users eq "ARRAY";

    if (grep { ref $_ ne "Fieldmapper::serial::routing_list_user" } @$users) {
        return new OpenILS::Event("BAD_PARAMS", "note" => "Only srlu objects");
    }

    my $e = new_editor("authtoken" => $auth, "xact" => 1);
    return $e->die_event unless $e->checkauth;

    my %streams_ok = ();
    my $pos = 0;

    foreach my $user (@$users) {
        unless (exists $streams_ok{$user->stream}) {
            my $stream = $e->retrieve_serial_stream([
                $user->stream, {
                    "flesh" => 1,
                    "flesh_fields" => {"sstr" => ["distribution"]}
                }
            ]) or return $e->die_event;
            $e->allowed(
                "ADMIN_SERIAL_STREAM", $stream->distribution->holding_lib
            ) or return $e->die_event;

            my $to_delete = $e->search_serial_routing_list_user(
                {"stream" => $user->stream}
            ) or return $e->die_event;

            $logger->info(
                "Deleting srlu: [" .
                join(", ", map { $_->id; } @$to_delete) .
                "]"
            );

            foreach (@$to_delete) {
                $e->delete_serial_routing_list_user($_) or
                    return $e->die_event;
            }

            $streams_ok{$user->stream} = 1;
        }

        next if $user->isdeleted;

        $user->clear_id;
        $user->pos($pos++);
        $e->create_serial_routing_list_user($user) or return $e->die_event;
    }

    $e->commit or return $e->die_event;
    undef;
}

__PACKAGE__->register_method(
    "method" => "get_records_with_marc_85x",
    "api_name"=>"open-ils.serial.caption_and_pattern.find_legacy_by_bib_record",
    "stream" => 1,
    "signature" => {
        "desc" => "Return the specified BRE itself and/or any related SRE ".
            "whenever they have 853-855 tags",
        "params" => [
            {"desc" => "Authtoken", "type" => "string"},
            {"desc" => "bib record ID", "type" => "number"},
        ],
        "return" => {
            "desc" => "objects, either bre or sre", "type" => "object"
        }
    }
);

sub get_records_with_marc_85x { # specifically, 853-855
    my ($self, $client, $auth, $bre_id) = @_;

    my $e = new_editor("authtoken" => $auth);
    return $e->die_event unless $e->checkauth;

    my $bre = $e->search_biblio_record_entry([
        {"id" => $bre_id, "deleted" => "f"}, {
            "flesh" => 1,
            "flesh_fields" => {"bre" => [qw/creator editor owner/]}
        }
    ]) or return $e->die_event;

    return undef unless @$bre;
    $bre = $bre->[0];

    my $record = MARC::Record->new_from_xml($bre->marc);
    $client->respond($bre) if $record->field("85[3-5]");
    # XXX Is passing a regex to ->field() an abuse of MARC::Record ?

    my $sres = $e->search_serial_record_entry([
        {"record" => $bre_id, "deleted" => "f"}, {
            "flesh" => 1,
            "flesh_fields" => {"sre" => [qw/creator editor owning_lib/]}
        }
    ]) or return $e->die_event;

    $e->disconnect;

    foreach my $sre (@$sres) {
        $client->respond($sre) if
            MARC::Record->new_from_xml($sre->marc)->field("85[3-5]");
    }

    undef;
}

__PACKAGE__->register_method(
    "method" => "create_scaps_from_marcxml",
    "api_name" => "open-ils.serial.caption_and_pattern.create_from_records",
    "stream" => 1,
    "signature" => {
        "desc" => "Create caption and pattern objects from 853-855 tags " .
            "in MARCXML documents",
        "params" => [
            {"desc" => "Authtoken", "type" => "string"},
            {"desc" => "Subscription ID", "type" => "number"},
            {"desc" => "list of MARCXML documents as strings",
                "type" => "array"},
        ],
        "return" => {
            "desc" => "Newly created caption and pattern objects",
            "type" => "object", "class" => "scap"
        }
    }
);

sub create_scaps_from_marcxml {
    my ($self, $client, $auth, $sub_id, $docs) = @_;

    return undef unless ref $docs eq "ARRAY";

    my $e = new_editor("authtoken" => $auth, "xact" => 1);
    return $e->die_event unless $e->checkauth;

    # Retrieve the subscription just for perm checking (whether we can create
    # scaps at the owning lib).
    my $sub = $e->retrieve_serial_subscription($sub_id) or return $e->die_event;
    return $e->die_event unless
        $e->allowed("ADMIN_SERIAL_CAPTION_PATTERN", $sub->owning_lib);

    foreach my $record (map { MARC::Record->new_from_xml($_) } @$docs) {
        foreach my $field ($record->field("85[3-5]")) {
            my $scap = new Fieldmapper::serial::caption_and_pattern;
            $scap->subscription($sub_id);
            $scap->type($MFHD_NAMES_BY_TAG{$field->tag});
            $scap->pattern_code(
                OpenSRF::Utils::JSON->perl2JSON(
                    [ $field->indicator(1), $field->indicator(2),
                        map { @$_ } $field->subfields ] # flattens nested array
                )
            );
            $e->create_serial_caption_and_pattern($scap) or
                return $e->die_event;
            $client->respond($e->data);
        }
    }

    $e->commit or return $e->die_event;
    undef;
}

# All these _clone_foo() functions could possibly have been consolidated into
# one clever function, but it's faster to get things working this way.
sub _clone_subscription {
    my ($sub, $bib_id, $e) = @_;

    # clone sub itself
    my $new_sub = $sub->clone;
    $new_sub->record_entry(int $bib_id) if $bib_id;
    $new_sub->clear_id;
    $new_sub->clear_distributions;
    $new_sub->clear_notes;
    $new_sub->clear_scaps;

    $e->create_serial_subscription($new_sub) or return $e->die_event;

    my $new_sub_id = $e->data->id;
    # clone dists
    foreach my $dist (@{$sub->distributions}) {
        my $r = _clone_distribution($dist, $new_sub_id, $e);
        return $r if $U->event_code($r);
    }

    # clone sub notes
    foreach my $note (@{$sub->notes}) {
        my $r = _clone_subscription_note($note, $new_sub_id, $e);
        return $r if $U->event_code($r);
    }

    # clone scaps
    foreach my $scap (@{$sub->scaps}) {
        my $r = _clone_caption_and_pattern($scap, $new_sub_id, $e);
        return $r if $U->event_code($r);
    }

    return $new_sub_id;
}

sub _clone_distribution {
    my ($dist, $sub_id, $e) = @_;

    my $new_dist = $dist->clone;
    $new_dist->clear_id;
    $new_dist->clear_notes;
    $new_dist->clear_streams;
    $new_dist->subscription($sub_id);

    $e->create_serial_distribution($new_dist) or return $e->die_event;
    my $new_dist_id = $e->data->id;

    # clone streams
    foreach my $stream (@{$dist->streams}) {
        my $r = _clone_stream($stream, $new_dist_id, $e);
        return $r if $U->event_code($r);
    }

    # clone distribution notes
    foreach my $note (@{$dist->notes}) {
        my $r = _clone_distribution_note($note, $new_dist_id, $e);
        return $r if $U->event_code($r);
    }

    return $new_dist_id;
}

sub _clone_subscription_note {
    my ($note, $sub_id, $e) = @_;

    my $new_note = $note->clone;
    $new_note->clear_id;
    $new_note->creator($e->requestor->id);
    $new_note->create_date("now");
    $new_note->subscription($sub_id);

    $e->create_serial_subscription_note($new_note) or return $e->die_event;
    return $e->data->id;
}

sub _clone_caption_and_pattern {
    my ($scap, $sub_id, $e) = @_;

    my $new_scap = $scap->clone;
    $new_scap->clear_id;
    $new_scap->subscription($sub_id);

    $e->create_serial_caption_and_pattern($new_scap) or return $e->die_event;
    return $e->data->id;
}

sub _clone_distribution_note {
    my ($note, $dist_id, $e) = @_;

    my $new_note = $note->clone;
    $new_note->clear_id;
    $new_note->creator($e->requestor->id);
    $new_note->create_date("now");
    $new_note->distribution($dist_id);

    $e->create_serial_distribution_note($new_note) or return $e->die_event;
    return $e->data->id;
}

sub _clone_stream {
    my ($stream, $dist_id, $e) = @_;

    my $new_stream = $stream->clone;
    $new_stream->clear_id;
    $new_stream->clear_routing_list_users;
    $new_stream->distribution($dist_id);

    $e->create_serial_stream($new_stream) or return $e->die_event;
    my $new_stream_id = $e->data->id;

    # clone routing list users
    foreach my $user (@{$stream->routing_list_users}) {
        my $r = _clone_routing_list_user($user, $new_stream_id, $e);
        return $r if $U->event_code($r);
    }

    return $new_stream_id;
}

sub _clone_routing_list_user {
    my ($user, $stream_id, $e) = @_;

    my $new_user = $user->clone;
    $new_user->clear_id;
    $new_user->stream($stream_id);

    $e->create_serial_routing_list_user($new_user) or return $e->die_event;
    return $e->data->id;
}

__PACKAGE__->register_method(
    "method" => "clone_subscription",
    "api_name" => "open-ils.serial.subscription.clone",
    "signature" => {
        "desc" => q{Clone a subscription, including its attending distributions,
            streams, captions and patterns, routing list users, distribution
            notes and subscription notes. Do not include holdings-specific
            things, like issuances, items, units, summaries. Attach the
            clone either to the same bib record as the original, or to one
            specified by ID.},
        "params" => [
            {"desc" => "Authtoken", "type" => "string"},
            {"desc" => "Subscription ID", "type" => "number"},
            {"desc" => "Bib Record ID (optional)", "type" => "number"}
        ],
        "return" => {
            "desc" => "ID of the new subscription", "type" => "number"
        }
    }
);

sub clone_subscription {
    my ($self, $client, $auth, $sub_id, $bib_id) = @_;

    my $e = new_editor("authtoken" => $auth, "xact" => 1);
    return $e->die_event unless $e->checkauth;

    my $sub = $e->retrieve_serial_subscription([
        int $sub_id, {
            "flesh" => 3,
            "flesh_fields" => {
                "ssub" => [qw/distributions notes scaps/],
                "sdist" => [qw/streams notes/],
                "sstr" => ["routing_list_users"]
            }
        }
    ]) or return $e->die_event;

    # ADMIN_SERIAL_SUBSCRIPTION will have to be good enough as a
    # catch-all permisison for this operation.
    return $e->die_event unless
        $e->allowed("ADMIN_SERIAL_SUBSCRIPTION", $sub->owning_lib);

    my $result = _clone_subscription($sub, $bib_id, $e);

    return $e->die_event($result) if $U->event_code($result);

    $e->commit or return $e->die_event;
    return $result;
}

__PACKAGE__->register_method(
    "method" => "summary_test",
    "api_name" => "open-ils.serial.summary_test",
    "stream" => 1,
    "api_level" => 1,
    "argc" => 3
);

# This crummy little test method allows quicker reproduction of certain
# failures (e.g. at item receive time) of the holdings summarization code.
# Pass it an authtoken, an array of issuance IDs, and a single sdist ID
sub summary_test {
    my ($self, $conn, $authtoken, $iss_id_list, $sdist_id) = @_;

    my $e = new_editor(authtoken => $authtoken, xact => 1);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed("RECEIVE_SERIAL");

    my @issuances;
    foreach my $id (@$iss_id_list) {
        my $iss = $e->retrieve_serial_issuance($id) or return $e->die_event;
        push @issuances, $iss;
    }

    my $dist = $e->retrieve_serial_distribution($sdist_id) or return $e->die_event;

    $conn->respond(_summarize_contents($e, \@issuances, $dist));
    $e->rollback;
    return;
}

__PACKAGE__->register_method(
    "method" => "fetch_pattern_templates",
    "api_name" => "open-ils.serial.pattern_template.retrieve.at",
    "stream" => 1,
    "signature" => {
        "desc" => q{Return the set of pattern templates that are
            visible to the specified library.},
        "params" => [
            {"desc" => "Authtoken", "type" => "string"},
            {"desc" => "OU ID", "type" => "number"},
        ],
        return => {
            desc => "stream of pattern templates",
            type => "object", class => "spt"
        }
    }
);

sub fetch_pattern_templates {
    my ($self, $client, $auth, $org_unit)  = @_;

    my $e = new_editor("authtoken" => $auth);
    return $e->die_event unless $e->checkauth;

    my $patterns = $e->json_query({
        from => [ 'serial.pattern_templates_visible_to' => $org_unit ]
    });
$logger->info(Dumper($patterns)); use Data::Dumper;

    $client->respond($e->retrieve_serial_pattern_template($_->{id}))
        foreach (@$patterns);

    $e->disconnect;
    return undef;
}

1;
