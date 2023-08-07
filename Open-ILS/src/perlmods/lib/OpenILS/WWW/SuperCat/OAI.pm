# OpenILS::WWW::SuperCat::OAI manages OAI2 requests and responses.
#
# Copyright (c) 2014-2017  International Institute of Social History
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


package OpenILS::WWW::SuperCat::OAI;
use strict; use warnings;
use Apache2::Const -compile => qw(OK REDIRECT DECLINED NOT_FOUND :log);
use CGI;
use DateTime::Format::ISO8601;
use HTTP::OAI;
use HTTP::OAI::Metadata::OAI_Identifier;
use HTTP::OAI::Repository qw/:validate/;
use MARC::File::XML ( BinaryEncoding => 'UTF-8' );
use MARC::Record;
use MIME::Base64;
use OpenSRF::EX qw(:try);
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor;
use OpenILS::Application::AppUtils;
use XML::LibXML;
use XML::LibXSLT;

my $U = 'OpenILS::Application::AppUtils';

my (
    $bootstrap,
    $base_url,
    $repository_identifier,
    $repository_name,
    $admin_email,
    $earliest_datestamp,
    $deleted_record,
    $max_count,
    $granularity,
    $scheme,
    $delimiter,
    $sample_identifier,
    $oai_metadataformats,
    $oai_sets,
    $parser,
    $xslt
);


sub import {

    my $self = shift;
    $bootstrap = shift;
}


sub child_init {

    OpenSRF::System->bootstrap_client( config_file => $bootstrap );

    my $idl = OpenSRF::Utils::SettingsClient->new->config_value('IDL');
    Fieldmapper->import(IDL => $idl);
    OpenILS::Utils::CStoreEditor->init; # just in case

    $parser = new XML::LibXML;
    $xslt = new XML::LibXSLT;

    my $app_settings = OpenSRF::Utils::SettingsClient->new->config_value(apps => 'open-ils.supercat')->{'app_settings'}->{'oai'};
    $base_url = $app_settings->{'base_url'} || 'localhost';
    $base_url =~/(.*)\/$/ ; # Keep all minus the trailing forward slash.
    $repository_identifier = $app_settings->{'repository_identifier'} || 'localhost';
    $repository_name = $app_settings->{'repository_name'} || 'A name';
    $admin_email = $app_settings->{'admin_email'} || 'adminEmail@' . $repository_identifier ;
    $earliest_datestamp =  $app_settings->{'earliest_datestamp'} || '0001-01-01' ;
    $deleted_record = $app_settings->{'deleted_record'} || 'yes' ;
    $max_count = $app_settings->{'max_count'} || 50;
    $granularity = $app_settings->{'granularity' } || 'YYYY-MM-DDThh:mm:ss';
    $scheme = $app_settings->{'scheme'} || 'oai';
    $delimiter = $app_settings->{'delimiter'} || ':';
    $sample_identifier = $app_settings->{'sample_identifier'} || $scheme . $delimiter . $repository_identifier . $delimiter . '12345' ;

    $logger->info('Default OAI repo settings in place, loading sets...');

    _load_oaisets_biblio();
    _load_oaisets_authority();
    _load_oai_metadataformats();

    $logger->info('... sets loaded.');

    return Apache2::Const::OK;
}


