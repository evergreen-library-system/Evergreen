BEGIN;

SELECT evergreen.upgrade_deps_block_check('1363', :eg_version);

ALTER TABLE action.hold_request_cancel_cause
  ADD COLUMN manual BOOL NOT NULL DEFAULT FALSE;

UPDATE action.hold_request_cancel_cause SET manual = TRUE
  WHERE id IN (
    2, -- Hold Shelf expiration
    3, -- Patron via phone
    4, -- Patron in person
    5  -- Staff forced
  );

INSERT INTO action.hold_request_cancel_cause (id, label, manual)
  VALUES (9, oils_i18n_gettext(9, 'Patron via email', 'ahrcc', 'label'), TRUE);

INSERT INTO action.hold_request_cancel_cause (id, label, manual)
  VALUES (10, oils_i18n_gettext(10, 'Patron via SMS', 'ahrcc', 'label'), TRUE);

COMMIT;
