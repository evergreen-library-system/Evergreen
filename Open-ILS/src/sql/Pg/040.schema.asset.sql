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

COMMENT ON SCHEMA asset is 'Logical grouping of all database objects that model physical assets.';

/* Table copy_location:
 * 	Represents a unique collection/shelving location. 
 *	Every copy will have a shelving location.
 *	Example: Upstairs Reference, holdable = False, Opac_visible = True, Circulate = False.
 */
CREATE TABLE asset.copy_location (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL,
	owning_lib	INT	NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	holdable	BOOL	NOT NULL DEFAULT TRUE,
	hold_verify	BOOL	NOT NULL DEFAULT FALSE,
	opac_visible	BOOL	NOT NULL DEFAULT TRUE,
	circulate	BOOL	NOT NULL DEFAULT TRUE,
	CONSTRAINT acl_name_once_per_lib UNIQUE (name, owning_lib)
);
COMMENT ON TABLE asset.copy_location IS 'Represents a unique collection/shelving location.';
COMMENT ON COLUMN asset.copy_location.id IS 'Unique ID number for each copy location.';
COMMENT ON COLUMN asset.copy_location.name IS 'Name of copy location.';
COMMENT ON COLUMN asset.copy_location.owning_lib IS 'Associates an organizational unit with a copy location.';
COMMENT ON COLUMN asset.copy_location.holdable IS 'Can holds be placed on copies in this copy location?';
COMMENT ON COLUMN asset.copy_location.opac_visible IS 'Can copies in this copy location be seen in the OPAC?';
COMMENT ON COLUMN asset.copy_location.circulate IS 'Can copies in this copy location circulate?';

/* Table copy:
 *      Represents a unique physical copy.
 *      There will be one record for every copy of a work in the library.
 *	A few foreign keys are setup later in fkeys.sql
 */
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
CREATE INDEX cp_avail_cn_idx ON asset.copy (call_number);  -- Redundant should be removed
CREATE RULE protect_copy_delete AS ON DELETE TO asset.copy DO INSTEAD UPDATE asset.copy SET deleted = TRUE WHERE OLD.id = asset.copy.id;
COMMENT ON TABLE asset.copy IS 'Represents a unique physical copy.';
COMMENT ON COLUMN asset.copy.id IS 'Unique ID number for each copy.';
COMMENT ON COLUMN asset.copy.circ_lib IS 'Associates an org unit with a copy, this org unit is considered the circulating library for this copy.';
COMMENT ON COLUMN asset.copy.creator IS 'Associates the actor.usr that created this record with the copy.';
COMMENT ON COLUMN asset.copy.call_number IS 'Associates an asset.call_number with this copy.';
COMMENT ON COLUMN asset.copy.editor IS 'Associates the actor.usr that last changed this record with the copy.';
COMMENT ON COLUMN asset.copy.create_date IS 'When the record was created.';
COMMENT ON COLUMN asset.copy.edit_date IS 'When the record was last edited';
COMMENT ON COLUMN asset.copy.copy_number IS 'Which copy in a volume set is this, or which one of several identical items is this?';
COMMENT ON COLUMN asset.copy.status IS 'Associates a config.copy_status with this copy.  Represents the circulation status of the copy.';
COMMENT ON COLUMN asset.copy.location IS 'Associates an asset.copy_location with this copy.';
COMMENT ON COLUMN asset.copy.loan_duration IS 'Specifies one of 3 loan duration categories, short, normal or long.  Used by loan rules.';
COMMENT ON COLUMN asset.copy.fine_level IS 'Daily fine rate level for this copy, currently 3 levels are allowed.  Used by loan rules';
COMMENT ON COLUMN asset.copy.age_protect IS 'Should the copy have hold protection.  Hold protection keeps new items from being placed on hold by other libraries or systems.';
COMMENT ON COLUMN asset.copy.circulate IS 'Can the item be circulated?';
COMMENT ON COLUMN asset.copy.deposit IS 'Is the deposit_amount required to check out this copy refundable (deposit vs rental)?';
COMMENT ON COLUMN asset.copy.ref IS 'Is this copy considered a reference item?';
COMMENT ON COLUMN asset.copy.holdable IS 'Is this copy holdable?';
COMMENT ON COLUMN asset.copy.deposit_amount IS 'If there is a deposit or rental fee required, how much is it?';
COMMENT ON COLUMN asset.copy.price IS 'Replacement price of copy.';
COMMENT ON COLUMN asset.copy.barcode IS 'Stores the barcode of the copy.';
COMMENT ON COLUMN asset.copy.circ_modifier IS 'The circ_modifier is a string that allows for special circulation rules to be set for a specific copy.';
COMMENT ON COLUMN asset.copy.circ_as_type IS 'The MARC item type that this copy should circulate as.';
COMMENT ON COLUMN asset.copy.dummy_title IS 'Pre-cataloging dummy title, for items that haven\'t been fully cataloged.';
COMMENT ON COLUMN asset.copy.dummy_author IS 'Pre-cataloging dummy author, for items that haven\'t been fully cataloged.';
COMMENT ON COLUMN asset.copy.alert_message IS 'Copy specific alert message.';
COMMENT ON COLUMN asset.copy.opac_visible IS 'Is this item visible in the opac?';
COMMENT ON COLUMN asset.copy.deleted IS 'Is this copy deleted?';

