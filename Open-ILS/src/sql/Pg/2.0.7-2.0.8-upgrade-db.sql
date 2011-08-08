BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0573'); -- miker

CREATE OR REPLACE FUNCTION search.query_parser_fts (

    param_search_ou INT,
    param_depth     INT,
    param_query     TEXT,
    param_statuses  INT[],
    param_locations INT[],
    param_offset    INT,
    param_check     INT,
    param_limit     INT,
    metarecord      BOOL,
    staff           BOOL
 
) RETURNS SETOF search.search_result AS $func$
DECLARE

    current_res         search.search_result%ROWTYPE;
    search_org_list     INT[];

    check_limit         INT;
    core_limit          INT;
    core_offset         INT;
    tmp_int             INT;

    core_result         RECORD;
    core_cursor         REFCURSOR;
    core_rel_query      TEXT;

    total_count         INT := 0;
    check_count         INT := 0;
    deleted_count       INT := 0;
    visible_count       INT := 0;
    excluded_count      INT := 0;

BEGIN

    check_limit := COALESCE( param_check, 1000 );
    core_limit  := COALESCE( param_limit, 25000 );
    core_offset := COALESCE( param_offset, 0 );

    -- core_skip_chk := COALESCE( param_skip_chk, 1 );

    IF param_search_ou > 0 THEN
        IF param_depth IS NOT NULL THEN
            SELECT array_accum(distinct id) INTO search_org_list FROM actor.org_unit_descendants( param_search_ou, param_depth );
        ELSE
            SELECT array_accum(distinct id) INTO search_org_list FROM actor.org_unit_descendants( param_search_ou );
        END IF;
    ELSIF param_search_ou < 0 THEN
        SELECT array_accum(distinct org_unit) INTO search_org_list FROM actor.org_lasso_map WHERE lasso = -param_search_ou;
    ELSIF param_search_ou = 0 THEN
        -- reserved for user lassos (ou_buckets/type='lasso') with ID passed in depth ... hack? sure.
    END IF;

    OPEN core_cursor FOR EXECUTE param_query;

    LOOP

        FETCH core_cursor INTO core_result;
        EXIT WHEN NOT FOUND;
        EXIT WHEN total_count >= core_limit;

        total_count := total_count + 1;

        CONTINUE WHEN total_count NOT BETWEEN  core_offset + 1 AND check_limit + core_offset;

        check_count := check_count + 1;

        PERFORM 1 FROM biblio.record_entry b WHERE NOT b.deleted AND b.id IN ( SELECT * FROM unnest( core_result.records ) );
        IF NOT FOUND THEN
            -- RAISE NOTICE ' % were all deleted ... ', core_result.records;
            deleted_count := deleted_count + 1;
            CONTINUE;
        END IF;

        PERFORM 1
          FROM  biblio.record_entry b
                JOIN config.bib_source s ON (b.source = s.id)
          WHERE s.transcendant
                AND b.id IN ( SELECT * FROM unnest( core_result.records ) );

        IF FOUND THEN
            -- RAISE NOTICE ' % were all transcendant ... ', core_result.records;
            visible_count := visible_count + 1;

            current_res.id = core_result.id;
            current_res.rel = core_result.rel;

            tmp_int := 1;
            IF metarecord THEN
                SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
            END IF;

            IF tmp_int = 1 THEN
                current_res.record = core_result.records[1];
            ELSE
                current_res.record = NULL;
            END IF;

            RETURN NEXT current_res;

            CONTINUE;
        END IF;

        PERFORM 1
          FROM  asset.call_number cn
                JOIN asset.uri_call_number_map map ON (map.call_number = cn.id)
                JOIN asset.uri uri ON (map.uri = uri.id)
          WHERE NOT cn.deleted
                AND cn.label = '##URI##'
                AND uri.active
                AND ( param_locations IS NULL OR array_upper(param_locations, 1) IS NULL )
                AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                AND cn.owning_lib IN ( SELECT * FROM unnest( search_org_list ) )
          LIMIT 1;

        IF FOUND THEN
            -- RAISE NOTICE ' % have at least one URI ... ', core_result.records;
            visible_count := visible_count + 1;

            current_res.id = core_result.id;
            current_res.rel = core_result.rel;

            tmp_int := 1;
            IF metarecord THEN
                SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
            END IF;

            IF tmp_int = 1 THEN
                current_res.record = core_result.records[1];
            ELSE
                current_res.record = NULL;
            END IF;

            RETURN NEXT current_res;

            CONTINUE;
        END IF;

        IF param_statuses IS NOT NULL AND array_upper(param_statuses, 1) > 0 THEN

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cp.call_number = cn.id)
              WHERE NOT cn.deleted
                    AND NOT cp.deleted
                    AND cp.status IN ( SELECT * FROM unnest( param_statuses ) )
                    AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                    AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
              LIMIT 1;

            IF NOT FOUND THEN
                -- RAISE NOTICE ' % were all status-excluded ... ', core_result.records;
                excluded_count := excluded_count + 1;
                CONTINUE;
            END IF;

        END IF;

        IF param_locations IS NOT NULL AND array_upper(param_locations, 1) > 0 THEN

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cp.call_number = cn.id)
              WHERE NOT cn.deleted
                    AND NOT cp.deleted
                    AND cp.location IN ( SELECT * FROM unnest( param_locations ) )
                    AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                    AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
              LIMIT 1;

            IF NOT FOUND THEN
                -- RAISE NOTICE ' % were all copy_location-excluded ... ', core_result.records;
                excluded_count := excluded_count + 1;
                CONTINUE;
            END IF;

        END IF;

        IF staff IS NULL OR NOT staff THEN

            PERFORM 1
              FROM  asset.opac_visible_copies
              WHERE circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                    AND record IN ( SELECT * FROM unnest( core_result.records ) )
              LIMIT 1;

            IF NOT FOUND THEN
                -- RAISE NOTICE ' % were all visibility-excluded ... ', core_result.records;
                excluded_count := excluded_count + 1;
                CONTINUE;
            END IF;

        ELSE

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cp.call_number = cn.id)
              WHERE NOT cn.deleted
                    AND NOT cp.deleted
                    AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                    AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
              LIMIT 1;

            IF NOT FOUND THEN

                PERFORM 1
                  FROM  asset.call_number cn
                        JOIN asset.copy cp ON (cp.call_number = cn.id)
                  WHERE cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                        AND NOT cp.deleted
                  LIMIT 1;

                IF FOUND THEN
                    -- RAISE NOTICE ' % were all visibility-excluded ... ', core_result.records;
                    excluded_count := excluded_count + 1;
                    CONTINUE;
                END IF;

            END IF;

        END IF;

        visible_count := visible_count + 1;

        current_res.id = core_result.id;
        current_res.rel = core_result.rel;

        tmp_int := 1;
        IF metarecord THEN
            SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
        END IF;

        IF tmp_int = 1 THEN
            current_res.record = core_result.records[1];
        ELSE
            current_res.record = NULL;
        END IF;

        RETURN NEXT current_res;

        IF visible_count % 1000 = 0 THEN
            -- RAISE NOTICE ' % visible so far ... ', visible_count;
        END IF;

    END LOOP;

    current_res.id = NULL;
    current_res.rel = NULL;
    current_res.record = NULL;
    current_res.total = total_count;
    current_res.checked = check_count;
    current_res.deleted = deleted_count;
    current_res.visible = visible_count;
    current_res.excluded = excluded_count;

    CLOSE core_cursor;

    RETURN NEXT current_res;

