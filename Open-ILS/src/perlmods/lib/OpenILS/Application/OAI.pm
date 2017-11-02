# OpenILS::WWW::OAI manages OAI2 requests and responses.
#
# Copyright (c) 2014-2017 International Institute of Social History
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#
# Author: Lucien van Wouw <lwo@iisg.nl>


package OpenILS::Application::OAI;
use strict; use warnings;

use base qw/OpenILS::Application/;
use OpenSRF::AppSession;
use OpenSRF::EX qw(:try);
use MARC::Record;
use MARC::File::XML ( BinaryEncoding => 'UTF-8' );
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Logger qw($logger);
use XML::LibXML;
use XML::LibXSLT;

my (
  $_parser,
  $_xslt,
  %record_xslt,
  %metarecord_xslt,
  %holdings_data_cache,
  %authority_browse_axis_cache,
  %copies,
  $barcode_filter,
  $status_filter
);


sub child_init {

    # set the XML parser
    $_parser = new XML::LibXML;

    # and the xslt parser
    $_xslt = new XML::LibXSLT;

    # Load the metadataformats that are configured.
    my $metadata_format = OpenSRF::Utils::SettingsClient->new->config_value(apps => 'open-ils.oai')->{'app_settings'}->{'metadataformat'};
    if ( $metadata_format ) {
        for my $schema ( keys %$metadata_format ) {
            $logger->info('Loading schema ' . $schema) ;
            $record_xslt{$schema}{namespace_uri}   = $metadata_format->{$schema}->{namespace_uri};
            $record_xslt{$schema}{schema_location} = $metadata_format->{$schema}->{schema_location};
            $record_xslt{$schema}{xslt}            = $_xslt->parse_stylesheet( $_parser->parse_file(
                OpenSRF::Utils::SettingsClient->new->config_value( dirs => 'xsl' ) . '/' . $metadata_format->{$schema}->{xslt}
            ) );
        }
    }

    # Fall back on system defaults if oai_dc is not set in the configuration.
    unless ( exists $record_xslt{oai_dc} ) {
        $logger->info('Loading default oai_dc schema') ;
        my $xslt = $_parser->parse_file(
            OpenSRF::Utils::SettingsClient
                ->new
                ->config_value( dirs => 'xsl' ).
            "/OAI2_OAIDC.xsl"
        );
        # and stash a transformer
        $record_xslt{oai_dc}{xslt} = $_xslt->parse_stylesheet( $xslt );
        $record_xslt{oai_dc}{namespace_uri} = 'http://www.openarchives.org/OAI/2.0/oai_dc/';
        $record_xslt{oai_dc}{schema_location} = 'http://www.openarchives.org/OAI/2.0/oai_dc.xsd';
    }

    # If not defined, use the natural marcxml metadata setting
    unless ( exists $record_xslt{marcxml}) {
        $logger->info('Loading default marcxml schema') ;
        my $xslt = $_parser->parse_file(
            OpenSRF::Utils::SettingsClient
                ->new
                ->config_value( dirs => 'xsl' ).
            "/OAI2_MARC21slim.xsl"
        );
        # and stash a transformer
        $record_xslt{marcxml}{xslt} = $_xslt->parse_stylesheet( $xslt );
        $record_xslt{marcxml}{namespace_uri} = 'http://www.loc.gov/MARC21/slim';
        $record_xslt{marcxml}{docs} = 'http://www.loc.gov/MARC21/slim';
        $record_xslt{marcxml}{schema_location} = 'http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd';
    }

    # Load the mapping of 852 holdings.
    my $copies = OpenSRF::Utils::SettingsClient->new->config_value(apps => 'open-ils.oai')->{'app_settings'}->{'copies'} ;
    if ( $copies ) {
        foreach my $subfield_code (keys %$copies) {
            my $value = $copies->{$subfield_code};
            $logger->info('Set 852 map ' . $subfield_code . '=' . $value );
            $copies{$subfield_code} = $value;
        }
    } else { # if not defined, fall back on these defaults.
        %copies = (
            a => 'location',
            b => 'owning_lib',
            c => 'callnumber',
            d => 'circlib',
            g => 'barcode',
            n => 'status'
        );
    }

    # Set the barcode filter and status filter
    $barcode_filter = OpenSRF::Utils::SettingsClient->new->config_value(apps => 'open-ils.oai')->{'app_settings'}->{'barcode_filter'};
    $status_filter = OpenSRF::Utils::SettingsClient->new->config_value(apps => 'open-ils.oai')->{'app_settings'}->{'status_filter'};

    return 1;
}


