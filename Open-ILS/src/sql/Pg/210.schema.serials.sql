

DROP SCHEMA serial CASCADE;

BEGIN;

CREATE SCHEMA serial;

CREATE TABLE serial.subscription (
	id		SERIAL	PRIMARY KEY,
	callnumber	BIGINT	REFERENCES asset.call_number (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
	uri		INT	REFERENCES asset.uri (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
	start_date	DATE	NOT NULL,
	end_date	DATE	NOT NULL
);

CREATE TABLE serial.binding_unit (
	id		SERIAL	PRIMARY KEY,
	subscription	INT	NOT NULL REFERENCES serial.subscription (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	label		TEXT	NOT NULL,
	CONSTRAINT bu_label_once_per_sub UNIQUE (subscription, label)
);

CREATE TABLE serial.issuance (
	id		SERIAL	PRIMARY KEY,
	subscription	INT	NOT NULL REFERENCES serial.subscription (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	target_copy	BIGINT	REFERENCES asset.copy (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	binding_unit	INT	REFERENCES serial.binding_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	label		TEXT
);

CREATE TABLE serial.bib_summary (
	id			SERIAL	PRIMARY KEY,
	call_number		INT	UNIQUE NOT NULL REFERENCES serial.subscription (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	generated_coverage	TEXT	NOT NULL,
	textual_holdings	TEXT
);

CREATE TABLE serial.sup_summary (
	id			SERIAL	PRIMARY KEY,
	call_number		INT	UNIQUE NOT NULL REFERENCES serial.subscription (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	generated_coverage	TEXT	NOT NULL,
	textual_holdings	TEXT
);

CREATE TABLE serial.index_summary (
	id			SERIAL	PRIMARY KEY,
	call_number		INT	UNIQUE NOT NULL REFERENCES serial.subscription (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	generated_coverage	TEXT	NOT NULL,
	textual_holdings	TEXT
);

COMMIT;

