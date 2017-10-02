--Upgrade Script for 2.12.6 to 3.0.0
\set eg_version '''3.0.0'''

-- verify that we're running a recent enough version of Pg
\set ON_ERROR_STOP on
BEGIN;

DO $$
   DECLARE ver INTEGER;
   BEGIN
      SELECT current_setting('server_version_num') INTO ver;
      IF (ver < 90400) THEN
         RAISE EXCEPTION 'Not running a new enough version of PostgreSQL. Minimum required is 9.4; you have %', ver;
      END IF;
   END;
$$;

COMMIT;
\set ON_ERROR_STOP off

BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.0-beta1', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1032', :eg_version); -- Bmagic/csharp/gmcharlt

CREATE OR REPLACE VIEW action.all_circulation_combined_types AS 
 SELECT acirc.id AS id,
    acirc.xact_start,
    acirc.circ_lib,
    acirc.circ_staff,
    acirc.create_time,
    ac_acirc.circ_modifier AS item_type,
    'regular_circ'::text AS circ_type
   FROM action.circulation acirc,
    asset.copy ac_acirc
  WHERE acirc.target_copy = ac_acirc.id
UNION ALL
 SELECT ancc.id::BIGINT AS id,
    ancc.circ_time AS xact_start,
    ancc.circ_lib,
    ancc.staff AS circ_staff,
    ancc.circ_time AS create_time,
    cnct_ancc.name AS item_type,
    'non-cat_circ'::text AS circ_type
   FROM action.non_cataloged_circulation ancc,
    config.non_cataloged_type cnct_ancc
  WHERE ancc.item_type = cnct_ancc.id
UNION ALL
 SELECT aihu.id::BIGINT AS id,
    aihu.use_time AS xact_start,
    aihu.org_unit AS circ_lib,
    aihu.staff AS circ_staff,
    aihu.use_time AS create_time,
    ac_aihu.circ_modifier AS item_type,
    'in-house_use'::text AS circ_type
   FROM action.in_house_use aihu,
    asset.copy ac_aihu
  WHERE aihu.item = ac_aihu.id
UNION ALL
 SELECT ancihu.id::BIGINT AS id,
    ancihu.use_time AS xact_start,
    ancihu.org_unit AS circ_lib,
    ancihu.staff AS circ_staff,
    ancihu.use_time AS create_time,
    cnct_ancihu.name AS item_type,
    'non-cat_circ'::text AS circ_type
   FROM action.non_cat_in_house_use ancihu,
    config.non_cataloged_type cnct_ancihu
  WHERE ancihu.item_type = cnct_ancihu.id
UNION ALL
 SELECT aacirc.id AS id,
    aacirc.xact_start,
    aacirc.circ_lib,
    aacirc.circ_staff,
    aacirc.create_time,
    ac_aacirc.circ_modifier AS item_type,
    'aged_circ'::text AS circ_type
   FROM action.aged_circulation aacirc,
    asset.copy ac_aacirc
  WHERE aacirc.target_copy = ac_aacirc.id;


SELECT evergreen.upgrade_deps_block_check('1034', :eg_version);

ALTER TABLE config.hold_matrix_matchpoint
    ADD COLUMN description TEXT;

ALTER TABLE config.circ_matrix_matchpoint
    ADD COLUMN description TEXT;


INSERT INTO config.upgrade_log (version, applied_to) VALUES ('1035', :eg_version); -- dyrcona/gmcharlt

-- Per Lp bug 1684984, the config.internal_flag,
-- ingest.disable_metabib_field_entry, was made obsolete by the
-- addition of the ingest.skip_browse_indexing,
-- ingest.skip_search_indexing, and ingest.skip_facet_indexing flags.
-- Since it is not used in the database, we delete it.
DELETE FROM config.internal_flag
WHERE name = 'ingest.disable_metabib_field_entry';


SELECT evergreen.upgrade_deps_block_check('1036', :eg_version);

CREATE OR REPLACE FUNCTION config.update_hard_due_dates () RETURNS INT AS $func$
DECLARE
    temp_value  config.hard_due_date_values%ROWTYPE;
    updated     INT := 0;
BEGIN
    FOR temp_value IN
      SELECT  DISTINCT ON (hard_due_date) *
        FROM  config.hard_due_date_values
        WHERE active_date <= NOW() -- We've passed (or are at) the rollover time
        ORDER BY hard_due_date, active_date DESC -- Latest (nearest to us) active time
   LOOP
        UPDATE  config.hard_due_date
          SET   ceiling_date = temp_value.ceiling_date
          WHERE id = temp_value.hard_due_date
                AND ceiling_date <> temp_value.ceiling_date -- Time is equal if we've already updated the chdd
                AND temp_value.ceiling_date >= NOW(); -- Don't update ceiling dates to the past

        IF FOUND THEN
            updated := updated + 1;
        END IF;
    END LOOP;

    RETURN updated;
END;
$func$ LANGUAGE plpgsql;


INSERT INTO config.upgrade_log (version, applied_to) VALUES ('1041', :eg_version); -- stompro/csharp/gmcharlt

--delete all instances from permission.grp_perm_map first
DELETE FROM permission.grp_perm_map where perm in 
(select id from permission.perm_list where code='SET_CIRC_MISSING');

--delete all instances from permission.usr_perm_map too
DELETE FROM permission.usr_perm_map where perm in
(select id from permission.perm_list where code='SET_CIRC_MISSING');

--delete from permission.perm_list
DELETE FROM permission.perm_list where code='SET_CIRC_MISSING';


INSERT INTO config.upgrade_log (version, applied_to) VALUES ('1042', :eg_version); -- mmorgan/gmcharlt

ALTER TABLE asset.copy_location
          ADD COLUMN url TEXT;


SELECT evergreen.upgrade_deps_block_check('1043', :eg_version);

ALTER TABLE action_trigger.event_definition
    ADD COLUMN retention_interval INTERVAL;

CREATE OR REPLACE FUNCTION action_trigger.check_valid_retention_interval() 
    RETURNS TRIGGER AS $_$
BEGIN

    /*
     * 1. Retention intervals are alwyas allowed on active hooks.
     * 2. On passive hooks, retention intervals are only allowed
     *    when the event definition has a max_delay value and the
     *    retention_interval value is greater than the difference 
     *    beteween the delay and max_delay values.
     */ 
    PERFORM TRUE FROM action_trigger.hook 
        WHERE key = NEW.hook AND NOT passive;

    IF FOUND THEN
        RETURN NEW;
    END IF;

    IF NEW.max_delay IS NOT NULL THEN
        IF EXTRACT(EPOCH FROM NEW.retention_interval) > 
            ABS(EXTRACT(EPOCH FROM (NEW.max_delay - NEW.delay))) THEN
            RETURN NEW; -- all good
        ELSE
            RAISE EXCEPTION 'retention_interval is too short';
        END IF;
    ELSE
        RAISE EXCEPTION 'retention_interval requires max_delay';
    END IF;
END;
$_$ LANGUAGE PLPGSQL;

CREATE TRIGGER is_valid_retention_interval 
    BEFORE INSERT OR UPDATE ON action_trigger.event_definition
    FOR EACH ROW WHEN (NEW.retention_interval IS NOT NULL)
    EXECUTE PROCEDURE action_trigger.check_valid_retention_interval();

CREATE OR REPLACE FUNCTION action_trigger.purge_events() RETURNS VOID AS $_$
/**
  * Deleting expired events without simultaneously deleting their outputs
  * creates orphaned outputs.  Deleting their outputs and all of the events 
  * linking back to them, plus any outputs those events link to is messy and 
  * inefficient.  It's simpler to handle them in 2 sweeping steps.
  *
  * 1. Delete expired events.
  * 2. Delete orphaned event outputs.
  *
  * This has the added benefit of removing outputs that may have been
  * orphaned by some other process.  Such outputs are not usuable by
  * the system.
  *
  * This does not guarantee that all events within an event group are
  * purged at the same time.  In such cases, the remaining events will
  * be purged with the next instance of the purge (or soon thereafter).
  * This is another nod toward efficiency over completeness of old 
  * data that's circling the bit bucket anyway.
  */
BEGIN

    DELETE FROM action_trigger.event WHERE id IN (
        SELECT evt.id
        FROM action_trigger.event evt
        JOIN action_trigger.event_definition def ON (def.id = evt.event_def)
        WHERE def.retention_interval IS NOT NULL 
            AND evt.state <> 'pending'
            AND evt.update_time < (NOW() - def.retention_interval)
    );

    WITH linked_outputs AS (
        SELECT templates.id AS id FROM (
            SELECT DISTINCT(template_output) AS id
                FROM action_trigger.event WHERE template_output IS NOT NULL
            UNION
            SELECT DISTINCT(error_output) AS id
                FROM action_trigger.event WHERE error_output IS NOT NULL
            UNION
            SELECT DISTINCT(async_output) AS id
                FROM action_trigger.event WHERE async_output IS NOT NULL
        ) templates
    ) DELETE FROM action_trigger.event_output
        WHERE id NOT IN (SELECT id FROM linked_outputs);

END;
$_$ LANGUAGE PLPGSQL;


/* -- UNDO --

DROP FUNCTION IF EXISTS action_trigger.purge_events();
DROP TRIGGER IF EXISTS is_valid_retention_interval ON action_trigger.event_definition;
DROP FUNCTION IF EXISTS action_trigger.check_valid_retention_interval();
ALTER TABLE action_trigger.event_definition DROP COLUMN retention_interval;

*/



SELECT evergreen.upgrade_deps_block_check('1044', :eg_version);

UPDATE action_trigger.hook SET passive = FALSE WHERE key IN (
    'format.po.html',
    'format.po.pdf',
    'format.selfcheck.checkout',
    'format.selfcheck.items_out',
    'format.selfcheck.holds',
    'format.selfcheck.fines',
    'format.acqcle.html',
    'format.acqinv.html',
    'format.acqli.html',
    'aur.ordered',
    'aur.received',
    'aur.cancelled',
    'aur.created',
    'aur.rejected'
);


INSERT INTO config.upgrade_log (version, applied_to) VALUES ('1045', :eg_version); -- csharp/berick/gmcharlt

ALTER TABLE action.transit_copy
	ADD COLUMN cancel_time TIMESTAMPTZ;

-- change "abort" to "cancel" in stock perm descriptions
UPDATE permission.perm_list 
	SET description = 'Allow a user to cancel a copy transit if the user is at the transit destination or source' 
	WHERE code = 'ABORT_TRANSIT'
	AND description = 'Allow a user to abort a copy transit if the user is at the transit destination or source';
UPDATE permission.perm_list 
	SET description = 'Allow a user to cancel a copy transit if the user is not at the transit source or dest' 
	WHERE code = 'ABORT_REMOTE_TRANSIT'
	AND description = 'Allow a user to abort a copy transit if the user is not at the transit source or dest';
UPDATE permission.perm_list 
	SET description = 'Allows a user to cancel a transit on a copy with status of LOST' 
	WHERE code = 'ABORT_TRANSIT_ON_LOST'
	AND description = 'Allows a user to abort a transit on a copy with status of LOST';
UPDATE permission.perm_list 
	SET description = 'Allows a user to cancel a transit on a copy with status of MISSING' 
	WHERE code = 'ABORT_TRANSIT_ON_MISSING'
	AND description = 'Allows a user to abort a transit on a copy with status of MISSING';

SELECT evergreen.upgrade_deps_block_check('1046', :eg_version); -- phasefx/berick/gmcharlt

INSERT into config.org_unit_setting_type (
     name
    ,grp
    ,label
    ,description
    ,datatype
) VALUES ( ----------------------------------------
     'webstaff.format.dates'
    ,'gui'
    ,oils_i18n_gettext(
         'webstaff.format.dates'
        ,'Format Dates with this pattern'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.format.dates'
        ,'Format Dates with this pattern (examples: "yyyy-MM-dd" for "2010-04-26", "MMM d, yyyy" for "Apr 26, 2010").  This will be used in areas where a date without a timestamp is sufficient, like Date of Birth.'
        ,'coust'
        ,'description'
    )
    ,'string'
), ( ----------------------------------------
     'webstaff.format.date_and_time'
    ,'gui'
    ,oils_i18n_gettext(
         'webstaff.format.date_and_time'
        ,'Format Date+Time with this pattern'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.format.date_and_time'
        ,'Format Date+Time with this pattern (examples: "yy-MM-dd h:m:s.SSS a" for "16-04-05 2:07:20.666 PM", "yyyy-dd-MMM HH:mm" for "2016-05-Apr 14:07").  This will be used in areas of the client where a date with a timestamp is needed, like Checkout, Due Date, or Record Created.'
        ,'coust'
        ,'description'
    )
    ,'string'
);

UPDATE
    config.org_unit_setting_type
SET
    label = 'Deprecated: ' || label -- FIXME: Is this okay?
WHERE
    name IN ('format.date','format.time')
;


SELECT evergreen.upgrade_deps_block_check('1047', :eg_version); -- gmcharlt/stompro