END;
$func$ LANGUAGE PLPGSQL;


-- Evergreen DB patch 0576.fix_maintain_901_quoting.sql
--
-- Fix for bug LP#809540 - fixes crash when inserting or updating
-- bib whose tcn_value contains regex metacharacters.
--

-- check whether patch can be applied
INSERT INTO config.upgrade_log (version) VALUES ('0576');

CREATE OR REPLACE FUNCTION evergreen.maintain_901 () RETURNS TRIGGER AS $func$
DECLARE
    use_id_for_tcn BOOLEAN;
BEGIN
    -- Remove any existing 901 fields before we insert the authoritative one
    NEW.marc := REGEXP_REPLACE(NEW.marc, E'<datafield[^>]*?tag="901".+?</datafield>', '', 'g');

    IF TG_TABLE_SCHEMA = 'biblio' THEN
        -- Set TCN value to record ID?
        SELECT enabled FROM config.global_flag INTO use_id_for_tcn
            WHERE name = 'cat.bib.use_id_for_tcn';

        IF use_id_for_tcn = 't' THEN
            NEW.tcn_value := NEW.id;
        END IF;

        NEW.marc := REGEXP_REPLACE(
            NEW.marc,
            E'(</(?:[^:]*?:)?record>)',
            E'<datafield tag="901" ind1=" " ind2=" ">' ||
                '<subfield code="a">' || REPLACE(evergreen.xml_escape(NEW.tcn_value), E'\\', E'\\\\') || E'</subfield>' ||
                '<subfield code="b">' || REPLACE(evergreen.xml_escape(NEW.tcn_source), E'\\', E'\\\\') || E'</subfield>' ||
                '<subfield code="c">' || NEW.id || E'</subfield>' ||
                '<subfield code="t">' || TG_TABLE_SCHEMA || E'</subfield>' ||
                CASE WHEN NEW.owner IS NOT NULL THEN '<subfield code="o">' || NEW.owner || E'</subfield>' ELSE '' END ||
                CASE WHEN NEW.share_depth IS NOT NULL THEN '<subfield code="d">' || NEW.share_depth || E'</subfield>' ELSE '' END ||
             E'</datafield>\\1'
        );
    ELSIF TG_TABLE_SCHEMA = 'authority' THEN
        NEW.marc := REGEXP_REPLACE(
            NEW.marc,
            E'(</(?:[^:]*?:)?record>)',
            E'<datafield tag="901" ind1=" " ind2=" ">' ||
                '<subfield code="c">' || NEW.id || E'</subfield>' ||
                '<subfield code="t">' || TG_TABLE_SCHEMA || E'</subfield>' ||
             E'</datafield>\\1'
        );
    ELSIF TG_TABLE_SCHEMA = 'serial' THEN
        NEW.marc := REGEXP_REPLACE(
            NEW.marc,
            E'(</(?:[^:]*?:)?record>)',
            E'<datafield tag="901" ind1=" " ind2=" ">' ||
                '<subfield code="c">' || NEW.id || E'</subfield>' ||
                '<subfield code="t">' || TG_TABLE_SCHEMA || E'</subfield>' ||
                '<subfield code="o">' || NEW.owning_lib || E'</subfield>' ||
                CASE WHEN NEW.record IS NOT NULL THEN '<subfield code="r">' || NEW.record || E'</subfield>' ELSE '' END ||
             E'</datafield>\\1'
        );
    ELSE
        NEW.marc := REGEXP_REPLACE(
            NEW.marc,
            E'(</(?:[^:]*?:)?record>)',
            E'<datafield tag="901" ind1=" " ind2=" ">' ||
                '<subfield code="c">' || NEW.id || E'</subfield>' ||
                '<subfield code="t">' || TG_TABLE_SCHEMA || E'</subfield>' ||
             E'</datafield>\\1'
        );
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;