sub list_record_formats {

    my @list;
    for my $type ( keys %record_xslt ) {
        push @list,
            { $type =>
                { namespace_uri   => $record_xslt{$type}{namespace_uri},
                  docs        => $record_xslt{$type}{docs},
                  schema_location => $record_xslt{$type}{schema_location},
                }
            };
    }

    return \@list;
}

__PACKAGE__->register_method(
    method    => 'list_record_formats',
    api_name  => 'open-ils.oai.record.formats',
    api_level => 1,
    argc      => 0,
    signature =>
    {
        desc     => 'Returns the list of valid record formats that oai understands.',
        'return' =>
        {
            desc => 'The format list.',
            type => 'array'
        }
    }
);


sub oai_biblio_retrieve {

    my $self = shift;
    my $client = shift;
    my $tcn = shift;
    my $metadataPrefix = shift;

    #  holdings hold an array of call numbers, which hold an array of copies
    #  holdings => [ label: { library, [ copies: { barcode, location, status, circ_lib } ] } ]
    my %holdings;

    my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );

    # Retrieve the bibliographic record and it's copies
    my $tree = $_storage->request(
        "open-ils.cstore.direct.biblio.record_entry.retrieve",
        $tcn,
        { flesh     => 5,
          flesh_fields  => {
                    bre => [qw/marc edit_date call_numbers/],
                    acn => [qw/edit_date copies owning_lib prefix suffix/],
                    acp => [qw/edit_date location status circ_lib parts/],
                }
        }
    )->gather(1);

    # Create a MARC::Record object with the marc.
    my $marc = MARC::Record->new_from_xml( $tree->marc, 'UTF8', 'XML');

    # Retrieve the MFHD where we can find them.
    my %serials;
    if ( substr($marc->leader, 7, 1) eq 's' ) { # serial
        my $_search = OpenSRF::AppSession->create( 'open-ils.search' );
        my $_serials = $_search->request('open-ils.search.serial.record.bib.retrieve', $tcn, 1, 0)->gather(1);
        my $order = 0 ;
        for my $sre (@$_serials) {
            if ( $sre->location ) {
                $order++ ;
                my @svr = split( ' -- ', $sre->location );
                my $cn_label = $svr[-1];
                $serials{$order}{'label'} = $cn_label ;
                my $display = @{$sre->basic_holdings_add} ? $sre->basic_holdings_add : $sre->basic_holdings;
                $serials{$order}{'ser'} = join(', ', @{$display});
            }
        }
    }

    my $edit_date = $tree->edit_date ;

    # Prepare a hash of all holdings and serials
    for my $cn (@{$tree->call_numbers}) {

        next unless ( $cn->deleted eq 'f' || !$cn->deleted );
        my $_visible = 0;
        for my $c (@{$cn->copies}) {
            $_visible = _cp_is_visible($cn, $c);
            last if ( $_visible );
        }
        next unless $_visible;

        my $cn_label = $cn->label;
        $holdings{$cn_label}{'owning_lib'} = $cn->owning_lib->shortname;

        $edit_date =  most_recent_date( $cn->edit_date, $edit_date );

        for my $cp (@{$cn->copies}) {

            next unless _cp_is_visible($cn, $cp);
            $edit_date = most_recent_date( $cp->edit_date, $edit_date );

            # find the corresponding serial.
            # There is no way of knowing here if the barcode 852$p is a correct match.
            my $order = 0 ;
            my $ser;
            foreach my $key (sort keys %serials) {
                my $serial = $serials{$key};
                if ( $serial->{'label'} eq $cn_label ) {
                    $ser = $serial->{'ser'};
                    $order = $key;
                    delete $serials{$key}; # in case we have several serial holdings with the same call number
                    last;
               }
            }
            $holdings{$cn_label}{'order'} = $order ;

            my $circlib = $cp->circ_lib->shortname ;
            push @{$holdings{$cn->label}{'copies'}}, {
                owning_lib => $cn->owning_lib->shortname,
                callnumber => $cn->label,
                barcode    => $cp->barcode,
                status     => $cp->status->name,
                location   => $cp->location->name,
                circlib    => $circlib,
                ser        => $ser
            };
        }
    }

    ## Append the holdings and MFHD data to the marc record and apply the stylesheet.
    if ( %holdings ) {

        # Force record leader to 'a' as our data is always UTF8
        # Avoids marc8_to_utf8 from being invoked with horrible results
        # on the off-chance the record leader isn't correct
        my $ldr = $marc->leader;
        substr($ldr, 9, 1, 'a');
        $marc->leader($ldr);

        # Expects the record ID in the 001
        $marc->delete_field($_) for ($marc->field('001'));
        if (!$marc->field('001')) {
            $marc->insert_fields_ordered(
                MARC::Field->new( '001', $tcn )
            );
        }

        # Our reference node to prepend nodes to.
        my $reference = $marc->field('901');

        $marc->delete_field($_) for ($marc->field('852')); # remove any legacy 852s
        foreach my $cn (sort { $holdings{$a}->{'order'} <=> $holdings{$b}->{'order'}} keys %holdings) {
            foreach my $cp (@{$holdings{$cn}->{'copies'}}) {
                my $marc_852 = MARC::Field->new(
                   '852', '4', ' ', 0 => 'dummy'); # The dummy is necessary to prevent a validation error.
                foreach my $subfield_code (sort keys %copies) {
                    my $_cp = $copies{$subfield_code} ;
                    $marc_852->add_subfields($subfield_code, $cp->{$_cp} || $_cp) if ($_cp);
                }
                $marc_852->delete_subfield(code => '0');
                $marc->insert_fields_before($reference, $marc_852);
                if ( $cp->{'ser'} ) {
                    my $marc_866_a = MARC::Field->new( '866', '4', ' ', 'a' => $cp->{'ser'});
                    $marc->insert_fields_after( $marc_852, $marc_866_a ) ;
                }
            }
        }

    }

    my $xslt = $record_xslt{$metadataPrefix}{xslt} ;
    my $xml = $xslt->transform( $_parser->parse_string( $marc->as_xml_record()) );
    return $xslt->output_as_chars( $xml ) ;
}