CREATE TABLE config.copy_tag_type (
    code            TEXT NOT NULL PRIMARY KEY,
    label           TEXT NOT NULL,
    owner           INTEGER NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX config_copy_tag_type_owner_idx
    ON config.copy_tag_type (owner);

CREATE TABLE asset.copy_tag (
    id              SERIAL PRIMARY KEY,
    tag_type        TEXT REFERENCES config.copy_tag_type (code)
                    ON UPDATE CASCADE ON DELETE CASCADE,
    label           TEXT NOT NULL,
    value           TEXT NOT NULL,
    index_vector    tsvector NOT NULL,
    staff_note      TEXT,
    pub             BOOLEAN DEFAULT TRUE,
    owner           INTEGER NOT NULL REFERENCES actor.org_unit (id)
);

CREATE INDEX asset_copy_tag_label_idx
    ON asset.copy_tag (label);
CREATE INDEX asset_copy_tag_label_lower_idx
    ON asset.copy_tag (evergreen.lowercase(label));
CREATE INDEX asset_copy_tag_index_vector_idx
    ON asset.copy_tag
    USING GIN(index_vector);
CREATE INDEX asset_copy_tag_tag_type_idx
    ON asset.copy_tag (tag_type);
CREATE INDEX asset_copy_tag_owner_idx
    ON asset.copy_tag (owner);

CREATE OR REPLACE FUNCTION asset.set_copy_tag_value () RETURNS TRIGGER AS $$
BEGIN
    IF NEW.value IS NULL THEN
        NEW.value = NEW.label;        
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';

-- name of following trigger chosen to ensure it runs first
CREATE TRIGGER asset_copy_tag_do_value
    BEFORE INSERT OR UPDATE ON asset.copy_tag
    FOR EACH ROW EXECUTE PROCEDURE asset.set_copy_tag_value();
CREATE TRIGGER asset_copy_tag_fti_trigger
    BEFORE UPDATE OR INSERT ON asset.copy_tag
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('default');

CREATE TABLE asset.copy_tag_copy_map (
    id              BIGSERIAL PRIMARY KEY,
    copy            BIGINT REFERENCES asset.copy (id)
                    ON UPDATE CASCADE ON DELETE CASCADE,
    tag             INTEGER REFERENCES asset.copy_tag (id)
                    ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE INDEX asset_copy_tag_copy_map_copy_idx
    ON asset.copy_tag_copy_map (copy);
CREATE INDEX asset_copy_tag_copy_map_tag_idx
    ON asset.copy_tag_copy_map (tag);

INSERT INTO config.copy_tag_type (code, label, owner) VALUES ('bookplate', 'Digital Bookplate', 1);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 590, 'ADMIN_COPY_TAG_TYPES', oils_i18n_gettext( 590,
    'Administer copy tag types', 'ppl', 'description' )),
 ( 591, 'ADMIN_COPY_TAG', oils_i18n_gettext( 591,
    'Administer copy tag', 'ppl', 'description' ))
;

INSERT INTO config.org_unit_setting_type
    (name, label, description, grp, datatype)
VALUES (
    'opac.search.enable_bookplate_search',
    oils_i18n_gettext(
        'opac.search.enable_bookplate_search',
        'Enable Digital Bookplate Search',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'opac.search.enable_bookplate_search',
        'If enabled, adds a "Digital Bookplate" option to the query type selectors in the public catalog for search on copy tags.',   
        'coust',
        'description'
    ),
    'opac',
    'bool'
);


SELECT evergreen.upgrade_deps_block_check('1048', :eg_version);

INSERT into config.org_unit_setting_type (
     name
    ,grp
    ,label
    ,description
    ,datatype
) VALUES ( ----------------------------------------
     'webstaff.cat.label.font.family'
    ,'cat'
    ,oils_i18n_gettext(
         'webstaff.cat.label.font.family'
        ,'Item Print Label Font Family'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.cat.label.font.family'
        ,'Set the preferred font family for item print labels. You can specify a list of CSS fonts, separated by commas, in order of preference; the system will use the first font it finds with a matching name. For example, "Arial, Helvetica, serif"'
        ,'coust'
        ,'description'
    )
    ,'string'
), ( ----------------------------------------
     'webstaff.cat.label.font.size'
    ,'cat'
    ,oils_i18n_gettext(
         'webstaff.cat.label.font.size'
        ,'Item Print Label Font Size'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.cat.label.font.size'
        ,'Set the default font size for item print labels. Please include a unit of measurement that is valid CSS. For example, "12pt" or "16px" or "1em"'
        ,'coust'
        ,'description'
    )
    ,'string'
), ( ----------------------------------------
     'webstaff.cat.label.font.weight'
    ,'cat'
    ,oils_i18n_gettext(
         'webstaff.cat.label.font.weight'
        ,'Item Print Label Font Weight'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.cat.label.font.weight'
        ,'Set the default font weight for item print labels. Please use the CSS specification for values for font-weight.  For example, "normal", "bold", "bolder", or "lighter"'
        ,'coust'
        ,'description'
    )
    ,'string'
), ( ----------------------------------------
     'webstaff.cat.label.left_label.left_margin'
    ,'cat'
    ,oils_i18n_gettext(
         'webstaff.cat.label.left_label.left_margin'
        ,'Item Print Label - Left Margin for Left Label'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.cat.label.left_label.left_margin'
        ,'Set the default left margin for the leftmost item print Label. Please include a unit of measurement that is valid CSS. For example, "1in" or "2.5cm"'
        ,'coust'
        ,'description'
    )
    ,'string'
), ( ----------------------------------------
     'webstaff.cat.label.right_label.left_margin'
    ,'cat'
    ,oils_i18n_gettext(
         'webstaff.cat.label.right_label.left_margin'
        ,'Item Print Label - Left Margin for Right Label'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.cat.label.right_label.left_margin'
        ,'Set the default left margin for the rightmost item print label (or in other words, the desired space between the two labels). Please include a unit of measurement that is valid CSS. For example, "1in" or "2.5cm"'
        ,'coust'
        ,'description'
    )
    ,'string'
), ( ----------------------------------------
     'webstaff.cat.label.left_label.height'
    ,'cat'
    ,oils_i18n_gettext(
         'webstaff.cat.label.left_label.height'
        ,'Item Print Label - Height for Left Label'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.cat.label.left_label.height'
        ,'Set the default height for the leftmost item print label. Please include a unit of measurement that is valid CSS. For example, "1in" or "2.5cm"'
        ,'coust'
        ,'description'
    )
    ,'string'
), ( ----------------------------------------
     'webstaff.cat.label.left_label.width'
    ,'cat'
    ,oils_i18n_gettext(
         'webstaff.cat.label.left_label.width'
        ,'Item Print Label - Width for Left Label'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.cat.label.left_label.width'
        ,'Set the default width for the leftmost item print label. Please include a unit of measurement that is valid CSS. For example, "1in" or "2.5cm"'
        ,'coust'
        ,'description'
    )
    ,'string'
), ( ----------------------------------------
     'webstaff.cat.label.right_label.height'
    ,'cat'
    ,oils_i18n_gettext(
         'webstaff.cat.label.right_label.height'
        ,'Item Print Label - Height for Right Label'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.cat.label.right_label.height'
        ,'Set the default height for the rightmost item print label. Please include a unit of measurement that is valid CSS. For example, "1in" or "2.5cm"'
        ,'coust'
        ,'description'
    )
    ,'string'
), ( ----------------------------------------
     'webstaff.cat.label.right_label.width'
    ,'cat'
    ,oils_i18n_gettext(
         'webstaff.cat.label.right_label.width'
        ,'Item Print Label - Width for Right Label'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.cat.label.right_label.width'
        ,'Set the default width for the rightmost item print label. Please include a unit of measurement that is valid CSS. For example, "1in" or "2.5cm"'
        ,'coust'
        ,'description'
    )
    ,'string'
), (
     'webstaff.cat.label.inline_css'
    ,'cat'
    ,oils_i18n_gettext(
         'webstaff.cat.label.inline_css'
        ,'Item Print Label - Inline CSS'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.cat.label.inline_css'
        ,'This setting allows you to inject arbitrary CSS into the item print label template.  For example, ".printlabel { text-transform: uppercase; }"'
        ,'coust'
        ,'description'
    )
    ,'string'
), (
     'webstaff.cat.label.call_number_wrap_filter_height'
    ,'cat'
    ,oils_i18n_gettext(
         'webstaff.cat.label.call_number_wrap_filter_height'
        ,'Item Print Label - Call Number Wrap Filter Height'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.cat.label.call_number_wrap_filter_height'
        ,'This setting is used to set the default height (in number of lines) to use for call number wrapping in the left print label.'
        ,'coust'
        ,'description'
    )
    ,'integer'
), (
     'webstaff.cat.label.call_number_wrap_filter_width'
    ,'cat'
    ,oils_i18n_gettext(
         'webstaff.cat.label.call_number_wrap_filter_width'
        ,'Item Print Label - Call Number Wrap Filter Width'
        ,'coust'
        ,'label'
    )
    ,oils_i18n_gettext(
         'webstaff.cat.label.call_number_wrap_filter_width'
        ,'This setting is used to set the default width (in number of characters) to use for call number wrapping in the left print label.'
        ,'coust'
        ,'description'
    )
    ,'integer'


);

-- for testing, setting removal:
--DELETE FROM actor.org_unit_setting WHERE name IN (
--     'webstaff.cat.label.font.family'
--    ,'webstaff.cat.label.font.size'
--    ,'webstaff.cat.label.font.weight'
--    ,'webstaff.cat.label.left_label.height'
--    ,'webstaff.cat.label.left_label.width'
--    ,'webstaff.cat.label.left_label.left_margin'
--    ,'webstaff.cat.label.right_label.height'
--    ,'webstaff.cat.label.right_label.width'
--    ,'webstaff.cat.label.right_label.left_margin'
--    ,'webstaff.cat.label.inline_css'
--    ,'webstaff.cat.label.call_number_wrap_filter_height'
--    ,'webstaff.cat.label.call_number_wrap_filter_width'
--);
--DELETE FROM config.org_unit_setting_type_log WHERE field_name IN (
--     'webstaff.cat.label.font.family'
--    ,'webstaff.cat.label.font.size'
--    ,'webstaff.cat.label.font.weight'
--    ,'webstaff.cat.label.left_label.height'
--    ,'webstaff.cat.label.left_label.width'
--    ,'webstaff.cat.label.left_label.left_margin'
--    ,'webstaff.cat.label.right_label.height'
--    ,'webstaff.cat.label.right_label.width'
--    ,'webstaff.cat.label.right_label.left_margin'
--    ,'webstaff.cat.label.inline_css'
--    ,'webstaff.cat.label.call_number_wrap_filter_height'
--    ,'webstaff.cat.label.call_number_wrap_filter_width'
--);
--DELETE FROM config.org_unit_setting_type WHERE name IN (
--     'webstaff.cat.label.font.family'
--    ,'webstaff.cat.label.font.size'
--    ,'webstaff.cat.label.font.weight'
--    ,'webstaff.cat.label.left_label.height'
--    ,'webstaff.cat.label.left_label.width'
--    ,'webstaff.cat.label.left_label.left_margin'
--    ,'webstaff.cat.label.right_label.height'
--    ,'webstaff.cat.label.right_label.width'
--    ,'webstaff.cat.label.right_label.left_margin'
--    ,'webstaff.cat.label.inline_css'
--    ,'webstaff.cat.label.call_number_wrap_filter_height'
--    ,'webstaff.cat.label.call_number_wrap_filter_width'
--);



SELECT evergreen.upgrade_deps_block_check('1049', :eg_version); -- mmorgan/stompro/gmcharlt

\echo -----------------------------------------------------------
\echo Setting invalid age_protect and circ_as_type entries to NULL,
\echo otherwise they will break the Serial Copy Templates editor.
\echo Please review any Serial Copy Templates listed below.
\echo
UPDATE asset.copy_template act
SET age_protect = NULL
FROM actor.org_unit aou
WHERE aou.id=act.owning_lib
   AND act.age_protect NOT IN
   (
   SELECT id FROM config.rule_age_hold_protect
   )
RETURNING act.id "Template ID", act.name "Template Name",
          aou.shortname "Owning Lib",
          'Age Protection value reset to null.' "Description";

UPDATE asset.copy_template act
SET circ_as_type = NULL
FROM actor.org_unit aou
WHERE aou.id=act.owning_lib
   AND act.circ_as_type NOT IN
   (
   SELECT code FROM config.item_type_map
   )
RETURNING act.id "Template ID", act.name "Template Name",
          aou.shortname "Owning Lib",
          'Circ as Type value reset to null.' as "Description";

\echo -----------End Serial Template Fix----------------

SELECT evergreen.upgrade_deps_block_check('1050', :eg_version); -- mmorgan/cesardv/gmcharlt

CREATE OR REPLACE FUNCTION permission.usr_perms ( INT ) RETURNS SETOF permission.usr_perm_map AS $$
    SELECT	DISTINCT ON (usr,perm) *
	  FROM	(
			(SELECT * FROM permission.usr_perm_map WHERE usr = $1)
            UNION ALL
			(SELECT	-p.id, $1 AS usr, p.perm, p.depth, p.grantable
			  FROM	permission.grp_perm_map p
			  WHERE	p.grp IN (
      SELECT	(permission.grp_ancestors(
      (SELECT profile FROM actor.usr WHERE id = $1)
					)).id
				)
			)
            UNION ALL
			(SELECT	-p.id, $1 AS usr, p.perm, p.depth, p.grantable
			  FROM	permission.grp_perm_map p
			  WHERE	p.grp IN (SELECT (permission.grp_ancestors(m.grp)).id FROM permission.usr_grp_map m WHERE usr = $1))
		) AS x
	  ORDER BY 2, 3, 4 ASC, 5 DESC ;
$$ LANGUAGE SQL STABLE ROWS 10;

SELECT evergreen.upgrade_deps_block_check('1051', :eg_version);

CREATE OR REPLACE VIEW action.all_circulation_slim AS
    SELECT
        id,
        usr,
        xact_start,
        xact_finish,
        unrecovered,
        target_copy,
        circ_lib,
        circ_staff,
        checkin_staff,
        checkin_lib,
        renewal_remaining,
        grace_period,
        due_date,
        stop_fines_time,
        checkin_time,
        create_time,
        duration,
        fine_interval,
        recurring_fine,
        max_fine,
        phone_renewal,
        desk_renewal,
        opac_renewal,
        duration_rule,
        recurring_fine_rule,
        max_fine_rule,
        stop_fines,
        workstation,
        checkin_workstation,
        copy_location,
        checkin_scan_time,
        parent_circ
    FROM action.circulation
UNION ALL
    SELECT
        id,
        NULL AS usr,
        xact_start,
        xact_finish,
        unrecovered,
        target_copy,
        circ_lib,
        circ_staff,
        checkin_staff,
        checkin_lib,
        renewal_remaining,
        grace_period,
        due_date,
        stop_fines_time,
        checkin_time,
        create_time,
        duration,
        fine_interval,
        recurring_fine,
        max_fine,
        phone_renewal,
        desk_renewal,
        opac_renewal,
        duration_rule,
        recurring_fine_rule,
        max_fine_rule,
        stop_fines,
        workstation,
        checkin_workstation,
        copy_location,
        checkin_scan_time,
        parent_circ
    FROM action.aged_circulation
;

DROP FUNCTION action.summarize_all_circ_chain(INTEGER);
DROP FUNCTION action.all_circ_chain(INTEGER);

CREATE OR REPLACE FUNCTION action.all_circ_chain (ctx_circ_id INTEGER) 
    RETURNS SETOF action.all_circulation_slim AS $$
DECLARE
    tmp_circ action.all_circulation_slim%ROWTYPE;
    circ_0 action.all_circulation_slim%ROWTYPE;
BEGIN

    SELECT INTO tmp_circ * FROM action.all_circulation_slim WHERE id = ctx_circ_id;

    IF tmp_circ IS NULL THEN
        RETURN NEXT tmp_circ;
    END IF;
    circ_0 := tmp_circ;

    -- find the front of the chain
    WHILE TRUE LOOP
        SELECT INTO tmp_circ * FROM action.all_circulation_slim 
            WHERE id = tmp_circ.parent_circ;
        IF tmp_circ IS NULL THEN
            EXIT;
        END IF;
        circ_0 := tmp_circ;
    END LOOP;

    -- now send the circs to the caller, oldest to newest
    tmp_circ := circ_0;
    WHILE TRUE LOOP
        IF tmp_circ IS NULL THEN
            EXIT;
        END IF;
        RETURN NEXT tmp_circ;
        SELECT INTO tmp_circ * FROM action.all_circulation_slim 
            WHERE parent_circ = tmp_circ.id;
    END LOOP;

END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION action.summarize_all_circ_chain 
    (ctx_circ_id INTEGER) RETURNS action.circ_chain_summary AS $$

DECLARE

    -- first circ in the chain
    circ_0 action.all_circulation_slim%ROWTYPE;

    -- last circ in the chain
    circ_n action.all_circulation_slim%ROWTYPE;

    -- circ chain under construction
    chain action.circ_chain_summary;
    tmp_circ action.all_circulation_slim%ROWTYPE;

BEGIN
    
    chain.num_circs := 0;
    FOR tmp_circ IN SELECT * FROM action.all_circ_chain(ctx_circ_id) LOOP

        IF chain.num_circs = 0 THEN
            circ_0 := tmp_circ;
        END IF;

        chain.num_circs := chain.num_circs + 1;
        circ_n := tmp_circ;
    END LOOP;

    chain.start_time := circ_0.xact_start;
    chain.last_stop_fines := circ_n.stop_fines;
    chain.last_stop_fines_time := circ_n.stop_fines_time;
    chain.last_checkin_time := circ_n.checkin_time;
    chain.last_checkin_scan_time := circ_n.checkin_scan_time;
    SELECT INTO chain.checkout_workstation name FROM actor.workstation WHERE id = circ_0.workstation;
    SELECT INTO chain.last_checkin_workstation name FROM actor.workstation WHERE id = circ_n.checkin_workstation;

    IF chain.num_circs > 1 THEN
        chain.last_renewal_time := circ_n.xact_start;
        SELECT INTO chain.last_renewal_workstation name FROM actor.workstation WHERE id = circ_n.workstation;
    END IF;

    RETURN chain;

END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION rating.percent_time_circulating(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    PERFORM rating.precalc_bibs_by_copy(badge_id);

    DELETE FROM precalc_copy_filter_bib_list WHERE id NOT IN (
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_list
    );

    ANALYZE precalc_copy_filter_bib_list;

    RETURN QUERY
     SELECT bib,
            SUM(COALESCE(circ_time,0))::NUMERIC / SUM(age)::NUMERIC
      FROM  (SELECT cn.record AS bib,
                    cp.id,
                    EXTRACT( EPOCH FROM AGE(cp.active_date) ) + 1 AS age,
                    SUM(  -- time copy spent circulating
                        EXTRACT(
                            EPOCH FROM
                            AGE(
                                COALESCE(circ.checkin_time, circ.stop_fines_time, NOW()),
                                circ.xact_start
                            )
                        )
                    )::NUMERIC AS circ_time
              FROM  asset.copy cp
                    JOIN precalc_copy_filter_bib_list c ON (cp.id = c.copy)
                    JOIN asset.call_number cn ON (cn.id = cp.call_number)
                    LEFT JOIN action.all_circulation_slim circ ON (
                        circ.target_copy = cp.id
                        AND stop_fines NOT IN (
                            'LOST',
                            'LONGOVERDUE',
                            'CLAIMSRETURNED',
                            'LONGOVERDUE'
                        )
                        AND NOT (
                            checkin_time IS NULL AND
                            stop_fines = 'MAXFINES'
                        )
                    )
              WHERE cn.owning_lib = ANY (badge.orgs)
                    AND cp.active_date IS NOT NULL
                    -- Next line requires that copies with no circs (circ.id IS NULL) also not be deleted
                    AND ((circ.id IS NULL AND NOT cp.deleted) OR circ.id IS NOT NULL)
              GROUP BY 1,2,3
            ) x
      GROUP BY 1;
END;
$f$ LANGUAGE PLPGSQL STRICT;


-- ROLLBACK;


SELECT evergreen.upgrade_deps_block_check('1052', :eg_version);

CREATE OR REPLACE FUNCTION rating.inhouse_over_time(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
    iage    INT     := 1;
    iint    INT     := NULL;
    iscale  NUMERIC := NULL;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    IF badge.horizon_age IS NULL THEN
        RAISE EXCEPTION 'Badge "%" with id % requires a horizon age but has none.',
            badge.name,
            badge.id;
    END IF;

    PERFORM rating.precalc_bibs_by_copy(badge_id);

    DELETE FROM precalc_copy_filter_bib_list WHERE id NOT IN (
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_list
    );

    ANALYZE precalc_copy_filter_bib_list;

    iint := EXTRACT(EPOCH FROM badge.importance_interval);
    IF badge.importance_age IS NOT NULL THEN
        iage := (EXTRACT(EPOCH FROM badge.importance_age) / iint)::INT;
    END IF;

    -- if iscale is smaller than 1, scaling slope will be shallow ... BEWARE!
    iscale := COALESCE(badge.importance_scale, 1.0);

    RETURN QUERY
     SELECT bib,
            SUM( uses * GREATEST( iscale * (iage - cage), 1.0 ))
      FROM (
         SELECT cn.record AS bib,
                (1 + EXTRACT(EPOCH FROM AGE(u.use_time)) / iint)::INT AS cage,
                COUNT(u.id)::INT AS uses
          FROM  action.in_house_use u
                JOIN precalc_copy_filter_bib_list cf ON (u.item = cf.copy)
                JOIN asset.copy cp ON (cp.id = u.item)
                JOIN asset.call_number cn ON (cn.id = cp.call_number)
          WHERE u.use_time >= NOW() - badge.horizon_age
                AND cn.owning_lib = ANY (badge.orgs)
          GROUP BY 1, 2
      ) x
      GROUP BY 1;
END;
$f$ LANGUAGE PLPGSQL STRICT;

INSERT INTO rating.popularity_parameter (id, name, func, require_horizon,require_percentile) VALUES
    (18,'In-House Use Over Time', 'rating.inhouse_over_time', TRUE, TRUE);



SELECT evergreen.upgrade_deps_block_check('1053', :eg_version);

CREATE OR REPLACE FUNCTION rating.org_unit_count(badge_id INT)
    RETURNS TABLE (record INT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    PERFORM rating.precalc_bibs_by_copy(badge_id);

    DELETE FROM precalc_copy_filter_bib_list WHERE id NOT IN (
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_list
    );
    ANALYZE precalc_copy_filter_bib_list;

    -- Use circ rather than owning lib here as that means "on the shelf at..."
    RETURN QUERY
     SELECT f.id::INT AS bib,
            COUNT(DISTINCT cp.circ_lib)::NUMERIC
     FROM asset.copy cp
          JOIN precalc_copy_filter_bib_list f ON (cp.id = f.copy)
     WHERE cp.circ_lib = ANY (badge.orgs) GROUP BY 1;

END;
$f$ LANGUAGE PLPGSQL STRICT;

INSERT INTO rating.popularity_parameter (id, name, func, require_percentile) VALUES
    (17,'Circulation Library Count', 'rating.org_unit_count', TRUE);



SELECT evergreen.upgrade_deps_block_check('1054', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype ) VALUES

( 'lib.timezone', 'lib',
    oils_i18n_gettext('lib.timezone',
        'Library time zone',
        'coust', 'label'),
    oils_i18n_gettext('lib.timezone',
        'Define the time zone in which a library physically resides',
        'coust', 'description'),
    'string');

ALTER TABLE actor.org_unit_closed ADD COLUMN full_day BOOLEAN DEFAULT FALSE;
ALTER TABLE actor.org_unit_closed ADD COLUMN multi_day BOOLEAN DEFAULT FALSE;

UPDATE actor.org_unit_closed SET multi_day = TRUE
  WHERE close_start::DATE <> close_end::DATE;

UPDATE actor.org_unit_closed SET full_day = TRUE
  WHERE close_start::DATE = close_end::DATE
        AND SUBSTRING(close_start::time::text FROM 1 FOR 8) = '00:00:00'
        AND SUBSTRING(close_end::time::text FROM 1 FOR 8) = '23:59:59';

CREATE OR REPLACE FUNCTION action.push_circ_due_time () RETURNS TRIGGER AS $$
DECLARE
    proper_tz TEXT := COALESCE(
        oils_json_to_text((
            SELECT value
              FROM  actor.org_unit_ancestor_setting('lib.timezone',NEW.circ_lib)
              LIMIT 1
        )),
        CURRENT_SETTING('timezone')
    );
BEGIN

    IF (EXTRACT(EPOCH FROM NEW.duration)::INT % EXTRACT(EPOCH FROM '1 day'::INTERVAL)::INT) = 0 -- day-granular duration
        AND SUBSTRING((NEW.due_date AT TIME ZONE proper_tz)::TIME::TEXT FROM 1 FOR 8) <> '23:59:59' THEN -- has not yet been pushed
        NEW.due_date = ((NEW.due_date AT TIME ZONE proper_tz)::DATE + '1 day'::INTERVAL - '1 second'::INTERVAL) || ' ' || proper_tz;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;


\qecho The following query will adjust all historical, unaged circulations so
\qecho that if their due date field is pushed to the end of the day, it is done
\qecho in the circulating library''''s time zone, and not the server time zone.
\qecho 
\qecho It is safe to run this after any change to library time zones.
\qecho 
\qecho Running this is not required, as no code before this change has
\qecho depended on the time string of '''23:59:59'''.  It is also not necessary
\qecho if all of your libraries are in the same time zone, and that time zone
\qecho is the same as the database''''s configured time zone.
\qecho 
\qecho 'DO $$'
\qecho 'declare'
\qecho '    new_tz  text;'
\qecho '    ou_id   int;'
\qecho 'begin'
\qecho '    for ou_id in select id from actor.org_unit loop'
\qecho '        for new_tz in select oils_json_to_text(value) from actor.org_unit_ancestor_setting('''lib.timezone''',ou_id) loop'
\qecho '            if new_tz is not null then'
\qecho '                update  action.circulation'
\qecho '                  set   due_date = (due_date::timestamp || ''' ''' || new_tz)::timestamptz'
\qecho '                  where circ_lib = ou_id'
\qecho '                        and substring((due_date at time zone new_tz)::time::text from 1 for 8) <> '''23:59:59''';'
\qecho '            end if;'
\qecho '        end loop;'
\qecho '    end loop;'
\qecho 'end;'
\qecho '$$;'
\qecho 


INSERT INTO config.upgrade_log (version, applied_to) VALUES ('1056', :eg_version); -- miker/gmcharlt

INSERT INTO permission.perm_list (id,code,description) VALUES (592,'CONTAINER_BATCH_UPDATE','Allow batch update via buckets');

INSERT INTO container.user_bucket_type (code,label) SELECT code,label FROM container.copy_bucket_type where code = 'staff_client';

CREATE TABLE action.fieldset_group (
    id              SERIAL  PRIMARY KEY,
    name            TEXT        NOT NULL,
    create_time     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    complete_time   TIMESTAMPTZ,
    container       INT,        -- Points to a container of some type ...
    container_type  TEXT,       -- One of 'biblio_record_entry', 'user', 'call_number', 'copy'
    can_rollback    BOOL        DEFAULT TRUE,
    rollback_group  INT         REFERENCES action.fieldset_group (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    rollback_time   TIMESTAMPTZ,
    creator         INT         NOT NULL REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    owning_lib      INT         NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

ALTER TABLE action.fieldset ADD COLUMN fieldset_group INT REFERENCES action.fieldset_group (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE action.fieldset ADD COLUMN error_msg TEXT;
ALTER TABLE container.biblio_record_entry_bucket ADD COLUMN owning_lib INT REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE container.user_bucket ADD COLUMN owning_lib INT REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE container.call_number_bucket ADD COLUMN owning_lib INT REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE container.copy_bucket ADD COLUMN owning_lib INT REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

UPDATE query.stored_query SET id = id + 1000 WHERE id < 1000;
UPDATE query.from_relation SET id = id + 1000 WHERE id < 1000;
UPDATE query.expression SET id = id + 1000 WHERE id < 1000;

SELECT SETVAL('query.stored_query_id_seq', 1, FALSE);
SELECT SETVAL('query.from_relation_id_seq', 1, FALSE);
SELECT SETVAL('query.expression_id_seq', 1, FALSE);

INSERT INTO query.bind_variable (name,type,description,label)
    SELECT  'bucket','number','ID of the bucket to pull items from','Bucket ID'
      WHERE NOT EXISTS (SELECT 1 FROM query.bind_variable WHERE name = 'bucket');

-- Assumes completely empty 'query' schema
INSERT INTO query.stored_query (type, use_distinct) VALUES ('SELECT', TRUE); -- 1

INSERT INTO query.from_relation (type, table_name, class_name, table_alias) VALUES ('RELATION', 'container.user_bucket_item', 'cubi', 'cubi'); -- 1
UPDATE query.stored_query SET from_clause = 1;

INSERT INTO query.expr_xcol (table_alias, column_name) VALUES ('cubi', 'target_user'); -- 1
INSERT INTO query.select_item (stored_query,seq_no,expression) VALUES (1,1,1);

INSERT INTO query.expr_xcol (table_alias, column_name) VALUES ('cubi', 'bucket'); -- 2
INSERT INTO query.expr_xbind (bind_variable) VALUES ('bucket'); -- 3

INSERT INTO query.expr_xop (left_operand, operator, right_operand) VALUES (2, '=', 3); -- 4
UPDATE query.stored_query SET where_clause = 4;

SELECT SETVAL('query.stored_query_id_seq', 1000, TRUE) FROM query.stored_query;
SELECT SETVAL('query.from_relation_id_seq', 1000, TRUE) FROM query.from_relation;
SELECT SETVAL('query.expression_id_seq', 10000, TRUE) FROM query.expression;

CREATE OR REPLACE FUNCTION action.apply_fieldset(
    fieldset_id IN INT,        -- id from action.fieldset
    table_name  IN TEXT,       -- table to be updated
    pkey_name   IN TEXT,       -- name of primary key column in that table
    query       IN TEXT        -- query constructed by qstore (for query-based
                               --    fieldsets only; otherwise null
)
RETURNS TEXT AS $$
DECLARE
    statement TEXT;
    where_clause TEXT;
    fs_status TEXT;
    fs_pkey_value TEXT;
    fs_query TEXT;
    sep CHAR;
    status_code TEXT;
    msg TEXT;
    fs_id INT;
    fsg_id INT;
    update_count INT;
    cv RECORD;
    fs_obj action.fieldset%ROWTYPE;
    fs_group action.fieldset_group%ROWTYPE;
    rb_row RECORD;
BEGIN
    -- Sanity checks
    IF fieldset_id IS NULL THEN
        RETURN 'Fieldset ID parameter is NULL';
    END IF;
    IF table_name IS NULL THEN
        RETURN 'Table name parameter is NULL';
    END IF;
    IF pkey_name IS NULL THEN
        RETURN 'Primary key name parameter is NULL';
    END IF;

    SELECT
        status,
        quote_literal( pkey_value )
    INTO
        fs_status,
        fs_pkey_value
    FROM
        action.fieldset
    WHERE
        id = fieldset_id;

    --
    -- Build the WHERE clause.  This differs according to whether it's a
    -- single-row fieldset or a query-based fieldset.
    --
    IF query IS NULL        AND fs_pkey_value IS NULL THEN
        RETURN 'Incomplete fieldset: neither a primary key nor a query available';
    ELSIF query IS NOT NULL AND fs_pkey_value IS NULL THEN
        fs_query := rtrim( query, ';' );
        where_clause := 'WHERE ' || pkey_name || ' IN ( '
                     || fs_query || ' )';
    ELSIF query IS NULL     AND fs_pkey_value IS NOT NULL THEN
        where_clause := 'WHERE ' || pkey_name || ' = ';
        IF pkey_name = 'id' THEN
            where_clause := where_clause || fs_pkey_value;
        ELSIF pkey_name = 'code' THEN
            where_clause := where_clause || quote_literal(fs_pkey_value);
        ELSE
            RETURN 'Only know how to handle "id" and "code" pkeys currently, received ' || pkey_name;
        END IF;
    ELSE  -- both are not null
        RETURN 'Ambiguous fieldset: both a primary key and a query provided';
    END IF;

    IF fs_status IS NULL THEN
        RETURN 'No fieldset found for id = ' || fieldset_id;
    ELSIF fs_status = 'APPLIED' THEN
        RETURN 'Fieldset ' || fieldset_id || ' has already been applied';
    END IF;

    SELECT * INTO fs_obj FROM action.fieldset WHERE id = fieldset_id;
    SELECT * INTO fs_group FROM action.fieldset_group WHERE id = fs_obj.fieldset_group;

    IF fs_group.can_rollback THEN
        -- This is part of a non-rollback group.  We need to record the current values for future rollback.

        INSERT INTO action.fieldset_group (can_rollback, name, creator, owning_lib, container, container_type)
            VALUES (FALSE, 'ROLLBACK: '|| fs_group.name, fs_group.creator, fs_group.owning_lib, fs_group.container, fs_group.container_type);

        fsg_id := CURRVAL('action.fieldset_group_id_seq');

        FOR rb_row IN EXECUTE 'SELECT * FROM ' || table_name || ' ' || where_clause LOOP
            IF pkey_name = 'id' THEN
                fs_pkey_value := rb_row.id;
            ELSIF pkey_name = 'code' THEN
                fs_pkey_value := rb_row.code;
            ELSE
                RETURN 'Only know how to handle "id" and "code" pkeys currently, received ' || pkey_name;
            END IF;
            INSERT INTO action.fieldset (fieldset_group,owner,owning_lib,status,classname,name,pkey_value)
                VALUES (fsg_id, fs_obj.owner, fs_obj.owning_lib, 'PENDING', fs_obj.classname, fs_obj.name || ' ROLLBACK FOR ' || fs_pkey_value, fs_pkey_value);

            fs_id := CURRVAL('action.fieldset_id_seq');
            sep := '';
            FOR cv IN
                SELECT  DISTINCT col
                FROM    action.fieldset_col_val
                WHERE   fieldset = fieldset_id
            LOOP
                EXECUTE 'INSERT INTO action.fieldset_col_val (fieldset, col, val) ' || 
                    'SELECT '|| fs_id || ', '||quote_literal(cv.col)||', '||cv.col||' FROM '||table_name||' WHERE '||pkey_name||' = '||fs_pkey_value;
            END LOOP;
        END LOOP;
    END IF;

    statement := 'UPDATE ' || table_name || ' SET';

    sep := '';
    FOR cv IN
        SELECT  col,
                val
        FROM    action.fieldset_col_val
        WHERE   fieldset = fieldset_id
    LOOP
        statement := statement || sep || ' ' || cv.col
                     || ' = ' || coalesce( quote_literal( cv.val ), 'NULL' );
        sep := ',';
    END LOOP;

    IF sep = '' THEN
        RETURN 'Fieldset ' || fieldset_id || ' has no column values defined';
    END IF;
    statement := statement || ' ' || where_clause;

    --
    -- Execute the update
    --
    BEGIN
        EXECUTE statement;
        GET DIAGNOSTICS update_count = ROW_COUNT;

        IF update_count = 0 THEN
            RAISE data_exception;
        END IF;

        IF fsg_id IS NOT NULL THEN
            UPDATE action.fieldset_group SET rollback_group = fsg_id WHERE id = fs_group.id;
        END IF;

        IF fs_group.id IS NOT NULL THEN
            UPDATE action.fieldset_group SET complete_time = now() WHERE id = fs_group.id;
        END IF;

        UPDATE action.fieldset SET status = 'APPLIED', applied_time = now() WHERE id = fieldset_id;

    EXCEPTION WHEN data_exception THEN
        msg := 'No eligible rows found for fieldset ' || fieldset_id;
        UPDATE action.fieldset SET status = 'ERROR', applied_time = now() WHERE id = fieldset_id;
        RETURN msg;

    END;

    RETURN msg;

EXCEPTION WHEN OTHERS THEN
    msg := 'Unable to apply fieldset ' || fieldset_id || ': ' || sqlerrm;
    UPDATE action.fieldset SET status = 'ERROR', applied_time = now() WHERE id = fieldset_id;
    RETURN msg;

END;
$$ LANGUAGE plpgsql;



INSERT INTO config.upgrade_log (version, applied_to) VALUES ('1057', :eg_version); -- miker/gmcharlt/kmlussier

-- Thist change drops a needless join and saves 10-15% in time cost
CREATE OR REPLACE FUNCTION search.facets_for_record_set(ignore_facet_classes text[], hits bigint[]) RETURNS TABLE(id integer, value text, count bigint)
AS $f$
    SELECT id, value, count
      FROM (
        SELECT  mfae.field AS id,
                mfae.value,
                COUNT(DISTINCT mfae.source),
                row_number() OVER (
                    PARTITION BY mfae.field ORDER BY COUNT(DISTINCT mfae.source) DESC
                ) AS rownum
          FROM  metabib.facet_entry mfae
                JOIN config.metabib_field cmf ON (cmf.id = mfae.field)
          WHERE mfae.source = ANY ($2)
                AND cmf.facet_field
                AND cmf.field_class NOT IN (SELECT * FROM unnest($1))
          GROUP by 1, 2
      ) all_facets
      WHERE rownum <= (
        SELECT COALESCE(
            (SELECT value::INT FROM config.global_flag WHERE name = 'search.max_facets_per_field' AND enabled),
            1000
        )
      );
$f$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.metabib_virtual_record_feed ( id_list BIGINT[], format TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE, title TEXT DEFAULT NULL, description TEXT DEFAULT NULL, creator TEXT DEFAULT NULL, update_ts TEXT DEFAULT NULL, unapi_url TEXT DEFAULT NULL, header_xml XML DEFAULT NULL ) RETURNS XML AS $F$
DECLARE
    layout          unapi.bre_output_layout%ROWTYPE;
    transform       config.xml_transform%ROWTYPE;
    item_format     TEXT;
    tmp_xml         TEXT;
    xmlns_uri       TEXT := 'http://open-ils.org/spec/feed-xml/v1';
    ouid            INT;
    element_list    TEXT[];
BEGIN

    IF org = '-' OR org IS NULL THEN
        SELECT shortname INTO org FROM evergreen.org_top();
    END IF;

    SELECT id INTO ouid FROM actor.org_unit WHERE shortname = org;
    SELECT * INTO layout FROM unapi.bre_output_layout WHERE name = format;

    IF layout.name IS NULL THEN
        RETURN NULL::XML;
    END IF;

    SELECT * INTO transform FROM config.xml_transform WHERE name = layout.transform;
    xmlns_uri := COALESCE(transform.namespace_uri,xmlns_uri);

    -- Gather the bib xml
    SELECT XMLAGG( unapi.mmr(i, format, '', includes, org, depth, slimit, soffset, include_xmlns)) INTO tmp_xml FROM UNNEST( id_list ) i;

    IF layout.title_element IS NOT NULL THEN
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.title_element ||', XMLATTRIBUTES( $1 AS xmlns), $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, title;
    END IF;

    IF layout.description_element IS NOT NULL THEN
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.description_element ||', XMLATTRIBUTES( $1 AS xmlns), $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, description;
    END IF;

    IF layout.creator_element IS NOT NULL THEN
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.creator_element ||', XMLATTRIBUTES( $1 AS xmlns), $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, creator;
    END IF;

    IF layout.update_ts_element IS NOT NULL THEN
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.update_ts_element ||', XMLATTRIBUTES( $1 AS xmlns), $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, update_ts;
    END IF;

    IF unapi_url IS NOT NULL THEN
        EXECUTE $$SELECT XMLCONCAT( XMLELEMENT( name link, XMLATTRIBUTES( 'http://www.w3.org/1999/xhtml' AS xmlns, 'unapi-server' AS rel, $1 AS href, 'unapi' AS title)), $2)$$ INTO tmp_xml USING unapi_url, tmp_xml::XML;
    END IF;

    IF header_xml IS NOT NULL THEN tmp_xml := XMLCONCAT(header_xml,tmp_xml::XML); END IF;

    element_list := regexp_split_to_array(layout.feed_top,E'\\.');
    FOR i IN REVERSE ARRAY_UPPER(element_list, 1) .. 1 LOOP
        EXECUTE 'SELECT XMLELEMENT( name '|| quote_ident(element_list[i]) ||', XMLATTRIBUTES( $1 AS xmlns), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML;
    END LOOP;

    RETURN tmp_xml::XML;
END;
$F$ LANGUAGE PLPGSQL STABLE;

CREATE TABLE asset.copy_vis_attr_cache (
    id              BIGSERIAL   PRIMARY KEY,
    record          BIGINT      NOT NULL, -- No FKEYs, managed by user triggers.
    target_copy     BIGINT      NOT NULL,
    vis_attr_vector INT[]
);
CREATE INDEX copy_vis_attr_cache_record_idx ON asset.copy_vis_attr_cache (record);
CREATE INDEX copy_vis_attr_cache_copy_idx ON asset.copy_vis_attr_cache (target_copy);

ALTER TABLE biblio.record_entry ADD COLUMN vis_attr_vector INT[];

CREATE OR REPLACE FUNCTION search.calculate_visibility_attribute ( value INT, attr TEXT ) RETURNS INT AS $f$
SELECT  ((CASE $2

            WHEN 'luri_org'         THEN 0 -- "b" attr
            WHEN 'bib_source'       THEN 1 -- "b" attr

            WHEN 'copy_flags'       THEN 0 -- "c" attr
            WHEN 'owning_lib'       THEN 1 -- "c" attr
            WHEN 'circ_lib'         THEN 2 -- "c" attr
            WHEN 'status'           THEN 3 -- "c" attr
            WHEN 'location'         THEN 4 -- "c" attr
            WHEN 'location_group'   THEN 5 -- "c" attr

        END) << 28 ) | $1;

/* copy_flags bit positions, LSB-first:

 0: asset.copy.opac_visible


   When adding flags, you must update asset.all_visible_flags()

   Because bib and copy values are stored separately, we can reuse
   shifts, saving us some space. We could probably take back a bit
   too, but I'm not sure its worth squeezing that last one out. We'd
   be left with just 2 slots for copy attrs, rather than 10.
*/

$f$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION search.calculate_visibility_attribute_list ( attr TEXT, value INT[] ) RETURNS INT[] AS $f$
    SELECT ARRAY_AGG(search.calculate_visibility_attribute(x, $1)) FROM UNNEST($2) AS X;
$f$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION search.calculate_visibility_attribute_test ( attr TEXT, value INT[], negate BOOL DEFAULT FALSE ) RETURNS TEXT AS $f$
    SELECT  CASE WHEN $3 THEN '!' ELSE '' END || '(' || ARRAY_TO_STRING(search.calculate_visibility_attribute_list($1,$2),'|') || ')';
$f$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION asset.calculate_copy_visibility_attribute_set ( copy_id BIGINT ) RETURNS INT[] AS $f$
DECLARE
    copy_row    asset.copy%ROWTYPE;
    lgroup_map  asset.copy_location_group_map%ROWTYPE;
    attr_set    INT[];
BEGIN
    SELECT * INTO copy_row FROM asset.copy WHERE id = copy_id;

    attr_set := attr_set || search.calculate_visibility_attribute(copy_row.opac_visible::INT, 'copy_flags');
    attr_set := attr_set || search.calculate_visibility_attribute(copy_row.circ_lib, 'circ_lib');
    attr_set := attr_set || search.calculate_visibility_attribute(copy_row.status, 'status');
    attr_set := attr_set || search.calculate_visibility_attribute(copy_row.location, 'location');

    SELECT  ARRAY_APPEND(
                attr_set,
                search.calculate_visibility_attribute(owning_lib, 'owning_lib')
            ) INTO attr_set
      FROM  asset.call_number
      WHERE id = copy_row.call_number;

    FOR lgroup_map IN SELECT * FROM asset.copy_location_group_map WHERE location = copy_row.location LOOP
        attr_set := attr_set || search.calculate_visibility_attribute(lgroup_map.lgroup, 'location_group');
    END LOOP;

    RETURN attr_set;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.calculate_bib_visibility_attribute_set ( bib_id BIGINT ) RETURNS INT[] AS $f$
DECLARE
    bib_row     biblio.record_entry%ROWTYPE;
    cn_row      asset.call_number%ROWTYPE;
    attr_set    INT[];
BEGIN
    SELECT * INTO bib_row FROM biblio.record_entry WHERE id = bib_id;

    IF bib_row.source IS NOT NULL THEN
        attr_set := attr_set || search.calculate_visibility_attribute(bib_row.source, 'bib_source');
    END IF;

    FOR cn_row IN
        SELECT  cn.*
          FROM  asset.call_number cn
                JOIN asset.uri_call_number_map m ON (cn.id = m.call_number)
                JOIN asset.uri u ON (u.id = m.uri)
          WHERE cn.record = bib_id
                AND cn.label = '##URI##'
                AND u.active
    LOOP
        attr_set := attr_set || search.calculate_visibility_attribute(cn_row.owning_lib, 'luri_org');
    END LOOP;

    RETURN attr_set;
END;
$f$ LANGUAGE PLPGSQL;


SELECT evergreen.upgrade_deps_block_check('1076', :eg_version); -- miker/gmcharlt

CREATE OR REPLACE FUNCTION asset.cache_copy_visibility () RETURNS TRIGGER as $func$
DECLARE
    ocn     asset.call_number%ROWTYPE;
    ncn     asset.call_number%ROWTYPE;
    cid     BIGINT;
BEGIN

    IF TG_TABLE_NAME = 'peer_bib_copy_map' THEN -- Only needs ON INSERT OR DELETE, so handle separately
        IF TG_OP = 'INSERT' THEN
            INSERT INTO asset.copy_vis_attr_cache (record, target_copy, vis_attr_vector) VALUES (
                NEW.peer_record,
                NEW.target_copy,
                asset.calculate_copy_visibility_attribute_set(NEW.target_copy)
            );

            RETURN NEW;
        ELSIF TG_OP = 'DELETE' THEN
            DELETE FROM asset.copy_vis_attr_cache
              WHERE record = NEW.peer_record AND target_copy = NEW.target_copy;

            RETURN OLD;
        END IF;
    END IF;

    IF TG_OP = 'INSERT' THEN -- Handles ON INSERT. ON UPDATE is below.
        IF TG_TABLE_NAME IN ('copy', 'unit') THEN
            SELECT * INTO ncn FROM asset.call_number cn WHERE id = NEW.call_number;
            INSERT INTO asset.copy_vis_attr_cache (record, target_copy, vis_attr_vector) VALUES (
                ncn.record,
                NEW.id,
                asset.calculate_copy_visibility_attribute_set(NEW.id)
            );
        ELSIF TG_TABLE_NAME = 'record_entry' THEN
            NEW.vis_attr_vector := biblio.calculate_bib_visibility_attribute_set(NEW.id);
        END IF;

        RETURN NEW;
    END IF;

    -- handle items first, since with circulation activity
    -- their statuses change frequently
    IF TG_TABLE_NAME IN ('copy', 'unit') THEN -- This handles ON UPDATE OR DELETE. ON INSERT above

        IF TG_OP = 'DELETE' THEN -- Shouldn't get here, normally
            DELETE FROM asset.copy_vis_attr_cache WHERE target_copy = OLD.id;
            RETURN OLD;
        END IF;

        SELECT * INTO ncn FROM asset.call_number cn WHERE id = NEW.call_number;

        IF OLD.deleted <> NEW.deleted THEN
            IF NEW.deleted THEN
                DELETE FROM asset.copy_vis_attr_cache WHERE target_copy = OLD.id;
            ELSE
                INSERT INTO asset.copy_vis_attr_cache (record, target_copy, vis_attr_vector) VALUES (
                    ncn.record,
                    NEW.id,
                    asset.calculate_copy_visibility_attribute_set(NEW.id)
                );
            END IF;

            RETURN NEW;
        ELSIF OLD.call_number  <> NEW.call_number THEN
            SELECT * INTO ocn FROM asset.call_number cn WHERE id = OLD.call_number;

            IF ncn.record <> ocn.record THEN
                UPDATE  biblio.record_entry
                  SET   vis_attr_vector = biblio.calculate_bib_visibility_attribute_set(ncn.record)
                  WHERE id = ocn.record;

                -- We have to use a record-specific WHERE clause
                -- to avoid modifying the entries for peer-bib copies.
                UPDATE  asset.copy_vis_attr_cache
                  SET   target_copy = NEW.id,
                        record = ncn.record
                  WHERE target_copy = OLD.id
                        AND record = ocn.record;
            END IF;
        END IF;

        IF OLD.location     <> NEW.location OR
           OLD.status       <> NEW.status OR
           OLD.opac_visible <> NEW.opac_visible OR
           OLD.circ_lib     <> NEW.circ_lib
        THEN
            -- Any of these could change visibility, but
            -- we'll save some queries and not try to calculate
            -- the change directly.  We want to update peer-bib
            -- entries in this case, unlike above.
            UPDATE  asset.copy_vis_attr_cache
              SET   target_copy = NEW.id,
                    vis_attr_vector = asset.calculate_copy_visibility_attribute_set(NEW.id)
              WHERE target_copy = OLD.id;

        END IF;

    ELSIF TG_TABLE_NAME = 'call_number' THEN -- Only ON UPDATE. Copy handler will deal with ON INSERT OR DELETE.

        IF OLD.record <> NEW.record THEN
            IF NEW.label = '##URI##' THEN
                UPDATE  biblio.record_entry
                  SET   vis_attr_vector = biblio.calculate_bib_visibility_attribute_set(OLD.record)
                  WHERE id = OLD.record;

                UPDATE  biblio.record_entry
                  SET   vis_attr_vector = biblio.calculate_bib_visibility_attribute_set(NEW.record)
                  WHERE id = NEW.record;
            END IF;

            UPDATE  asset.copy_vis_attr_cache
              SET   record = NEW.record,
                    vis_attr_vector = asset.calculate_copy_visibility_attribute_set(target_copy)
              WHERE target_copy IN (SELECT id FROM asset.copy WHERE call_number = NEW.id)
                    AND record = OLD.record;

        ELSIF OLD.owning_lib <> NEW.owning_lib THEN
            UPDATE  asset.copy_vis_attr_cache
              SET   vis_attr_vector = asset.calculate_copy_visibility_attribute_set(target_copy)
              WHERE target_copy IN (SELECT id FROM asset.copy WHERE call_number = NEW.id)
                    AND record = NEW.record;

            IF NEW.label = '##URI##' THEN
                UPDATE  biblio.record_entry
                  SET   vis_attr_vector = biblio.calculate_bib_visibility_attribute_set(OLD.record)
                  WHERE id = OLD.record;
            END IF;
        END IF;

    ELSIF TG_TABLE_NAME = 'record_entry' THEN -- Only handles ON UPDATE OR DELETE

        IF TG_OP = 'DELETE' THEN -- Shouldn't get here, normally
            DELETE FROM asset.copy_vis_attr_cache WHERE record = OLD.id;
            RETURN OLD;
        ELSIF OLD.source <> NEW.source THEN
            NEW.vis_attr_vector := biblio.calculate_bib_visibility_attribute_set(NEW.id);
        END IF;

    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;


-- Helper functions for use in constructing searches --

CREATE OR REPLACE FUNCTION asset.all_visible_flags () RETURNS TEXT AS $f$
    SELECT  '(' || ARRAY_TO_STRING(ARRAY_AGG(search.calculate_visibility_attribute(1 << x, 'copy_flags')),'&') || ')'
      FROM  GENERATE_SERIES(0,0) AS x; -- increment as new flags are added.
$f$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION asset.visible_orgs (otype TEXT) RETURNS TEXT AS $f$
    SELECT  '(' || ARRAY_TO_STRING(ARRAY_AGG(search.calculate_visibility_attribute(id, $1)),'|') || ')'
      FROM  actor.org_unit
      WHERE opac_visible;
$f$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION asset.invisible_orgs (otype TEXT) RETURNS TEXT AS $f$
    SELECT  '!(' || ARRAY_TO_STRING(ARRAY_AGG(search.calculate_visibility_attribute(id, $1)),'|') || ')'
      FROM  actor.org_unit
      WHERE NOT opac_visible;
$f$ LANGUAGE SQL STABLE;

-- Bib-oriented defaults for search
CREATE OR REPLACE FUNCTION asset.bib_source_default () RETURNS TEXT AS $f$
    SELECT  '(' || ARRAY_TO_STRING(ARRAY_AGG(search.calculate_visibility_attribute(id, 'bib_source')),'|') || ')'
      FROM  config.bib_source
      WHERE transcendant;
$f$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION asset.luri_org_default () RETURNS TEXT AS $f$
    SELECT  * FROM asset.invisible_orgs('luri_org');
$f$ LANGUAGE SQL STABLE;

-- Copy-oriented defaults for search
CREATE OR REPLACE FUNCTION asset.location_group_default () RETURNS TEXT AS $f$
    SELECT  '!(' || ARRAY_TO_STRING(ARRAY_AGG(search.calculate_visibility_attribute(id, 'location_group')),'|') || ')'
      FROM  asset.copy_location_group
      WHERE NOT opac_visible;
$f$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION asset.location_default () RETURNS TEXT AS $f$
    SELECT  '!(' || ARRAY_TO_STRING(ARRAY_AGG(search.calculate_visibility_attribute(id, 'location')),'|') || ')'
      FROM  asset.copy_location
      WHERE NOT opac_visible;
$f$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION asset.status_default () RETURNS TEXT AS $f$
    SELECT  '!(' || ARRAY_TO_STRING(ARRAY_AGG(search.calculate_visibility_attribute(id, 'status')),'|') || ')'
      FROM  config.copy_status
      WHERE NOT opac_visible;
$f$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION asset.owning_lib_default () RETURNS TEXT AS $f$
    SELECT  * FROM asset.invisible_orgs('owning_lib');
$f$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION asset.circ_lib_default () RETURNS TEXT AS $f$
    SELECT  * FROM asset.invisible_orgs('circ_lib');
$f$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION asset.patron_default_visibility_mask () RETURNS TABLE (b_attrs TEXT, c_attrs TEXT)  AS $f$
DECLARE
    copy_flags      TEXT; -- "c" attr

    owning_lib      TEXT; -- "c" attr
    circ_lib        TEXT; -- "c" attr
    status          TEXT; -- "c" attr
    location        TEXT; -- "c" attr
    location_group  TEXT; -- "c" attr

    luri_org        TEXT; -- "b" attr
    bib_sources     TEXT; -- "b" attr
BEGIN
    copy_flags      := asset.all_visible_flags(); -- Will always have at least one

    owning_lib      := NULLIF(asset.owning_lib_default(),'!()');
    
    circ_lib        := NULLIF(asset.circ_lib_default(),'!()');
    status          := NULLIF(asset.status_default(),'!()');
    location        := NULLIF(asset.location_default(),'!()');
    location_group  := NULLIF(asset.location_group_default(),'!()');

    luri_org        := NULLIF(asset.luri_org_default(),'!()');
    bib_sources     := NULLIF(asset.bib_source_default(),'()');

    RETURN QUERY SELECT
        '('||ARRAY_TO_STRING(
            ARRAY[luri_org,bib_sources],
            '|'
        )||')',
        '('||ARRAY_TO_STRING(
            ARRAY[copy_flags,owning_lib,circ_lib,status,location,location_group]::TEXT[],
            '&'
        )||')';
END;
$f$ LANGUAGE PLPGSQL STABLE ROWS 1;

CREATE OR REPLACE FUNCTION metabib.suggest_browse_entries(raw_query_text text, search_class text, headline_opts text, visibility_org integer, query_limit integer, normalization integer)
 RETURNS TABLE(value text, field integer, buoyant_and_class_match boolean, field_match boolean, field_weight integer, rank real, buoyant boolean, match text)
AS $f$
DECLARE
    prepared_query_texts    TEXT[];
    query                   TSQUERY;
    plain_query             TSQUERY;
    opac_visibility_join    TEXT;
    search_class_join       TEXT;
    r_fields                RECORD;
BEGIN
    prepared_query_texts := metabib.autosuggest_prepare_tsquery(raw_query_text);

    query := TO_TSQUERY('keyword', prepared_query_texts[1]);
    plain_query := TO_TSQUERY('keyword', prepared_query_texts[2]);

    visibility_org := NULLIF(visibility_org,-1);
    IF visibility_org IS NOT NULL THEN
        PERFORM FROM actor.org_unit WHERE id = visibility_org AND parent_ou IS NULL;
        IF FOUND THEN
            opac_visibility_join := '';
        ELSE
            opac_visibility_join := '
    JOIN asset.copy_vis_attr_cache acvac ON (acvac.record = x.source)
    JOIN vm ON (acvac.vis_attr_vector @@
            (vm.c_attrs || $$&$$ ||
                search.calculate_visibility_attribute_test(
                    $$circ_lib$$,
                    (SELECT ARRAY_AGG(id) FROM actor.org_unit_descendants($4))
                )
            )::query_int
         )
';
        END IF;
    ELSE
        opac_visibility_join := '';
    END IF;

    -- The following determines whether we only provide suggestsons matching
    -- the user's selected search_class, or whether we show other suggestions
    -- too. The reason for MIN() is that for search_classes like
    -- 'title|proper|uniform' you would otherwise get multiple rows.  The
    -- implication is that if title as a class doesn't have restrict,
    -- nor does the proper field, but the uniform field does, you're going
    -- to get 'false' for your overall evaluation of 'should we restrict?'
    -- To invert that, change from MIN() to MAX().

    SELECT
        INTO r_fields
            MIN(cmc.restrict::INT) AS restrict_class,
            MIN(cmf.restrict::INT) AS restrict_field
        FROM metabib.search_class_to_registered_components(search_class)
            AS _registered (field_class TEXT, field INT)
        JOIN
            config.metabib_class cmc ON (cmc.name = _registered.field_class)
        LEFT JOIN
            config.metabib_field cmf ON (cmf.id = _registered.field);

    -- evaluate 'should we restrict?'
    IF r_fields.restrict_field::BOOL OR r_fields.restrict_class::BOOL THEN
        search_class_join := '
    JOIN
        metabib.search_class_to_registered_components($2)
        AS _registered (field_class TEXT, field INT) ON (
            (_registered.field IS NULL AND
                _registered.field_class = cmf.field_class) OR
            (_registered.field = cmf.id)
        )
    ';
    ELSE
        search_class_join := '
    LEFT JOIN
        metabib.search_class_to_registered_components($2)
        AS _registered (field_class TEXT, field INT) ON (
            _registered.field_class = cmc.name
        )
    ';
    END IF;

    RETURN QUERY EXECUTE '
WITH vm AS ( SELECT * FROM asset.patron_default_visibility_mask() ),
     mbe AS (SELECT * FROM metabib.browse_entry WHERE index_vector @@ $1 LIMIT 10000)
SELECT  DISTINCT
        x.value,
        x.id,
        x.push,
        x.restrict,
        x.weight,
        x.ts_rank_cd,
        x.buoyant,
        TS_HEADLINE(value, $7, $3)
  FROM  (SELECT DISTINCT
                mbe.value,
                cmf.id,
                cmc.buoyant AND _registered.field_class IS NOT NULL AS push,
                _registered.field = cmf.id AS restrict,
                cmf.weight,
                TS_RANK_CD(mbe.index_vector, $1, $6),
                cmc.buoyant,
                mbedm.source
          FROM  metabib.browse_entry_def_map mbedm
                JOIN mbe ON (mbe.id = mbedm.entry)
                JOIN config.metabib_field cmf ON (cmf.id = mbedm.def)
                JOIN config.metabib_class cmc ON (cmf.field_class = cmc.name)
                '  || search_class_join || '
          ORDER BY 3 DESC, 4 DESC NULLS LAST, 5 DESC, 6 DESC, 7 DESC, 1 ASC
          LIMIT 1000) AS x
        ' || opac_visibility_join || '
  ORDER BY 3 DESC, 4 DESC NULLS LAST, 5 DESC, 6 DESC, 7 DESC, 1 ASC
  LIMIT $5
'   -- sic, repeat the order by clause in the outer select too
    USING
        query, search_class, headline_opts,
        visibility_org, query_limit, normalization, plain_query
        ;

    -- sort order:
    --  buoyant AND chosen class = match class
    --  chosen field = match field
    --  field weight
    --  rank
    --  buoyancy
    --  value itself

END;
$f$ LANGUAGE plpgsql ROWS 10;

CREATE OR REPLACE FUNCTION metabib.browse(search_field integer[], browse_term text, context_org integer DEFAULT NULL::integer, context_loc_group integer DEFAULT NULL::integer, staff boolean DEFAULT false, pivot_id bigint DEFAULT NULL::bigint, result_limit integer DEFAULT 10)
 RETURNS SETOF metabib.flat_browse_entry_appearance
AS $f$
DECLARE
    core_query              TEXT;
    back_query              TEXT;
    forward_query           TEXT;
    pivot_sort_value        TEXT;
    pivot_sort_fallback     TEXT;
    context_locations       INT[];
    browse_superpage_size   INT;
    results_skipped         INT := 0;
    back_limit              INT;
    back_to_pivot           INT;
    forward_limit           INT;
    forward_to_pivot        INT;
BEGIN
    -- First, find the pivot if we were given a browse term but not a pivot.
    IF pivot_id IS NULL THEN
        pivot_id := metabib.browse_pivot(search_field, browse_term);
    END IF;

    SELECT INTO pivot_sort_value, pivot_sort_fallback
        sort_value, value FROM metabib.browse_entry WHERE id = pivot_id;

    -- Bail if we couldn't find a pivot.
    IF pivot_sort_value IS NULL THEN
        RETURN;
    END IF;

    -- Transform the context_loc_group argument (if any) (logc at the
    -- TPAC layer) into a form we'll be able to use.
    IF context_loc_group IS NOT NULL THEN
        SELECT INTO context_locations ARRAY_AGG(location)
            FROM asset.copy_location_group_map
            WHERE lgroup = context_loc_group;
    END IF;

    -- Get the configured size of browse superpages.
    SELECT INTO browse_superpage_size COALESCE(value::INT,100)     -- NULL ok
        FROM config.global_flag
        WHERE enabled AND name = 'opac.browse.holdings_visibility_test_limit';

    -- First we're going to search backward from the pivot, then we're going
    -- to search forward.  In each direction, we need two limits.  At the
    -- lesser of the two limits, we delineate the edge of the result set
    -- we're going to return.  At the greater of the two limits, we find the
    -- pivot value that would represent an offset from the current pivot
    -- at a distance of one "page" in either direction, where a "page" is a
    -- result set of the size specified in the "result_limit" argument.
    --
    -- The two limits in each direction make four derived values in total,
    -- and we calculate them now.
    back_limit := CEIL(result_limit::FLOAT / 2);
    back_to_pivot := result_limit;
    forward_limit := result_limit / 2;
    forward_to_pivot := result_limit - 1;

    -- This is the meat of the SQL query that finds browse entries.  We'll
    -- pass this to a function which uses it with a cursor, so that individual
    -- rows may be fetched in a loop until some condition is satisfied, without
    -- waiting for a result set of fixed size to be collected all at once.
    core_query := '
SELECT  mbe.id,
        mbe.value,
        mbe.sort_value
  FROM  metabib.browse_entry mbe
  WHERE (
            EXISTS ( -- are there any bibs using this mbe via the requested fields?
                SELECT  1
                  FROM  metabib.browse_entry_def_map mbedm
                  WHERE mbedm.entry = mbe.id AND mbedm.def = ANY(' || quote_literal(search_field) || ')
            ) OR EXISTS ( -- are there any authorities using this mbe via the requested fields?
                SELECT  1
                  FROM  metabib.browse_entry_simple_heading_map mbeshm
                        JOIN authority.simple_heading ash ON ( mbeshm.simple_heading = ash.id )
                        JOIN authority.control_set_auth_field_metabib_field_map_refs map ON (
                            ash.atag = map.authority_field
                            AND map.metabib_field = ANY(' || quote_literal(search_field) || ')
                        )
                  WHERE mbeshm.entry = mbe.id
            )
        ) AND ';

    -- This is the variant of the query for browsing backward.
    back_query := core_query ||
        ' mbe.sort_value <= ' || quote_literal(pivot_sort_value) ||
    ' ORDER BY mbe.sort_value DESC, mbe.value DESC LIMIT 1000';

    -- This variant browses forward.
    forward_query := core_query ||
        ' mbe.sort_value > ' || quote_literal(pivot_sort_value) ||
    ' ORDER BY mbe.sort_value, mbe.value LIMIT 1000';

    -- We now call the function which applies a cursor to the provided
    -- queries, stopping at the appropriate limits and also giving us
    -- the next page's pivot.
    RETURN QUERY
        SELECT * FROM metabib.staged_browse(
            back_query, search_field, context_org, context_locations,
            staff, browse_superpage_size, TRUE, back_limit, back_to_pivot
        ) UNION
        SELECT * FROM metabib.staged_browse(
            forward_query, search_field, context_org, context_locations,
            staff, browse_superpage_size, FALSE, forward_limit, forward_to_pivot
        ) ORDER BY row_number DESC;

END;
$f$ LANGUAGE plpgsql ROWS 10;

CREATE OR REPLACE FUNCTION metabib.staged_browse(query text, fields integer[], context_org integer, context_locations integer[], staff boolean, browse_superpage_size integer, count_up_from_zero boolean, result_limit integer, next_pivot_pos integer)
 RETURNS SETOF metabib.flat_browse_entry_appearance
AS $f$
DECLARE
    curs                    REFCURSOR;
    rec                     RECORD;
    qpfts_query             TEXT;
    aqpfts_query            TEXT;
    afields                 INT[];
    bfields                 INT[];
    result_row              metabib.flat_browse_entry_appearance%ROWTYPE;
    results_skipped         INT := 0;
    row_counter             INT := 0;
    row_number              INT;
    slice_start             INT;
    slice_end               INT;
    full_end                INT;
    all_records             BIGINT[];
    all_brecords             BIGINT[];
    all_arecords            BIGINT[];
    superpage_of_records    BIGINT[];
    superpage_size          INT;
    c_tests                 TEXT := '';
    b_tests                 TEXT := '';
    c_orgs                  INT[];
BEGIN
    IF count_up_from_zero THEN
        row_number := 0;
    ELSE
        row_number := -1;
    END IF;

    IF NOT staff THEN
        SELECT x.c_attrs, x.b_attrs INTO c_tests, b_tests FROM asset.patron_default_visibility_mask() x;
    END IF;

    IF c_tests <> '' THEN c_tests := c_tests || '&'; END IF;
    IF b_tests <> '' THEN b_tests := b_tests || '&'; END IF;

    SELECT ARRAY_AGG(id) INTO c_orgs FROM actor.org_unit_descendants(context_org);
    
    c_tests := c_tests || search.calculate_visibility_attribute_test('circ_lib',c_orgs)
               || '&' || search.calculate_visibility_attribute_test('owning_lib',c_orgs);
    
    PERFORM 1 FROM config.internal_flag WHERE enabled AND name = 'opac.located_uri.act_as_copy';
    IF FOUND THEN
        b_tests := b_tests || search.calculate_visibility_attribute_test(
            'luri_org',
            (SELECT ARRAY_AGG(id) FROM actor.org_unit_full_path(context_org) x)
        );
    ELSE
        b_tests := b_tests || search.calculate_visibility_attribute_test(
            'luri_org',
            (SELECT ARRAY_AGG(id) FROM actor.org_unit_ancestors(context_org) x)
        );
    END IF;

    IF context_locations THEN
        IF c_tests <> '' THEN c_tests := c_tests || '&'; END IF;
        c_tests := c_tests || search.calculate_visibility_attribute_test('location',context_locations);
    END IF;

    OPEN curs NO SCROLL FOR EXECUTE query;

    LOOP
        FETCH curs INTO rec;
        IF NOT FOUND THEN
            IF result_row.pivot_point IS NOT NULL THEN
                RETURN NEXT result_row;
            END IF;
            RETURN;
        END IF;

        -- Gather aggregate data based on the MBE row we're looking at now, authority axis
        SELECT INTO all_arecords, result_row.sees, afields
                ARRAY_AGG(DISTINCT abl.bib), -- bibs to check for visibility
                STRING_AGG(DISTINCT aal.source::TEXT, $$,$$), -- authority record ids
                ARRAY_AGG(DISTINCT map.metabib_field) -- authority-tag-linked CMF rows

          FROM  metabib.browse_entry_simple_heading_map mbeshm
                JOIN authority.simple_heading ash ON ( mbeshm.simple_heading = ash.id )
                JOIN authority.authority_linking aal ON ( ash.record = aal.source )
                JOIN authority.bib_linking abl ON ( aal.target = abl.authority )
                JOIN authority.control_set_auth_field_metabib_field_map_refs map ON (
                    ash.atag = map.authority_field
                    AND map.metabib_field = ANY(fields)
                )
          WHERE mbeshm.entry = rec.id;

        -- Gather aggregate data based on the MBE row we're looking at now, bib axis
        SELECT INTO all_brecords, result_row.authorities, bfields
                ARRAY_AGG(DISTINCT source),
                STRING_AGG(DISTINCT authority::TEXT, $$,$$),
                ARRAY_AGG(DISTINCT def)
          FROM  metabib.browse_entry_def_map
          WHERE entry = rec.id
                AND def = ANY(fields);

        SELECT INTO result_row.fields STRING_AGG(DISTINCT x::TEXT, $$,$$) FROM UNNEST(afields || bfields) x;

        result_row.sources := 0;
        result_row.asources := 0;

        -- Bib-linked vis checking
        IF ARRAY_UPPER(all_brecords,1) IS NOT NULL THEN

            SELECT  INTO result_row.sources COUNT(DISTINCT b.id)
              FROM  biblio.record_entry b
                    JOIN asset.copy_vis_attr_cache acvac ON (acvac.record = b.id)
              WHERE b.id = ANY(all_brecords[1:browse_superpage_size])
                    AND (
                        acvac.vis_attr_vector @@ c_tests::query_int
                        OR b.vis_attr_vector @@ b_tests::query_int
                    );

            result_row.accurate := TRUE;

        END IF;

        -- Authority-linked vis checking
        IF ARRAY_UPPER(all_arecords,1) IS NOT NULL THEN

            SELECT  INTO result_row.asources COUNT(DISTINCT b.id)
              FROM  biblio.record_entry b
                    JOIN asset.copy_vis_attr_cache acvac ON (acvac.record = b.id)
              WHERE b.id = ANY(all_arecords[1:browse_superpage_size])
                    AND (
                        acvac.vis_attr_vector @@ c_tests::query_int
                        OR b.vis_attr_vector @@ b_tests::query_int
                    );

            result_row.aaccurate := TRUE;

        END IF;

        IF result_row.sources > 0 OR result_row.asources > 0 THEN

            -- The function that calls this function needs row_number in order
            -- to correctly order results from two different runs of this
            -- functions.
            result_row.row_number := row_number;

            -- Now, if row_counter is still less than limit, return a row.  If
            -- not, but it is less than next_pivot_pos, continue on without
            -- returning actual result rows until we find
            -- that next pivot, and return it.

            IF row_counter < result_limit THEN
                result_row.browse_entry := rec.id;
                result_row.value := rec.value;

                RETURN NEXT result_row;
            ELSE
                result_row.browse_entry := NULL;
                result_row.authorities := NULL;
                result_row.fields := NULL;
                result_row.value := NULL;
                result_row.sources := NULL;
                result_row.sees := NULL;
                result_row.accurate := NULL;
                result_row.aaccurate := NULL;
                result_row.pivot_point := rec.id;

                IF row_counter >= next_pivot_pos THEN
                    RETURN NEXT result_row;
                    RETURN;
                END IF;
            END IF;

            IF count_up_from_zero THEN
                row_number := row_number + 1;
            ELSE
                row_number := row_number - 1;
            END IF;

            -- row_counter is different from row_number.
            -- It simply counts up from zero so that we know when
            -- we've reached our limit.
            row_counter := row_counter + 1;
        END IF;
    END LOOP;
END;
$f$ LANGUAGE plpgsql ROWS 10;

DROP TRIGGER IF EXISTS a_opac_vis_mat_view_tgr ON biblio.peer_bib_copy_map;
DROP TRIGGER IF EXISTS a_opac_vis_mat_view_tgr ON biblio.record_entry;
DROP TRIGGER IF EXISTS a_opac_vis_mat_view_tgr ON asset.copy;
DROP TRIGGER IF EXISTS a_opac_vis_mat_view_tgr ON asset.call_number;
DROP TRIGGER IF EXISTS a_opac_vis_mat_view_tgr ON asset.copy_location;
DROP TRIGGER IF EXISTS a_opac_vis_mat_view_tgr ON serial.unit;
DROP TRIGGER IF EXISTS a_opac_vis_mat_view_tgr ON config.copy_status;
DROP TRIGGER IF EXISTS a_opac_vis_mat_view_tgr ON actor.org_unit;

-- Upgrade the data!
INSERT INTO asset.copy_vis_attr_cache (target_copy, record, vis_attr_vector)
    SELECT  cp.id,
            cn.record,
            asset.calculate_copy_visibility_attribute_set(cp.id)
      FROM  asset.copy cp
            JOIN asset.call_number cn ON (cp.call_number = cn.id);

-- updating vis cache for biblio.record_entry deferred to end

CREATE TRIGGER z_opac_vis_mat_view_tgr BEFORE INSERT OR UPDATE ON biblio.record_entry FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER z_opac_vis_mat_view_tgr AFTER INSERT OR DELETE ON biblio.peer_bib_copy_map FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER z_opac_vis_mat_view_tgr AFTER UPDATE ON asset.call_number FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER z_opac_vis_mat_view_del_tgr BEFORE DELETE ON asset.copy FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER z_opac_vis_mat_view_del_tgr BEFORE DELETE ON serial.unit FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER z_opac_vis_mat_view_tgr AFTER INSERT OR UPDATE ON asset.copy FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER z_opac_vis_mat_view_tgr AFTER INSERT OR UPDATE ON serial.unit FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();

CREATE OR REPLACE FUNCTION asset.opac_ou_record_copy_count (org INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = rid;

    FOR ans IN SELECT u.id, t.depth FROM actor.org_unit_ancestors(org) AS u JOIN actor.org_unit_type t ON (u.ou_type = t.id) LOOP
        RETURN QUERY
        WITH org_list AS (SELECT ARRAY_AGG(id)::BIGINT[] AS orgs FROM actor.org_unit_descendants(ans.id) x),
             available_statuses AS (SELECT ARRAY_AGG(id) AS ids FROM config.copy_status WHERE is_available),
             mask AS (SELECT c_attrs FROM asset.patron_default_visibility_mask() x)
        SELECT  ans.depth,
                ans.id,
                COUNT( av.id ),
                SUM( (cp.status = ANY (available_statuses.ids))::INT ),
                COUNT( av.id ),
                trans
          FROM  mask,
                available_statuses,
                org_list,
                asset.copy_vis_attr_cache av
                JOIN asset.copy cp ON (cp.id = av.target_copy AND av.record = rid)
          WHERE cp.circ_lib = ANY (org_list.orgs) AND av.vis_attr_vector @@ mask.c_attrs::query_int
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.opac_lasso_record_copy_count (i_lasso INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = rid;

    FOR ans IN SELECT u.org_unit AS id FROM actor.org_lasso_map AS u WHERE lasso = i_lasso LOOP
        RETURN QUERY
        WITH org_list AS (SELECT ARRAY_AGG(id)::BIGINT[] AS orgs FROM actor.org_unit_descendants(ans.id) x),
             available_statuses AS (SELECT ARRAY_AGG(id) AS ids FROM config.copy_status WHERE is_available),
             mask AS (SELECT c_attrs FROM asset.patron_default_visibility_mask() x)
        SELECT  -1,
                ans.id,
                COUNT( av.id ),
                SUM( (cp.status = ANY (available_statuses.ids))::INT ),
                COUNT( av.id ),
                trans
          FROM  mask,
                org_list,
                asset.copy_vis_attr_cache av
                JOIN asset.copy cp ON (cp.id = av.target_copy AND av.record = rid)
          WHERE cp.circ_lib = ANY (org_list.orgs) AND av.vis_attr_vector @@ mask.c_attrs::query_int
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT -1, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.opac_ou_metarecord_copy_count (org INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) JOIN metabib.metarecord_source_map m ON (m.source = b.id) WHERE src.transcendant AND m.metarecord = rid;

    FOR ans IN SELECT u.id, t.depth FROM actor.org_unit_ancestors(org) AS u JOIN actor.org_unit_type t ON (u.ou_type = t.id) LOOP
        RETURN QUERY
        WITH org_list AS (SELECT ARRAY_AGG(id)::BIGINT[] AS orgs FROM actor.org_unit_descendants(ans.id) x),
             available_statuses AS (SELECT ARRAY_AGG(id) AS ids FROM config.copy_status WHERE is_available),
             mask AS (SELECT c_attrs FROM asset.patron_default_visibility_mask() x)
        SELECT  ans.depth,
                ans.id,
                COUNT( av.id ),
                SUM( (cp.status = ANY (available_statuses.ids))::INT ),
                COUNT( av.id ),
                trans
          FROM  mask,
                org_list,
                available_statuses,
                asset.copy_vis_attr_cache av
                JOIN asset.copy cp ON (cp.id = av.target_copy)
                JOIN metabib.metarecord_source_map m ON (m.metarecord = rid AND m.source = av.record)
          WHERE cp.circ_lib = ANY (org_list.orgs) AND av.vis_attr_vector @@ mask.c_attrs::query_int
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.opac_lasso_metarecord_copy_count (i_lasso INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) JOIN metabib.metarecord_source_map m ON (m.source = b.id) WHERE src.transcendant AND m.metarecord = rid;

    FOR ans IN SELECT u.org_unit AS id FROM actor.org_lasso_map AS u WHERE lasso = i_lasso LOOP
        RETURN QUERY
        WITH org_list AS (SELECT ARRAY_AGG(id)::BIGINT[] AS orgs FROM actor.org_unit_descendants(ans.id) x),
             available_statuses AS (SELECT ARRAY_AGG(id) AS ids FROM config.copy_status WHERE is_available),
             mask AS (SELECT c_attrs FROM asset.patron_default_visibility_mask() x)
        SELECT  -1,
                ans.id,
                COUNT( av.id ),
                SUM( (cp.status = ANY (available_statuses.ids))::INT ),
                COUNT( av.id ),
                trans
          FROM  mask,
                org_list,
                available_statuses,
                asset.copy_vis_attr_cache av
                JOIN asset.copy cp ON (cp.id = av.target_copy)
                JOIN metabib.metarecord_source_map m ON (m.metarecord = rid AND m.source = av.record)
          WHERE cp.circ_lib = ANY (org_list.orgs) AND av.vis_attr_vector @@ mask.c_attrs::query_int
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION unapi.mmr_mra (
    obj_id BIGINT,
    format TEXT,
    ename TEXT,
    includes TEXT[],
    org TEXT,
    depth INT DEFAULT NULL,
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE,
    pref_lib INT DEFAULT NULL
) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
        name attributes,
        XMLATTRIBUTES(
            CASE WHEN $9 THEN 'http://open-ils.org/spec/indexing/v1' ELSE NULL END AS xmlns,
            'tag:open-ils.org:U2@mmr/' || $1 AS metarecord
        ),
        (SELECT XMLAGG(foo.y)
          FROM (
            WITH sourcelist AS (
                WITH aou AS (SELECT COALESCE(id, (evergreen.org_top()).id) AS id FROM actor.org_unit WHERE shortname = $5 LIMIT 1),
                     basevm AS (SELECT c_attrs FROM  asset.patron_default_visibility_mask()),
                     circvm AS (SELECT search.calculate_visibility_attribute_test('circ_lib', ARRAY_AGG(aoud.id)) AS mask
                                  FROM aou, LATERAL actor.org_unit_descendants(aou.id, $6) aoud)
                SELECT  source
                  FROM  aou, circvm, basevm, metabib.metarecord_source_map mmsm
                  WHERE mmsm.metarecord = $1 AND (
                    EXISTS (
                        SELECT  1
                          FROM  circvm, basevm, asset.copy_vis_attr_cache acvac
                          WHERE acvac.vis_attr_vector @@ (basevm.c_attrs || '&' || circvm.mask)::query_int
                                AND acvac.record = mmsm.source
                    )
                    OR EXISTS (SELECT 1 FROM evergreen.located_uris(source, aou.id, $10) LIMIT 1)
                    OR EXISTS (SELECT 1 FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = mmsm.source)
                )
            )
            SELECT  cmra.aid,
                    XMLELEMENT(
                        name field,
                        XMLATTRIBUTES(
                            cmra.attr AS name,
                            cmra.value AS "coded-value",
                            cmra.aid AS "cvmid",
                            rad.composite,
                            rad.multi,
                            rad.filter,
                            rad.sorter,
                            cmra.source_list
                        ),
                        cmra.value
                    )
              FROM  (
                SELECT DISTINCT aid, attr, value, STRING_AGG(x.id::TEXT, ',') AS source_list
                  FROM (
                    SELECT  v.source AS id,
                            c.id AS aid,
                            c.ctype AS attr,
                            c.code AS value
                      FROM  metabib.record_attr_vector_list v
                            JOIN config.coded_value_map c ON ( c.id = ANY( v.vlist ) )
                    ) AS x
                    JOIN sourcelist ON (x.id = sourcelist.source)
                    GROUP BY 1, 2, 3
                ) AS cmra
                JOIN config.record_attr_definition rad ON (cmra.attr = rad.name)
                UNION ALL
            SELECT  umra.aid,
                    XMLELEMENT(
                        name field,
                        XMLATTRIBUTES(
                            umra.attr AS name,
                            rad.composite,
                            rad.multi,
                            rad.filter,
                            rad.sorter
                        ),
                        umra.value
                    )
              FROM  (
                SELECT DISTINCT aid, attr, value
                  FROM (
                    SELECT  v.source AS id,
                            m.id AS aid,
                            m.attr AS attr,
                            m.value AS value
                      FROM  metabib.record_attr_vector_list v
                            JOIN metabib.uncontrolled_record_attr_value m ON ( m.id = ANY( v.vlist ) )
                    ) AS x
                    JOIN sourcelist ON (x.id = sourcelist.source)
                ) AS umra
                JOIN config.record_attr_definition rad ON (umra.attr = rad.name)
                ORDER BY 1

            )foo(id,y)
        )
    )
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION evergreen.ranked_volumes(
    bibid BIGINT[],
    ouid INT,
    depth INT DEFAULT NULL,
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    pref_lib INT DEFAULT NULL,
    includes TEXT[] DEFAULT NULL::TEXT[]
) RETURNS TABLE(id BIGINT, name TEXT, label_sortkey TEXT, rank BIGINT) AS $$
    WITH RECURSIVE ou_depth AS (
        SELECT COALESCE(
            $3,
            (
                SELECT depth
                FROM actor.org_unit_type aout
                    INNER JOIN actor.org_unit ou ON ou_type = aout.id
                WHERE ou.id = $2
            )
        ) AS depth
    ), descendant_depth AS (
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
        FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN anscestor_depth ad ON (ad.id = ou.id),
                ou_depth
        WHERE ad.depth = ou_depth.depth
            UNION ALL
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
        FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN descendant_depth ot ON (ot.id = ou.parent_ou)
    ), anscestor_depth AS (
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
        FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
        WHERE ou.id = $2
            UNION ALL
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
        FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN anscestor_depth ot ON (ot.parent_ou = ou.id)
    ), descendants as (
        SELECT ou.* FROM actor.org_unit ou JOIN descendant_depth USING (id)
    )

    SELECT ua.id, ua.name, ua.label_sortkey, MIN(ua.rank) AS rank FROM (
        SELECT acn.id, owning_lib.name, acn.label_sortkey,
            evergreen.rank_cp(acp),
            RANK() OVER w
        FROM asset.call_number acn
            JOIN asset.copy acp ON (acn.id = acp.call_number)
            JOIN descendants AS aou ON (acp.circ_lib = aou.id)
            JOIN actor.org_unit AS owning_lib ON (acn.owning_lib = owning_lib.id)
        WHERE acn.record = ANY ($1)
            AND acn.deleted IS FALSE
            AND acp.deleted IS FALSE
            AND CASE WHEN ('exclude_invisible_acn' = ANY($7)) THEN
                EXISTS (
                    WITH basevm AS (SELECT c_attrs FROM  asset.patron_default_visibility_mask()),
                         circvm AS (SELECT search.calculate_visibility_attribute_test('circ_lib', ARRAY[acp.circ_lib]) AS mask)
                    SELECT  1
                      FROM  basevm, circvm, asset.copy_vis_attr_cache acvac
                      WHERE acvac.vis_attr_vector @@ (basevm.c_attrs || '&' || circvm.mask)::query_int
                            AND acvac.target_copy = acp.id
                            AND acvac.record = acn.record
                ) ELSE TRUE END
        GROUP BY acn.id, evergreen.rank_cp(acp), owning_lib.name, acn.label_sortkey, aou.id
        WINDOW w AS (
            ORDER BY
                COALESCE(
                    CASE WHEN aou.id = $2 THEN -20000 END,
                    CASE WHEN aou.id = $6 THEN -10000 END,
                    (SELECT distance - 5000
                        FROM actor.org_unit_descendants_distance($6) as x
                        WHERE x.id = aou.id AND $6 IN (
                            SELECT q.id FROM actor.org_unit_descendants($2) as q)),
                    (SELECT e.distance FROM actor.org_unit_descendants_distance($2) as e WHERE e.id = aou.id),
                    1000
                ),
                evergreen.rank_cp(acp)
        )
    ) AS ua
    GROUP BY ua.id, ua.name, ua.label_sortkey
    ORDER BY rank, ua.name, ua.label_sortkey
    LIMIT ($4 -> 'acn')::INT
    OFFSET ($5 -> 'acn')::INT;
$$ LANGUAGE SQL STABLE ROWS 10;


-- Evergreen DB patch XXXX.schema.action-trigger.event_definition.sms_preminder.sql
--
-- New action trigger event definition: 3 Day Courtesy Notice by SMS
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('1058', :eg_version); -- mccanna/csharp/gmcharlt

INSERT INTO action_trigger.event_definition (id, active, owner, name, hook,
        validator, reactor, delay, max_delay, delay_field, group_field, template)
    VALUES (54, FALSE, 1,
        '3 Day Courtesy Notice by SMS',
        'checkout.due',
        'CircIsOpen', 'SendSMS', '-3 days', '-2 days', 'due_date', 'usr',
$$
[%- USE date -%]
[%- user = target.0.usr -%]
[%- homelib = user.home_ou -%]
[%- sms_number = helpers.get_user_setting(user.id, 'opac.default_sms_notify') -%]
[%- sms_carrier = helpers.get_user_setting(user.id, 'opac.default_sms_carrier') -%]
From: [%- helpers.get_org_setting(homelib.id, 'org.bounced_emails') || homelib.email || params.sender_email || default_sender %]
To: [%- helpers.get_sms_gateway_email(sms_carrier,sms_number) %]
Subject: Library Materials Due Soon

You have items due soon:

[% FOR circ IN target %]
[%- copy_details = helpers.get_copy_bib_basics(circ.target_copy.id) -%]
[% copy_details.title FILTER ucfirst %] by [% copy_details.author FILTER ucfirst %] due on [% date.format(helpers.format_date(circ.due_date), '%m-%d-%Y') %]

[% END %]

$$);

INSERT INTO action_trigger.environment (event_def, path) VALUES
    (54, 'circ_lib.billing_address'),
    (54, 'target_copy.call_number'),
    (54, 'usr'),
    (54, 'usr.home_ou');


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('1059', :eg_version); --Stompro/DPearl/kmlussier

CREATE OR REPLACE VIEW reporter.old_super_simple_record AS
SELECT  r.id,
    r.fingerprint,
    r.quality,
    r.tcn_source,
    r.tcn_value,
    CONCAT_WS(' ', FIRST(title.value),FIRST(title_np.val)) AS title,
    FIRST(author.value) AS author,
    STRING_AGG(DISTINCT publisher.value, ', ') AS publisher,
    STRING_AGG(DISTINCT SUBSTRING(pubdate.value FROM $$\d+$$), ', ') AS pubdate,
    CASE WHEN ARRAY_AGG( DISTINCT REPLACE(SUBSTRING(isbn.value FROM $$^\S+$$), '-', '') ) = '{NULL}'
        THEN NULL
        ELSE ARRAY_AGG( DISTINCT REPLACE(SUBSTRING(isbn.value FROM $$^\S+$$), '-', '') )
    END AS isbn,
    CASE WHEN ARRAY_AGG( DISTINCT REGEXP_REPLACE(issn.value, E'^\\S*(\\d{4})[-\\s](\\d{3,4}x?)', E'\\1 \\2') ) = '{NULL}'
        THEN NULL
        ELSE ARRAY_AGG( DISTINCT REGEXP_REPLACE(issn.value, E'^\\S*(\\d{4})[-\\s](\\d{3,4}x?)', E'\\1 \\2') )
    END AS issn
  FROM  biblio.record_entry r
    LEFT JOIN metabib.full_rec title ON (r.id = title.record AND title.tag = '245' AND title.subfield = 'a')
    LEFT JOIN ( -- Grab 245 N and P subfields in the order that they appear.
      SELECT b.record, string_agg(val, ' ') AS val FROM (
	     SELECT title_np.record, title_np.value AS val
	      FROM metabib.full_rec title_np
	      WHERE
	      title_np.tag = '245'
			AND title_np.subfield IN ('p','n')			
			ORDER BY title_np.id
		) b
		GROUP BY 1
	 ) title_np ON (title_np.record=r.id) 
    LEFT JOIN metabib.full_rec author ON (r.id = author.record AND author.tag IN ('100','110','111') AND author.subfield = 'a')
    LEFT JOIN metabib.full_rec publisher ON (r.id = publisher.record AND (publisher.tag = '260' OR (publisher.tag = '264' AND publisher.ind2 = '1')) AND publisher.subfield = 'b')
    LEFT JOIN metabib.full_rec pubdate ON (r.id = pubdate.record AND (pubdate.tag = '260' OR (pubdate.tag = '264' AND pubdate.ind2 = '1')) AND pubdate.subfield = 'c')
    LEFT JOIN metabib.full_rec isbn ON (r.id = isbn.record AND isbn.tag IN ('024', '020') AND isbn.subfield IN ('a','z'))
    LEFT JOIN metabib.full_rec issn ON (r.id = issn.record AND issn.tag = '022' AND issn.subfield = 'a')
  GROUP BY 1,2,3,4,5;

  
  -- Remove trigger on biblio.record_entry
  SELECT reporter.disable_materialized_simple_record_trigger();
  
  -- Rebuild reporter.materialized_simple_record
  SELECT reporter.enable_materialized_simple_record_trigger();
  

SELECT evergreen.upgrade_deps_block_check('1060', :eg_version);

DROP VIEW IF EXISTS extend_reporter.copy_count_per_org;


CREATE OR REPLACE VIEW extend_reporter.copy_count_per_org AS
 SELECT acn.record AS bibid,
    ac.circ_lib,
    acn.owning_lib,
    max(ac.edit_date) AS last_edit_time,
    min(ac.deleted::integer) AS has_only_deleted_copies,
    count(
        CASE
            WHEN ac.deleted THEN ac.id
            ELSE NULL::bigint
        END) AS deleted_count,
    count(
        CASE
            WHEN NOT ac.deleted THEN ac.id
            ELSE NULL::bigint
        END) AS visible_count,
    count(*) AS total_count
   FROM asset.call_number acn,
    asset.copy ac
  WHERE ac.call_number = acn.id
  GROUP BY acn.record, acn.owning_lib, ac.circ_lib;



SELECT evergreen.upgrade_deps_block_check('1061', :eg_version);

INSERT INTO config.org_unit_setting_type
    (name, label, description, grp, datatype)
VALUES (
    'ui.staff.max_recent_patrons',
    oils_i18n_gettext(
        'ui.staff.max_recent_patrons',
        'Number of Retrievable Recent Patrons',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ui.staff.max_recent_patrons',
        'Number of most recently accessed patrons that can be re-retrieved ' ||
        'in the staff client.  A value of 0 or less disables the feature. Defaults to 1.',
        'coust',
        'description'
    ),
    'circ',
    'integer'
);


SELECT evergreen.upgrade_deps_block_check('1062', :eg_version);

CREATE TABLE acq.edi_attr (
    key     TEXT PRIMARY KEY,
    label   TEXT NOT NULL UNIQUE
);

CREATE TABLE acq.edi_attr_set (
    id      SERIAL  PRIMARY KEY,
    label   TEXT NOT NULL UNIQUE
);

CREATE TABLE acq.edi_attr_set_map (
    id          SERIAL  PRIMARY KEY,
    attr_set    INTEGER NOT NULL REFERENCES acq.edi_attr_set(id) 
                ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    attr        TEXT NOT NULL REFERENCES acq.edi_attr(key) 
                ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT edi_attr_set_map_attr_once UNIQUE (attr_set, attr)
);

-- An attr_set is not strictly required, since some edi_accounts/vendors 
-- may not need to apply any attributes.
ALTER TABLE acq.edi_account 
    ADD COLUMN attr_set INTEGER REFERENCES acq.edi_attr_set(id),
    ADD COLUMN use_attrs BOOLEAN NOT NULL DEFAULT FALSE;




SELECT evergreen.upgrade_deps_block_check('1063', :eg_version);

DO $temp$
DECLARE
	r RECORD;
BEGIN

	FOR r IN SELECT	t.table_schema AS sname,
			t.table_name AS tname,
			t.column_name AS colname,
			t.constraint_name
		  FROM	information_schema.referential_constraints ref
			JOIN information_schema.key_column_usage t USING (constraint_schema,constraint_name)
		  WHERE	ref.unique_constraint_schema = 'asset'
			AND ref.unique_constraint_name = 'copy_pkey'
	LOOP

		EXECUTE 'ALTER TABLE '||r.sname||'.'||r.tname||' DROP CONSTRAINT '||r.constraint_name||';';

		EXECUTE '
			CREATE OR REPLACE FUNCTION evergreen.'||r.sname||'_'||r.tname||'_'||r.colname||'_inh_fkey() RETURNS TRIGGER AS $f$
			BEGIN
				PERFORM 1 FROM asset.copy WHERE id = NEW.'||r.colname||';
				IF NOT FOUND THEN
					RAISE foreign_key_violation USING MESSAGE = FORMAT(
						$$Referenced asset.copy id not found, '||r.colname||':%s$$, NEW.'||r.colname||'
					);
				END IF;
				RETURN NEW;
			END;
			$f$ LANGUAGE PLPGSQL VOLATILE COST 50;
		';

		EXECUTE '
			CREATE CONSTRAINT TRIGGER inherit_'||r.constraint_name||'
				AFTER UPDATE OR INSERT OR DELETE ON '||r.sname||'.'||r.tname||'
				DEFERRABLE FOR EACH ROW EXECUTE PROCEDURE evergreen.'||r.sname||'_'||r.tname||'_'||r.colname||'_inh_fkey();
		';
	END LOOP;
END
$temp$;



SELECT evergreen.upgrade_deps_block_check('1064', :eg_version);

ALTER TABLE serial.issuance DROP CONSTRAINT IF EXISTS issuance_caption_and_pattern_fkey;

-- Using NOT VALID and VALIDATE CONSTRAINT limits the impact to concurrent work.
-- For details, see: https://www.postgresql.org/docs/current/static/sql-altertable.html

ALTER TABLE serial.issuance ADD CONSTRAINT issuance_caption_and_pattern_fkey
    FOREIGN KEY (caption_and_pattern)
    REFERENCES serial.caption_and_pattern (id)
    ON DELETE CASCADE
    DEFERRABLE INITIALLY DEFERRED
    NOT VALID;

ALTER TABLE serial.issuance VALIDATE CONSTRAINT issuance_caption_and_pattern_fkey;



SELECT evergreen.upgrade_deps_block_check('1065', :eg_version);

CREATE TABLE serial.pattern_template (
    id            SERIAL PRIMARY KEY,
    name          TEXT NOT NULL,
    pattern_code  TEXT NOT NULL,
    owning_lib    INTEGER REFERENCES actor.org_unit(id) DEFERRABLE INITIALLY DEFERRED,
    share_depth   INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX serial_pattern_template_name_idx ON serial.pattern_template (evergreen.lowercase(name));

CREATE OR REPLACE FUNCTION serial.pattern_templates_visible_to(org_unit INT) RETURNS SETOF serial.pattern_template AS $func$
BEGIN
    RETURN QUERY SELECT *
           FROM serial.pattern_template spt
           WHERE (
             SELECT ARRAY_AGG(id)
             FROM actor.org_unit_descendants(spt.owning_lib, spt.share_depth)
           ) @@ org_unit::TEXT::QUERY_INT;
END;
$func$ LANGUAGE PLPGSQL;


SELECT evergreen.upgrade_deps_block_check('1066', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 593, 'ADMIN_SERIAL_PATTERN_TEMPLATE', oils_i18n_gettext( 593,
    'Administer serial prediction pattern templates', 'ppl', 'description' ))
;

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT
        pgt.id, perm.id, aout.depth, FALSE
    FROM
        permission.grp_tree pgt,
        permission.perm_list perm,
        actor.org_unit_type aout
    WHERE
        pgt.name = 'Serials' AND
        aout.name = 'System' AND
        perm.code IN (
            'ADMIN_SERIAL_PATTERN_TEMPLATE'
        );


SELECT evergreen.upgrade_deps_block_check('1067', :eg_version);

INSERT INTO acq.edi_attr (key, label) VALUES
    ('INCLUDE_PO_NAME', 
        oils_i18n_gettext('INCLUDE_PO_NAME', 
        'Orders Include PO Name', 'aea', 'label')),
    ('INCLUDE_COPIES', 
        oils_i18n_gettext('INCLUDE_COPIES', 
        'Orders Include Copy Data', 'aea', 'label')),
    ('INCLUDE_FUND', 
        oils_i18n_gettext('INCLUDE_FUND', 
        'Orders Include Copy Funds', 'aea', 'label')),
    ('INCLUDE_CALL_NUMBER', 
        oils_i18n_gettext('INCLUDE_CALL_NUMBER', 
        'Orders Include Copy Call Numbers', 'aea', 'label')),
    ('INCLUDE_ITEM_TYPE', 
        oils_i18n_gettext('INCLUDE_ITEM_TYPE', 
        'Orders Include Copy Item Types', 'aea', 'label')),
    ('INCLUDE_ITEM_BARCODE',
        oils_i18n_gettext('INCLUDE_ITEM_BARCODE',
        'Orders Include Copy Barcodes', 'aea', 'label')),
    ('INCLUDE_LOCATION', 
        oils_i18n_gettext('INCLUDE_LOCATION', 
        'Orders Include Copy Locations', 'aea', 'label')),
    ('INCLUDE_COLLECTION_CODE', 
        oils_i18n_gettext('INCLUDE_COLLECTION_CODE', 
        'Orders Include Copy Collection Codes', 'aea', 'label')),
    ('INCLUDE_OWNING_LIB', 
        oils_i18n_gettext('INCLUDE_OWNING_LIB', 
        'Orders Include Copy Owning Library', 'aea', 'label')),
    ('USE_ID_FOR_OWNING_LIB',
        oils_i18n_gettext('USE_ID_FOR_OWNING_LIB',
        'Emit Owning Library ID Rather Than Short Name. Takes effect only if INCLUDE_OWNING_LIB is in use', 'aea', 'label')),
    ('INCLUDE_QUANTITY', 
        oils_i18n_gettext('INCLUDE_QUANTITY', 
        'Orders Include Copy Quantities', 'aea', 'label')),
    ('INCLUDE_COPY_ID', 
        oils_i18n_gettext('INCLUDE_COPY_ID', 
        'Orders Include Copy IDs', 'aea', 'label')),
    ('BUYER_ID_INCLUDE_VENDCODE', 
        oils_i18n_gettext('BUYER_ID_INCLUDE_VENDCODE', 
        'Buyer ID Qualifier Includes Vendcode', 'aea', 'label')),
    ('BUYER_ID_ONLY_VENDCODE', 
        oils_i18n_gettext('BUYER_ID_ONLY_VENDCODE', 
        'Buyer ID Qualifier Only Contains Vendcode', 'aea', 'label')),
    ('INCLUDE_BIB_EDITION', 
        oils_i18n_gettext('INCLUDE_BIB_EDITION', 
        'Order Lineitems Include Edition Info', 'aea', 'label')),
    ('INCLUDE_BIB_AUTHOR', 
        oils_i18n_gettext('INCLUDE_BIB_AUTHOR', 
        'Order Lineitems Include Author Info', 'aea', 'label')),
    ('INCLUDE_BIB_PAGINATION', 
        oils_i18n_gettext('INCLUDE_BIB_PAGINATION', 
        'Order Lineitems Include Pagination Info', 'aea', 'label')),
    ('COPY_SPEC_CODES', 
        oils_i18n_gettext('COPY_SPEC_CODES', 
        'Order Lineitem Notes Include Copy Spec Codes', 'aea', 'label')),
    ('INCLUDE_EMPTY_IMD_VALUES', 
        oils_i18n_gettext('INCLUDE_EMPTY_IMD_VALUES',
        'Lineitem Title, Author, etc. Fields Are Present Even if Empty', 'aea', 'label')),
    ('INCLUDE_EMPTY_LI_NOTE', 
        oils_i18n_gettext('INCLUDE_EMPTY_LI_NOTE', 
        'Order Lineitem Notes Always Present (Even if Empty)', 'aea', 'label')),
    ('INCLUDE_EMPTY_CALL_NUMBER', 
        oils_i18n_gettext('INCLUDE_EMPTY_CALL_NUMBER', 
        'Order Copies Always Include Call Number (Even if Empty)', 'aea', 'label')),
    ('INCLUDE_EMPTY_ITEM_TYPE', 
        oils_i18n_gettext('INCLUDE_EMPTY_ITEM_TYPE', 
        'Order Copies Always Include Item Type (Even if Empty)', 'aea', 'label')),
    ('INCLUDE_EMPTY_LOCATION', 
        oils_i18n_gettext('INCLUDE_EMPTY_LOCATION', 
        'Order Copies Always Include Location (Even if Empty)', 'aea', 'label')),
    ('INCLUDE_EMPTY_COLLECTION_CODE', 
        oils_i18n_gettext('INCLUDE_EMPTY_COLLECTION_CODE', 
        'Order Copies Always Include Collection Code (Even if Empty)', 'aea', 'label')),
    ('LINEITEM_IDENT_VENDOR_NUMBER',
        oils_i18n_gettext('LINEITEM_IDENT_VENDOR_NUMBER',
        'Lineitem Identifier Fields (LIN/PIA) Use Vendor-Encoded ID Value When Available', 'aea', 'label')),
    ('LINEITEM_REF_ID_ONLY',
        oils_i18n_gettext('LINEITEM_REF_ID_ONLY',
        'Lineitem Reference Field (RFF) Uses Lineitem ID Only', 'aea', 'label'))

;

INSERT INTO acq.edi_attr_set (id, label) VALUES (1, 'Ingram Default');
INSERT INTO acq.edi_attr_set (id, label) VALUES (2, 'Baker & Taylor Default');
INSERT INTO acq.edi_attr_set (id, label) VALUES (3, 'Brodart Default');
INSERT INTO acq.edi_attr_set (id, label) VALUES (4, 'Midwest Tape Default');
INSERT INTO acq.edi_attr_set (id, label) VALUES (5, 'ULS Default');
INSERT INTO acq.edi_attr_set (id, label) VALUES (6, 'Recorded Books Default');
INSERT INTO acq.edi_attr_set (id, label) VALUES (7, 'Midwest Library Service');

-- carve out space for mucho defaults
SELECT SETVAL('acq.edi_attr_set_id_seq'::TEXT, 1000);

INSERT INTO acq.edi_attr_set_map (attr_set, attr) VALUES

    -- Ingram
    (1, 'INCLUDE_PO_NAME'),
    (1, 'INCLUDE_COPIES'),
    (1, 'INCLUDE_ITEM_TYPE'),
    (1, 'INCLUDE_COLLECTION_CODE'),
    (1, 'INCLUDE_OWNING_LIB'),
    (1, 'INCLUDE_QUANTITY'),
    (1, 'INCLUDE_BIB_PAGINATION'),

    -- B&T
    (2, 'INCLUDE_COPIES'),
    (2, 'INCLUDE_ITEM_TYPE'),
    (2, 'INCLUDE_COLLECTION_CODE'),
    (2, 'INCLUDE_CALL_NUMBER'),
    (2, 'INCLUDE_OWNING_LIB'),
    (2, 'INCLUDE_QUANTITY'),
    (2, 'INCLUDE_BIB_PAGINATION'),
    (2, 'BUYER_ID_INCLUDE_VENDCODE'),
    (2, 'INCLUDE_EMPTY_LI_NOTE'),
    (2, 'INCLUDE_EMPTY_CALL_NUMBER'),
    (2, 'INCLUDE_EMPTY_ITEM_TYPE'),
    (2, 'INCLUDE_EMPTY_COLLECTION_CODE'),
    (2, 'INCLUDE_EMPTY_LOCATION'),
    (2, 'LINEITEM_IDENT_VENDOR_NUMBER'),
    (2, 'LINEITEM_REF_ID_ONLY'),

    -- Brodart
    (3, 'INCLUDE_COPIES'),
    (3, 'INCLUDE_FUND'),
    (3, 'INCLUDE_ITEM_TYPE'),
    (3, 'INCLUDE_COLLECTION_CODE'),
    (3, 'INCLUDE_OWNING_LIB'),
    (3, 'INCLUDE_QUANTITY'),
    (3, 'INCLUDE_BIB_PAGINATION'),
    (3, 'COPY_SPEC_CODES'),

    -- Midwest
    (4, 'INCLUDE_COPIES'),
    (4, 'INCLUDE_FUND'),
    (4, 'INCLUDE_OWNING_LIB'),
    (4, 'INCLUDE_QUANTITY'),
    (4, 'INCLUDE_BIB_PAGINATION'),

    -- ULS
    (5, 'INCLUDE_COPIES'),
    (5, 'INCLUDE_ITEM_TYPE'),
    (5, 'INCLUDE_COLLECTION_CODE'),
    (5, 'INCLUDE_OWNING_LIB'),
    (5, 'INCLUDE_QUANTITY'),
    (5, 'INCLUDE_BIB_AUTHOR'),
    (5, 'INCLUDE_BIB_EDITION'),
    (5, 'INCLUDE_EMPTY_LI_NOTE'),

    -- Recorded Books
    (6, 'INCLUDE_COPIES'),
    (6, 'INCLUDE_ITEM_TYPE'),
    (6, 'INCLUDE_COLLECTION_CODE'),
    (6, 'INCLUDE_OWNING_LIB'),
    (6, 'INCLUDE_QUANTITY'),
    (6, 'INCLUDE_BIB_PAGINATION'),

    -- Midwest Library Service
    (7, 'INCLUDE_BIB_AUTHOR'),
    (7, 'INCLUDE_BIB_EDITION'),
    (7, 'BUYER_ID_ONLY_VENDCODE'),
    (7, 'INCLUDE_EMPTY_IMD_VALUES')
;





SELECT evergreen.upgrade_deps_block_check('1068', :eg_version); --miker/gmcharlt/kmlussier

INSERT INTO config.xml_transform (name,namespace_uri,prefix,xslt) VALUES ('mads21','http://www.loc.gov/mads/v2','mads21',$XSLT$<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:mads="http://www.loc.gov/mads/v2"
	xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:marc="http://www.loc.gov/MARC21/slim"
	xmlns:xsl="http://www.w3.org/1999/XSL/Transform" exclude-result-prefixes="marc">
	<xsl:output method="xml" indent="yes" encoding="UTF-8"/>
	<xsl:strip-space elements="*"/>

	<xsl:variable name="ascii">
		<xsl:text> !"#$%&amp;'()*+,-./0123456789:;&lt;=&gt;?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~</xsl:text>
	</xsl:variable>

	<xsl:variable name="latin1">
		<xsl:text> ¡¢£¤¥¦§¨©ª«¬­®¯°±²³´µ¶·¸¹º»¼½¾¿ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖ×ØÙÚÛÜÝÞßàáâãäåæçèéêëìíîïðñòóôõö÷øùúûüýþÿ</xsl:text>
	</xsl:variable>
	<!-- Characters that usually don't need to be escaped -->
	<xsl:variable name="safe">
		<xsl:text>!'()*-.0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~</xsl:text>
	</xsl:variable>

	<xsl:variable name="hex">0123456789ABCDEF</xsl:variable>


	<xsl:template name="datafield">
		<xsl:param name="tag"/>
		<xsl:param name="ind1">
			<xsl:text> </xsl:text>
		</xsl:param>
		<xsl:param name="ind2">
			<xsl:text> </xsl:text>
		</xsl:param>
		<xsl:param name="subfields"/>
		<xsl:element name="marc:datafield">
			<xsl:attribute name="tag">
				<xsl:value-of select="$tag"/>
			</xsl:attribute>
			<xsl:attribute name="ind1">
				<xsl:value-of select="$ind1"/>
			</xsl:attribute>
			<xsl:attribute name="ind2">
				<xsl:value-of select="$ind2"/>
			</xsl:attribute>
			<xsl:copy-of select="$subfields"/>
		</xsl:element>
	</xsl:template>

	<xsl:template name="subfieldSelect">
		<xsl:param name="codes">abcdefghijklmnopqrstuvwxyz</xsl:param>
		<xsl:param name="delimeter">
			<xsl:text> </xsl:text>
		</xsl:param>
		<xsl:variable name="str">
			<xsl:for-each select="marc:subfield">
				<xsl:if test="contains($codes, @code)">
					<xsl:value-of select="text()"/>
					<xsl:value-of select="$delimeter"/>
				</xsl:if>
			</xsl:for-each>
		</xsl:variable>
		<xsl:value-of select="substring($str,1,string-length($str)-string-length($delimeter))"/>
	</xsl:template>

	<xsl:template name="buildSpaces">
		<xsl:param name="spaces"/>
		<xsl:param name="char">
			<xsl:text> </xsl:text>
		</xsl:param>
		<xsl:if test="$spaces>0">
			<xsl:value-of select="$char"/>
			<xsl:call-template name="buildSpaces">
				<xsl:with-param name="spaces" select="$spaces - 1"/>
				<xsl:with-param name="char" select="$char"/>
			</xsl:call-template>
		</xsl:if>
	</xsl:template>

	<xsl:template name="chopPunctuation">
		<xsl:param name="chopString"/>
		<xsl:param name="punctuation">
			<xsl:text>.:,;/ </xsl:text>
		</xsl:param>
		<xsl:variable name="length" select="string-length($chopString)"/>
		<xsl:choose>
			<xsl:when test="$length=0"/>
			<xsl:when test="contains($punctuation, substring($chopString,$length,1))">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="substring($chopString,1,$length - 1)"/>
					<xsl:with-param name="punctuation" select="$punctuation"/>
				</xsl:call-template>
			</xsl:when>
			<xsl:when test="not($chopString)"/>
			<xsl:otherwise>
				<xsl:value-of select="$chopString"/>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>

	<xsl:template name="chopPunctuationFront">
		<xsl:param name="chopString"/>
		<xsl:variable name="length" select="string-length($chopString)"/>
		<xsl:choose>
			<xsl:when test="$length=0"/>
			<xsl:when test="contains('.:,;/[ ', substring($chopString,1,1))">
				<xsl:call-template name="chopPunctuationFront">
					<xsl:with-param name="chopString" select="substring($chopString,2,$length - 1)"
					/>
				</xsl:call-template>
			</xsl:when>
			<xsl:when test="not($chopString)"/>
			<xsl:otherwise>
				<xsl:value-of select="$chopString"/>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>

	<xsl:template name="chopPunctuationBack">
		<xsl:param name="chopString"/>
		<xsl:param name="punctuation">
			<xsl:text>.:,;/] </xsl:text>
		</xsl:param>
		<xsl:variable name="length" select="string-length($chopString)"/>
		<xsl:choose>
			<xsl:when test="$length=0"/>
			<xsl:when test="contains($punctuation, substring($chopString,$length,1))">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="substring($chopString,1,$length - 1)"/>
					<xsl:with-param name="punctuation" select="$punctuation"/>
				</xsl:call-template>
			</xsl:when>
			<xsl:when test="not($chopString)"/>
			<xsl:otherwise>
				<xsl:value-of select="$chopString"/>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>

	<!-- nate added 12/14/2007 for lccn.loc.gov: url encode ampersand, etc. -->
	<xsl:template name="url-encode">

		<xsl:param name="str"/>

		<xsl:if test="$str">
			<xsl:variable name="first-char" select="substring($str,1,1)"/>
			<xsl:choose>
				<xsl:when test="contains($safe,$first-char)">
					<xsl:value-of select="$first-char"/>
				</xsl:when>
				<xsl:otherwise>
					<xsl:variable name="codepoint">
						<xsl:choose>
							<xsl:when test="contains($ascii,$first-char)">
								<xsl:value-of
									select="string-length(substring-before($ascii,$first-char)) + 32"
								/>
							</xsl:when>
							<xsl:when test="contains($latin1,$first-char)">
								<xsl:value-of
									select="string-length(substring-before($latin1,$first-char)) + 160"/>
								<!-- was 160 -->
							</xsl:when>
							<xsl:otherwise>
								<xsl:message terminate="no">Warning: string contains a character
									that is out of range! Substituting "?".</xsl:message>
								<xsl:text>63</xsl:text>
							</xsl:otherwise>
						</xsl:choose>
					</xsl:variable>
					<xsl:variable name="hex-digit1"
						select="substring($hex,floor($codepoint div 16) + 1,1)"/>
					<xsl:variable name="hex-digit2" select="substring($hex,$codepoint mod 16 + 1,1)"/>
					<!-- <xsl:value-of select="concat('%',$hex-digit2)"/> -->
					<xsl:value-of select="concat('%',$hex-digit1,$hex-digit2)"/>
				</xsl:otherwise>
			</xsl:choose>
			<xsl:if test="string-length($str) &gt; 1">
				<xsl:call-template name="url-encode">
					<xsl:with-param name="str" select="substring($str,2)"/>
				</xsl:call-template>
			</xsl:if>
		</xsl:if>
	</xsl:template>


<!--
2.14    Fixed bug in mads:geographic attributes syntax                                      ws   05/04/2016		
2.13	fixed repeating <geographic>														tmee 01/31/2014
2.12	added $2 authority for <classification>												tmee 09/18/2012
2.11	added delimiters between <classification> subfields									tmee 09/18/2012
2.10	fixed type="other" and type="otherType" for mads:related							tmee 09/16/2011
2.09	fixed professionTerm and genreTerm empty tag error									tmee 09/16/2011
2.08	fixed marc:subfield @code='i' matching error										tmee 09/16/2011
2.07	fixed 555 duplication error															tmee 08/10/2011	
2.06	fixed topic subfield error															tmee 08/10/2011	
2.05	fixed title subfield error															tmee 06/20/2011	
2.04	fixed geographicSubdivision mapping for authority element							tmee 06/16/2011
2.03	added classification for 053, 055, 060, 065, 070, 080, 082, 083, 086, 087			tmee 06/03/2011		
2.02	added descriptionStandard for 008/10												tmee 04/27/2011
2.01	added extensions for 046, 336, 370, 374, 375, 376									tmee 04/08/2011
2.00	redefined imported MODS elements in version 1.0 to MADS elements in version 2.0		tmee 02/08/2011
1.08	added 372 subfields $a $s $t for <fieldOfActivity>									tmee 06/24/2010
1.07	removed role/roleTerm 100, 110, 111, 400, 410, 411, 500, 510, 511, 700, 710, 711	tmee 06/24/2010
1.06	added strip-space																	tmee 06/24/2010
1.05	added subfield $a for 130, 430, 530													tmee 06/21/2010
1.04	fixed 550 z omission																ntra 08/11/2008
1.03	removed duplication of 550 $a text													tmee 11/01/2006
1.02	fixed namespace references between mads and mods									ntra 10/06/2006
1.01	revised																				rgue/jrad 11/29/05
1.00	adapted from MARC21Slim2MODS3.xsl													ntra 07/06/05
-->

	<!-- authority attribute defaults to 'naf' if not set using this authority parameter, for <authority> descriptors: name, titleInfo, geographic -->
	<xsl:param name="authority"/>
	<xsl:variable name="auth">
		<xsl:choose>
			<xsl:when test="$authority">
				<xsl:value-of select="$authority"/>
			</xsl:when>
			<xsl:otherwise>naf</xsl:otherwise>
		</xsl:choose>
	</xsl:variable>
	<xsl:variable name="controlField008" select="marc:controlfield[@tag='008']"/>
	<xsl:variable name="controlField008-06"
		select="substring(descendant-or-self::marc:controlfield[@tag=008],7,1)"/>
	<xsl:variable name="controlField008-11"
		select="substring(descendant-or-self::marc:controlfield[@tag=008],12,1)"/>
	<xsl:variable name="controlField008-14"
		select="substring(descendant-or-self::marc:controlfield[@tag=008],15,1)"/>
	<xsl:template match="/">
		<xsl:choose>
			<xsl:when test="descendant-or-self::marc:collection">
				<mads:madsCollection xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
					xsi:schemaLocation="http://www.loc.gov/mads/v2 http://www.loc.gov/standards/mads/v2/mads-2-0.xsd">
					<xsl:for-each select="descendant-or-self::marc:collection/marc:record">
						<mads:mads version="2.0">
							<xsl:call-template name="marcRecord"/>
						</mads:mads>
					</xsl:for-each>
				</mads:madsCollection>
			</xsl:when>
			<xsl:otherwise>
				<mads:mads version="2.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
					xsi:schemaLocation="http://www.loc.gov/mads/v2 http://www.loc.gov/standards/mads/mads-2-0.xsd">
					<xsl:for-each select="descendant-or-self::marc:record">
						<xsl:call-template name="marcRecord"/>
					</xsl:for-each>
				</mads:mads>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>

	<xsl:template name="marcRecord">
		<mads:authority>
			<!-- 2.04 -->
			<xsl:choose>
				<xsl:when test="$controlField008-06='d'">
					<xsl:attribute name="geographicSubdivision">
						<xsl:text>direct</xsl:text>
					</xsl:attribute>
				</xsl:when>
				<xsl:when test="$controlField008-06='i'">
					<xsl:attribute name="geographicSubdivision">
						<xsl:text>indirect</xsl:text>
					</xsl:attribute>
				</xsl:when>
				<xsl:when test="$controlField008-06='n'">
					<xsl:attribute name="geographicSubdivision">
						<xsl:text>not applicable</xsl:text>
					</xsl:attribute>
				</xsl:when>
			</xsl:choose>
			
			<xsl:apply-templates select="marc:datafield[100 &lt;= @tag  and @tag &lt; 200]"/>		
		</mads:authority>

		<!-- related -->
		<xsl:apply-templates
			select="marc:datafield[500 &lt;= @tag and @tag &lt;= 585]|marc:datafield[700 &lt;= @tag and @tag &lt;= 785]"/>

		<!-- variant -->
		<xsl:apply-templates select="marc:datafield[400 &lt;= @tag and @tag &lt;= 485]"/>

		<!-- notes -->
		<xsl:apply-templates select="marc:datafield[667 &lt;= @tag and @tag &lt;= 688]"/>

		<!-- url -->
		<xsl:apply-templates select="marc:datafield[@tag=856]"/>
		<xsl:apply-templates select="marc:datafield[@tag=010]"/>
		<xsl:apply-templates select="marc:datafield[@tag=024]"/>
		<xsl:apply-templates select="marc:datafield[@tag=372]"/>
		
		<!-- classification -->
		<xsl:apply-templates select="marc:datafield[@tag=053]"/>
		<xsl:apply-templates select="marc:datafield[@tag=055]"/>
		<xsl:apply-templates select="marc:datafield[@tag=060]"/>
		<xsl:apply-templates select="marc:datafield[@tag=065]"/>
		<xsl:apply-templates select="marc:datafield[@tag=070]"/>
		<xsl:apply-templates select="marc:datafield[@tag=080]"/>
		<xsl:apply-templates select="marc:datafield[@tag=082]"/>
		<xsl:apply-templates select="marc:datafield[@tag=083]"/>
		<xsl:apply-templates select="marc:datafield[@tag=086]"/>
		<xsl:apply-templates select="marc:datafield[@tag=087]"/>

		<!-- affiliation-->
		<xsl:for-each select="marc:datafield[@tag=373]">
			<mads:affiliation>
				<mads:position>
					<xsl:value-of select="marc:subfield[@code='a']"/>
				</mads:position>
				<mads:dateValid point="start">
					<xsl:value-of select="marc:subfield[@code='s']"/>
				</mads:dateValid>
				<mads:dateValid point="end">
					<xsl:value-of select="marc:subfield[@code='t']"/>
				</mads:dateValid>
			</mads:affiliation>
		</xsl:for-each>
		<xsl:for-each select="marc:datafield[@tag=371]">
			<mads:affiliation>
				<mads:address>
					<mads:street>
						<xsl:value-of select="marc:subfield[@code='a']"/>
					</mads:street>
					<mads:city>
						<xsl:value-of select="marc:subfield[@code='b']"/>
					</mads:city>
					<mads:state>
						<xsl:value-of select="marc:subfield[@code='c']"/>
					</mads:state>
					<mads:country>
						<xsl:value-of select="marc:subfield[@code='d']"/>
					</mads:country>
					<mads:postcode>
						<xsl:value-of select="marc:subfield[@code='e']"/>
					</mads:postcode>
				</mads:address>
				<mads:email>
					<xsl:value-of select="marc:subfield[@code='m']"/>
				</mads:email>
			</mads:affiliation>
		</xsl:for-each>

		<!-- extension-->
		<xsl:for-each select="marc:datafield[@tag=336]">
			<mads:extension>
				<mads:contentType>
					<mads:contentType type="text">
						<xsl:value-of select="marc:subfield[@code='a']"/>
					</mads:contentType>
					<mads:contentType type="code">
						<xsl:value-of select="marc:subfield[@code='b']"/>
					</mads:contentType>
				</mads:contentType>
			</mads:extension>
		</xsl:for-each>

		<xsl:for-each select="marc:datafield[@tag=374]">
			<mads:extension>
				<mads:profession>
					<xsl:choose>
						<xsl:when test="marc:subfield[@code='a']">
							<mads:professionTerm>
								<xsl:value-of select="marc:subfield[@code='a']"/>
							</mads:professionTerm>
						</xsl:when>
						<xsl:when test="marc:subfield[@code='s']">
							<mads:dateValid point="start">
								<xsl:value-of select="marc:subfield[@code='s']"/>
							</mads:dateValid>
						</xsl:when>
						<xsl:when test="marc:subfield[@code='t']">
							<mads:dateValid point="end">
								<xsl:value-of select="marc:subfield[@code='t']"/>
							</mads:dateValid>
						</xsl:when>
					</xsl:choose>
				</mads:profession>
			</mads:extension>
		</xsl:for-each>
		
		<xsl:for-each select="marc:datafield[@tag=375]">
			<mads:extension>
				<mads:gender>
					<xsl:choose>
						<xsl:when test="marc:subfield[@code='a']">
							<mads:genderTerm>
								<xsl:value-of select="marc:subfield[@code='a']"/>
							</mads:genderTerm>
						</xsl:when>
						<xsl:when test="marc:subfield[@code='s']">
							<mads:dateValid point="start">
								<xsl:value-of select="marc:subfield[@code='s']"/>
							</mads:dateValid>
						</xsl:when>
						<xsl:when test="marc:subfield[@code='t']">
							<mads:dateValid point="end">
								<xsl:value-of select="marc:subfield[@code='t']"/>
							</mads:dateValid>
						</xsl:when>
					</xsl:choose>
				</mads:gender>
			</mads:extension>
		</xsl:for-each>

		<xsl:for-each select="marc:datafield[@tag=376]">
			<mads:extension>
				<mads:familyInformation>
					<mads:typeOfFamily>
						<xsl:value-of select="marc:subfield[@code='a']"/>
					</mads:typeOfFamily>
					<mads:nameOfProminentMember>
						<xsl:value-of select="marc:subfield[@code='b']"/>
					</mads:nameOfProminentMember>
					<mads:hereditaryTitle>
						<xsl:value-of select="marc:subfield[@code='c']"/>
					</mads:hereditaryTitle>
					<mads:dateValid point="start">
						<xsl:value-of select="marc:subfield[@code='s']"/>
					</mads:dateValid>
					<mads:dateValid point="end">
						<xsl:value-of select="marc:subfield[@code='t']"/>
					</mads:dateValid>
				</mads:familyInformation>
			</mads:extension>
		</xsl:for-each>

		<mads:recordInfo>
			<mads:recordOrigin>Converted from MARCXML to MADS version 2.0 (Revision 2.13)</mads:recordOrigin>
			<!-- <xsl:apply-templates select="marc:datafield[@tag=024]"/> -->

			<xsl:apply-templates select="marc:datafield[@tag=040]/marc:subfield[@code='a']"/>
			<xsl:apply-templates select="marc:controlfield[@tag=005]"/>
			<xsl:apply-templates select="marc:controlfield[@tag=001]"/>
			<xsl:apply-templates select="marc:datafield[@tag=040]/marc:subfield[@code='b']"/>
			<xsl:apply-templates select="marc:datafield[@tag=040]/marc:subfield[@code='e']"/>
			<xsl:for-each select="marc:controlfield[@tag=008]">
				<xsl:if test="substring(.,11,1)='a'">
					<mads:descriptionStandard>
						<xsl:text>earlier rules</xsl:text>
					</mads:descriptionStandard>
				</xsl:if>
				<xsl:if test="substring(.,11,1)='b'">
					<mads:descriptionStandard>
						<xsl:text>aacr1</xsl:text>
					</mads:descriptionStandard>
				</xsl:if>
				<xsl:if test="substring(.,11,1)='c'">
					<mads:descriptionStandard>
						<xsl:text>aacr2</xsl:text>
					</mads:descriptionStandard>
				</xsl:if>
				<xsl:if test="substring(.,11,1)='d'">
					<mads:descriptionStandard>
						<xsl:text>aacr2 compatible</xsl:text>
					</mads:descriptionStandard>
				</xsl:if>
				<xsl:if test="substring(.,11,1)='z'">
					<mads:descriptionStandard>
						<xsl:text>other rules</xsl:text>
					</mads:descriptionStandard>
				</xsl:if>
			</xsl:for-each>
		</mads:recordInfo>
	</xsl:template>

	<!-- start of secondary templates -->

	<!-- ======== xlink ======== -->

	<!-- <xsl:template name="uri"> 
    <xsl:for-each select="marc:subfield[@code='0']">
      <xsl:attribute name="xlink:href">
	<xsl:value-of select="."/>
      </xsl:attribute>
    </xsl:for-each>
     </xsl:template> 
   -->
	<xsl:template match="marc:subfield[@code='i']">
		<xsl:attribute name="otherType">
			<xsl:value-of select="."/>
		</xsl:attribute>
	</xsl:template>

	<!-- No role/roleTerm mapped in MADS 06/24/2010
	<xsl:template name="role">
		<xsl:for-each select="marc:subfield[@code='e']">
			<mads:role>
				<mads:roleTerm type="text">
					<xsl:value-of select="."/>
				</mads:roleTerm>
			</mads:role>
		</xsl:for-each>
	</xsl:template>
-->

	<xsl:template name="part">
		<xsl:variable name="partNumber">
			<xsl:call-template name="specialSubfieldSelect">
				<xsl:with-param name="axis">n</xsl:with-param>
				<xsl:with-param name="anyCodes">n</xsl:with-param>
				<xsl:with-param name="afterCodes">fghkdlmor</xsl:with-param>
			</xsl:call-template>
		</xsl:variable>
		<xsl:variable name="partName">
			<xsl:call-template name="specialSubfieldSelect">
				<xsl:with-param name="axis">p</xsl:with-param>
				<xsl:with-param name="anyCodes">p</xsl:with-param>
				<xsl:with-param name="afterCodes">fghkdlmor</xsl:with-param>
			</xsl:call-template>
		</xsl:variable>
		<xsl:if test="string-length(normalize-space($partNumber))">
			<mads:partNumber>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="$partNumber"/>
				</xsl:call-template>
			</mads:partNumber>
		</xsl:if>
		<xsl:if test="string-length(normalize-space($partName))">
			<mads:partName>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="$partName"/>
				</xsl:call-template>
			</mads:partName>
		</xsl:if>
	</xsl:template>

	<xsl:template name="nameABCDN">
		<xsl:for-each select="marc:subfield[@code='a']">
			<mads:namePart>
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="."/>
				</xsl:call-template>
			</mads:namePart>
		</xsl:for-each>
		<xsl:for-each select="marc:subfield[@code='b']">
			<mads:namePart>
				<xsl:value-of select="."/>
			</mads:namePart>
		</xsl:for-each>
		<xsl:if
			test="marc:subfield[@code='c'] or marc:subfield[@code='d'] or marc:subfield[@code='n']">
			<mads:namePart>
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">cdn</xsl:with-param>
				</xsl:call-template>
			</mads:namePart>
		</xsl:if>
	</xsl:template>

	<xsl:template name="nameABCDQ">
		<mads:namePart>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString">
					<xsl:call-template name="subfieldSelect">
						<xsl:with-param name="codes">aq</xsl:with-param>
					</xsl:call-template>
				</xsl:with-param>
			</xsl:call-template>
		</mads:namePart>
		<xsl:call-template name="termsOfAddress"/>
		<xsl:call-template name="nameDate"/>
	</xsl:template>

	<xsl:template name="nameACDENQ">
		<mads:namePart>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">acdenq</xsl:with-param>
			</xsl:call-template>
		</mads:namePart>
	</xsl:template>

	<xsl:template name="nameDate">
		<xsl:for-each select="marc:subfield[@code='d']">
			<mads:namePart type="date">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString" select="."/>
				</xsl:call-template>
			</mads:namePart>
		</xsl:for-each>
	</xsl:template>

	<xsl:template name="specialSubfieldSelect">
		<xsl:param name="anyCodes"/>
		<xsl:param name="axis"/>
		<xsl:param name="beforeCodes"/>
		<xsl:param name="afterCodes"/>
		<xsl:variable name="str">
			<xsl:for-each select="marc:subfield">
				<xsl:if
					test="contains($anyCodes, @code) or (contains($beforeCodes,@code) and following-sibling::marc:subfield[@code=$axis]) or (contains($afterCodes,@code) and preceding-sibling::marc:subfield[@code=$axis])">
					<xsl:value-of select="text()"/>
					<xsl:text> </xsl:text>
				</xsl:if>
			</xsl:for-each>
		</xsl:variable>
		<xsl:value-of select="substring($str,1,string-length($str)-1)"/>
	</xsl:template>

	<xsl:template name="termsOfAddress">
		<xsl:if test="marc:subfield[@code='b' or @code='c']">
			<mads:namePart type="termsOfAddress">
				<xsl:call-template name="chopPunctuation">
					<xsl:with-param name="chopString">
						<xsl:call-template name="subfieldSelect">
							<xsl:with-param name="codes">bc</xsl:with-param>
						</xsl:call-template>
					</xsl:with-param>
				</xsl:call-template>
			</mads:namePart>
		</xsl:if>
	</xsl:template>

	<xsl:template name="displayLabel">
		<xsl:if test="marc:subfield[@code='z']">
			<xsl:attribute name="displayLabel">
				<xsl:value-of select="marc:subfield[@code='z']"/>
			</xsl:attribute>
		</xsl:if>
		<xsl:if test="marc:subfield[@code='3']">
			<xsl:attribute name="displayLabel">
				<xsl:value-of select="marc:subfield[@code='3']"/>
			</xsl:attribute>
		</xsl:if>
	</xsl:template>

	<xsl:template name="isInvalid">
		<xsl:if test="@code='z'">
			<xsl:attribute name="invalid">yes</xsl:attribute>
		</xsl:if>
	</xsl:template>

	<xsl:template name="sub2Attribute">
		<!-- 024 -->
		<xsl:if test="../marc:subfield[@code='2']">
			<xsl:attribute name="type">
				<xsl:value-of select="../marc:subfield[@code='2']"/>
			</xsl:attribute>
		</xsl:if>
	</xsl:template>

	<xsl:template match="marc:controlfield[@tag=001]">
		<mads:recordIdentifier>
			<xsl:if test="../marc:controlfield[@tag=003]">
				<xsl:attribute name="source">
					<xsl:value-of select="../marc:controlfield[@tag=003]"/>
				</xsl:attribute>
			</xsl:if>
			<xsl:value-of select="."/>
		</mads:recordIdentifier>
	</xsl:template>

	<xsl:template match="marc:controlfield[@tag=005]">
		<mads:recordChangeDate encoding="iso8601">
			<xsl:value-of select="."/>
		</mads:recordChangeDate>
	</xsl:template>

	<xsl:template match="marc:controlfield[@tag=008]">
		<mads:recordCreationDate encoding="marc">
			<xsl:value-of select="substring(.,1,6)"/>
		</mads:recordCreationDate>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=010]">
		<xsl:for-each select="marc:subfield">
			<mads:identifier type="lccn">
				<xsl:call-template name="isInvalid"/>
				<xsl:value-of select="."/>
			</mads:identifier>
		</xsl:for-each>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=024]">
		<xsl:for-each select="marc:subfield[not(@code=2)]">
			<mads:identifier>
				<xsl:call-template name="isInvalid"/>
				<xsl:call-template name="sub2Attribute"/>
				<xsl:value-of select="."/>
			</mads:identifier>
		</xsl:for-each>
	</xsl:template>

	<!-- ========== 372 ========== -->
	<xsl:template match="marc:datafield[@tag=372]">
		<mads:fieldOfActivity>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">a</xsl:with-param>
			</xsl:call-template>
			<xsl:text>-</xsl:text>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">st</xsl:with-param>
			</xsl:call-template>
		</mads:fieldOfActivity>
	</xsl:template>


	<!-- ========== 040 ========== -->
	<xsl:template match="marc:datafield[@tag=040]/marc:subfield[@code='a']">
		<mads:recordContentSource authority="marcorg">
			<xsl:value-of select="."/>
		</mads:recordContentSource>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=040]/marc:subfield[@code='b']">
		<mads:languageOfCataloging>
			<mads:languageTerm authority="iso639-2b" type="code">
				<xsl:value-of select="."/>
			</mads:languageTerm>
		</mads:languageOfCataloging>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=040]/marc:subfield[@code='e']">
		<mads:descriptionStandard>
			<xsl:value-of select="."/>
		</mads:descriptionStandard>
	</xsl:template>
	
	<!-- ========== classification 2.03 ========== -->
	
	<xsl:template match="marc:datafield[@tag=053]">
		<mads:classification>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">abcdxyz</xsl:with-param>
				<xsl:with-param name="delimeter">-</xsl:with-param>
			</xsl:call-template>
		</mads:classification>
	</xsl:template>
	
	<xsl:template match="marc:datafield[@tag=055]">
		<mads:classification>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">abcdxyz</xsl:with-param>
				<xsl:with-param name="delimeter">-</xsl:with-param>
			</xsl:call-template>
		</mads:classification>
	</xsl:template>
	
	<xsl:template match="marc:datafield[@tag=060]">
		<mads:classification>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">abcdxyz</xsl:with-param>
				<xsl:with-param name="delimeter">-</xsl:with-param>
			</xsl:call-template>
		</mads:classification>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=065]">
		<mads:classification>
			<xsl:attribute name="authority">
				<xsl:value-of select="marc:subfield[@code='2']"/>
			</xsl:attribute>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">abcdxyz</xsl:with-param>
				<xsl:with-param name="delimeter">-</xsl:with-param>
			</xsl:call-template>
		</mads:classification>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=070]">
		<mads:classification>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">abcdxyz5</xsl:with-param>
				<xsl:with-param name="delimeter">-</xsl:with-param>
			</xsl:call-template>
		</mads:classification>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=080]">
		<mads:classification>
			<xsl:attribute name="authority">
				<xsl:value-of select="marc:subfield[@code='2']"/>
			</xsl:attribute>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">abcdxyz5</xsl:with-param>
				<xsl:with-param name="delimeter">-</xsl:with-param>
			</xsl:call-template>
		</mads:classification>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=082]">
		<mads:classification>
			<xsl:attribute name="authority">
				<xsl:value-of select="marc:subfield[@code='2']"/>
			</xsl:attribute>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">abcdxyz5</xsl:with-param>
				<xsl:with-param name="delimeter">-</xsl:with-param>
			</xsl:call-template>
		</mads:classification>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=083]">
		<mads:classification>
			<xsl:attribute name="authority">
				<xsl:value-of select="marc:subfield[@code='2']"/>
			</xsl:attribute>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">abcdxyz5</xsl:with-param>
				<xsl:with-param name="delimeter">-</xsl:with-param>
			</xsl:call-template>
		</mads:classification>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=086]">
		<mads:classification>
			<xsl:attribute name="authority">
				<xsl:value-of select="marc:subfield[@code='2']"/>
			</xsl:attribute>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">abcdxyz5</xsl:with-param>
				<xsl:with-param name="delimeter">-</xsl:with-param>
			</xsl:call-template>
		</mads:classification>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=087]">
		<mads:classification>
			<xsl:attribute name="authority">
				<xsl:value-of select="marc:subfield[@code='2']"/>
			</xsl:attribute>
			<xsl:call-template name="subfieldSelect">
				<xsl:with-param name="codes">abcdxyz5</xsl:with-param>
				<xsl:with-param name="delimeter">-</xsl:with-param>
			</xsl:call-template>
		</mads:classification>
	</xsl:template>
	

	<!-- ========== names  ========== -->
	<xsl:template match="marc:datafield[@tag=100]">
		<mads:name type="personal">
			<xsl:call-template name="setAuthority"/>
			<xsl:call-template name="nameABCDQ"/>
		</mads:name>
		<xsl:apply-templates select="*[marc:subfield[not(contains('abcdeq',@code))]]"/>
		<xsl:call-template name="title"/>
		<xsl:apply-templates select="marc:subfield[@code!='i']"/>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=110]">
		<mads:name type="corporate">
			<xsl:call-template name="setAuthority"/>
			<xsl:call-template name="nameABCDN"/>
		</mads:name>
		<xsl:apply-templates select="marc:subfield[@code!='i']"/>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=111]">
		<mads:name type="conference">
			<xsl:call-template name="setAuthority"/>
			<xsl:call-template name="nameACDENQ"/>
		</mads:name>
		<xsl:apply-templates select="marc:subfield[@code!='i']"/>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=400]">
		<mads:variant>
			<xsl:call-template name="variantTypeAttribute"/>
			<mads:name type="personal">
				<xsl:call-template name="nameABCDQ"/>
			</mads:name>
			<xsl:apply-templates select="marc:subfield[@code!='i']"/>
			<xsl:call-template name="title"/>
		</mads:variant>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=410]">
		<mads:variant>
			<xsl:call-template name="variantTypeAttribute"/>
			<mads:name type="corporate">
				<xsl:call-template name="nameABCDN"/>
			</mads:name>
			<xsl:apply-templates select="marc:subfield[@code!='i']"/>
		</mads:variant>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=411]">
		<mads:variant>
			<xsl:call-template name="variantTypeAttribute"/>
			<mads:name type="conference">
				<xsl:call-template name="nameACDENQ"/>
			</mads:name>
			<xsl:apply-templates select="marc:subfield[@code!='i']"/>
		</mads:variant>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=500]|marc:datafield[@tag=700]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<!-- <xsl:call-template name="uri"/> -->
			<mads:name type="personal">
				<xsl:call-template name="setAuthority"/>
				<xsl:call-template name="nameABCDQ"/>
			</mads:name>
			<xsl:call-template name="title"/>
			<xsl:apply-templates select="marc:subfield[@code!='i']"/>
		</mads:related>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=510]|marc:datafield[@tag=710]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<!-- <xsl:call-template name="uri"/> -->
			<mads:name type="corporate">
				<xsl:call-template name="setAuthority"/>
				<xsl:call-template name="nameABCDN"/>
			</mads:name>
			<xsl:apply-templates select="marc:subfield[@code!='i']"/>
		</mads:related>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=511]|marc:datafield[@tag=711]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<!-- <xsl:call-template name="uri"/> -->
			<mads:name type="conference">
				<xsl:call-template name="setAuthority"/>
				<xsl:call-template name="nameACDENQ"/>
			</mads:name>
			<xsl:apply-templates select="marc:subfield[@code!='i']"/>
		</mads:related>
	</xsl:template>

	<!-- ========== titles  ========== -->
	<xsl:template match="marc:datafield[@tag=130]">
		<xsl:call-template name="uniform-title"/>
		<xsl:apply-templates select="marc:subfield[@code!='i']"/>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=430]">
		<mads:variant>
			<xsl:call-template name="variantTypeAttribute"/>
			<xsl:call-template name="uniform-title"/>
			<xsl:apply-templates select="marc:subfield[@code!='i']"/>
		</mads:variant>
	</xsl:template>

	<xsl:template match="marc:datafield[@tag=530]|marc:datafield[@tag=730]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<xsl:call-template name="uniform-title"/>
			<xsl:apply-templates select="marc:subfield[@code!='i']"/>
		</mads:related>
	</xsl:template>

	<xsl:template name="title">
		<xsl:variable name="hasTitle">
			<xsl:for-each select="marc:subfield">
				<xsl:if test="(contains('tfghklmors',@code) )">
					<xsl:value-of select="@code"/>
				</xsl:if>
			</xsl:for-each>
		</xsl:variable>
		<xsl:if test="string-length($hasTitle) &gt; 0 ">
			<mads:titleInfo>
				<xsl:call-template name="setAuthority"/>
				<mads:title>
					<xsl:variable name="str">
						<xsl:for-each select="marc:subfield">
							<xsl:if test="(contains('atfghklmors',@code) )">
								<xsl:value-of select="text()"/>
								<xsl:text> </xsl:text>
							</xsl:if>
						</xsl:for-each>
					</xsl:variable>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:value-of select="substring($str,1,string-length($str)-1)"/>
						</xsl:with-param>
					</xsl:call-template>
				</mads:title>
				<xsl:call-template name="part"/>
				<!-- <xsl:call-template name="uri"/> -->
			</mads:titleInfo>
		</xsl:if>
	</xsl:template>

	<xsl:template name="uniform-title">
		<xsl:variable name="hasTitle">
			<xsl:for-each select="marc:subfield">
				<xsl:if test="(contains('atfghklmors',@code) )">
					<xsl:value-of select="@code"/>
				</xsl:if>
			</xsl:for-each>
		</xsl:variable>
		<xsl:if test="string-length($hasTitle) &gt; 0 ">
			<mads:titleInfo>
				<xsl:call-template name="setAuthority"/>
				<mads:title>
					<xsl:variable name="str">
						<xsl:for-each select="marc:subfield">
							<xsl:if test="(contains('adfghklmors',@code) )">
								<xsl:value-of select="text()"/>
								<xsl:text> </xsl:text>
							</xsl:if>
						</xsl:for-each>
					</xsl:variable>
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:value-of select="substring($str,1,string-length($str)-1)"/>
						</xsl:with-param>
					</xsl:call-template>
				</mads:title>
				<xsl:call-template name="part"/>
				<!-- <xsl:call-template name="uri"/> -->
			</mads:titleInfo>
		</xsl:if>
	</xsl:template>


	<!-- ========== topics  ========== -->
	<xsl:template match="marc:subfield[@code='x']">
		<mads:topic>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString">
					<xsl:value-of select="."/>
				</xsl:with-param>
			</xsl:call-template>
		</mads:topic>
	</xsl:template>
	
	<!-- 2.06 fix -->
	<xsl:template
		match="marc:datafield[@tag=150][marc:subfield[@code='a' or @code='b']]|marc:datafield[@tag=180][marc:subfield[@code='x']]">
		<xsl:call-template name="topic"/>
		<xsl:apply-templates select="marc:subfield[@code!='i']"/>
	</xsl:template>
	<xsl:template
		match="marc:datafield[@tag=450][marc:subfield[@code='a' or @code='b']]|marc:datafield[@tag=480][marc:subfield[@code='x']]">
		<mads:variant>
			<xsl:call-template name="variantTypeAttribute"/>
			<xsl:call-template name="topic"/>
		</mads:variant>
	</xsl:template>
	<xsl:template
		match="marc:datafield[@tag=550 or @tag=750][marc:subfield[@code='a' or @code='b']]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<!-- <xsl:call-template name="uri"/> -->
			<xsl:call-template name="topic"/>
			<xsl:apply-templates select="marc:subfield[@code='z']"/>
		</mads:related>
	</xsl:template>
	<xsl:template name="topic">
		<mads:topic>
			<xsl:call-template name="setAuthority"/>
			<!-- tmee2006 dedupe 550a
			<xsl:if test="@tag=550 or @tag=750">
				<xsl:call-template name="subfieldSelect">
					<xsl:with-param name="codes">ab</xsl:with-param>
				</xsl:call-template>
			</xsl:if>	
			-->
			<xsl:choose>
				<xsl:when test="@tag=180 or @tag=480 or @tag=580 or @tag=780">
					<xsl:call-template name="chopPunctuation">
						<xsl:with-param name="chopString">
							<xsl:apply-templates select="marc:subfield[@code='x']"/>
						</xsl:with-param>
					</xsl:call-template>
				</xsl:when>
			</xsl:choose>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString">
					<xsl:choose>
						<xsl:when test="@tag=180 or @tag=480 or @tag=580 or @tag=780">
							<xsl:apply-templates select="marc:subfield[@code='x']"/>
						</xsl:when>
						<xsl:otherwise>
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">ab</xsl:with-param>
							</xsl:call-template>
						</xsl:otherwise>
					</xsl:choose>
				</xsl:with-param>
			</xsl:call-template>
		</mads:topic>
	</xsl:template>

	<!-- ========= temporals  ========== -->
	<xsl:template match="marc:subfield[@code='y']">
		<mads:temporal>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString">
					<xsl:value-of select="."/>
				</xsl:with-param>
			</xsl:call-template>
		</mads:temporal>
	</xsl:template>
	<xsl:template
		match="marc:datafield[@tag=148][marc:subfield[@code='a']]|marc:datafield[@tag=182 ][marc:subfield[@code='y']]">
		<xsl:call-template name="temporal"/>
	</xsl:template>
	<xsl:template
		match="marc:datafield[@tag=448][marc:subfield[@code='a']]|marc:datafield[@tag=482][marc:subfield[@code='y']]">
		<mads:variant>
			<xsl:call-template name="variantTypeAttribute"/>
			<xsl:call-template name="temporal"/>
		</mads:variant>
	</xsl:template>
	<xsl:template
		match="marc:datafield[@tag=548 or @tag=748][marc:subfield[@code='a']]|marc:datafield[@tag=582 or @tag=782][marc:subfield[@code='y']]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<!-- <xsl:call-template name="uri"/> -->
			<xsl:call-template name="temporal"/>
		</mads:related>
	</xsl:template>
	<xsl:template name="temporal">
		<mads:temporal>
			<xsl:call-template name="setAuthority"/>
			<xsl:if test="@tag=548 or @tag=748">
				<xsl:value-of select="marc:subfield[@code='a']"/>
			</xsl:if>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString">
					<xsl:choose>
						<xsl:when test="@tag=182 or @tag=482 or @tag=582 or @tag=782">
							<xsl:apply-templates select="marc:subfield[@code='y']"/>
						</xsl:when>
						<xsl:otherwise>
							<xsl:value-of select="marc:subfield[@code='a']"/>
						</xsl:otherwise>
					</xsl:choose>
				</xsl:with-param>
			</xsl:call-template>
		</mads:temporal>
		<xsl:apply-templates select="marc:subfield[@code!='i']"/>
	</xsl:template>

	<!-- ========== genre  ========== -->
	<xsl:template match="marc:subfield[@code='v']">
		<mads:genre>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString">
					<xsl:value-of select="."/>
				</xsl:with-param>
			</xsl:call-template>
		</mads:genre>
	</xsl:template>
	<xsl:template
		match="marc:datafield[@tag=155][marc:subfield[@code='a']]|marc:datafield[@tag=185][marc:subfield[@code='v']]">
		<xsl:call-template name="genre"/>
	</xsl:template>
	<xsl:template
		match="marc:datafield[@tag=455][marc:subfield[@code='a']]|marc:datafield[@tag=485 ][marc:subfield[@code='v']]">
		<mads:variant>
			<xsl:call-template name="variantTypeAttribute"/>
			<xsl:call-template name="genre"/>
		</mads:variant>
	</xsl:template>
	<!--
	<xsl:template match="marc:datafield[@tag=555]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<xsl:call-template name="uri"/>
			<xsl:call-template name="genre"/>
		</mads:related>
	</xsl:template>
	-->
	<xsl:template
		match="marc:datafield[@tag=555 or @tag=755][marc:subfield[@code='a']]|marc:datafield[@tag=585][marc:subfield[@code='v']]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<xsl:call-template name="genre"/>
		</mads:related>
	</xsl:template>
	<xsl:template name="genre">
		<mads:genre>
			<xsl:if test="@tag=555">
				<xsl:value-of select="marc:subfield[@code='a']"/>
			</xsl:if>
			<xsl:call-template name="setAuthority"/>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString">
					<xsl:choose>
						<!-- 2.07 fix -->
						<xsl:when test="@tag='555'"/>
						<xsl:when test="@tag=185 or @tag=485 or @tag=585">
							<xsl:apply-templates select="marc:subfield[@code='v']"/>
						</xsl:when>
						<xsl:otherwise>
							<xsl:value-of select="marc:subfield[@code='a']"/>
						</xsl:otherwise>
					</xsl:choose>
				</xsl:with-param>
			</xsl:call-template>
		</mads:genre>
		<xsl:apply-templates/>
	</xsl:template>

	<!-- ========= geographic  ========== -->
	<xsl:template match="marc:subfield[@code='z']">
		<mads:geographic>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString">
					<xsl:value-of select="."/>
				</xsl:with-param>
			</xsl:call-template>
		</mads:geographic>
	</xsl:template>
	<xsl:template name="geographic">
		<mads:geographic>
			<!-- 2.14 -->
			<xsl:call-template name="setAuthority"/>
			<!-- 2.13 -->
			<xsl:if test="@tag=151 or @tag=551">
				<xsl:value-of select="marc:subfield[@code='a']"/>
			</xsl:if>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString">
						<xsl:if test="@tag=181 or @tag=481 or @tag=581">
								<xsl:apply-templates select="marc:subfield[@code='z']"/>
						</xsl:if>
						<!-- 2.13
							<xsl:choose>
						<xsl:when test="@tag=181 or @tag=481 or @tag=581">
							<xsl:apply-templates select="marc:subfield[@code='z']"/>
						</xsl:when>
					
						<xsl:otherwise>
							<xsl:value-of select="marc:subfield[@code='a']"/>
						</xsl:otherwise>
						</xsl:choose>
						-->
				</xsl:with-param>
			</xsl:call-template>
		</mads:geographic>
		<xsl:apply-templates select="marc:subfield[@code!='i']"/>
	</xsl:template>
	<xsl:template
		match="marc:datafield[@tag=151][marc:subfield[@code='a']]|marc:datafield[@tag=181][marc:subfield[@code='z']]">
		<xsl:call-template name="geographic"/>
	</xsl:template>
	<xsl:template
		match="marc:datafield[@tag=451][marc:subfield[@code='a']]|marc:datafield[@tag=481][marc:subfield[@code='z']]">
		<mads:variant>
			<xsl:call-template name="variantTypeAttribute"/>
			<xsl:call-template name="geographic"/>
		</mads:variant>
	</xsl:template>
	<xsl:template
		match="marc:datafield[@tag=551]|marc:datafield[@tag=581][marc:subfield[@code='z']]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<!-- <xsl:call-template name="uri"/> -->
			<xsl:call-template name="geographic"/>
		</mads:related>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=580]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<xsl:apply-templates select="marc:subfield[@code!='i']"/>
		</mads:related>
	</xsl:template>
	<xsl:template
		match="marc:datafield[@tag=751][marc:subfield[@code='z']]|marc:datafield[@tag=781][marc:subfield[@code='z']]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<xsl:call-template name="geographic"/>
		</mads:related>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=755]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<xsl:call-template name="genre"/>
			<xsl:call-template name="setAuthority"/>
			<xsl:apply-templates select="marc:subfield[@code!='i']"/>
		</mads:related>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=780]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<xsl:apply-templates select="marc:subfield[@code!='i']"/>
		</mads:related>
	</xsl:template>
	<xsl:template match="marc:datafield[@tag=785]">
		<mads:related>
			<xsl:call-template name="relatedTypeAttribute"/>
			<xsl:apply-templates select="marc:subfield[@code!='i']"/>
		</mads:related>
	</xsl:template>

	<!-- ========== notes  ========== -->
	<xsl:template match="marc:datafield[667 &lt;= @tag and @tag &lt;= 688]">
		<mads:note>
			<xsl:choose>
				<xsl:when test="@tag=667">
					<xsl:attribute name="type">nonpublic</xsl:attribute>
				</xsl:when>
				<xsl:when test="@tag=670">
					<xsl:attribute name="type">source</xsl:attribute>
				</xsl:when>
				<xsl:when test="@tag=675">
					<xsl:attribute name="type">notFound</xsl:attribute>
				</xsl:when>
				<xsl:when test="@tag=678">
					<xsl:attribute name="type">history</xsl:attribute>
				</xsl:when>
				<xsl:when test="@tag=681">
					<xsl:attribute name="type">subject example</xsl:attribute>
				</xsl:when>
				<xsl:when test="@tag=682">
					<xsl:attribute name="type">deleted heading information</xsl:attribute>
				</xsl:when>
				<xsl:when test="@tag=688">
					<xsl:attribute name="type">application history</xsl:attribute>
				</xsl:when>
			</xsl:choose>
			<xsl:call-template name="chopPunctuation">
				<xsl:with-param name="chopString">
					<xsl:choose>
						<xsl:when test="@tag=667 or @tag=675">
							<xsl:value-of select="marc:subfield[@code='a']"/>
						</xsl:when>
						<xsl:when test="@tag=670 or @tag=678">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">ab</xsl:with-param>
							</xsl:call-template>
						</xsl:when>
						<xsl:when test="680 &lt;= @tag and @tag &lt;=688">
							<xsl:call-template name="subfieldSelect">
								<xsl:with-param name="codes">ai</xsl:with-param>
							</xsl:call-template>
						</xsl:when>
					</xsl:choose>
				</xsl:with-param>
			</xsl:call-template>
		</mads:note>
	</xsl:template>

	<!-- ========== url  ========== -->
	<xsl:template match="marc:datafield[@tag=856][marc:subfield[@code='u']]">
		<mads:url>
			<xsl:if test="marc:subfield[@code='z' or @code='3']">
				<xsl:attribute name="displayLabel">
					<xsl:call-template name="subfieldSelect">
						<xsl:with-param name="codes">z3</xsl:with-param>
					</xsl:call-template>
				</xsl:attribute>
			</xsl:if>
			<xsl:value-of select="marc:subfield[@code='u']"/>
		</mads:url>
	</xsl:template>

	<xsl:template name="relatedTypeAttribute">
		<xsl:choose>
			<xsl:when
				test="@tag=500 or @tag=510 or @tag=511 or @tag=548 or @tag=550 or @tag=551 or @tag=555 or @tag=580 or @tag=581 or @tag=582 or @tag=585">
				<xsl:if test="substring(marc:subfield[@code='w'],1,1)='a'">
					<xsl:attribute name="type">earlier</xsl:attribute>
				</xsl:if>
				<xsl:if test="substring(marc:subfield[@code='w'],1,1)='b'">
					<xsl:attribute name="type">later</xsl:attribute>
				</xsl:if>
				<xsl:if test="substring(marc:subfield[@code='w'],1,1)='t'">
					<xsl:attribute name="type">parentOrg</xsl:attribute>
				</xsl:if>
				<xsl:if test="substring(marc:subfield[@code='w'],1,1)='g'">
					<xsl:attribute name="type">broader</xsl:attribute>
				</xsl:if>
				<xsl:if test="substring(marc:subfield[@code='w'],1,1)='h'">
					<xsl:attribute name="type">narrower</xsl:attribute>
				</xsl:if>
				<xsl:if test="substring(marc:subfield[@code='w'],1,1)='r'">
					<xsl:attribute name="type">other</xsl:attribute>
				</xsl:if>
				<xsl:if test="contains('fin|', substring(marc:subfield[@code='w'],1,1))">
					<xsl:attribute name="type">other</xsl:attribute>
				</xsl:if>
			</xsl:when>
			<xsl:when test="@tag=530 or @tag=730">
				<xsl:attribute name="type">other</xsl:attribute>
			</xsl:when>
			<xsl:otherwise>
				<!-- 7xx -->
				<xsl:attribute name="type">equivalent</xsl:attribute>
			</xsl:otherwise>
		</xsl:choose>
		<xsl:apply-templates select="marc:subfield[@code='i']"/>
	</xsl:template>
	


	<xsl:template name="variantTypeAttribute">
		<xsl:choose>
			<xsl:when
				test="@tag=400 or @tag=410 or @tag=411 or @tag=451 or @tag=455 or @tag=480 or @tag=481 or @tag=482 or @tag=485">
				<xsl:if test="substring(marc:subfield[@code='w'],1,1)='d'">
					<xsl:attribute name="type">acronym</xsl:attribute>
				</xsl:if>
				<xsl:if test="substring(marc:subfield[@code='w'],1,1)='n'">
					<xsl:attribute name="type">other</xsl:attribute>
				</xsl:if>
				<xsl:if test="contains('fit', substring(marc:subfield[@code='w'],1,1))">
					<xsl:attribute name="type">other</xsl:attribute>
				</xsl:if>
			</xsl:when>
			<xsl:otherwise>
				<!-- 430  -->
				<xsl:attribute name="type">other</xsl:attribute>
			</xsl:otherwise>
		</xsl:choose>
		<xsl:apply-templates select="marc:subfield[@code='i']"/>
	</xsl:template>

	<xsl:template name="setAuthority">
		<xsl:choose>
			<!-- can be called from the datafield or subfield level, so "..//@tag" means
			the tag can be at the subfield's parent level or at the datafields own level -->

			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=100 and (@ind1=0 or @ind1=1) and $controlField008-11='a' and $controlField008-14='a'">
				<xsl:attribute name="authority">
					<xsl:text>naf</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=100 and (@ind1=0 or @ind1=1) and $controlField008-11='a' and $controlField008-14='b'">
				<xsl:attribute name="authority">
					<xsl:text>lcsh</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=100 and (@ind1=0 or @ind1=1) and $controlField008-11='k'">
				<xsl:attribute name="authority">
					<xsl:text>lacnaf</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=100 and @ind1=3 and $controlField008-11='a' and $controlField008-14='b'">
				<xsl:attribute name="authority">
					<xsl:text>lcsh</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=100 and @ind1=3 and $controlField008-11='k' and $controlField008-14='b'">
				<xsl:attribute name="authority">cash</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=110 and $controlField008-11='a' and $controlField008-14='a'">
				<xsl:attribute name="authority">naf</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=110 and $controlField008-11='a' and $controlField008-14='b'">
				<xsl:attribute name="authority">lcsh</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=110 and $controlField008-11='k' and $controlField008-14='a'">
				<xsl:attribute name="authority">
					<xsl:text>lacnaf</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=110 and $controlField008-11='k' and $controlField008-14='b'">
				<xsl:attribute name="authority">
					<xsl:text>cash</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="100 &lt;= ancestor-or-self::marc:datafield/@tag and ancestor-or-self::marc:datafield/@tag &lt;= 155 and $controlField008-11='b'">
				<xsl:attribute name="authority">
					<xsl:text>lcshcl</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=100 or ancestor-or-self::marc:datafield/@tag=110 or ancestor-or-self::marc:datafield/@tag=111 or ancestor-or-self::marc:datafield/@tag=130 or ancestor-or-self::marc:datafield/@tag=151) and $controlField008-11='c'">
				<xsl:attribute name="authority">
					<xsl:text>nlmnaf</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=100 or ancestor-or-self::marc:datafield/@tag=110 or ancestor-or-self::marc:datafield/@tag=111 or ancestor-or-self::marc:datafield/@tag=130 or ancestor-or-self::marc:datafield/@tag=151) and $controlField008-11='d'">
				<xsl:attribute name="authority">
					<xsl:text>nalnaf</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="100 &lt;= ancestor-or-self::marc:datafield/@tag and ancestor-or-self::marc:datafield/@tag &lt;= 155 and $controlField008-11='r'">
				<xsl:attribute name="authority">
					<xsl:text>aat</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="100 &lt;= ancestor-or-self::marc:datafield/@tag and ancestor-or-self::marc:datafield/@tag &lt;= 155 and $controlField008-11='s'">
				<xsl:attribute name="authority">sears</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="100 &lt;= ancestor-or-self::marc:datafield/@tag and ancestor-or-self::marc:datafield/@tag &lt;= 155 and $controlField008-11='v'">
				<xsl:attribute name="authority">rvm</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="100 &lt;= ancestor-or-self::marc:datafield/@tag and ancestor-or-self::marc:datafield/@tag &lt;= 155 and $controlField008-11='z'">
				<xsl:attribute name="authority">
					<xsl:value-of
						select="../marc:datafield[ancestor-or-self::marc:datafield/@tag=040]/marc:subfield[@code='f']"
					/>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=111 or ancestor-or-self::marc:datafield/@tag=130) and $controlField008-11='a' and $controlField008-14='a'">
				<xsl:attribute name="authority">
					<xsl:text>naf</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=111 or ancestor-or-self::marc:datafield/@tag=130) and $controlField008-11='a' and $controlField008-14='b'">
				<xsl:attribute name="authority">
					<xsl:text>lcsh</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=111 or ancestor-or-self::marc:datafield/@tag=130) and $controlField008-11='k' ">
				<xsl:attribute name="authority">
					<xsl:text>lacnaf</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=148 or ancestor-or-self::marc:datafield/@tag=150  or ancestor-or-self::marc:datafield/@tag=155) and $controlField008-11='a' ">
				<xsl:attribute name="authority">
					<xsl:text>lcsh</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=148 or ancestor-or-self::marc:datafield/@tag=150  or ancestor-or-self::marc:datafield/@tag=155) and $controlField008-11='a' ">
				<xsl:attribute name="authority">
					<xsl:text>lcsh</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=148 or ancestor-or-self::marc:datafield/@tag=150  or ancestor-or-self::marc:datafield/@tag=155) and $controlField008-11='c' ">
				<xsl:attribute name="authority">
					<xsl:text>mesh</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=148 or ancestor-or-self::marc:datafield/@tag=150  or ancestor-or-self::marc:datafield/@tag=155) and $controlField008-11='d' ">
				<xsl:attribute name="authority">
					<xsl:text>nal</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=148 or ancestor-or-self::marc:datafield/@tag=150  or ancestor-or-self::marc:datafield/@tag=155) and $controlField008-11='k' ">
				<xsl:attribute name="authority">
					<xsl:text>cash</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=151 and $controlField008-11='a' and $controlField008-14='a'">
				<xsl:attribute name="authority">
					<xsl:text>naf</xsl:text>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=151 and $controlField008-11='a' and $controlField008-14='b'">
				<xsl:attribute name="authority">lcsh</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=151 and $controlField008-11='k' and $controlField008-14='a'">
				<xsl:attribute name="authority">lacnaf</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=151 and $controlField008-11='k' and $controlField008-14='b'">
				<xsl:attribute name="authority">cash</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(..//ancestor-or-self::marc:datafield/@tag=180 or ..//ancestor-or-self::marc:datafield/@tag=181 or ..//ancestor-or-self::marc:datafield/@tag=182 or ..//ancestor-or-self::marc:datafield/@tag=185) and $controlField008-11='a'">
				<xsl:attribute name="authority">lcsh</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=700 and (@ind1='0' or @ind1='1') and @ind2='0'">
				<xsl:attribute name="authority">naf</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="ancestor-or-self::marc:datafield/@tag=700 and (@ind1='0' or @ind1='1') and @ind2='5'">
				<xsl:attribute name="authority">lacnaf</xsl:attribute>
			</xsl:when>
			<xsl:when test="ancestor-or-self::marc:datafield/@tag=700 and @ind1='3' and @ind2='0'">
				<xsl:attribute name="authority">lcsh</xsl:attribute>
			</xsl:when>
			<xsl:when test="ancestor-or-self::marc:datafield/@tag=700 and @ind1='3' and @ind2='5'">
				<xsl:attribute name="authority">cash</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(700 &lt;= ancestor-or-self::marc:datafield/@tag and ancestor-or-self::marc:datafield/@tag &lt;= 755 ) and @ind2='1'">
				<xsl:attribute name="authority">lcshcl</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=700 or ancestor-or-self::marc:datafield/@tag=710 or ancestor-or-self::marc:datafield/@tag=711 or ancestor-or-self::marc:datafield/@tag=730 or ancestor-or-self::marc:datafield/@tag=751)  and @ind2='2'">
				<xsl:attribute name="authority">nlmnaf</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=700 or ancestor-or-self::marc:datafield/@tag=710 or ancestor-or-self::marc:datafield/@tag=711 or ancestor-or-self::marc:datafield/@tag=730 or ancestor-or-self::marc:datafield/@tag=751)  and @ind2='3'">
				<xsl:attribute name="authority">nalnaf</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(700 &lt;= ancestor-or-self::marc:datafield/@tag and ancestor-or-self::marc:datafield/@tag &lt;= 755 ) and @ind2='6'">
				<xsl:attribute name="authority">rvm</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(700 &lt;= ancestor-or-self::marc:datafield/@tag and ancestor-or-self::marc:datafield/@tag &lt;= 755 ) and @ind2='7'">
				<xsl:attribute name="authority">
					<xsl:value-of select="marc:subfield[@code='2']"/>
				</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=710 or ancestor-or-self::marc:datafield/@tag=711 or ancestor-or-self::marc:datafield/@tag=730 or ancestor-or-self::marc:datafield/@tag=751)  and @ind2='5'">
				<xsl:attribute name="authority">lacnaf</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=710 or ancestor-or-self::marc:datafield/@tag=711 or ancestor-or-self::marc:datafield/@tag=730 or ancestor-or-self::marc:datafield/@tag=751)  and @ind2='0'">
				<xsl:attribute name="authority">naf</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=748 or ancestor-or-self::marc:datafield/@tag=750 or ancestor-or-self::marc:datafield/@tag=755)  and @ind2='0'">
				<xsl:attribute name="authority">lcsh</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=748 or ancestor-or-self::marc:datafield/@tag=750 or ancestor-or-self::marc:datafield/@tag=755)  and @ind2='2'">
				<xsl:attribute name="authority">mesh</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=748 or ancestor-or-self::marc:datafield/@tag=750 or ancestor-or-self::marc:datafield/@tag=755)  and @ind2='3'">
				<xsl:attribute name="authority">nal</xsl:attribute>
			</xsl:when>
			<xsl:when
				test="(ancestor-or-self::marc:datafield/@tag=748 or ancestor-or-self::marc:datafield/@tag=750 or ancestor-or-self::marc:datafield/@tag=755)  and @ind2='5'">
				<xsl:attribute name="authority">cash</xsl:attribute>
			</xsl:when>
		</xsl:choose>
	</xsl:template>
	<xsl:template match="*"/>
</xsl:stylesheet>$XSLT$);


SELECT evergreen.upgrade_deps_block_check('1069', :eg_version); --gmcharlt/kmlussier

-- subset of types listed in https://www.loc.gov/marc/authority/ad1xx3xx.html
-- for now, ignoring subdivisions
CREATE TYPE authority.heading_type AS ENUM (
    'personal_name',
    'corporate_name',
    'meeting_name',
    'uniform_title',
    'named_event',
    'chronological_term',
    'topical_term',
    'geographic_name',
    'genre_form_term',
    'medium_of_performance_term'
);

CREATE TYPE authority.variant_heading_type AS ENUM (
    'abbreviation',
    'acronym',
    'translation',
    'expansion',
    'other',
    'hidden'
);

CREATE TYPE authority.related_heading_type AS ENUM (
    'earlier',
    'later',
    'parent organization',
    'broader',
    'narrower',
    'equivalent',
    'other'
);

CREATE TYPE authority.heading_purpose AS ENUM (
    'main',
    'variant',
    'related'
);

CREATE TABLE authority.heading_field (
    id              SERIAL                      PRIMARY KEY,
    heading_type    authority.heading_type      NOT NULL,
    heading_purpose authority.heading_purpose   NOT NULL,
    label           TEXT                        NOT NULL,
    format          TEXT                        NOT NULL REFERENCES config.xml_transform (name) DEFAULT 'mads21',
    heading_xpath   TEXT                        NOT NULL,
    component_xpath TEXT                        NOT NULL,
    type_xpath      TEXT                        NULL, -- to extract related or variant type
    thesaurus_xpath TEXT                        NULL,
    thesaurus_override_xpath TEXT               NULL,
    joiner          TEXT                        NULL
);

CREATE TABLE authority.heading_field_norm_map (
        id      SERIAL  PRIMARY KEY,
        field   INT     NOT NULL REFERENCES authority.heading_field (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
        norm    INT     NOT NULL REFERENCES config.index_normalizer (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
        params  TEXT,
        pos     INT     NOT NULL DEFAULT 0
);

INSERT INTO authority.heading_field(heading_type, heading_purpose, label, heading_xpath, component_xpath, type_xpath, thesaurus_xpath, thesaurus_override_xpath) VALUES
 ( 'topical_term', 'main',    'Main Topical Term',    '/mads21:mads/mads21:authority', '//mads21:topic', NULL, '/mads21:mads/mads21:authority/mads21:topic[1]/@authority', NULL )
,( 'topical_term', 'variant', 'Variant Topical Term', '/mads21:mads/mads21:variant',   '//mads21:topic', '/mads21:variant/@type', '/mads21:mads/mads21:authority/mads21:topic[1]/@authority', '//mads21:topic[1]/@authority')
,( 'topical_term', 'related', 'Related Topical Term', '/mads21:mads/mads21:related',   '//mads21:topic', '/mads21:related/@type', '/mads21:mads/mads21:authority/mads21:topic[1]/@authority', '//mads21:topic[1]/@authority')
,( 'personal_name', 'main', 'Main Personal Name',     '/mads21:mads/mads21:authority', '//mads21:name[@type="personal"]', NULL, NULL, NULL )
,( 'personal_name', 'variant', 'Variant Personal Name',     '/mads21:mads/mads21:variant', '//mads21:name[@type="personal"]', NULL, NULL, NULL )
,( 'personal_name', 'related', 'Related Personal Name',     '/mads21:mads/mads21:related', '//mads21:name[@type="personal"]', '/mads21:related/@type', NULL, NULL )
,( 'corporate_name', 'main', 'Main Corporate name',     '/mads21:mads/mads21:authority', '//mads21:name[@type="corporate"]', NULL, NULL, NULL )
,( 'corporate_name', 'variant', 'Variant Corporate Name',     '/mads21:mads/mads21:variant', '//mads21:name[@type="corporate"]', NULL, NULL, NULL )
,( 'corporate_name', 'related', 'Related Corporate Name',     '/mads21:mads/mads21:related', '//mads21:name[@type="corporate"]', '/mads21:related/@type', NULL, NULL )
,( 'meeting_name', 'main', 'Main Meeting name',     '/mads21:mads/mads21:authority', '//mads21:name[@type="conference"]', NULL, NULL, NULL )
,( 'meeting_name', 'variant', 'Variant Meeting Name',     '/mads21:mads/mads21:variant', '//mads21:name[@type="conference"]', NULL, NULL, NULL )
,( 'meeting_name', 'related', 'Related Meeting Name',     '/mads21:mads/mads21:related', '//mads21:name[@type="meeting"]', '/mads21:related/@type', NULL, NULL )
,( 'geographic_name', 'main',    'Main Geographic Term',    '/mads21:mads/mads21:authority', '//mads21:geographic', NULL, '/mads21:mads/mads21:authority/mads21:geographic[1]/@authority', NULL )
,( 'geographic_name', 'variant', 'Variant Geographic Term', '/mads21:mads/mads21:variant',   '//mads21:geographic', '/mads21:variant/@type', '/mads21:mads/mads21:authority/mads21:geographic[1]/@authority', '//mads21:geographic[1]/@authority')
,( 'geographic_name', 'related', 'Related Geographic Term', '/mads21:mads/mads21:related',   '//mads21:geographic', '/mads21:related/@type', '/mads21:mads/mads21:authority/mads21:geographic[1]/@authority', '//mads21:geographic[1]/@authority')
,( 'genre_form_term', 'main',    'Main Genre/Form Term',    '/mads21:mads/mads21:authority', '//mads21:genre', NULL, '/mads21:mads/mads21:authority/mads21:genre[1]/@authority', NULL )
,( 'genre_form_term', 'variant', 'Variant Genre/Form Term', '/mads21:mads/mads21:variant',   '//mads21:genre', '/mads21:variant/@type', '/mads21:mads/mads21:authority/mads21:genre[1]/@authority', '//mads21:genre[1]/@authority')
,( 'genre_form_term', 'related', 'Related Genre/Form Term', '/mads21:mads/mads21:related',   '//mads21:genre', '/mads21:related/@type', '/mads21:mads/mads21:authority/mads21:genre[1]/@authority', '//mads21:genre[1]/@authority')
,( 'chronological_term', 'main',    'Main Chronological Term',    '/mads21:mads/mads21:authority', '//mads21:temporal', NULL, '/mads21:mads/mads21:authority/mads21:temporal[1]/@authority', NULL )
,( 'chronological_term', 'variant', 'Variant Chronological Term', '/mads21:mads/mads21:variant',   '//mads21:temporal', '/mads21:variant/@type', '/mads21:mads/mads21:authority/mads21:temporal[1]/@authority', '//mads21:temporal[1]/@authority')
,( 'chronological_term', 'related', 'Related Chronological Term', '/mads21:mads/mads21:related',   '//mads21:temporal', '/mads21:related/@type', '/mads21:mads/mads21:authority/mads21:temporal[1]/@authority', '//mads21:temporal[1]/@authority')
,( 'uniform_title', 'main',    'Main Uniform Title',    '/mads21:mads/mads21:authority', '//mads21:title', NULL, '/mads21:mads/mads21:authority/mads21:title[1]/@authority', NULL )
,( 'uniform_title', 'variant', 'Variant Uniform Title', '/mads21:mads/mads21:variant',   '//mads21:title', '/mads21:variant/@type', '/mads21:mads/mads21:authority/mads21:title[1]/@authority', '//mads21:title[1]/@authority')
,( 'uniform_title', 'related', 'Related Uniform Title', '/mads21:mads/mads21:related',   '//mads21:title', '/mads21:related/@type', '/mads21:mads/mads21:authority/mads21:title[1]/@authority', '//mads21:title[1]/@authority')
;

-- NACO normalize all the things
INSERT INTO authority.heading_field_norm_map (field, norm, pos)
SELECT id, 1, 0
FROM authority.heading_field;

CREATE TYPE authority.heading AS (
    field               INT,
    type                authority.heading_type,
    purpose             authority.heading_purpose,
    variant_type        authority.variant_heading_type,
    related_type        authority.related_heading_type,
    thesaurus           TEXT,
    heading             TEXT,
    normalized_heading  TEXT
);

CREATE OR REPLACE FUNCTION authority.extract_headings(marc TEXT, restrict INT[] DEFAULT NULL) RETURNS SETOF authority.heading AS $func$
DECLARE
    idx         authority.heading_field%ROWTYPE;
    xfrm        config.xml_transform%ROWTYPE;
    prev_xfrm   TEXT;
    transformed_xml TEXT;
    heading_node    TEXT;
    heading_node_list   TEXT[];
    component_node    TEXT;
    component_node_list   TEXT[];
    raw_text    TEXT;
    normalized_text    TEXT;
    normalizer  RECORD;
    curr_text   TEXT;
    joiner      TEXT;
    type_value  TEXT;
    base_thesaurus TEXT := NULL;
    output_row  authority.heading;
BEGIN

    -- Loop over the indexing entries
    FOR idx IN SELECT * FROM authority.heading_field WHERE restrict IS NULL OR id = ANY (restrict) ORDER BY format LOOP

        output_row.field   := idx.id;
        output_row.type    := idx.heading_type;
        output_row.purpose := idx.heading_purpose;

        joiner := COALESCE(idx.joiner, ' ');

        SELECT INTO xfrm * from config.xml_transform WHERE name = idx.format;

        -- See if we can skip the XSLT ... it's expensive
        IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
            -- Can't skip the transform
            IF xfrm.xslt <> '---' THEN
                transformed_xml := oils_xslt_process(marc, xfrm.xslt);
            ELSE
                transformed_xml := marc;
            END IF;

            prev_xfrm := xfrm.name;
        END IF;

        IF idx.thesaurus_xpath IS NOT NULL THEN
            base_thesaurus := ARRAY_TO_STRING(oils_xpath(idx.thesaurus_xpath, transformed_xml, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]), '');
        END IF;

        heading_node_list := oils_xpath( idx.heading_xpath, transformed_xml, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );

        FOR heading_node IN SELECT x FROM unnest(heading_node_list) AS x LOOP

            CONTINUE WHEN heading_node !~ E'^\\s*<';

            output_row.variant_type := NULL;
            output_row.related_type := NULL;
            output_row.thesaurus    := NULL;
            output_row.heading      := NULL;

            IF idx.heading_purpose = 'variant' AND idx.type_xpath IS NOT NULL THEN
                type_value := ARRAY_TO_STRING(oils_xpath(idx.type_xpath, heading_node, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]), '');
                BEGIN
                    output_row.variant_type := type_value;
                EXCEPTION WHEN invalid_text_representation THEN
                    RAISE NOTICE 'Do not recognize variant heading type %', type_value;
                END;
            END IF;
            IF idx.heading_purpose = 'related' AND idx.type_xpath IS NOT NULL THEN
                type_value := ARRAY_TO_STRING(oils_xpath(idx.type_xpath, heading_node, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]), '');
                BEGIN
                    output_row.related_type := type_value;
                EXCEPTION WHEN invalid_text_representation THEN
                    RAISE NOTICE 'Do not recognize related heading type %', type_value;
                END;
            END IF;
 
            IF idx.thesaurus_override_xpath IS NOT NULL THEN
                output_row.thesaurus := ARRAY_TO_STRING(oils_xpath(idx.thesaurus_override_xpath, heading_node, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]), '');
            END IF;
            IF output_row.thesaurus IS NULL THEN
                output_row.thesaurus := base_thesaurus;
            END IF;

            raw_text := NULL;

            -- now iterate over components of heading
            component_node_list := oils_xpath( idx.component_xpath, heading_node, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );
            FOR component_node IN SELECT x FROM unnest(component_node_list) AS x LOOP
            -- XXX much of this should be moved into oils_xpath_string...
                curr_text := ARRAY_TO_STRING(evergreen.array_remove_item_by_value(evergreen.array_remove_item_by_value(
                    oils_xpath( '//text()', -- get the content of all the nodes within the main selected node
                        REGEXP_REPLACE( component_node, E'\\s+', ' ', 'g' ) -- Translate adjacent whitespace to a single space
                    ), ' '), ''),  -- throw away morally empty (bankrupt?) strings
                    joiner
                );

                CONTINUE WHEN curr_text IS NULL OR curr_text = '';

                IF raw_text IS NOT NULL THEN
                    raw_text := raw_text || joiner;
                END IF;

                raw_text := COALESCE(raw_text,'') || curr_text;
            END LOOP;

            IF raw_text IS NOT NULL THEN
                output_row.heading := raw_text;
                normalized_text := raw_text;

                FOR normalizer IN
                    SELECT  n.func AS func,
                            n.param_count AS param_count,
                            m.params AS params
                    FROM  config.index_normalizer n
                            JOIN authority.heading_field_norm_map m ON (m.norm = n.id)
                    WHERE m.field = idx.id
                    ORDER BY m.pos LOOP
            
                        EXECUTE 'SELECT ' || normalizer.func || '(' ||
                            quote_literal( normalized_text ) ||
                            CASE
                                WHEN normalizer.param_count > 0
                                    THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                                    ELSE ''
                                END ||
                            ')' INTO normalized_text;
            
                END LOOP;
            
                output_row.normalized_heading := normalized_text;
            
                RETURN NEXT output_row;
            END IF;
        END LOOP;

    END LOOP;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION authority.extract_headings(rid BIGINT, restrict INT[] DEFAULT NULL) RETURNS SETOF authority.heading AS $func$
DECLARE
    auth        authority.record_entry%ROWTYPE;
    output_row  authority.heading;
BEGIN
    -- Get the record
    SELECT INTO auth * FROM authority.record_entry WHERE id = rid;

    RETURN QUERY SELECT * FROM authority.extract_headings(auth.marc, restrict);
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION authority.simple_heading_set( marcxml TEXT ) RETURNS SETOF authority.simple_heading AS $func$
DECLARE
    res             authority.simple_heading%ROWTYPE;
    acsaf           authority.control_set_authority_field%ROWTYPE;
    heading_row     authority.heading%ROWTYPE;
    tag_used        TEXT;
    nfi_used        TEXT;
    sf              TEXT;
    cset            INT;
    heading_text    TEXT;
    joiner_text     TEXT;
    sort_text       TEXT;
    tmp_text        TEXT;
    tmp_xml         TEXT;
    first_sf        BOOL;
    auth_id         INT DEFAULT COALESCE(NULLIF(oils_xpath_string('//*[@tag="901"]/*[local-name()="subfield" and @code="c"]', marcxml), ''), '0')::INT; 
BEGIN

    SELECT control_set INTO cset FROM authority.record_entry WHERE id = auth_id;

    IF cset IS NULL THEN
        SELECT  control_set INTO cset
          FROM  authority.control_set_authority_field
          WHERE tag IN ( SELECT  UNNEST(XPATH('//*[starts-with(@tag,"1")]/@tag',marcxml::XML)::TEXT[]))
          LIMIT 1;
    END IF;

    res.record := auth_id;
    res.thesaurus := authority.extract_thesaurus(marcxml);

    FOR acsaf IN SELECT * FROM authority.control_set_authority_field WHERE control_set = cset LOOP
        res.atag := acsaf.id;

        IF acsaf.heading_field IS NULL THEN
            tag_used := acsaf.tag;
            nfi_used := acsaf.nfi;
            joiner_text := COALESCE(acsaf.joiner, ' ');
    
            FOR tmp_xml IN SELECT UNNEST(XPATH('//*[@tag="'||tag_used||'"]', marcxml::XML)::TEXT[]) LOOP
    
                heading_text := COALESCE(
                    oils_xpath_string('./*[contains("'||acsaf.display_sf_list||'",@code)]', tmp_xml, joiner_text),
                    ''
                );
    
                IF nfi_used IS NOT NULL THEN
    
                    sort_text := SUBSTRING(
                        heading_text FROM
                        COALESCE(
                            NULLIF(
                                REGEXP_REPLACE(
                                    oils_xpath_string('./@ind'||nfi_used, tmp_xml::TEXT),
                                    $$\D+$$,
                                    '',
                                    'g'
                                ),
                                ''
                            )::INT,
                            0
                        ) + 1
                    );
    
                ELSE
                    sort_text := heading_text;
                END IF;
    
                IF heading_text IS NOT NULL AND heading_text <> '' THEN
                    res.value := heading_text;
                    res.sort_value := public.naco_normalize(sort_text);
                    res.index_vector = to_tsvector('keyword'::regconfig, res.sort_value);
                    RETURN NEXT res;
                END IF;
    
            END LOOP;
        ELSE
            FOR heading_row IN SELECT * FROM authority.extract_headings(marcxml, ARRAY[acsaf.heading_field]) LOOP
                res.value := heading_row.heading;
                res.sort_value := heading_row.normalized_heading;
                res.index_vector = to_tsvector('keyword'::regconfig, res.sort_value);
                RETURN NEXT res;
            END LOOP;
        END IF;
    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL STABLE STRICT;

ALTER TABLE authority.control_set_authority_field ADD COLUMN heading_field INTEGER REFERENCES authority.heading_field(id);

UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '100'
AND control_set = 1
AND ahf.heading_purpose = 'main'
AND ahf.heading_type = 'personal_name';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '400'
AND control_set = 1
AND ahf.heading_purpose = 'variant'
AND ahf.heading_type = 'personal_name';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '500'
AND control_set = 1
AND ahf.heading_purpose = 'related'
AND ahf.heading_type = 'personal_name';

UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '110'
AND control_set = 1
AND ahf.heading_purpose = 'main'
AND ahf.heading_type = 'corporate_name';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '410'
AND control_set = 1
AND ahf.heading_purpose = 'variant'
AND ahf.heading_type = 'corporate_name';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '510'
AND control_set = 1
AND ahf.heading_purpose = 'related'
AND ahf.heading_type = 'corporate_name';

UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '111'
AND control_set = 1
AND ahf.heading_purpose = 'main'
AND ahf.heading_type = 'meeting_name';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '411'
AND control_set = 1
AND ahf.heading_purpose = 'variant'
AND ahf.heading_type = 'meeting_name';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '511'
AND control_set = 1
AND ahf.heading_purpose = 'related'
AND ahf.heading_type = 'meeting_name';

UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '130'
AND control_set = 1
AND ahf.heading_purpose = 'main'
AND ahf.heading_type = 'uniform_title';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '430'
AND control_set = 1
AND ahf.heading_purpose = 'variant'
AND ahf.heading_type = 'uniform_title';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '530'
AND control_set = 1
AND ahf.heading_purpose = 'related'
AND ahf.heading_type = 'uniform_title';

UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '150'
AND control_set = 1
AND ahf.heading_purpose = 'main'
AND ahf.heading_type = 'topical_term';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '450'
AND control_set = 1
AND ahf.heading_purpose = 'variant'
AND ahf.heading_type = 'topical_term';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '550'
AND control_set = 1
AND ahf.heading_purpose = 'related'
AND ahf.heading_type = 'topical_term';

UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '151'
AND control_set = 1
AND ahf.heading_purpose = 'main'
AND ahf.heading_type = 'geographic_name';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '451'
AND control_set = 1
AND ahf.heading_purpose = 'variant'
AND ahf.heading_type = 'geographic_name';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '551'
AND control_set = 1
AND ahf.heading_purpose = 'related'
AND ahf.heading_type = 'geographic_name';

UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '155'
AND control_set = 1
AND ahf.heading_purpose = 'main'
AND ahf.heading_type = 'genre_form_term';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '455'
AND control_set = 1
AND ahf.heading_purpose = 'variant'
AND ahf.heading_type = 'genre_form_term';
UPDATE authority.control_set_authority_field acsaf
SET heading_field = ahf.id
FROM authority.heading_field ahf
WHERE tag = '555'
AND control_set = 1
AND ahf.heading_purpose = 'related'
AND ahf.heading_type = 'genre_form_term';


SELECT evergreen.upgrade_deps_block_check('1070', :eg_version); --miker/gmcharlt/kmlussier

CREATE TRIGGER thes_code_tracking_trigger
    AFTER UPDATE ON authority.thesaurus
    FOR EACH ROW EXECUTE PROCEDURE oils_i18n_code_tracking('at');

ALTER TABLE authority.thesaurus ADD COLUMN short_code TEXT, ADD COLUMN uri TEXT;

DELETE FROM authority.thesaurus WHERE control_set = 1 AND code NOT IN ('n',' ','|');
UPDATE authority.thesaurus SET short_code = code;

CREATE TEMP TABLE thesauri (code text, uri text, name text, xlate hstore);
COPY thesauri (code, uri, name, xlate) FROM STDIN;
migfg	http://id.loc.gov/vocabulary/genreFormSchemes/migfg	Moving image genre-form guide	
reveal	http://id.loc.gov/vocabulary/genreFormSchemes/reveal	REVEAL: fiction indexing and genre headings	
dct	http://id.loc.gov/vocabulary/genreFormSchemes/dct	Dublin Core list of resource types	
gmgpc	http://id.loc.gov/vocabulary/genreFormSchemes/gmgpc	Thesaurus for graphic materials: TGM II, Genre and physical characteristic terms	
rbgenr	http://id.loc.gov/vocabulary/genreFormSchemes/rbgenr	Genre terms: a thesaurus for use in rare book and special collections cataloguing	
sgp	http://id.loc.gov/vocabulary/genreFormSchemes/sgp	Svenska genrebeteckningar fr periodika	"sv"=>"Svenska genrebeteckningar fr periodika"
estc	http://id.loc.gov/vocabulary/genreFormSchemes/estc	Eighteenth century short title catalogue, the cataloguing rules. New ed.	
ftamc	http://id.loc.gov/vocabulary/genreFormSchemes/ftamc	Form terms for archival and manuscripts control	
alett	http://id.loc.gov/vocabulary/genreFormSchemes/alett	An alphabetical list of English text types	
gtlm	http://id.loc.gov/vocabulary/genreFormSchemes/gtlm	Genre terms for law materials: a thesaurus	
rbprov	http://id.loc.gov/vocabulary/genreFormSchemes/rbprov	Provenance evidence: a thesaurus for use in rare book and special collections cataloging	
rbbin	http://id.loc.gov/vocabulary/genreFormSchemes/rbbin	Binding terms: a thesaurus for use in rare book and special collections cataloguing	
fbg	http://id.loc.gov/vocabulary/genreFormSchemes/fbg	Films by genre /dd>	
isbdmedia	http://id.loc.gov/vocabulary/genreFormSchemes/isbdmedia	ISBD Area 0 [media]	
marccategory	http://id.loc.gov/vocabulary/genreFormSchemes/marccategory	MARC form category term list	
gnd-music	http://id.loc.gov/vocabulary/genreFormSchemes/gnd-music	Gemeinsame Normdatei: Musikalische Ausgabeform	
proysen	http://id.loc.gov/vocabulary/genreFormSchemes/proysen	PrÃ¸ysen: emneord for PrÃ¸ysen-bibliografien	
rdacarrier	http://id.loc.gov/vocabulary/genreFormSchemes/rdacarrier	Term and code list for RDA carrier types	
gnd	http://id.loc.gov/vocabulary/genreFormSchemes/gnd	Gemeinsame Normdatei	
cjh	http://id.loc.gov/vocabulary/genreFormSchemes/cjh	Center for Jewish History thesaurus	
rbpri	http://id.loc.gov/vocabulary/genreFormSchemes/rbpri	Printing & publishing evidence: a thesaurus for use in rare book and special collections cataloging	
fgtpcm	http://id.loc.gov/vocabulary/genreFormSchemes/fgtpcm	Form/genre terms for printed cartoon material	
rbpub	http://id.loc.gov/vocabulary/genreFormSchemes/rbpub	Printing and publishing evidence: a thesaurus for use in rare book and special collections cataloging	
gmd	http://id.loc.gov/vocabulary/genreFormSchemes/gmd	Anglo-American Cataloguing Rules general material designation	
rbpap	http://id.loc.gov/vocabulary/genreFormSchemes/rbpap	Paper terms: a thesaurus for use in rare book and special collections cataloging	
rdamedia	http://id.loc.gov/vocabulary/genreFormSchemes/rdamedia	Term and code list for RDA media types	
marcsmd	http://id.loc.gov/vocabulary/genreFormSchemes/marcsmd	MARC specific material form term list	
saogf	http://id.loc.gov/vocabulary/genreFormSchemes/saogf	Svenska Ã¤mnesord - Genre/Form	"sv"=>"Svenska Ã¤mnesord - Genre/Form"
lcgft	http://id.loc.gov/vocabulary/genreFormSchemes/lcgft	Library of Congress genre/form terms for library and archival materials	
muzeukv	http://id.loc.gov/vocabulary/genreFormSchemes/muzeukv	MuzeVideo UK DVD and UMD film genre classification	
mim	http://id.loc.gov/vocabulary/genreFormSchemes/mim	Moving image materials: genre terms	
nmc	http://id.loc.gov/vocabulary/genreFormSchemes/nmc	Revised nomenclature for museum cataloging: a revised and expanded version of Robert C. Chenhall's system for classifying man-made objects	
gnd-content	http://id.loc.gov/vocabulary/genreFormSchemes/gnd-content	Gemeinsame Normdatei: Beschreibung des Inhalts	
bgtchm	http://id.loc.gov/vocabulary/genreFormSchemes/bgtchm	Basic genre terms for cultural heritage materials	
gsafd	http://id.loc.gov/vocabulary/genreFormSchemes/gsafd	Guidelines on subject access to individual works of fiction, drama, etc	
marcform	http://id.loc.gov/vocabulary/genreFormSchemes/marcform	MARC form of item term list	
marcgt	http://id.loc.gov/vocabulary/genreFormSchemes/marcgt	MARC genre terms	
barngf	http://id.loc.gov/vocabulary/genreFormSchemes/barngf	Svenska Ã¤mnesord fÃ¶r barn - Genre/Form	"sv"=>"Svenska Ã¤mnesord fÃ¶r barn - Genre/Form"
ngl	http://id.loc.gov/vocabulary/genreFormSchemes/ngl	Newspaper genre list	
rvmgf	http://id.loc.gov/vocabulary/genreFormSchemes/rvmgf	ThÃ©saurus des descripteurs de genre/forme de l'UniversitÃ© Laval	"fr"=>"ThÃ©saurus des descripteurs de genre/forme de l'UniversitÃ© Laval"
tgfbne	http://id.loc.gov/vocabulary/genreFormSchemes/tgfbne	TÃ©rminos de gÃ©nero/forma de la Biblioteca Nacional de EspaÃ±a	
nbdbgf	http://id.loc.gov/vocabulary/genreFormSchemes/nbdbgf	NBD Biblion Genres Fictie	
rbtyp	http://id.loc.gov/vocabulary/genreFormSchemes/rbtyp	Type evidence: a thesaurus for use in rare book and special collections cataloging	
radfg	http://id.loc.gov/vocabulary/genreFormSchemes/radfg	Radio form / genre terms guide	
gnd-carrier	http://id.loc.gov/vocabulary/genreFormSchemes/gnd-carrier	Gemeinsame Normdatei: DatentrÃ¤gertyp	
gatbeg	http://id.loc.gov/vocabulary/genreFormSchemes/gatbeg	Gattungsbegriffe	"de"=>"Gattungsbegriffe"
rdacontent	http://id.loc.gov/vocabulary/genreFormSchemes/rdacontent	Term and code list for RDA content types	
isbdcontent	http://id.loc.gov/vocabulary/genreFormSchemes/isbdcontent	ISBD Area 0 [content]	
nimafc	http://id.loc.gov/vocabulary/genreFormSchemes/nimafc	NIMA form codes	
amg	http://id.loc.gov/vocabulary/genreFormSchemes/amg	Audiovisual material glossary	
local	http://id.loc.gov/vocabulary/subjectSchemes/local	Locally assigned term	
taika	http://id.loc.gov/vocabulary/subjectSchemes/taika	Taideteollisuuden asiasanasto	"fi"=>"Taideteollisuuden asiasanasto"
nasat	http://id.loc.gov/vocabulary/subjectSchemes/nasat	NASA thesaurus	
rswkaf	http://id.loc.gov/vocabulary/subjectSchemes/rswkaf	Alternativform zum Hauptschlagwort	"de"=>"Alternativform zum Hauptschlagwort"
jhpk	http://id.loc.gov/vocabulary/subjectSchemes/jhpk	JÄzyk haseÅ przedmiotowych KABA	"pl"=>"JÄzyk haseÅ przedmiotowych KABA"
asrcrfcd	http://id.loc.gov/vocabulary/subjectSchemes/asrcrfcd	Australian Standard Research Classification: Research Fields, Courses and Disciplines (RFCD) classification	
bt	http://id.loc.gov/vocabulary/subjectSchemes/bt	Bioethics thesaurus	
lcstt	http://id.loc.gov/vocabulary/subjectSchemes/lcstt	List of Chinese subject terms	
netc	http://id.loc.gov/vocabulary/subjectSchemes/netc	National Emergency Training Center Thesaurus (NETC)	
aat	http://id.loc.gov/vocabulary/subjectSchemes/aat	Art & architecture thesaurus	
bet	http://id.loc.gov/vocabulary/subjectSchemes/bet	British education thesaurus	
ncjt	http://id.loc.gov/vocabulary/subjectSchemes/ncjt	National criminal justice thesaurus	
samisk	http://id.loc.gov/vocabulary/subjectSchemes/samisk	Sami bibliography	"no"=>"SÃ¡mi bibliografia = Samisk bibliografi (Norge)"
tips	http://id.loc.gov/vocabulary/subjectSchemes/tips	Tesauro ISOC de psicologÃ­a	"es"=>"Tesauro ISOC de psicologÃ­a"
ukslc	http://id.loc.gov/vocabulary/subjectSchemes/ukslc	UK Standard Library Categories	
tekord	http://id.loc.gov/vocabulary/subjectSchemes/tekord	TEK-ord : UBiTs emneordliste for arkitektur, realfag, og teknolog	"no"=>"TEK-ord : UBiTs emneordliste for arkitektur, realfag, og teknolog"
umitrist	http://id.loc.gov/vocabulary/subjectSchemes/umitrist	University of Michigan Transportation Research Institute structured thesaurus	
wgst	http://id.loc.gov/vocabulary/subjectSchemes/wgst	Washington GILS Subject Tree	
rasuqam	http://id.loc.gov/vocabulary/subjectSchemes/rasuqam	RÃ©pertoire d'autoritÃ©s-sujet de l'UQAM	"fr"=>"RÃ©pertoire d'autoritÃ©s-sujet de l'UQAM"
ntids	http://id.loc.gov/vocabulary/subjectSchemes/ntids	Norske tidsskrifter 1700-1820: emneord	"no"=>"Norske tidsskrifter 1700-1820: emneord"
kaa	http://id.loc.gov/vocabulary/subjectSchemes/kaa	Kasvatusalan asiasanasto	"fi"=>"Kasvatusalan asiasanasto"
yso	http://id.loc.gov/vocabulary/subjectSchemes/yso	YSO - Yleinen suomalainen ontologia	"fi"=>"YSO - Yleinen suomalainen ontologia"
gcipmedia	http://id.loc.gov/vocabulary/subjectSchemes/gcipmedia	GAMECIP - Computer Game Media Formats (GAMECIP (Game Metadata and Citation Project))	
inspect	http://id.loc.gov/vocabulary/subjectSchemes/inspect	INSPEC thesaurus	
ordnok	http://id.loc.gov/vocabulary/subjectSchemes/ordnok	Ordnokkelen: tesaurus for kulturminnevern	"no"=>"Ordnokkelen: tesaurus for kulturminnevern"
helecon	http://id.loc.gov/vocabulary/subjectSchemes/helecon	Asiasanasto HELECON-tietikantoihin	"fi"=>"Asiasanasto HELECON-tietikantoihin"
dltlt	http://id.loc.gov/vocabulary/subjectSchemes/dltlt	Cuddon, J. A. A dictionary of literary terms and literary theory	
csapa	http://id.loc.gov/vocabulary/subjectSchemes/csapa	"Controlled vocabulary" in Pollution abstracts	
gtt	http://id.loc.gov/vocabulary/subjectSchemes/gtt	GOO-trefwoorden thesaurus	"nl"=>"GOO-trefwoorden thesaurus"
iescs	http://id.loc.gov/vocabulary/subjectSchemes/iescs	International energy subject categories and scope	
itrt	http://id.loc.gov/vocabulary/subjectSchemes/itrt	International Thesaurus of Refugee Terminology	
sanb	http://id.loc.gov/vocabulary/subjectSchemes/sanb	South African national bibliography authority file	
blmlsh	http://id.loc.gov/vocabulary/subjectSchemes/blmlsh	British Library - Map library subject headings	
bhb	http://id.loc.gov/vocabulary/subjectSchemes/bhb	Bibliography of the Hebrew Book	
csh	http://id.loc.gov/vocabulary/subjectSchemes/csh	Kapsner, Oliver Leonard. Catholic subject headings	
fire	http://id.loc.gov/vocabulary/subjectSchemes/fire	FireTalk, IFSI thesaurus	
jlabsh	http://id.loc.gov/vocabulary/subjectSchemes/jlabsh	Basic subject headings	"ja"=>"Kihon kenmei hyÃ´mokuhyÃ´"
udc	http://id.loc.gov/vocabulary/subjectSchemes/udc	Universal decimal classification	
lcshac	http://id.loc.gov/vocabulary/subjectSchemes/lcshac	Children's subject headings in Library of Congress subject headings: supplementary vocabularies	
geonet	http://id.loc.gov/vocabulary/subjectSchemes/geonet	NGA GEOnet Names Server (GNS)	
humord	http://id.loc.gov/vocabulary/subjectSchemes/humord	HUMORD	"no"=>"HUMORD"
no-ubo-mr	http://id.loc.gov/vocabulary/subjectSchemes/no-ubo-mr	Menneskerettighets-tesaurus	"no"=>"Menneskerettighets-tesaurus"
sgce	http://id.loc.gov/vocabulary/subjectSchemes/sgce	COBISS.SI General List of subject headings (English subject headings)	"sl"=>"SploÅ¡ni geslovnik COBISS.SI"
kdm	http://id.loc.gov/vocabulary/subjectSchemes/kdm	Khung dÃª muc hÃª thÃ´ng thÃ´ng tin khoa hoc vÃ  ky thuÃ¢t quÃ´c gia	"vi"=>"Khung dÃª muc hÃª thÃ´ng thÃ´ng tin khoa hoc vÃ  ky thuÃ¢t quÃ´c gia"
thesoz	http://id.loc.gov/vocabulary/subjectSchemes/thesoz	Thesaurus for the Social Sciences	
asth	http://id.loc.gov/vocabulary/subjectSchemes/asth	Astronomy thesaurus	
muzeukc	http://id.loc.gov/vocabulary/subjectSchemes/muzeukc	MuzeMusic UK classical music classification	
norbok	http://id.loc.gov/vocabulary/subjectSchemes/norbok	Norbok: emneord i Norsk bokfortegnelse	"no"=>"Norbok: emneord i Norsk bokfortegnelse"
masa	http://id.loc.gov/vocabulary/subjectSchemes/masa	Museoalan asiasanasto	"fi"=>"Museoalan asiasanasto"
conorsi	http://id.loc.gov/vocabulary/subjectSchemes/conorsi	CONOR.SI (name authority file) (Maribor, Slovenia: Institut informacijskih znanosti (IZUM))	
eurovocen	http://id.loc.gov/vocabulary/subjectSchemes/eurovocen	Eurovoc thesaurus (English)	
kto	http://id.loc.gov/vocabulary/subjectSchemes/kto	KTO - Kielitieteen ontologia	"fi"=>"KTO - Kielitieteen ontologia"
muzvukci	http://id.loc.gov/vocabulary/subjectSchemes/muzvukci	MuzeVideo UK contributor index	
kaunokki	http://id.loc.gov/vocabulary/subjectSchemes/kaunokki	Kaunokki: kaunokirjallisuuden asiasanasto	"fi"=>"Kaunokki: kaunokirjallisuuden asiasanasto"
maotao	http://id.loc.gov/vocabulary/subjectSchemes/maotao	MAO/TAO - Ontologi fÃ¶r museibranschen och Konstindustriella ontologin	"fi"=>"MAO/TAO - Ontologi fÃ¶r museibranschen och Konstindustriella ontologin"
psychit	http://id.loc.gov/vocabulary/subjectSchemes/psychit	Thesaurus of psychological index terms.	
tlsh	http://id.loc.gov/vocabulary/subjectSchemes/tlsh	Subject heading authority list	
csalsct	http://id.loc.gov/vocabulary/subjectSchemes/csalsct	CSA life sciences collection thesaurus	
ciesiniv	http://id.loc.gov/vocabulary/subjectSchemes/ciesiniv	CIESIN indexing vocabulary	
ebfem	http://id.loc.gov/vocabulary/subjectSchemes/ebfem	Encabezamientos bilingÃ¼es de la FundaciÃ³n Educativa Ana G. Mendez	
mero	http://id.loc.gov/vocabulary/subjectSchemes/mero	MERO - Merenkulkualan ontologia	"fi"=>"MERO - Merenkulkualan ontologia"
mmm	http://id.loc.gov/vocabulary/subjectSchemes/mmm	"Subject key" in Marxism and the mass media	
pascal	http://id.loc.gov/vocabulary/subjectSchemes/pascal	PASCAL database classification scheme	"fr"=>"Base de donneÃ©s PASCAL: plan de classement"
chirosh	http://id.loc.gov/vocabulary/subjectSchemes/chirosh	Chiropractic Subject Headings	
cilla	http://id.loc.gov/vocabulary/subjectSchemes/cilla	Cilla: specialtesaurus fÃ¶r musik	"fi"=>"Cilla: specialtesaurus fÃ¶r musik"
aiatsisl	http://id.loc.gov/vocabulary/subjectSchemes/aiatsisl	AIATSIS language thesaurus	
nskps	http://id.loc.gov/vocabulary/subjectSchemes/nskps	PriruÄnik za izradu predmetnog kataloga u Nacionalnoj i sveuÄiliÅ¡noj knjiÄnici u Zagrebu	"hr"=>"PriruÄnik za izradu predmetnog kataloga u Nacionalnoj i sveuÄiliÅ¡noj knjiÄnici u Zagrebu"
lctgm	http://id.loc.gov/vocabulary/subjectSchemes/lctgm	Thesaurus for graphic materials: TGM I, Subject terms	
muso	http://id.loc.gov/vocabulary/subjectSchemes/muso	MUSO - Ontologi fÃ¶r musik	"fi"=>"MUSO - Ontologi fÃ¶r musik"
blcpss	http://id.loc.gov/vocabulary/subjectSchemes/blcpss	COMPASS subject authority system	
fast	http://id.loc.gov/vocabulary/subjectSchemes/fast	Faceted application of subject terminology	
bisacmt	http://id.loc.gov/vocabulary/subjectSchemes/bisacmt	BISAC Merchandising Themes	
lapponica	http://id.loc.gov/vocabulary/subjectSchemes/lapponica	Lapponica	"fi"=>"Lapponica"
juho	http://id.loc.gov/vocabulary/subjectSchemes/juho	JUHO - Julkishallinnon ontologia	"fi"=>"JUHO - Julkishallinnon ontologia"
idas	http://id.loc.gov/vocabulary/subjectSchemes/idas	ID-ArchivschlÃ¼ssel	"de"=>"ID-ArchivschlÃ¼ssel"
tbjvp	http://id.loc.gov/vocabulary/subjectSchemes/tbjvp	Tesauro de la Biblioteca Dr. Jorge Villalobos Padilla, S.J.	"es"=>"Tesauro de la Biblioteca Dr. Jorge Villalobos Padilla, S.J."
test	http://id.loc.gov/vocabulary/subjectSchemes/test	Thesaurus of engineering and scientific terms	
finmesh	http://id.loc.gov/vocabulary/subjectSchemes/finmesh	FinMeSH	"fi"=>"FinMeSH"
kssbar	http://id.loc.gov/vocabulary/subjectSchemes/kssbar	Klassifikationssystem for svenska bibliotek. Ãmnesordregister. Alfabetisk del	"sv"=>"Klassifikationssystem for svenska bibliotek. Ãmnesordregister. Alfabetisk del"
kupu	http://id.loc.gov/vocabulary/subjectSchemes/kupu	Maori Wordnet	"mi"=>"He puna kupu"
rpe	http://id.loc.gov/vocabulary/subjectSchemes/rpe	Rubricator on economics	"ru"=>"Rubrikator po ekonomike"
dit	http://id.loc.gov/vocabulary/subjectSchemes/dit	Defense intelligence thesaurus	
she	http://id.loc.gov/vocabulary/subjectSchemes/she	SHE: subject headings for engineering	
idszbzna	http://id.loc.gov/vocabulary/subjectSchemes/idszbzna	Thesaurus IDS Nebis Zentralbibliothek ZÃ¼rich, Nordamerika-Bibliothek	"de"=>"Thesaurus IDS Nebis Zentralbibliothek ZÃ¼rich, Nordamerika-Bibliothek"
msc	http://id.loc.gov/vocabulary/subjectSchemes/msc	Mathematical subject classification	
muzeukn	http://id.loc.gov/vocabulary/subjectSchemes/muzeukn	MuzeMusic UK non-classical music classification	
ipsp	http://id.loc.gov/vocabulary/subjectSchemes/ipsp	Defense intelligence production schedule.	
sthus	http://id.loc.gov/vocabulary/subjectSchemes/sthus	Subject Taxonomy of the History of U.S. Foreign Relations	
poliscit	http://id.loc.gov/vocabulary/subjectSchemes/poliscit	Political science thesaurus II	
qtglit	http://id.loc.gov/vocabulary/subjectSchemes/qtglit	A queer thesaurus : an international thesaurus of gay and lesbian index terms	
unbist	http://id.loc.gov/vocabulary/subjectSchemes/unbist	UNBIS thesaurus	
gcipplatform	http://id.loc.gov/vocabulary/subjectSchemes/gcipplatform	GAMECIP - Computer Game Platforms (GAMECIP (Game Metadata and Citation Project))	
puho	http://id.loc.gov/vocabulary/subjectSchemes/puho	PUHO - Puolustushallinnon ontologia	"fi"=>"PUHO - Puolustushallinnon ontologia"
thub	http://id.loc.gov/vocabulary/subjectSchemes/thub	Thesaurus de la Universitat de Barcelona	"ca"=>"Thesaurus de la Universitat de Barcelona"
ndlsh	http://id.loc.gov/vocabulary/subjectSchemes/ndlsh	National Diet Library list of subject headings	"ja"=>"Koktsu Kokkai Toshokan kenmei hyÃ´mokuhyÃ´"
czenas	http://id.loc.gov/vocabulary/subjectSchemes/czenas	CZENAS thesaurus: a list of subject terms used in the National Library of the Czech Republic	"cs"=>"Soubor vÄcnÃ½ch autorit NÃ¡rodnÃ­ knihovny ÄR"
idszbzzh	http://id.loc.gov/vocabulary/subjectSchemes/idszbzzh	Thesaurus IDS Nebis Zentralbibliothek ZÃ¼rich, Handschriftenabteilung	"de"=>"Thesaurus IDS Nebis Zentralbibliothek ZÃ¼rich, Handschriftenabteilung"
unbisn	http://id.loc.gov/vocabulary/subjectSchemes/unbisn	UNBIS name authority list (New York, NY: Dag Hammarskjld Library, United Nations; : Chadwyck-Healey)	
rswk	http://id.loc.gov/vocabulary/subjectSchemes/rswk	Regeln fÃ¼r den Schlagwortkatalog	"de"=>"Regeln fÃ¼r den Schlagwortkatalog"
larpcal	http://id.loc.gov/vocabulary/subjectSchemes/larpcal	Lista de assuntos referente ao programa de cadastramento automatizado de livros da USP	"pt"=>"Lista de assuntos referente ao programa de cadastramento automatizado de livros da USP"
biccbmc	http://id.loc.gov/vocabulary/subjectSchemes/biccbmc	BIC Children's Books Marketing Classifications	
kulo	http://id.loc.gov/vocabulary/subjectSchemes/kulo	KULO - Kulttuurien tutkimuksen ontologia	"fi"=>"KULO - Kulttuurien tutkimuksen ontologia"
popinte	http://id.loc.gov/vocabulary/subjectSchemes/popinte	POPIN thesaurus: population multilingual thesaurus	
tisa	http://id.loc.gov/vocabulary/subjectSchemes/tisa	VillagrÃ¡ Rubio, Angel. Tesauro ISOC de sociologÃ­a autores	"es"=>"VillagrÃ¡ Rubio, Angel. Tesauro ISOC de sociologÃ­a autores"
atg	http://id.loc.gov/vocabulary/subjectSchemes/atg	Agricultural thesaurus and glossary	
eflch	http://id.loc.gov/vocabulary/subjectSchemes/eflch	E4Libraries Category Headings	
maaq	http://id.loc.gov/vocabulary/subjectSchemes/maaq	MadÃ¢khil al-asmÃ¢' al-'arabÃ®yah al-qadÃ®mah	"ar"=>"MadÃ¢khil al-asmÃ¢' al-'arabÃ®yah al-qadÃ®mah"
rvmgd	http://id.loc.gov/vocabulary/subjectSchemes/rvmgd	ThÃ©saurus des descripteurs de groupes dÃ©mographiques de l'UniversitÃ© Laval	"fr"=>"ThÃ©saurus des descripteurs de groupes dÃ©mographiques de l'UniversitÃ© Laval"
csahssa	http://id.loc.gov/vocabulary/subjectSchemes/csahssa	"Controlled vocabulary" in Health and safety science abstracts	
sigle	http://id.loc.gov/vocabulary/subjectSchemes/sigle	SIGLE manual, Part 2, Subject category list	
blnpn	http://id.loc.gov/vocabulary/subjectSchemes/blnpn	British Library newspaper place names	
asrctoa	http://id.loc.gov/vocabulary/subjectSchemes/asrctoa	Australian Standard Research Classification: Type of Activity (TOA) classification	
lcdgt	http://id.loc.gov/vocabulary/subjectSchemes/lcdgt	Library of Congress demographic group term and code List	
bokbas	http://id.loc.gov/vocabulary/subjectSchemes/bokbas	Bokbasen	"no"=>"Bokbasen"
gnis	http://id.loc.gov/vocabulary/subjectSchemes/gnis	Geographic Names Information System (GNIS)	
nbiemnfag	http://id.loc.gov/vocabulary/subjectSchemes/nbiemnfag	NBIs emneordsliste for faglitteratur	"no"=>"NBIs emneordsliste for faglitteratur"
nlgaf	http://id.loc.gov/vocabulary/subjectSchemes/nlgaf	Archeio KathierÅmenÅn EpikephalidÅn	"el"=>"Archeio KathierÅmenÅn EpikephalidÅn"
bhashe	http://id.loc.gov/vocabulary/subjectSchemes/bhashe	BHA, Bibliography of the history of art, subject headings/English	
tsht	http://id.loc.gov/vocabulary/subjectSchemes/tsht	Thesaurus of subject headings for television	
scbi	http://id.loc.gov/vocabulary/subjectSchemes/scbi	Soggettario per i cataloghi delle biblioteche italiane	"it"=>"Soggettario per i cataloghi delle biblioteche italiane"
valo	http://id.loc.gov/vocabulary/subjectSchemes/valo	VALO - Fotografiska ontologin	"fi"=>"VALO - Fotografiska ontologin"
wpicsh	http://id.loc.gov/vocabulary/subjectSchemes/wpicsh	WPIC Library thesaurus of subject headings	
aktp	http://id.loc.gov/vocabulary/subjectSchemes/aktp	AlphavÄtikos Katalogos ThematikÅn PerigrapheÅn	"el"=>"AlphavÄtikos Katalogos ThematikÅn PerigrapheÅn"
stw	http://id.loc.gov/vocabulary/subjectSchemes/stw	STW Thesaurus for Economics	"de"=>"Standard-Thesaurus Wirtschaft"
mesh	http://id.loc.gov/vocabulary/subjectSchemes/mesh	Medical subject headings	
ica	http://id.loc.gov/vocabulary/subjectSchemes/ica	Index of Christian art	
emnmus	http://id.loc.gov/vocabulary/subjectSchemes/emnmus	Emneord for musikkdokument i EDB-kataloger	"no"=>"Emneord for musikkdokument i EDB-kataloger"
sao	http://id.loc.gov/vocabulary/subjectSchemes/sao	Svenska Ã¤mnesord	"sv"=>"Svenska Ã¤mnesord"
sgc	http://id.loc.gov/vocabulary/subjectSchemes/sgc	COBISS.SI General List of subject headings (Slovenian subject headings)	"sl"=>"SploÅ¡ni geslovnik COBISS.SI"
bib1814	http://id.loc.gov/vocabulary/subjectSchemes/bib1814	1814-bibliografi: emneord for 1814-bibliografi	"no"=>"1814-bibliografi: emneord for 1814-bibliografi"
bjornson	http://id.loc.gov/vocabulary/subjectSchemes/bjornson	Bjornson: emneord for Bjornsonbibliografien	"no"=>"Bjornson: emneord for Bjornsonbibliografien"
liito	http://id.loc.gov/vocabulary/subjectSchemes/liito	LIITO - Liiketoimintaontologia	"fi"=>"LIITO - Liiketoimintaontologia"
apaist	http://id.loc.gov/vocabulary/subjectSchemes/apaist	APAIS thesaurus: a list of subject terms used in the Australian Public Affairs Information Service	
itglit	http://id.loc.gov/vocabulary/subjectSchemes/itglit	International thesaurus of gay and lesbian index terms (Chicago?: Thesaurus Committee, Gay and Lesbian Task Force, American Library Association)	
ntcsd	http://id.loc.gov/vocabulary/subjectSchemes/ntcsd	"National Translations Center secondary descriptors" in National Translation Center primary subject classification and secondary descriptor	
scisshl	http://id.loc.gov/vocabulary/subjectSchemes/scisshl	SCIS subject headings	
opms	http://id.loc.gov/vocabulary/subjectSchemes/opms	OpetusministeriÃ¶n asiasanasto	"fi"=>"OpetusministeriÃ¶n asiasanasto"
ttka	http://id.loc.gov/vocabulary/subjectSchemes/ttka	Teologisen tiedekunnan kirjaston asiasanasto	"fi"=>"Teologisen tiedekunnan kirjaston asiasanasto"
watrest	http://id.loc.gov/vocabulary/subjectSchemes/watrest	Thesaurus of water resources terms: a collection of water resources and related terms for use in indexing technical information	
ysa	http://id.loc.gov/vocabulary/subjectSchemes/ysa	Yleinen suomalainen asiasanasto	"fi"=>"Yleinen suomalainen asiasanasto"
kitu	http://id.loc.gov/vocabulary/subjectSchemes/kitu	Kirjallisuudentutkimuksen asiasanasto	"fi"=>"Kirjallisuudentutkimuksen asiasanasto"
sk	http://id.loc.gov/vocabulary/subjectSchemes/sk	'Zhong guo gu ji shan ban shu zong mu' fen lei biao	"zh"=>"'Zhong guo gu ji shan ban shu zong mu' fen lei biao"
aiatsisp	http://id.loc.gov/vocabulary/subjectSchemes/aiatsisp	AIATSIS place thesaurus	
ram	http://id.loc.gov/vocabulary/subjectSchemes/ram	RAMEAU: rÃ©pertoire d'authoritÃ© de matiÃ¨res encyclopÃ©dique unifiÃ©	"fr"=>"RAMEAU: rÃ©pertoire d'authoritÃ© de matiÃ¨res encyclopÃ©dique unifiÃ©"
aedoml	http://id.loc.gov/vocabulary/subjectSchemes/aedoml	Listado de encabezamientos de materia de mÃºsica	"es"=>"Listado de encabezamientos de materia de mÃºsica"
ated	http://id.loc.gov/vocabulary/subjectSchemes/ated	Australian Thesaurus of Education Descriptors (ATED)	
cabt	http://id.loc.gov/vocabulary/subjectSchemes/cabt	CAB thesaurus (Slough [England]: Commonwealth Agricultural Bureaux)	
kassu	http://id.loc.gov/vocabulary/subjectSchemes/kassu	Kassu - Kasvien suomenkieliset nimet	"fi"=>"Kassu - Kasvien suomenkieliset nimet"
nbdbt	http://id.loc.gov/vocabulary/subjectSchemes/nbdbt	NBD Biblion Trefwoordenthesaurus	"nl"=>"NBD Biblion Trefwoordenthesaurus"
jhpb	http://id.loc.gov/vocabulary/subjectSchemes/jhpb	JÄzyk haseÅ przedmiotowych Biblioteki Narodowej	"pl"=>"JÄzyk haseÅ przedmiotowych Biblioteki Narodowej"
bidex	http://id.loc.gov/vocabulary/subjectSchemes/bidex	Bilindex: a bilingual Spanish-English subject heading list	
ccsa	http://id.loc.gov/vocabulary/subjectSchemes/ccsa	Catalogue collectif suisse des affiches	"fr"=>"Catalogue collectif suisse des affiches"
noraf	http://id.loc.gov/vocabulary/subjectSchemes/noraf	Norwegian Authority File	
kito	http://id.loc.gov/vocabulary/subjectSchemes/kito	KITO - Kirjallisuudentutkimuksen ontologia	"fi"=>"KITO - Kirjallisuudentutkimuksen ontologia"
tho	http://id.loc.gov/vocabulary/subjectSchemes/tho	Thesauros HellÄnikÅn Oron	"el"=>"Thesauros HellÄnikÅn Oron"
pmont	http://id.loc.gov/vocabulary/subjectSchemes/pmont	Powerhouse Museum Object Name Thesaurus	
ssg	http://id.loc.gov/vocabulary/subjectSchemes/ssg	SploÅ¡ni slovenski geslovnik	"sl"=>"SploÅ¡ni slovenski geslovnik"
huc	http://id.loc.gov/vocabulary/subjectSchemes/huc	U.S. Geological Survey water-supply paper 2294: hydrologic basins unit codes	
isis	http://id.loc.gov/vocabulary/subjectSchemes/isis	"Classification scheme" in Isis	
ibsen	http://id.loc.gov/vocabulary/subjectSchemes/ibsen	Ibsen: emneord for Den internasjonale Ibsen-bibliografien	"no"=>"Ibsen: emneord for Den internasjonale Ibsen-bibliografien"
lacnaf	http://id.loc.gov/vocabulary/subjectSchemes/lacnaf	Library and Archives Canada name authority file	
swemesh	http://id.loc.gov/vocabulary/subjectSchemes/swemesh	Swedish MeSH	"sv"=>"Svenska MeSH"
hamsun	http://id.loc.gov/vocabulary/subjectSchemes/hamsun	Hamsun: emneord for Hamsunbibliografien	"no"=>"Hamsun: emneord for Hamsunbibliografien"
qrma	http://id.loc.gov/vocabulary/subjectSchemes/qrma	List of Arabic subject headings	"ar"=>"QÃ¢'imat ru'Ã»s al-mawdÃ»Ã¢t al-'ArabÃ®yah"
qrmak	http://id.loc.gov/vocabulary/subjectSchemes/qrmak	QÃ¢'imat ru'Ã»s al-mawdÃ»'Ã¢t al-'ArabÃ®yah al-qiyÃ¢sÃ®yah al-maktabÃ¢t wa-marÃ¢kaz al-ma'lÃ»mÃ¢t wa-qawÃ¢id al-bayÃ¢nÃ¢t	"ar"=>"QÃ¢'imat ru'Ã»s al-mawdÃ»'Ã¢t al-'ArabÃ®yah al-qiyÃ¢sÃ®yah al-maktabÃ¢t wa-marÃ¢kaz al-ma'lÃ»mÃ¢t wa-qawÃ¢id al-bayÃ¢nÃ¢t"
ceeus	http://id.loc.gov/vocabulary/subjectSchemes/ceeus	Counties and equivalent entities of the United States its possessions, and associated areas	
taxhs	http://id.loc.gov/vocabulary/subjectSchemes/taxhs	A taxonomy or human services: a conceptual framework with standardized terminology and definitions for the field	
noram	http://id.loc.gov/vocabulary/subjectSchemes/noram	Noram: emneord for Norsk-amerikansk samling	"no"=>"Noram: emneord for Norsk-amerikansk samling"
eurovocfr	http://id.loc.gov/vocabulary/subjectSchemes/eurovocfr	Eurovoc thesaurus (French)	
jurivoc	http://id.loc.gov/vocabulary/subjectSchemes/jurivoc	JURIVOC	
agrifors	http://id.loc.gov/vocabulary/subjectSchemes/agrifors	AGRIFOREST-sanasto	"fi"=>"AGRIFOREST-sanasto"
noubojur	http://id.loc.gov/vocabulary/subjectSchemes/noubojur	Thesaurus of Law	"no"=>"Thesaurus of Law"
pha	http://id.loc.gov/vocabulary/subjectSchemes/pha	Puolostushallinnon asiasanasto	"fi"=>"Puolostushallinnon asiasanasto"
ddcrit	http://id.loc.gov/vocabulary/subjectSchemes/ddcrit	DDC retrieval and indexing terminology; posting terms with hierarchy and KWOC	
mar	http://id.loc.gov/vocabulary/subjectSchemes/mar	Merenkulun asiasanasto	"fi"=>"Merenkulun asiasanasto"
sbt	http://id.loc.gov/vocabulary/subjectSchemes/sbt	Soggettario Sistema Bibliotecario Ticinese	"it"=>"Soggettario Sistema Bibliotecario Ticinese"
nzggn	http://id.loc.gov/vocabulary/subjectSchemes/nzggn	New Zealand gazetteer of official geographic names (New Zealand Geographic Board Ngā Pou Taunaha o Aotearoa (NZGB))	
kta	http://id.loc.gov/vocabulary/subjectSchemes/kta	Kielitieteen asiasanasto	"fi"=>"Kielitieteen asiasanasto"
snt	http://id.loc.gov/vocabulary/subjectSchemes/snt	Sexual nomenclature : a thesaurus	
francis	http://id.loc.gov/vocabulary/subjectSchemes/francis	FRANCIS database classification scheme	"fr"=>"Base de donneÃ©s FRANCIS: plan de classement"
eurovocsl	http://id.loc.gov/vocabulary/subjectSchemes/eurovocsl	Eurovoc thesaurus	"sl"=>"Eurovoc thesaurus"
idszbzes	http://id.loc.gov/vocabulary/subjectSchemes/idszbzes	Thesaurus IDS Nebis Bibliothek Englisches Seminar der UniversitÃ¤t ZÃ¼rich	"de"=>"Thesaurus IDS Nebis Bibliothek Englisches Seminar der UniversitÃ¤t ZÃ¼rich"
nlmnaf	http://id.loc.gov/vocabulary/subjectSchemes/nlmnaf	National Library of Medicine name authority file	
rugeo	http://id.loc.gov/vocabulary/subjectSchemes/rugeo	Natsional'nyi normativnyi fail geograficheskikh nazvanii Rossiiskoi Federatsii	"ru"=>"Natsional'nyi normativnyi fail geograficheskikh nazvanii Rossiiskoi Federatsii"
sipri	http://id.loc.gov/vocabulary/subjectSchemes/sipri	SIPRI library thesaurus	
kkts	http://id.loc.gov/vocabulary/subjectSchemes/kkts	Katalogos KathierÅmenÅn TypÅn Syllogikou Katalogou Demosion Vivliothekon	"el"=>"Katalogos KathierÅmenÅn TypÅn Syllogikou Katalogou Demosion Vivliothekon"
tucua	http://id.loc.gov/vocabulary/subjectSchemes/tucua	Thesaurus for use in college and university archives	
pmbok	http://id.loc.gov/vocabulary/subjectSchemes/pmbok	Guide to the project management body of knowledge (PMBOK Guide)	
agrovoc	http://id.loc.gov/vocabulary/subjectSchemes/agrovoc	AGROVOC multilingual agricultural thesaurus	
nal	http://id.loc.gov/vocabulary/subjectSchemes/nal	National Agricultural Library subject headings	
lnmmbr	http://id.loc.gov/vocabulary/subjectSchemes/lnmmbr	Lietuvos nacionalines Martyno Mazvydo bibliotekos rubrikynas	"lt"=>"Lietuvos nacionalines Martyno Mazvydo bibliotekos rubrikynas"
vmj	http://id.loc.gov/vocabulary/subjectSchemes/vmj	Vedettes-matiÃ¨re jeunesse	"fr"=>"Vedettes-matiÃ¨re jeunesse"
ddcut	http://id.loc.gov/vocabulary/subjectSchemes/ddcut	Dewey Decimal Classification user terms	
eks	http://id.loc.gov/vocabulary/subjectSchemes/eks	Eduskunnan kirjaston asiasanasto	"fi"=>"Eduskunnan kirjaston asiasanasto"
wot	http://id.loc.gov/vocabulary/subjectSchemes/wot	A Women's thesaurus	
noubomn	http://id.loc.gov/vocabulary/subjectSchemes/noubomn	University of Oslo Library Thesaurus of Science	"no"=>"University of Oslo Library Thesaurus of Science"
idszbzzg	http://id.loc.gov/vocabulary/subjectSchemes/idszbzzg	Thesaurus IDS Nebis Zentralbibliothek ZÃ¼rich, Graphische Sammlung	"de"=>"Thesaurus IDS Nebis Zentralbibliothek ZÃ¼rich, Graphische Sammlung"
precis	http://id.loc.gov/vocabulary/subjectSchemes/precis	PRECIS: a manual of concept analysis and subject indexing	
cstud	http://id.loc.gov/vocabulary/subjectSchemes/cstud	Classificatieschema's Bibliotheek TU Delft	"nl"=>"Classificatieschema's Bibliotheek TU Delft"
nlgkk	http://id.loc.gov/vocabulary/subjectSchemes/nlgkk	Katalogos kathierÅmenÅn onomatÅn physikÅn prosÅpÅn	"el"=>"Katalogos kathierÅmenÅn onomatÅn physikÅn prosÅpÅn"
pmt	http://id.loc.gov/vocabulary/subjectSchemes/pmt	Project management terminology. Newtown Square, PA: Project Management Institute	
ericd	http://id.loc.gov/vocabulary/subjectSchemes/ericd	Thesaurus of ERIC descriptors	
rvm	http://id.loc.gov/vocabulary/subjectSchemes/rvm	RÃ©pertoire de vedettes-matiÃ¨re	"fr"=>"RÃ©pertoire de vedettes-matiÃ¨re"
sfit	http://id.loc.gov/vocabulary/subjectSchemes/sfit	Svenska filminstitutets tesaurus	"sv"=>"Svenska filminstitutets tesaurus"
trtsa	http://id.loc.gov/vocabulary/subjectSchemes/trtsa	Teatterin ja tanssin asiasanasto	"fi"=>"Teatterin ja tanssin asiasanasto"
ulan	http://id.loc.gov/vocabulary/subjectSchemes/ulan	Union list of artist names	
unescot	http://id.loc.gov/vocabulary/subjectSchemes/unescot	UNESCO thesaurus	"fr"=>"ThÃ©saurus de l'UNESCO","es"=>"Tesauro de la UNESCO"
koko	http://id.loc.gov/vocabulary/subjectSchemes/koko	KOKO-ontologia	"fi"=>"KOKO-ontologia"
msh	http://id.loc.gov/vocabulary/subjectSchemes/msh	Trimboli, T., and Martyn S. Marianist subject headings	
trt	http://id.loc.gov/vocabulary/subjectSchemes/trt	Transportation resource thesaurus	
agrovocf	http://id.loc.gov/vocabulary/subjectSchemes/agrovocf	AGROVOC thÃ©saurus agricole multilingue	"fr"=>"AGROVOC thÃ©saurus agricole multilingue"
aucsh	http://id.loc.gov/vocabulary/subjectSchemes/aucsh	Arabic Union Catalog Subject Headings	"ar"=>"QÃ¢'imat ru'Ã»s mawdÃ»'Ã¢t al-fahras al-'ArabÃ®yah al-mowahad"
ddcri	http://id.loc.gov/vocabulary/subjectSchemes/ddcri	Dewey Decimal Classification Relative Index	
est	http://id.loc.gov/vocabulary/subjectSchemes/est	International energy: subject thesaurus (: International Energy Agency, Energy Technology Data Exchange)	
lua	http://id.loc.gov/vocabulary/subjectSchemes/lua	Liikunnan ja urheilun asiasanasto	"fi"=>"Liikunnan ja urheilun asiasanasto"
mipfesd	http://id.loc.gov/vocabulary/subjectSchemes/mipfesd	Macrothesaurus for information processing in the field of economic and social development	
rurkp	http://id.loc.gov/vocabulary/subjectSchemes/rurkp	Predmetnye rubriki Rossiiskoi knizhnoi palaty	"ru"=>"Predmetnye rubriki Rossiiskoi knizhnoi palaty"
albt	http://id.loc.gov/vocabulary/subjectSchemes/albt	Arbetslivsbibliotekets tesaurus	"sv"=>"Arbetslivsbibliotekets tesaurus"
fmesh	http://id.loc.gov/vocabulary/subjectSchemes/fmesh	Liste systÃ©matique et liste permutÃ©e des descripteurs franÃ§ais MeSH	"fr"=>"Liste systÃ©matique et liste permutÃ©e des descripteurs franÃ§ais MeSH"
bicssc	http://id.loc.gov/vocabulary/subjectSchemes/bicssc	BIC standard subject categories	
cctf	http://id.loc.gov/vocabulary/subjectSchemes/cctf	Carto-Canadiana thÃ©saurus - FranÃ§ais	"fr"=>"Carto-Canadiana thÃ©saurus - FranÃ§ais"
reo	http://id.loc.gov/vocabulary/subjectSchemes/reo	Māori Subject Headings thesaurus	"mi"=>"Ngā Åªpoko Tukutuku"
icpsr	http://id.loc.gov/vocabulary/subjectSchemes/icpsr	ICPSR controlled vocabulary system	
kao	http://id.loc.gov/vocabulary/subjectSchemes/kao	KVINNSAM Ã¤mnesordsregister	"sv"=>"KVINNSAM Ã¤mnesordsregister"
asrcseo	http://id.loc.gov/vocabulary/subjectSchemes/asrcseo	Australian Standard Research Classification: Socio-Economic Objective (SEO) classification	
georeft	http://id.loc.gov/vocabulary/subjectSchemes/georeft	GeoRef thesaurus	
cct	http://id.loc.gov/vocabulary/subjectSchemes/cct	Chinese Classified Thesaurus	"zh"=>"Zhong guo fen lei zhu ti ci biao"
dcs	http://id.loc.gov/vocabulary/subjectSchemes/dcs	Health Sciences Descriptors	"es"=>"Descriptores en Ciencias de la Salud","pt"=>"Descritores em CiÃªncias da SaÃºde"
musa	http://id.loc.gov/vocabulary/subjectSchemes/musa	Musiikin asiasanasto: erikoissanasto	"fi"=>"Musiikin asiasanasto: erikoissanasto"
ntissc	http://id.loc.gov/vocabulary/subjectSchemes/ntissc	NTIS subject categories	
idszbz	http://id.loc.gov/vocabulary/subjectSchemes/idszbz	Thesaurus IDS Nebis Zentralbibliothek ZÃ¼rich	"de"=>"Thesaurus IDS Nebis Zentralbibliothek ZÃ¼rich"
tlka	http://id.loc.gov/vocabulary/subjectSchemes/tlka	InvestigaciÃ³, ProcÃ©s TÃ¨cnicn kirjaston asiasanasto	"fi"=>"InvestigaciÃ³, ProcÃ©s TÃ¨cnicn kirjaston asiasanasto"
usaidt	http://id.loc.gov/vocabulary/subjectSchemes/usaidt	USAID thesaurus: Keywords used to index documents included in the USAID Development Experience System.	
embne	http://id.loc.gov/vocabulary/subjectSchemes/embne	Encabezamientos de Materia de la Biblioteca Nacional de EspaÃ±a	"es"=>"Encabezamientos de Materia de la Biblioteca Nacional de EspaÃ±a"
vcaadu	http://id.loc.gov/vocabulary/subjectSchemes/vcaadu	Vocabulario controlado de arquitectura, arte, diseÃ±o y urbanismo	"es"=>"Vocabulario controlado de arquitectura, arte, diseÃ±o y urbanismo"
ntcpsc	http://id.loc.gov/vocabulary/subjectSchemes/ntcpsc	"National Translations Center primary subject classification" in National Translations Center primary subject classification and secondary descriptors	
quiding	http://id.loc.gov/vocabulary/subjectSchemes/quiding	Quiding, Nils Herman. Svenskt allmÃ¤nt fÃ¶rfattningsregister fÃ¶r tiden frÃ¥n Ã¥r 1522 till och med Ã¥r 1862	"sv"=>"Quiding, Nils Herman. Svenskt allmÃ¤nt fÃ¶rfattningsregister fÃ¶r tiden frÃ¥n Ã¥r 1522 till och med Ã¥r 1862"
allars	http://id.loc.gov/vocabulary/subjectSchemes/allars	AllÃ¤rs: allmÃ¤n tesaurus pÃ¤ svenska	"fi"=>"AllÃ¤rs: allmÃ¤n tesaurus pÃ¤ svenska"
ogst	http://id.loc.gov/vocabulary/subjectSchemes/ogst	Oregon GILS Subject Tree (Oregon: Oregon State Library and Oregon Information Resource Management Division (IRMD))	
bella	http://id.loc.gov/vocabulary/subjectSchemes/bella	Bella: specialtesaurus fÃ¶r skÃ¶nlitteratur	"fi"=>"Bella: specialtesaurus fÃ¶r skÃ¶nlitteratur"
bibalex	http://id.loc.gov/vocabulary/subjectSchemes/bibalex	Bibliotheca Alexandrina name and subject authority file	
pepp	http://id.loc.gov/vocabulary/subjectSchemes/pepp	The Princeton encyclopedia of poetry and poetics	
hkcan	http://id.loc.gov/vocabulary/subjectSchemes/hkcan	Hong Kong Chinese Authority File (Name) - HKCAN	
dissao	http://id.loc.gov/vocabulary/subjectSchemes/dissao	"Dissertation abstracts online" in Search tools: the guide to UNI/Data Courier Online	
ltcsh	http://id.loc.gov/vocabulary/subjectSchemes/ltcsh	Land Tenure Center Library list of subject headings	
mpirdes	http://id.loc.gov/vocabulary/subjectSchemes/mpirdes	Macrothesaurus para el procesamiento de la informaciÃ³n relativa al desarrollo econÃ³mico y social	"es"=>"Macrothesaurus para el procesamiento de la informaciÃ³n relativa al desarrollo econÃ³mico y social"
asft	http://id.loc.gov/vocabulary/subjectSchemes/asft	Aquatic sciences and fisheries thesaurus	
naf	http://id.loc.gov/vocabulary/subjectSchemes/naf	NACO authority file	
nimacsc	http://id.loc.gov/vocabulary/subjectSchemes/nimacsc	NIMA cartographic subject categories	
khib	http://id.loc.gov/vocabulary/subjectSchemes/khib	Emneord, KHiB Biblioteket	"no"=>"Emneord, KHiB Biblioteket"
cdcng	http://id.loc.gov/vocabulary/subjectSchemes/cdcng	Catalogage des documents cartographiques: forme et structure des vedettes noms gÃ©ographiques - NF Z 44-081	"fr"=>"Catalogage des documents cartographiques: forme et structure des vedettes noms gÃ©ographiques - NF Z 44-081"
afset	http://id.loc.gov/vocabulary/subjectSchemes/afset	American Folklore Society Ethnographic Thesaurus	
erfemn	http://id.loc.gov/vocabulary/subjectSchemes/erfemn	Erfaringskompetanses emneord	"no"=>"Erfaringskompetanses emneord"
sbiao	http://id.loc.gov/vocabulary/subjectSchemes/sbiao	Svenska barnboksinstitutets Ã¤mnesordslista	"sv"=>"Svenska barnboksinstitutets Ã¤mnesordslista"
socio	http://id.loc.gov/vocabulary/subjectSchemes/socio	Sociological Abstracts Thesaurus	
bisacrt	http://id.loc.gov/vocabulary/subjectSchemes/bisacrt	BISAC Regional Themes	
eum	http://id.loc.gov/vocabulary/subjectSchemes/eum	Eesti uldine mÃ¤rksonastik	"et"=>"Eesti uldine mÃ¤rksonastik"
kula	http://id.loc.gov/vocabulary/subjectSchemes/kula	Kulttuurien tutkimuksen asiasanasto	"fi"=>"Kulttuurien tutkimuksen asiasanasto"
odlt	http://id.loc.gov/vocabulary/subjectSchemes/odlt	Baldick, C. The Oxford dictionary of literary terms	
rerovoc	http://id.loc.gov/vocabulary/subjectSchemes/rerovoc	Indexation matiÃ©res RERO autoritÃ¨s	"fr"=>"Indexation matiÃ©res RERO autoritÃ¨s"
tsr	http://id.loc.gov/vocabulary/subjectSchemes/tsr	TSR-ontologia	"fi"=>"TSR-ontologia"
czmesh	http://id.loc.gov/vocabulary/subjectSchemes/czmesh	Czech MeSH	"cs"=>"Czech MeSH"
dltt	http://id.loc.gov/vocabulary/subjectSchemes/dltt	Quinn, E. A dictionary of literary and thematic terms	
idsbb	http://id.loc.gov/vocabulary/subjectSchemes/idsbb	Thesaurus IDS Basel Bern	"de"=>"Thesaurus IDS Basel Bern"
inist	http://id.loc.gov/vocabulary/subjectSchemes/inist	INIS: thesaurus	
idszbzzk	http://id.loc.gov/vocabulary/subjectSchemes/idszbzzk	Thesaurus IDS Nebis Zentralbibliothek ZÃ¼rich, Kartensammlung	"de"=>"Thesaurus IDS Nebis Zentralbibliothek ZÃ¼rich, Kartensammlung"
tesa	http://id.loc.gov/vocabulary/subjectSchemes/tesa	Tesauro AgrÃ­cola	"es"=>"Tesauro AgrÃ­cola"
liv	http://id.loc.gov/vocabulary/subjectSchemes/liv	Legislative indexing vocabulary	
collett	http://id.loc.gov/vocabulary/subjectSchemes/collett	Collett-bibliografi: litteratur av og om Camilla Collett	"no"=>"Collett-bibliografi: litteratur av og om Camilla Collett"
nsbncf	http://id.loc.gov/vocabulary/subjectSchemes/nsbncf	Nuovo Soggettario	"it"=>"Nuovo Soggettario"
ipat	http://id.loc.gov/vocabulary/subjectSchemes/ipat	IPA thesaurus and frequency list	
skon	http://id.loc.gov/vocabulary/subjectSchemes/skon	Att indexera skÃ¶nlitteratur: Ãmnesordslista, vuxenlitteratur	"sv"=>"Att indexera skÃ¶nlitteratur: Ãmnesordslista, vuxenlitteratur"
renib	http://id.loc.gov/vocabulary/subjectSchemes/renib	Renib	"es"=>"Renib"
hrvmesh	http://id.loc.gov/vocabulary/subjectSchemes/hrvmesh	Croatian MeSH / Hrvatski MeSH	"no"=>"Croatian MeSH / Hrvatski MeSH"
swd	http://id.loc.gov/vocabulary/subjectSchemes/swd	Schlagwortnormdatei	"de"=>"Schlagwortnormdatei"
aass	http://id.loc.gov/vocabulary/subjectSchemes/aass	"Asian American Studies Library subject headings" in A Guide for establishing Asian American core collections	
cht	http://id.loc.gov/vocabulary/subjectSchemes/cht	Chicano thesaurus for indexing Chicano materials in Chicano periodical index	
galestne	http://id.loc.gov/vocabulary/subjectSchemes/galestne	Gale Group subject thesaurus and named entity vocabulary	
nlgsh	http://id.loc.gov/vocabulary/subjectSchemes/nlgsh	Katalogos HellÄnikÅn thematikÅn epikephalidÅn	"el"=>"Katalogos HellÄnikÅn thematikÅn epikephalidÅn"
hoidokki	http://id.loc.gov/vocabulary/subjectSchemes/hoidokki	Hoitotieteellinen asiasanasto	
vffyl	http://id.loc.gov/vocabulary/subjectSchemes/vffyl	Vocabulario de la Biblioteca Central de la FFyL	"es"=>"Vocabulario de la Biblioteca Central de la FFyL"
kubikat	http://id.loc.gov/vocabulary/subjectSchemes/kubikat	kubikat	"de"=>"kubikat"
waqaf	http://id.loc.gov/vocabulary/subjectSchemes/waqaf	Maknas Uloom Al Waqaf	"ar"=>"Maknas Uloom Al Waqaf"
hapi	http://id.loc.gov/vocabulary/subjectSchemes/hapi	HAPI thesaurus and name authority, 1970-2000	
drama	http://id.loc.gov/vocabulary/subjectSchemes/drama	Drama: specialtesaurus fÃ¶r teater och dans	
sosa	http://id.loc.gov/vocabulary/subjectSchemes/sosa	Sociaalialan asiasanasto	"fi"=>"Sociaalialan asiasanasto"
ilpt	http://id.loc.gov/vocabulary/subjectSchemes/ilpt	Index to legal periodicals: thesaurus	
nicem	http://id.loc.gov/vocabulary/subjectSchemes/nicem	NICEM subject headings and classification system	
qlsp	http://id.loc.gov/vocabulary/subjectSchemes/qlsp	Queens Library Spanish language subject headings	
eet	http://id.loc.gov/vocabulary/subjectSchemes/eet	European education thesaurus	
nalnaf	http://id.loc.gov/vocabulary/subjectSchemes/nalnaf	National Agricultural Library name authority file	
eclas	http://id.loc.gov/vocabulary/subjectSchemes/eclas	ECLAS thesaurus	
agrovocs	http://id.loc.gov/vocabulary/subjectSchemes/agrovocs	AGROVOC tesauro agrÃ­cola multilingÃ©e	"es"=>"AGROVOC tesauro agrÃ­cola multilingÃ©e"
shbe	http://id.loc.gov/vocabulary/subjectSchemes/shbe	Subject headings in business and economics	"sv"=>"Subject headings in business and economics"
barn	http://id.loc.gov/vocabulary/subjectSchemes/barn	Svenska Ã¤mnesord fÃ¶r barn	"sv"=>"Svenska Ã¤mnesord fÃ¶r barn"
bhammf	http://id.loc.gov/vocabulary/subjectSchemes/bhammf	BHA, Bibliographie d'histoire de l'art, mots-matiÃ¨re/franÃ§ais	"fr"=>"BHA, Bibliographie d'histoire de l'art, mots-matiÃ¨re/franÃ§ais"
gccst	http://id.loc.gov/vocabulary/subjectSchemes/gccst	Government of Canada core subject thesaurus (Gatineau : Library and Archives Canada)	
fnhl	http://id.loc.gov/vocabulary/subjectSchemes/fnhl	First Nations House of Learning Subject Headings	
kauno	http://id.loc.gov/vocabulary/subjectSchemes/kauno	KAUNO - Kaunokki-ontologin	"fi"=>"KAUNO - Kaunokki-ontologin"
dtict	http://id.loc.gov/vocabulary/subjectSchemes/dtict	Defense Technical Information Center thesaurus	
mech	http://id.loc.gov/vocabulary/subjectSchemes/mech	Iskanje po zbirki MECH	"sl"=>"Iskanje po zbirki MECH"
jupo	http://id.loc.gov/vocabulary/subjectSchemes/jupo	JUPO - Julkisen hallinnon palveluontologia	"fi"=>"JUPO - Julkisen hallinnon palveluontologia"
ktpt	http://id.loc.gov/vocabulary/subjectSchemes/ktpt	Kirjasto- ja tietopalvelualan tesaurus	"fi"=>"Kirjasto- ja tietopalvelualan tesaurus"
aiatsiss	http://id.loc.gov/vocabulary/subjectSchemes/aiatsiss	AIATSIS subject Thesaurus	
lcac	http://id.loc.gov/vocabulary/subjectSchemes/lcac	Library of Congress Annotated Children's Cataloging Program subject headings	
lemac	http://id.loc.gov/vocabulary/subjectSchemes/lemac	Llista d'encapÃ§alaments de matÃ¨ria en catalÃ 	"ca"=>"Llista d'encapÃ§alaments de matÃ¨ria en catalÃ "
lemb	http://id.loc.gov/vocabulary/subjectSchemes/lemb	Lista de encabezamientos de materia para bibliotecas	"es"=>"Lista de encabezamientos de materia para bibliotecas"
henn	http://id.loc.gov/vocabulary/subjectSchemes/henn	Hennepin County Library cumulative authority list	
mtirdes	http://id.loc.gov/vocabulary/subjectSchemes/mtirdes	MacrothÃ©saurus pour le traitement de l'information relative au dÃ©veloppement Ã©conomique et social	"fr"=>"MacrothÃ©saurus pour le traitement de l'information relative au dÃ©veloppement Ã©conomique et social"
cash	http://id.loc.gov/vocabulary/subjectSchemes/cash	Canadian subject headings	
nznb	http://id.loc.gov/vocabulary/subjectSchemes/nznb	New Zealand national bibliographic	
prvt	http://id.loc.gov/vocabulary/subjectSchemes/prvt	Patent- och registreringsverkets tesaurus	"sv"=>"Patent- och registreringsverkets tesaurus"
scgdst	http://id.loc.gov/vocabulary/subjectSchemes/scgdst	Subject categorization guide for defense science and technology	
gem	http://id.loc.gov/vocabulary/subjectSchemes/gem	GEM controlled vocabularies	
lcsh	http://id.loc.gov/vocabulary/subjectSchemes/lcsh	Library of Congress subject headings	
rero	http://id.loc.gov/vocabulary/subjectSchemes/rero	Indexation matires RERO	"fr"=>"Indexation matires RERO"
peri	http://id.loc.gov/vocabulary/subjectSchemes/peri	Perinnetieteiden asiasanasto	"fi"=>"Perinnetieteiden asiasanasto"
shsples	http://id.loc.gov/vocabulary/subjectSchemes/shsples	Encabezamientos de materia para bibliotecas escolares y pÃºblicas	"es"=>"Encabezamientos de materia para bibliotecas escolares y pÃºblicas"
slem	http://id.loc.gov/vocabulary/subjectSchemes/slem	Sears: lista de encabezamientos de materia	"es"=>"Sears: lista de encabezamientos de materia"
afo	http://id.loc.gov/vocabulary/subjectSchemes/afo	AFO - Viikin kampuskirjaston ontologia	"fi"=>"AFO - Viikin kampuskirjaston ontologia"
gst	http://id.loc.gov/vocabulary/subjectSchemes/gst	Gay studies thesaurus: a controlled vocabulary for indexing and accessing materials of relevance to gay culture, history, politics and psychology	
hlasstg	http://id.loc.gov/vocabulary/subjectSchemes/hlasstg	HLAS subject term glossary	
iest	http://id.loc.gov/vocabulary/subjectSchemes/iest	International energy: subject thesaurus	
pkk	http://id.loc.gov/vocabulary/subjectSchemes/pkk	Predmetnik za katoliÅ¡ke knjiÅ¾nice	"sl"=>"Predmetnik za katoliÅ¡ke knjiÅ¾nice"
atla	http://id.loc.gov/vocabulary/subjectSchemes/atla	Religion indexes: thesaurus	
scot	http://id.loc.gov/vocabulary/subjectSchemes/scot	Schools Online Thesaurus (ScOT)	
smda	http://id.loc.gov/vocabulary/subjectSchemes/smda	Smithsonian National Air and Space Museum Directory of Airplanes	
solstad	http://id.loc.gov/vocabulary/subjectSchemes/solstad	Solstad: emneord for Solstadbibliografien	"no"=>"Solstad: emneord for Solstadbibliografien"
abne	http://id.loc.gov/vocabulary/subjectSchemes/abne	Autoridades de la Biblioteca Nacional de EspaÃ±a	"es"=>"Autoridades de la Biblioteca Nacional de EspaÃ±a"
spines	http://id.loc.gov/vocabulary/subjectSchemes/spines	Tesauro SPINES: un vocabulario controlado y estructurado para el tratamiento de informaciÃ³n sobre ciencia y tecnologÃ­a para el desarrollo	"es"=>"Tesauro SPINES: un vocabulario controlado y estructurado para el tratamiento de informaciÃ³n sobre ciencia y tecnologÃ­a para el desarrollo"
ktta	http://id.loc.gov/vocabulary/subjectSchemes/ktta	KÃ¤si - ja taideteollisuuden asiasanasto	"fi"=>"KÃ¤si - ja taideteollisuuden asiasanasto"
ccte	http://id.loc.gov/vocabulary/subjectSchemes/ccte	Carto-Canadiana thesaurus - English	
pmcsg	http://id.loc.gov/vocabulary/subjectSchemes/pmcsg	Combined standards glossary	
bisacsh	http://id.loc.gov/vocabulary/subjectSchemes/bisacsh	BISAC Subject Headings	
fssh	http://id.loc.gov/vocabulary/subjectSchemes/fssh	FamilySearch Subject Headings (FamilySearch)	
tasmas	http://id.loc.gov/vocabulary/subjectSchemes/tasmas	Tesaurus de Asuntos Sociales del Ministerio de Asuntos Sociales de EspaÃ±a	"es"=>"Tesaurus de Asuntos Sociales del Ministerio de Asuntos Sociales de EspaÃ±a"
tero	http://id.loc.gov/vocabulary/subjectSchemes/tero	TERO - Terveyden ja hyvinvoinnin ontologia	"fi"=>"TERO - Terveyden ja hyvinvoinnin ontologia"
rma	http://id.loc.gov/vocabulary/subjectSchemes/rma	Ru'us al-mawdu'at al-'Arabiyah	"ar"=>"Ru'us al-mawdu'at al-'Arabiyah"
tgn	http://id.loc.gov/vocabulary/subjectSchemes/tgn	Getty thesaurus of geographic names	
tha	http://id.loc.gov/vocabulary/subjectSchemes/tha	Barcala de Moyano, Graciela G., Cristina Voena. Tesauro de Historia Argentina	"es"=>"Barcala de Moyano, Graciela G., Cristina Voena. Tesauro de Historia Argentina"
ttll	http://id.loc.gov/vocabulary/subjectSchemes/ttll	Roggau, Zunilda. Tell. Tesauro de lengua y literatura	"es"=>"Roggau, Zunilda. Tell. Tesauro de lengua y literatura"
sears	http://id.loc.gov/vocabulary/subjectSchemes/sears	Sears list of subject headings	
csht	http://id.loc.gov/vocabulary/subjectSchemes/csht	Chinese subject headings	
\.

-- ' ...blah

INSERT INTO authority.thesaurus (code, uri, name, control_set)
  SELECT code, uri, name, 1 FROM thesauri;

UPDATE authority.thesaurus SET short_code = 'a' WHERE code = 'lcsh';
UPDATE authority.thesaurus SET short_code = 'b' WHERE code = 'lcshac';
UPDATE authority.thesaurus SET short_code = 'c' WHERE code = 'mesh';
UPDATE authority.thesaurus SET short_code = 'd' WHERE code = 'nal';
UPDATE authority.thesaurus SET short_code = 'k' WHERE code = 'cash';
UPDATE authority.thesaurus SET short_code = 'r' WHERE code = 'aat';
UPDATE authority.thesaurus SET short_code = 's' WHERE code = 'sears';
UPDATE authority.thesaurus SET short_code = 'v' WHERE code = 'rvm';

UPDATE  authority.thesaurus
  SET   short_code = 'z'
  WHERE short_code IS NULL
        AND control_set = 1;

INSERT INTO config.i18n_core (fq_field, identity_value, translation, string )
  SELECT  'at.name', t.code, xlate->key, xlate->value
    FROM  thesauri t
          JOIN LATERAL each(t.xlate) AS xlate ON TRUE
    WHERE NOT EXISTS
            (SELECT id
              FROM  config.i18n_core
              WHERE fq_field = 'at.name'
                    AND identity_value = t.code
                    AND translation = xlate->key)
          AND t.xlate IS NOT NULL
          AND t.name <> (xlate->value);

CREATE OR REPLACE FUNCTION authority.extract_thesaurus( marcxml TEXT ) RETURNS TEXT AS $func$
DECLARE
    thes_code TEXT;
BEGIN
    thes_code := vandelay.marc21_extract_fixed_field(marcxml,'Subj');
    IF thes_code IS NULL THEN
        thes_code := '|';
    ELSIF thes_code = 'z' THEN
        thes_code := COALESCE( oils_xpath_string('//*[@tag="040"]/*[@code="f"][1]', marcxml), 'z' );
    ELSE
        SELECT code INTO thes_code FROM authority.thesaurus WHERE short_code = thes_code;
        IF NOT FOUND THEN
            thes_code := '|'; -- default
        END IF;
    END IF;
    RETURN thes_code;
END;
$func$ LANGUAGE PLPGSQL STABLE STRICT;

CREATE OR REPLACE FUNCTION authority.map_thesaurus_to_control_set () RETURNS TRIGGER AS $func$
BEGIN
    IF NEW.control_set IS NULL THEN
        SELECT control_set INTO NEW.control_set
        FROM authority.thesaurus
        WHERE code = authority.extract_thesaurus(NEW.marc);
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION authority.reingest_authority_rec_descriptor( auth_id BIGINT ) RETURNS VOID AS $func$
BEGIN
    DELETE FROM authority.rec_descriptor WHERE record = auth_id;
    INSERT INTO authority.rec_descriptor (record, record_status, encoding_level, thesaurus)
        SELECT  auth_id,
                vandelay.marc21_extract_fixed_field(marc,'RecStat'),
                vandelay.marc21_extract_fixed_field(marc,'ELvl'),
                authority.extract_thesaurus(marc)
          FROM  authority.record_entry
          WHERE id = auth_id;
    RETURN;
END;
$func$ LANGUAGE PLPGSQL;



SELECT evergreen.upgrade_deps_block_check('1071', :eg_version); --gmcharlt/kmlussier

CREATE OR REPLACE FUNCTION metabib.staged_browse(query text, fields integer[], context_org integer, context_locations integer[], staff boolean, browse_superpage_size integer, count_up_from_zero boolean, result_limit integer, next_pivot_pos integer)
 RETURNS SETOF metabib.flat_browse_entry_appearance
AS $f$
DECLARE
    curs                    REFCURSOR;
    rec                     RECORD;
    qpfts_query             TEXT;
    aqpfts_query            TEXT;
    afields                 INT[];
    bfields                 INT[];
    result_row              metabib.flat_browse_entry_appearance%ROWTYPE;
    results_skipped         INT := 0;
    row_counter             INT := 0;
    row_number              INT;
    slice_start             INT;
    slice_end               INT;
    full_end                INT;
    all_records             BIGINT[];
    all_brecords             BIGINT[];
    all_arecords            BIGINT[];
    superpage_of_records    BIGINT[];
    superpage_size          INT;
    c_tests                 TEXT := '';
    b_tests                 TEXT := '';
    c_orgs                  INT[];
    unauthorized_entry      RECORD;
BEGIN
    IF count_up_from_zero THEN
        row_number := 0;
    ELSE
        row_number := -1;
    END IF;

    IF NOT staff THEN
        SELECT x.c_attrs, x.b_attrs INTO c_tests, b_tests FROM asset.patron_default_visibility_mask() x;
    END IF;

    IF c_tests <> '' THEN c_tests := c_tests || '&'; END IF;
    IF b_tests <> '' THEN b_tests := b_tests || '&'; END IF;

    SELECT ARRAY_AGG(id) INTO c_orgs FROM actor.org_unit_descendants(context_org);

    c_tests := c_tests || search.calculate_visibility_attribute_test('circ_lib',c_orgs)
               || '&' || search.calculate_visibility_attribute_test('owning_lib',c_orgs);

    PERFORM 1 FROM config.internal_flag WHERE enabled AND name = 'opac.located_uri.act_as_copy';
    IF FOUND THEN
        b_tests := b_tests || search.calculate_visibility_attribute_test(
            'luri_org',
            (SELECT ARRAY_AGG(id) FROM actor.org_unit_full_path(context_org) x)
        );
    ELSE
        b_tests := b_tests || search.calculate_visibility_attribute_test(
            'luri_org',
            (SELECT ARRAY_AGG(id) FROM actor.org_unit_ancestors(context_org) x)
        );
    END IF;

    IF context_locations THEN
        IF c_tests <> '' THEN c_tests := c_tests || '&'; END IF;
        c_tests := c_tests || search.calculate_visibility_attribute_test('location',context_locations);
    END IF;

    OPEN curs NO SCROLL FOR EXECUTE query;

    LOOP
        FETCH curs INTO rec;
        IF NOT FOUND THEN
            IF result_row.pivot_point IS NOT NULL THEN
                RETURN NEXT result_row;
            END IF;
            RETURN;
        END IF;

        --Is unauthorized?
        SELECT INTO unauthorized_entry *
        FROM metabib.browse_entry_simple_heading_map mbeshm
        INNER JOIN authority.simple_heading ash ON ( mbeshm.simple_heading = ash.id )
        INNER JOIN authority.control_set_authority_field acsaf ON ( acsaf.id = ash.atag )
        JOIN authority.heading_field ahf ON (ahf.id = acsaf.heading_field)
        WHERE mbeshm.entry = rec.id
        AND   ahf.heading_purpose = 'variant';

        -- Gather aggregate data based on the MBE row we're looking at now, authority axis
        IF (unauthorized_entry.record IS NOT NULL) THEN
            --unauthorized term belongs to an auth linked to a bib?
            SELECT INTO all_arecords, result_row.sees, afields
                    ARRAY_AGG(DISTINCT abl.bib),
                    STRING_AGG(DISTINCT abl.authority::TEXT, $$,$$),
                    ARRAY_AGG(DISTINCT map.metabib_field)
            FROM authority.bib_linking abl
            INNER JOIN authority.control_set_auth_field_metabib_field_map_refs map ON (
                    map.authority_field = unauthorized_entry.atag
                    AND map.metabib_field = ANY(fields)
            )
            WHERE abl.authority = unauthorized_entry.record;
        ELSE
            --do usual procedure
            SELECT INTO all_arecords, result_row.sees, afields
                    ARRAY_AGG(DISTINCT abl.bib), -- bibs to check for visibility
                    STRING_AGG(DISTINCT aal.source::TEXT, $$,$$), -- authority record ids
                    ARRAY_AGG(DISTINCT map.metabib_field) -- authority-tag-linked CMF rows

            FROM  metabib.browse_entry_simple_heading_map mbeshm
                    JOIN authority.simple_heading ash ON ( mbeshm.simple_heading = ash.id )
                    JOIN authority.authority_linking aal ON ( ash.record = aal.source )
                    JOIN authority.bib_linking abl ON ( aal.target = abl.authority )
                    JOIN authority.control_set_auth_field_metabib_field_map_refs map ON (
                        ash.atag = map.authority_field
                        AND map.metabib_field = ANY(fields)
                    )
                    JOIN authority.control_set_authority_field acsaf ON (
                        map.authority_field = acsaf.id
                    )
                    JOIN authority.heading_field ahf ON (ahf.id = acsaf.heading_field)
              WHERE mbeshm.entry = rec.id
              AND   ahf.heading_purpose = 'variant';

        END IF;

        -- Gather aggregate data based on the MBE row we're looking at now, bib axis
        SELECT INTO all_brecords, result_row.authorities, bfields
                ARRAY_AGG(DISTINCT source),
                STRING_AGG(DISTINCT authority::TEXT, $$,$$),
                ARRAY_AGG(DISTINCT def)
          FROM  metabib.browse_entry_def_map
          WHERE entry = rec.id
                AND def = ANY(fields);

        SELECT INTO result_row.fields STRING_AGG(DISTINCT x::TEXT, $$,$$) FROM UNNEST(afields || bfields) x;

        result_row.sources := 0;
        result_row.asources := 0;

        -- Bib-linked vis checking
        IF ARRAY_UPPER(all_brecords,1) IS NOT NULL THEN

            SELECT  INTO result_row.sources COUNT(DISTINCT b.id)
              FROM  biblio.record_entry b
                    JOIN asset.copy_vis_attr_cache acvac ON (acvac.record = b.id)
              WHERE b.id = ANY(all_brecords[1:browse_superpage_size])
                    AND (
                        acvac.vis_attr_vector @@ c_tests::query_int
                        OR b.vis_attr_vector @@ b_tests::query_int
                    );

            result_row.accurate := TRUE;

        END IF;

        -- Authority-linked vis checking
        IF ARRAY_UPPER(all_arecords,1) IS NOT NULL THEN

            SELECT  INTO result_row.asources COUNT(DISTINCT b.id)
              FROM  biblio.record_entry b
                    JOIN asset.copy_vis_attr_cache acvac ON (acvac.record = b.id)
              WHERE b.id = ANY(all_arecords[1:browse_superpage_size])
                    AND (
                        acvac.vis_attr_vector @@ c_tests::query_int
                        OR b.vis_attr_vector @@ b_tests::query_int
                    );

            result_row.aaccurate := TRUE;

        END IF;

        IF result_row.sources > 0 OR result_row.asources > 0 THEN

            -- The function that calls this function needs row_number in order
            -- to correctly order results from two different runs of this
            -- functions.
            result_row.row_number := row_number;

            -- Now, if row_counter is still less than limit, return a row.  If
            -- not, but it is less than next_pivot_pos, continue on without
            -- returning actual result rows until we find
            -- that next pivot, and return it.

            IF row_counter < result_limit THEN
                result_row.browse_entry := rec.id;
                result_row.value := rec.value;

                RETURN NEXT result_row;
            ELSE
                result_row.browse_entry := NULL;
                result_row.authorities := NULL;
                result_row.fields := NULL;
                result_row.value := NULL;
                result_row.sources := NULL;
                result_row.sees := NULL;
                result_row.accurate := NULL;
                result_row.aaccurate := NULL;
                result_row.pivot_point := rec.id;

                IF row_counter >= next_pivot_pos THEN
                    RETURN NEXT result_row;
                    RETURN;
                END IF;
            END IF;

            IF count_up_from_zero THEN
                row_number := row_number + 1;
            ELSE
                row_number := row_number - 1;
            END IF;

            -- row_counter is different from row_number.
            -- It simply counts up from zero so that we know when
            -- we've reached our limit.
            row_counter := row_counter + 1;
        END IF;
    END LOOP;
END;
$f$ LANGUAGE plpgsql ROWS 10;

CREATE OR REPLACE FUNCTION metabib.browse(search_field integer[], browse_term text, context_org integer DEFAULT NULL::integer, context_loc_group integer DEFAULT NULL::integer, staff boolean DEFAULT false, pivot_id bigint DEFAULT NULL::bigint, result_limit integer DEFAULT 10)
 RETURNS SETOF metabib.flat_browse_entry_appearance
AS $f$
DECLARE
    core_query              TEXT;
    back_query              TEXT;
    forward_query           TEXT;
    pivot_sort_value        TEXT;
    pivot_sort_fallback     TEXT;
    context_locations       INT[];
    browse_superpage_size   INT;
    results_skipped         INT := 0;
    back_limit              INT;
    back_to_pivot           INT;
    forward_limit           INT;
    forward_to_pivot        INT;
BEGIN
    -- First, find the pivot if we were given a browse term but not a pivot.
    IF pivot_id IS NULL THEN
        pivot_id := metabib.browse_pivot(search_field, browse_term);
    END IF;

    SELECT INTO pivot_sort_value, pivot_sort_fallback
        sort_value, value FROM metabib.browse_entry WHERE id = pivot_id;

    -- Bail if we couldn't find a pivot.
    IF pivot_sort_value IS NULL THEN
        RETURN;
    END IF;

    -- Transform the context_loc_group argument (if any) (logc at the
    -- TPAC layer) into a form we'll be able to use.
    IF context_loc_group IS NOT NULL THEN
        SELECT INTO context_locations ARRAY_AGG(location)
            FROM asset.copy_location_group_map
            WHERE lgroup = context_loc_group;
    END IF;

    -- Get the configured size of browse superpages.
    SELECT INTO browse_superpage_size COALESCE(value::INT,100)     -- NULL ok
        FROM config.global_flag
        WHERE enabled AND name = 'opac.browse.holdings_visibility_test_limit';

    -- First we're going to search backward from the pivot, then we're going
    -- to search forward.  In each direction, we need two limits.  At the
    -- lesser of the two limits, we delineate the edge of the result set
    -- we're going to return.  At the greater of the two limits, we find the
    -- pivot value that would represent an offset from the current pivot
    -- at a distance of one "page" in either direction, where a "page" is a
    -- result set of the size specified in the "result_limit" argument.
    --
    -- The two limits in each direction make four derived values in total,
    -- and we calculate them now.
    back_limit := CEIL(result_limit::FLOAT / 2);
    back_to_pivot := result_limit;
    forward_limit := result_limit / 2;
    forward_to_pivot := result_limit - 1;

    -- This is the meat of the SQL query that finds browse entries.  We'll
    -- pass this to a function which uses it with a cursor, so that individual
    -- rows may be fetched in a loop until some condition is satisfied, without
    -- waiting for a result set of fixed size to be collected all at once.
    core_query := '
SELECT  mbe.id,
        mbe.value,
        mbe.sort_value
  FROM  metabib.browse_entry mbe
  WHERE (
            EXISTS ( -- are there any bibs using this mbe via the requested fields?
                SELECT  1
                  FROM  metabib.browse_entry_def_map mbedm
                  WHERE mbedm.entry = mbe.id AND mbedm.def = ANY(' || quote_literal(search_field) || ')
            ) OR EXISTS ( -- are there any authorities using this mbe via the requested fields?
                SELECT  1
                  FROM  metabib.browse_entry_simple_heading_map mbeshm
                        JOIN authority.simple_heading ash ON ( mbeshm.simple_heading = ash.id )
                        JOIN authority.control_set_auth_field_metabib_field_map_refs map ON (
                            ash.atag = map.authority_field
                            AND map.metabib_field = ANY(' || quote_literal(search_field) || ')
                        )
                        JOIN authority.control_set_authority_field acsaf ON (
                            map.authority_field = acsaf.id
                        )
                        JOIN authority.heading_field ahf ON (ahf.id = acsaf.heading_field)
                  WHERE mbeshm.entry = mbe.id
                    AND ahf.heading_purpose IN (' || $$'variant'$$ || ')
                    -- and authority that variant is coming from is linked to a bib
                    AND EXISTS (
                        SELECT  1
                        FROM  metabib.browse_entry_def_map mbedm2
                        WHERE mbedm2.authority = ash.record AND mbedm2.def = ANY(' || quote_literal(search_field) || ')
                    )
            )
        ) AND ';

    -- This is the variant of the query for browsing backward.
    back_query := core_query ||
        ' mbe.sort_value <= ' || quote_literal(pivot_sort_value) ||
    ' ORDER BY mbe.sort_value DESC, mbe.value DESC LIMIT 1000';

    -- This variant browses forward.
    forward_query := core_query ||
        ' mbe.sort_value > ' || quote_literal(pivot_sort_value) ||
    ' ORDER BY mbe.sort_value, mbe.value LIMIT 1000';

    -- We now call the function which applies a cursor to the provided
    -- queries, stopping at the appropriate limits and also giving us
    -- the next page's pivot.
    RETURN QUERY
        SELECT * FROM metabib.staged_browse(
            back_query, search_field, context_org, context_locations,
            staff, browse_superpage_size, TRUE, back_limit, back_to_pivot
        ) UNION
        SELECT * FROM metabib.staged_browse(
            forward_query, search_field, context_org, context_locations,
            staff, browse_superpage_size, FALSE, forward_limit, forward_to_pivot
        ) ORDER BY row_number DESC;

END;
$f$ LANGUAGE plpgsql ROWS 10;


SELECT evergreen.upgrade_deps_block_check('1072', :eg_version); --gmcharlt/kmlussier

INSERT INTO config.global_flag (name, label, enabled) VALUES (
    'opac.show_related_headings_in_browse',
    oils_i18n_gettext(
        'opac.show_related_headings_in_browse',
        'Display related headings (see-also) in browse',
        'cgf',
        'label'
    ),
    TRUE
);



SELECT evergreen.upgrade_deps_block_check('1073', :eg_version);

ALTER TABLE config.metabib_field 
    ADD COLUMN display_xpath TEXT, 
    ADD COLUMN display_field BOOL NOT NULL DEFAULT FALSE;

CREATE TABLE config.display_field_map (
    name    TEXT   PRIMARY KEY,
    field   INTEGER REFERENCES config.metabib_field (id),
    multi   BOOLEAN DEFAULT FALSE
);

CREATE TABLE metabib.display_entry (
    id      BIGSERIAL  PRIMARY KEY,
    source  BIGINT     NOT NULL REFERENCES biblio.record_entry (id),
    field   INT        NOT NULL REFERENCES config.metabib_field (id),
    value   TEXT       NOT NULL
);

CREATE INDEX metabib_display_entry_field_idx ON metabib.display_entry (field);
CREATE INDEX metabib_display_entry_source_idx ON metabib.display_entry (source);

-- one row per display entry fleshed with field info
CREATE VIEW metabib.flat_display_entry AS
    SELECT
        mde.source,
        cdfm.name,
        cdfm.multi,
        cmf.label,
        cmf.id AS field,
        mde.value
    FROM metabib.display_entry mde
    JOIN config.metabib_field cmf ON (cmf.id = mde.field)
    JOIN config.display_field_map cdfm ON (cdfm.field = mde.field)
;

-- like flat_display_entry except values are compressed 
-- into one row per display_field_map and JSON-ified.
CREATE VIEW metabib.compressed_display_entry AS
    SELECT 
        source,
        name,
        multi,
        label,
        field,
        CASE WHEN multi THEN
            TO_JSON(ARRAY_AGG(value))
        ELSE
            TO_JSON(MIN(value))
        END AS value
    FROM metabib.flat_display_entry
    GROUP BY 1, 2, 3, 4, 5
;

-- TODO: expand to encompass all well-known fields
CREATE VIEW metabib.wide_display_entry AS
    SELECT 
        bre.id AS source,
        COALESCE(mcde_title.value, 'null') AS title,
        COALESCE(mcde_author.value, 'null') AS author,
        COALESCE(mcde_subject.value, 'null') AS subject,
        COALESCE(mcde_creators.value, 'null') AS creators,
        COALESCE(mcde_isbn.value, 'null') AS isbn
    -- ensure one row per bre regardless of any display fields
    FROM biblio.record_entry bre 
    LEFT JOIN metabib.compressed_display_entry mcde_title 
        ON (bre.id = mcde_title.source AND mcde_title.name = 'title')
    LEFT JOIN metabib.compressed_display_entry mcde_author 
        ON (bre.id = mcde_author.source AND mcde_author.name = 'author')
    LEFT JOIN metabib.compressed_display_entry mcde_subject 
        ON (bre.id = mcde_subject.source AND mcde_subject.name = 'subject')
    LEFT JOIN metabib.compressed_display_entry mcde_creators 
        ON (bre.id = mcde_creators.source AND mcde_creators.name = 'creators')
    LEFT JOIN metabib.compressed_display_entry mcde_isbn 
        ON (bre.id = mcde_isbn.source AND mcde_isbn.name = 'isbn')
;


CREATE OR REPLACE FUNCTION metabib.display_field_normalize_trigger () 
    RETURNS TRIGGER AS $$
DECLARE
    normalizer  RECORD;
    display_field_text  TEXT;
BEGIN
    display_field_text := NEW.value;

    FOR normalizer IN
        SELECT  n.func AS func,
                n.param_count AS param_count,
                m.params AS params
          FROM  config.index_normalizer n
                JOIN config.metabib_field_index_norm_map m ON (m.norm = n.id)
          WHERE m.field = NEW.field AND m.pos < 0
          ORDER BY m.pos LOOP

            EXECUTE 'SELECT ' || normalizer.func || '(' ||
                quote_literal( display_field_text ) ||
                CASE
                    WHEN normalizer.param_count > 0
                        THEN ',' || REPLACE(REPLACE(BTRIM(
                            normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                        ELSE ''
                    END ||
                ')' INTO display_field_text;

    END LOOP;

    NEW.value = display_field_text;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER display_field_normalize_tgr
	BEFORE UPDATE OR INSERT ON metabib.display_entry
	FOR EACH ROW EXECUTE PROCEDURE metabib.display_field_normalize_trigger();

CREATE OR REPLACE FUNCTION evergreen.display_field_force_nfc() 
    RETURNS TRIGGER AS $$
BEGIN
    NEW.value := force_unicode_normal_form(NEW.value,'NFC');
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER display_field_force_nfc_tgr
	BEFORE UPDATE OR INSERT ON metabib.display_entry
	FOR EACH ROW EXECUTE PROCEDURE evergreen.display_field_force_nfc();

ALTER TYPE metabib.field_entry_template ADD ATTRIBUTE display_field BOOL;

DROP FUNCTION metabib.reingest_metabib_field_entries(BIGINT, BOOL, BOOL, BOOL);
DROP FUNCTION biblio.extract_metabib_field_entry(BIGINT);
DROP FUNCTION biblio.extract_metabib_field_entry(BIGINT, TEXT);

CREATE OR REPLACE FUNCTION biblio.extract_metabib_field_entry (
    rid BIGINT,
    default_joiner TEXT,
    field_types TEXT[],
    only_fields INT[]
) RETURNS SETOF metabib.field_entry_template AS $func$
DECLARE
    bib     biblio.record_entry%ROWTYPE;
    idx     config.metabib_field%ROWTYPE;
    xfrm        config.xml_transform%ROWTYPE;
    prev_xfrm   TEXT;
    transformed_xml TEXT;
    xml_node    TEXT;
    xml_node_list   TEXT[];
    facet_text  TEXT;
    display_text TEXT;
    browse_text TEXT;
    sort_value  TEXT;
    raw_text    TEXT;
    curr_text   TEXT;
    joiner      TEXT := default_joiner; -- XXX will index defs supply a joiner?
    authority_text TEXT;
    authority_link BIGINT;
    output_row  metabib.field_entry_template%ROWTYPE;
    process_idx BOOL;
BEGIN

    -- Start out with no field-use bools set
    output_row.browse_field = FALSE;
    output_row.facet_field = FALSE;
    output_row.display_field = FALSE;
    output_row.search_field = FALSE;

    -- Get the record
    SELECT INTO bib * FROM biblio.record_entry WHERE id = rid;

    -- Loop over the indexing entries
    FOR idx IN SELECT * FROM config.metabib_field WHERE id = ANY (only_fields) ORDER BY format LOOP

        process_idx := FALSE;
        IF idx.display_field AND 'display' = ANY (field_types) THEN process_idx = TRUE; END IF;
        IF idx.browse_field AND 'browse' = ANY (field_types) THEN process_idx = TRUE; END IF;
        IF idx.search_field AND 'search' = ANY (field_types) THEN process_idx = TRUE; END IF;
        IF idx.facet_field AND 'facet' = ANY (field_types) THEN process_idx = TRUE; END IF;
        CONTINUE WHEN process_idx = FALSE;

        joiner := COALESCE(idx.joiner, default_joiner);

        SELECT INTO xfrm * from config.xml_transform WHERE name = idx.format;

        -- See if we can skip the XSLT ... it's expensive
        IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
            -- Can't skip the transform
            IF xfrm.xslt <> '---' THEN
                transformed_xml := oils_xslt_process(bib.marc,xfrm.xslt);
            ELSE
                transformed_xml := bib.marc;
            END IF;

            prev_xfrm := xfrm.name;
        END IF;

        xml_node_list := oils_xpath( idx.xpath, transformed_xml, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );

        raw_text := NULL;
        FOR xml_node IN SELECT x FROM unnest(xml_node_list) AS x LOOP
            CONTINUE WHEN xml_node !~ E'^\\s*<';

            -- XXX much of this should be moved into oils_xpath_string...
            curr_text := ARRAY_TO_STRING(evergreen.array_remove_item_by_value(evergreen.array_remove_item_by_value(
                oils_xpath( '//text()', -- get the content of all the nodes within the main selected node
                    REGEXP_REPLACE( xml_node, E'\\s+', ' ', 'g' ) -- Translate adjacent whitespace to a single space
                ), ' '), ''),  -- throw away morally empty (bankrupt?) strings
                joiner
            );

            CONTINUE WHEN curr_text IS NULL OR curr_text = '';

            IF raw_text IS NOT NULL THEN
                raw_text := raw_text || joiner;
            END IF;

            raw_text := COALESCE(raw_text,'') || curr_text;

            -- autosuggest/metabib.browse_entry
            IF idx.browse_field THEN

                IF idx.browse_xpath IS NOT NULL AND idx.browse_xpath <> '' THEN
                    browse_text := oils_xpath_string( idx.browse_xpath, xml_node, joiner, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );
                ELSE
                    browse_text := curr_text;
                END IF;

                IF idx.browse_sort_xpath IS NOT NULL AND
                    idx.browse_sort_xpath <> '' THEN

                    sort_value := oils_xpath_string(
                        idx.browse_sort_xpath, xml_node, joiner,
                        ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]
                    );
                ELSE
                    sort_value := browse_text;
                END IF;

                output_row.field_class = idx.field_class;
                output_row.field = idx.id;
                output_row.source = rid;
                output_row.value = BTRIM(REGEXP_REPLACE(browse_text, E'\\s+', ' ', 'g'));
                output_row.sort_value :=
                    public.naco_normalize(sort_value);

                output_row.authority := NULL;

                IF idx.authority_xpath IS NOT NULL AND idx.authority_xpath <> '' THEN
                    authority_text := oils_xpath_string(
                        idx.authority_xpath, xml_node, joiner,
                        ARRAY[
                            ARRAY[xfrm.prefix, xfrm.namespace_uri],
                            ARRAY['xlink','http://www.w3.org/1999/xlink']
                        ]
                    );

                    IF authority_text ~ '^\d+$' THEN
                        authority_link := authority_text::BIGINT;
                        PERFORM * FROM authority.record_entry WHERE id = authority_link;
                        IF FOUND THEN
                            output_row.authority := authority_link;
                        END IF;
                    END IF;

                END IF;

                output_row.browse_field = TRUE;
                -- Returning browse rows with search_field = true for search+browse
                -- configs allows us to retain granularity of being able to search
                -- browse fields with "starts with" type operators (for example, for
                -- titles of songs in music albums)
                IF idx.search_field THEN
                    output_row.search_field = TRUE;
                END IF;
                RETURN NEXT output_row;
                output_row.browse_field = FALSE;
                output_row.search_field = FALSE;
                output_row.sort_value := NULL;
            END IF;

            -- insert raw node text for faceting
            IF idx.facet_field THEN

                IF idx.facet_xpath IS NOT NULL AND idx.facet_xpath <> '' THEN
                    facet_text := oils_xpath_string( idx.facet_xpath, xml_node, joiner, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );
                ELSE
                    facet_text := curr_text;
                END IF;

                output_row.field_class = idx.field_class;
                output_row.field = -1 * idx.id;
                output_row.source = rid;
                output_row.value = BTRIM(REGEXP_REPLACE(facet_text, E'\\s+', ' ', 'g'));

                output_row.facet_field = TRUE;
                RETURN NEXT output_row;
                output_row.facet_field = FALSE;
            END IF;

            -- insert raw node text for display
            IF idx.display_field THEN

                IF idx.display_xpath IS NOT NULL AND idx.display_xpath <> '' THEN
                    display_text := oils_xpath_string( idx.display_xpath, xml_node, joiner, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );
                ELSE
                    display_text := curr_text;
                END IF;

                output_row.field_class = idx.field_class;
                output_row.field = -1 * idx.id;
                output_row.source = rid;
                output_row.value = BTRIM(REGEXP_REPLACE(display_text, E'\\s+', ' ', 'g'));

                output_row.display_field = TRUE;
                RETURN NEXT output_row;
                output_row.display_field = FALSE;
            END IF;

        END LOOP;

        CONTINUE WHEN raw_text IS NULL OR raw_text = '';

        -- insert combined node text for searching
        IF idx.search_field THEN
            output_row.field_class = idx.field_class;
            output_row.field = idx.id;
            output_row.source = rid;
            output_row.value = BTRIM(REGEXP_REPLACE(raw_text, E'\\s+', ' ', 'g'));

            output_row.search_field = TRUE;
            RETURN NEXT output_row;
            output_row.search_field = FALSE;
        END IF;

    END LOOP;

END;

$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION metabib.reingest_metabib_field_entries( 
    bib_id BIGINT,
    skip_facet BOOL DEFAULT FALSE, 
    skip_display BOOL DEFAULT FALSE,
    skip_browse BOOL DEFAULT FALSE, 
    skip_search BOOL DEFAULT FALSE,
    only_fields INT[] DEFAULT '{}'::INT[]
) RETURNS VOID AS $func$
DECLARE
    fclass          RECORD;
    ind_data        metabib.field_entry_template%ROWTYPE;
    mbe_row         metabib.browse_entry%ROWTYPE;
    mbe_id          BIGINT;
    b_skip_facet    BOOL;
    b_skip_display    BOOL;
    b_skip_browse   BOOL;
    b_skip_search   BOOL;
    value_prepped   TEXT;
    field_list      INT[] := only_fields;
    field_types     TEXT[] := '{}'::TEXT[];
BEGIN

    IF field_list = '{}'::INT[] THEN
        SELECT ARRAY_AGG(id) INTO field_list FROM config.metabib_field;
    END IF;

    SELECT COALESCE(NULLIF(skip_facet, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_facet_indexing' AND enabled)) INTO b_skip_facet;
    SELECT COALESCE(NULLIF(skip_display, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_display_indexing' AND enabled)) INTO b_skip_display;
    SELECT COALESCE(NULLIF(skip_browse, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_browse_indexing' AND enabled)) INTO b_skip_browse;
    SELECT COALESCE(NULLIF(skip_search, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_search_indexing' AND enabled)) INTO b_skip_search;

    IF NOT b_skip_facet THEN field_types := field_types || '{facet}'; END IF;
    IF NOT b_skip_display THEN field_types := field_types || '{display}'; END IF;
    IF NOT b_skip_browse THEN field_types := field_types || '{browse}'; END IF;
    IF NOT b_skip_search THEN field_types := field_types || '{search}'; END IF;

    PERFORM * FROM config.internal_flag WHERE name = 'ingest.assume_inserts_only' AND enabled;
    IF NOT FOUND THEN
        IF NOT b_skip_search THEN
            FOR fclass IN SELECT * FROM config.metabib_class LOOP
                -- RAISE NOTICE 'Emptying out %', fclass.name;
                EXECUTE $$DELETE FROM metabib.$$ || fclass.name || $$_field_entry WHERE source = $$ || bib_id;
            END LOOP;
        END IF;
        IF NOT b_skip_facet THEN
            DELETE FROM metabib.facet_entry WHERE source = bib_id;
        END IF;
        IF NOT b_skip_display THEN
            DELETE FROM metabib.display_entry WHERE source = bib_id;
        END IF;
        IF NOT b_skip_browse THEN
            DELETE FROM metabib.browse_entry_def_map WHERE source = bib_id;
        END IF;
    END IF;

    FOR ind_data IN SELECT * FROM biblio.extract_metabib_field_entry( bib_id, ' ', field_types, field_list ) LOOP

	-- don't store what has been normalized away
        CONTINUE WHEN ind_data.value IS NULL;

        IF ind_data.field < 0 THEN
            ind_data.field = -1 * ind_data.field;
        END IF;

        IF ind_data.facet_field AND NOT b_skip_facet THEN
            INSERT INTO metabib.facet_entry (field, source, value)
                VALUES (ind_data.field, ind_data.source, ind_data.value);
        END IF;

        IF ind_data.display_field AND NOT b_skip_display THEN
            INSERT INTO metabib.display_entry (field, source, value)
                VALUES (ind_data.field, ind_data.source, ind_data.value);
        END IF;


        IF ind_data.browse_field AND NOT b_skip_browse THEN
            -- A caveat about this SELECT: this should take care of replacing
            -- old mbe rows when data changes, but not if normalization (by
            -- which I mean specifically the output of
            -- evergreen.oils_tsearch2()) changes.  It may or may not be
            -- expensive to add a comparison of index_vector to index_vector
            -- to the WHERE clause below.

            CONTINUE WHEN ind_data.sort_value IS NULL;

            value_prepped := metabib.browse_normalize(ind_data.value, ind_data.field);
            SELECT INTO mbe_row * FROM metabib.browse_entry
                WHERE value = value_prepped AND sort_value = ind_data.sort_value;

            IF FOUND THEN
                mbe_id := mbe_row.id;
            ELSE
                INSERT INTO metabib.browse_entry
                    ( value, sort_value ) VALUES
                    ( value_prepped, ind_data.sort_value );

                mbe_id := CURRVAL('metabib.browse_entry_id_seq'::REGCLASS);
            END IF;

            INSERT INTO metabib.browse_entry_def_map (entry, def, source, authority)
                VALUES (mbe_id, ind_data.field, ind_data.source, ind_data.authority);
        END IF;

        IF ind_data.search_field AND NOT b_skip_search THEN
            -- Avoid inserting duplicate rows
            EXECUTE 'SELECT 1 FROM metabib.' || ind_data.field_class ||
                '_field_entry WHERE field = $1 AND source = $2 AND value = $3'
                INTO mbe_id USING ind_data.field, ind_data.source, ind_data.value;
                -- RAISE NOTICE 'Search for an already matching row returned %', mbe_id;
            IF mbe_id IS NULL THEN
                EXECUTE $$
                INSERT INTO metabib.$$ || ind_data.field_class || $$_field_entry (field, source, value)
                    VALUES ($$ ||
                        quote_literal(ind_data.field) || $$, $$ ||
                        quote_literal(ind_data.source) || $$, $$ ||
                        quote_literal(ind_data.value) ||
                    $$);$$;
            END IF;
        END IF;

    END LOOP;

    IF NOT b_skip_search THEN
        PERFORM metabib.update_combined_index_vectors(bib_id);
    END IF;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

-- AFTER UPDATE OR INSERT trigger for biblio.record_entry
CREATE OR REPLACE FUNCTION biblio.indexing_ingest_or_delete () RETURNS TRIGGER AS $func$
DECLARE
    tmp_bool BOOL;
BEGIN

    IF NEW.deleted THEN -- If this bib is deleted

        PERFORM * FROM config.internal_flag WHERE
            name = 'ingest.metarecord_mapping.preserve_on_delete' AND enabled;

        tmp_bool := FOUND; -- Just in case this is changed by some other statement

        PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint, TRUE, tmp_bool );

        IF NOT tmp_bool THEN
            -- One needs to keep these around to support searches
            -- with the #deleted modifier, so one should turn on the named
            -- internal flag for that functionality.
            DELETE FROM metabib.record_attr_vector_list WHERE source = NEW.id;
        END IF;

        DELETE FROM authority.bib_linking WHERE bib = NEW.id; -- Avoid updating fields in bibs that are no longer visible
        DELETE FROM biblio.peer_bib_copy_map WHERE peer_record = NEW.id; -- Separate any multi-homed items
        DELETE FROM metabib.browse_entry_def_map WHERE source = NEW.id; -- Don't auto-suggest deleted bibs
        RETURN NEW; -- and we're done
    END IF;

    IF TG_OP = 'UPDATE' THEN -- re-ingest?
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc' AND enabled;

        IF NOT FOUND AND OLD.marc = NEW.marc THEN -- don't do anything if the MARC didn't change
            RETURN NEW;
        END IF;
    END IF;

    -- Record authority linking
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_linking' AND enabled;
    IF NOT FOUND THEN
        PERFORM biblio.map_authority_linking( NEW.id, NEW.marc );
    END IF;

    -- Flatten and insert the mfr data
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_full_rec' AND enabled;
    IF NOT FOUND THEN
        PERFORM metabib.reingest_metabib_full_rec(NEW.id);

        -- Now we pull out attribute data, which is dependent on the mfr for all but XPath-based fields
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_rec_descriptor' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.reingest_record_attributes(NEW.id, NULL, NEW.marc, TG_OP = 'INSERT' OR OLD.deleted);
        END IF;
    END IF;

    -- Gather and insert the field entry data
    PERFORM metabib.reingest_metabib_field_entries(NEW.id);

    -- Located URI magic
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
    IF NOT FOUND THEN PERFORM biblio.extract_located_uris( NEW.id, NEW.marc, NEW.editor ); END IF;

    -- (re)map metarecord-bib linking
    IF TG_OP = 'INSERT' THEN -- if not deleted and performing an insert, check for the flag
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_insert' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    ELSE -- we're doing an update, and we're not deleted, remap
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_update' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;




SELECT evergreen.upgrade_deps_block_check('1074', :eg_version);

INSERT INTO config.internal_flag (name, enabled) 
    VALUES ('ingest.skip_display_indexing', FALSE);

-- Adds seed data to replace (for now) values from the 'mvr' class

UPDATE config.metabib_field SET display_field = TRUE WHERE id IN (6, 8, 16, 18);

INSERT INTO config.metabib_field ( id, field_class, name, label,
    format, xpath, display_field, display_xpath ) VALUES
    (37, 'author', 'creator', oils_i18n_gettext(37, 'All Creators', 'cmf', 'label'),
     'mods32', $$//mods32:mods/mods32:name[mods32:role/mods32:roleTerm[text()='creator']]$$, 
     TRUE, $$//*[local-name()='namePart']$$ ); -- /* to fool vim */;

-- 'author' field
UPDATE config.metabib_field SET display_xpath = 
    $$//*[local-name()='namePart']$$ -- /* to fool vim */
    WHERE id = 8;

INSERT INTO config.display_field_map (name, field, multi) VALUES
    ('title', 6, FALSE),
    ('author', 8, FALSE),
    ('creators', 37, TRUE),
    ('subject', 16, TRUE),
    ('isbn', 18, TRUE)
;



SELECT evergreen.upgrade_deps_block_check('1075', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.vandelay_import_item_imported_as_inh_fkey() RETURNS TRIGGER AS $f$
BEGIN   
        IF NEW.imported_as IS NULL THEN
                RETURN NEW;
        END IF;
        PERFORM 1 FROM asset.copy WHERE id = NEW.imported_as;
        IF NOT FOUND THEN
                RAISE foreign_key_violation USING MESSAGE = FORMAT(
                        $$Referenced asset.copy id not found, imported_as:%s$$, NEW.imported_as
                );
        END IF;
        RETURN NEW;
END;
$f$ LANGUAGE PLPGSQL VOLATILE COST 50;

SELECT evergreen.upgrade_deps_block_check('1077', :eg_version); -- csharp/gmcharlt

-- if the "public" version of this function exists, drop it to prevent confusion/trouble

-- drop triggers that depend on this first
DROP TRIGGER IF EXISTS c_maintain_control_numbers ON biblio.record_entry;
DROP TRIGGER IF EXISTS c_maintain_control_numbers ON serial.record_entry;
DROP TRIGGER IF EXISTS c_maintain_control_numbers ON authority.record_entry;

DROP FUNCTION IF EXISTS public.maintain_control_numbers();

-- create the function within the "evergreen" schema

CREATE OR REPLACE FUNCTION evergreen.maintain_control_numbers() RETURNS TRIGGER AS $func$
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
if ($cn =~ /^o(c[nm]|n)\d/) {
    $cn =~ s/^o(c[nm]|n)0*(\d+)/$2/;
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

-- re-create the triggers
CREATE TRIGGER c_maintain_control_numbers BEFORE INSERT OR UPDATE ON serial.record_entry FOR EACH ROW EXECUTE PROCEDURE evergreen.maintain_control_numbers();
CREATE TRIGGER c_maintain_control_numbers BEFORE INSERT OR UPDATE ON authority.record_entry FOR EACH ROW EXECUTE PROCEDURE evergreen.maintain_control_numbers();
CREATE TRIGGER c_maintain_control_numbers BEFORE INSERT OR UPDATE ON biblio.record_entry FOR EACH ROW EXECUTE PROCEDURE evergreen.maintain_control_numbers();

COMMIT;

\echo ---------------------------------------------------------------------
\echo Updating visibility attribute vector for biblio.record_entry
BEGIN;

ALTER TABLE biblio.record_entry DISABLE TRIGGER  a_marcxml_is_well_formed;
ALTER TABLE biblio.record_entry DISABLE TRIGGER  aaa_indexing_ingest_or_delete;
ALTER TABLE biblio.record_entry DISABLE TRIGGER  audit_biblio_record_entry_update_trigger;
ALTER TABLE biblio.record_entry DISABLE TRIGGER  b_maintain_901;
ALTER TABLE biblio.record_entry DISABLE TRIGGER  bbb_simple_rec_trigger;
ALTER TABLE biblio.record_entry DISABLE TRIGGER  c_maintain_control_numbers;
ALTER TABLE biblio.record_entry DISABLE TRIGGER  fingerprint_tgr;
ALTER TABLE biblio.record_entry DISABLE TRIGGER  z_opac_vis_mat_view_tgr;

UPDATE biblio.record_entry SET vis_attr_vector = biblio.calculate_bib_visibility_attribute_set(id) WHERE NOT DELETED;

ALTER TABLE biblio.record_entry ENABLE TRIGGER  a_marcxml_is_well_formed;
ALTER TABLE biblio.record_entry ENABLE TRIGGER  aaa_indexing_ingest_or_delete;
ALTER TABLE biblio.record_entry ENABLE TRIGGER  audit_biblio_record_entry_update_trigger;
ALTER TABLE biblio.record_entry ENABLE TRIGGER  b_maintain_901;
ALTER TABLE biblio.record_entry ENABLE TRIGGER  bbb_simple_rec_trigger;
ALTER TABLE biblio.record_entry ENABLE TRIGGER  c_maintain_control_numbers;
ALTER TABLE biblio.record_entry ENABLE TRIGGER  fingerprint_tgr;
ALTER TABLE biblio.record_entry ENABLE TRIGGER  z_opac_vis_mat_view_tgr;

COMMIT;

\echo ---------------------------------------------------------------------
\echo Reingest display fields.  This can be canceled via Ctrl-C and run at
\echo a later time with the following (or similar) SQL:
\echo
\echo 'SELECT metabib.reingest_metabib_field_entries(id, TRUE, FALSE, TRUE, TRUE, '
\echo '    (SELECT ARRAY_AGG(id)::INT[] FROM config.metabib_field WHERE display_field))'
\echo '    FROM biblio.record_entry WHERE NOT deleted AND id > 0;'
\echo
\echo Note that if you cancel now, you will also need to do the authority reingest
\echo further down in the upgrade script.

-- REINGEST DISPLAY ENTRIES
SELECT metabib.reingest_metabib_field_entries(id, TRUE, FALSE, TRUE, TRUE, 
    (SELECT ARRAY_AGG(id)::INT[] FROM config.metabib_field WHERE display_field))
    FROM biblio.record_entry WHERE NOT deleted AND id > 0;


\echo ---------------------------------------------------------------------
\echo Reingest authority records. This can be canceled via Ctrl-C and run
\echo at a later time; see the upgrade script.  Note that if you cancel now,
\echo you should consult this upgrade script for the reingest actions required.
BEGIN;

-- add the flag ingest.disable_authority_full_rec if it does not exist
INSERT INTO config.internal_flag (name, enabled)
SELECT 'ingest.disable_authority_full_rec', FALSE
WHERE NOT EXISTS (SELECT 1 FROM config.internal_flag WHERE name = 'ingest.disable_authority_full_rec');

CREATE TEMPORARY TABLE internal_flag_state AS
    SELECT name, enabled
    FROM config.internal_flag
    WHERE name in (
        'ingest.reingest.force_on_same_marc',
        'ingest.disable_authority_auto_update',
        'ingest.disable_authority_full_rec'
    );

UPDATE config.internal_flag
SET enabled = TRUE
WHERE name in (
    'ingest.reingest.force_on_same_marc',
    'ingest.disable_authority_auto_update',
    'ingest.disable_authority_full_rec'
);

ALTER TABLE authority.record_entry DISABLE TRIGGER a_marcxml_is_well_formed;
ALTER TABLE authority.record_entry DISABLE TRIGGER b_maintain_901;
ALTER TABLE authority.record_entry DISABLE TRIGGER c_maintain_control_numbers;
ALTER TABLE authority.record_entry DISABLE TRIGGER map_thesaurus_to_control_set;

UPDATE authority.record_entry SET id = id WHERE NOT DELETED;

ALTER TABLE authority.record_entry ENABLE TRIGGER a_marcxml_is_well_formed;
ALTER TABLE authority.record_entry ENABLE TRIGGER b_maintain_901;
ALTER TABLE authority.record_entry ENABLE TRIGGER c_maintain_control_numbers;
ALTER TABLE authority.record_entry ENABLE TRIGGER map_thesaurus_to_control_set;

-- and restore
UPDATE config.internal_flag a
SET enabled = b.enabled
FROM internal_flag_state b
WHERE a.name = b.name;

COMMIT;