INSERT INTO config.upgrade_log (version) VALUES ('0580'); -- tsbere via miker

CREATE OR REPLACE FUNCTION actor.org_unit_parent_protect () RETURNS TRIGGER AS $$
    DECLARE
        current_aou actor.org_unit%ROWTYPE;
        seen_ous    INT[];
        depth_count INT;
	BEGIN
        current_aou := NEW;
        depth_count := 0;
        seen_ous := ARRAY[NEW.id];
        IF TG_OP = 'INSERT' OR NEW.parent_ou IS DISTINCT FROM OLD.parent_ou THEN
            LOOP
                IF current_aou.parent_ou IS NULL THEN -- Top of the org tree?
                    RETURN NEW; -- No loop. Carry on.
                END IF;
                IF current_aou.parent_ou = ANY(seen_ous) THEN -- Parent is one we have seen?
                    RAISE 'OU LOOP: Saw % twice', current_aou.parent_ou; -- LOOP! ABORT!
                END IF;
                -- Get the next one!
                SELECT INTO current_aou * FROM actor.org_unit WHERE id = current_aou.parent_ou;
                seen_ous := seen_ous || current_aou.id;
                depth_count := depth_count + 1;
                IF depth_count = 100 THEN
                    RAISE 'OU CHECK TOO DEEP';
                END IF;
            END LOOP;
        END IF;
		RETURN NEW;
	END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER actor_org_unit_parent_protect_trigger
    BEFORE INSERT OR UPDATE ON actor.org_unit FOR EACH ROW
    EXECUTE PROCEDURE actor.org_unit_parent_protect ();