sub handler {

    my $apache = shift;
    return Apache2::Const::DECLINED if (-e $apache->filename);

    my $cgi = new CGI;
    my $record_class;
    if ( $cgi->path_info =~ /\/(authority|biblio)/ ) {
        $record_class = $1 ;
    } else {
        return Apache2::Const::NOT_FOUND ;
    }

    my %attr = $cgi->Vars();
    my $requestURL = $base_url
        . '/' . $record_class
        . '?'
        . join('&', map { "$_=$attr{$_}" } keys %attr);
    $logger->info('Request url=' . $requestURL ) ;

    my $response;
    my @errors = validate_request( %attr );
    if ( !@errors ) {

        # Retrieve our parameters
        my $verb = delete( $attr{verb} );
        my $identifier = $attr{identifier};
        my $metadataPrefix = $attr{metadataPrefix} ;
        my $from = $attr{from};
        my $until = $attr{'until'};
        my $set = $attr{set};
        my $resumptionToken = decode_base64($attr{resumptionToken} ) if $attr{resumptionToken};
        my $offset = 0 ;
        if ( $resumptionToken ) {
            ($metadataPrefix, $from, $until, $set, $offset) = split( '\$', $resumptionToken );
        }

        # Is the set valid ?
        if ( $set ) {
            my $_set = $oai_sets->{$set};
            if ( $_set && $_set->{id} && $_set->{record_class} eq $record_class) {
                $set = $_set->{id} ;
            } else {
                push @errors, new HTTP::OAI::Error(code=>'noRecordsMatch', message=>"Set argument doesn't match any sets. The setSpec was '$set'") ;
            }
        }

        # Are the from and until ranges aligned ?
        if ( $from && $until ) {
            my $_from = $from ;
            my $_until = $until ;
            $_from =~ s/[-T:\.\+Z]//g ; # '2001-02-03T04:05:06Z' becomes '20010203040506'
            $_until =~ s/[-T:\.\+Z]//g ;
            push @errors, new HTTP::OAI::Error(code=>'badArgument', message=>'Bad date values, must have from<=until') unless ($_from <= $_until);
        }

        # Is this metadataformat available ?
        push @errors, new HTTP::OAI::Error(code=>'cannotDisseminateFormat', message=>'The metadata format identified by the value given for the metadataPrefix argument is not supported by the item or by the repository') unless ( ($verb eq 'ListMetadataFormats' || $verb eq 'ListSets' || $verb eq 'Identify') || $oai_metadataformats->{$metadataPrefix} );

        if ( !@errors ) {

            # Now prepare the response
            if ( $verb eq 'ListRecords' ) {
                $response = listRecords( $record_class, $requestURL, $from, $until, $set, $metadataPrefix, $offset);
            }
            elsif ( $verb eq 'ListMetadataFormats' ) {
                $response = listMetadataFormats();
            }
            elsif ( $verb eq 'ListSets' ) {
                $response = listSets( $record_class, $requestURL );
            }
            elsif ( $verb eq 'GetRecord' ) {
                $response = getRecord( $record_class, $requestURL, $identifier, $metadataPrefix, $set);
            }
            elsif ( $verb eq 'ListIdentifiers' ) {
                $response = listIdentifiers( $record_class, $requestURL, $from, $until, $set, $metadataPrefix, $offset);
            }
            else { # Identify
                $response = identify($record_class);
            }
        }
    }

    if ( @errors ) {
        $response = HTTP::OAI::Response->new( requestURL => $requestURL );
        $response->errors(@errors);
    }

    $cgi->header(-type=>'text/xml', -charset=>'utf-8');
    $cgi->print($response->toDOM->toString());

    return Apache2::Const::OK;
}


sub identify {

    my $record_class = shift;

    my $response = HTTP::OAI::Identify->new(
        protocolVersion     => '2.0',
        baseURL             => $base_url . '/' . $record_class,
        repositoryName      => $repository_name,
        adminEmail          => $admin_email,
        MaxCount            => $max_count,
        granularity         => $granularity,
        earliestDatestamp   => $earliest_datestamp,
        deletedRecord       => $deleted_record
    );

    $response->description(
        HTTP::OAI::Metadata::OAI_Identifier->new(
            'scheme', $scheme,
            'repositoryIdentifier' , $repository_identifier,
            'delimiter', $delimiter,
            'sampleIdentifier', $sample_identifier
        )
    );

    return $response;
}


sub listMetadataFormats {

    my $response = HTTP::OAI::ListMetadataFormats->new();
    foreach my $metadataPrefix (keys %$oai_metadataformats) {
        my $metadata_format = $oai_metadataformats->{$metadataPrefix} ;
        $response->metadataFormat( HTTP::OAI::MetadataFormat->new(
           metadataPrefix    => $metadataPrefix,
           schema            => $metadata_format->{schema},
           metadataNamespace => $metadata_format->{metadataNamespace}
        ) );
    }

    return $response;
}


sub listSets {

    my ($record_class, $requestURL ) = @_;

    if ($oai_sets) {
        my $response = HTTP::OAI::ListSets->new( );
        foreach my $key (keys %$oai_sets) {
            my $set = $oai_sets->{$key} ;
            if ( $set && $set->{setSpec} && $set->{record_class} eq $record_class ) {
                $response->set(
                    HTTP::OAI::Set->new(
                        setSpec => $set->{setSpec},
                        setName => $set->{setName}
                    )
                );
            }
        }
        return $response;
    } else {
        my @errors = (new HTTP::OAI::Error(code=>'noSetHierarchy', message=>'The repository does not support sets.') ) ;
        my $response = HTTP::OAI::Response->new( requestURL => $requestURL );
        $response->errors(@errors);
        return $response;
    }
}


