BEGIN;

CREATE TABLE config.hard_due_date (
        id          SERIAL      PRIMARY KEY,
        name        TEXT        NOT NULL UNIQUE CHECK ( name ~ E'^\\w+$' ),
        ceiling_date    TIMESTAMPTZ NOT NULL,
        forceto     BOOL        NOT NULL,
        owner       INT         NOT NULL
);

CREATE TABLE config.hard_due_date_values (
    id                  SERIAL      PRIMARY KEY,
    hard_due_date       INT         NOT NULL REFERENCES config.hard_due_date (id)
                                    DEFERRABLE INITIALLY DEFERRED,
    ceiling_date        TIMESTAMPTZ NOT NULL,
    active_date         TIMESTAMPTZ NOT NULL
);

ALTER TABLE config.circ_matrix_matchpoint ADD COLUMN hard_due_date INT REFERENCES config.hard_due_date (id);

CREATE OR REPLACE FUNCTION config.update_hard_due_dates () RETURNS INT AS $func$
DECLARE
    temp_value  config.hard_due_date_values%ROWTYPE;
    updated     INT := 0;
BEGIN
    FOR temp_value IN
      SELECT  DISTINCT ON (hard_due_date) *
        FROM  config.hard_due_date_values
        WHERE active_date <= NOW() -- We've passed (or are at) the rollover time
        ORDER BY active_date DESC -- Latest (nearest to us) active time
   LOOP
        UPDATE  config.hard_due_date
          SET   ceiling_date = temp_value.ceiling_date
          WHERE id = temp_value.hard_due_date
                AND ceiling_date <> temp_value.ceiling_date; -- Time is equal if we've already updated the chdd

        IF FOUND THEN
            updated := updated + 1;
        END IF;
    END LOOP;

    RETURN updated;
END;
$func$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION oils_text_as_bytea (TEXT) RETURNS BYTEA AS $_$
    SELECT CAST(REGEXP_REPLACE(UPPER($1), $$\\$$, $$\\\\$$, 'g') AS BYTEA);
$_$ LANGUAGE SQL IMMUTABLE;

DROP INDEX asset.asset_call_number_upper_label_id_owning_lib_idx;
CREATE INDEX asset_call_number_upper_label_id_owning_lib_idx ON asset.call_number (oils_text_as_bytea(label),id,owning_lib);

/* this makes us require PG 8.3+ */
CREATE OR REPLACE FUNCTION oils_xpath ( TEXT, TEXT, ANYARRAY ) RETURNS TEXT[] AS 'SELECT XPATH( $1, $2::XML, $3 )::TEXT[];' LANGUAGE SQL IMMUTABLE;
CREATE OR REPLACE FUNCTION oils_xpath ( TEXT, TEXT ) RETURNS TEXT[] AS 'SELECT XPATH( $1, $2::XML )::TEXT[];' LANGUAGE SQL IMMUTABLE;

-- Start picking up call number label prefixes and suffixes
-- from asset.copy_location
ALTER TABLE asset.copy_location ADD COLUMN label_prefix TEXT;
ALTER TABLE asset.copy_location ADD COLUMN label_suffix TEXT;

-- Push due dates to 23:59:59 on insert OR update
DROP TRIGGER push_due_date_tgr ON action.circulation;
CREATE TRIGGER push_due_date_tgr BEFORE INSERT OR UPDATE ON action.circulation FOR EACH ROW EXECUTE PROCEDURE action.push_circ_due_time();

ALTER TABLE permission.grp_tree
	ADD COLUMN hold_priority INT NOT NULL DEFAULT 0;

INSERT INTO container.biblio_record_entry_bucket_type (code,label) VALUES ('template_merge','Template Merge Container');

