package OpenILS::Application::Cat::Authority;
use strict; use warnings;
use base qw/OpenILS::Application/;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Application::Cat::AuthCommon;
use OpenSRF::Utils::Logger qw($logger);
use OpenILS::Application::AppUtils;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Const qw/:const/;
use OpenILS::Event;
my $U = 'OpenILS::Application::AppUtils';
my $MARC_NAMESPACE = 'http://www.loc.gov/MARC21/slim';


# generate a MARC XML document from a MARC XML string
sub marc_xml_to_doc {
	my $xml = shift;
	my $marc_doc = XML::LibXML->new->parse_string($xml);
	$marc_doc->documentElement->setNamespace($MARC_NAMESPACE, 'marc', 1);
	$marc_doc->documentElement->setNamespace($MARC_NAMESPACE);
	return $marc_doc;
}


__PACKAGE__->register_method(
	method	=> 'import_authority_record',
	api_name	=> 'open-ils.cat.authority.record.import',
);

sub import_authority_record {
    my($self, $conn, $auth, $marc_xml, $source) = @_;
	my $e = new_editor(authtoken=>$auth, xact=>1);
	return $e->die_event unless $e->checkauth;
	return $e->die_event unless $e->allowed('CREATE_AUTHORITY_RECORD');
    my $rec = OpenILS::Application::Cat::AuthCommon->import_authority_record($marc_xml, $source);
    $e->commit unless $U->event_code($rec);
    return $rec;
}

__PACKAGE__->register_method(
    method => 'create_authority_record_from_bib_field',
    api_name => 'open-ils.cat.authority.record.create_from_bib',
    signature => {
        desc => q/Create an authority record entry from a field in a bibliographic record/,
        params => q/
            @param field A hash representing the field to control, consisting of: { tag: string, ind1: string, ind2: string, subfields: [ [code, value] ... ] }
            @param identifier A MARC control number identifier
            @param authtoken A valid authentication token
            @returns The new record object 
 /}
);

__PACKAGE__->register_method(
    method => 'create_authority_record_from_bib_field',
    api_name => 'open-ils.cat.authority.record.create_from_bib.readonly',
    signature => {
        desc => q/Creates MARCXML for an authority record entry from a field in a bibliographic record/,
        params => q/
            @param field A hash representing the field to control, consisting of: { tag: string, ind1: string, ind2: string, subfields: [ [code, value] ... ] }
            @param identifier A MARC control number identifier
            @returns The MARCXML for the authority record
 /}
);

sub create_authority_record_from_bib_field {
    my($self, $conn, $field, $cni, $auth) = @_;

    # Control number identifier should have been passed in
    if (!$cni) {
        $cni = 'UNSET';
    }

    # Change the first character of the incoming bib field tag to a '1'
    # for use in our authority record; close enough for now?
    my $tag = $field->{'tag'};
    $tag =~ s/^./1/;

    my $ind1 = $field->{ind1} || ' ';
    my $ind2 = $field->{ind2} || ' ';

    my $control = qq{<datafield tag="$tag" ind1="$ind1" ind2="$ind2">};
    foreach my $sf (@{$field->{subfields}}) {
        my $code = $sf->[0];
        my $val = $U->entityize($sf->[1]);
        $control .= qq{<subfield code="$code">$val</subfield>};
    }
    $control .= '</datafield>';

    # ARN, or "authority record number", used to need to be unique across the database.
    # Of course, we have no idea what's in the database, and if the
    # cat.maintain_control_numbers flag is set to "TRUE" then the 001 will
    # be reset to the record ID anyway.
    my $arn = 'AUTOGEN-' . time();

    # Placeholder MARCXML; 
    #   001/003 can be be properly filled in via database triggers
    #   005 will be filled in automatically at creation time
    #   008 needs to be set by a cataloguer (could be some OU settings, I suppose)
    #   040 should come from OU settings / OU shortname
    #   
    my $marc_xml = <<MARCXML;
<record xmlns:marc="http://www.loc.gov/MARC21/slim" xmlns="http://www.loc.gov/MARC21/slim"><leader>     nz  a22     o  4500</leader>
<controlfield tag="001">$arn</controlfield>
<controlfield tag="008">      ||||||||||||||||||||||||||||||||||</controlfield>
<datafield tag="040" ind1=" " ind2=" "><subfield code="a">$cni</subfield><subfield code="c">$cni</subfield></datafield>
$control
</record>
MARCXML

    if ($self->api_name =~ m/readonly$/) {
        return $marc_xml;
    } else {
        my $e = new_editor(authtoken=>$auth, xact=>1);
        return $e->die_event unless $e->checkauth;
        return $e->die_event unless $e->allowed('CREATE_AUTHORITY_RECORD');
        my $rec = OpenILS::Application::Cat::AuthCommon->import_authority_record($e, $marc_xml);
        $e->commit unless $U->event_code($rec);
        return $rec;
    }
}