INSERT INTO config.upgrade_log (version) VALUES ('0581'); -- tsbere via miker

INSERT INTO config.global_flag (name, label, enabled)
    VALUES (
        'circ.opac_renewal.use_original_circ_lib',
        oils_i18n_gettext(
            'circ.opac_renewal.use_original_circ_lib',
            'Circ: Use original circulation library on opac renewal instead of user home library',
            'cgf',
            'label'
        ),
        FALSE
    );


INSERT INTO config.upgrade_log (version) VALUES ('0582'); -- miker

CREATE OR REPLACE VIEW action.all_circulation AS
    SELECT  id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ
      FROM  action.aged_circulation
            UNION ALL
    SELECT  DISTINCT circ.id,COALESCE(a.post_code,b.post_code) AS usr_post_code, p.home_ou AS usr_home_ou, p.profile AS usr_profile, EXTRACT(YEAR FROM p.dob)::INT AS usr_birth_year,
        cp.call_number AS copy_call_number, cp.location AS copy_location, cn.owning_lib AS copy_owning_lib, cp.circ_lib AS copy_circ_lib,
        cn.record AS copy_bib_record, circ.xact_start, circ.xact_finish, circ.target_copy, circ.circ_lib, circ.circ_staff, circ.checkin_staff,
        circ.checkin_lib, circ.renewal_remaining, circ.due_date, circ.stop_fines_time, circ.checkin_time, circ.create_time, circ.duration,
        circ.fine_interval, circ.recurring_fine, circ.max_fine, circ.phone_renewal, circ.desk_renewal, circ.opac_renewal, circ.duration_rule,
        circ.recurring_fine_rule, circ.max_fine_rule, circ.stop_fines, circ.workstation, circ.checkin_workstation, circ.checkin_scan_time,
        circ.parent_circ
      FROM  action.circulation circ
        JOIN asset.copy cp ON (circ.target_copy = cp.id)
        JOIN asset.call_number cn ON (cp.call_number = cn.id)
        JOIN actor.usr p ON (circ.usr = p.id)
        LEFT JOIN actor.usr_address a ON (p.mailing_address = a.id)
        LEFT JOIN actor.usr_address b ON (p.billing_address = b.id);


INSERT INTO config.upgrade_log (version) VALUES ('0587'); -- dbs/berick

CREATE OR REPLACE FUNCTION maintain_control_numbers() RETURNS TRIGGER AS $func$
use strict;
use MARC::Record;
use MARC::File::XML (BinaryEncoding => 'UTF-8');
use MARC::Charset;
use Encode;
use Unicode::Normalize;

MARC::Charset->assume_unicode(1);

my $record = MARC::Record->new_from_xml($_TD->{new}{marc});
my $schema = $_TD->{table_schema};
my $rec_id = $_TD->{new}{id};

