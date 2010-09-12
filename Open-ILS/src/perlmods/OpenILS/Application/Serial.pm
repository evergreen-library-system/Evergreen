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
use OpenSRF::Utils qw/:datetime/;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::MFHD;
use MARC::File::XML (BinaryEncoding => 'utf8');
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

# helper method for conforming dates to ISO8601
sub _cleanse_dates {
    my $item = shift;
    my $fields = shift;

    foreach my $field (@$fields) {
        $item->$field(OpenSRF::Utils::clense_ISO8601($item->$field)) if $item->$field;
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

# TODO: permission check
#        return $editor->event unless
#            $editor->allowed('UPDATE_COPY', $class->copy_perm_org($vol, $copy));

    for my $item (@$items) {

        my $itemid = $item->id;
        $item->editor($editor->requestor->id);
        $item->edit_date('now');

        if( $item->isdeleted ) {
            $evt = _delete_sitem( $editor, $override, $item);
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

    if( $evt ) {
        $logger->info("fleshed item-alter failed with event: ".OpenSRF::Utils::JSON->perl2JSON($evt));
        $editor->rollback;
        return $evt;
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
          flesh_fields => {sitem => [ qw/issuance creator editor stream unit notes/ ], sstr => ["distribution"], sunit => ["call_number"], siss => [qw/creator editor subscription/]}
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
    my $editor = new_editor(requestor => $reqr, xact => 1);
    my $override = $self->api_name =~ /override/;

# TODO: permission support
#        return $editor->event unless
#            $editor->allowed('UPDATE_COPY', $class->copy_perm_org($vol, $copy));

    for my $issuance (@$issuances) {
        my $issuanceid = $issuance->id;
        $issuance->editor($editor->requestor->id);
        $issuance->edit_date('now');

        if( $issuance->isdeleted ) {
            $evt = _delete_siss( $editor, $override, $issuance);
        } elsif( $issuance->isnew ) {
            _cleanse_dates($issuance, ['date_published']);
            $evt = _create_siss( $editor, $issuance );
        } else {
            _cleanse_dates($issuance, ['date_published']);
            $evt = _update_siss( $editor, $override, $issuance );
        }
    }

    if( $evt ) {
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
    my $self = shift;
    my $client = shift;
    my $bib = shift;

    my $args = shift || {};
    $$args{order} ||= 'asc';

    my $e = new_editor();
    my $issuances = $e->json_query({
        select  => { 'siss' => [ 'id' ] },
        from    => {
            siss => {
                ssub => {
                    field  => 'id',
                    fkey   => 'subscription'
                },
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
        },
        where => {
            $$args{type} ? ( 'holding_type' => $$args{type} ) : (),
            '+ssub'  => { record_entry => $bib },
            '+sitem' => {
                # XXX should we also take specific item statuses into account?
                date_received => { '!=' => undef },
                $$args{status} ? ( 'status' => $$args{status} ) : ()
            },
            $$args{ou} ? ( '+sdist' => {
                holding_lib => {
                    'in' => {
                        from => [
                            'actor.org_unit_descendants',
                            defined($$args{depth}) ? ( $$args{ou}, $$args{depth} ) :  ( $$args{ou} )
                        ]
                    }
                }
            }) : ()
        },
        $$args{limit}  ? ( limit  => $$args{limit}  ) : (),
        $$args{offset} ? ( offset => $$args{offset} ) : (),
        order_by => [{ class => 'siss', field => 'date_published', direction => $$args{order} }],
        distinct => 1
    });

    $client->respond($e->retrieve_serial_issuance($_->{id})) for @$issuances;
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
    order  := date_published sort direction, either "asc" (chronological, default) or "desc" (reverse chronological)
    limit  := Number of issuances to return.  Useful for paging results, or finding the oldest or newest
    offest := Number of issuance to skip before returning results.  Useful for paging.
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

# TODO: permission support
#        return $editor->event unless
#            $editor->allowed('UPDATE_COPY', $class->copy_perm_org($vol, $copy));

    for my $sunit (@$sunits) {
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

    $logger->info("sunit-alter: new Unit ".OpenSRF::Utils::JSON->perl2JSON($sunit));
    return $editor->event unless $editor->create_serial_unit($sunit);
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
	method	=> "retrieve_unit_list",
    authoritative => 1,
	api_name	=> "open-ils.serial.unit_list.retrieve"
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

    my $editor = OpenILS::Utils::CStoreEditor->new();
    my $ssub_id = $args->{ssub_id};
    my $mfhd = MFHD->new(MARC::Record->new());

    my $ssub = $editor->retrieve_serial_subscription([$ssub_id]);
    my $scaps = $editor->search_serial_caption_and_pattern({ subscription => $ssub_id, active => 't'});
    my $sdists = $editor->search_serial_distribution( [{ subscription => $ssub->id }, {  flesh => 1,
              flesh_fields => {sdist => [ qw/ streams / ]}, limit => 1 }] ); #TODO: 'deleted' support?

    my @predictions;
    my $link_id = 1;
    foreach my $scap (@$scaps) {
        my $caption_field = _revive_caption($scap);
        $caption_field->update('8' => $link_id);
        $mfhd->append_fields($caption_field);
        my $options = {
                'caption' => $caption_field,
                'scap_id' => $scap->id,
                'num_to_predict' => $args->{num_to_predict},
                'end_date' => defined $args->{end_date} ?
                    $_strp_date->parse_datetime($args->{end_date}) : undef
                };
        if ($args->{base_issuance}) { # predict from a given issuance
            $options->{predict_from} = _revive_holding($args->{base_issuance}->holding_code, $caption_field, 1); # fresh MFHD Record, so we simply default to 1 for seqno
        } else { # default to predicting from last published
            my $last_published = $editor->search_serial_issuance([
                    {'caption_and_pattern' => $scap->id,
                    'subscription' => $ssub_id},
                {limit => 1, order_by => { siss => "date_published DESC" }}]
                );
            if ($last_published->[0]) {
                my $last_siss = $last_published->[0];
                $options->{predict_from} = _revive_holding($last_siss->holding_code, $caption_field, 1);
            } else {
                #TODO: throw event (can't predict from nothing!)
            }
        }
        push( @predictions, _generate_issuance_values($mfhd, $options) );
        $link_id++;
    }

    my @issuances;
    foreach my $prediction (@predictions) {
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

    fleshed_issuance_alter($self, $conn, $authtoken, \@issuances); # FIXME: catch events

    my @items;
    for (my $i = 0; $i < @issuances; $i++) {
        my $date_expected = $predictions[$i]->{date_published}->add(seconds => interval_to_seconds($ssub->expected_date_offset))->strftime('%F');
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
# last_rec_date : the date of the last received issue, to be used as an offset
#                 for predicting future issues
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
    my $num_to_predict = $options->{num_to_predict};
    my $end_date = $options->{end_date};
    my $predict_from = $options->{predict_from};   # issuance to predict from
    #my $last_rec_date = $options->{last_rec_date};   # expected or actual

    # TODO: add support for predicting serials with no chronology by passing in
    # a last_pub_date option?


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

    my $pub_date;
    my @issuance_values;
    my @predictions = $mfhd->generate_predictions({'base_holding' => $predict_from, 'num_to_predict' => $num_to_predict, 'end_date' => $end_date});
    foreach my $prediction (@predictions) {
        $pub_date = $_strp_date->parse_datetime($prediction->chron_to_date);
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
            }
        ],
        'return' => {
            desc => 'Returns number of received items',
            type => 'int'
        }
    }
);

sub unitize_items {
    my ($self, $conn, $auth, $items) = @_;

    my( $reqr, $evt ) = $U->checkses($auth);
    return $evt if $evt;
    my $editor = new_editor(requestor => $reqr, xact => 1);
    $self->api_name =~ /serial\.(\w*)_items/;
    my $mode = $1;
    
    my %found_unit_ids;
    my %found_stream_ids;
    my %found_types;

    my %stream_ids_by_unit_id;

    my %unit_map;
    my %sdist_by_unit_id;
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
        } else {
            $item->status('Bindery');
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
        $found_types{$stream_id}->{$scap->type} = 1;

        # create unit if needed
        if ($unit_id == -1 or (!$new_unit_id and $unit_id == -2)) { # create unit per item
            my $unit;
            my $sdists = $editor->search_serial_distribution([{"+sstr" => {"id" => $stream_id}}, { "join" => {"sstr" => {}} }]);
            $unit = _build_unit($editor, $sdists->[0], $mode);
            my $evt =  _create_sunit($editor, $unit);
            return $evt if $evt;
            if ($unit_id == -2) {
                $new_unit_id = $unit->id;
                $unit_id = $new_unit_id;
            } else {
                $unit_id = $unit->id;
            }
            $item->unit($unit_id);
            
            # get unit with 'DEFAULT's and save unit and sdist for later use
            $unit = $editor->retrieve_serial_unit($unit->id);
            $unit_map{$unit_id} = $unit;
            $sdist_by_unit_id{$unit_id} = $sdists->[0];
            $sdist_by_stream_id{$stream_id} = $sdists->[0];
        } elsif ($unit_id == -2) { # create one unit for all '-2' items
            $unit_id = $new_unit_id;
            $item->unit($unit_id);
        }

        $found_unit_ids{$unit_id} = 1;
        $found_stream_ids{$stream_id} = 1;

        # save the stream_id for this unit_id
        # TODO: prevent items from different streams in same unit? (perhaps in interface)
        $stream_ids_by_unit_id{$unit_id} = $stream_id;

        my $evt = _update_sitem($editor, undef, $item);
        return $evt if $evt;
    }

    # deal with unit level labels
    foreach my $unit_id (keys %found_unit_ids) {

        # get all the needed issuances for unit
        my $issuances = $editor->search_serial_issuance([ {"+sitem" => {"unit" => $unit_id, "status" => "Received"}}, {"join" => {"sitem" => {}}, "order_by" => {"siss" => "date_published"}} ]);
        #TODO: evt on search failure

        my ($mfhd, $formatted_parts) = _summarize_contents($editor, $issuances);

        # special case for single formatted_part (may have summarized version)
        if (@$formatted_parts == 1) {
            #TODO: MFHD.pm should have a 'format_summary' method for this
        }

        # retrieve and update unit contents
        my $sunit;
        my $sdist;

        # if we just created the unit, we will already have it and the distribution stored
        if (exists $unit_map{$unit_id}) {
            $sunit = $unit_map{$unit_id};
            $sdist = $sdist_by_unit_id{$unit_id};
        } else {
            $sunit = $editor->retrieve_serial_unit($unit_id);
            $sdist = $editor->search_serial_distribution([{"+sstr" => {"id" => $stream_ids_by_unit_id{$unit_id}}}, { "join" => {"sstr" => {}} }]);
            $sdist = $sdist->[0];
        }

        $sunit->detailed_contents($sdist->unit_label_prefix . ' '
                    . join(', ', @$formatted_parts) . ' '
                    . $sdist->unit_label_suffix);

        $sunit->summary_contents($sunit->detailed_contents); #TODO: change this when real summary contents are available

        # create sort_key by left padding numbers to 6 digits
        my $sort_key = $sunit->detailed_contents;
        $sort_key =~ s/(\d+)/sprintf '%06d', $1/eg; # this may need improvement
        $sunit->sort_key($sort_key);
        
        if ($mode eq 'bind') {
            $sunit->status(2); # set to 'Bindery' status
        }

        my $evt = _update_sunit($editor, undef, $sunit);
        return $evt if $evt;
    }

    # TODO: cleanup 'dead' units (units which are now emptied of their items)

    if ($mode eq 'receive') { # the summary holdings do not change when binding
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

                my ($mfhd, $formatted_parts) = _summarize_contents($editor, $issuances);

                # retrieve and update the generated_coverage of the summary
                my $search_method = "search_serial_${type}_summary";
                my $summary = $editor->$search_method([{"distribution" => $sdist_id}]);
                $summary = $summary->[0];
                $summary->generated_coverage(join(', ', @$formatted_parts));
                my $update_method = "update_serial_${type}_summary";
                return $editor->event unless $editor->$update_method($summary);
            }
        }
    }

    $editor->commit;
    return {'num_items_received' => scalar @$items, 'new_unit_id' => $new_unit_id};
}

sub _find_or_create_call_number {
    my ($e, $lib, $cn_string, $record) = @_;

    my $existing = $e->search_asset_call_number({
        "owning_lib" => $lib,
        "label" => $cn_string,
        "record" => $record,
        "deleted" => "f"
    }) or return $e->die_event;

    if (@$existing) {
        return $existing->[0]->id;
    } else {
        return $e->die_event unless
            $e->allowed("CREATE_VOLUME", $lib);

        my $acn = new Fieldmapper::asset::call_number;

        $acn->creator($e->requestor->id);
        $acn->editor($e->requestor->id);
        $acn->record($record);
        $acn->label($cn_string);
        $acn->owning_lib($lib);

        $e->create_asset_call_number($acn) or return $e->die_event;
        return $e->data->id;
    }
}

sub _issuances_received {
    my ($e, $sitem) = @_;

    my $results = $e->json_query({
        "select" => {
            "sitem" => [
                {"transform" => "distinct", "column" => "issuance"}
            ]
        },
        "from" => {"sitem" => {"sstr" => {}, "siss" => {}}},
        "where" => {
            "+sstr" => {"distribution" => $sitem->stream->distribution->id},
            "+siss" => {"holding_type" => $sitem->issuance->holding_type},
            "+sitem" => {"date_received" => {"!=" => undef}}
        }
    }) or return $e->die_event;

    return [ map { $e->retrieve_serial_issuance($_->{"issuance"}) } @$results ];
}

# XXX _prepare_unit_label() duplicates some code from unitize_items().
# Hopefully we can unify code paths down the road.
sub _prepare_unit_label {
    my ($e, $sunit, $sdist, $issuance) = @_;

    my ($mfhd, $formatted_parts) = _summarize_contents($e, [$issuance]);

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

# XXX duplicates a block of code from unitize_items().  Once I fully understand
# what's going on and I'm sure it's working right, I'd like to have
# unitize_items() just use this, keeping the logic in one place.
sub _prepare_summaries {
    my ($e, $sitem, $issuances) = @_;

    my $dist_id = $sitem->stream->distribution->id;
    my $type = $sitem->issuance->holding_type;

    # Make sure @$issuances contains the new issuance from sitem.
    unless (grep { $_->id == $sitem->issuance->id } @$issuances) {
        push @$issuances, $sitem->issuance;
    }

    my ($mfhd, $formatted_parts) = _summarize_contents($e, $issuances);

    my $search_method = "search_serial_${type}_summary";
    my $summary = $e->$search_method([{"distribution" => $dist_id}]);

    my $cu_method = "update";

    if (@$summary) {
        $summary = $summary->[0];
    } else {
        my $class = "Fieldmapper::serial::${type}_summary";
        $summary = $class->new;
        $summary->distribution($dist_id);
        $cu_method = "create";
    }

    $summary->generated_coverage(join(", ", @$formatted_parts));
    my $method = "${cu_method}_serial_${type}_summary";
    return $e->die_event unless $e->$method($summary);
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

        # Create unit if given by user
        if (ref $item->unit) {
            # detach from the item, as we need to create separately
            my $user_unit = $item->unit;

            # get a unit based on associated template
            my $template_unit = _build_unit($e, $sdist, "receive", 1);
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
            if ($user_unit->call_number) {
                my $real_cn = _find_or_create_call_number(
                    $e, $sdist->holding_lib->id,
                    $user_unit->call_number, $record
                );

                if ($U->event_code($real_cn)) {
                    $e->rollback;
                    return $real_cn;
                } else {
                    $user_unit->call_number($real_cn);
                }
            }

            my $evt = _prepare_unit_label(
                $e, $user_unit, $sdist, $item->issuance
            );
            if ($U->event_code($evt)) {
                $e->rollback;
                return $evt;
            }

            # fetch a list of issuances with received copies already existing
            # on this distribution.
            my $issuances = _issuances_received($e, $item); #XXX optimize later
            if ($U->event_code($issuances)) {
                $e->rollback;
                return $issuances;
            }

            # create/update summary objects related to this distribution
            $evt = _prepare_summaries($e, $item, $issuances);
            if ($U->event_code($evt)) {
                $e->rollback;
                return $evt;
            }

            # set the incontrovertibles on the unit
            $user_unit->edit_date("now");
            $user_unit->create_date("now");
            $user_unit->editor($user_id);
            $user_unit->creator($user_id);

            return $e->die_event unless $e->create_serial_unit($user_unit);

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
    my $skip_call_number = shift;

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

    unless ($skip_call_number) {
        $attr = $mode . '_call_number';
        my $cn = $sdist->$attr or
            return new OpenILS::Event("SERIAL_DISTRIBUTION_HAS_NO_CALL_NUMBER");

        $unit->call_number($cn);
    }

    $unit->barcode('AUTO');
    $unit->sort_key('');
    $unit->summary_contents('');
    $unit->detailed_contents('');

    return $unit;
}


sub _summarize_contents {
    my $editor = shift;
    my $issuances = shift;

    # create MFHD record
    my $mfhd = MFHD->new(MARC::Record->new());
    my %scaps;
    my %scap_fields;
    my @scap_fields_ordered;
    my $seqno = 1;
    my $link_id = 1;
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
            $scap_fields{$scap_id} = $scap_field;
            push(@scap_fields_ordered, $scap_field);
            $scap_field->update('8' => $link_id);
            $mfhd->append_fields($scap_field);
            $link_id++;
        } else {
            $scap = $scaps{$scap_id};
            $scap_field = $scap_fields{$scap_id};
        }

        $mfhd->append_fields(_revive_holding($issuance->holding_code, $scap_field, $seqno));
        $seqno++;
    }

    my @formatted_parts;
    foreach my $scap_field (@scap_fields_ordered) { #TODO: use generic MFHD "summarize" method, once available
       my @updated_holdings = $mfhd->get_compressed_holdings($scap_field);
       foreach my $holding (@updated_holdings) {
           push(@formatted_parts, $holding->format);
       }
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
    my( $r, $evt);

    if( $$args{pub} ) {
        return $U->cstorereq(
            'open-ils.cstore.direct.serial.'.$type.'_note.search.atomic',
            { $type => $id, pub => 't' } );
    } else {
        # FIXME: restore perm check
        # ( $r, $evt ) = $U->checksesperm($authtoken, 'VIEW_COPY_NOTES');
        # return $evt if $evt;
        return $U->cstorereq(
            'open-ils.cstore.direct.serial.'.$type.'_note.search.atomic', {$type => $id} );
    }

    return undef;
}

__PACKAGE__->register_method(
    method      => 'create_note',
    api_name        => 'open-ils.serial.item_note.create',
    signature   => q/
        Creates a new item note
        @param authtoken The login session key
        @param note The note object to create
        @return The id of the new note object
    /
);

__PACKAGE__->register_method(
    method      => 'create_note',
    api_name        => 'open-ils.serial.subscription_note.create',
    signature   => q/
        Creates a new subscription note
        @param authtoken The login session key
        @param note The note object to create
        @return The id of the new note object
    /
);

__PACKAGE__->register_method(
    method      => 'create_note',
    api_name        => 'open-ils.serial.distribution_note.create',
    signature   => q/
        Creates a new distribution note
        @param authtoken The login session key
        @param note The note object to create
        @return The id of the new note object
    /
);

sub create_note {
    my( $self, $connection, $authtoken, $note ) = @_;

    $self->api_name =~ /serial\.(\w*)_note/;
    my $type = $1;

    my $e = new_editor(xact=>1, authtoken=>$authtoken);
    return $e->event unless $e->checkauth;

    # FIXME: restore permission support
#    my $item = $e->retrieve_serial_item(
#        [
#            $note->item
#        ]
#    );
#
#    return $e->event unless
#        $e->allowed('CREATE_COPY_NOTE', $item->call_number->owning_lib);

    $note->create_date('now');
    $note->creator($e->requestor->id);
    $note->pub( ($U->is_true($note->pub)) ? 't' : 'f' );
    $note->clear_id;

    my $method = "create_serial_${type}_note";
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

# FIXME: restore permissions check
#    if( $note->creator ne $e->requestor->id ) {
#        return $e->die_event unless
#            $e->allowed('DELETE_COPY_NOTE', $note->item->call_number->owning_lib);
#    }

    $method = "delete_serial_${type}_note";
    $e->$method($note) or return $e->die_event;
    $e->commit;
    return 1;
}


##########################################################################
# subscription methods
#
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

# TODO: permission check
#        return $editor->event unless
#            $editor->allowed('UPDATE_COPY', $class->copy_perm_org($vol, $copy));

    for my $ssub (@$ssubs) {

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
	method	=> "retrieve_sub_tree",
    authoritative => 1,
	api_name	=> "open-ils.serial.subscription_tree.retrieve"
);

__PACKAGE__->register_method(
	method	=> "retrieve_sub_tree",
	api_name	=> "open-ils.serial.subscription_tree.global.retrieve"
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

# TODO: permission check
#        return $editor->event unless
#            $editor->allowed('UPDATE_COPY', $class->copy_perm_org($vol, $copy));

    for my $sdist (@$sdists) {
        my $sdistid = $sdist->id;

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
          flesh_fields => {sdist => [ qw/ holding_lib receive_call_number receive_unit_template bind_call_number bind_unit_template streams / ]}
        });
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

# TODO: permission check
#        return $editor->event unless
#            $editor->allowed('UPDATE_COPY', $class->copy_perm_org($vol, $copy));

    for my $scap (@$scaps) {
        my $scapid = $scap->id;

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
                " (all boolean)", "type" => "object"}
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
        @ids = map { @{$_} } @{$search_result->{"ids"}};

        unless (@ids) {
            $e->disconnect;
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
    "method" => "get_receivable_items",
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
            "type" => "object"
        }
    }
);

__PACKAGE__->register_method(
    "method" => "get_receivable_items",
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
            "type" => "object"
        }
    }
);

sub get_receivable_items {
    my ($self, $client, $auth, $term)  = @_;

    my $e = new_editor("authtoken" => $auth);
    return $e->die_event unless $e->checkauth;

    # XXX permissions

    my $by = ($self->api_name =~ /by_(\w+)$/)[0];

    my %where = (
        "issuance" => {"issuance" => $term},
        "subscription" => {"+siss" => {"subscription" => $term}}
    );

    my $item_ids = $e->json_query(
        {
            "select" => {"sitem" => ["id"]},
            "from" => {"sitem" => "siss"},
            "where" => {
                %{$where{$by}}, "date_received" => undef
            },
            "order_by" => {"sitem" => ["id"]}
        }
    ) or return $e->die_event;

    return undef unless @$item_ids;

    foreach (map { $_->{"id"} } @$item_ids) {
        $client->respond(
            $e->retrieve_serial_item([
                $_, {
                    "flesh" => 3,
                    "flesh_fields" => {
                        "sitem" => ["stream", "issuance"],
                        "sstr" => ["distribution"],
                        "sdist" => ["holding_lib"]
                    }
                }
            ])
        );
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

1;