__PACKAGE__->register_method(
	method	=> 'overlay_authority_record',
	api_name	=> 'open-ils.cat.authority.record.overlay',
);

sub overlay_authority_record {
    my($self, $conn, $auth, $rec_id, $marc_xml, $source) = @_;
	my $e = new_editor(authtoken=>$auth, xact=>1);
	return $e->die_event unless $e->checkauth;
	return $e->die_event unless $e->allowed('UPDATE_AUTHORITY_RECORD');
    my $rec = OpenILS::Application::Cat::AuthCommon->overlay_authority_record($rec_id, $marc_xml, $source);
    $e->commit unless $U->event_code($rec);
    return $rec;

}

__PACKAGE__->register_method(
	method	=> 'retrieve_authority_record',
	api_name	=> 'open-ils.cat.authority.record.retrieve',
    signature => {
        desc => q/Retrieve an authority record entry/,
        params => [
            {desc => q/hash of options.  Options include "clear_marc" which clears
                the MARC xml from the record before it is returned/}
        ]
    }
);
sub retrieve_authority_record {
    my($self, $conn, $auth, $rec_id, $options) = @_;
	my $e = new_editor(authtoken=>$auth);
	return $e->die_event unless $e->checkauth;
    my $rec = $e->retrieve_authority_record($rec_id) or return $e->event;
    $rec->clear_marc if $$options{clear_marc};
    return $rec;
}

__PACKAGE__->register_method(
	method	=> 'batch_retrieve_authority_record',
	api_name	=> 'open-ils.cat.authority.record.batch.retrieve',
    stream => 1,
    signature => {
        desc => q/Retrieve a set of authority record entry objects/,
        params => [
            {desc => q/hash of options.  Options include "clear_marc" which clears
                the MARC xml from the record before it is returned/}
        ]
    }
);
sub batch_retrieve_authority_record {
    my($self, $conn, $auth, $rec_id_list, $options) = @_;
	my $e = new_editor(authtoken=>$auth);
	return $e->die_event unless $e->checkauth;
    for my $rec_id (@$rec_id_list) {
        my $rec = $e->retrieve_authority_record($rec_id) or return $e->event;
        $rec->clear_marc if $$options{clear_marc};
        $conn->respond($rec);
    }
    return undef;
}

__PACKAGE__->register_method(
    method    => 'count_linked_bibs',
    api_name  => 'open-ils.cat.authority.records.count_linked_bibs',
    signature => q/
        Counts the number of bib records linked to each authority record in the input list
        @param records Array of authority records to return counts
        @return A list of hashes containing the authority record ID ("id") and linked bib count ("bibs")
    /
);

sub count_linked_bibs {
    my( $self, $conn, $records ) = @_;

    my $editor = new_editor();

    my $link_count;
    my @clean_records;
    for my $auth ( @$records ) {
        # Protection against SQL injection? Might be overkill.
        my $intauth = int($auth);
        if ($intauth) {
            push(@clean_records, $intauth);
        }
    }
    return $link_count if !@clean_records;
    
    $link_count = $editor->json_query({
        "select" => {
            "abl" => [
                {
                    "column" => "authority"
                },
                {
                    "alias" => "bibs",
                    "transform" => "count",
                    "column" => "bib",
                    "aggregate" => 1
                }
            ]
        },
        "from" => "abl",
        "where" => { "authority" => \@clean_records }
    });

    return $link_count;
}

1;
