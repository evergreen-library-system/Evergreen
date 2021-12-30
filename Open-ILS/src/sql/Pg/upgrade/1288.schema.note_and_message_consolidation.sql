BEGIN;

SELECT evergreen.upgrade_deps_block_check('1288', :eg_version);

-- stage a copy of notes, temporarily setting
-- the id to the negative value for later ausp
-- id munging
CREATE TABLE actor.XXXX_penalty_notes AS
    SELECT id * -1 AS id, usr, org_unit, set_date, note
    FROM actor.usr_standing_penalty
    WHERE NULLIF(BTRIM(note),'') IS NOT NULL;

ALTER TABLE actor.usr_standing_penalty ALTER COLUMN id SET DEFAULT nextval('actor.usr_message_id_seq'::regclass);
ALTER TABLE actor.usr_standing_penalty ADD COLUMN usr_message BIGINT REFERENCES actor.usr_message(id);
CREATE INDEX usr_standing_penalty_usr_message_idx ON actor.usr_standing_penalty (usr_message);
ALTER TABLE actor.usr_standing_penalty DROP COLUMN note;

-- munge ausp IDs and aum IDs so that they're disjoint sets
UPDATE actor.usr_standing_penalty SET id = id * -1; -- move them out of the way to avoid mid-statement collisions

WITH messages AS ( SELECT COALESCE(MAX(id), 0) AS max_id FROM actor.usr_message )
UPDATE actor.usr_standing_penalty SET id = id * -1 + messages.max_id FROM messages;

-- doing the same thing to the staging table because
-- we had to grab a copy of ausp.note first. We had
-- to grab that copy first because we're both ALTERing
-- and UPDATEing ausp, and all of the ALTER TABLEs
-- have to be done before we can modify data in the table
-- lest ALTER TABLE gets blocked by a pending trigger
-- event
WITH messages AS ( SELECT COALESCE(MAX(id), 0) AS max_id FROM actor.usr_message )
UPDATE actor.XXXX_penalty_notes SET id = id * -1 + messages.max_id FROM messages;

SELECT SETVAL('actor.usr_message_id_seq'::regclass, COALESCE((SELECT MAX(id) FROM actor.usr_standing_penalty) + 1, 1), FALSE);

ALTER TABLE actor.usr_message ADD COLUMN pub BOOL NOT NULL DEFAULT FALSE;
ALTER TABLE actor.usr_message ADD COLUMN stop_date TIMESTAMP WITH TIME ZONE;
ALTER TABLE actor.usr_message ADD COLUMN editor	BIGINT REFERENCES actor.usr (id);
ALTER TABLE actor.usr_message ADD COLUMN edit_date TIMESTAMP WITH TIME ZONE;

DROP VIEW actor.usr_message_limited;
CREATE VIEW actor.usr_message_limited
AS SELECT * FROM actor.usr_message WHERE pub AND NOT deleted;

-- alright, let's set all existing user messages to public

UPDATE actor.usr_message SET pub = TRUE;

-- alright, let's migrate penalty notes to usr_messages and link the messages back to the penalties:

-- here is our staging table which will be shaped exactly like
-- actor.usr_message and use the same id sequence
CREATE TABLE actor.XXXX_usr_message_for_penalty_notes (
    LIKE actor.usr_message INCLUDING DEFAULTS 
);

INSERT INTO actor.XXXX_usr_message_for_penalty_notes (
    usr,
    title,
    message,
    create_date,
    sending_lib,
    pub
) SELECT
    usr,
    'Penalty Note ID ' || id,
    note,
    set_date,
    org_unit,
    FALSE
FROM
    actor.XXXX_penalty_notes
;

-- so far so good, let's push this into production

INSERT INTO actor.usr_message
    SELECT * FROM actor.XXXX_usr_message_for_penalty_notes;

-- and link the production penalties to these new user messages

UPDATE actor.usr_standing_penalty p SET usr_message = m.id
    FROM actor.XXXX_usr_message_for_penalty_notes m
    WHERE m.title = 'Penalty Note ID ' || p.id;