sub getRecord {

    my ($record_class, $requestURL, $identifier, $metadataPrefix, $set ) = @_;

    my $response ;
    my @errors;

    # Do we have a valid identifier ?
    my $regex_identifier = "^${scheme}${delimiter}${repository_identifier}${delimiter}([0-9]+)\$";
    if ( $identifier =~ /$regex_identifier/i ) {
        my $rec_id = $1 ;

        # Do we have a record ?
        my $record = $U->simplereq('open-ils.supercat','open-ils.supercat.oai.list.retrieve', $record_class, $rec_id, undef, undef, undef, 1, $deleted_record);
        if (@$record) {
            $response = HTTP::OAI::GetRecord->new();
            $response->record(_record($record_class, $$record[0], $metadataPrefix, $set));
        } else {
            push @errors, new HTTP::OAI::Error(code=>'idDoesNotExist', message=>'The value of the identifier argument is unknown or illegal in this repository.') ;
        }
    }
    else {
         push @errors, new HTTP::OAI::Error(code=>'idDoesNotExist', message=>'The value of the identifier argument is unknown or illegal in this repository.') ;
    }

    if (@errors) {
        $response = HTTP::OAI::Response->new( requestURL => $requestURL );
        $response->errors(@errors);
    }

    return $response;
}


sub listIdentifiers {

    my ($record_class, $requestURL, $from, $until, $set, $metadataPrefix, $offset ) = @_;
    my $response;

    my $r = $U->simplereq('open-ils.supercat','open-ils.supercat.oai.list.retrieve', $record_class, $offset, $from, $until, $oai_sets->{$set}->{setSpec}, $max_count, $deleted_record);
    if (@$r) {
        my $cursor = 0 ;
        $response = HTTP::OAI::ListIdentifiers->new();
        for my $record (@$r) {
            if ( $cursor++ == $max_count ) {
                my $token = new HTTP::OAI::ResumptionToken( resumptionToken => encode_base64(join( '$', $metadataPrefix, $from, $until, $oai_sets->{$set}->{setSpec}, $record->rec_id ), '' ) ) ;
                $token->cursor($offset);
                $response->resumptionToken($token) ;
            } else {
                $response->identifier( _header($record_class, $record)) ;
            }
        }
    } else {
        my @errors = (new HTTP::OAI::Error(code=>'noRecordsMatch', message=>'The combination of the values of the from, until, set, and metadataPrefix arguments results in an empty list.') ) ;
        $response = HTTP::OAI::Response->new( requestURL => $requestURL );
        $response->errors(@errors);
    }

    return $response ;
}


sub listRecords {

    my ($record_class, $requestURL, $from, $until, $set, $metadataPrefix, $offset ) = @_;
    my $response;

    my $r = $U->simplereq('open-ils.supercat','open-ils.supercat.oai.list.retrieve', $record_class, $offset, $from, $until, $oai_sets->{$set}->{setSpec}, $max_count, $deleted_record);
    if (@$r) {
        my $cursor = 0 ;
        $response = HTTP::OAI::ListRecords->new();
        for my $record (@$r) {
            if ( $cursor++ == $max_count ) {
                my $token = new HTTP::OAI::ResumptionToken( resumptionToken => encode_base64(join( '$', $metadataPrefix, $from, $until, $oai_sets->{$set}->{setSpec}, $record->rec_id ), '' ) ) ;
                $token->cursor($offset);
                $response->resumptionToken($token) ;
            } else {
                $response->record(_record($record_class, $record, $metadataPrefix, $set));
            }
        }
    } else {
        my @errors = (new HTTP::OAI::Error(code=>'noRecordsMatch', message=>'The combination of the values of the from, until, set, and metadataPrefix arguments results in an empty list.') ) ;
        $response = HTTP::OAI::Response->new( requestURL => $requestURL );
        $response->errors(@errors);
    }

    return $response ;
}


sub _header {

    my ($record_class, $o) = @_;
    my @set_spec;

    my $status = 'deleted' if ($o->deleted eq 't');
    my $s = $o->set_spec; # Here we get an array that was parsed as a string like "{1,2,3,4}"
    $s =~ s/[{}]//g ;     # We remove the {}
    foreach (split(',', $s)) { # and turn this into an array.
        my $_set = $oai_sets->{$_};
        push @set_spec, $_set->{setSpec} if ( $_set && $_set->{record_class} eq $record_class) ;
    }

    return new HTTP::OAI::Header(
            identifier  => $scheme . $delimiter . $repository_identifier . $delimiter . $o->rec_id,
            datestamp   => substr($o->datestamp, 0, 19) . 'Z',
            status      => $status,
            setSpec     => \@set_spec
        )
}


sub _record {

    my ($record_class, $o, $metadataPrefix, $set ) = @_;

    my $record = HTTP::OAI::Record->new();
    $record->header( _header($record_class, $o) );

    if ( $o->deleted eq 'f' ) {
        my $md = new HTTP::OAI::Metadata() ;
        my $xml = $U->simplereq('open-ils.supercat','open-ils.supercat.oai.' . $record_class . '.retrieve', $o->rec_id, $metadataPrefix, $oai_sets->{$set}->{setSpec});
        $xml =~ s/^<\?xml[^?]+?\?>//;
        $md->dom( $parser->parse_string('<metadata>' . $xml . '</metadata>') ); # Not sure why I need to add the metadata element,
        $record->metadata( $md );                                               # because I expect ->metadata() would provide the wrapper for it.
    }

    return $record ;
}


