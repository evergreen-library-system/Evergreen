package OpenILS::Application::Cat::Authority;
use strict; use warnings;
use MARC::Record;
use MARC::File::XML (BinaryEncoding => 'utf8', RecordFormat => 'USMARC');
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
    method  => 'import_authority_record',
    api_name    => 'open-ils.cat.authority.record.import',
);

sub import_authority_record {
    my($self, $conn, $auth, $marc_xml, $source) = @_;
    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('CREATE_AUTHORITY_RECORD');
    my $rec = OpenILS::Application::Cat::AuthCommon->
        import_authority_record($e, $marc_xml, $source);
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
    method  => 'overlay_authority_record',
    api_name    => 'open-ils.cat.authority.record.overlay',
);

sub overlay_authority_record {
    my($self, $conn, $auth, $rec_id, $marc_xml, $source) = @_;
    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('UPDATE_AUTHORITY_RECORD');
    my $rec = OpenILS::Application::Cat::AuthCommon->
        overlay_authority_record($e, $rec_id, $marc_xml, $source);
    $e->commit unless $U->event_code($rec);
    return $rec;
}

__PACKAGE__->register_method(
    method  => 'retrieve_authority_record',
    api_name    => 'open-ils.cat.authority.record.retrieve',
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
    my $rec = $e->retrieve_authority_record_entry($rec_id) or return $e->event;
    $rec->clear_marc if $$options{clear_marc};
    return $rec;
}

