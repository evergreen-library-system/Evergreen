DROP SCHEMA asset CASCADE;

BEGIN;

CREATE SCHEMA asset;

CREATE TABLE asset.copy (
	id		bigserial PRIMARY KEY,
	creator		BIGINT				NOT NULL,
	create_date	TIMESTAMP WITH TIME ZONE	DEFAULT NOW(),
	editor		BIGINT				NOT NULL,
	edit_date	TIMESTAMP WITH TIME ZONE	DEFAULT NOW(),
	barcode		text,
	call_number	bigint,
	copy_number	text,
	status		text, -- current_lib
	home_lib	text,
	loan_duration	text, -- 2
	fine_level	text, -- 2
	circulate	text, --
	deposit		text, -- 0
	deposit_amount	text, -- 0.00
	price		text,
	ref		text, -- 0
	opac_visible	text, -- 1
	genre		text, -- cat1
	audience	text, -- cat2
	shelving_loc	text  -- "stacks"
);

CREATE TABLE asset.copy_note (
	id		BIGSERIAL			PRIMARY KEY,
	copy		BIGINT				NOT NULL,
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