# Short-circuit if maintaining control numbers per MARC21 spec is not enabled
my $enable = spi_exec_query("SELECT enabled FROM config.global_flag WHERE name = 'cat.maintain_control_numbers'");
if (!($enable->{processed}) or $enable->{rows}[0]->{enabled} eq 'f') {
    return;
}

# Get the control number identifier from an OU setting based on $_TD->{new}{owner}
my $ou_cni = 'EVRGRN';

my $owner;
if ($schema eq 'serial') {
    $owner = $_TD->{new}{owning_lib};
} else {
    # are.owner and bre.owner can be null, so fall back to the consortial setting
    $owner = $_TD->{new}{owner} || 1;
}

my $ous_rv = spi_exec_query("SELECT value FROM actor.org_unit_ancestor_setting('cat.marc_control_number_identifier', $owner)");
if ($ous_rv->{processed}) {
    $ou_cni = $ous_rv->{rows}[0]->{value};
    $ou_cni =~ s/"//g; # Stupid VIM syntax highlighting"
} else {
    # Fall back to the shortname of the OU if there was no OU setting
    $ous_rv = spi_exec_query("SELECT shortname FROM actor.org_unit WHERE id = $owner");
    if ($ous_rv->{processed}) {
        $ou_cni = $ous_rv->{rows}[0]->{shortname};
    }
}

my ($create, $munge) = (0, 0);

my @scns = $record->field('035');

foreach my $id_field ('001', '003') {
    my $spec_value;
    my @controls = $record->field($id_field);

    if ($id_field eq '001') {
        $spec_value = $rec_id;
    } else {
        $spec_value = $ou_cni;
    }

    # Create the 001/003 if none exist
    if (scalar(@controls) == 1) {
        # Only one field; check to see if we need to munge it
        unless (grep $_->data() eq $spec_value, @controls) {
            $munge = 1;
        }
    } else {
        # Delete the other fields, as with more than 1 001/003 we do not know which 003/001 to match
        foreach my $control (@controls) {
            $record->delete_field($control);
        }
        $record->insert_fields_ordered(MARC::Field->new($id_field, $spec_value));
        $create = 1;
    }
}

my $cn = $record->field('001')->data();
# Special handling of OCLC numbers, often found in records that lack 003
if ($cn =~ /^oc[nm]/) {
    $cn =~ s/^oc[nm]0*(\d+)/$1/;
    $record->field('003')->data('OCoLC');
    $create = 0;
}

# Now, if we need to munge the 001, we will first push the existing 001/003
# into the 035; but if the record did not have one (and one only) 001 and 003
# to begin with, skip this process
if ($munge and not $create) {

    my $scn = "(" . $record->field('003')->data() . ")" . $cn;

    # Do not create duplicate 035 fields
    unless (grep $_->subfield('a') eq $scn, @scns) {
        $record->insert_fields_ordered(MARC::Field->new('035', '', '', 'a' => $scn));
    }
}

# Set the 001/003 and update the MARC
if ($create or $munge) {
    $record->field('001')->data($rec_id);
    $record->field('003')->data($ou_cni);

    my $xml = $record->as_xml_record();
    $xml =~ s/\n//sgo;
    $xml =~ s/^<\?xml.+\?\s*>//go;
    $xml =~ s/>\s+</></go;
    $xml =~ s/\p{Cc}//go;

    # Embed a version of OpenILS::Application::AppUtils->entityize()
    # to avoid having to set PERL5LIB for PostgreSQL as well

    # If we are going to convert non-ASCII characters to XML entities,
    # we had better be dealing with a UTF8 string to begin with
    $xml = decode_utf8($xml);

    $xml = NFC($xml);

    # Convert raw ampersands to entities
    $xml =~ s/&(?!\S+;)/&amp;/gso;

    # Convert Unicode characters to entities
    $xml =~ s/([\x{0080}-\x{fffd}])/sprintf('&#x%X;',ord($1))/sgoe;

    $xml =~ s/[\x00-\x1f]//go;
    $_TD->{new}{marc} = $xml;

    return "MODIFY";
}

