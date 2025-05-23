--Upgrade Script for 3.12.6 to 3.12.7
\set eg_version '''3.12.7'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.12.7', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1424', :eg_version);

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.acq.distribution_formula', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.acq.distribution_formula',
        'Grid Config: admin.acq.distribution_formula',
        'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1427', :eg_version);

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.catalog.record.conjoined', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.catalog.record.conjoined',
        'Grid Config: catalog.record.conjoined',
        'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1428', :eg_version);

ALTER TABLE acq.exchange_rate 
	DROP CONSTRAINT exchange_rate_from_currency_fkey
	,ADD CONSTRAINT exchange_rate_from_currency_fkey FOREIGN KEY (from_currency) REFERENCES acq.currency_type (code) ON UPDATE CASCADE;

ALTER TABLE acq.exchange_rate 
	DROP CONSTRAINT exchange_rate_to_currency_fkey
	,ADD CONSTRAINT exchange_rate_to_currency_fkey FOREIGN KEY (to_currency) REFERENCES acq.currency_type (code) ON UPDATE CASCADE;

ALTER TABLE acq.funding_source
    DROP CONSTRAINT funding_source_currency_type_fkey
    ,ADD CONSTRAINT funding_source_currency_type_fkey FOREIGN KEY (currency_type) REFERENCES acq.currency_type (code) ON UPDATE CASCADE;

UPDATE acq.fund SET currency_type ='CAD' WHERE currency_type = 'CAN';
UPDATE acq.fund_debit SET origin_currency_type ='CAD' WHERE origin_currency_type = 'CAN';
UPDATE acq.provider SET currency_type ='CAD' WHERE currency_type = 'CAN';
UPDATE acq.currency_type SET code = 'CAD' WHERE code = 'CAN';

SELECT evergreen.upgrade_deps_block_check('1429', :eg_version);

UPDATE config.org_unit_setting_type
SET description = oils_i18n_gettext('circ.course_materials_brief_record_bib_source',
    'The course materials module will use this bib source for any new brief bibliographic records made inside that module. For best results, use a transcendent bib source.',
    'coust', 'description')
WHERE name='circ.course_materials_brief_record_bib_source';


SELECT evergreen.upgrade_deps_block_check('1430', :eg_version);

INSERT INTO config.print_template
    (name, label, owner, active, locale, content_type, template)
VALUES ('serials_routing_list', 'Serials routing list', 1, TRUE, 'en-US', 'text/html', '');

UPDATE config.print_template SET template = $TEMPLATE$
[% 
  SET title = template_data.title;
  SET distribution = template_data.distribution;
  SET issuance = template_data.issuance;
  SET routing_list = template_data.routing_list;
  SET stream = template_data.stream;
%] 

<p>[% title %]</p>
<p>[% issuance.label %]</p>
<p>([% distribution.holding_lib.shortname %]) [% distribution.label %] / [% stream.routing_label %] ID [% stream.id %]</p>
  <ol>
	[% FOR route IN routing_list %]
    <li>
    [% IF route.reader %]
      [% route.reader.first_given_name %] [% route.reader.family_name %]
      [% IF route.note %]
        - [% route.note %]
      [% END %]
      [% route.reader.mailing_address.street1 %]
      [% route.reader.mailing_address.street2 %]
      [% route.reader.mailing_address.city %], [% route.reader.mailing_address.state %] [% route.reader.mailing_address.post_code %]
    [% ELSIF route.department %]
      [% route.department %]
      [% IF route.note %]
        - [% route.note %]
      [% END %]
    [% END %]
    </li>
  [% END %]
  </ol>
</div>

$TEMPLATE$ WHERE name = 'serials_routing_list';


SELECT evergreen.upgrade_deps_block_check('1431', :eg_version);

--Add the new information used to calculate available_copy_ratio to the stats the function sends out
DROP TYPE IF EXISTS action.hold_stats CASCADE;
CREATE TYPE action.hold_stats AS (
    hold_count              INT,
    competing_hold_count    INT,
    copy_count              INT,
    available_count         INT,
    total_copy_ratio        FLOAT,
    available_copy_ratio    FLOAT
);

--copy_id is a numeric id from asset.copy.
--A copy is treated as unavailable if it is still age protected and belongs to a different org unit
CREATE OR REPLACE FUNCTION action.copy_related_hold_stats (copy_id BIGINT) RETURNS action.hold_stats AS $func$
DECLARE
    output                  action.hold_stats%ROWTYPE;
    hold_count              INT := 0;
    competing_hold_count    INT := 0;
    copy_count              INT := 0;
    available_count         INT := 0;
    copy                    RECORD;
    hold                    RECORD;
BEGIN

    output.hold_count := 0;
    output.competing_hold_count := 0;
    output.copy_count := 0;
    output.available_count := 0;

    --Find all unique holds considering our copy
    CREATE TEMPORARY TABLE copy_holds_tmp AS 
        SELECT  DISTINCT m.hold, m.target_copy, h.pickup_lib, h.request_lib, h.requestor, h.usr
        FROM  action.hold_copy_map m
                JOIN action.hold_request h ON (m.hold = h.id)
        WHERE m.target_copy = copy_id
                AND NOT h.frozen;
        

    --Count how many holds there are
    SELECT  COUNT( DISTINCT m.hold ) INTO hold_count
       FROM  action.hold_copy_map m
             JOIN action.hold_request h ON (m.hold = h.id)
       WHERE m.target_copy = copy_id
             AND NOT h.frozen;

    output.hold_count := hold_count;

    --Count how many holds looking at our copy would be allowed to be fulfilled by our copy (are valid competition for our copy)
    CREATE TEMPORARY TABLE competing_holds AS
        SELECT *
        FROM copy_holds_tmp
        WHERE (SELECT success FROM action.hold_request_permit_test(pickup_lib, request_lib, copy_id, usr, requestor) LIMIT 1);

    SELECT COUNT(*) INTO competing_hold_count
    FROM competing_holds;

    output.competing_hold_count := competing_hold_count;

    IF output.hold_count > 0 THEN

        --Get the total count separately in case the competing hold we find the available on is old and missed a target
        SELECT INTO output.copy_count COUNT(DISTINCT m.target_copy)
        FROM  action.hold_copy_map m
                JOIN asset.copy acp ON (m.target_copy = acp.id)
                JOIN action.hold_request h ON (m.hold = h.id)
        WHERE m.hold IN ( SELECT DISTINCT hold_copy_map.hold FROM action.hold_copy_map WHERE target_copy = copy_id ) 
        AND NOT h.frozen
        AND NOT acp.deleted;

        --'Available' means available to the same people, so we use the competing hold to test if it's available to them
        SELECT INTO hold * FROM competing_holds ORDER BY competing_holds.hold DESC LIMIT 1;

        --Assuming any competing hold can be placed on the same copies as every competing hold ; can't afford a nested loop
        --Could maybe be broken by a hold from a user with superpermissions ignoring age protections? Still using available status first as fallback.
        FOR copy IN
            SELECT DISTINCT m.target_copy AS id, acp.status
            FROM competing_holds c
                JOIN action.hold_copy_map m ON c.hold = m.hold
                JOIN asset.copy acp ON m.target_copy = acp.id
        LOOP
            --Check age protection by checking if the hold is permitted with hold_permit_test
            --Hopefully hold_matrix never needs to know if an item could circulate or there'd be an infinite loop
            IF (copy.status IN (SELECT id FROM config.copy_status WHERE holdable AND is_available)) AND
                (SELECT success FROM action.hold_request_permit_test(hold.pickup_lib, hold.request_lib, copy.id, hold.usr, hold.requestor) LIMIT 1) THEN
                    output.available_count := output.available_count + 1;
            END IF;
        END LOOP;

        output.total_copy_ratio = output.copy_count::FLOAT / output.hold_count::FLOAT;
        IF output.competing_hold_count > 0 THEN
            output.available_copy_ratio = output.available_count::FLOAT / output.competing_hold_count::FLOAT;
        END IF;
    END IF;
    
    --Clean up our temporary tables
    DROP TABLE copy_holds_tmp;
    DROP TABLE competing_holds;

    RETURN output;

END;
$func$ LANGUAGE PLPGSQL;


SELECT evergreen.upgrade_deps_block_check('1432', :eg_version);

CREATE OR REPLACE FUNCTION vandelay.add_field ( target_xml TEXT, source_xml TEXT, field TEXT, force_add INT ) RETURNS TEXT AS $_$

    use MARC::Record;
    use MARC::File::XML (BinaryEncoding => 'UTF-8');
    use MARC::Charset;
    use strict;

    MARC::Charset->assume_unicode(1);

    my $target_xml = shift;
    my $source_xml = shift;
    my $field_spec = shift;
    my $force_add = shift || 0;

    my $target_r = MARC::Record->new_from_xml( $target_xml );
    my $source_r = MARC::Record->new_from_xml( $source_xml );

    return $target_xml unless ($target_r && $source_r);

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

    for my $f ( keys %fields) {
        if ( @{$fields{$f}{sf}} ) {
            for my $from_field ($source_r->field( $f )) {
                my @tos = $target_r->field( $f );
                if (!@tos) {
                    next if (exists($fields{$f}{match}) and !$force_add);
                    my @new_fields = map { $_->clone } $source_r->field( $f );
                    $target_r->insert_fields_ordered( @new_fields );
                } else {
                    for my $to_field (@tos) {
                        if (exists($fields{$f}{match})) {
                            my @match_list = grep { $to_field->subfield($_) =~ $fields{$f}{match}{$_} } keys %{$fields{$f}{match}};
                            next unless (scalar(@match_list) == scalar(keys %{$fields{$f}{match}}));
                        }
                        for my $old_sf ($from_field->subfields) {
                            $to_field->add_subfields( @$old_sf ) if grep(/$$old_sf[0]/,@{$fields{$f}{sf}});
                        }
                    }
                }
            }
        } else {
            my @new_fields = map { $_->clone } $source_r->field( $f );
            $target_r->insert_fields_ordered( @new_fields );
        }
    }

    $target_xml = $target_r->as_xml_record;
    $target_xml =~ s/^<\?.+?\?>$//mo;
    $target_xml =~ s/\n//sgo;
    $target_xml =~ s/>\s+</></sgo;

    return $target_xml;

$_$ LANGUAGE PLPERLU;

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

        for my $target_sf ($target_field->subfields) {
            my $subfield = $target_sf->[0];
            my $target_val = $target_sf->[1];

            if (grep {$_ eq $subfield} @controlled_subfields) {
                if (my $source_val = $source_field->subfield($subfield)) {
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
                my @match_list = grep { $target_field->subfield($_) =~ $fields{$f}{match}{$_} } keys %{$fields{$f}{match}};
                next unless (scalar(@match_list) == scalar(keys %{$fields{$f}{match}}));
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


COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