COMMENT ON INDEX asset.copy_barcode_key IS 'Index for the copy barcode that only includes barcodes for items that are not deleted.  This allows barcodes on deleted items to be reused.';
COMMENT ON INDEX asset.cp_cn_idx IS 'Index on copy call number foreign key.';
COMMENT ON INDEX asset.cp_avail_cn_idx IS 'Index on copy call number foreign key, Redundant index, should be removed.';
COMMENT ON RULE protect_copy_delete IS 'This rule reformats deletes of asset.copy records into update statements that change the asset.copy.deleted field to true.';

/* Table copy_transparency:
 *	This table represents an overlay of certain asset.copy columns that can be
 *	used to temporarily change the behavior of a group of copies without modifying
 *	the copy records themselves.  Not currently implemented.
 */
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
COMMENT ON TABLE asset.copy_transparency IS 'Overlay of certain copy columns for temporarily changing the behavior of a group of copies.';
COMMENT ON COLUMN asset.copy_transparency.id IS 'Unique ID for each copy_transparency record.';
COMMENT ON COLUMN asset.copy_transparency.deposit_amount IS 'If there is a deposit required, how much is it?';
COMMENT ON COLUMN asset.copy_transparency.owner IS 'Associates an asset.org_unit with this copy_transparency.  Represents the owner of this record.';
COMMENT ON COLUMN asset.copy_transparency.circ_lib IS 'Associates an org unit with a copy, this org unit is considered the circulating library for this copy.';
COMMENT ON COLUMN asset.copy_transparency.loan_duration IS 'Specifies one of 3 loan duration categories, short, normal or long.  Used by loan rules.';
COMMENT ON COLUMN asset.copy_transparency.fine_level IS 'Daily fine rate level for this copy, currently 3 levels are allowed.';
COMMENT ON COLUMN asset.copy_transparency.holdable IS 'Is this copy holdable?';
COMMENT ON COLUMN asset.copy_transparency.circulate IS 'Can the item be circulated?';
COMMENT ON COLUMN asset.copy_transparency.deposit IS 'Is a deposit required to be able to check out this copy?';
COMMENT ON COLUMN asset.copy_transparency.ref IS 'Is this copy considered a reference item?';
COMMENT ON COLUMN asset.copy_transparency.opac_visible IS 'Is this item visible in the opac?';
COMMENT ON COLUMN asset.copy_transparency.circ_modifier IS 'The circ_modifier is a string that allows for special circulation rules to be set for a specific copy.';
COMMENT ON COLUMN asset.copy_transparency.circ_as_type IS 'The MARC item type that this copy should circulate as.';
COMMENT ON COLUMN asset.copy_transparency.name IS 'Name of this copy_transparency record.';
COMMENT ON INDEX asset.scte_name_once_per_lib IS 'This constraint allows only one unique combination of owner and name at a time.  One owner can have only one copy_transparency with a given name, but names can be used multiple times by different owners.';

/* Table copy_tranparency_map:
 *      This table maps asset.copy_transparency records to asset.copy records. 
 *	Table is misspelled, needs to be fixed.
 */
