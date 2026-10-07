--Upgrade Script for 3.17.5 to 3.18-beta
\set eg_version '''3.18-beta'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.18-beta', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1524', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   695,
   'ADMIN_CALL_NUMBER_CLASS',
   oils_i18n_gettext(695,
     'Allow updates to call number classification names, normalizers, and fields.', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'ADMIN_CALL_NUMBER_CLASS');

CREATE OR REPLACE FUNCTION evergreen.function_exists(function_name TEXT) RETURNS BOOLEAN AS $$
  SELECT EXISTS (SELECT 1 FROM information_schema.routines WHERE CONCAT(routine_schema, '.', routine_name) = function_name);
$$
LANGUAGE SQL
VOLATILE;

ALTER TABLE asset.call_number_class ADD CONSTRAINT asset_call_number_class_has_valid_normalizer
    CHECK (evergreen.function_exists(normalizer));


SELECT evergreen.upgrade_deps_block_check('1528', :eg_version);

CREATE OR REPLACE FUNCTION vandelay.replace_field
    (target_xml TEXT, source_xml TEXT, field TEXT) RETURNS TEXT AS $_$

    use strict;
    use MARC::Record;
    use MARC::Field;
    use MARC::File::XML (BinaryEncoding => 'UTF-8');
    use MARC::Charset;

    MARC::Charset->assume_unicode(1);

    my $target_xml = shift;
    my $source_xml = shift;
    my $field_spec = shift;

    my $target_r = MARC::Record->new_from_xml($target_xml);
    my $source_r = MARC::Record->new_from_xml($source_xml);

    return $target_xml unless $target_r && $source_r;

    # Extract the field_spec components into MARC tags, subfields,
    # and regex matches.  Copied wholesale from vandelay.strip_field()

    my @field_list = split(',', $field_spec);
    my %fields;
    for my $f (@field_list) {
        $f =~ s/^\s*//; $f =~ s/\s*$//;
        if ($f =~ /^(.{3})(\w*)(?:\[([^]]*)\])?$/) {
            my $field = $1;
            $field =~ s/\s+//;
            my $sf = $2;
            $sf =~ s/\s+//;
            my $matches = $3;
            $matches =~ s/^\s*//; $matches =~ s/\s*$//;
            $fields{$field} = { sf => [ split('', $sf) ] };
            if ($matches) {
                for my $match (split('&&', $matches)) {
                    $match =~ s/^\s*//; $match =~ s/\s*$//;
                    my ($msf,$mre) = split('~', $match);
                    if (length($msf) > 0 and length($mre) > 0) {
                        $msf =~ s/^\s*//; $msf =~ s/\s*$//;
                        $mre =~ s/^\s*//; $mre =~ s/\s*$//;
                        $fields{$field}{match}{$msf} = qr/$mre/;
                    }
                 }
            }
        }
    }

    # Returns a flat list of subfield (code, value, code, value, ...)
    # suitable for adding to a MARC::Field.
    sub generate_replacement_subfields {
        my ($source_field, $target_field, @controlled_subfields) = @_;

        # Performing a wholesale field replacment.
        # Use the entire source field as-is.
        return map {$_->[0], $_->[1]} $source_field->subfields
            unless @controlled_subfields;

        my @new_subfields;

        # Iterate over all target field subfields:
        # 1. Keep uncontrolled subfields as is.
        # 2. Replace values for controlled subfields when a
        #    replacement value exists on the source record.
        # 3. Delete values for controlled subfields when no
        #    replacement value exists on the source record.

        my %sf_index_map;
        for my $target_sf ($target_field->subfields) {
            my $subfield = $target_sf->[0];
            my $target_val = $target_sf->[1];

            if (grep {$_ eq $subfield} @controlled_subfields) {
                $sf_index_map{$subfield} //= -1; # create the slot if not defined
                $sf_index_map{$subfield}++;      # increment (even to 0) on each pass through the target list
                if (my $source_val = ($source_field->subfield($subfield))[$sf_index_map{$subfield}]) {
                    # We have a replacement value
                    push(@new_subfields, $subfield, $source_val);
                } else {
                    # no replacement value for controlled subfield, drop it.
                }
            } else {
                # Field is not controlled.  Copy it over as-is.
                push(@new_subfields, $subfield, $target_val);
            }
        }

        # Iterate over all subfields in the source field and back-fill
        # any values that exist only in the source field.  Insert these
        # subfields in the same relative position they exist in the
        # source field.
 
        my @seen_subfields;
        for my $source_sf ($source_field->subfields) {
            my $subfield = $source_sf->[0];
            my $source_val = $source_sf->[1];
            push(@seen_subfields, $subfield);

            # target field already contains this subfield,
            # so it would have been addressed above.
            next if $target_field->subfield($subfield);

            # Ignore uncontrolled subfields.
            next unless grep {$_ eq $subfield} @controlled_subfields;

            # Adding a new subfield.  Find its relative position and add
            # it to the list under construction.  Work backwards from
            # the list of already seen subfields to find the best slot.

            my $done = 0;
            for my $seen_sf (reverse(@seen_subfields)) {
                my $idx = @new_subfields;
                for my $new_sf (reverse(@new_subfields)) {
                    $idx--;
                    next if $idx % 2 == 1; # sf codes are in the even slots

                    if ($new_subfields[$idx] eq $seen_sf) {
                        splice(@new_subfields, $idx + 2, 0, $subfield, $source_val);
                        $done = 1;
                        last;
                    }
                }
                last if $done;
            }

            # if no slot was found, add to the end of the list.
            push(@new_subfields, $subfield, $source_val) unless $done;
        }

        return @new_subfields;
    }

    # MARC tag loop
    for my $f (keys %fields) {
        my $tag_idx = -1;
        my @target_fields = $target_r->field($f);

        if (!@target_fields and !defined($fields{$f}{match})) {
            # we will just add the source fields
            # unless they require a target match.
            my @add_these = map { $_->clone } $source_r->field($f);
            $target_r->insert_fields_ordered( @add_these );
        }

        for my $target_field (@target_fields) { # This will not run when the above "if" does.

            # field spec contains a regex for this field.  Confirm field on
            # target record matches the specified regex before replacing.
            if (exists($fields{$f}{match})) {
                my @match_list;
                for my $match_key_sf_code ( keys %{$fields{$f}{match}} ) {
                    # We loop here because there might be multiple SFs, such as multiple
                    # $0s in an authority controlled datafield, where one has the EG-special
                    # format, and others are links to external heading data.
                    for my $sf_content ($target_field->subfield($match_key_sf_code)) {
                        if ($sf_content =~ $fields{$f}{match}{$match_key_sf_code}) {
                            push @match_list, $sf_content;
                        }
                    }
                }
                next unless (scalar(@match_list) >= scalar(keys %{$fields{$f}{match}}));
            }

            my @new_subfields;
            my @controlled_subfields = @{$fields{$f}{sf}};

            # If the target record has multiple matching bib fields,
            # replace them from matching fields on the source record
            # in a predictable order to avoid replacing with them with
            # same source field repeatedly.
            my @source_fields = $source_r->field($f);
            my $source_field = $source_fields[++$tag_idx];

            if (!$source_field && @controlled_subfields) {
                # When there are more target fields than source fields
                # and we are replacing values for subfields and not
                # performing wholesale field replacment, use the last
                # available source field as the input for all remaining
                # target fields.
                $source_field = $source_fields[$#source_fields];
            }

            if (!$source_field) {
                # No source field exists.  Delete all affected target
                # data.  This is a little bit counterintuitive, but is
                # backwards compatible with the previous version of this
                # function which first deleted all affected data, then
                # replaced values where possible.
                if (@controlled_subfields) {
                    $target_field->delete_subfield($_) for @controlled_subfields;
                } else {
                    $target_r->delete_field($target_field);
                }
                next;
            }

            my @new_subfields = generate_replacement_subfields(
                $source_field, $target_field, @controlled_subfields);

            # Build the replacement field from scratch.
            my $replacement_field = MARC::Field->new(
                $target_field->tag,
                $target_field->indicator(1),
                $target_field->indicator(2),
                @new_subfields
            );

            $target_field->replace_with($replacement_field);
        }
    }

    $target_xml = $target_r->as_xml_record;
    $target_xml =~ s/^<\?.+?\?>$//mo;
    $target_xml =~ s/\n//sgo;
    $target_xml =~ s/>\s+</></sgo;

    return $target_xml;

$_$ LANGUAGE PLPERLU;



SELECT evergreen.upgrade_deps_block_check('1529', :eg_version);

INSERT INTO openapi.endpoint_set
(name, description, active, rate_limit)
VALUES
('coded_value_maps', 'Methods for retrieving coded value maps', TRUE, NULL),
('search', 'Methods for searching the catalog of bibliographic records', 't', NULL)
ON CONFLICT DO NOTHING;

-- coded_value_maps and search do not need extra permissions.

INSERT INTO openapi.endpoint
(operation_id, path, http_method, summary, method_source, method_name,
 method_params)
VALUES (
  'retrieveCodedValueMap',
  '/coded_value_map/:id',
  'get',
  'Retrieve one coded value map by id',
  'OpenILS::OpenAPI::Controller::ccvm',
  'retrieve_ccvm',
  'param.id'
) ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint_param
(endpoint, name, in_part, schema_type, required)
VALUES
('retrieveCodedValueMap', 'id', 'path', 'integer', TRUE)
ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint_response (endpoint, fm_type)
VALUES ('retrieveCodedValueMap', 'ccvm') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint
(operation_id, path, http_method, summary, method_source, method_name,
 method_params)
VALUES (
  'codedValueMapsByCtype',
  '/coded_value_maps/by_ctype/:ctype',
  'get',
  'Retrieve coded value maps by ctype',
  'OpenILS::OpenAPI::Controller::ccvm',
  'ccvm_by_ctype',
  'param.ctype'
) ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint_param
(endpoint, name, in_part, schema_type, required)
VALUES
('codedValueMapsByCtype', 'ctype', 'path', 'string', TRUE)
ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint_response (endpoint,schema_type,array_items)
VALUES ('codedValueMapsByCtype','array','object') ON CONFLICT DO NOTHING;

-- New search endpoint(s)
INSERT INTO openapi.endpoint
(operation_id, path, http_method, summary, method_source, method_name, method_params)
VALUES (
    'searchMulticlass',
    '/search/multiclass',
    'get',
    'Search bibliographic records similar to the OPAC',
    'OpenILS::OpenAPI::Controller::search',
    'multiclass_search',
    'eg_auth_token every_param.title every_param.author every_param.subject every_param.series every_param.keyword every_param.identifier every_param.isbn every_param.issn param.org_unit param.depth param.limit param.offset param.sort param.sort_dir param.tag_circulated_records param.query param.docache'
) ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint_param
(endpoint, name, required, in_part, schema_type, default_value)
VALUES
('searchMulticlass', 'title', FALSE, 'query', 'string', NULL),
('searchMulticlass', 'author', FALSE, 'query', 'string', NULL),
('searchMulticlass', 'subject', FALSE, 'query', 'string', NULL),
('searchMulticlass', 'series', FALSE, 'query', 'string', NULL),
('searchMulticlass', 'keyword', FALSE, 'query', 'string', NULL),
('searchMulticlass', 'identifier', FALSE, 'query', 'string', NULL),
('searchMulticlass', 'isbn', FALSE, 'query', 'string', NULL),
('searchMulticlass', 'issn', FALSE, 'query', 'string', NULL),
('searchMulticlass', 'query', FALSE, 'query', 'string', NULL),
('searchMulticlass', 'sort', FALSE, 'query', 'string', NULL),
('searchMulticlass', 'sort_dir', FALSE, 'query', 'string', 'ASC')
ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint_param
(endpoint, name, required, in_part, schema_type, default_value)
VALUES
('searchMulticlass', 'org_unit', FALSE, 'query', 'integer', NULL),
('searchMulticlass', 'depth', FALSE, 'query', 'integer', NULL),
('searchMulticlass', 'limit', FALSE, 'query', 'integer', '10'),
('searchMulticlass', 'offset', FALSE, 'query', 'integer', '0')
ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint_param
(endpoint, name, required, in_part, schema_type, default_value)
VALUES
('searchMulticlass', 'tag_circulated_records', FALSE, 'query', 'boolean', 'false'),
('searchMulticlass', 'docache', FALSE, 'query', 'boolean', 'true')
ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint_response (endpoint, schema_type)
VALUES ('searchMulticlass', 'object') ON CONFLICT DO NOTHING;

-- New bibs endpoint to retrieve record by identifier

INSERT INTO openapi.endpoint
(operation_id, path, http_method, summary, method_source, method_name, method_params)
VALUES (
  'bibByISBN',
  '/bibs/by_isbn/:isbn',
  'get',
  'Retrieve bib record by ISBN or other standard identifier',
  'OpenILS::OpenAPI::Controller::bib',
  'retrieve_bib',
  'param.isbn'
) ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint_param
(endpoint, name, in_part, schema_type, required)
VALUES
('bibByISBN', 'isbn', 'path', 'string', TRUE)
ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint_response
(endpoint, content_type, fm_type)
VALUES
('bibByISBN', 'application/json', 'bre')
ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint_response
(endpoint, content_type)
VALUES
('bibByISBN', 'application/xml'),
('bibByISBN', 'application/octet-stream')
ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint_set_endpoint_map (endpoint, endpoint_set)
  SELECT e.operation_id, s.name FROM openapi.endpoint e JOIN openapi.endpoint_set s ON (e.path LIKE '/'||RTRIM(s.name,'s')||'%')
ON CONFLICT DO NOTHING;


SELECT evergreen.upgrade_deps_block_check('1530', :eg_version);

--remove entry from settings table
DELETE FROM actor.org_unit_setting
WHERE name='circ.hold_stalling_hard';

--remove entries from log table
DELETE FROM config.org_unit_setting_type_log
WHERE field_name='circ.hold_stalling_hard';

--Remove unused org unit setting
DELETE FROM config.org_unit_setting_type
WHERE name='circ.hold_stalling_hard';

COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
