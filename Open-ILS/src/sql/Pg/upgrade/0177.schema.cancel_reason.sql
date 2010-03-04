BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0177'); -- Scott McKellar

CREATE TABLE acq.cancel_reason (
	id            SERIAL            PRIMARY KEY,
	org_unit      INTEGER           NOT NULL REFERENCES actor.org_unit( id )
	                                DEFERRABLE INITIALLY DEFERRED,
	label         TEXT              NOT NULL,
	description   TEXT              NOT NULL,
	CONSTRAINT acq_cancel_reason_one_per_org_unit UNIQUE( org_unit, label )
);

-- Reserve ids 1-999 for stock reasons
-- Reserve ids 1000-1999 for EDI reasons
-- 2000+ are available for staff to create

SELECT SETVAL('acq.cancel_reason_id_seq'::TEXT, 2000);

ALTER TABLE acq.purchase_order
	ADD COLUMN cancel_reason        INT REFERENCES acq.cancel_reason( id )
	                                    DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE acq.lineitem
	ADD COLUMN cancel_reason        INT REFERENCES acq.cancel_reason( id )
	                                    DEFERRABLE INITIALLY DEFERRED;

COMMIT;
