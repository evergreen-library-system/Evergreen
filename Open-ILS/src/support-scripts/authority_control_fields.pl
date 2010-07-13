#!/usr/bin/perl
# Copyright (C) 2010 Laurentian University
# Author: Dan Scott <dscott@laurentian.ca>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------

use strict;
use warnings;
use DBI;
use Getopt::Long;
use MARC::Record;
use MARC::File::XML;
use OpenSRF::System;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::SettingsClient;
use Encode;
use Unicode::Normalize;
use OpenILS::Application::AppUtils;
# use Data::Dumper;

=head1

For a given set of records (specified by ID at the command line, or special option --all):

=over

=item * Iterate through the list of fields that are controlled fields

=item * Iterate through the list of subfields that are controlled for
that given field

=item * Search for a matching authority record for that combination of
field + subfield(s)

=over

=item * If we find a match, then add a $0 subfield to that field identifying
the controlling authority record

=item * If we do not find a match, then insert a row into an "uncontrolled"
table identifying the record ID, field, and subfield(s) that were not controlled

=back

=item * Iterate through the list of floating subdivisions

=over

=item * If we find a match, then add a $0 subfield to that field identifying
the controlling authority record

=item * If we do not find a match, then insert a row into an "uncontrolled"
table identifying the record ID, field, and subfield(s) that were not controlled

=back

=item * If we changed the record, update it in the database

=back

=cut

my $all_records;
my $bootstrap = '/openils/conf/opensrf_core.xml';
my @records;
my $result = GetOptions(
    'configuration=s' => \$bootstrap,
    'record=s' => \@records,
    'all' => \$all_records
);

OpenSRF::System->bootstrap_client(config_file => $bootstrap);
Fieldmapper->import(IDL => OpenSRF::Utils::SettingsClient->new->config_value("IDL"));

# must be loaded and initialized after the IDL is parsed
use OpenILS::Utils::CStoreEditor;
OpenILS::Utils::CStoreEditor::init();

my $editor = OpenILS::Utils::CStoreEditor->new;
if ($all_records) {
    # get a list of all non-deleted records from Evergreen
    # open-ils.cstore open-ils.cstore.direct.biblio.record_entry.id_list.atomic {"deleted":"f"}
    push @records, $editor->request( 
        'open-ils.cstore.direct.biblio.record_entry.id_list.atomic', 
        {deleted => 'f'},
        {id => { '>' => 0}}
    );
}
# print Dumper(\@records);

# Hash of controlled fields & subfields in bibliographic records, and their
# corresponding controlling fields & subfields in the authority record
#
# So, if the bib 650$a can be controlled by an auth 150$a, that maps to:
# 650 => { a => { 150 => 'a'}}
my %controllees = (
    110 =>  { a => { 110 => 'a' },
              d => { 110 => 'd' },
              e => { 110 => 'e' }
            },
    711 =>  { a => { 111 => 'a' },
              c => { 111 => 'c' },
              d => { 111 => 'd' }
            }
    
);

foreach my $rec_id (@records) {

    my $e = OpenILS::Utils::CStoreEditor->new(xact=>1);
    # State variable; was the record changed?
    my $changed;

    # get the record
    my $record = $e->retrieve_biblio_record_entry($rec_id);
    next unless $record;
    # print Dumper($record);

    my $marc = MARC::Record->new_from_xml($record->marc());

    # get the list of controlled fields
    my @c_fields = keys %controllees;

    foreach my $c_tag (@c_fields) {
        my @c_subfields = keys %{$controllees{"$c_tag"}};
        # print "Field: $field subfields: ";
        # foreach (@subfields) { print "$_ "; }

        # Get the MARCXML from the record and check for controlled fields/subfields
        my @bib_fields = ($marc->field($c_tag));
        foreach my $bib_field (@bib_fields) {
            # print $_->as_formatted(); 
            my %match_subfields;
            my $match_tag;
            my @searches;
            foreach my $c_subfield (@c_subfields) {
                my $sf = $bib_field->subfield($c_subfield);
                if ($sf) {
                    # Give me the first element of the list of authority controlling tags for this subfield
                    # XXX Will we need to support more than one controlling tag per subfield? Probably. That
                    # will suck. Oh well, leave that up to Ole to implement.
                    $match_subfields{$c_subfield} = (keys %{$controllees{$c_tag}{$c_subfield}})[0];
                    $match_tag = $match_subfields{$c_subfield};
                    push @searches, {term => $sf, subfield => $c_subfield};
                }
            }
            # print Dumper(\%match_subfields);

            my @tags = ($match_tag);
            # Now we've built up a complete set of matching controlled
            # subfields for this particular field; let's check to see if
            # we have a matching authority record
            my $session = OpenSRF::AppSession->create("open-ils.search");
            my $validates = $session->request("open-ils.search.authority.validate.tag.id_list", 
                "tags", \@tags, "searches", \@searches
            )->gather();
            $session->disconnect();

            # print Dumper($validates);

            if (scalar(@$validates) == 0) {
                next;
            }

            # Okay, we have a matching authority control; time to
            # add the magical subfield 0
            my $auth_id = @$validates[0];
            my $auth_rec = $e->retrieve_authority_record_entry($auth_id);
            my $auth_marc = MARC::Record->new_from_xml($auth_rec->marc());
            my $cni = $auth_marc->field('003')->data();
            
            $bib_field->add_subfields('0' => "($cni)$auth_id");
            $changed = 1;
        }
    }
    if ($changed) {
        # print $marc->as_formatted();
        my $xml = $marc->as_xml_record();
        $xml =~ s/\n//sgo;
        $xml =~ s/^<\?xml.+\?\s*>//go;
        $xml =~ s/>\s+</></go;
        $xml =~ s/\p{Cc}//go;
        $xml = OpenILS::Application::AppUtils->entityize($xml);

        $record->marc($xml);
        $e->update_biblio_record_entry($record);
    }
    $e->commit();
}