CREATE OR REPLACE FUNCTION vandelay.strip_field ( xml TEXT, field TEXT ) RETURNS TEXT AS $_$

    use MARC::Record;
    use MARC::File::XML (BinaryEncoding => 'UTF-8');
    use strict;

    my $xml = shift;
    my $r = MARC::Record->new_from_xml( $xml );

    return $xml unless ($r);

    my $field_spec = shift;
    my @field_list = split(',', $field_spec);

    my %fields;
    for my $f (@field_list) {
        $f =~ s/^\s*//; $f =~ s/\s*$//;
        if ($f =~ /^(.{3})(\w*)(?:\[([^]]*)\])?$/) {
            my $field = $1;
            $field =~ s/\s+//;
            my $sf = $2;
            $sf =~ s/\s+//;
            my $match = $3;
            $match =~ s/^\s*//; $match =~ s/\s*$//;
            $fields{$field} = { sf => [ split('', $sf) ] };
            if ($match) {
                my ($msf,$mre) = split('~', $match);
                if (length($msf) > 0 and length($mre) > 0) {
                    $msf =~ s/^\s*//; $msf =~ s/\s*$//;
                    $mre =~ s/^\s*//; $mre =~ s/\s*$//;
                    $fields{$field}{match} = { sf => $msf, re => qr/$mre/ };
                }
            }
        }
    }

    for my $f ( keys %fields) {
        for my $to_field ($r->field( $f )) {
            if (exists($fields{$f}{match})) {
                next unless (grep { $_ =~ $fields{$f}{match}{re} } $to_field->subfield($fields{$f}{match}{sf}));
            }

            if ( @{$fields{$f}{sf}} ) {
                $to_field->delete_subfield(code => $fields{$f}{sf});
            } else {
                $r->delete_field( $to_field );
            }
        }
    }

    $xml = $r->as_xml_record;
    $xml =~ s/^<\?.+?\?>$//mo;
    $xml =~ s/\n//sgo;
    $xml =~ s/>\s+</></sgo;

    return $xml;