return;
$func$ LANGUAGE PLPERLU;

INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath) VALUES
    (29, 'identifier', 'scn', oils_i18n_gettext(28, 'System Control Number', 'cmf', 'label'), 'marcxml', $$//marc:datafield[@tag='035']/marc:subfield[@code="a"]$$);
INSERT INTO config.metabib_field ( id, field_class, name, label, format, xpath) VALUES
    (30, 'identifier', 'lccn', oils_i18n_gettext(28, 'LC Control Number', 'cmf', 'label'), 'marcxml', $$//marc:datafield[@tag='010']/marc:subfield[@code="a" or @code='z']$$);

-- Far from perfect, but much faster than reingesting every record
INSERT INTO metabib.identifier_field_entry(source, field, value) 
    SELECT record, 29, value FROM metabib.full_rec WHERE tag = '035' AND subfield = 'a';
INSERT INTO metabib.identifier_field_entry(source, field, value) 
    SELECT record, 30, value FROM metabib.full_rec WHERE tag = '010' AND subfield IN ('a', 'z');


INSERT INTO config.upgrade_log (version) VALUES ('0588');

CREATE OR REPLACE FUNCTION vandelay.replace_field ( target_xml TEXT, source_xml TEXT, field TEXT ) RETURNS TEXT AS $_$
DECLARE
    xml_output TEXT;
    parsed_target TEXT;
    curr_field TEXT;
BEGIN

    parsed_target := vandelay.strip_field( target_xml, ''); -- this dance normalizes the format of the xml for the IF below
    xml_output := parsed_target; -- if there are no replace rules, just return the input

    FOR curr_field IN SELECT UNNEST( STRING_TO_ARRAY(field, ',') ) LOOP -- naive split, but it's the same we use in the perl

        xml_output := vandelay.strip_field( parsed_target, curr_field);

        IF xml_output <> parsed_target  AND curr_field ~ E'~' THEN
            -- we removed something, and there was a regexp restriction in the curr_field definition, so proceed
            xml_output := vandelay.add_field( xml_output, source_xml, curr_field, 1 );
        ELSIF curr_field !~ E'~' THEN
            -- No regexp restriction, add the curr_field
            xml_output := vandelay.add_field( xml_output, source_xml, curr_field, 0 );
        END IF;

        parsed_target := xml_output; -- in prep for any following loop iterations

    END LOOP;

    RETURN xml_output;
END;
$_$ LANGUAGE PLPGSQL;



INSERT INTO config.upgrade_log (version) VALUES ('0589');

DROP TRIGGER IF EXISTS mat_summary_add_tgr ON money.cash_payment;
DROP TRIGGER IF EXISTS mat_summary_upd_tgr ON money.cash_payment;
DROP TRIGGER IF EXISTS mat_summary_del_tgr ON money.cash_payment;

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.cash_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('cash_payment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.cash_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('cash_payment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.cash_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('cash_payment');
 
DROP TRIGGER IF EXISTS mat_summary_add_tgr ON money.check_payment;
DROP TRIGGER IF EXISTS mat_summary_upd_tgr ON money.check_payment;
DROP TRIGGER IF EXISTS mat_summary_del_tgr ON money.check_payment;

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.check_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('check_payment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.check_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('check_payment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.check_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('check_payment');


--Upgrade script for lp818311.


INSERT INTO config.upgrade_log (version) VALUES ('0592');

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 512, 'ACQ_INVOICE_REOPEN', oils_i18n_gettext( 512,
    'Allows a user to reopen an Acquisitions invoice', 'ppl', 'description' ));

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
	SELECT
		pgt.id, perm.id, aout.depth, TRUE
	FROM
		permission.grp_tree pgt,
		permission.perm_list perm,
		actor.org_unit_type aout
	WHERE
		pgt.name = 'Acquisitions Administrator' AND
		aout.name = 'Consortium' AND
		perm.code = 'ACQ_INVOICE_REOPEN';

COMMIT;