CREATE TABLE asset.copy_tranparency_map (
	id		BIGSERIAL	PRIMARY KEY,
	tansparency	INT	NOT NULL REFERENCES asset.copy_transparency (id),
	target_copy	INT	NOT NULL UNIQUE REFERENCES asset.copy (id)
);
CREATE INDEX cp_tr_cp_idx ON asset.copy_tranparency_map (tansparency);
COMMENT ON TABLE asset.copy_tranparency_map IS 'Maps asset.copy_transparency records to asset.copy records.';
COMMENT ON COLUMN asset.copy_tranparency_map.id IS 'Unique ID for each asset.copy_tranparency_map mapping.';
COMMENT ON COLUMN asset.copy_tranparency_map.tansparency IS 'Associates an asset.copy_transparency record with a mapping. Misspelled, needs to be fixed.';
COMMENT ON COLUMN asset.copy_tranparency_map.target_copy IS 'Associates an asset.copy record with a mapping.';
COMMENT ON INDEX asset.cp_tr_cp_idx IS 'Index on asset.copy_tranparency_map.tansparency, to speed up finding all rows that belong to one asset.copy_transparency.';

/* Table stat_cat_entry_transparency_map:
 * 	Maps a statistical category entry to a copy_transparency entry.  Allows
 *	a copy_transparency to have a stat_cat entry assigned to it, thus associating 
 *	stat_cat_entries to all the copies that are part of the copy_transparency.
 */
CREATE TABLE asset.stat_cat_entry_transparency_map (
	id			BIGSERIAL	PRIMARY KEY,
	stat_cat		INT		NOT NULL, -- needs ON DELETE CASCADE
	stat_cat_entry		INT		NOT NULL, -- needs ON DELETE CASCADE
	owning_transparency	INT		NOT NULL, -- needs ON DELETE CASCADE
	CONSTRAINT scte_once_per_trans UNIQUE (owning_transparency,stat_cat)
);
COMMENT ON TABLE asset.stat_cat_entry_transparency_map IS 'Maps a stat_cat_entry to a copy_transparency.  Allows for collecting stats on all copies that are part of a copy_transparency.';
COMMENT ON COLUMN asset.stat_cat_entry_transparency_map.id IS 'Unique ID for each stat_cat_entry_transparency_map mapping.';
COMMENT ON COLUMN asset.stat_cat_entry_transparency_map.stat_cat IS 'Associates a stat_cat with this mapping.';
COMMENT ON COLUMN asset.stat_cat_entry_transparency_map.stat_cat_entry IS 'Associates a stat_cat_entry with this mapping.';
COMMENT ON COLUMN asset.stat_cat_entry_transparency_map.owning_transparency IS 'Associates a copy_transparency with this mapping.';
COMMENT ON INDEX asset.scte_once_per_trans IS 'Only allow one stat_cat_entry per stat_cat and owning_transparency combination.  A copy_transparency shouldn\'t have more than one stat_cat_entry from one stat_cat at a time.';

/* Table asset.stat_cat:
 *      Table represents a statistical category.  This allows for custom
 *	statistical categories to track any kind of information wanted.
 */
CREATE TABLE asset.stat_cat (
	id		SERIAL	PRIMARY KEY,
	owner		INT	NOT NULL,
	opac_visible	BOOL	NOT NULL DEFAULT FALSE,
	name		TEXT	NOT NULL,
	CONSTRAINT sc_once_per_owner UNIQUE (owner,name)
);
COMMENT ON TABLE asset.stat_cat IS 'Table represents a statistical category.';
COMMENT ON COLUMN asset.stat_cat.id IS 'Unique id for each stat_cat entry.';
COMMENT ON COLUMN asset.stat_cat.owner IS 'Associates an actor.org_unit with this stat_cat entry.  Represents the owner of the category.';
COMMENT ON COLUMN asset.stat_cat.opac_visible IS 'Is this stat_cat visible in the OPAC?';
COMMENT ON COLUMN asset.stat_cat.name IS 'Name of the stat_cat entry.';
COMMENT ON INDEX asset.sc_once_per_owner IS 'Each owner can only have one stat_cat with a certain name.';

/* Table stat_cat_entry:
 *	These are the values that can be set for each statistical category.
 */