$_$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION vandelay.add_field ( target_xml TEXT, source_xml TEXT, field TEXT, force_add INT ) RETURNS TEXT AS $_$

    use MARC::Record;
    use MARC::File::XML (BinaryEncoding => 'UTF-8');
    use strict;

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
            my $match = $3;
            $match =~ s/^\s*//; $match =~ s/\s*$//;
            $fields{$field} = { sf => [ split('', $sf) ] };
            if ($match) {
                my ($msf,$mre) = split('~', $match);
                if (length($msf) > 0 and length($mre) > 0) {
                    $msf =~ s/^\s*//; $msf =~ s/\s*$//;
                    $mre =~ s/^\s*//; $mre =~ s/\s*$//;
                    $fields{$field}{match} = { sf => $msf, re => qr/$mre/ };
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
                            next unless (grep { $_ =~ $fields{$f}{match}{re} } $to_field->subfield($fields{$f}{match}{sf}));
                        }
                        my @new_sf = map { ($_ => $from_field->subfield($_)) } @{$fields{$f}{sf}};
                        $to_field->add_subfields( @new_sf );
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

CREATE OR REPLACE FUNCTION vandelay.add_field ( target_xml TEXT, source_xml TEXT, field TEXT ) RETURNS TEXT AS $_$
    SELECT vandelay.add_field( $1, $2, $3, 0 );
$_$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION vandelay.replace_field ( target_xml TEXT, source_xml TEXT, field TEXT ) RETURNS TEXT AS $_$
DECLARE
    xml_output TEXT;
    parsed_target TEXT;
BEGIN
    parsed_target := vandelay.strip_field( target_xml, ''); -- this dance normalized the format of the xml for the IF below
    xml_output := vandelay.strip_field( parsed_target, field);

    IF xml_output <> parsed_target  AND field ~ E'~' THEN
        -- we removed something, and there was a regexp restriction in the field definition, so proceed
        xml_output := vandelay.add_field( xml_output, source_xml, field, 1 );
    ELSIF field !~ E'~' THEN
        -- No regexp restriction, add the field
        xml_output := vandelay.add_field( xml_output, source_xml, field, 0 );
    END IF;

    RETURN xml_output;
END;
$_$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.merge_record_xml ( target_xml TEXT, source_xml TEXT, add_rule TEXT, replace_preserve_rule TEXT, strip_rule TEXT ) RETURNS TEXT AS $_$
    SELECT vandelay.replace_field( vandelay.add_field( vandelay.strip_field( $1, $5) , $2, $3 ), $2, $4);
$_$ LANGUAGE SQL;

CREATE TYPE vandelay.compile_profile AS (add_rule TEXT, replace_rule TEXT, preserve_rule TEXT, strip_rule TEXT);
CREATE OR REPLACE FUNCTION vandelay.compile_profile ( incoming_xml TEXT ) RETURNS vandelay.compile_profile AS $_$
DECLARE
    output              vandelay.compile_profile%ROWTYPE;
    add_rule            TEXT := '';
    strip_rule          TEXT := '';
    replace_rule        TEXT := '';
    preserve_rule       TEXT := '';

BEGIN

    add_rule := add_rule || ',' || COALESCE(ARRAY_TO_STRING(oils_xpath('//*[@tag="905"]/*[@code="a"]/text()',incoming_xml),','),'');
    strip_rule := strip_rule || ',' || COALESCE(ARRAY_TO_STRING(oils_xpath('//*[@tag="905"]/*[@code="d"]/text()',incoming_xml),','),'');
    replace_rule := replace_rule || ',' || COALESCE(ARRAY_TO_STRING(oils_xpath('//*[@tag="905"]/*[@code="r"]/text()',incoming_xml),','),'');
    preserve_rule := preserve_rule || ',' || COALESCE(ARRAY_TO_STRING(oils_xpath('//*[@tag="905"]/*[@code="p"]/text()',incoming_xml),','),'');

    output.add_rule := BTRIM(add_rule,',');
    output.replace_rule := BTRIM(replace_rule,',');
    output.strip_rule := BTRIM(strip_rule,',');
    output.preserve_rule := BTRIM(preserve_rule,',');

    RETURN output;
END;
$_$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.template_overlay_bib_record ( v_marc TEXT, eg_id BIGINT ) RETURNS BOOL AS $$
DECLARE
    dyn_profile     vandelay.compile_profile%ROWTYPE;
    editor_string   TEXT;
    editor_id       INT;
    source_marc     TEXT;
    target_marc     TEXT;
    eg_marc         TEXT;
    replace_rule    TEXT;
    match_count     INT;
BEGIN

    SELECT  b.marc INTO eg_marc
      FROM  biblio.record_entry b
      WHERE b.id = eg_id
      LIMIT 1;

    IF eg_marc IS NULL OR v_marc IS NULL THEN
        -- RAISE NOTICE 'no marc for template or bib record';
        RETURN FALSE;
    END IF;

    dyn_profile := vandelay.compile_profile( v_marc );

    IF dyn_profile.replace_rule <> '' AND dyn_profile.preserve_rule <> '' THEN
        -- RAISE NOTICE 'both replace [%] and preserve [%] specified', dyn_profile.replace_rule, dyn_profile.preserve_rule;
        RETURN FALSE;
    END IF;

    IF dyn_profile.replace_rule <> '' THEN
        source_marc = v_marc;
        target_marc = eg_marc;
        replace_rule = dyn_profile.replace_rule;
    ELSE
        source_marc = eg_marc;
        target_marc = v_marc;
        replace_rule = dyn_profile.preserve_rule;
    END IF;

    UPDATE  biblio.record_entry
      SET   marc = vandelay.merge_record_xml( target_marc, source_marc, dyn_profile.add_rule, replace_rule, dyn_profile.strip_rule )
      WHERE id = eg_id;

    IF NOT FOUND THEN
        -- RAISE NOTICE 'update of biblio.record_entry failed';
        RETURN FALSE;
    END IF;

    RETURN TRUE;

END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION action.hold_request_permit_test( pickup_ou INT, request_ou INT, match_item BIGINT, match_user INT, match_requestor INT, retargetting BOOL ) RETURNS SETOF action.matrix_test_result AS $func$
DECLARE
    matchpoint_id        INT;
    user_object        actor.usr%ROWTYPE;
    age_protect_object    config.rule_age_hold_protect%ROWTYPE;
    standing_penalty    config.standing_penalty%ROWTYPE;
    transit_range_ou_type    actor.org_unit_type%ROWTYPE;
    transit_source        actor.org_unit%ROWTYPE;
    item_object        asset.copy%ROWTYPE;
    result            action.matrix_test_result;
    hold_test        config.hold_matrix_matchpoint%ROWTYPE;
    hold_count        INT;
    hold_transit_prox    INT;
    frozen_hold_count    INT;
    context_org_list    INT[];
    done            BOOL := FALSE;
BEGIN
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user;
    SELECT INTO context_org_list ARRAY_ACCUM(id) FROM actor.org_unit_full_path( pickup_ou );

    result.success := TRUE;

    -- Fail if we couldn't find a user
    IF user_object.id IS NULL THEN
        result.fail_part := 'no_user';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO item_object * FROM asset.copy WHERE id = match_item;

    -- Fail if we couldn't find a copy
    IF item_object.id IS NULL THEN
        result.fail_part := 'no_item';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO matchpoint_id action.find_hold_matrix_matchpoint(pickup_ou, request_ou, match_item, match_user, match_requestor);
    result.matchpoint := matchpoint_id;

    -- Fail if user is barred
    IF user_object.barred IS TRUE THEN
        result.fail_part := 'actor.usr.barred';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    -- Fail if we couldn't find any matchpoint (requires a default)
    IF matchpoint_id IS NULL THEN
        result.fail_part := 'no_matchpoint';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO hold_test * FROM config.hold_matrix_matchpoint WHERE id = matchpoint_id;

    IF hold_test.holdable IS FALSE THEN
        result.fail_part := 'config.hold_matrix_test.holdable';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    IF hold_test.transit_range IS NOT NULL THEN
        SELECT INTO transit_range_ou_type * FROM actor.org_unit_type WHERE id = hold_test.transit_range;
        IF hold_test.distance_is_from_owner THEN
            SELECT INTO transit_source ou.* FROM actor.org_unit ou JOIN asset.call_number cn ON (cn.owning_lib = ou.id) WHERE cn.id = item_object.call_number;
        ELSE
            SELECT INTO transit_source * FROM actor.org_unit WHERE id = item_object.circ_lib;
        END IF;

        PERFORM * FROM actor.org_unit_descendants( transit_source.id, transit_range_ou_type.depth ) WHERE id = pickup_ou;

        IF NOT FOUND THEN
            result.fail_part := 'transit_range';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;
 
    FOR standing_penalty IN
        SELECT  DISTINCT csp.*
          FROM  actor.usr_standing_penalty usp
                JOIN config.standing_penalty csp ON (csp.id = usp.standing_penalty)
          WHERE usr = match_user
                AND usp.org_unit IN ( SELECT * FROM explode_array(context_org_list) )
                AND (usp.stop_date IS NULL or usp.stop_date > NOW())
                AND csp.block_list LIKE '%HOLD%' LOOP

        result.fail_part := standing_penalty.name;
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END LOOP;

    IF hold_test.stop_blocked_user IS TRUE THEN
        FOR standing_penalty IN
            SELECT  DISTINCT csp.*
              FROM  actor.usr_standing_penalty usp
                    JOIN config.standing_penalty csp ON (csp.id = usp.standing_penalty)
              WHERE usr = match_user
                    AND usp.org_unit IN ( SELECT * FROM explode_array(context_org_list) )
                    AND (usp.stop_date IS NULL or usp.stop_date > NOW())
                    AND csp.block_list LIKE '%CIRC%' LOOP
    
            result.fail_part := standing_penalty.name;
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END LOOP;
    END IF;

    IF hold_test.max_holds IS NOT NULL AND NOT retargetting THEN
        SELECT    INTO hold_count COUNT(*)
          FROM    action.hold_request
          WHERE    usr = match_user
            AND fulfillment_time IS NULL
            AND cancel_time IS NULL
            AND CASE WHEN hold_test.include_frozen_holds THEN TRUE ELSE frozen IS FALSE END;

        IF hold_count >= hold_test.max_holds THEN
            result.fail_part := 'config.hold_matrix_test.max_holds';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;

    IF item_object.age_protect IS NOT NULL THEN
        SELECT INTO age_protect_object * FROM config.rule_age_hold_protect WHERE id = item_object.age_protect;

        IF item_object.create_date + age_protect_object.age > NOW() THEN
            IF hold_test.distance_is_from_owner THEN
                SELECT INTO hold_transit_prox prox FROM actor.org_unit_proximity WHERE from_org = item_cn_object.owning_lib AND to_org = pickup_ou;
            ELSE
                SELECT INTO hold_transit_prox prox FROM actor.org_unit_proximity WHERE from_org = item_object.circ_lib AND to_org = pickup_ou;
            END IF;

            IF hold_transit_prox > age_protect_object.prox THEN
                result.fail_part := 'config.rule_age_hold_protect.prox';
                result.success := FALSE;
                done := TRUE;
                RETURN NEXT result;
            END IF;
        END IF;
    END IF;

    IF NOT done THEN
        RETURN NEXT result;
    END IF;

    RETURN;
END;
$func$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION action.hold_request_permit_test( pickup_ou INT, request_ou INT, match_item BIGINT, match_user INT, match_requestor INT ) RETURNS SETOF action.matrix_test_result AS $func$
    SELECT * FROM action.hold_request_permit_test( $1, $2, $3, $4, $5, FALSE);
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION action.hold_retarget_permit_test( pickup_ou INT, request_ou INT, match_item BIGINT, match_user INT, match_requestor INT ) RETURNS SETOF action.matrix_test_result AS $func$
    SELECT * FROM action.hold_request_permit_test( $1, $2, $3, $4, $5, TRUE );
$func$ LANGUAGE SQL;

-- 0448.data.trigger.circ.staff_age_to_lost.sql

INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES 
    (   'circ.staff_age_to_lost',
        'circ', 
        oils_i18n_gettext(
            'circ.staff_age_to_lost',
            'An overdue circulation should be aged to a Lost status.',
            'ath',
            'description'
        ), 
        TRUE
    )
;

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        delay_field
    ) VALUES (
        36,
        FALSE,
        1,
        'circ.staff_age_to_lost',
        'circ.staff_age_to_lost',
        'CircIsOverdue',
        'MarkItemLost',
        'due_date'
    )
;

COMMIT;