sub most_recent_date {

    my $date1 = substr(shift, 0, 19) ;  # e.g. '2001-02-03T04:05:06+0000' becomes '2001-02-03T04:05:06'
    my $date2 = substr(shift, 0, 19) ;
    my $_date1 = $date1 ;
    my $_date2 = $date2 ;

    $date1 =~ s/[-T:\.\+]//g ; # '2001-02-03T04:05:06' becomes '20010203040506'
    $date2 =~ s/[-T:\.\+]//g ;

    return $_date1 if ( $date1 > $date2) ;
    return $_date2 ;
}


sub _cp_is_visible {

    my $cn = shift;
    my $cp = shift;

    my $visible = 0;
    if ( ($cp->deleted eq 'f' || !$cp->deleted) &&
         ( ! $barcode_filter || $cp->barcode =~ /$barcode_filter/ ) &&
         $cp->location->opac_visible eq 't' &&
         $cp->status->opac_visible eq 't' &&
         $cp->opac_visible eq 't' &&
         $cp->circ_lib->opac_visible eq 't' &&
         $cn->owning_lib->opac_visible eq 't' &&
         (! $status_filter || $cp->status->name =~ /$status_filter/ )
    ) {
        $visible = 1;
    }

    return $visible;
}

__PACKAGE__->register_method(
    method    => 'oai_biblio_retrieve',
    api_name  => 'open-ils.oai.biblio.retrieve',
    api_level => 1,
    argc      => 1,
    signature =>
    {
        desc     => 'Returns the MARCXML representation of the requested bibliographic record.',
        params   =>
        [
            {
                name => 'tcn',
                desc => 'An OpenILS biblio::record_entry id.',
                type => 'number'
            },
            {
                name => 'metadataPrefix',
                desc => 'The metadataPrefix of the schema.',
                type => 'string'
            }
        ],
        'return' =>
        {
            desc => 'An string of the XML in the desired schema.',
            type => 'string'
        }
    }
);