CREATE TABLE asset.stat_cat_entry (
	id		SERIAL	PRIMARY KEY,
        stat_cat        INT     NOT NULL,
	owner		INT	NOT NULL,
	value		TEXT	NOT NULL,
	CONSTRAINT sce_once_per_owner UNIQUE (stat_cat,owner,value)
);
COMMENT ON TABLE asset.stat_cat_entry IS 'Table represents the different values that can be set for each statistical category.';
COMMENT ON COLUMN asset.stat_cat_entry.id IS 'Unique id for each stat_cat_entry.';
COMMENT ON COLUMN asset.stat_cat_entry.stat_cat IS 'Associates this stat_cat_entry with a parent stat_cat.';
COMMENT ON COLUMN asset.stat_cat_entry.owner IS 'Associates the owning org_unit with a stat_cat_entry.  Allows for custom entries that are owned by a different org_unit than the stat_cat itself.';
COMMENT ON COLUMN asset.stat_cat_entry.value IS 'The value of the stat_cat_entry.';
COMMENT ON INDEX asset.sce_once_per_owner IS 'Each owner can only have one entry with a certain value for each stat_cat.';

/* Table stat_cat_entry_copy_map:
 *      Maps the relationship between Statistical Category entries and individual copies.
 *	A copy should only be associated with one stat_cat_entry per stat_cat.
 */
CREATE TABLE asset.stat_cat_entry_copy_map (
	id		BIGSERIAL	PRIMARY KEY,
	stat_cat	INT		NOT NULL,
	stat_cat_entry	INT		NOT NULL,
	owning_copy	BIGINT		NOT NULL,
	CONSTRAINT sce_once_per_copy UNIQUE (owning_copy,stat_cat)
);
COMMENT ON TABLE  asset.stat_cat_entry_copy_map IS 'Maps the relationship between statistical category entries and individual copies.';
COMMENT ON COLUMN asset.stat_cat_entry_copy_map.id IS 'Unique id for each map entry.';
COMMENT ON COLUMN asset.stat_cat_entry_copy_map.stat_cat IS 'Associates a stat_cat with this mapping.';
COMMENT ON COLUMN asset.stat_cat_entry_copy_map.stat_cat_entry IS 'Associates a stat_cat_entry with this mapping.';
COMMENT ON COLUMN asset.stat_cat_entry_copy_map.owning_copy IS 'Associates a copy with this mapping.';
COMMENT ON INDEX asset.sce_once_per_copy IS 'A copy can only be associated with one stat_cat_entry per stat_cat.';

/* Table copy_note:
 *	Represents a notice/note/message that is associated with a copy.  Can be marked public for display to patrons
 *	in the opac.  A way to store free form information about a copy.  A copy can have multiple notes.
 */
CREATE TABLE asset.copy_note (
	id		BIGSERIAL			PRIMARY KEY,
	owning_copy	BIGINT				NOT NULL,
	creator		BIGINT				NOT NULL,
	create_date	TIMESTAMP WITH TIME ZONE	DEFAULT NOW(),
	pub		BOOL				NOT NULL DEFAULT FALSE,
	title		TEXT				NOT NULL,
	value		TEXT				NOT NULL
);
COMMENT ON TABLE asset.copy_note IS 'A note/notice/message that is associated with a copy.';
COMMENT ON COLUMN asset.copy_note.id IS 'Unique id for each note.';
COMMENT ON COLUMN asset.copy_note.owning_copy IS 'Associates an asset.copy with this note.';
COMMENT ON COLUMN asset.copy_note.creator IS 'Associates an actor.usr with this note. Represents the creator of the note.';
COMMENT ON COLUMN asset.copy_note.create_date IS 'Note creation timestamp.';
COMMENT ON COLUMN asset.copy_note.pub IS 'Is this note public?';
COMMENT ON COLUMN asset.copy_note.title IS 'The title of the note.';
COMMENT ON COLUMN asset.copy_note.value IS 'The contents of the note.';