-- and remove the temporary overloading of the message title we used for this:

UPDATE
    actor.usr_message
SET
    title = message
WHERE
    id IN (SELECT id FROM actor.XXXX_usr_message_for_penalty_notes)
;

-- probably redundant here, but the spec calls for an assertion before removing
-- the note column from actor.usr_standing_penalty, so being extra cautious:
/*
do $$ begin
    assert (
        select count(*)
        from actor.XXXX_usr_message_for_penalty_notes
        where id not in (
            select id from actor.usr_message
        )
    ) = 0, 'failed migrating to actor.usr_message';
end; $$;
*/

-- combined view of actor.usr_standing_penalty and actor.usr_message for populating
-- staff Notes (formerly Messages) interface

CREATE VIEW actor.usr_message_penalty AS
SELECT -- ausp with or without messages
    ausp.id AS "id",
    ausp.id AS "ausp_id",
    aum.id AS "aum_id",
    ausp.org_unit AS "org_unit",
    ausp.org_unit AS "ausp_org_unit",
    aum.sending_lib AS "aum_sending_lib",
    ausp.usr AS "usr",
    ausp.usr as "ausp_usr",
    aum.usr as "aum_usr",
    ausp.standing_penalty AS "standing_penalty",
    ausp.staff AS "staff",
    ausp.set_date AS "create_date",
    ausp.set_date AS "ausp_set_date",
    aum.create_date AS "aum_create_date",
    ausp.stop_date AS "stop_date",
    ausp.stop_date AS "ausp_stop_date",
    aum.stop_date AS "aum_stop_date",
    ausp.usr_message AS "ausp_usr_message",
    aum.title AS "title",
    aum.message AS "message",
    aum.deleted AS "deleted",
    aum.read_date AS "read_date",
    aum.pub AS "pub",
    aum.editor AS "editor",
    aum.edit_date AS "edit_date"
FROM
    actor.usr_standing_penalty ausp
    LEFT JOIN actor.usr_message aum ON (ausp.usr_message = aum.id)
        UNION ALL
SELECT -- aum without penalties
    aum.id AS "id",
    NULL::INT AS "ausp_id",
    aum.id AS "aum_id",
    aum.sending_lib AS "org_unit",
    NULL::INT AS "ausp_org_unit",
    aum.sending_lib AS "aum_sending_lib",
    aum.usr AS "usr",
    NULL::INT as "ausp_usr",
    aum.usr as "aum_usr",
    NULL::INT AS "standing_penalty",
    NULL::INT AS "staff",
    aum.create_date AS "create_date",
    NULL::TIMESTAMPTZ AS "ausp_set_date",
    aum.create_date AS "aum_create_date",
    aum.stop_date AS "stop_date",
    NULL::TIMESTAMPTZ AS "ausp_stop_date",
    aum.stop_date AS "aum_stop_date",
    NULL::INT AS "ausp_usr_message",
    aum.title AS "title",
    aum.message AS "message",
    aum.deleted AS "deleted",
    aum.read_date AS "read_date",
    aum.pub AS "pub",
    aum.editor AS "editor",
    aum.edit_date AS "edit_date"
FROM
    actor.usr_message aum
    LEFT JOIN actor.usr_standing_penalty ausp ON (ausp.usr_message = aum.id)
WHERE NOT aum.deleted AND ausp.id IS NULL
;

-- fun part where we migrate the following alert messages:

CREATE TABLE actor.XXXX_note_and_message_consolidation AS
    SELECT id, home_ou, alert_message
    FROM actor.usr
    WHERE NOT deleted AND NULLIF(BTRIM(alert_message),'') IS NOT NULL;

-- here is our staging table which will be shaped exactly like
-- actor.usr_message and use the same id sequence
CREATE TABLE actor.XXXX_usr_message (
    LIKE actor.usr_message INCLUDING DEFAULTS 
);

