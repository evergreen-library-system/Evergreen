/*
 * Copyright (C) 2004-2008  Georgia Public Library Service
 * Copyright (C) 2007-2008  Equinox Software, Inc.
 * Mike Rylander <miker@esilibrary.com> 
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 */

DROP SCHEMA asset CASCADE;

BEGIN;

CREATE SCHEMA asset;

CREATE TABLE asset.copy_location (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL,
	owning_lib	INT	NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	holdable	BOOL	NOT NULL DEFAULT TRUE,
	hold_verify	BOOL	NOT NULL DEFAULT FALSE,
	opac_visible	BOOL	NOT NULL DEFAULT TRUE,
	circulate	BOOL	NOT NULL DEFAULT TRUE
);

CREATE TABLE asset.copy (
	id		BIGSERIAL			PRIMARY KEY,
	circ_lib	INT				NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	creator		BIGINT				NOT NULL,
	call_number	BIGINT				NOT NULL,
	editor		BIGINT				NOT NULL,
	create_date	TIMESTAMP WITH TIME ZONE	DEFAULT NOW(),
	edit_date	TIMESTAMP WITH TIME ZONE	DEFAULT NOW(),
	copy_number	INT,
	status		INT				NOT NULL DEFAULT 0 REFERENCES config.copy_status (id) DEFERRABLE INITIALLY DEFERRED,
	location	INT				NOT NULL DEFAULT 1 REFERENCES asset.copy_location (id) DEFERRABLE INITIALLY DEFERRED,
	loan_duration	INT				NOT NULL CHECK ( loan_duration IN (1,2,3) ),
	fine_level	INT				NOT NULL CHECK ( fine_level IN (1,2,3) ),
	age_protect	INT,
	circulate	BOOL				NOT NULL DEFAULT TRUE,
	deposit		BOOL				NOT NULL DEFAULT FALSE,
	ref		BOOL				NOT NULL DEFAULT FALSE,
	holdable	BOOL				NOT NULL DEFAULT TRUE,
	deposit_amount	NUMERIC(6,2)			NOT NULL DEFAULT 0.00,
	price		NUMERIC(8,2),
	barcode		TEXT				NOT NULL,
	circ_modifier	TEXT,
	circ_as_type	TEXT,
	dummy_title	TEXT,
	dummy_author	TEXT,
	alert_message	TEXT,
	opac_visible	BOOL				NOT NULL DEFAULT TRUE,
	deleted		BOOL				NOT NULL DEFAULT FALSE
);
CREATE UNIQUE INDEX copy_barcode_key ON asset.copy (barcode) WHERE deleted IS FALSE;
CREATE INDEX cp_cn_idx ON asset.copy (call_number);
CREATE INDEX cp_avail_cn_idx ON asset.copy (call_number);
CREATE RULE protect_copy_delete AS ON DELETE TO asset.copy DO INSTEAD UPDATE asset.copy SET deleted = TRUE WHERE OLD.id = asset.copy.id;

CREATE TABLE asset.copy_transparency (
	id		SERIAL		PRIMARY KEY,
	deposit_amount	NUMERIC(6,2),
	owner		INT		NOT NULL REFERENCES actor.org_unit (id),
	circ_lib	INT		REFERENCES actor.org_unit (id),
	loan_duration	INT		CHECK ( loan_duration IN (1,2,3) ),
	fine_level	INT		CHECK ( fine_level IN (1,2,3) ),
	holdable	BOOL,
	circulate	BOOL,
	deposit		BOOL,
	ref		BOOL,
	opac_visible	BOOL,
	circ_modifier	TEXT,
	circ_as_type	TEXT,
	name		TEXT		NOT NULL,
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
	opac_visible	BOOL	NOT NULL DEFAULT FALSE,
	name		TEXT	NOT NULL,
	CONSTRAINT sc_once_per_owner UNIQUE (owner,name)
);