/* Table call_number:
 *	Represents call numbers, and in effect volumes.  A copy must reference a call number.
 *	More than one copy can reference the same call number.  A call number must be 
 *	associated with one biblio.record_entry.  The call number provides the association 
 *	between a copy and a bib.
 */
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
COMMENT ON TABLE asset.call_number IS 'Represents call numbers/volumes.  Provides the mapping between copies and biblio.record_entry(s).';
COMMENT ON COLUMN asset.call_number.id IS 'Unique id for each call number.';
COMMENT ON COLUMN asset.call_number.creator IS 'Associates an actor.usr with this call number. Represents the user that created the call number.';
COMMENT ON COLUMN asset.call_number.create_date IS 'Timestamp of call_number creation.';
COMMENT ON COLUMN asset.call_number.editor IS 'Associates an actor.usr with this call number. Represents the last user to edit the call number.';
COMMENT ON COLUMN asset.call_number.edit_date IS 'Timestamp of last edit.';
COMMENT ON COLUMN asset.call_number.record IS 'Associates a biblio.record_entry with this call_number.';
COMMENT ON COLUMN asset.call_number.owning_lib IS 'Associates an actor.org_unit with this call_number. Represents the owning org unit.';
COMMENT ON COLUMN asset.call_number.label IS 'The value of the call number.';
COMMENT ON COLUMN asset.call_number.deleted IS 'Is this call number deleted?';
COMMENT ON INDEX asset.asset_call_number_dewey_idx IS 'This indexes the label values after they are modified by the public.call_number_dewey procedure.';
COMMENT ON INDEX asset.asset_call_number_upper_label_id_owning_lib_idx IS 'This indexes the combination of uppercase label, id and owning_lib.';
COMMENT ON INDEX asset.asset_call_number_label_once_per_lib IS 'This index makes sure that all combinations of record, owning_lib, and label are unique.  It also excludes deleted call numbers, so there values can be reused.';
COMMENT ON RULE protect_cn_delete IS 'Reformats deletes into updates that set the deleted column to true.';


/* Table call_number_note:
 *      Represents a notice/note/message that is associated with a call_number/volume.
 *	This feature is not yet fully implemented.  Can be marked public for display to patrons
 *      in the opac.  A way to store free form information about a volume.  A volume can 
 *	have multiple notes.
 */
CREATE TABLE asset.call_number_note (
	id		BIGSERIAL			PRIMARY KEY,
	call_number	BIGINT				NOT NULL,
	creator		BIGINT				NOT NULL,
	create_date	TIMESTAMP WITH TIME ZONE	DEFAULT NOW(),
	pub		BOOL				NOT NULL DEFAULT FALSE,
	title		TEXT				NOT NULL,
	value		TEXT				NOT NULL
);
COMMENT ON TABLE asset.call_number_note IS 'A notice/note/message that is associated with a call number/volume.  Not fully implemented.';
COMMENT ON COLUMN asset.call_number_note.id IS 'Unique id of each note.';
COMMENT ON COLUMN asset.call_number_note.call_number IS 'Associates an asset.call_number with a note.';
COMMENT ON COLUMN asset.call_number_note.creator IS 'Associates an actor.usr with a note.  Represents the user that created the note.';
COMMENT ON COLUMN asset.call_number_note.create_date IS 'Timestamp of note creation.';
COMMENT ON COLUMN asset.call_number_note.pub IS 'Is this note public?  Should it be shown in the opac?';
COMMENT ON COLUMN asset.call_number_note.title IS 'Title of the note.';
COMMENT ON COLUMN asset.call_number_note.value IS 'Contents of the note.';

/* View stats.fleshed_copy:
 *	This shows a fleshed out view of a copy that includes call number information and
 *	bibliographic record descriptors(Item Language, Item Type and Item form).  Where is this used?
 */
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
COMMENT ON VIEW stats.fleshed_copy IS 'Fleshed out view of a copy that includes call number information and bibliographic descriptors.';
COMMENT ON COLUMN stats.fleshed_copy.create_date_day IS 'create_day cast to a date from a timestamp.';
COMMENT ON COLUMN stats.fleshed_copy.edit_date_day IS 'edit_date cast to a date from a timestamp.';
COMMENT ON COLUMN stats.fleshed_copy.create_date_hour IS 'The creation time.';
COMMENT ON COLUMN stats.fleshed_copy.edit_date_hour IS 'The last edit time.';

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

COMMIT;