INSERT INTO actor.XXXX_usr_message (
    usr,
    title,
    message,
    create_date,
    sending_lib,
    pub
) SELECT
    id,
    'converted Alert Message, real date unknown',
    alert_message,
    NOW(), -- best we can do
    1, -- it's this or home_ou
    FALSE
FROM
    actor.XXXX_note_and_message_consolidation
;

-- another staging table, but for actor.usr_standing_penalty
CREATE TABLE actor.XXXX_usr_standing_penalty (
    LIKE actor.usr_standing_penalty INCLUDING DEFAULTS 
);

INSERT INTO actor.XXXX_usr_standing_penalty (
    org_unit,
    usr,
    standing_penalty,
    staff,
    set_date,
    usr_message
) SELECT
    sending_lib,
    usr,
    20, -- ALERT_NOTE
    1, -- admin user, usually; best we can do
    create_date,
    id
FROM
    actor.XXXX_usr_message
;

-- so far so good, let's push these into production

INSERT INTO actor.usr_message
    SELECT * FROM actor.XXXX_usr_message;
INSERT INTO actor.usr_standing_penalty
    SELECT * FROM actor.XXXX_usr_standing_penalty;

-- probably redundant here, but the spec calls for an assertion before removing
-- the alert message column from actor.usr, so being extra cautious:
/*
do $$ begin
    assert (
        select count(*)
        from actor.XXXX_usr_message
        where id not in (
            select id from actor.usr_message
        )
    ) = 0, 'failed migrating to actor.usr_message';
end; $$;

do $$ begin
    assert (
        select count(*)
        from actor.XXXX_usr_standing_penalty
        where id not in (
            select id from actor.usr_standing_penalty
        )
    ) = 0, 'failed migrating to actor.usr_standing_penalty';
end; $$;
*/

-- WARNING: we're going to lose the history of alert_message
ALTER TABLE actor.usr DROP COLUMN alert_message CASCADE;
SELECT auditor.update_auditors();

-- fun part where we migrate actor.usr_notes as penalties to preserve
-- their creator, and then the private ones to private user messages.
-- For public notes, we try to link to existing user messages if we
-- can, but if we can't, we'll create new, but archived, user messages
-- for the note contents.

CREATE TABLE actor.XXXX_usr_message_for_private_notes (
    LIKE actor.usr_message INCLUDING DEFAULTS 
);
ALTER TABLE actor.XXXX_usr_message_for_private_notes ADD COLUMN orig_id BIGINT;
CREATE INDEX ON actor.XXXX_usr_message_for_private_notes (orig_id);

INSERT INTO actor.XXXX_usr_message_for_private_notes (
    orig_id,
    usr,
    title,
    message,
    create_date,
    sending_lib,
    pub
) SELECT
    id,
    usr,
    title,
    value,
    create_date,
    (select home_ou from actor.usr where id = creator), -- best we can do
    FALSE
FROM
    actor.usr_note
WHERE
    NOT pub
;

CREATE TABLE actor.XXXX_usr_message_for_unmatched_public_notes (
    LIKE actor.usr_message INCLUDING DEFAULTS 
);
ALTER TABLE actor.XXXX_usr_message_for_unmatched_public_notes ADD COLUMN orig_id BIGINT;
CREATE INDEX ON actor.XXXX_usr_message_for_unmatched_public_notes (orig_id);

INSERT INTO actor.XXXX_usr_message_for_unmatched_public_notes (
    orig_id,
    usr,
    title,
    message,
    create_date,
    deleted,
    sending_lib,
    pub
) SELECT
    id,
    usr,
    title,
    value,
    create_date,
    TRUE, -- the patron has likely already seen and deleted the corresponding usr_message
    (select home_ou from actor.usr where id = creator), -- best we can do
    FALSE
FROM
    actor.usr_note n
WHERE
    pub AND NOT EXISTS (SELECT 1 FROM actor.usr_message m WHERE n.usr = m.usr AND n.create_date = m.create_date)
;

