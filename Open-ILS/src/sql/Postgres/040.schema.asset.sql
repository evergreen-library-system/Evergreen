DROP SCHEMA asset CASCADE;

BEGIN;

CREATE SCHEMA asset;

CREATE TABLE asset.copy (
	id		BIGSERIAL PRIMARY KEY,
	creator		BIGINT				NOT NULL,
	create_date	TIMESTAMP WITH TIME ZONE	DEFAULT NOW(),
	editor		BIGINT				NOT NULL,
	edit_date	TIMESTAMP WITH TIME ZONE	DEFAULT NOW(),
	barcode		TEXT,
	call_number	BIGINT,
	copy_number	INT,
	available	BOOL NOT NULL DEFAULT TRUE, -- was STATUS
	loan_duration	INT,
	fine_level	INT,
	circulate	BOOL NOT NULL DEFAULT TRUE,
	deposit		BOOL NOT NULL DEFAULT FALSE,
	deposit_amount	NUMERIC(6,2) NOT NULL DEFAULT 0.00,
	price		NUMERIC(8,2) NOT NULL DEFAULT 0.00,
	ref		BOOL NOT NULL DEFAULT FALSE,
	circ_modifier	TEXT,
	circ_as_type	TEXT,
	opac_visible	BOOL NOT NULL DEFAULT TRUE
);
CREATE INDEX cp_cn_idx ON asset.copy (call_number);

CREATE TABLE asset.stat_cat (
	id		SERIAL	PRIMARY KEY,
	owner		INT	NOT NULL, -- actor.org_unit.id
	name		TEXT	NOT NULL,
	opac_visible	BOOL NOT NULL DEFAULT FALSE,
	CONSTRAINT sc_once_per_owner UNIQUE (owner,name)
);

CREATE TABLE asset.stat_cat_entry (
	id		SERIAL	PRIMARY KEY,
	owner		INT	NOT NULL, -- actor.org_unit.id
	value		TEXT	NOT NULL,
	CONSTRAINT sce_once_per_owner UNIQUE (owner,value)
);

CREATE TABLE asset.stat_cat_entry_copy_map (
	id		BIGSERIAL	PRIMARY KEY,
	stat_cat	INT		NOT NULL, -- needs ON DELETE CASCADE
	stat_cat_entry	INT		NOT NULL, -- needs ON DELETE CASCADE
	owning_copy	BIGINT		NOT NULL, -- needs ON DELETE CASCADE
	CONSTRAINT sce_once_per_copy UNIQUE (owning_copy,stat_cat)
);

CREATE TABLE asset.copy_note (
	id		BIGSERIAL			PRIMARY KEY,
	owning_copy	BIGINT				NOT NULL,
	creator		BIGINT				NOT NULL,
	create_date	TIMESTAMP WITH TIME ZONE	DEFAULT NOW(),
	title		TEXT				NOT NULL,
	value		TEXT				NOT NULL
);

CREATE TABLE asset.call_number (
	id		bigserial PRIMARY KEY,
	creator		BIGINT				NOT NULL,
	create_date	TIMESTAMP WITH TIME ZONE	DEFAULT NOW(),
	editor		BIGINT				NOT NULL,
	edit_date	TIMESTAMP WITH TIME ZONE	DEFAULT NOW(),
	record		bigint,
	label		text,
	owning_lib	text
);

CREATE TABLE asset.call_number_note (
	id		BIGSERIAL			PRIMARY KEY,
	call_number	BIGINT				NOT NULL,
	creator		BIGINT				NOT NULL,
	create_date	TIMESTAMP WITH TIME ZONE	DEFAULT NOW(),
	title		TEXT				NOT NULL,
	value		TEXT				NOT NULL
);


COMMIT;