sub oai_authority_retrieve {

    my $self = shift;
    my $client = shift;
    my $tcn = shift;
    my $metadataPrefix = shift;

    my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );

    # Retrieve the authority record
    my $record = $_storage->request('open-ils.cstore.direct.authority.record_entry.retrieve', $tcn)->gather(1);
    my $o = Fieldmapper::authority::record_entry->new($record) ;
    my $marc = MARC::Record->new_from_xml( $o->marc, 'UTF8', 'XML');

    # Expects the record ID in the 001
    $marc->delete_field($_) for ($marc->field('001'));
    if (!$marc->field('001')) {
        $marc->insert_fields_ordered(
            MARC::Field->new( '001', $tcn )
        );
    }

    my $xslt = $record_xslt{$metadataPrefix}{xslt} ;
    my $xml = $record_xslt{$metadataPrefix}{xslt}->transform(
       $_parser->parse_string( $marc->as_xml_record())
    );
    return $record_xslt{$metadataPrefix}{xslt}->output_as_chars( $xml ) ;
}


__PACKAGE__->register_method(
    method    => 'oai_authority_retrieve',
    api_name  => 'open-ils.oai.authority.retrieve',
    api_level => 1,
    argc      => 1,
    signature =>
    {
        desc     => 'Returns the MARCXML representation of the requested authority record.',
        params   =>
        [
            {
                name => 'tcn',
                desc => 'An OpenILS authority::record_entry id.',
                type => 'number'
            },
            {
                name => 'metadataPrefix',
                desc => 'The metadataPrefix of the schema.',
                type => 'string'
            }
        ],
        'return' =>
        {
            desc => 'An string of the XML in the desired schema.',
            type => 'string'
        }
    }
);


sub oai_list_retrieve {

    my $self            = shift;
    my $client          = shift;
    my $record_class    = shift || 'biblio';
    my $tcn             = shift || 0;
    my $from            = shift;
    my $until           = shift;
    my $set             = shift ;
    my $metadataPrefix  = shift;
    my $max_count       = shift;
    my $deleted_record  = shift || 'yes';

    my $query = {};
    $query->{'tcn'}       = ($max_count eq 1) ? $tcn : {'>=' => $tcn} ;
    $query->{'set_spec'}  = $set                     if ( $set ); # unsupported
    $query->{'deleted'}   = 'f'                      unless ( $deleted_record eq 'yes' );
    $query->{'datestamp'} = {'>=', $from}            if ( $from && !$until ) ;
    $query->{'datestamp'} = {'<=', $until}           if ( !$from && $until ) ;
    $query->{'-and'}      = [{'datestamp'=>{'>=' => $from}}, {'datestamp'=>{'<=' => $until}}] if ( $from && $until ) ;

    my $_storage = OpenSRF::AppSession->create( 'open-ils.cstore' );
    return $_storage->request('open-ils.cstore.direct.oai.' . $record_class . '.search.atomic',
            $query,
            {
                limit => $max_count + 1
            }
        )->gather(1);
}

__PACKAGE__->register_method(
    method    => 'oai_list_retrieve',
    api_name  => 'open-ils.oai.list.retrieve',
    api_level => 1,
    argc      => 1,
    signature =>
    {
        desc => 'Returns a list of record identifiers.',
        params =>
        [
            {
                name => 'record_class',
                desc => '\'biblio\' for bibliographic records or \'authority\' for authority records',
                type => 'string'
            },            {
                name => 'tcn',
                desc => 'An optional tcn number used as a cursor.',
                type => 'number'
            },
            {
                name => 'from',
                desc => 'The datestamp the resultset range should begin with.',
                type => 'string'
            },
            {
                name => 'until',
                desc => 'The datestamp the resultset range should end with.',
                type => 'string'
            },
            {
                name => 'set',
                desc => 'A setspec.',
                type => 'string'
            },
            {
                name => 'metadataPrefix',
                desc => 'The metadataPrefix of the schema.',
                type => 'string'
            },
            {
                name => 'offset',
                desc => 'The start of the cursor position in the result set.',
                type => 'number'
            },
            {
                name => 'deleted_record',
                desc => 'If set to \'no\' the response will only include active records.',
                type => 'string'
            }
        ],
        'return' =>
        {
            desc => 'An OAI type record.',
            type => 'array'
        }
    }
);


1;