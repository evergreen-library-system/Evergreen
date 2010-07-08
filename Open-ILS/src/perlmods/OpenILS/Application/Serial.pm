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
use OpenSRF::AppSession;
use OpenSRF::Utils::Logger qw($logger);
use OpenILS::Utils::CStoreEditor q/:funcs/;
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


# helper method for conforming dates to ISO8601
sub _cleanse_dates {
    my $item = shift;
    my $fields = shift;

    foreach my $field (@$fields) {
        $item->$field(OpenSRF::Utils::clense_ISO8601($item->$field)) if $item->$field;
    }
    return 0;
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
                 name => 'issuances',
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
            $evt = _delete_item( $editor, $override, $item);
        } elsif( $item->isnew ) {
            # TODO: reconsider this
            # if the item has a new issuance, create the issuance first
            if ($item->issuance->isnew) {
                fleshed_issuance_alter($self, $conn, $auth, [$item->issuance]);
            }
            _cleanse_dates($item, ['date_expected','date_received']);
            $evt = _create_item( $editor, $item );
        } else {
            _cleanse_dates($item, ['date_expected','date_received']);
            $evt = _update_item( $editor, $override, $item );
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

sub _delete_item {
    my ($editor, $override, $item) = @_;
    $logger->info("item-alter: delete item ".OpenSRF::Utils::JSON->perl2JSON($item));
    return $editor->event unless $editor->delete_serial_item($item);
    return 0;
}

sub _create_item {
    my ($editor, $item) = @_;

    $item->creator($editor->requestor->id);
    $item->create_date('now');

    $logger->info("item-alter: new item ".OpenSRF::Utils::JSON->perl2JSON($item));
    return $editor->event unless $editor->create_serial_item($item);
    return 0;
}

sub _update_item {
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
            $evt = _delete_issuance( $editor, $override, $issuance);
        } elsif( $issuance->isnew ) {
            _cleanse_dates($issuance, ['date_published']);
            $evt = _create_issuance( $editor, $issuance );
        } else {
            _cleanse_dates($issuance, ['date_published']);
            $evt = _update_issuance( $editor, $override, $issuance );
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

sub _delete_issuance {
    my ($editor, $override, $issuance) = @_;
    $logger->info("issuance-alter: delete issuance ".OpenSRF::Utils::JSON->perl2JSON($issuance));
    return $editor->event unless $editor->delete_serial_issuance($issuance);
    return 0;
}

sub _create_issuance {
    my ($editor, $issuance) = @_;

    $issuance->creator($editor->requestor->id);
    $issuance->create_date('now');

    $logger->info("issuance-alter: new issuance ".OpenSRF::Utils::JSON->perl2JSON($issuance));
    return $editor->event unless $editor->create_serial_issuance($issuance);
    return 0;
}

sub _update_issuance {
    my ($editor, $override, $issuance) = @_;

    $logger->info("issuance-alter: retrieving issuance ".$issuance->id);
    my $orig_issuance = $editor->retrieve_serial_issuance($issuance->id);

    $logger->info("issuance-alter: original issuance ".OpenSRF::Utils::JSON->perl2JSON($orig_issuance));
    $logger->info("issuance-alter: updated issuance ".OpenSRF::Utils::JSON->perl2JSON($issuance));
    return $editor->event unless $editor->update_serial_issuance($issuance);
    return 0;
}


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

#    my $evt;
#    my $org = (ref $copy->circ_lib) ? $copy->circ_lib->id : $copy->circ_lib;
#    return $evt if ( $evt = OpenILS::Application::Cat::AssetCommon->org_cannot_have_vols($editor, $org) );

    $logger->info("sunit-alter: retrieving sunit ".$sunit->id);
    my $orig_sunit = $editor->retrieve_serial_unit($sunit->id);

    $logger->info("sunit-alter: original sunit ".OpenSRF::Utils::JSON->perl2JSON($orig_sunit));
    $logger->info("sunit-alter: updated sunit ".OpenSRF::Utils::JSON->perl2JSON($sunit));
    return $editor->event unless $editor->update_serial_unit($sunit);
    return 0;
}


##########################################################################
# predict and receive methods
#
__PACKAGE__->register_method(
    method    => 'generate_predictions',
    api_name  => 'open-ils.serial.generate_predictions',
    api_level => 1,
    argc      => 1,
    signature => {
        desc     => 'Receives an sre (serial record entry) id and returns an array ref of predicted issuances',
        'params' => [ {
                 name => 'sre_id',
                 desc => 'Serial Record Entry ID',
                 type => 'integer'
            }
        ],
        'return' => {
            desc => 'Returns predicted issuances',
            type => 'array'
        }
    }
);

sub generate_predictions {
    my ($self, $conn, $authtoken, $args) = @_;

    my $editor = OpenILS::Utils::CStoreEditor->new();
    if (!exists($args->{sre_id})) { # lookup by sdist_id instead
        my $sdist = $editor->retrieve_serial_distribution([$args->{sdist_id}]);
        $args->{sre_id} = $sdist->record_entry;
    }
    #return $args->{sre_id};
    my $sre = $editor->retrieve_serial_record_entry([$args->{sre_id}]);

    #return $sre->marc;

    #convert from marc_xml to marc
    my $marc = MARC::Record->new_from_xml($sre->marc);

    #turn into MFHD record object
    my $mfhd = MFHD->new($marc);

    my @predictions;
    # TODO: consider support for predicting supplements/indexes (854/855)
    my $tag = '853';
    my @active_captions = $mfhd->active_captions($tag);
    foreach my $caption (@active_captions) {
        my $options = {
                'caption' => $caption,
                'num_to_predict' => $args->{num_to_predict},
                'last_rec_date' => $args->{last_rec_date}
                };
        if ($args->{from_last_received}) {
            my $last_received = $editor->search_serial_issuance([
                {   'holding_type' => $MFHD_NAMES_BY_TAG{$tag},
                    'holding_link_id' => $caption->link_id,
                    'distribution' => $args->{sdist_id}},
                {limit => 1, order_by => { siss => "date_expected DESC" }}]
                );
            if ($last_received->[0]) {
                $options->{last_rec_date} = $last_received->[0]->date_expected;
                $options->{predict_from} = _revive_holding($mfhd, $last_received->[0]->holding_code);
            }
        }
        push( @predictions, _generate_issuance_values($mfhd, $options) );
    }

    my @issuances;
    foreach my $prediction (@predictions) {
        my $issuance = new Fieldmapper::serial::issuance;
        $issuance->isnew(1);
        $issuance->holding_link_id($prediction->[0]);
        $issuance->label($prediction->[1]);
        $issuance->date_published($prediction->[2]);
        $issuance->date_expected($prediction->[3]);
        $issuance->holding_code(OpenSRF::Utils::JSON->perl2JSON($prediction->[4]));
        $issuance->holding_type($prediction->[5]);
        push (@issuances, $issuance);
    }

    return \@issuances;
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
# returns @issuance_values, an array of array refs containing (link id, formatted
# label, formatted chronology date, formatted estimated arrival date, and an
# array ref of holding subfields as (key, value, key, value ...)) (not a hash
# to protect order and possible duplicate keys).
#
sub _generate_issuance_values {
    my ($mfhd, $options) = @_;
    my $caption = $options->{caption};
    my $num_to_predict = $options->{num_to_predict};
    my $last_rec_date = $options->{last_rec_date};   # expected or actual, according to preference
    my $predict_from = $options->{predict_from};   # optional issuance to predict from

    # TODO: add support for predicting serials with no chronology by passing in
    # a last_pub_date option?

    my $strp = new DateTime::Format::Strptime(pattern => '%F');

    my $receival_date = $strp->parse_datetime($last_rec_date);

    my $htag    = $caption->tag;
    $htag =~ s/^85/86/;
    my $link_id = $caption->link_id;
    if(!$predict_from) {
        my @holdings = $mfhd->holdings($htag, $link_id);
        my $last_holding = $holdings[-1];

        if ($last_holding->is_compressed) {
            $last_holding->compressed_to_last; # convert to last in range
        }
        $predict_from = $last_holding;
    }

    my $pub_date  = $strp->parse_datetime($predict_from->chron_to_date);
    my $date_diff = $receival_date - $pub_date;

    $predict_from->notes('public',  []);
# add a note marker for system use
    $predict_from->notes('private', ['AUTOGEN']);

    my @issuance_values;
    my @predictions = $mfhd->generate_predictions({'base_holding' => $predict_from, 'num_to_predict' => $num_to_predict});
    foreach my $prediction (@predictions) {
        $pub_date = $strp->parse_datetime($prediction->chron_to_date);
        my $arrival_date = $pub_date + $date_diff;
        push(
                @issuance_values,
                [
                    $link_id,
                    $prediction->format,
                    $pub_date->strftime('%F'),
                    $arrival_date->strftime('%F'),
                    [$htag,$prediction->indicator(1),$prediction->indicator(2),$prediction->subfields_list],
                    $MFHD_NAMES_BY_TAG{$caption->tag}
                ]
            );
    }

    return @issuance_values;
}

sub _revive_holding {
    my $mfhd = shift;
    my $holding_code = shift;

    # build MARC::Field
    my $holding_parts = OpenSRF::Utils::JSON->JSON2perl($holding_code);
    my $issuance_holding = new MARC::Field(@$holding_parts);
    # fetch matching captions
    my $captag = $issuance_holding->tag;
    $captag =~ s/^86/85/;
    my $captions_ref = $mfhd->captions($captag, 'hashref');
    # build MFHD::Holding
    my $link_subfield = $issuance_holding->subfield('8');
    my ($link_id, $seqno) = split(/\./, $link_subfield);
    return new MFHD::Holding($seqno, $issuance_holding, $captions_ref->{$link_id});
}

__PACKAGE__->register_method(
    method    => 'receive_issuances',
    api_name  => 'open-ils.serial.receive_issuances',
    api_level => 1,
    argc      => 1,
    signature => {
        desc     => 'Marks an issuance as received, updates the shelving unit (creating a new shelving unit if needed), and updates the underlying MFHD record',
        'params' => [ {
                 name => 'issuances',
                 desc => 'array of Issuance objects',
                 type => 'array'
            }
        ],
        'return' => {
            desc => 'Returns number of received issuances',
            type => 'int'
        }
    }
);

sub receive_issuances {
    my ($self, $conn, $auth, $issuances) = @_;

    my $last_distribution;
    my $last_mfhd;
    my %sres_to_save;
    my %mfhds_to_save;
    my( $reqr, $evt ) = $U->checkses($auth);
    return $evt if $evt;
    my $editor = new_editor(requestor => $reqr, xact => 1);
    foreach my $issuance (@$issuances) {
        # unflesh shelving unit if fleshed
        $issuance->shelving_unit( $issuance->shelving_unit->id ) if ref($issuance->shelving_unit);
        $issuance->distribution( $issuance->distribution->id ) if ref($issuance->distribution);

        $issuance->copies_received($issuance->copies_received + 1);
        $issuance->copies_expected($issuance->copies_expected - 1);
        $issuance->date_received('now');

        # create shelving unit if needed
        if ($issuance->shelving_unit == -1) { # create by "volume" (first issuance division)
        #TODO
        } elsif ($issuance->shelving_unit == -2) { # create by "issue" (second issuance division)
        #TODO
        }

        my $mfhd;
        my $sre;
        if ($issuance->distribution == $last_distribution) {
            # use cached record
            $mfhd = $last_mfhd;
        } else { # get MFHD record
            my $sdist = $editor->retrieve_serial_distribution([$issuance->distribution]);
            $sre = $editor->retrieve_serial_record_entry([$sdist->record_entry]);

            #convert from marc_xml to marc
            my $marc = MARC::Record->new_from_xml($sre->marc);

            #turn into MFHD record object
            $mfhd = MFHD->new($marc);
            $sres_to_save{$sre->id} = $sre;
            $mfhds_to_save{$sre->id} = $mfhd;
        }

#        # build MARC::Field
#        my $holding_parts = OpenSRF::Utils::JSON->JSON2perl($issuance->holding_code);
#        my $issuance_holding = new MARC::Field(@$holding_parts);
#        # fetch matching captions
#        my $captag = $issuance_holding->tag;
#        $captag =~ s/^86/85/;
#        my $captions_ref = $mfhd->captions($captag, 'hashref');
#        # build MFHD::Holding
#        my $link_subfield = $issuance_holding->subfield('8');
#        my ($link_id, $seqno) = split(/\./, $link_subfield);
#        $issuance_holding = new MFHD::Holding($seqno, $issuance_holding, $captions_ref->{$link_id});
        my $issuance_holding = _revive_holding($mfhd, $issuance->holding_code);
        
        # get all current holdings for this linked caption
#        my @curr_holdings = $mfhd->holdings($issuance_holding->tag, $link_id);
        my @curr_holdings = $mfhd->holdings($issuance_holding->tag, $issuance_holding->caption->link_id);
        # short-circuit logic : if holding is the next one, increment the last current holding
        my $next_holding_values = $curr_holdings[-1]->next;
        if ($next_holding_values and $issuance_holding->matches($next_holding_values)) {
            $curr_holdings[-1]->extend;
        } else { # not the next expected, do full replacement
            $mfhd->append_fields($issuance_holding);
#            my @updated_holdings = $mfhd->get_compressed_holdings($captions_ref->{$link_id});
            my @updated_holdings = $mfhd->get_compressed_holdings($issuance_holding->caption);
            # set reference point to top of current holdings
            my $marker_field = MARC::Field->new(500, '', '','a' => 'Temporary Marker'); 
            $mfhd->insert_fields_before($curr_holdings[0], $marker_field);
            foreach my $holding (@curr_holdings) {
                $mfhd->delete_field($holding);
            }
            $mfhd->delete_field($issuance_holding);
            $mfhd->insert_fields_before($marker_field, @updated_holdings);
            # delete reference point
            $mfhd->delete_field($marker_field);
        }   

        $last_distribution = $issuance->distribution;
        $last_mfhd = $mfhd;
        _update_issuance($editor, undef, $issuance);
    }

    foreach my $sre_id (keys %sres_to_save) {
        #TODO: update '005' to current date
        my $sre = $sres_to_save{$sre_id};
        (my $xml = $mfhds_to_save{$sre_id}->as_xml_record()) =~ s/\n//sog;
        $xml =~ s/^<\?xml.+\?\s*>//go;
        $sre->marc($xml);
        $sre->ischanged(1);
        $editor->update_serial_record_entry($sre);
        #return ($sre->record);
    }

    #return OpenSRF::Utils::JSON->perl2JSON($last_mfhd);

    $editor->commit;
    return scalar @$issuances;
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

sub delete_note {
    my( $self, $conn, $authtoken, $noteid ) = @_;

    $self->api_name =~ /serial\.(\w*)_note/;
    my $type = $1;

    my $e = new_editor(xact=>1, authtoken=>$authtoken);
    return $e->die_event unless $e->checkauth;

    my $note = $e->retrieve_serial_item_note([
        $noteid,
    ]) or return $e->die_event;

# FIXME: restore permissions check
#    if( $note->creator ne $e->requestor->id ) {
#        return $e->die_event unless
#            $e->allowed('DELETE_COPY_NOTE', $note->item->call_number->owning_lib);
#    }

    my $method = "delete_serial_${type}_note";
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

# user_session may be null/undef
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

#		for my $dist (@$dists) {
#			if( $c->status == OILS_COPY_STATUS_CHECKED_OUT ) {
#				$c->circulations(
#					$e->search_action_circulation(
#						[
#							{ target_copy => $c->id },
#							{
#								order_by => { circ => 'xact_start desc' },
#								limit => 1
#							}
#						]
#					)
#				)
#			}
#		}

		$sub->distributions($dists);
        
        # TODO: filter on !deleted?
		my $issuances = $e->search_serial_issuance(
			[{ subscription => $sub->id }, { 'order_by' => {'siss' => 'label'} }]
            );

		#$issuances = [ sort { $a->label cmp $b->label } @$issuances  ];
		$sub->issuances($issuances);

		my $scaps = $e->search_serial_caption_and_pattern(
			{ subscription => $sub->id }); # TODO: filter on !deleted?

		$scaps = [ sort { $a->id cmp $b->id } @$scaps  ];
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
          flesh_fields => {sdist => [ qw/ holding_lib receive_call_number receive_unit_template bind_call_number bind_unit_template / ]}
        });
}

1;