-- now, in order to preserve the creator from usr_note, we want to create standing SILENT_NOTE penalties for
--  1) actor.XXXX_usr_message_for_private_notes and associated usr_note entries
--  2) actor.XXXX_usr_message_for_unmatched_public_notes and associated usr_note entries, but archive these
--  3) usr_note and usr_message entries that can be matched

CREATE TABLE actor.XXXX_usr_standing_penalties_for_notes (
    LIKE actor.usr_standing_penalty INCLUDING DEFAULTS 
);

--  1) actor.XXXX_usr_message_for_private_notes and associated usr_note entries
INSERT INTO actor.XXXX_usr_standing_penalties_for_notes (
    org_unit,
    usr,
    standing_penalty,
    staff,
    set_date,
    stop_date,
    usr_message
) SELECT
    m.sending_lib,
    m.usr,
    21, -- SILENT_NOTE
    n.creator,
    m.create_date,
    m.stop_date,
    m.id
FROM
    actor.usr_note n,
    actor.XXXX_usr_message_for_private_notes m
WHERE
    n.usr = m.usr AND n.id = m.orig_id AND NOT n.pub AND NOT m.pub
;

--  2) actor.XXXX_usr_message_for_unmatched_public_notes and associated usr_note entries, but archive these
INSERT INTO actor.XXXX_usr_standing_penalties_for_notes (
    org_unit,
    usr,
    standing_penalty,
    staff,
    set_date,
    stop_date,
    usr_message
) SELECT
    m.sending_lib,
    m.usr,
    21, -- SILENT_NOTE
    n.creator,
    m.create_date,
    m.stop_date,
    m.id
FROM
    actor.usr_note n,
    actor.XXXX_usr_message_for_unmatched_public_notes m
WHERE
    n.usr = m.usr AND n.id = m.orig_id AND n.pub AND m.pub
;

--  3) usr_note and usr_message entries that can be matched
INSERT INTO actor.XXXX_usr_standing_penalties_for_notes (
    org_unit,
    usr,
    standing_penalty,
    staff,
    set_date,
    stop_date,
    usr_message
) SELECT
    m.sending_lib,
    m.usr,
    21, -- SILENT_NOTE
    n.creator,
    m.create_date,
    m.stop_date,
    m.id
FROM
    actor.usr_note n
    JOIN actor.usr_message m ON (n.usr = m.usr AND n.id = m.id)
WHERE
    NOT EXISTS ( SELECT 1 FROM actor.XXXX_usr_message_for_private_notes WHERE id = m.id )
    AND NOT EXISTS ( SELECT 1 FROM actor.XXXX_usr_message_for_unmatched_public_notes WHERE id = m.id )
;

-- so far so good, let's push these into production

INSERT INTO actor.usr_message
    SELECT id, usr, title, message, create_date, deleted, read_date, sending_lib, pub, stop_date, editor, edit_date FROM actor.XXXX_usr_message_for_private_notes
    UNION SELECT id, usr, title, message, create_date, deleted, read_date, sending_lib, pub, stop_date, editor, edit_date FROM actor.XXXX_usr_message_for_unmatched_public_notes;
INSERT INTO actor.usr_standing_penalty
    SELECT * FROM actor.XXXX_usr_standing_penalties_for_notes;

-- probably redundant here, but the spec calls for an assertion before dropping
-- the actor.usr_note table, so being extra cautious:
/*
do $$ begin
    assert (
        select count(*)
        from actor.XXXX_usr_message_for_private_notes
        where id not in (
            select id from actor.usr_message
        )
    ) = 0, 'failed migrating to actor.usr_message';
end; $$;
*/

DROP TABLE actor.usr_note CASCADE;

-- preserve would-be collisions for migrating
-- ui.staff.require_initials.patron_info_notes
-- to ui.staff.require_initials.patron_standing_penalty

