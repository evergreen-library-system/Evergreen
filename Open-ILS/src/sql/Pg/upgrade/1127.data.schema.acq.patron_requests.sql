BEGIN;

SELECT evergreen.upgrade_deps_block_check('1127', :eg_version);

ALTER TABLE acq.user_request ADD COLUMN cancel_time TIMESTAMPTZ;
ALTER TABLE acq.user_request ADD COLUMN upc TEXT;
ALTER TABLE action.hold_request ADD COLUMN acq_request INT REFERENCES acq.user_request (id);

UPDATE
    config.org_unit_setting_type
SET
    label = oils_i18n_gettext(
        'circ.holds.canceled.display_age',
        'Canceled holds/requests display age',
        'coust', 'label'),
    description = oils_i18n_gettext(
        'circ.holds.canceled.display_age',
        'Show all canceled entries in patron holds and patron acquisition requests interfaces that were canceled within this amount of time',
        'coust', 'description')
WHERE
    name = 'circ.holds.canceled.display_age'
;

UPDATE
    config.org_unit_setting_type
SET
    label = oils_i18n_gettext(
        'circ.holds.canceled.display_count',
        'Canceled holds/requests display count',
        'coust', 'label'),
    description = oils_i18n_gettext(
        'circ.holds.canceled.display_count',
        'How many canceled entries to show in patron holds and patron acquisition requests interfaces',
        'coust', 'description')
WHERE
    name = 'circ.holds.canceled.display_count'
;

INSERT INTO acq.cancel_reason (org_unit, keep_debits, id, label, description)
    VALUES (
        1, 'f', 1015,
        oils_i18n_gettext(1015, 'Canceled: Fulfilled', 'acqcr', 'label'),
        oils_i18n_gettext(1015, 'This acquisition request has been fulfilled.', 'acqcr', 'description')
    )
;

UPDATE
    acq.user_request_type
SET
    label = oils_i18n_gettext('2', 'Articles', 'aurt', 'label')
WHERE
    id = 2
;

INSERT INTO acq.user_request_type (id,label)
    SELECT 6, oils_i18n_gettext('6', 'Other', 'aurt', 'label');

SELECT SETVAL('acq.user_request_type_id_seq'::TEXT, (SELECT MAX(id)+1 FROM acq.user_request_type));

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 610, 'CLEAR_PURCHASE_REQUEST', oils_i18n_gettext(610,
    'Clear Completed User Purchase Requests', 'ppl', 'description'))
;

CREATE TABLE acq.user_request_status_type (
     id  SERIAL  PRIMARY KEY
    ,label TEXT
);

INSERT INTO acq.user_request_status_type (id,label) VALUES
     (0,oils_i18n_gettext(0,'Error','aurst','label'))
    ,(1,oils_i18n_gettext(1,'New','aurst','label'))
    ,(2,oils_i18n_gettext(2,'Pending','aurst','label'))
    ,(3,oils_i18n_gettext(3,'Ordered, Hold Not Placed','aurst','label'))
    ,(4,oils_i18n_gettext(4,'Ordered, Hold Placed','aurst','label'))
    ,(5,oils_i18n_gettext(5,'Received','aurst','label'))
    ,(6,oils_i18n_gettext(6,'Fulfilled','aurst','label'))
    ,(7,oils_i18n_gettext(7,'Canceled','aurst','label'))
;

SELECT SETVAL('acq.user_request_status_type_id_seq'::TEXT, 100);

-- not used
DELETE FROM actor.org_unit_setting WHERE name = 'acq.holds.allow_holds_from_purchase_request';
DELETE FROM config.org_unit_setting_type_log WHERE field_name = 'acq.holds.allow_holds_from_purchase_request';
DELETE FROM config.org_unit_setting_type WHERE name = 'acq.holds.allow_holds_from_purchase_request';

COMMIT;