CREATE TABLE asset.stat_cat_entry (
	id		SERIAL	PRIMARY KEY,
        stat_cat        INT     NOT NULL,
	owner		INT	NOT NULL,
	value		TEXT	NOT NULL,
	CONSTRAINT sce_once_per_owner UNIQUE (stat_cat,owner,value)
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
	pub		BOOL				NOT NULL DEFAULT FALSE,
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
	owning_lib	INT				NOT NULL,
	label		TEXT				NOT NULL,
	deleted		BOOL				NOT NULL DEFAULT FALSE
);
CREATE INDEX asset_call_number_record_idx ON asset.call_number (record);
CREATE INDEX asset_call_number_creator_idx ON asset.call_number (creator);
CREATE INDEX asset_call_number_editor_idx ON asset.call_number (editor);
CREATE INDEX asset_call_number_dewey_idx ON asset.call_number (public.call_number_dewey(label));
CREATE INDEX asset_call_number_upper_label_id_owning_lib_idx ON asset.call_number (upper(label),id,owning_lib);
CREATE UNIQUE INDEX asset_call_number_label_once_per_lib ON asset.call_number (record, owning_lib, label) WHERE deleted IS FALSE;
CREATE RULE protect_cn_delete AS ON DELETE TO asset.call_number DO INSTEAD UPDATE asset.call_number SET deleted = TRUE WHERE OLD.id = asset.call_number.id;

CREATE TABLE asset.call_number_note (
	id		BIGSERIAL			PRIMARY KEY,
	call_number	BIGINT				NOT NULL,
	creator		BIGINT				NOT NULL,
	create_date	TIMESTAMP WITH TIME ZONE	DEFAULT NOW(),
	pub		BOOL				NOT NULL DEFAULT FALSE,
	title		TEXT				NOT NULL,
	value		TEXT				NOT NULL
);

CREATE VIEW stats.fleshed_copy AS 
        SELECT  cp.*,
		CAST(cp.create_date AS DATE) AS create_date_day,
		CAST(cp.edit_date AS DATE) AS edit_date_day,
		DATE_TRUNC('hour', cp.create_date) AS create_date_hour,
		DATE_TRUNC('hour', cp.edit_date) AS edit_date_hour,
                cn.label AS call_number_label,
                cn.owning_lib,
                rd.item_lang,
                rd.item_type,
                rd.item_form
        FROM    asset.copy cp
                JOIN asset.call_number cn ON (cp.call_number = cn.id)
                JOIN metabib.rec_descriptor rd ON (rd.record = cn.record);

CREATE VIEW stats.fleshed_call_number AS 
        SELECT  cn.*,
       		CAST(cn.create_date AS DATE) AS create_date_day,
		CAST(cn.edit_date AS DATE) AS edit_date_day,
		DATE_TRUNC('hour', cn.create_date) AS create_date_hour,
		DATE_TRUNC('hour', cn.edit_date) AS edit_date_hour,
         	rd.item_lang,
                rd.item_type,
                rd.item_form
        FROM    asset.call_number cn
                JOIN metabib.rec_descriptor rd ON (rd.record = cn.record);

CREATE OR REPLACE FUNCTION asset.merge_record_assets( target_record BIGINT, source_record BIGINT ) RETURNS INT AS $func$
DECLARE
	moved_cns INT := 0;
	source_cn asset.call_number%ROWTYPE;
	target_cn asset.call_number%ROWTYPE;
BEGIN
	FOR source_cn IN SELECT * FROM asset.call_number WHERE record = source_record LOOP

		SELECT	INTO target_cn *
		  FROM	asset.call_number
		  WHERE	label = source_cn.label
			AND owning_lib = source_cn.owning_lib
			AND record = target_record;

		IF FOUND THEN
			UPDATE	asset.copy
			  SET	call_number = target_cn.id
			  WHERE	call_number = source_cn.id;
		ELSE
			UPDATE	asset.call_number
			  SET	record = target_record
			  WHERE	id = source_cn.id;
		END IF;

		moved_cns := moved_cns + 1;
	END LOOP;

	RETURN moved_cns;
END;
$func$ LANGUAGE plpgsql;

COMMIT;