\o ui.staff.require_initials.patron_info_notes.collisions.txt
SELECT a.*
FROM actor.org_unit_setting a
WHERE
        a.name = 'ui.staff.require_initials.patron_info_notes'
    -- hits on org_unit
    AND a.org_unit IN (
        SELECT b.org_unit
        FROM actor.org_unit_setting b
        WHERE b.name = 'ui.staff.require_initials.patron_standing_penalty'
    )
    -- but doesn't hit on org_unit + value
    AND CONCAT_WS('|',a.org_unit::TEXT,a.value::TEXT) NOT IN (
        SELECT CONCAT_WS('|',b.org_unit::TEXT,b.value::TEXT)
        FROM actor.org_unit_setting b
        WHERE b.name = 'ui.staff.require_initials.patron_standing_penalty'
    );
\o

-- and preserve the _log data

\o ui.staff.require_initials.patron_info_notes.log_data.txt
SELECT *
FROM config.org_unit_setting_type_log
WHERE field_name = 'ui.staff.require_initials.patron_info_notes';
\o

-- migrate the non-collisions

INSERT INTO actor.org_unit_setting (org_unit, name, value)
SELECT a.org_unit, 'ui.staff.require_initials.patron_standing_penalty', a.value
FROM actor.org_unit_setting a
WHERE
        a.name = 'ui.staff.require_initials.patron_info_notes'
    AND a.org_unit NOT IN (
        SELECT b.org_unit
        FROM actor.org_unit_setting b
        WHERE b.name = 'ui.staff.require_initials.patron_standing_penalty'
    )
;

-- and now delete the old patron_info_notes settings

DELETE FROM actor.org_unit_setting
    WHERE name = 'ui.staff.require_initials.patron_info_notes';
DELETE FROM config.org_unit_setting_type_log
    WHERE field_name = 'ui.staff.require_initials.patron_info_notes';
DELETE FROM config.org_unit_setting_type
    WHERE name = 'ui.staff.require_initials.patron_info_notes';

-- relabel the org unit setting type

UPDATE config.org_unit_setting_type
SET
    label = oils_i18n_gettext('ui.staff.require_initials.patron_standing_penalty',
        'Require staff initials for entry/edit of patron standing penalties and notes.',
        'coust', 'label'),
    description = oils_i18n_gettext('ui.staff.require_initials.patron_standing_penalty',
        'Require staff initials for entry/edit of patron standing penalties and notes.',
        'coust', 'description')
WHERE
    name = 'ui.staff.require_initials.patron_standing_penalty'
;

-- preserve _log data for some different settings on their way out

\o ui.patron.edit.au.alert_message.show_suggest.log_data.txt
SELECT *
FROM config.org_unit_setting_type_log
WHERE field_name IN (
    'ui.patron.edit.au.alert_message.show',
    'ui.patron.edit.au.alert_message.suggest'
);
\o

-- remove patron editor alert message settings

DELETE FROM actor.org_unit_setting
    WHERE name = 'ui.patron.edit.au.alert_message.show';
DELETE FROM config.org_unit_setting_type_log
    WHERE field_name = 'ui.patron.edit.au.alert_message.show';
DELETE FROM config.org_unit_setting_type
    WHERE name = 'ui.patron.edit.au.alert_message.show';

DELETE FROM actor.org_unit_setting
    WHERE name = 'ui.patron.edit.au.alert_message.suggest';
DELETE FROM config.org_unit_setting_type_log
    WHERE field_name = 'ui.patron.edit.au.alert_message.suggest';
DELETE FROM config.org_unit_setting_type
    WHERE name = 'ui.patron.edit.au.alert_message.suggest';

-- comment these out if you want the staging tables to stick around
DROP TABLE actor.XXXX_note_and_message_consolidation;
DROP TABLE actor.XXXX_penalty_notes;
DROP TABLE actor.XXXX_usr_message_for_penalty_notes;
DROP TABLE actor.XXXX_usr_message;
DROP TABLE actor.XXXX_usr_standing_penalty;
DROP TABLE actor.XXXX_usr_message_for_private_notes;
DROP TABLE actor.XXXX_usr_message_for_unmatched_public_notes;
DROP TABLE actor.XXXX_usr_standing_penalties_for_notes;

COMMIT;