# _load_oaisets_authority
# Populate the $oai_sets hash with the sets for authority records.
# oai_sets = {id\setSpec => {id, setSpec, setName, record_class = 'authority' }}
sub _load_oaisets_authority {

    my $axes = $U->simplereq('open-ils.cstore','open-ils.cstore.direct.authority.browse_axis.search.atomic', {code => {'!=' => undef } } );

    for my $o (@$axes) {
        $oai_sets->{$o->code} = {
           id => $o->code,
           setSpec => $o->code,
           setName => $o->description, # description is more verbose than $o->name
           record_class => 'authority'
        };
    }
}


# _load_oaisets_biblio
# Populate the $oai_sets hash with the sets for bibliographic records. Those are org_type records
# oai_sets = {id\setSpec => {id, setSpec, setName, record_class = 'biblio' }}
my $org_tree;
my $bib_sources;
sub _load_oaisets_biblio {

    my $node = shift;
    my $parent = shift;

    if (!$node) {
        $org_tree ||= $U->get_org_tree;
        $bib_sources ||= $U->simplereq('open-ils.cat','open-ils.cat.bib_sources.retrieve.all');
        
        $node = $org_tree;
    }

    return unless ($node->opac_visible =~ /^[y1t]+/i);


    my $ou_hierarchy_string = ($parent) ? $parent . ':' . $node->shortname : $node->shortname ;
    $logger->info('Registering setSpec list for ' . $ou_hierarchy_string);

    my $cspec = 'COPIES:'.$ou_hierarchy_string;
    $oai_sets->{$cspec} = {id => 'C'.$node->id, record_class => 'biblio' };
    $oai_sets->{'C'.$node->id} = {setSpec => $cspec, setName => $node->name . ' / by copies', record_class => 'biblio' };

    my $lspec = 'LURIS:'.$ou_hierarchy_string;
    $oai_sets->{$lspec} = {id => 'L'.$node->id, record_class => 'biblio' };
    $oai_sets->{'L'.$node->id} = {setSpec => $lspec, setName => $node->name . ' / by LURIs', record_class => 'biblio' };

    my $clspec = $cspec . '!' . $lspec;
    $oai_sets->{$clspec} = {id => 'CL'.$node->id, record_class => 'biblio' };
    $oai_sets->{'CL'.$node->id} = {setSpec => $clspec, setName => $node->name . ' / by copies and LURIs', record_class => 'biblio' };


    my $source_string;
    for my $s (@$bib_sources) {

        my $sspec = 'SOURCES:'.$s->source;
        $oai_sets->{$sspec} = {id => 'S'.$s->id, record_class => 'biblio' };
        $oai_sets->{'S'.$s->id} = {setSpec => $sspec, setName => $s->source . ' / by source', record_class => 'biblio' };

        my $csspec = $cspec . '!' . $sspec;
        $oai_sets->{$csspec} = {id => $s->id.'CS'.$node->id, record_class => 'biblio' };
        $oai_sets->{$s->id.'CS'.$node->id} = {setSpec => $csspec, setName => $node->name . ' / by copies and source', record_class => 'biblio' };

        my $lsspec = $lspec . '!' . $sspec;
        $oai_sets->{$lsspec} = {id => $s->id.'LS'.$node->id, record_class => 'biblio' };
        $oai_sets->{$s->id.'LS'.$node->id} = {setSpec => $lsspec, setName => $node->name . ' / by LURIs and source', record_class => 'biblio' };

        my $clsspec = $clspec . '!' . $sspec;
        $oai_sets->{$clsspec} = {id => $s->id.'CLS'.$node->id, record_class => 'biblio' };
        $oai_sets->{$s->id.'CLS'.$node->id} = {setSpec => $clsspec, setName => $node->name . ' / by copies, LURIs, and source', record_class => 'biblio' };

    }

    my $kids = $node->children;
    _load_oaisets_biblio($_, $ou_hierarchy_string) for (@$kids);
}


# _load_oai_metadataformats
# Populate the $oai_metadataformats hash with the supported metadata formats:
# oai_metadataformats = { metadataPrefix => { schema, metadataNamespace } }
sub _load_oai_metadataformats {

    my $list = $U->simplereq('open-ils.supercat','open-ils.supercat.oai.record.formats');
    for my $record_browse_format ( @$list ) {
        my %h = %$record_browse_format ;
        my $metadataPrefix = (keys %h)[0] ;
        $oai_metadataformats->{$metadataPrefix} = {
           schema            => $h{$metadataPrefix}->{'namespace_uri'},
           metadataNamespace => $h{$metadataPrefix}->{'schema_location'}
        };
    }
}

1;