__PACKAGE__->register_method(
    method  => 'batch_retrieve_authority_record',
    api_name    => 'open-ils.cat.authority.record.batch.retrieve',
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
        my $rec = $e->retrieve_authority_record_entry($rec_id) or return $e->event;
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

    my $link_count = [];
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

__PACKAGE__->register_method(
    "method" => "retrieve_acs",
    "api_name" => "open-ils.cat.authority.control_set.retrieve",
    "api_level" => 1,
    "stream" => 1,
    "argc" => 2,
    "signature" => {
        "desc" => q/Retrieve authority.control_set objects with fleshed
        thesauri and authority fields/,
        "params" => [
            {"name" => "limit",  "desc" => "limit (optional; default 15)", "type" => "number"},
            {"name" => "offset",  "desc" => "offset doptional; default 0)", "type" => "number"},
            {"name" => "focus",  "desc" => "optionally make sure the acs object with ID matching this value comes at the top of the result set (only works with offset 0)", "type" => "number"}
        ]
    }
);

# XXX I don't think this really needs to be protected by perms, or does it?
sub retrieve_acs {
    my $self = shift;
    my $client = shift;

    my ($limit, $offset, $focus) = map int, @_;

    $limit ||= 15;
    $offset ||= 0;
    $focus ||= undef;

    my $e = new_editor;
    my $order_by = [
        {"class" => "acs", "field" => "name"}
    ];

    # Here is the magic that let's us say that a given acsaf
    # will be our first result.
    unshift @$order_by, {
        "class" => "acs", "field" => "id",
        "transform" => "numeric_eq", "params" => [$focus],
        "direction" => "desc"
    } if $focus;

    my $sets = $e->search_authority_control_set([
        {"id" => {"!=" => undef}}, {
            "flesh" => 1,
            "flesh_fields" => {"acs" => [qw/thesauri authority_fields/]},
            "order_by" => $order_by,
            "limit" => $limit,
            "offset" => $offset
        }
    ]) or return $e->die_event;

    $e->disconnect;

    $client->respond($_) foreach @$sets;
    return undef;
}

__PACKAGE__->register_method(
    "method" => "retrieve_acsaf",
    "api_name" => "open-ils.cat.authority.control_set_authority_field.retrieve",
    "api_level" => 1,
    "stream" => 1,
    "argc" => 2,
    "signature" => {
        "desc" => q/Retrieve authority.control_set_authority_field objects with
        fleshed bib_fields and axes/,
        "params" => [
            {"name" => "limit",  "desc" => "limit (optional; default 15)", "type" => "number"},
            {"name" => "offset",  "desc" => "offset (optional; default 0)", "type" => "number"},
            {"name" => "control_set",  "desc" => "optionally constrain by value of acsaf.control_set field", "type" => "number"},
            {"name" => "focus", "desc" => "optionally make sure the acsaf object with ID matching this value comes at the top of the result set (only works with offset 0)"}
        ]
    }
);

sub retrieve_acsaf {
    my $self = shift;
    my $client = shift;

    my ($limit, $offset, $control_set, $focus) = map int, @_;

    $limit ||= 15;
    $offset ||= 0;
    $control_set ||= undef;
    $focus ||= undef;

    my $e = new_editor;
    my $where = {
        "control_set" => ($control_set ? $control_set : {"!=" => undef})
    };
    my $order_by = [
        {"class" => "acsaf", "field" => "main_entry", "direction" => "desc"},
        {"class" => "acsaf", "field" => "id"}
    ];

    unshift @$order_by, {
        "class" => "acsaf", "field" => "id",
        "transform" => "numeric_eq", "params" => [$focus],
        "direction" => "desc"
    } if $focus;

    my $fields = $e->search_authority_control_set_authority_field([
        $where, {
            "flesh" => 2,
            "flesh_fields" => {
                "acsaf" => ["bib_fields", "axis_maps"],
                "abaafm" => ["axis"]
            },
            "order_by" => $order_by,
            "limit" => $limit,
            "offset" => $offset
        }
    ]) or return $e->die_event;

    $e->disconnect;

    $client->respond($_) foreach @$fields;
    return undef;
}

__PACKAGE__->register_method(
    method => "bib_field_overlay_authority_field",
    api_name => "open-ils.cat.authority.bib_field.overlay_authority",
    api_level => 1,
    stream => 1,
    argc => 2,
    signature => {
        desc => q/Given a bib field hash and an authority field hash,
            merge the authority data for controlled fields into the 
            bib field./,
        params => [
            {name => 'Bib Field', 
                desc => '{tag:., ind1:., ind2:.,subfields:[[code, value],...]}'},
            {name => 'Authority Field', 
                desc => '{tag:., ind1:., ind2:.,subfields:[[code, value],...]}'},
            {name => 'Control Set ID',
                desc => q/Optional control set limiter.  If no control set
                    is provided, the first matching authority field
                    definition will be used./}
        ],
        return => q/The modified bib field/
    }
);

# Returns the first found field.
sub get_auth_field_by_tag {
    my ($atag, $cset_id) = @_;

    my $e = new_editor();

    my $where = {tag => $atag};

    $where->{control_set} = $cset_id if $cset_id;

    return $e->search_authority_control_set_authority_field($where)->[0];
}

sub bib_field_overlay_authority_field {
    my ($self, $client, $bib_field, $auth_field, $cset_id) = @_;

    return $bib_field unless $bib_field && $auth_field;

    my $btag = $bib_field->{'tag'};
    my $atag = $auth_field->{'tag'};

    # Find the controlled subfields.  Here we assume the authority
    # field provided should be used as the source of which subfields
    # are controlled.  If passed a set of bib and auth data that are
    # not consistent with the control set, it may produce unexpected
    # results.
    my $sf_list = '';
    my $acsaf = get_auth_field_by_tag($atag, $cset_id);

    if ($acsaf) {
        $sf_list = $acsaf->sf_list;

    } else {

        # Handle 4XX and 5XX
        (my $alt_atag = $atag) =~ s/^./1/;
        $acsaf = get_auth_field_by_tag($alt_atag, $cset_id) if $alt_atag ne $atag;

        $sf_list = $acsaf->sf_list if $acsaf;
    }

    my $subfields = [];
    my $auth_sf_zero;

    # Add the controlled authority subfields
    for my $sf (@{$auth_field->{subfields}}) {
        my $c = $sf->[0]; # subfield code
        my $v = $sf->[1]; # subfield value

        if ($c eq '0') {
            $auth_sf_zero = $v;

        } elsif (index($sf_list, $c) > -1) {
            push(@$subfields, [$c, $v]);
        }
    }

    # Add the uncontrolled bib subfields
    for my $sf (@{$bib_field->{subfields}}) {
        my $c = $sf->[0]; # subfield code
        my $v = $sf->[1]; # subfield value

        # Discard the bib '0' since the link is no longer valid, 
        # given we're replacing the contents of the field.
        if (index($sf_list, $c) < 0 && $c ne '0') {
            push(@$subfields, [$c, $v]);
        }
    }

    # The data on this authority field may link to yet 
    # another authority record.  Track that in our bib field
    # as the last subfield;
    push(@$subfields, ['0', $auth_sf_zero]) if $auth_sf_zero;

    my $new_bib_field = {
        tag => $bib_field->{tag},
        ind1 => $auth_field->{'ind1'},
        ind2 => $auth_field->{'ind2'},
        subfields => $subfields
    };

    $new_bib_field->{ind1} = $auth_field->{'ind2'} 
        if $atag eq '130' && $btag eq '130';

    return $new_bib_field;
}

__PACKAGE__->register_method(
    method    => "validate_bib_fields",
    api_name  => "open-ils.cat.authority.validate.bib_field",
    stream => 1,
    signature => {
        desc => q/Returns a stream of bib field objects with a 'valid'
        attribute added, set to 1 or 0, indicating whether the field
        has a matching authority entry.  If no control set ID is provided
        all configured control sets will be tested.  Testing will stop
        with the first positive validation./,
        params => [
            {type => 'object', name => 'Bib Fields',
                description => q/
                    List of objects like this 
                    {
                        tag: tag, 
                        ind1: ind1, 
                        ind2: ind2, 
                        subfields: [[code, value], ...]
                    }

                    For example:
srfsh# request open-ils.cat open-ils.cat.authority.validate.bib_field
  [{"tag":"600","ind1":"", "ind2":"", "subfields":[["a","shakespeare william"], ...]}]
                /
            },
            {type => 'number', name => 'Optional Control Set ID'},
        ]
    }
);

# for stub records sent to 
# open-ils.cat.authority.simple_heading
my $auth_leader = '00000czm a2200205Ka 4500';

sub validate_bib_fields {
    my ($self, $client, $bib_fields, $control_set) = @_;

    $bib_fields = [$bib_fields] unless ref $bib_fields eq 'ARRAY';

    my $e = new_editor();

    for my $bib_field (@$bib_fields) {

        $bib_field->{valid} = 0;

        my $where = {'+acsbf' => {tag => $bib_field->{tag}}};
        $where->{'+acsaf'} = {control_set => $control_set} if $control_set;

        my $auth_field_list = $e->json_query({
            select => {
                acsbf => ['authority_field'],
                acsaf => ['id', 'tag', 'sf_list', 'control_set']
            },
            from => {acsbf => {acsaf => {}}},
            where => $where,
            order_by => [
                {class => 'acsaf', field => 'main_entry', direction => 'desc'},
                {class => 'acsaf', field => 'tag'}
            ]
        });

        my @seen_subfields;
        for my $auth_field (@$auth_field_list) {

            my $sf_list = $auth_field->{sf_list};

            # Some auth fields have the same sf_list values.  Track the
            # ones we've already tested.
            next if grep {$_ eq $sf_list} @seen_subfields;

            push(@seen_subfields, $sf_list);

            my @sf_values;
            for my $subfield (@{$bib_field->{subfields}}) {
                my $code = $subfield->[0];
                my $value = $subfield->[1];

                next unless defined $value && $value ne '';

                # is this a controlled subfield?
                next unless index($sf_list, $code) > -1;

                push(@sf_values, $code, $value);
            }

            next unless @sf_values;

            my $record = MARC::Record->new;
            $record->leader($auth_leader);

            my $field = MARC::Field->new($auth_field->{tag},
                $bib_field->{ind1}, $bib_field->{ind2}, @sf_values);

            $record->append_fields($field);

            my $match = $U->simplereq(
                'open-ils.search', 
                'open-ils.search.authority.simple_heading.from_xml',
                $record->as_xml_record, $control_set);

            if ($match) {
                $bib_field->{valid} = 1;
                $bib_field->{authority_record} = $match;
                $bib_field->{authority_field} = $auth_field->{id};
                $bib_field->{control_set} = $auth_field->{control_set};
                last;
            }
        }

        # Present our findings.
        $client->respond($bib_field);
    }

    return undef;
}


__PACKAGE__->register_method(
    method    => "bib_field_authority_linking_browse",
    api_name  => "open-ils.cat.authority.bib_field.linking_browse",
    stream => 1,
    signature => {
        desc => q/Returns a stream of authority record blobs including
            information on its main heading and its see froms and see 
            alsos, based on an axis-based browse search.  This was
            initially created to move some MARC editor authority linking 
            logic to the server.  The browse axis is derived from the
            bib field data provided.
        ...
        /,
        params => [
            {type => 'object', name => 'MARC Field hash {tag:.,ind1:.,ind2:,subfields:[[code,value],.]}'},
            {type => 'number', name => 'Page size / limit'},
            {type => 'number', name => 'Page offset'},
            {type => 'string', name => 'Optional thesauri, comma separated'}
        ]
    }
);

sub get_heading_string {
    my $field = shift;

    my $heading = '';
    for my $subfield ($field->subfields) {
        $heading .= ' --' if index('xyz', $subfield->[0]) > -1;
        $heading .= ' ' if $heading;
        $heading .= $subfield->[1];
    }

    return $heading;
}

# Turns a MARC::Field into a hash and adds the field's heading string.
sub hashify_field {
    my $field = shift;
    return {
        heading => get_heading_string($field),
        tag => $field->tag,
        ind1 => $field->indicator(1),
        ind2 => $field->indicator(2),
        subfields => [$field->subfields]
    };
}

sub bib_field_authority_linking_browse {
    my ($self, $client, $bib_field, $limit, $offset, $thesauri) = @_;

    $offset ||= 0;
    $limit ||= 5;
    $thesauri ||= '';
    my $e = new_editor();

    return [] unless $bib_field;

    my $term = join(' ', map {$_->[1]} @{$bib_field->{subfields}});

    return [] unless $term;

    my $axis = $e->json_query({
        select => {abaafm => ['axis']},
        from => {acsbf => {acsaf => {join => 'abaafm'}}},
        where => {'+acsbf' => {tag => $bib_field->{tag}}},
        order_by => [
            {class => 'acsaf', field => 'main_entry', direction => 'desc'},
            {class => 'acsaf', field => 'tag'},

            # This lets us favor the 'subject' axis to the 'topic' axis.
            # Topic is a subset of subject.  It's not clear if a field
            # can link only to the 'topic' axes.  In stock EG, the one
            # 'topic' field also links to 'subject'.
            {class => 'abaafm', field => 'axis'}
        ]
    })->[0];

    return [] unless $axis && ($axis = $axis->{axis});

    # See https://bugs.launchpad.net/evergreen/+bug/1403098
    my $are_ids = $U->simplereq(
        'open-ils.supercat',
        'open-ils.supercat.authority.browse_center.by_axis.refs',
        $axis, $term, $offset, $limit, $thesauri);

    for my $are_id (@$are_ids) {

        my $are = $e->retrieve_authority_record_entry($are_id);
        my $rec = MARC::Record->new_from_xml($are->marc, 'UTF-8');

        my $main_field = $rec->field('1..');
        my $auth_org_field = $rec->field('003');
        my $auth_org = $auth_org_field ? $auth_org_field->data : undef;

        my $resp = {
            authority_id => $are_id,
            main_heading => hashify_field($main_field),
            auth_org => $auth_org,
            see_alsos => [],
            see_froms => []
        };

        for my $also_field ($rec->field('5..')) {
            push(@{$resp->{see_alsos}}, hashify_field($also_field));
        }

        for my $from_field ($rec->field('4..')) {
            push(@{$resp->{see_froms}}, hashify_field($from_field));
        }

        $client->respond($resp);
    }

    return undef;
}

1;
