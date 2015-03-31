--Upgrade Script for 2.7.4 to 2.8.0
\set eg_version '''2.8.0'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.8.0', :eg_version);

SELECT evergreen.upgrade_deps_block_check('0902', :eg_version);

CREATE OR REPLACE FUNCTION action.hold_request_clear_map () RETURNS TRIGGER AS $$
BEGIN
  DELETE FROM action.hold_copy_map WHERE hold = NEW.id;
  RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER hold_request_clear_map_tgr
    AFTER UPDATE ON action.hold_request
    FOR EACH ROW
    WHEN (
        (NEW.cancel_time IS NOT NULL AND OLD.cancel_time IS NULL)
        OR (NEW.fulfillment_time IS NOT NULL AND OLD.fulfillment_time IS NULL)
    )
    EXECUTE PROCEDURE action.hold_request_clear_map();



SELECT evergreen.upgrade_deps_block_check('0903', :eg_version);

INSERT INTO config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES
        ('circ.void_lost_on_claimsreturned',
         'circ',
         oils_i18n_gettext('circ.void_lost_on_claimsreturned',
             'Void lost item billing when claims returned',
             'coust', 'label'),
         oils_i18n_gettext('circ.void_lost_on_claimsreturned',
             'Void lost item billing when claims returned',
             'coust', 'description'),
         'bool'),
        ('circ.void_lost_proc_fee_on_claimsreturned',
         'circ',
         oils_i18n_gettext('circ.void_lost_proc_fee_on_claimsreturned',
             'Void lost item processing fee when claims returned',
             'coust', 'label'),
         oils_i18n_gettext('circ.void_lost_proc_fee_on_claimsreturned',
             'Void lost item processing fee when claims returned',
             'coust', 'description'),
         'bool');

INSERT INTO config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES
        ('circ.void_longoverdue_on_claimsreturned',
         'circ',
         oils_i18n_gettext('circ.void_longoverdue_on_claimsreturned',
             'Void long overdue item billing when claims returned',
             'coust', 'label'),
         oils_i18n_gettext('circ.void_longoverdue_on_claimsreturned',
             'Void long overdue item billing when claims returned',
             'coust', 'description'),
         'bool'),
        ('circ.void_longoverdue_proc_fee_on_claimsreturned',
         'circ',
         oils_i18n_gettext('circ.void_longoverdue_proc_fee_on_claimsreturned',
             'Void long overdue item processing fee when claims returned',
             'coust', 'label'),
         oils_i18n_gettext('circ.void_longoverdue_proc_fee_on_claimsreturned',
             'Void long overdue item processing fee when claims returned',
             'coust', 'description'),
         'bool');


SELECT evergreen.upgrade_deps_block_check('0907', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype ) VALUES

( 'circ.checkin.lost_zero_balance.do_not_change',
  'circ',
  'Do not change fines/fees on zero-balance LOST transaction',
  'When an item has been marked lost and all fines/fees have been completely paid on the transaction, do not void or reinstate any fines/fees EVEN IF circ.void_lost_on_checkin and/or circ.void_lost_proc_fee_on_checkin are enabled',
  'bool');



SELECT evergreen.upgrade_deps_block_check('0909', :eg_version);

ALTER TABLE vandelay.authority_match
    ADD COLUMN match_score INT NOT NULL DEFAULT 0;

-- support heading=TRUE match set points
ALTER TABLE vandelay.match_set_point
    ADD COLUMN heading BOOLEAN NOT NULL DEFAULT FALSE,
    DROP CONSTRAINT vmsp_need_a_tag_or_a_ff_or_a_bo,
    ADD CONSTRAINT vmsp_need_a_tag_or_a_ff_or_a_heading_or_a_bo
    CHECK (
        (tag IS NOT NULL AND svf IS NULL AND heading IS FALSE AND bool_op IS NULL) OR 
        (tag IS NULL AND svf IS NOT NULL AND heading IS FALSE AND bool_op IS NULL) OR 
        (tag IS NULL AND svf IS NULL AND heading IS TRUE AND bool_op IS NULL) OR 
        (tag IS NULL AND svf IS NULL AND heading IS FALSE AND bool_op IS NOT NULL)
    );

CREATE OR REPLACE FUNCTION vandelay.get_expr_from_match_set(
    match_set_id INTEGER,
    tags_rstore HSTORE,
    auth_heading TEXT
) RETURNS TEXT AS $$
DECLARE
    root vandelay.match_set_point;
BEGIN
    SELECT * INTO root FROM vandelay.match_set_point
        WHERE parent IS NULL AND match_set = match_set_id;

    RETURN vandelay.get_expr_from_match_set_point(
        root, tags_rstore, auth_heading);
END;
$$  LANGUAGE PLPGSQL;

-- backwards compat version so we don't have 
-- to modify vandelay.match_set_test_marcxml()
CREATE OR REPLACE FUNCTION vandelay.get_expr_from_match_set(
    match_set_id INTEGER,
    tags_rstore HSTORE
) RETURNS TEXT AS $$
BEGIN
    RETURN vandelay.get_expr_from_match_set(
        match_set_id, tags_rstore, NULL);
END;
$$  LANGUAGE PLPGSQL;


DROP FUNCTION IF EXISTS 
    vandelay.get_expr_from_match_set_point(vandelay.match_set_point, HSTORE);

CREATE OR REPLACE FUNCTION vandelay.get_expr_from_match_set_point(
    node vandelay.match_set_point,
    tags_rstore HSTORE,
    auth_heading TEXT
) RETURNS TEXT AS $$
DECLARE
    q           TEXT;
    i           INTEGER;
    this_op     TEXT;
    children    INTEGER[];
    child       vandelay.match_set_point;
BEGIN
    SELECT ARRAY_AGG(id) INTO children FROM vandelay.match_set_point
        WHERE parent = node.id;

    IF ARRAY_LENGTH(children, 1) > 0 THEN
        this_op := vandelay._get_expr_render_one(node);
        q := '(';
        i := 1;
        WHILE children[i] IS NOT NULL LOOP
            SELECT * INTO child FROM vandelay.match_set_point
                WHERE id = children[i];
            IF i > 1 THEN
                q := q || ' ' || this_op || ' ';
            END IF;
            i := i + 1;
            q := q || vandelay.get_expr_from_match_set_point(
                child, tags_rstore, auth_heading);
        END LOOP;
        q := q || ')';
        RETURN q;
    ELSIF node.bool_op IS NULL THEN
        PERFORM vandelay._get_expr_push_qrow(node);
        PERFORM vandelay._get_expr_push_jrow(node, tags_rstore, auth_heading);
        RETURN vandelay._get_expr_render_one(node);
    ELSE
        RETURN '';
    END IF;
END;
$$  LANGUAGE PLPGSQL;


DROP FUNCTION IF EXISTS 
    vandelay._get_expr_push_jrow(vandelay.match_set_point, HSTORE);

CREATE OR REPLACE FUNCTION vandelay._get_expr_push_jrow(
    node vandelay.match_set_point,
    tags_rstore HSTORE,
    auth_heading TEXT
) RETURNS VOID AS $$
DECLARE
    jrow        TEXT;
    my_alias    TEXT;
    op          TEXT;
    tagkey      TEXT;
    caseless    BOOL;
    jrow_count  INT;
    my_using    TEXT;
    my_join     TEXT;
    rec_table   TEXT;
BEGIN
    -- remember $1 is tags_rstore, and $2 is svf_rstore
    -- a non-NULL auth_heading means we're matching authority records

    IF auth_heading IS NOT NULL THEN
        rec_table := 'authority.full_rec';
    ELSE
        rec_table := 'metabib.full_rec';
    END IF;

    caseless := FALSE;
    SELECT COUNT(*) INTO jrow_count FROM _vandelay_tmp_jrows;
    IF jrow_count > 0 THEN
        my_using := ' USING (record)';
        my_join := 'FULL OUTER JOIN';
    ELSE
        my_using := '';
        my_join := 'FROM';
    END IF;

    IF node.tag IS NOT NULL THEN
        caseless := (node.tag IN ('020', '022', '024'));
        tagkey := node.tag;
        IF node.subfield IS NOT NULL THEN
            tagkey := tagkey || node.subfield;
        END IF;
    END IF;

    IF node.negate THEN
        IF caseless THEN
            op := 'NOT LIKE';
        ELSE
            op := '<>';
        END IF;
    ELSE
        IF caseless THEN
            op := 'LIKE';
        ELSE
            op := '=';
        END IF;
    END IF;

    my_alias := 'n' || node.id::TEXT;

    jrow := my_join || ' (SELECT *, ';
    IF node.tag IS NOT NULL THEN
        jrow := jrow  || node.quality ||
            ' AS quality FROM ' || rec_table || ' mfr WHERE mfr.tag = ''' ||
            node.tag || '''';
        IF node.subfield IS NOT NULL THEN
            jrow := jrow || ' AND mfr.subfield = ''' ||
                node.subfield || '''';
        END IF;
        jrow := jrow || ' AND (';
        jrow := jrow || vandelay._node_tag_comparisons(caseless, op, tags_rstore, tagkey);
        jrow := jrow || ')) ' || my_alias || my_using || E'\n';
    ELSE    -- svf
        IF auth_heading IS NOT NULL THEN -- authority record
            IF node.heading AND auth_heading <> '' THEN
                jrow := jrow || 'id AS record, ' || node.quality ||
                ' AS quality FROM authority.record_entry are ' ||
                ' WHERE are.heading = ''' || auth_heading || '''';
                jrow := jrow || ') ' || my_alias || my_using || E'\n';
            END IF;
        ELSE -- bib record
            jrow := jrow || 'id AS record, ' || node.quality ||
                ' AS quality FROM metabib.record_attr_flat mraf WHERE mraf.attr = ''' ||
                node.svf || ''' AND mraf.value ' || op || ' $2->''' || node.svf || ''') ' ||
                my_alias || my_using || E'\n';
        END IF;
    END IF;
    INSERT INTO _vandelay_tmp_jrows (j) VALUES (jrow);
END;
$$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION vandelay.match_set_test_authxml(
    match_set_id INTEGER, record_xml TEXT
) RETURNS SETOF vandelay.match_set_test_result AS $$
DECLARE
    tags_rstore HSTORE;
    heading     TEXT;
    coal        TEXT;
    joins       TEXT;
    query_      TEXT;
    wq          TEXT;
    qvalue      INTEGER;
    rec         RECORD;
BEGIN
    tags_rstore := vandelay.flatten_marc_hstore(record_xml);

    SELECT normalize_heading INTO heading 
        FROM authority.normalize_heading(record_xml);

    CREATE TEMPORARY TABLE _vandelay_tmp_qrows (q INTEGER);
    CREATE TEMPORARY TABLE _vandelay_tmp_jrows (j TEXT);

    -- generate the where clause and return that directly (into wq), and as
    -- a side-effect, populate the _vandelay_tmp_[qj]rows tables.
    wq := vandelay.get_expr_from_match_set(
        match_set_id, tags_rstore, heading);

    query_ := 'SELECT DISTINCT(record), ';

    -- qrows table is for the quality bits we add to the SELECT clause
    SELECT STRING_AGG(
        'COALESCE(n' || q::TEXT || '.quality, 0)', ' + '
    ) INTO coal FROM _vandelay_tmp_qrows;

    -- our query string so far is the SELECT clause and the inital FROM.
    -- no JOINs yet nor the WHERE clause
    query_ := query_ || coal || ' AS quality ' || E'\n';

    -- jrows table is for the joins we must make (and the real text conditions)
    SELECT STRING_AGG(j, E'\n') INTO joins
        FROM _vandelay_tmp_jrows;

    -- add those joins and the where clause to our query.
    query_ := query_ || joins || E'\n';

    query_ := query_ || 'JOIN authority.record_entry are ON (are.id = record) ' 
        || 'WHERE ' || wq || ' AND not are.deleted';

    -- this will return rows of record,quality
    FOR rec IN EXECUTE query_ USING tags_rstore LOOP
        RETURN NEXT rec;
    END LOOP;

    DROP TABLE _vandelay_tmp_qrows;
    DROP TABLE _vandelay_tmp_jrows;
    RETURN;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.measure_auth_record_quality 
    ( xml TEXT, match_set_id INT ) RETURNS INT AS $_$
DECLARE
    out_q   INT := 0;
    rvalue  TEXT;
    test    vandelay.match_set_quality%ROWTYPE;
BEGIN

    FOR test IN SELECT * FROM vandelay.match_set_quality 
            WHERE match_set = match_set_id LOOP
        IF test.tag IS NOT NULL THEN
            FOR rvalue IN SELECT value FROM vandelay.flatten_marc( xml ) 
                WHERE tag = test.tag AND subfield = test.subfield LOOP
                IF test.value = rvalue THEN
                    out_q := out_q + test.quality;
                END IF;
            END LOOP;
        END IF;
    END LOOP;

    RETURN out_q;
END;
$_$ LANGUAGE PLPGSQL;



CREATE OR REPLACE FUNCTION vandelay.match_authority_record() RETURNS TRIGGER AS $func$
DECLARE
    incoming_existing_id    TEXT;
    test_result             vandelay.match_set_test_result%ROWTYPE;
    tmp_rec                 BIGINT;
    match_set               INT;
BEGIN
    IF TG_OP IN ('INSERT','UPDATE') AND NEW.imported_as IS NOT NULL THEN
        RETURN NEW;
    END IF;

    DELETE FROM vandelay.authority_match WHERE queued_record = NEW.id;

    SELECT q.match_set INTO match_set FROM vandelay.authority_queue q WHERE q.id = NEW.queue;

    IF match_set IS NOT NULL THEN
        NEW.quality := vandelay.measure_auth_record_quality( NEW.marc, match_set );
    END IF;

    -- Perfect matches on 901$c exit early with a match with high quality.
    incoming_existing_id :=
        oils_xpath_string('//*[@tag="901"]/*[@code="c"][1]', NEW.marc);

    IF incoming_existing_id IS NOT NULL AND incoming_existing_id != '' THEN
        SELECT id INTO tmp_rec FROM authority.record_entry WHERE id = incoming_existing_id::bigint;
        IF tmp_rec IS NOT NULL THEN
            INSERT INTO vandelay.authority_match (queued_record, eg_record, match_score, quality) 
                SELECT
                    NEW.id, 
                    b.id,
                    9999,
                    -- note: no match_set means quality==0
                    vandelay.measure_auth_record_quality( b.marc, match_set )
                FROM authority.record_entry b
                WHERE id = incoming_existing_id::bigint;
        END IF;
    END IF;

    IF match_set IS NULL THEN
        RETURN NEW;
    END IF;

    FOR test_result IN SELECT * FROM
        vandelay.match_set_test_authxml(match_set, NEW.marc) LOOP

        INSERT INTO vandelay.authority_match ( queued_record, eg_record, match_score, quality )
            SELECT  
                NEW.id,
                test_result.record,
                test_result.quality,
                vandelay.measure_auth_record_quality( b.marc, match_set )
	        FROM  authority.record_entry b
	        WHERE id = test_result.record;

    END LOOP;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

CREATE TRIGGER zz_match_auths_trigger
    BEFORE INSERT OR UPDATE ON vandelay.queued_authority_record
    FOR EACH ROW EXECUTE PROCEDURE vandelay.match_authority_record();

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_authority_record_with_best ( import_id BIGINT, merge_profile_id INT, lwm_ratio_value_p NUMERIC ) RETURNS BOOL AS $$
DECLARE
    eg_id           BIGINT;
    lwm_ratio_value NUMERIC;
BEGIN

    lwm_ratio_value := COALESCE(lwm_ratio_value_p, 0.0);

    PERFORM * FROM vandelay.queued_authority_record WHERE import_time IS NOT NULL AND id = import_id;

    IF FOUND THEN
        -- RAISE NOTICE 'already imported, cannot auto-overlay'
        RETURN FALSE;
    END IF;

    SELECT  m.eg_record INTO eg_id
      FROM  vandelay.authority_match m
            JOIN vandelay.queued_authority_record qr ON (m.queued_record = qr.id)
            JOIN vandelay.authority_queue q ON (qr.queue = q.id)
            JOIN authority.record_entry r ON (r.id = m.eg_record)
      WHERE m.queued_record = import_id
            AND qr.quality::NUMERIC / COALESCE(NULLIF(m.quality,0),1)::NUMERIC >= lwm_ratio_value
      ORDER BY  m.match_score DESC, -- required match score
                qr.quality::NUMERIC / COALESCE(NULLIF(m.quality,0),1)::NUMERIC DESC, -- quality tie breaker
                m.id -- when in doubt, use the first match
      LIMIT 1;

    IF eg_id IS NULL THEN
        -- RAISE NOTICE 'incoming record is not of high enough quality';
        RETURN FALSE;
    END IF;

    RETURN vandelay.overlay_authority_record( import_id, eg_id, merge_profile_id );
END;
$$ LANGUAGE PLPGSQL;



SELECT evergreen.upgrade_deps_block_check('0910', :eg_version);

CREATE TABLE actor.usr_message (
    id          SERIAL                      PRIMARY KEY,
    usr         INT                         NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    title       TEXT,
    message     TEXT                        NOT NULL,
    create_date TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
    deleted     BOOL                        NOT NULL DEFAULT FALSE,
    read_date   TIMESTAMP WITH TIME ZONE,
    sending_lib INT                         NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED
);
CREATE INDEX aum_usr ON actor.usr_message (usr);

CREATE RULE protect_usr_message_delete AS
    ON DELETE TO actor.usr_message DO INSTEAD (
        UPDATE actor.usr_message
            SET deleted = TRUE
            WHERE OLD.id = actor.usr_message.id
    );

ALTER TABLE action_trigger.event_definition
    ADD COLUMN message_template TEXT,
    ADD COLUMN message_usr_path TEXT,
    ADD COLUMN message_library_path TEXT,
    ADD COLUMN message_title TEXT;

CREATE FUNCTION actor.convert_usr_note_to_message () RETURNS TRIGGER AS $$
BEGIN
    IF NEW.pub THEN
        IF TG_OP = 'UPDATE' THEN
            IF OLD.pub = TRUE THEN
                RETURN NEW;
            END IF;
        END IF;

        INSERT INTO actor.usr_message (usr, title, message, sending_lib)
            VALUES (NEW.usr, NEW.title, NEW.value, (SELECT home_ou FROM actor.usr WHERE id = NEW.creator));
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER convert_usr_note_to_message_tgr
    AFTER INSERT OR UPDATE ON actor.usr_note
    FOR EACH ROW EXECUTE PROCEDURE actor.convert_usr_note_to_message();

CREATE VIEW actor.usr_message_limited
AS SELECT * FROM actor.usr_message;

CREATE FUNCTION actor.restrict_usr_message_limited () RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        UPDATE actor.usr_message
        SET    read_date = NEW.read_date,
               deleted   = NEW.deleted
        WHERE  id = NEW.id;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER restrict_usr_message_limited_tgr
    INSTEAD OF UPDATE OR INSERT OR DELETE ON actor.usr_message_limited
    FOR EACH ROW EXECUTE PROCEDURE actor.restrict_usr_message_limited();

-- and copy over existing public user notes as (read) patron messages
INSERT INTO actor.usr_message (usr, title, message, sending_lib, create_date, read_date)
SELECT aun.usr, title, value, home_ou, aun.create_date, NOW()
FROM actor.usr_note aun
JOIN actor.usr au ON (au.id = aun.usr)
WHERE aun.pub;



SELECT evergreen.upgrade_deps_block_check('0911', :eg_version);

-- Auto-cancelled, no target
INSERT INTO action_trigger.event_definition (
    id, active, owner, name, hook,
    validator, reactor, delay, delay_field,
    group_field, message_usr_path, message_library_path, message_title,
    message_template
) VALUES (
    51, FALSE, 1, 'Hold Cancelled (No Target) User Message', 'hold_request.cancel.expire_no_target',
    'HoldIsCancelled', 'NOOP_True', '30 minutes', 'cancel_time',
    'usr', 'usr', 'usr.home_ou', 'Hold Request Cancelled',
$$
[%- USE date -%]
[%- user = target.0.usr -%]
The following holds were cancelled because no items were found to fullfil them.

[% FOR hold IN target %]
    Title: [% hold.bib_rec.bib_record.simple_record.title %]
    Author: [% hold.bib_rec.bib_record.simple_record.author %]
    Library: [% hold.pickup_lib.name %]
    Request Date: [% date.format(helpers.format_date(hold.request_time), '%Y-%m-%d') %]
[% END %]

$$);

INSERT INTO action_trigger.environment (event_def, path) VALUES
    (51, 'usr'),
    (51, 'pickup_lib'),
    (51, 'bib_rec.bib_record.simple_record');


-- Cancelled by staff
INSERT INTO action_trigger.event_definition (
    id, active, owner, name, hook,
    validator, reactor, delay, delay_field,
    group_field, message_usr_path, message_library_path, message_title,
    message_template
) VALUES (
    52, FALSE, 1, 'Hold Cancelled (Staff) User Message', 'hold_request.cancel.staff',
    'HoldIsCancelled', 'NOOP_True', '30 minutes', 'cancel_time',
    'usr', 'usr', 'usr.home_ou', 'Hold Request Cancelled',
$$
[%- USE date -%]
[%- user = target.0.usr -%]
The following holds were cancelled by a staff member.

[% FOR hold IN target %]
    Title: [% hold.bib_rec.bib_record.simple_record.title %]
    Author: [% hold.bib_rec.bib_record.simple_record.author %]
    Library: [% hold.pickup_lib.name %]
    Request Date: [% date.format(helpers.format_date(hold.request_time), '%Y-%m-%d') %]
    Cancellation Note: [% hold.cancel_note %]
[% END %]

$$);

INSERT INTO action_trigger.environment (event_def, path) VALUES
    (52, 'usr'),
    (52, 'pickup_lib'),
    (52, 'bib_rec.bib_record.simple_record');


-- Shelf expired
INSERT INTO action_trigger.event_definition (
    id, active, owner, name, hook,
    validator, reactor, delay, delay_field,
    group_field, message_usr_path, message_library_path, message_title,
    message_template
) VALUES (
    53, TRUE, 1, 'Hold Cancelled (Shelf-Expired) User Message', 'hold_request.cancel.expire_holds_shelf',
    'HoldIsCancelled', 'NOOP_True', '30 minutes', 'cancel_time',
    'usr', 'usr', 'usr.home_ou', 'Hold Request Cancelled',
$$
[%- USE date -%]
[%- user = target.0.usr -%]
The following holds were cancelled because they were never picked up.

[% FOR hold IN target %]
    Title: [% hold.bib_rec.bib_record.simple_record.title %]
    Author: [% hold.bib_rec.bib_record.simple_record.author %]
    Library: [% hold.pickup_lib.name %]
    Request Date: [% date.format(helpers.format_date(hold.request_time), '%Y-%m-%d') %]
    Pickup By: [% date.format(helpers.format_date(hold.shelf_expire_time), '%Y-%m-%d') %]
[% END %]

$$);

INSERT INTO action_trigger.environment (event_def, path) VALUES
    (53, 'usr'),
    (53, 'pickup_lib'),
    (53, 'bib_rec.bib_record.simple_record');



SELECT evergreen.upgrade_deps_block_check('0912', :eg_version);

ALTER TABLE asset.copy_location ADD COLUMN deleted BOOLEAN NOT NULL DEFAULT FALSE;

CREATE OR REPLACE RULE protect_copy_location_delete AS
    ON DELETE TO asset.copy_location DO INSTEAD (
        UPDATE asset.copy_location SET deleted = TRUE WHERE OLD.id = asset.copy_location.id;
        UPDATE acq.lineitem_detail SET location = NULL WHERE location = OLD.id;
        DELETE FROM asset.copy_location_order WHERE location = OLD.id;
        DELETE FROM asset.copy_location_group_map WHERE location = OLD.id;
        DELETE FROM config.circ_limit_set_copy_loc_map WHERE copy_loc = OLD.id;
    );

ALTER TABLE asset.copy_location DROP CONSTRAINT acl_name_once_per_lib;
CREATE UNIQUE INDEX acl_name_once_per_lib ON asset.copy_location (name, owning_lib) WHERE deleted = FALSE OR deleted IS FALSE;

CREATE OR REPLACE FUNCTION asset.acp_location_fixer()
RETURNS TRIGGER AS $$
DECLARE
    new_copy_location INT;
BEGIN
    IF (TG_OP = 'UPDATE') THEN
        IF NEW.location = OLD.location AND NEW.call_number = OLD.call_number AND NEW.circ_lib = OLD.circ_lib THEN
            RETURN NEW;
        END IF;
    END IF;
    SELECT INTO new_copy_location acpl.id FROM asset.copy_location acpl JOIN actor.org_unit_ancestors_distance((SELECT owning_lib FROM asset.call_number WHERE id = NEW.call_number)) aouad ON acpl.owning_lib = aouad.id WHERE deleted IS FALSE AND name = (SELECT name FROM asset.copy_location WHERE id = NEW.location) ORDER BY distance LIMIT 1;
    IF new_copy_location IS NULL THEN
        SELECT INTO new_copy_location acpl.id FROM asset.copy_location acpl JOIN actor.org_unit_ancestors_distance(NEW.circ_lib) aouad ON acpl.owning_lib = aouad.id WHERE deleted IS FALSE AND name = (SELECT name FROM asset.copy_location WHERE id = NEW.location) ORDER BY distance LIMIT 1;
    END IF;
    IF new_copy_location IS NOT NULL THEN
        NEW.location = new_copy_location;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION asset.staff_ou_record_copy_count (org INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE         
    ans RECORD; 
    trans INT;
BEGIN           
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = rid;

    FOR ans IN SELECT u.id, t.depth FROM actor.org_unit_ancestors(org) AS u JOIN actor.org_unit_type t ON (u.ou_type = t.id) LOOP
        RETURN QUERY
        SELECT  ans.depth,
                ans.id,
                COUNT( cp.id ),
                SUM( CASE WHEN cp.status IN (0,7,12) THEN 1 ELSE 0 END ),
                SUM( CASE WHEN cl.opac_visible AND cp.opac_visible THEN 1 ELSE 0 END),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
                JOIN asset.copy_location cl ON (cp.location = cl.id AND NOT cl.deleted)
                JOIN asset.call_number cn ON (cn.record = rid AND cn.id = cp.call_number AND NOT cn.deleted)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

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
                SUM( CASE WHEN cp.status IN (0,7,12) THEN 1 ELSE 0 END ),
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

CREATE OR REPLACE FUNCTION asset.record_has_holdable_copy ( rid BIGINT, ou INT DEFAULT NULL) RETURNS BOOL AS $f$
BEGIN
    PERFORM 1
        FROM
            asset.copy acp
            JOIN asset.call_number acn ON acp.call_number = acn.id
            JOIN asset.copy_location acpl ON acp.location = acpl.id
            JOIN config.copy_status ccs ON acp.status = ccs.id
        WHERE
            acn.record = rid
            AND acp.holdable = true
            AND acpl.holdable = true
            AND ccs.holdable = true
            AND acp.deleted = false
            AND acpl.deleted = false
            AND acp.circ_lib IN (SELECT id FROM actor.org_unit_descendants(COALESCE($2,(SELECT id FROM evergreen.org_top()))))
        LIMIT 1;
    IF FOUND THEN
        RETURN true;
    END IF;
    RETURN FALSE;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.metarecord_has_holdable_copy ( rid BIGINT, ou INT DEFAULT NULL) RETURNS BOOL AS $f$
BEGIN
    PERFORM 1
        FROM
            asset.copy acp
            JOIN asset.call_number acn ON acp.call_number = acn.id
            JOIN asset.copy_location acpl ON acp.location = acpl.id
            JOIN config.copy_status ccs ON acp.status = ccs.id
            JOIN metabib.metarecord_source_map mmsm ON acn.record = mmsm.source
        WHERE
            mmsm.metarecord = rid
            AND acp.holdable = true
            AND acpl.holdable = true
            AND ccs.holdable = true
            AND acp.deleted = false
            AND acpl.deleted = false
            AND acp.circ_lib IN (SELECT id FROM actor.org_unit_descendants(COALESCE($2,(SELECT id FROM evergreen.org_top()))))
        LIMIT 1;
    IF FOUND THEN
        RETURN true;
    END IF;
    RETURN FALSE;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.refresh_opac_visible_copies_mat_view () RETURNS VOID AS $$

    TRUNCATE TABLE asset.opac_visible_copies;

    INSERT INTO asset.opac_visible_copies (copy_id, circ_lib, record)
    SELECT  cp.id, cp.circ_lib, cn.record
    FROM  asset.copy cp
        JOIN asset.call_number cn ON (cn.id = cp.call_number)
        JOIN actor.org_unit a ON (cp.circ_lib = a.id)
        JOIN asset.copy_location cl ON (cp.location = cl.id)
        JOIN config.copy_status cs ON (cp.status = cs.id)
        JOIN biblio.record_entry b ON (cn.record = b.id)
    WHERE NOT cp.deleted
        AND NOT cl.deleted
        AND NOT cn.deleted
        AND NOT b.deleted
        AND cs.opac_visible
        AND cl.opac_visible
        AND cp.opac_visible
        AND a.opac_visible
            UNION
    SELECT  cp.id, cp.circ_lib, pbcm.peer_record AS record
    FROM  asset.copy cp
        JOIN biblio.peer_bib_copy_map pbcm ON (pbcm.target_copy = cp.id)
        JOIN actor.org_unit a ON (cp.circ_lib = a.id)
        JOIN asset.copy_location cl ON (cp.location = cl.id)
        JOIN config.copy_status cs ON (cp.status = cs.id)
    WHERE NOT cp.deleted
        AND NOT cl.deleted
        AND cs.opac_visible
        AND cl.opac_visible
        AND cp.opac_visible
        AND a.opac_visible;

$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION asset.cache_copy_visibility () RETURNS TRIGGER as $func$
DECLARE
    add_front       TEXT;
    add_back        TEXT;
    add_base_query  TEXT;
    add_peer_query  TEXT;
    remove_query    TEXT;
    do_add          BOOLEAN := false;
    do_remove       BOOLEAN := false;
BEGIN
    add_base_query := $$
        SELECT  cp.id, cp.circ_lib, cn.record, cn.id AS call_number, cp.location, cp.status
          FROM  asset.copy cp
                JOIN asset.call_number cn ON (cn.id = cp.call_number)
                JOIN actor.org_unit a ON (cp.circ_lib = a.id)
                JOIN asset.copy_location cl ON (cp.location = cl.id)
                JOIN config.copy_status cs ON (cp.status = cs.id)
                JOIN biblio.record_entry b ON (cn.record = b.id)
          WHERE NOT cp.deleted
                AND NOT cl.deleted
                AND NOT cn.deleted
                AND NOT b.deleted
                AND cs.opac_visible
                AND cl.opac_visible
                AND cp.opac_visible
                AND a.opac_visible
    $$;
    add_peer_query := $$
        SELECT  cp.id, cp.circ_lib, pbcm.peer_record AS record, NULL AS call_number, cp.location, cp.status
          FROM  asset.copy cp
                JOIN biblio.peer_bib_copy_map pbcm ON (pbcm.target_copy = cp.id)
                JOIN actor.org_unit a ON (cp.circ_lib = a.id)
                JOIN asset.copy_location cl ON (cp.location = cl.id)
                JOIN config.copy_status cs ON (cp.status = cs.id)
          WHERE NOT cp.deleted
                AND NOT cl.deleted
                AND cs.opac_visible
                AND cl.opac_visible
                AND cp.opac_visible
                AND a.opac_visible
    $$;
    add_front := $$
        INSERT INTO asset.opac_visible_copies (copy_id, circ_lib, record)
          SELECT DISTINCT ON (id, record) id, circ_lib, record FROM (
    $$;
    add_back := $$
        ) AS x
    $$;
 
    remove_query := $$ DELETE FROM asset.opac_visible_copies WHERE copy_id IN ( SELECT id FROM asset.copy WHERE $$;

    IF TG_TABLE_NAME = 'peer_bib_copy_map' THEN
        IF TG_OP = 'INSERT' THEN
            add_peer_query := add_peer_query || ' AND cp.id = ' || NEW.target_copy || ' AND pbcm.peer_record = ' || NEW.peer_record;
            EXECUTE add_front || add_peer_query || add_back;
            RETURN NEW;
        ELSE
            remove_query := 'DELETE FROM asset.opac_visible_copies WHERE copy_id = ' || OLD.target_copy || ' AND record = ' || OLD.peer_record || ';';
            EXECUTE remove_query;
            RETURN OLD;
        END IF;
    END IF;

    IF TG_OP = 'INSERT' THEN

        IF TG_TABLE_NAME IN ('copy', 'unit') THEN
            add_base_query := add_base_query || ' AND cp.id = ' || NEW.id;
            EXECUTE add_front || add_base_query || add_back;
        END IF;

        RETURN NEW;

    END IF;

    -- handle items first, since with circulation activity
    -- their statuses change frequently
    IF TG_TABLE_NAME IN ('copy', 'unit') THEN

        IF OLD.location    <> NEW.location OR
           OLD.call_number <> NEW.call_number OR
           OLD.status      <> NEW.status OR
           OLD.circ_lib    <> NEW.circ_lib THEN
            -- any of these could change visibility, but
            -- we'll save some queries and not try to calculate
            -- the change directly
            do_remove := true;
            do_add := true;
        ELSE

            IF OLD.deleted <> NEW.deleted THEN
                IF NEW.deleted THEN
                    do_remove := true;
                ELSE
                    do_add := true;
                END IF;
            END IF;

            IF OLD.opac_visible <> NEW.opac_visible THEN
                IF OLD.opac_visible THEN
                    do_remove := true;
                ELSIF NOT do_remove THEN -- handle edge case where deleted item
                                        -- is also marked opac_visible
                    do_add := true;
                END IF;
            END IF;

        END IF;

        IF do_remove THEN
            DELETE FROM asset.opac_visible_copies WHERE copy_id = NEW.id;
        END IF;
        IF do_add THEN
            add_base_query := add_base_query || ' AND cp.id = ' || NEW.id;
            add_peer_query := add_peer_query || ' AND cp.id = ' || NEW.id;
            EXECUTE add_front || add_base_query || ' UNION ' || add_peer_query || add_back;
        END IF;

        RETURN NEW;

    END IF;

    IF TG_TABLE_NAME IN ('call_number', 'copy_location', 'record_entry') THEN -- these have a 'deleted' column
 
        IF OLD.deleted AND NEW.deleted THEN -- do nothing

            RETURN NEW;
 
        ELSIF NEW.deleted THEN -- remove rows
 
            IF TG_TABLE_NAME = 'call_number' THEN
                DELETE FROM asset.opac_visible_copies WHERE copy_id IN (SELECT id FROM asset.copy WHERE call_number = NEW.id);
            ELSIF TG_TABLE_NAME = 'copy_location' THEN
                DELETE FROM asset.opac_visible_copies WHERE copy_id IN (SELECT id FROM asset.copy WHERE location = NEW.id);
            ELSIF TG_TABLE_NAME = 'record_entry' THEN
                DELETE FROM asset.opac_visible_copies WHERE record = NEW.id;
            END IF;
 
            RETURN NEW;
 
        ELSIF OLD.deleted THEN -- add rows
 
            IF TG_TABLE_NAME = 'call_number' THEN
                add_base_query := add_base_query || ' AND cn.id = ' || NEW.id;
                EXECUTE add_front || add_base_query || add_back;
            ELSIF TG_TABLE_NAME = 'copy_location' THEN
                add_base_query := add_base_query || 'AND cl.id = ' || NEW.id;
                EXECUTE add_front || add_base_query || add_back;
            ELSIF TG_TABLE_NAME = 'record_entry' THEN
                add_base_query := add_base_query || ' AND cn.record = ' || NEW.id;
                add_peer_query := add_peer_query || ' AND pbcm.peer_record = ' || NEW.id;
                EXECUTE add_front || add_base_query || ' UNION ' || add_peer_query || add_back;
            END IF;
 
            RETURN NEW;
 
        END IF;
 
    END IF;

    IF TG_TABLE_NAME = 'call_number' THEN

        IF OLD.record <> NEW.record THEN
            -- call number is linked to different bib
            remove_query := remove_query || 'call_number = ' || NEW.id || ');';
            EXECUTE remove_query;
            add_base_query := add_base_query || ' AND cn.id = ' || NEW.id;
            EXECUTE add_front || add_base_query || add_back;
        END IF;

        RETURN NEW;

    END IF;

    IF TG_TABLE_NAME IN ('record_entry') THEN
        RETURN NEW; -- don't have 'opac_visible'
    END IF;

    -- actor.org_unit, asset.copy_location, asset.copy_status
    IF NEW.opac_visible = OLD.opac_visible THEN -- do nothing

        RETURN NEW;

    ELSIF NEW.opac_visible THEN -- add rows

        IF TG_TABLE_NAME = 'org_unit' THEN
            add_base_query := add_base_query || ' AND cp.circ_lib = ' || NEW.id;
            add_peer_query := add_peer_query || ' AND cp.circ_lib = ' || NEW.id;
        ELSIF TG_TABLE_NAME = 'copy_location' THEN
            add_base_query := add_base_query || ' AND cp.location = ' || NEW.id;
            add_peer_query := add_peer_query || ' AND cp.location = ' || NEW.id;
        ELSIF TG_TABLE_NAME = 'copy_status' THEN
            add_base_query := add_base_query || ' AND cp.status = ' || NEW.id;
            add_peer_query := add_peer_query || ' AND cp.status = ' || NEW.id;
        END IF;
 
        EXECUTE add_front || add_base_query || ' UNION ' || add_peer_query || add_back;
 
    ELSE -- delete rows

        IF TG_TABLE_NAME = 'org_unit' THEN
            remove_query := 'DELETE FROM asset.opac_visible_copies WHERE circ_lib = ' || NEW.id || ';';
        ELSIF TG_TABLE_NAME = 'copy_location' THEN
            remove_query := remove_query || 'location = ' || NEW.id || ');';
        ELSIF TG_TABLE_NAME = 'copy_status' THEN
            remove_query := remove_query || 'status = ' || NEW.id || ');';
        END IF;
 
        EXECUTE remove_query;
 
    END IF;
 
    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

-- updated copy location validity test to disallow deleted locations
CREATE OR REPLACE FUNCTION vandelay.ingest_items ( import_id BIGINT, attr_def_id BIGINT ) RETURNS SETOF vandelay.import_item AS $$
DECLARE

    owning_lib      TEXT;
    circ_lib        TEXT;
    call_number     TEXT;
    copy_number     TEXT;
    status          TEXT;
    location        TEXT;
    circulate       TEXT;
    deposit         TEXT;
    deposit_amount  TEXT;
    ref             TEXT;
    holdable        TEXT;
    price           TEXT;
    barcode         TEXT;
    circ_modifier   TEXT;
    circ_as_type    TEXT;
    alert_message   TEXT;
    opac_visible    TEXT;
    pub_note        TEXT;
    priv_note       TEXT;
    internal_id     TEXT;

    attr_def        RECORD;
    tmp_attr_set    RECORD;
    attr_set        vandelay.import_item%ROWTYPE;

    xpath           TEXT;
    tmp_str         TEXT;

BEGIN

    SELECT * INTO attr_def FROM vandelay.import_item_attr_definition WHERE id = attr_def_id;

    IF FOUND THEN

        attr_set.definition := attr_def.id;

        -- Build the combined XPath

        owning_lib :=
            CASE
                WHEN attr_def.owning_lib IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.owning_lib ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.owning_lib || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.owning_lib
            END;

        circ_lib :=
            CASE
                WHEN attr_def.circ_lib IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circ_lib ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circ_lib || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circ_lib
            END;

        call_number :=
            CASE
                WHEN attr_def.call_number IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.call_number ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.call_number || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.call_number
            END;

        copy_number :=
            CASE
                WHEN attr_def.copy_number IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.copy_number ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.copy_number || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.copy_number
            END;

        status :=
            CASE
                WHEN attr_def.status IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.status ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.status || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.status
            END;

        location :=
            CASE
                WHEN attr_def.location IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.location ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.location || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.location
            END;

        circulate :=
            CASE
                WHEN attr_def.circulate IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circulate ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circulate || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circulate
            END;

        deposit :=
            CASE
                WHEN attr_def.deposit IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.deposit ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.deposit || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.deposit
            END;

        deposit_amount :=
            CASE
                WHEN attr_def.deposit_amount IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.deposit_amount ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.deposit_amount || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.deposit_amount
            END;

        ref :=
            CASE
                WHEN attr_def.ref IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.ref ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.ref || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.ref
            END;

        holdable :=
            CASE
                WHEN attr_def.holdable IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.holdable ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.holdable || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.holdable
            END;

        price :=
            CASE
                WHEN attr_def.price IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.price ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.price || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.price
            END;

        barcode :=
            CASE
                WHEN attr_def.barcode IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.barcode ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.barcode || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.barcode
            END;

        circ_modifier :=
            CASE
                WHEN attr_def.circ_modifier IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circ_modifier ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circ_modifier || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circ_modifier
            END;

        circ_as_type :=
            CASE
                WHEN attr_def.circ_as_type IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circ_as_type ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circ_as_type || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circ_as_type
            END;

        alert_message :=
            CASE
                WHEN attr_def.alert_message IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.alert_message ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.alert_message || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.alert_message
            END;

        opac_visible :=
            CASE
                WHEN attr_def.opac_visible IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.opac_visible ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.opac_visible || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.opac_visible
            END;

        pub_note :=
            CASE
                WHEN attr_def.pub_note IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.pub_note ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.pub_note || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.pub_note
            END;
        priv_note :=
            CASE
                WHEN attr_def.priv_note IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.priv_note ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.priv_note || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.priv_note
            END;

        internal_id :=
            CASE
                WHEN attr_def.internal_id IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.internal_id ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.internal_id || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.internal_id
            END;



        xpath :=
            owning_lib      || '|' ||
            circ_lib        || '|' ||
            call_number     || '|' ||
            copy_number     || '|' ||
            status          || '|' ||
            location        || '|' ||
            circulate       || '|' ||
            deposit         || '|' ||
            deposit_amount  || '|' ||
            ref             || '|' ||
            holdable        || '|' ||
            price           || '|' ||
            barcode         || '|' ||
            circ_modifier   || '|' ||
            circ_as_type    || '|' ||
            alert_message   || '|' ||
            pub_note        || '|' ||
            priv_note       || '|' ||
            internal_id     || '|' ||
            opac_visible;

        FOR tmp_attr_set IN
                SELECT  *
                  FROM  oils_xpath_table( 'id', 'marc', 'vandelay.queued_bib_record', xpath, 'id = ' || import_id )
                            AS t( id INT, ol TEXT, clib TEXT, cn TEXT, cnum TEXT, cs TEXT, cl TEXT, circ TEXT,
                                  dep TEXT, dep_amount TEXT, r TEXT, hold TEXT, pr TEXT, bc TEXT, circ_mod TEXT,
                                  circ_as TEXT, amessage TEXT, note TEXT, pnote TEXT, internal_id TEXT, opac_vis TEXT )
        LOOP

            attr_set.import_error := NULL;
            attr_set.error_detail := NULL;
            attr_set.deposit_amount := NULL;
            attr_set.copy_number := NULL;
            attr_set.price := NULL;
            attr_set.circ_modifier := NULL;
            attr_set.location := NULL;
            attr_set.barcode := NULL;
            attr_set.call_number := NULL;

            IF tmp_attr_set.pr != '' THEN
                tmp_str = REGEXP_REPLACE(tmp_attr_set.pr, E'[^0-9\\.]', '', 'g');
                IF tmp_str = '' THEN 
                    attr_set.import_error := 'import.item.invalid.price';
                    attr_set.error_detail := tmp_attr_set.pr; -- original value
                    RETURN NEXT attr_set; CONTINUE; 
                END IF;
                attr_set.price := tmp_str::NUMERIC(8,2); 
            END IF;

            IF tmp_attr_set.dep_amount != '' THEN
                tmp_str = REGEXP_REPLACE(tmp_attr_set.dep_amount, E'[^0-9\\.]', '', 'g');
                IF tmp_str = '' THEN 
                    attr_set.import_error := 'import.item.invalid.deposit_amount';
                    attr_set.error_detail := tmp_attr_set.dep_amount; 
                    RETURN NEXT attr_set; CONTINUE; 
                END IF;
                attr_set.deposit_amount := tmp_str::NUMERIC(8,2); 
            END IF;

            IF tmp_attr_set.cnum != '' THEN
                tmp_str = REGEXP_REPLACE(tmp_attr_set.cnum, E'[^0-9]', '', 'g');
                IF tmp_str = '' THEN 
                    attr_set.import_error := 'import.item.invalid.copy_number';
                    attr_set.error_detail := tmp_attr_set.cnum; 
                    RETURN NEXT attr_set; CONTINUE; 
                END IF;
                attr_set.copy_number := tmp_str::INT; 
            END IF;

            IF tmp_attr_set.ol != '' THEN
                SELECT id INTO attr_set.owning_lib FROM actor.org_unit WHERE shortname = UPPER(tmp_attr_set.ol); -- INT
                IF NOT FOUND THEN
                    attr_set.import_error := 'import.item.invalid.owning_lib';
                    attr_set.error_detail := tmp_attr_set.ol;
                    RETURN NEXT attr_set; CONTINUE; 
                END IF;
            END IF;

            IF tmp_attr_set.clib != '' THEN
                SELECT id INTO attr_set.circ_lib FROM actor.org_unit WHERE shortname = UPPER(tmp_attr_set.clib); -- INT
                IF NOT FOUND THEN
                    attr_set.import_error := 'import.item.invalid.circ_lib';
                    attr_set.error_detail := tmp_attr_set.clib;
                    RETURN NEXT attr_set; CONTINUE; 
                END IF;
            END IF;

            IF tmp_attr_set.cs != '' THEN
                SELECT id INTO attr_set.status FROM config.copy_status WHERE LOWER(name) = LOWER(tmp_attr_set.cs); -- INT
                IF NOT FOUND THEN
                    attr_set.import_error := 'import.item.invalid.status';
                    attr_set.error_detail := tmp_attr_set.cs;
                    RETURN NEXT attr_set; CONTINUE; 
                END IF;
            END IF;

            IF COALESCE(tmp_attr_set.circ_mod, '') = '' THEN

                -- no circ mod defined, see if we should apply a default
                SELECT INTO attr_set.circ_modifier TRIM(BOTH '"' FROM value) 
                    FROM actor.org_unit_ancestor_setting(
                        'vandelay.item.circ_modifier.default', 
                        attr_set.owning_lib
                    );

                -- make sure the value from the org setting is still valid
                PERFORM 1 FROM config.circ_modifier WHERE code = attr_set.circ_modifier;
                IF NOT FOUND THEN
                    attr_set.import_error := 'import.item.invalid.circ_modifier';
                    attr_set.error_detail := tmp_attr_set.circ_mod;
                    RETURN NEXT attr_set; CONTINUE; 
                END IF;

            ELSE 

                SELECT code INTO attr_set.circ_modifier FROM config.circ_modifier WHERE code = tmp_attr_set.circ_mod;
                IF NOT FOUND THEN
                    attr_set.import_error := 'import.item.invalid.circ_modifier';
                    attr_set.error_detail := tmp_attr_set.circ_mod;
                    RETURN NEXT attr_set; CONTINUE; 
                END IF;
            END IF;

            IF tmp_attr_set.circ_as != '' THEN
                SELECT code INTO attr_set.circ_as_type FROM config.coded_value_map WHERE ctype = 'item_type' AND code = tmp_attr_set.circ_as;
                IF NOT FOUND THEN
                    attr_set.import_error := 'import.item.invalid.circ_as_type';
                    attr_set.error_detail := tmp_attr_set.circ_as;
                    RETURN NEXT attr_set; CONTINUE; 
                END IF;
            END IF;

            IF COALESCE(tmp_attr_set.cl, '') = '' THEN
                -- no location specified, see if we should apply a default

                SELECT INTO attr_set.location TRIM(BOTH '"' FROM value) 
                    FROM actor.org_unit_ancestor_setting(
                        'vandelay.item.copy_location.default', 
                        attr_set.owning_lib
                    );

                -- make sure the value from the org setting is still valid
                PERFORM 1 FROM asset.copy_location 
                    WHERE id = attr_set.location AND NOT deleted;
                IF NOT FOUND THEN
                    attr_set.import_error := 'import.item.invalid.location';
                    attr_set.error_detail := tmp_attr_set.cs;
                    RETURN NEXT attr_set; CONTINUE; 
                END IF;
            ELSE

                -- search up the org unit tree for a matching copy location
                WITH RECURSIVE anscestor_depth AS (
                    SELECT  ou.id,
                        out.depth AS depth,
                        ou.parent_ou
                    FROM  actor.org_unit ou
                        JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                    WHERE ou.id = COALESCE(attr_set.owning_lib, attr_set.circ_lib)
                        UNION ALL
                    SELECT  ou.id,
                        out.depth,
                        ou.parent_ou
                    FROM  actor.org_unit ou
                        JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                        JOIN anscestor_depth ot ON (ot.parent_ou = ou.id)
                ) SELECT  cpl.id INTO attr_set.location
                    FROM  anscestor_depth a
                        JOIN asset.copy_location cpl ON (cpl.owning_lib = a.id)
                    WHERE LOWER(cpl.name) = LOWER(tmp_attr_set.cl) 
                        AND NOT cpl.deleted
                    ORDER BY a.depth DESC
                    LIMIT 1; 

                IF NOT FOUND THEN
                    attr_set.import_error := 'import.item.invalid.location';
                    attr_set.error_detail := tmp_attr_set.cs;
                    RETURN NEXT attr_set; CONTINUE; 
                END IF;
            END IF;

            attr_set.circulate      :=
                LOWER( SUBSTRING( tmp_attr_set.circ, 1, 1)) IN ('t','y','1')
                OR LOWER(tmp_attr_set.circ) = 'circulating'; -- BOOL

            attr_set.deposit        :=
                LOWER( SUBSTRING( tmp_attr_set.dep, 1, 1 ) ) IN ('t','y','1')
                OR LOWER(tmp_attr_set.dep) = 'deposit'; -- BOOL

            attr_set.holdable       :=
                LOWER( SUBSTRING( tmp_attr_set.hold, 1, 1 ) ) IN ('t','y','1')
                OR LOWER(tmp_attr_set.hold) = 'holdable'; -- BOOL

            attr_set.opac_visible   :=
                LOWER( SUBSTRING( tmp_attr_set.opac_vis, 1, 1 ) ) IN ('t','y','1')
                OR LOWER(tmp_attr_set.opac_vis) = 'visible'; -- BOOL

            attr_set.ref            :=
                LOWER( SUBSTRING( tmp_attr_set.r, 1, 1 ) ) IN ('t','y','1')
                OR LOWER(tmp_attr_set.r) = 'reference'; -- BOOL

            attr_set.call_number    := tmp_attr_set.cn; -- TEXT
            attr_set.barcode        := tmp_attr_set.bc; -- TEXT,
            attr_set.alert_message  := tmp_attr_set.amessage; -- TEXT,
            attr_set.pub_note       := tmp_attr_set.note; -- TEXT,
            attr_set.priv_note      := tmp_attr_set.pnote; -- TEXT,
            attr_set.alert_message  := tmp_attr_set.amessage; -- TEXT,
            attr_set.internal_id    := tmp_attr_set.internal_id::BIGINT;

            RETURN NEXT attr_set;

        END LOOP;

    END IF;

    RETURN;

END;
$$ LANGUAGE PLPGSQL;





SELECT evergreen.upgrade_deps_block_check('0915', :eg_version);

INSERT INTO permission.perm_list (id, code, description) 
VALUES (  
    560, 
    'TOTAL_HOLD_COPY_RATIO_EXCEEDED.override',
    oils_i18n_gettext(
        560,
        'Override the TOTAL_HOLD_COPY_RATIO_EXCEEDED event',
        'ppl', 
        'description'
    )
);

INSERT INTO permission.perm_list (id, code, description) 
VALUES (  
    561, 
    'AVAIL_HOLD_COPY_RATIO_EXCEEDED.override',
    oils_i18n_gettext(
        561,
        'Override the AVAIL_HOLD_COPY_RATIO_EXCEEDED event',
        'ppl', 
        'description'
    )
);

COMMIT;
