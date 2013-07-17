--Upgrade Script for 2.3.8 to 2.3.9
\set eg_version '''2.3.9'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.3.9', :eg_version);

SELECT evergreen.upgrade_deps_block_check('0803', :eg_version);

UPDATE config.org_unit_setting_type 
SET description = oils_i18n_gettext('circ.holds.default_shelf_expire_interval',
        'The amount of time an item will be held on the shelf before the hold expires. For example: "2 weeks" or "5 days"',
        'coust', 'description')
WHERE name = 'circ.holds.default_shelf_expire_interval';


SELECT evergreen.upgrade_deps_block_check('0804', :eg_version);

UPDATE config.coded_value_map
SET value = oils_i18n_gettext('169', 'Gwich''in', 'ccvm', 'value')
WHERE ctype = 'item_lang' AND code = 'gwi';

-- Evergreen DB patch XXXX.schema.usrname_index.sql
--
-- Create search index on actor.usr.usrname
--

SELECT evergreen.upgrade_deps_block_check('0808', :eg_version);

CREATE INDEX actor_usr_usrname_idx ON actor.usr (evergreen.lowercase(usrname));


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0810', :eg_version);

UPDATE authority.control_set_authority_field
    SET name = REGEXP_REPLACE(name, '^See Also', 'See From')
    WHERE tag LIKE '4__' AND control_set = 1;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0811', :eg_version);

DROP FUNCTION action.copy_related_hold_stats(integer);

CREATE OR REPLACE FUNCTION action.copy_related_hold_stats(copy_id bigint)
  RETURNS action.hold_stats AS
$BODY$
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
            IF hold_map_data.status IN (0,7,12) THEN
                output.available_count := output.available_count + 1;
            END IF;
        END LOOP;
        output.total_copy_ratio = output.copy_count::FLOAT / output.hold_count::FLOAT;
        output.available_copy_ratio = output.available_count::FLOAT / output.hold_count::FLOAT;

    END IF;

    RETURN output;

END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;


COMMIT;
