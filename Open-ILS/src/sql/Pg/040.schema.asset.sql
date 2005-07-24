DROP SCHEMA asset CASCADE;

BEGIN;

CREATE SCHEMA asset;

CREATE TABLE asset.copy_location (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL,
	owning_lib	INT	NOT NULL REFERENCES actor.org_unit (id),
	holdable	BOOL	NOT NULL DEFAULT TRUE,
	opac_visible	BOOL	NOT NULL DEFAULT TRUE,
	circulate	BOOL	NOT NULL DEFAULT TRUE
);
INSERT INTO asset.copy_location (name,owning_lib) VALUES ('Stacks',1);

CREATE TABLE asset.copy (
	id		BIGSERIAL			PRIMARY KEY,
	circ_lib	INT				NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	creator		BIGINT				NOT NULL,
	create_date	TIMESTAMP WITH TIME ZONE	DEFAULT NOW(),
	editor		BIGINT				NOT NULL,
	edit_date	TIMESTAMP WITH TIME ZONE	DEFAULT NOW(),
	barcode		TEXT				UNIQUE NOT NULL,
	call_number	BIGINT				NOT NULL,
	copy_number	INT,
	holdable	BOOL				NOT NULL DEFAULT TRUE,
	status		INT				NOT NULL DEFAULT 0 REFERENCES config.copy_status (id) DEFERRABLE INITIALLY DEFERRED,
	location	INT				NOT NULL DEFAULT 1 REFERENCES asset.copy_location (id) DEFERRABLE INITIALLY DEFERRED,
	loan_duration	INT				NOT NULL CHECK ( loan_duration IN (1,2,3) ),
	fine_level	INT				NOT NULL CHECK ( fine_level IN (1,2,3) ),
	circulate	BOOL				NOT NULL DEFAULT TRUE,
	deposit		BOOL				NOT NULL DEFAULT FALSE,
	deposit_amount	NUMERIC(6,2)			NOT NULL DEFAULT 0.00,
	price		NUMERIC(8,2)			NOT NULL DEFAULT 0.00,
	ref		BOOL				NOT NULL DEFAULT FALSE,
	circ_modifier	TEXT,
	circ_as_type	TEXT,
	opac_visible	BOOL				NOT NULL DEFAULT TRUE
);
CREATE INDEX cp_cn_idx ON asset.copy (call_number);
CREATE INDEX cp_avail_cn_idx ON asset.copy (call_number) WHERE status = 0;

CREATE TABLE asset.copy_transparency (
	id		SERIAL		PRIMARY KEY,
	name		TEXT		NOT NULL,
	owner		INT		NOT NULL REFERENCES actor.org_unit (id),
	circ_lib	INT		REFERENCES actor.org_unit (id),
	holdable	BOOL,
	loan_duration	INT		CHECK ( loan_duration IN (1,2,3) ),
	fine_level	INT		CHECK ( fine_level IN (1,2,3) ),
	circulate	BOOL,
	deposit		BOOL,
	deposit_amount	NUMERIC(6,2),
	ref		BOOL,
	circ_modifier	TEXT,
	circ_as_type	TEXT,
	opac_visible	BOOL,
	CONSTRAINT scte_name_once_per_lib UNIQUE (owner,name)
);

CREATE TABLE asset.copy_tranparency_map (
	id		BIGSERIAL	PRIMARY KEY,
	tansparency	INT	NOT NULL REFERENCES asset.copy_transparency (id),
	target_copy	INT	NOT NULL UNIQUE REFERENCES asset.copy (id)
);
CREATE INDEX cp_tr_cp_idx ON asset.copy_tranparency_map (tansparency);

CREATE TABLE asset.stat_cat_entry_transparency_map (
	id			BIGSERIAL	PRIMARY KEY,
	stat_cat		INT		NOT NULL, -- needs ON DELETE CASCADE
	stat_cat_entry		INT		NOT NULL, -- needs ON DELETE CASCADE
	owning_transparency	INT		NOT NULL, -- needs ON DELETE CASCADE
	CONSTRAINT scte_once_per_trans UNIQUE (owning_transparency,stat_cat)
);

CREATE TABLE asset.stat_cat (
	id		SERIAL	PRIMARY KEY,
	owner		INT	NOT NULL,
	name		TEXT	NOT NULL,
	opac_visible	BOOL NOT NULL DEFAULT FALSE,
	CONSTRAINT sc_once_per_owner UNIQUE (owner,name)
);

CREATE TABLE asset.stat_cat_entry (
	id		SERIAL	PRIMARY KEY,
        stat_cat        INT     NOT NULL,
	owner		INT	NOT NULL,
	value		TEXT	NOT NULL,
	CONSTRAINT sce_once_per_owner UNIQUE (owner,value)
);

CREATE TABLE asset.stat_cat_entry_copy_map (
	id		BIGSERIAL	PRIMARY KEY,
	stat_cat	INT		NOT NULL,
	stat_cat_entry	INT		NOT NULL,
	owning_copy	BIGINT		NOT NULL,
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
	record		bigint				NOT NULL,
	label		TEXT				NOT NULL,
	owning_lib	INT				NOT NULL,
	CONSTRAINT asset_call_number_label_once_per_lib UNIQUE (record, owning_lib, label)
);
CREATE INDEX asset_call_number_record_idx ON asset.call_number (record);
CREATE INDEX asset_call_number_creator_idx ON asset.call_number (creator);
CREATE INDEX asset_call_number_editor_idx ON asset.call_number (editor);

CREATE TABLE asset.call_number_note (
	id		BIGSERIAL			PRIMARY KEY,
	call_number	BIGINT				NOT NULL,
	creator		BIGINT				NOT NULL,
	create_date	TIMESTAMP WITH TIME ZONE	DEFAULT NOW(),
	title		TEXT				NOT NULL,
	value		TEXT				NOT NULL
);


COMMIT;
