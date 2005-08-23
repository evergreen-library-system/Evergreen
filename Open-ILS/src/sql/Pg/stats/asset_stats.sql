DROP SCHEMA asset_hist CASCADE;

BEGIN

CREATE SCHEMA asset_hist;

CREATE TABLE asset_hist.copy_immutables (
	id		BIGINT				PRIMARY KEY,
	owning_lib	BIGINT				NOT NULL,
	creator		BIGINT				NOT NULL,
	create_date	TIMESTAMP WITH TIME ZONE	NOT NULL,
	deleter		BIGINT,
	delete_date	TIMESTAMP WITH TIME ZONE,
	barcode		TEXT				NOT NULL,
	copy_number	INT				NOT NULL,
	price		NUMERIC(8,2)			NOT NULL
);

