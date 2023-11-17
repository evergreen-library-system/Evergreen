--Upgrade Script for 3.11.1 to 3.12-beta
\set eg_version '''3.12-beta'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.12-beta', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1375', :eg_version);

UPDATE action.hold_request 
SET selection_ou = request_lib
WHERE selection_ou NOT IN (
    SELECT id FROM actor.org_unit
);

ALTER TABLE action.hold_request ADD CONSTRAINT hold_request_selection_ou_fkey FOREIGN KEY (selection_ou) REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED NOT VALID;
ALTER TABLE action.hold_request VALIDATE CONSTRAINT hold_request_selection_ou_fkey;


SELECT evergreen.upgrade_deps_block_check('1380', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 644, 'ADMIN_PROXIMITY_ADJUSTMENT', oils_i18n_gettext(644,
    'Allow a user to administer Org Unit Proximity Adjustments', 'ppl', 'description'));


SELECT evergreen.upgrade_deps_block_check('1381', :eg_version);

CREATE OR REPLACE VIEW action.open_non_cataloged_circulation AS
    SELECT ncc.* 
    FROM action.non_cataloged_circulation ncc
    JOIN config.non_cataloged_type nct ON nct.id = ncc.item_type
    WHERE ncc.circ_time + nct.circ_duration > CURRENT_TIMESTAMP
;




SELECT evergreen.upgrade_deps_block_check('1382', :eg_version); -- JBoyer / smorrison

-- Remove previous acpl 1 protection
DROP RULE protect_acl_id_1 ON asset.copy_location;

-- Ensure that the owning_lib is set to CONS (equivalent), *should* be a noop.
UPDATE asset.copy_location SET owning_lib = (SELECT id FROM actor.org_unit_ancestor_at_depth(owning_lib,0)) WHERE id = 1;

CREATE OR REPLACE FUNCTION asset.check_delete_copy_location(acpl_id integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    PERFORM TRUE FROM asset.copy WHERE location = acpl_id AND NOT deleted LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION
            'Copy location % contains active copies and cannot be deleted', acpl_id;
    END IF;
    
    IF acpl_id = 1 THEN
        RAISE EXCEPTION
            'Copy location 1 cannot be deleted';
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION asset.copy_location_validate_edit()
  RETURNS trigger
  LANGUAGE plpgsql
AS $function$
BEGIN
    IF OLD.id = 1 THEN
        IF OLD.owning_lib != NEW.owning_lib OR NEW.deleted THEN
            RAISE EXCEPTION 'Copy location 1 cannot be moved or deleted';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE TRIGGER acpl_validate_edit BEFORE UPDATE ON asset.copy_location FOR EACH ROW EXECUTE FUNCTION asset.copy_location_validate_edit();



SELECT evergreen.upgrade_deps_block_check('1383', :eg_version);

DROP INDEX IF EXISTS asset.cp_available_by_circ_lib_idx;

DROP INDEX IF EXISTS serial.unit_available_by_circ_lib_idx;

CREATE INDEX cp_extant_by_circ_lib_idx ON asset.copy(circ_lib) WHERE deleted = FALSE OR deleted IS FALSE;

CREATE INDEX unit_extant_by_circ_lib_idx ON serial.unit(circ_lib) WHERE deleted = FALSE OR deleted IS FALSE;

CREATE OR REPLACE FUNCTION action.copy_related_hold_stats (copy_id BIGINT) RETURNS action.hold_stats AS $func$
DECLARE
    output          action.hold_stats%ROWTYPE;
    hold_count      INT := 0;
    copy_count      INT := 0;
    available_count INT := 0;
    hold_map_data   RECORD;
BEGIN

    output.hold_count := 0;
    output.copy_count := 0;
    output.available_count := 0;

    SELECT  COUNT( DISTINCT m.hold ) INTO hold_count
      FROM  action.hold_copy_map m
            JOIN action.hold_request h ON (m.hold = h.id)
      WHERE m.target_copy = copy_id
            AND NOT h.frozen;

    output.hold_count := hold_count;

    IF output.hold_count > 0 THEN
        FOR hold_map_data IN
            SELECT  DISTINCT m.target_copy,
                    acp.status
              FROM  action.hold_copy_map m
                    JOIN asset.copy acp ON (m.target_copy = acp.id)
                    JOIN action.hold_request h ON (m.hold = h.id)
              WHERE m.hold IN ( SELECT DISTINCT hold FROM action.hold_copy_map WHERE target_copy = copy_id ) AND NOT h.frozen
        LOOP
            output.copy_count := output.copy_count + 1;
            IF hold_map_data.status IN (SELECT id from config.copy_status where holdable and is_available) THEN
                output.available_count := output.available_count + 1;
            END IF;
        END LOOP;
        output.total_copy_ratio = output.copy_count::FLOAT / output.hold_count::FLOAT;
        output.available_copy_ratio = output.available_count::FLOAT / output.hold_count::FLOAT;

    END IF;

    RETURN output;

END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.staff_lasso_record_copy_count (i_lasso INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = rid;

    FOR ans IN SELECT u.org_unit AS id FROM actor.org_lasso_map AS u WHERE lasso = i_lasso LOOP
        RETURN QUERY
        SELECT  -1,
                ans.id,
                COUNT( cp.id ),
                SUM( CASE WHEN cp.status IN (SELECT id FROM config.copy_status WHERE holdable AND is_available)
                   THEN 1 ELSE 0 END ),
                SUM( CASE WHEN cl.opac_visible AND cp.opac_visible THEN 1 ELSE 0 END),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
                JOIN asset.copy_location cl ON (cp.location = cl.id AND NOT cl.deleted)
                JOIN asset.call_number cn ON (cn.record = rid AND cn.id = cp.call_number AND NOT cn.deleted)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT -1, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.staff_ou_metarecord_copy_count (org INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) JOIN metabib.metarecord_source_map m ON (m.source = b.id) WHERE src.transcendant AND m.metarecord = rid;

    FOR ans IN SELECT u.id, t.depth FROM actor.org_unit_ancestors(org) AS u JOIN actor.org_unit_type t ON (u.ou_type = t.id) LOOP
        RETURN QUERY
        SELECT  ans.depth,
                ans.id,
                COUNT( cp.id ),
                SUM( CASE WHEN cp.status IN (SELECT id FROM config.copy_status WHERE holdable AND is_available) THEN 1 ELSE 0 END ),
                COUNT( cp.id ),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
                JOIN asset.call_number cn ON (cn.id = cp.call_number AND NOT cn.deleted)
                JOIN metabib.metarecord_source_map m ON (m.metarecord = rid AND m.source = cn.record)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.staff_lasso_metarecord_copy_count (i_lasso INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) JOIN metabib.metarecord_source_map m ON (m.source = b.id) WHERE src.transcendant AND m.metarecord = rid;

    FOR ans IN SELECT u.org_unit AS id FROM actor.org_lasso_map AS u WHERE lasso = i_lasso LOOP
        RETURN QUERY
        SELECT  -1,
                ans.id,
                COUNT( cp.id ),
                SUM( CASE WHEN cp.status IN (SELECT id FROM config.copy_status WHERE holdable AND is_available) THEN 1 ELSE 0 END ),
                COUNT( cp.id ),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
                JOIN asset.call_number cn ON (cn.id = cp.call_number AND NOT cn.deleted)
                JOIN metabib.metarecord_source_map m ON (m.metarecord = rid AND m.source = cn.record)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;



SELECT evergreen.upgrade_deps_block_check('1384', :eg_version); -- dbriem, berick, tmccanna

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.holds.pull_list_filters', 'gui', 'object',
    oils_i18n_gettext(
        'eg.holds.pull_list_filters',
        'Holds pull list filter values for pickup library and shelving locations.',
        'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1385', :eg_version); -- mmorgan, rfrasur, tmccanna

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 645, 'ADMIN_USER_BUCKET', oils_i18n_gettext(645,
    'Allow a user to administer User Buckets', 'ppl', 'description'));
INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 646, 'CREATE_USER_BUCKET', oils_i18n_gettext(646,
    'Allow a user to create a User Bucket', 'ppl', 'description'));

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
        SELECT
                pgt.id, perm.id, aout.depth, FALSE
        FROM
                permission.grp_tree pgt,
                permission.perm_list perm,
                actor.org_unit_type aout
        WHERE
                pgt.name = 'Circulators' AND
                aout.name = 'System' AND
                perm.code IN (
                        'ADMIN_USER_BUCKET',
                        'CREATE_USER_BUCKET');

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
        SELECT
                pgt.id, perm.id, aout.depth, FALSE
        FROM
                permission.grp_tree pgt,
                permission.perm_list perm,
                actor.org_unit_type aout
        WHERE
                pgt.name = 'Circulation Administrator' AND
                aout.name = 'System' AND
                perm.code IN (
                        'ADMIN_USER_BUCKET',
                        'CREATE_USER_BUCKET');


SELECT evergreen.upgrade_deps_block_check('1386', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) VALUES (
    647, 'UPDATE_ADDED_CONTENT_URL',
    oils_i18n_gettext(647, 'Update the NoveList added-content javascript URL', 'ppl', 'description')
);

-- Note: see local.syndetics_id as precedence for not requiring view or update perms for credentials

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'staff.added_content.novelistselect.version',
    'gui',
    oils_i18n_gettext('staff.added_content.novelistselect.version',
        'Staff Client added content: NoveList Select API version',
        'coust', 'label'),
    oils_i18n_gettext('staff.added_content.novelistselect.version',
        'API version used to provide NoveList Select added content in the Staff Client',
        'coust', 'description'),
    'string'
);

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'staff.added_content.novelistselect.profile',
    'gui',
    oils_i18n_gettext('staff.added_content.novelistselect.profile',
        'Staff Client added content: NoveList Select profile/user',
        'coust', 'label'),
    oils_i18n_gettext('staff.added_content.novelistselect.profile',
        'Profile/user used to provide NoveList Select added content in the Staff Client',
        'coust', 'description'),
    'string'
);

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'staff.added_content.novelistselect.passwd',
    'gui',
    oils_i18n_gettext('staff.added_content.novelistselect.passwd',
        'Staff Client added content: NoveList Select key/password',
        'coust', 'label'),
    oils_i18n_gettext('staff.added_content.novelistselect.passwd',
        'Key/password used to provide NoveList Select added content in the Staff Client',
        'coust', 'description'),
    'string'
);

INSERT into config.org_unit_setting_type
    (name, datatype, grp, update_perm, label, description)
VALUES (
    'staff.added_content.novelistselect.url', 'string', 'opac', 647,
    oils_i18n_gettext(
        'staff.added_content.novelistselect.url',
        'URL Override for NoveList Select added content javascript',
        'coust', 'label'
    ),
    oils_i18n_gettext(
        'staff.added_content.novelistselect.url',
        'URL Override for NoveList Select added content javascript',
        'coust', 'description'
    )
);


SELECT evergreen.upgrade_deps_block_check('1387', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'opac.uri_default_note_text', 'opac',
    oils_i18n_gettext('opac.uri_default_note_text',
        'Default text to appear for 856 links if none is present',
        'coust', 'label'),
    oils_i18n_gettext('opac.uri_default_note_text',
        'When no value is present in the 856$z this string will be used instead',
        'coust', 'description'),
    'string', null)
;



SELECT evergreen.upgrade_deps_block_check('1388', :eg_version);

UPDATE action_trigger.event_definition
SET delay = '-24:01:00'::INTERVAL
WHERE reactor = 'Circ::AutoRenew'
AND delay = '-23 hours'::INTERVAL
AND max_delay = '-1 minute'::INTERVAL;



SELECT evergreen.upgrade_deps_block_check('1389', :eg_version);

ALTER TABLE acq.provider ADD COLUMN buyer_san TEXT;



SELECT evergreen.upgrade_deps_block_check('1390', :eg_version);

ALTER TABLE actor.org_unit_custom_tree_node
DROP CONSTRAINT org_unit_custom_tree_node_parent_node_fkey;

ALTER TABLE actor.org_unit_custom_tree_node
ADD CONSTRAINT org_unit_custom_tree_node_parent_node_fkey 
FOREIGN KEY (parent_node) 
REFERENCES actor.org_unit_custom_tree_node(id) 
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;


SELECT evergreen.upgrade_deps_block_check('1391', :eg_version);

DROP FUNCTION IF EXISTS evergreen.find_next_open_time(INT, TIMESTAMPTZ, BOOL, TIME, INT); --Get rid of the last version of this function with different arguments so it doesn't cause conflicts when calling it
CREATE OR REPLACE FUNCTION evergreen.find_next_open_time ( circ_lib INT, initial TIMESTAMPTZ, hourly BOOL DEFAULT FALSE, initial_time TIME DEFAULT NULL, has_hoo BOOL DEFAULT TRUE )
    RETURNS TIMESTAMPTZ AS $$
DECLARE
    day_number      INT;
    plus_days       INT;
    final_time      TEXT;
    time_adjusted   BOOL;
    hoo_open        TIME WITHOUT TIME ZONE;
    hoo_close       TIME WITHOUT TIME ZONE;
    adjacent        actor.org_unit_closed%ROWTYPE;
    breakout        INT := 0;
BEGIN

    IF initial_time IS NULL THEN
        initial_time := initial::TIME;
    END IF;

    final_time := (initial + '1 second'::INTERVAL)::TEXT;
    LOOP
        breakout := breakout + 1;

        time_adjusted := FALSE;

        IF has_hoo THEN -- Don't check hours if they have no hoo. I think the behavior in that case is that we act like they're always open? Better than making things due in 2 years.
                        -- Don't expect anyone to call this with it set to false; it's just for our own recursive use.
            day_number := EXTRACT(ISODOW FROM final_time::TIMESTAMPTZ) - 1; --Get which day of the week  it is from which it started on.
            plus_days := 0;
            has_hoo := FALSE; -- set has_hoo to false to check if any days are open (for the first recursion where it's always true)
            FOR i IN 1..7 LOOP
                EXECUTE 'SELECT dow_' || day_number || '_open, dow_' || day_number || '_close FROM actor.hours_of_operation WHERE id = $1'
                    INTO hoo_open, hoo_close
                    USING circ_lib;

                -- RAISE NOTICE 'initial time: %; dow: %; close: %',initial_time,day_number,hoo_close;

                IF hoo_close = '00:00:00' THEN -- bah ... I guess we'll check the next day
                    day_number := (day_number + 1) % 7;
                    plus_days := plus_days + 1;
                    time_adjusted := TRUE;
                    CONTINUE;
                ELSE
                    has_hoo := TRUE; --We do have hours open sometimes, yay!
                END IF;

                IF hoo_close IS NULL THEN -- no hours of operation ... assume no closing?
                    hoo_close := '23:59:59';
                END IF;

                EXIT;
            END LOOP;

            IF NOT has_hoo THEN -- If always closed then forget the extra days - just determine based on closures.
                plus_days := 0;
            END IF;

            final_time := DATE(final_time::TIMESTAMPTZ + (plus_days || ' days')::INTERVAL)::TEXT;
            IF hoo_close <> '00:00:00' AND hourly THEN -- Not a day-granular circ
                final_time := final_time||' '|| hoo_close;
            ELSE
                final_time := final_time||' 23:59:59';
            END IF;
        END IF;

        --RAISE NOTICE 'final_time: %',final_time;

        -- Loop through other closings
        LOOP 
            SELECT * INTO adjacent FROM actor.org_unit_closed WHERE org_unit = circ_lib AND final_time::TIMESTAMPTZ between close_start AND close_end;
            EXIT WHEN adjacent.id IS NULL;
            time_adjusted := TRUE;
            -- RAISE NOTICE 'recursing for closings with final_time: %',final_time;
            final_time := evergreen.find_next_open_time(circ_lib, adjacent.close_end::TIMESTAMPTZ, hourly, initial_time, has_hoo)::TEXT;
        END LOOP;

        EXIT WHEN breakout > 100;
        EXIT WHEN NOT time_adjusted;

    END LOOP;

    RETURN final_time;
END;
$$ LANGUAGE PLPGSQL;


SELECT evergreen.upgrade_deps_block_check('1392', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.acq.fiscal_calendar', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.acq.fiscal_calendar',
        'Grid Config: eg.grid.admin.acq.fiscal_calendar',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.fiscal_year', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.acq.fiscal_year',
        'Grid Config: eg.grid.admin.acq.fiscal_year',
        'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1393', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.staffcat.course_materials_selector', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.staffcat.course_materials_selector',
        'Add the "Reserves material" dropdown to refine search results',
        'cwst', 'label'
    )
);

SELECT evergreen.upgrade_deps_block_check('1394', :eg_version);

ALTER TABLE url_verify.url_selector
    DROP CONSTRAINT url_selector_session_fkey,
    ADD CONSTRAINT url_selector_session_fkey 
        FOREIGN KEY (session) 
        REFERENCES url_verify.session(id) 
        ON UPDATE CASCADE
        ON DELETE CASCADE
        DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE url_verify.url
    DROP CONSTRAINT url_session_fkey,
    DROP CONSTRAINT url_redirect_from_fkey,
    ADD CONSTRAINT url_session_fkey 
        FOREIGN KEY (session) 
        REFERENCES url_verify.session(id) 
        ON UPDATE CASCADE
        ON DELETE CASCADE
        DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT url_redirect_from_fkey
        FOREIGN KEY (redirect_from)
        REFERENCES url_verify.url(id)
        ON UPDATE CASCADE
        ON DELETE CASCADE
        DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE url_verify.verification_attempt
    DROP CONSTRAINT verification_attempt_session_fkey,
    ADD CONSTRAINT verification_attempt_session_fkey 
        FOREIGN KEY (session) 
        REFERENCES url_verify.session(id) 
        ON UPDATE CASCADE
        ON DELETE CASCADE
        DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE url_verify.url_verification
    DROP CONSTRAINT url_verification_url_fkey,
    ADD CONSTRAINT url_verification_url_fkey
        FOREIGN KEY (url)
        REFERENCES url_verify.url(id)
        ON UPDATE CASCADE
        ON DELETE CASCADE
        DEFERRABLE INITIALLY DEFERRED;

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.catalog.link_checker', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.catalog.link_checker',
        'Grid Config: catalog.link_checker',
        'cwst', 'label'
    )
), (
    'eg.grid.catalog.link_checker.attempt', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.catalog.link_checker.attempt',
        'Grid Config: catalog.link_checker.attempt',
        'cwst', 'label'
    )
), (
    'eg.grid.catalog.link_checker.url', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.catalog.link_checker.url',
        'Grid Config: catalog.link_checker.url',
        'cwst', 'label'
    )
), (
    'eg.grid.filters.catalog.link_checker', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.filters.catalog.link_checker',
        'Grid Filter Sets: catalog.link_checker',
        'cwst', 'label'
    )
), (
    'eg.grid.filters.catalog.link_checker.attempt', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.filters.catalog.link_checker.attempt',
        'Grid Filter Sets: catalog.link_checker.attempt',
        'cwst', 'label'
    )
), (
    'eg.grid.filters.catalog.link_checker.url', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.filters.catalog.link_checker.url',
        'Grid Filter Sets: catalog.link_checker.url',
        'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1395', :eg_version);

DELETE FROM actor.org_unit_setting WHERE name IN (
    'opac.did_you_mean.low_result_threshold',
    'opac.did_you_mean.max_suggestions',
    'search.symspell.keyboard_distance.weight',
    'search.symspell.min_suggestion_use_threshold',
    'search.symspell.pg_trgm.weight',
    'search.symspell.soundex.weight'
);

DELETE FROM config.org_unit_setting_type WHERE name IN (
    'opac.did_you_mean.low_result_threshold',
    'opac.did_you_mean.max_suggestions',
    'search.symspell.keyboard_distance.weight',
    'search.symspell.min_suggestion_use_threshold',
    'search.symspell.pg_trgm.weight',
    'search.symspell.soundex.weight'
);

SELECT evergreen.upgrade_deps_block_check('1396', :eg_version);

-- intent of this change done by editing the one for 1393

COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
