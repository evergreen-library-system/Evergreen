/*
 * Copyright (C) 2004-2008  Georgia Public Library Service
 * Copyright (C) 2008-2011  Equinox Software, Inc.
 * Mike Rylander <miker@esilibrary.com>
 * Copyright (C) 2010 Merrimack Valley Library Consortium
 * Jason Stephenson <jstephenson@mvlc.org>
 * Copyright (C) 2010 Laurentian University
 * Dan Scott <dscott@laurentian.ca>
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



DROP SCHEMA IF EXISTS stats CASCADE;
DROP SCHEMA IF EXISTS config CASCADE;

BEGIN;
CREATE SCHEMA stats;

CREATE SCHEMA config;
COMMENT ON SCHEMA config IS $$
The config schema holds static configuration data for the
Evergreen installation.
$$;

CREATE TABLE config.internal_flag (
    name    TEXT    PRIMARY KEY,
    value   TEXT,
    enabled BOOL    NOT NULL DEFAULT FALSE
);
INSERT INTO config.internal_flag (name) VALUES ('ingest.metarecord_mapping.skip_on_insert');
INSERT INTO config.internal_flag (name) VALUES ('ingest.metarecord_mapping.skip_on_update');
INSERT INTO config.internal_flag (name) VALUES ('ingest.reingest.force_on_same_marc');
INSERT INTO config.internal_flag (name) VALUES ('ingest.disable_located_uri');
INSERT INTO config.internal_flag (name) VALUES ('ingest.disable_metabib_full_rec');
INSERT INTO config.internal_flag (name) VALUES ('ingest.disable_metabib_rec_descriptor');
INSERT INTO config.internal_flag (name) VALUES ('ingest.assume_inserts_only');
INSERT INTO config.internal_flag (name) VALUES ('ingest.skip_browse_indexing');
INSERT INTO config.internal_flag (name) VALUES ('ingest.skip_search_indexing');
INSERT INTO config.internal_flag (name) VALUES ('ingest.skip_facet_indexing');
INSERT INTO config.internal_flag (name) VALUES ('ingest.skip_display_indexing');
INSERT INTO config.internal_flag (name) VALUES ('serial.rematerialize_on_same_holding_code');
INSERT INTO config.internal_flag (name) VALUES ('ingest.metarecord_mapping.preserve_on_delete');


CREATE TABLE config.global_flag (
    label   TEXT    NOT NULL
) INHERITS (config.internal_flag);
ALTER TABLE config.global_flag ADD PRIMARY KEY (name);

CREATE TABLE config.upgrade_log (
    version         TEXT    PRIMARY KEY,
    install_date    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    applied_to      TEXT
);

CREATE TABLE config.db_patch_dependencies (
  db_patch      TEXT PRIMARY KEY,
  supersedes    TEXT[],
  deprecates    TEXT[]
);

CREATE OR REPLACE FUNCTION evergreen.array_overlap_check (/* field */) RETURNS TRIGGER AS $$
DECLARE
    fld     TEXT;
    cnt     INT;
BEGIN
    fld := TG_ARGV[0];
    EXECUTE 'SELECT COUNT(*) FROM '|| TG_TABLE_SCHEMA ||'.'|| TG_TABLE_NAME ||' WHERE '|| fld ||' && ($1).'|| fld INTO cnt USING NEW;
    IF cnt > 0 THEN
        RAISE EXCEPTION 'Cannot insert duplicate array into field % of table %', fld, TG_TABLE_SCHEMA ||'.'|| TG_TABLE_NAME;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER no_overlapping_sups
    BEFORE INSERT OR UPDATE ON config.db_patch_dependencies
    FOR EACH ROW EXECUTE PROCEDURE evergreen.array_overlap_check ('supersedes');

CREATE TRIGGER no_overlapping_deps
    BEFORE INSERT OR UPDATE ON config.db_patch_dependencies
    FOR EACH ROW EXECUTE PROCEDURE evergreen.array_overlap_check ('deprecates');

INSERT INTO config.upgrade_log (version, applied_to) VALUES ('1466', :eg_version); -- sleary/miker

CREATE TABLE config.bib_source (
	id		SERIAL	PRIMARY KEY,
	quality		INT	CHECK ( quality BETWEEN 0 AND 100 ),
	source		TEXT	NOT NULL UNIQUE,
	transcendant	BOOL	NOT NULL DEFAULT FALSE,
	can_have_copies	BOOL	NOT NULL DEFAULT TRUE
);
COMMENT ON TABLE config.bib_source IS $$
This is table is used to set up the relative "quality" of each
MARC source, such as OCLC.  Also identifies "transcendant" sources,
i.e., sources of bib records that should display in the OPAC
even if no copies or located URIs are attached. Also indicates if
the source is allowed to have actual copies on its bibs. Volumes
for targeted URIs are unaffected by this setting.
$$;

CREATE TABLE config.standing (
	id		SERIAL	PRIMARY KEY,
	value		TEXT	NOT NULL UNIQUE
);
COMMENT ON TABLE config.standing IS $$
Patron Standings

This table contains the values that can be applied to a patron
by a staff member.  These values should not be changed, other
than for translation, as the ID column is currently a "magic
number" in the source. :(
$$;

CREATE TABLE config.standing_penalty (
	id			SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL UNIQUE,
	label		TEXT	NOT NULL,
	block_list	TEXT,
	staff_alert	BOOL	NOT NULL DEFAULT FALSE,
	org_depth	INTEGER,
	ignore_proximity INTEGER
);

CREATE TABLE config.xml_transform (
	name		TEXT	PRIMARY KEY,
	namespace_uri	TEXT	NOT NULL,
	prefix		TEXT	NOT NULL,
	xslt		TEXT	NOT NULL
);

CREATE TABLE config.biblio_fingerprint (
	id			SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL, 
	xpath		TEXT	NOT NULL,
    first_word  BOOL    NOT NULL DEFAULT FALSE,
	format		TEXT	NOT NULL DEFAULT 'marcxml'
);

INSERT INTO config.biblio_fingerprint (name, xpath, format)
    VALUES (
        'Title',
        '//marc:datafield[@tag="700"]/marc:subfield[@code="t"]|' ||
            '//marc:datafield[@tag="240"]/marc:subfield[@code="a"]|' ||
            '//marc:datafield[@tag="242"]/marc:subfield[@code="a"]|' ||
            '//marc:datafield[@tag="246"]/marc:subfield[@code="a"]|' ||
            '//marc:datafield[@tag="245"]/marc:subfield[@code="a"]',
        'marcxml'
    );

INSERT INTO config.biblio_fingerprint (name, xpath, format, first_word)
    VALUES (
        'Author',
        '//marc:datafield[@tag="700" and ./*[@code="t"]]/marc:subfield[@code="a"]|'
            '//marc:datafield[@tag="100"]/marc:subfield[@code="a"]|'
            '//marc:datafield[@tag="110"]/marc:subfield[@code="a"]|'
            '//marc:datafield[@tag="111"]/marc:subfield[@code="a"]|'
            '//marc:datafield[@tag="260"]/marc:subfield[@code="b"]',
        'marcxml',
        TRUE
    );

INSERT INTO config.biblio_fingerprint (name, xpath, format)
    VALUES (
        'PartName',
        '//mods32:mods/mods32:titleInfo/mods32:partName',
        'mods32'
    );

INSERT INTO config.biblio_fingerprint (name, xpath, format)
    VALUES (
        'PartNumber',
        '//mods32:mods/mods32:titleInfo/mods32:partNumber',
        'mods32'
    );

CREATE TABLE config.metabib_class (
    name     TEXT    PRIMARY KEY,
    label    TEXT    NOT NULL UNIQUE,
    buoyant  BOOL    DEFAULT FALSE NOT NULL,
    restrict BOOL    DEFAULT FALSE NOT NULL,
    combined BOOL    DEFAULT FALSE NOT NULL,
    a_weight NUMERIC  DEFAULT 1.0 NOT NULL,
    b_weight NUMERIC  DEFAULT 0.4 NOT NULL,
    c_weight NUMERIC  DEFAULT 0.2 NOT NULL,
    d_weight NUMERIC  DEFAULT 0.1 NOT NULL,
    variant_authority_suggestion   BOOL NOT NULL DEFAULT TRUE,
    symspell_transfer_case         BOOL NOT NULL DEFAULT TRUE,
    symspell_skip_correct          BOOL NOT NULL DEFAULT FALSE,
    symspell_suggestion_verbosity  INT NOT NULL DEFAULT 2,
    max_phrase_edit_distance       INT NOT NULL DEFAULT 2,
    suggestion_word_option_count   INT NOT NULL DEFAULT 5,
    max_suggestions                INT NOT NULL DEFAULT -1,
    low_result_threshold           INT NOT NULL DEFAULT 0,
    min_suggestion_use_threshold   INT NOT NULL DEFAULT 1,
    soundex_weight                 INT NOT NULL DEFAULT 0,
    pg_trgm_weight                 INT NOT NULL DEFAULT 0,
    keyboard_distance_weight       INT NOT NULL DEFAULT 0
);

CREATE TABLE config.metabib_field (
	id		SERIAL	PRIMARY KEY,
	field_class	TEXT	NOT NULL REFERENCES config.metabib_class (name),
	name		TEXT	NOT NULL,
	label		TEXT	NOT NULL,
	xpath		TEXT,
	weight		INT	NOT NULL DEFAULT 1,
	format		TEXT	NOT NULL REFERENCES config.xml_transform (name) DEFAULT 'mods33',
	search_field	BOOL	NOT NULL DEFAULT TRUE,
	facet_field	BOOL	NOT NULL DEFAULT FALSE,
	browse_field	BOOL	NOT NULL DEFAULT TRUE,
    browse_nocase BOOL NOT NULL DEFAULT FALSE,
	browse_xpath   TEXT,
	browse_sort_xpath TEXT,
	facet_xpath	TEXT,
	display_xpath	TEXT,
	authority_xpath TEXT,
	joiner      TEXT,
	restrict	BOOL    DEFAULT FALSE NOT NULL,
    display_field BOOL NOT NULL DEFAULT TRUE
);
COMMENT ON TABLE config.metabib_field IS $$
XPath used for record indexing ingest

This table contains the XPath used to chop up MODS into its
indexable parts.  Each XPath entry is named and assigned to
a "class" of either title, subject, author, keyword, series
or identifier.
$$;

CREATE TABLE config.metabib_field_virtual_map (
    id      SERIAL  PRIMARY KEY,
    real    INT NOT NULL REFERENCES config.metabib_field (id),
    virtual INT NOT NULL REFERENCES config.metabib_field (id),
    weight  INT NOT NULL DEFAULT 1
);
COMMENT ON TABLE config.metabib_field_virtual_map IS $$
Maps between real (physically extracted) index definitions
and virtual (target sync, no required extraction of its own)
index definitions.

The virtual side may not extract any data of its own, but
will collect data from all of the real fields.  This reduces
extraction (ingest) overhead by eliminating duplcated extraction,
and allows for searching across novel combinations of fields, such
as names used as either subjects or authors.  By preserving this
mapping rather than defining duplicate extractions, information
about the originating, "real" index definitions can be used
in interesting ways, such as highlighting in search results.
$$;

CREATE UNIQUE INDEX config_metabib_field_class_name_idx ON config.metabib_field (field_class, name);

CREATE TABLE config.display_field_map (
    name    TEXT   PRIMARY KEY,
    field   INTEGER REFERENCES config.metabib_field (id),
    multi   BOOLEAN DEFAULT FALSE
);

CREATE TABLE config.ts_config_list (
	id			TEXT PRIMARY KEY,
	name		TEXT NOT NULL
);
COMMENT ON TABLE config.ts_config_list IS $$
Full Text Configs

A list of full text configs with names and descriptions.
$$;

CREATE TABLE config.metabib_class_ts_map (
	id				SERIAL PRIMARY KEY,
	field_class		TEXT NOT NULL REFERENCES config.metabib_class (name),
	ts_config		TEXT NOT NULL REFERENCES config.ts_config_list (id),
	active			BOOL NOT NULL DEFAULT TRUE,
	index_weight	CHAR(1) NOT NULL DEFAULT 'C' CHECK (index_weight IN ('A','B','C','D')),
	index_lang		TEXT NULL,
	search_lang		TEXT NULL,
	always			BOOL NOT NULL DEFAULT true
);
COMMENT ON TABLE config.metabib_class_ts_map IS $$
Text Search Configs for metabib class indexing

This table contains text search config definitions for
storing index_vector values.
$$;

CREATE TABLE config.metabib_field_ts_map (
	id				SERIAL PRIMARY KEY,
	metabib_field	INT NOT NULL REFERENCES config.metabib_field (id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
	ts_config		TEXT NOT NULL REFERENCES config.ts_config_list (id),
	active			BOOL NOT NULL DEFAULT TRUE,
	index_weight	CHAR(1) NOT NULL DEFAULT 'C' CHECK (index_weight IN ('A','B','C','D')),
	index_lang		TEXT NULL,
	search_lang		TEXT NULL
);
COMMENT ON TABLE config.metabib_field_ts_map IS $$
Text Search Configs for metabib field indexing

This table contains text search config definitions for
storing index_vector values.
$$;

CREATE TABLE config.metabib_search_alias (
    alias       TEXT    PRIMARY KEY,
    field_class TEXT    NOT NULL REFERENCES config.metabib_class (name),
    field       INT     REFERENCES config.metabib_field (id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE config.non_cataloged_type (
	id		SERIAL		PRIMARY KEY,
	owning_lib	INT		NOT NULL, -- REFERENCES actor.org_unit (id),
	name		TEXT		NOT NULL,
	circ_duration	INTERVAL	NOT NULL DEFAULT '14 days'::INTERVAL,
	in_house	BOOL		NOT NULL DEFAULT FALSE,
	CONSTRAINT noncat_once_per_lib UNIQUE (owning_lib,name)
);
COMMENT ON TABLE config.non_cataloged_type IS $$
Types of valid non-cataloged items.
$$;

CREATE TABLE config.identification_type (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL UNIQUE
);
COMMENT ON TABLE config.identification_type IS $$
Types of valid patron identification.

Each patron must display at least one valid form of identification
in order to get a library card.  This table lists those forms.
$$;

CREATE TABLE config.rule_circ_duration (
	id		SERIAL		PRIMARY KEY,
	name		TEXT		NOT NULL UNIQUE CHECK ( name ~ E'^\\w+$' ),
	extended	INTERVAL	NOT NULL,
	normal		INTERVAL	NOT NULL,
	shrt		INTERVAL	NOT NULL,
	max_renewals	INT		NOT NULL,
    max_auto_renewals INTEGER
);
COMMENT ON TABLE config.rule_circ_duration IS $$
Circulation Duration rules

Each circulation is given a duration based on one of these rules.
$$;

CREATE TABLE config.hard_due_date (
    id                  SERIAL      PRIMARY KEY,
    name                TEXT        NOT NULL UNIQUE,
    ceiling_date        TIMESTAMPTZ NOT NULL,
    forceto             BOOL        NOT NULL,
    owner               INT         NOT NULL   -- REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
);

CREATE TABLE config.hard_due_date_values (
    id                  SERIAL      PRIMARY KEY,
    hard_due_date       INT         NOT NULL REFERENCES config.hard_due_date (id)
                                    DEFERRABLE INITIALLY DEFERRED,
    ceiling_date        TIMESTAMPTZ NOT NULL,
    active_date         TIMESTAMPTZ NOT NULL
);

CREATE OR REPLACE FUNCTION config.update_hard_due_dates () RETURNS INT AS $func$
DECLARE
    temp_value  config.hard_due_date_values%ROWTYPE;
    updated     INT := 0;
BEGIN
    FOR temp_value IN
      SELECT  DISTINCT ON (hard_due_date) *
        FROM  config.hard_due_date_values
        WHERE active_date <= NOW() -- We've passed (or are at) the rollover time
        ORDER BY hard_due_date, active_date DESC -- Latest (nearest to us) active time
   LOOP
        UPDATE  config.hard_due_date
          SET   ceiling_date = temp_value.ceiling_date
          WHERE id = temp_value.hard_due_date
                AND ceiling_date <> temp_value.ceiling_date -- Time is equal if we've already updated the chdd
                AND temp_value.ceiling_date >= NOW(); -- Don't update ceiling dates to the past

        IF FOUND THEN
            updated := updated + 1;
        END IF;
    END LOOP;

    RETURN updated;
END;
$func$ LANGUAGE plpgsql;

CREATE TABLE config.rule_max_fine (
    id          SERIAL          PRIMARY KEY,
    name        TEXT            NOT NULL UNIQUE CHECK ( name ~ E'^\\w+$' ),
    amount      NUMERIC(6,2)    NOT NULL,
    is_percent  BOOL            NOT NULL DEFAULT FALSE
);
COMMENT ON TABLE config.rule_max_fine IS $$
Circulation Max Fine rules

Each circulation is given a maximum fine based on one of
these rules.
$$;

CREATE TABLE config.rule_recurring_fine (
	id			SERIAL		PRIMARY KEY,
	name			TEXT		NOT NULL UNIQUE CHECK ( name ~ E'^\\w+$' ),
	high			NUMERIC(6,2)	NOT NULL,
	normal			NUMERIC(6,2)	NOT NULL,
	low			NUMERIC(6,2)	NOT NULL,
	recurrence_interval	INTERVAL	NOT NULL DEFAULT '1 day'::INTERVAL,
    grace_period       INTERVAL         NOT NULL DEFAULT '1 day'::INTERVAL
);
COMMENT ON TABLE config.rule_recurring_fine IS $$
Circulation Recurring Fine rules

Each circulation is given a recurring fine amount based on one of
these rules.  Note that it is recommended to run the fine generator
(from cron) at least as frequently as the lowest recurrence interval
used by your circulation rules so that accrued fines will be up
to date.
$$;


CREATE TABLE config.rule_age_hold_protect (
	id	SERIAL		PRIMARY KEY,
	name	TEXT		NOT NULL UNIQUE CHECK ( name ~ E'^\\w+$' ),
	age	INTERVAL	NOT NULL,
	prox	INT		NOT NULL
);
COMMENT ON TABLE config.rule_age_hold_protect IS $$
Hold Item Age Protection rules

A hold request can only capture new(ish) items when they are
within a particular proximity of the pickup_lib of the request.
The proximity ('prox' column) is calculated by counting
the number of tree edges between the pickup_lib and either the
owning_lib or circ_lib of the copy that could fulfill the hold,
as determined by the distance_is_from_owner value of the hold matrix
rule controlling the hold request.
$$;

CREATE TABLE config.copy_status (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL UNIQUE,
	holdable	BOOL	NOT NULL DEFAULT FALSE,
	opac_visible	BOOL	NOT NULL DEFAULT FALSE,
    copy_active  BOOL    NOT NULL DEFAULT FALSE,
	restrict_copy_delete BOOL	  NOT NULL DEFAULT FALSE,
    is_available  BOOL    NOT NULL DEFAULT FALSE,
    hopeless_prone  BOOL    NOT NULL DEFAULT FALSE
);
COMMENT ON TABLE config.copy_status IS $$
Copy Statuses

The available copy statuses, and whether a copy in that
status is available for hold request capture.  0 (zero) is
the only special number in this set, meaning that the item
is available for immediate checkout, and is counted as available
in the OPAC.

Statuses with an ID below 100 are not removable, and have special
meaning in the code.  Do not change them except to translate the
textual name.

You may add and remove statuses above 100, and these can be used
to remove items from normal circulation without affecting the rest
of the copy's values or its location.
$$;

CREATE TABLE config.net_access_level (
	id	SERIAL		PRIMARY KEY,
	name	TEXT		NOT NULL UNIQUE
);
COMMENT ON TABLE config.net_access_level IS $$
Patron Network Access level

This will be used to inform the in-library firewall of how much
internet access the using patron should be allowed.
$$;


CREATE TABLE config.remote_account (
    id          SERIAL  PRIMARY KEY,
    label       TEXT    NOT NULL,
    host        TEXT    NOT NULL,   -- name or IP, :port optional
    username    TEXT,               -- optional, since we could default to $USER
    password    TEXT,               -- optional, since we could use SSH keys, or anonymous login.
    account     TEXT,               -- aka profile or FTP "account" command
    path        TEXT,               -- aka directory
    owner       INT     NOT NULL,   -- REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
    last_activity TIMESTAMP WITH TIME ZONE
);

CREATE TABLE config.marc21_rec_type_map (
    code        TEXT    PRIMARY KEY,
    type_val    TEXT    NOT NULL,
    blvl_val    TEXT    NOT NULL
);

CREATE TABLE config.marc21_ff_pos_map (
    id          SERIAL  PRIMARY KEY,
    fixed_field TEXT    NOT NULL,
    tag         TEXT    NOT NULL,
    rec_type    TEXT    NOT NULL,
    start_pos   INT     NOT NULL,
    length      INT     NOT NULL,
    default_val TEXT    NOT NULL DEFAULT ' '
);

CREATE TABLE config.marc21_physical_characteristic_type_map (
    ptype_key   TEXT    PRIMARY KEY,
    label       TEXT    NOT NULL -- I18N
);

CREATE TABLE config.marc21_physical_characteristic_subfield_map (
    id          SERIAL  PRIMARY KEY,
    ptype_key   TEXT    NOT NULL REFERENCES config.marc21_physical_characteristic_type_map (ptype_key) ON DELETE CASCADE ON UPDATE CASCADE,
    subfield    TEXT    NOT NULL,
    start_pos   INT     NOT NULL,
    length      INT     NOT NULL,
    label       TEXT    NOT NULL -- I18N
);

CREATE TABLE config.marc21_physical_characteristic_value_map (
    id              SERIAL  PRIMARY KEY,
    value           TEXT    NOT NULL,
    ptype_subfield  INT     NOT NULL REFERENCES config.marc21_physical_characteristic_subfield_map (id),
    label           TEXT    NOT NULL -- I18N
);


CREATE TABLE config.z3950_source (
    name                TEXT    PRIMARY KEY,
    label               TEXT    NOT NULL UNIQUE,
    host                TEXT    NOT NULL,
    port                INT     NOT NULL,
    db                  TEXT    NOT NULL,
    record_format       TEXT    NOT NULL DEFAULT 'FI',
    transmission_format TEXT    NOT NULL DEFAULT 'usmarc',
    auth                BOOL    NOT NULL DEFAULT TRUE,
    use_perm            INT     -- REFERENCES permission.perm_list (id)
);

COMMENT ON TABLE config.z3950_source IS $$
Z39.50 Sources

Each row in this table represents a database searchable via Z39.50.
$$;

COMMENT ON COLUMN config.z3950_source.record_format IS $$
Z39.50 element set.
$$;

COMMENT ON COLUMN config.z3950_source.transmission_format IS $$
Z39.50 preferred record syntax..
$$;

COMMENT ON COLUMN config.z3950_source.use_perm IS $$
If set, this permission is required for the source to be listed in the staff
client Z39.50 interface.  Similar to permission.grp_tree.application_perm.
$$;

CREATE TABLE config.z3950_attr (
    id          SERIAL  PRIMARY KEY,
    source      TEXT    NOT NULL REFERENCES config.z3950_source (name) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    name        TEXT    NOT NULL,
    label       TEXT    NOT NULL,
    code        INT     NOT NULL,
    format      INT     NOT NULL,
    truncation  INT     NOT NULL DEFAULT 0,
    CONSTRAINT z_code_format_once_per_source UNIQUE (code,format,source)
);

CREATE TABLE config.z3950_source_credentials (
    id SERIAL PRIMARY KEY,
    owner INTEGER NOT NULL, -- REFERENCES actor.org_unit(id),
    source TEXT NOT NULL REFERENCES config.z3950_source(name) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    username TEXT,
    password TEXT,
    CONSTRAINT czsc_source_once_per_lib UNIQUE (source, owner)
);

CREATE TABLE config.i18n_locale (
    code        TEXT    PRIMARY KEY,
    marc_code   TEXT    NOT NULL, -- should exist in config.coded_value_map WHERE ctype = 'item_lang'
    name        TEXT    UNIQUE NOT NULL,
    description TEXT,
    rtl         BOOL    NOT NULL DEFAULT FALSE
);

CREATE TABLE config.i18n_core (
    id              BIGSERIAL   PRIMARY KEY,
    fq_field        TEXT        NOT NULL,
    identity_value  TEXT        NOT NULL,
    translation     TEXT        NOT NULL    REFERENCES config.i18n_locale (code) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    string          TEXT        NOT NULL
);

CREATE UNIQUE INDEX i18n_identity ON config.i18n_core (fq_field,identity_value,translation);

CREATE OR REPLACE FUNCTION oils_i18n_update_apply(old_ident TEXT, new_ident TEXT, hint TEXT) RETURNS VOID AS $_$
BEGIN

    EXECUTE $$
        UPDATE  config.i18n_core
          SET   identity_value = $$ || quote_literal(new_ident) || $$ 
          WHERE fq_field LIKE '$$ || hint || $$.%' 
                AND identity_value = $$ || quote_literal(old_ident) || $$::TEXT;$$;

    RETURN;

END;
$_$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION oils_i18n_id_tracking(/* hint */) RETURNS TRIGGER AS $_$
BEGIN
    PERFORM oils_i18n_update_apply( OLD.id::TEXT, NEW.id::TEXT, TG_ARGV[0]::TEXT );
    RETURN NEW;
END;
$_$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION oils_i18n_code_tracking(/* hint */) RETURNS TRIGGER AS $_$
BEGIN
    PERFORM oils_i18n_update_apply( OLD.code::TEXT, NEW.code::TEXT, TG_ARGV[0]::TEXT );
    RETURN NEW;
END;
$_$ LANGUAGE PLPGSQL;

-- this may grow to support full GNU gettext functionality
CREATE TABLE config.i18n_string (
    id              SERIAL      PRIMARY KEY,
    context         TEXT        NOT NULL, -- hint for translators to disambiguate
    string          TEXT        NOT NULL
);

CREATE TABLE config.billing_type (
    id              SERIAL  PRIMARY KEY,
    name            TEXT    NOT NULL,
    owner           INT     NOT NULL, -- REFERENCES actor.org_unit (id)
    default_price   NUMERIC(6,2),
    CONSTRAINT billing_type_once_per_lib UNIQUE (name, owner)
);

CREATE TABLE config.settings_group (
    name    TEXT PRIMARY KEY,
    label   TEXT UNIQUE NOT NULL -- I18N
);

CREATE TABLE config.org_unit_setting_type (
    name            TEXT    PRIMARY KEY,
    label           TEXT    UNIQUE NOT NULL,
    grp             TEXT    REFERENCES config.settings_group (name),
    description     TEXT,
    datatype        TEXT    NOT NULL DEFAULT 'string',
    fm_class        TEXT,
    view_perm       INT,
    update_perm     INT,
    --
    -- define valid datatypes
    --
    CONSTRAINT coust_valid_datatype CHECK ( datatype IN
    ( 'bool', 'integer', 'float', 'currency', 'interval',
      'date', 'string', 'object', 'array', 'link' ) ),
    --
    -- fm_class is meaningful only for 'link' datatype
    --
    CONSTRAINT coust_no_empty_link CHECK
    ( ( datatype =  'link' AND fm_class IS NOT NULL ) OR
      ( datatype <> 'link' AND fm_class IS NULL ) )
);

CREATE TABLE config.usr_setting_type (

    name TEXT PRIMARY KEY,
    opac_visible BOOL NOT NULL DEFAULT FALSE,
    label TEXT UNIQUE NOT NULL,
    description TEXT,
    grp             TEXT    REFERENCES config.settings_group (name),
    datatype TEXT NOT NULL DEFAULT 'string',
    fm_class TEXT,
    reg_default TEXT,

    --
    -- define valid datatypes
    --
    CONSTRAINT coust_valid_datatype CHECK ( datatype IN
    ( 'bool', 'integer', 'float', 'currency', 'interval',
        'date', 'string', 'object', 'array', 'link' ) ),

    --
    -- fm_class is meaningful only for 'link' datatype
    --
    CONSTRAINT coust_no_empty_link CHECK
    ( ( datatype = 'link' AND fm_class IS NOT NULL ) OR
        ( datatype <> 'link' AND fm_class IS NULL ) )

);

CREATE TABLE config.workstation_setting_type (
    name            TEXT    PRIMARY KEY,
    label           TEXT    UNIQUE NOT NULL,
    grp             TEXT    REFERENCES config.settings_group (name),
    description     TEXT,
    datatype        TEXT    NOT NULL DEFAULT 'string',
    fm_class        TEXT,
    --
    -- define valid datatypes
    --
    CONSTRAINT cwst_valid_datatype CHECK ( datatype IN
    ( 'bool', 'integer', 'float', 'currency', 'interval',
      'date', 'string', 'object', 'array', 'link' ) ),
    --
    -- fm_class is meaningful only for 'link' datatype
    --
    CONSTRAINT cwst_no_empty_link CHECK
    ( ( datatype =  'link' AND fm_class IS NOT NULL ) OR
      ( datatype <> 'link' AND fm_class IS NULL ) )
);

-- Prevent setting types from being both user and workstation settings.
CREATE OR REPLACE FUNCTION config.setting_is_user_or_ws()
RETURNS TRIGGER AS $FUNC$
BEGIN

    IF TG_TABLE_NAME = 'usr_setting_type' THEN
        PERFORM TRUE FROM config.workstation_setting_type cwst
            WHERE cwst.name = NEW.name;
        IF NOT FOUND THEN
            RETURN NULL;
        END IF;
    END IF;

    IF TG_TABLE_NAME = 'workstation_setting_type' THEN
        PERFORM TRUE FROM config.usr_setting_type cust
            WHERE cust.name = NEW.name;
        IF NOT FOUND THEN
            RETURN NULL;
        END IF;
    END IF;

    RAISE EXCEPTION 
        '% Cannot be used as both a user setting and a workstation setting.', 
        NEW.name;
END;
$FUNC$ LANGUAGE PLPGSQL STABLE;

CREATE CONSTRAINT TRIGGER check_setting_is_usr_or_ws
  AFTER INSERT OR UPDATE ON config.usr_setting_type
  FOR EACH ROW EXECUTE PROCEDURE config.setting_is_user_or_ws();

CREATE CONSTRAINT TRIGGER check_setting_is_usr_or_ws
  AFTER INSERT OR UPDATE ON config.workstation_setting_type
  FOR EACH ROW EXECUTE PROCEDURE config.setting_is_user_or_ws();



-- Some handy functions, based on existing ones, to provide optional ingest normalization

CREATE OR REPLACE FUNCTION public.left_trunc( TEXT, INT ) RETURNS TEXT AS $func$
        SELECT SUBSTRING($1,$2);
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.right_trunc( TEXT, INT ) RETURNS TEXT AS $func$
        SELECT SUBSTRING($1,1,$2);
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.split_date_range( TEXT ) RETURNS TEXT AS $func$
        SELECT REGEXP_REPLACE( $1, E'(\\d{4})-(\\d{4})', E'\\1 \\2', 'g' );
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.approximate_date( TEXT, TEXT ) RETURNS TEXT AS $func$
        SELECT REGEXP_REPLACE( $1, E'\\D', $2, 'g' );
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.approximate_low_date( TEXT ) RETURNS TEXT AS $func$
        SELECT approximate_date( $1, '0');
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.approximate_high_date( TEXT ) RETURNS TEXT AS $func$
        SELECT approximate_date( $1, '9');
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.content_or_null( TEXT ) RETURNS TEXT AS $func$
        SELECT CASE WHEN $1 ~ E'^\\s*$' THEN NULL ELSE $1 END
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.integer_or_null( TEXT ) RETURNS TEXT AS $func$
        SELECT CASE WHEN $1 ~ E'^\\d+$' THEN $1 ELSE NULL END
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.force_to_isbn13( TEXT ) RETURNS TEXT AS $func$
    use Business::ISBN;
    use strict;
    use warnings;

    # Find the first ISBN, force it to ISBN13 and return it

    my $input = shift;

    foreach my $word (split(/\s/, $input)) {
        my $isbn = Business::ISBN->new($word);

        # First check the checksum; if it is not valid, fix it and add the original
        # bad-checksum ISBN to the output
        if ($isbn && $isbn->is_valid_checksum() == Business::ISBN::BAD_CHECKSUM) {
            $isbn->fix_checksum();
        }

        # If we now have a valid ISBN, force it to ISBN13 and return it
        return $isbn->as_isbn13->isbn if ($isbn && $isbn->is_valid());
    }
    return undef;
$func$ LANGUAGE PLPERLU;

COMMENT ON FUNCTION public.force_to_isbn13(TEXT) IS $$
Inspired by translate_isbn1013

The force_to_isbn13 function takes an input ISBN and returns the ISBN13
version without hypens and with a repaired checksum if the checksum was bad
$$;


CREATE OR REPLACE FUNCTION public.translate_isbn1013( TEXT ) RETURNS TEXT AS $func$
    use Business::ISBN;
    use strict;
    use warnings;

    # For each ISBN found in a single string containing a set of ISBNs:
    #   * Normalize an incoming ISBN to have the correct checksum and no hyphens
    #   * Convert an incoming ISBN10 or ISBN13 to its counterpart and return

    my $input = shift;
    my $output = '';

    foreach my $word (split(/\s/, $input)) {
        my $isbn = Business::ISBN->new($word);

        # First check the checksum; if it is not valid, fix it and add the original
        # bad-checksum ISBN to the output
        if ($isbn && $isbn->is_valid_checksum() == Business::ISBN::BAD_CHECKSUM) {
            $output .= $isbn->isbn() . " ";
            $isbn->fix_checksum();
        }

        # If we now have a valid ISBN, convert it to its counterpart ISBN10/ISBN13
        # and add the normalized original ISBN to the output
        if ($isbn && $isbn->is_valid()) {
            my $isbn_xlated = ($isbn->type eq "ISBN13") ? $isbn->as_isbn10 : $isbn->as_isbn13;
            $output .= $isbn->isbn . " ";

            # If we successfully converted the ISBN to its counterpart, add the
            # converted ISBN to the output as well
            $output .= ($isbn_xlated->isbn . " ") if ($isbn_xlated);
        }
    }
    return $output if $output;

    # If there were no valid ISBNs, just return the raw input
    return $input;
$func$ LANGUAGE PLPERLU;

COMMENT ON FUNCTION public.translate_isbn1013(TEXT) IS $$
The translate_isbn1013 function takes an input ISBN and returns the
following in a single space-delimited string if the input ISBN is valid:
  - The normalized input ISBN (hyphens stripped)
  - The normalized input ISBN with a fixed checksum if the checksum was bad
  - The ISBN converted to its ISBN10 or ISBN13 counterpart, if possible
$$;

-- And ... a table in which to register them

CREATE TABLE config.index_normalizer (
        id              SERIAL  PRIMARY KEY,
        name            TEXT    UNIQUE NOT NULL,
        description     TEXT,
        func            TEXT    NOT NULL,
        param_count     INT     NOT NULL DEFAULT 0
);

CREATE TABLE config.metabib_field_index_norm_map (
        id      SERIAL  PRIMARY KEY,
        field   INT     NOT NULL REFERENCES config.metabib_field (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
        norm    INT     NOT NULL REFERENCES config.index_normalizer (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
        params  TEXT,
        pos     INT     NOT NULL DEFAULT 0
);

CREATE TABLE config.record_attr_definition (
    name        TEXT    PRIMARY KEY,
    label       TEXT    NOT NULL, -- I18N
    description TEXT,
    multi       BOOL    NOT NULL DEFAULT TRUE,  -- will store all values from a record
    filter      BOOL    NOT NULL DEFAULT TRUE,  -- becomes QP filter if true
    sorter      BOOL    NOT NULL DEFAULT FALSE, -- becomes QP sort() axis if true
    composite   BOOL    NOT NULL DEFAULT FALSE, -- its values are derived from others

-- For pre-extracted fields. Takes the first occurance, uses naive subfield ordering
    tag         TEXT, -- LIKE format
    sf_list     TEXT, -- pile-o-values, like 'abcd' for a and b and c and d

-- This is used for both tag/sf and xpath entries
    joiner      TEXT,

-- For xpath-extracted attrs
    xpath       TEXT,
    format      TEXT    REFERENCES config.xml_transform (name) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    start_pos   INT,
    string_len  INT,

-- For fixed fields
    fixed_field TEXT, -- should exist in config.marc21_ff_pos_map.fixed_field

-- For phys-char fields
    phys_char_sf    INT REFERENCES config.marc21_physical_characteristic_subfield_map (id),

-- Source of vocabulary terms for this record attribute;
-- typically will be a URI referring to a SKOS vocabulary
    vocabulary  TEXT
);

CREATE TABLE config.record_attr_index_norm_map (
    id      SERIAL  PRIMARY KEY,
    attr    TEXT    NOT NULL REFERENCES config.record_attr_definition (name) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    norm    INT     NOT NULL REFERENCES config.index_normalizer (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    params  TEXT,
    pos     INT     NOT NULL DEFAULT 0
);

CREATE TABLE config.coded_value_map (
    id              SERIAL  PRIMARY KEY,
    ctype           TEXT    NOT NULL REFERENCES config.record_attr_definition (name) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    code            TEXT    NOT NULL,
    value           TEXT    NOT NULL,
    description     TEXT,
    opac_visible    BOOL    NOT NULL DEFAULT TRUE, -- For TPac selectors
    search_label    TEXT,
    is_simple       BOOL    NOT NULL DEFAULT FALSE,
    concept_uri     TEXT    -- URI expressing the SKOS concept that the
                            -- coded value represents
);

CREATE INDEX config_coded_value_map_ctype_idx ON config.coded_value_map (ctype);

CREATE VIEW config.language_map AS SELECT code, value FROM config.coded_value_map WHERE ctype = 'item_lang';
CREATE VIEW config.bib_level_map AS SELECT code, value FROM config.coded_value_map WHERE ctype = 'bib_level';
CREATE VIEW config.item_form_map AS SELECT code, value FROM config.coded_value_map WHERE ctype = 'item_form';
CREATE VIEW config.item_type_map AS SELECT code, value FROM config.coded_value_map WHERE ctype = 'item_type';
CREATE VIEW config.lit_form_map AS SELECT code, value, description FROM config.coded_value_map WHERE ctype = 'lit_form';
CREATE VIEW config.audience_map AS SELECT code, value, description FROM config.coded_value_map WHERE ctype = 'audience';
CREATE VIEW config.videorecording_format_map AS SELECT code, value FROM config.coded_value_map WHERE ctype = 'vr_format';

CREATE OR REPLACE FUNCTION config.update_coded_value_map(in_ctype TEXT, in_code TEXT, in_value TEXT, in_description TEXT DEFAULT NULL, in_opac_visible BOOL DEFAULT NULL, in_search_label TEXT DEFAULT NULL, in_is_simple BOOL DEFAULT NULL, add_only BOOL DEFAULT FALSE) RETURNS VOID AS $f$
DECLARE
    current_row config.coded_value_map%ROWTYPE;
BEGIN
    -- Look for a current value
    SELECT INTO current_row * FROM config.coded_value_map WHERE ctype = in_ctype AND code = in_code;
    -- If we have one..
    IF FOUND AND NOT add_only THEN
        -- Update anything we were handed
        current_row.value := COALESCE(current_row.value, in_value);
        current_row.description := COALESCE(current_row.description, in_description);
        current_row.opac_visible := COALESCE(current_row.opac_visible, in_opac_visible);
        current_row.search_label := COALESCE(current_row.search_label, in_search_label);
        current_row.is_simple := COALESCE(current_row.is_simple, in_is_simple);
        UPDATE config.coded_value_map
            SET
                value = current_row.value,
                description = current_row.description,
                opac_visible = current_row.opac_visible,
                search_label = current_row.search_label,
                is_simple = current_row.is_simple
            WHERE id = current_row.id;
    ELSE
        INSERT INTO config.coded_value_map(ctype, code, value, description, opac_visible, search_label, is_simple) VALUES
            (in_ctype, in_code, in_value, in_description, COALESCE(in_opac_visible, TRUE), in_search_label, COALESCE(in_is_simple, FALSE));
    END IF;
END;
$f$ LANGUAGE PLPGSQL;

CREATE TABLE config.composite_attr_entry_definition(
    coded_value INT  PRIMARY KEY NOT NULL REFERENCES config.coded_value_map (id) ON UPDATE CASCADE ON DELETE CASCADE,
    definition  TEXT    NOT NULL -- JSON
);

-- List applied db patches that are deprecated by (and block the application of) my_db_patch
CREATE OR REPLACE FUNCTION evergreen.upgrade_list_applied_deprecates ( my_db_patch TEXT ) RETURNS SETOF evergreen.patch AS $$
    SELECT  DISTINCT l.version
      FROM  config.upgrade_log l
            JOIN config.db_patch_dependencies d ON (l.version = ANY(d.deprecates))
      WHERE d.db_patch = $1
$$ LANGUAGE SQL;

-- List applied db patches that are superseded by (and block the application of) my_db_patch
CREATE OR REPLACE FUNCTION evergreen.upgrade_list_applied_supersedes ( my_db_patch TEXT ) RETURNS SETOF evergreen.patch AS $$
    SELECT  DISTINCT l.version
      FROM  config.upgrade_log l
            JOIN config.db_patch_dependencies d ON (l.version = ANY(d.supersedes))
      WHERE d.db_patch = $1
$$ LANGUAGE SQL;

-- List applied db patches that deprecates (and block the application of) my_db_patch
CREATE FUNCTION evergreen.upgrade_list_applied_deprecated ( my_db_patch TEXT ) RETURNS SETOF TEXT AS $$
    SELECT  db_patch
      FROM  config.db_patch_dependencies
      WHERE ARRAY[$1]::TEXT[] && deprecates
$$ LANGUAGE SQL;

-- List applied db patches that supersedes (and block the application of) my_db_patch
CREATE FUNCTION evergreen.upgrade_list_applied_superseded ( my_db_patch TEXT ) RETURNS SETOF TEXT AS $$
    SELECT  db_patch
      FROM  config.db_patch_dependencies
      WHERE ARRAY[$1]::TEXT[] && supersedes
$$ LANGUAGE SQL;

-- Make sure that no deprecated or superseded db patches are currently applied
CREATE OR REPLACE FUNCTION evergreen.upgrade_verify_no_dep_conflicts ( my_db_patch TEXT ) RETURNS BOOL AS $$
    SELECT  COUNT(*) = 0
      FROM  (SELECT * FROM evergreen.upgrade_list_applied_deprecates( $1 )
                UNION
             SELECT * FROM evergreen.upgrade_list_applied_supersedes( $1 )
                UNION
             SELECT * FROM evergreen.upgrade_list_applied_deprecated( $1 )
                UNION
             SELECT * FROM evergreen.upgrade_list_applied_superseded( $1 ))x
$$ LANGUAGE SQL;

-- Raise an exception if there are, in fact, dep/sup conflict
CREATE OR REPLACE FUNCTION evergreen.upgrade_deps_block_check ( my_db_patch TEXT, my_applied_to TEXT ) RETURNS BOOL AS $$
DECLARE 
    deprecates TEXT;
    supersedes TEXT;
BEGIN
    IF NOT evergreen.upgrade_verify_no_dep_conflicts( my_db_patch ) THEN
        SELECT  STRING_AGG(patch, ', ') INTO deprecates FROM evergreen.upgrade_list_applied_deprecates(my_db_patch);
        SELECT  STRING_AGG(patch, ', ') INTO supersedes FROM evergreen.upgrade_list_applied_supersedes(my_db_patch);
        RAISE EXCEPTION '
Upgrade script % can not be applied:
  applied deprecated scripts %
  applied superseded scripts %
  deprecated by %
  superseded by %',
            my_db_patch,
            (SELECT ARRAY_AGG(patch) FROM evergreen.upgrade_list_applied_deprecates(my_db_patch)),
            (SELECT ARRAY_AGG(patch) FROM evergreen.upgrade_list_applied_supersedes(my_db_patch)),
            evergreen.upgrade_list_applied_deprecated(my_db_patch),
            evergreen.upgrade_list_applied_superseded(my_db_patch);
    END IF;

    INSERT INTO config.upgrade_log (version, applied_to) VALUES (my_db_patch, my_applied_to);
    RETURN TRUE;
END;
$$ LANGUAGE PLPGSQL;

CREATE TABLE config.barcode_completion (
    id          SERIAL PRIMARY KEY,
    active      BOOL NOT NULL DEFAULT true,
    org_unit    INT NOT NULL, -- REFERENCES actor.org_unit(id) DEFERRABLE INITIALLY DEFERRED,
    prefix      TEXT,
    suffix      TEXT,
    length      INT NOT NULL DEFAULT 0,
    padding     TEXT,
    padding_end BOOL NOT NULL DEFAULT false,
    asset       BOOL NOT NULL DEFAULT true,
    actor       BOOL NOT NULL DEFAULT true
);

CREATE TYPE evergreen.barcode_set AS (type TEXT, id BIGINT, barcode TEXT);

-- Add support for logging, only keep the most recent five rows for each category. 


CREATE TABLE config.org_unit_setting_type_log (
    id              BIGSERIAL   PRIMARY KEY,
    date_applied    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    org             INT,   --REFERENCES actor.org_unit (id),
    original_value  TEXT,
    new_value       TEXT,
    field_name      TEXT      REFERENCES config.org_unit_setting_type (name) DEFERRABLE INITIALLY DEFERRED
);

COMMENT ON TABLE config.org_unit_setting_type_log IS $$
Org Unit setting Logs

This table contains the most recent changes to each setting 
in actor.org_unit_setting, allowing for mistakes to be undone.
This is NOT meant to be an auditor, but rather an undo/redo.
$$;

CREATE OR REPLACE FUNCTION evergreen.limit_oustl() RETURNS TRIGGER AS $oustl_limit$
    BEGIN
        -- Only keeps the most recent five settings changes.
        DELETE FROM config.org_unit_setting_type_log WHERE field_name = NEW.field_name AND org = NEW.org AND date_applied NOT IN 
        (SELECT date_applied FROM config.org_unit_setting_type_log WHERE field_name = NEW.field_name AND org = NEW.org ORDER BY date_applied DESC LIMIT 4);
        
        IF (TG_OP = 'UPDATE') THEN
            RETURN NEW;
        ELSIF (TG_OP = 'INSERT') THEN
            RETURN NEW;
        END IF;
        RETURN NULL;
    END;
$oustl_limit$ LANGUAGE plpgsql;

CREATE TRIGGER limit_logs_oust
    BEFORE INSERT OR UPDATE ON config.org_unit_setting_type_log
    FOR EACH ROW EXECUTE PROCEDURE limit_oustl();

CREATE TABLE config.sms_carrier (
    id              SERIAL PRIMARY KEY,
    region          TEXT,
    name            TEXT,
    email_gateway   TEXT,
    active          BOOLEAN DEFAULT TRUE
);

CREATE TYPE config.usr_activity_group AS ENUM ('authen','authz','circ','hold','search','mfa');

CREATE TABLE config.usr_activity_type (
    id          SERIAL                      PRIMARY KEY, 
    ewho        TEXT,
    ewhat       TEXT,
    ehow        TEXT,
    label       TEXT                        NOT NULL, -- i18n
    egroup      config.usr_activity_group   NOT NULL,
    enabled     BOOL                        NOT NULL DEFAULT TRUE,
    transient   BOOL                        NOT NULL DEFAULT TRUE,
    CONSTRAINT  one_of_wwh CHECK (COALESCE(ewho,ewhat,ehow) IS NOT NULL)
);

CREATE UNIQUE INDEX unique_wwh ON config.usr_activity_type 
    (COALESCE(ewho,''), COALESCE (ewhat,''), COALESCE(ehow,''));

CREATE TABLE config.filter_dialog_interface (
    key         TEXT                        PRIMARY KEY,
    description TEXT
);  

CREATE TABLE config.filter_dialog_filter_set (
    id          SERIAL                      PRIMARY KEY,
    name        TEXT                        NOT NULL,
    owning_lib  INT                         NOT NULL, -- REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
    creator     INT                         NOT NULL, -- REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    create_time TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
    interface   TEXT                        NOT NULL REFERENCES config.filter_dialog_interface (key) DEFERRABLE INITIALLY DEFERRED,
    filters     TEXT                        NOT NULL, -- CHECK (evergreen.is_json(filters))
    CONSTRAINT cfdfs_name_once_per_lib UNIQUE (name, owning_lib)
);

CREATE TABLE config.best_hold_order(
    id          SERIAL      PRIMARY KEY,
    name        TEXT        UNIQUE,   -- i18n
    pprox       INT, -- copy capture <-> pickup lib prox
    hprox       INT, -- copy circ lib <-> request lib prox
    owning_lib_to_home_lib_prox      INT, -- copy owning lib <-> user home lib prox
    aprox       INT, -- copy circ lib <-> pickup lib ADJUSTED prox on ahcm
    approx      INT, -- copy capture <-> pickup lib ADJUSTED prox from function
    priority    INT, -- group hold priority
    cut         INT, -- cut-in-line
    depth       INT, -- selection depth
    htime       INT, -- time since last home-lib circ exceeds org-unit setting
    rtime       INT, -- request time
    shtime      INT  -- time since copy last trip home exceeds org-unit setting
);

-- At least one of these columns must contain a non-null value
ALTER TABLE config.best_hold_order ADD CHECK ((
    pprox IS NOT NULL OR
    hprox IS NOT NULL OR
    owning_lib_to_home_lib_prox IS NOT NULL OR
    aprox IS NOT NULL OR
    priority IS NOT NULL OR
    cut IS NOT NULL OR
    depth IS NOT NULL OR
    htime IS NOT NULL OR
    rtime IS NOT NULL
));

CREATE OR REPLACE FUNCTION 
    evergreen.z3950_attr_name_is_valid() RETURNS TRIGGER AS $func$
    BEGIN

      PERFORM * FROM config.z3950_attr WHERE name = NEW.z3950_attr_type;

      IF FOUND THEN
        RETURN NULL;
      END IF;

      RAISE EXCEPTION '% is not a valid Z39.50 attribute type', NEW.z3950_attr_type;

    END;
$func$ LANGUAGE PLPGSQL STABLE;

COMMENT ON FUNCTION evergreen.z3950_attr_name_is_valid() IS $$
Used by a config.z3950_index_field_map constraint trigger
to verify z3950_attr_type maps.
$$;

-- drop these in down here since they reference config.metabib_field
-- and config.record_attr_definition
CREATE TABLE config.z3950_index_field_map (
    id              SERIAL  PRIMARY KEY,
    label           TEXT    NOT NULL, -- i18n
    metabib_field   INTEGER REFERENCES config.metabib_field(id) ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    record_attr     TEXT    REFERENCES config.record_attr_definition(name),
    z3950_attr      INTEGER REFERENCES config.z3950_attr(id),
    z3950_attr_type TEXT,-- REFERENCES config.z3950_attr(name)
    CONSTRAINT metabib_field_or_record_attr CHECK (
        metabib_field IS NOT NULL OR 
        record_attr IS NOT NULL
    ),
    CONSTRAINT attr_or_attr_type CHECK (
        z3950_attr IS NOT NULL OR 
        z3950_attr_type IS NOT NULL
    )
);

CREATE CONSTRAINT TRIGGER valid_z3950_attr_type AFTER INSERT OR UPDATE ON config.z3950_index_field_map
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (NEW.z3950_attr_type IS NOT NULL)
    EXECUTE PROCEDURE evergreen.z3950_attr_name_is_valid();

CREATE TABLE config.marc_format (
    id                  SERIAL PRIMARY KEY,
    code                TEXT NOT NULL,
    name                TEXT NOT NULL
);
COMMENT ON TABLE config.marc_format IS $$
List of MARC formats supported by this Evergreen
database. This exists primarily as a hook for future
support of UNIMARC, though whether that will ever
happen remains to be seen.
$$;

CREATE TYPE config.marc_record_type AS ENUM ('biblio', 'authority', 'serial');

CREATE TABLE config.marc_field (
    id                  SERIAL PRIMARY KEY,
    marc_format         INTEGER NOT NULL
                        REFERENCES config.marc_format (id) DEFERRABLE INITIALLY DEFERRED,
    marc_record_type    config.marc_record_type NOT NULL,
    tag                 CHAR(3) NOT NULL,
    name                TEXT,
    description         TEXT,
    fixed_field         BOOLEAN,
    repeatable          BOOLEAN,
    mandatory           BOOLEAN,
    hidden              BOOLEAN,
    owner               INTEGER -- REFERENCES actor.org_unit (id)
                        -- if the owner is null, the data about the field is
                        -- assumed to come from the controlling MARC standard
);

COMMENT ON TABLE config.marc_field IS $$
This table stores a list of MARC fields recognized by the Evergreen
instance.  Note that we're not aiming for completely generic ISO2709
support: we're assuming things like three characters for a tag,
one-character subfield labels, two indicators per variable data field,
and the like, all of which are technically specializations of ISO2709.

Of particular significance is the owner column; if it's set to a null
value, the field definition is assumed to come from a national
standards body; if it's set to a non-null value, the field definition
is an OU-level addition to or override of the standard.
$$;

CREATE INDEX config_marc_field_tag_idx ON config.marc_field (tag);
CREATE INDEX config_marc_field_owner_idx ON config.marc_field (owner);

CREATE UNIQUE INDEX config_standard_marc_tags_are_unique
    ON config.marc_field(marc_format, marc_record_type, tag)
    WHERE owner IS NULL;
ALTER TABLE config.marc_field
    ADD CONSTRAINT config_standard_marc_tags_are_fully_specified
    CHECK ((owner IS NOT NULL) OR
           (
                owner IS NULL AND
                repeatable IS NOT NULL AND
                mandatory IS NOT NULL AND
                hidden IS NOT NULL
           )
          );

CREATE TABLE config.marc_subfield (
    id                  SERIAL PRIMARY KEY,
    marc_format         INTEGER NOT NULL
                        REFERENCES config.marc_format (id) DEFERRABLE INITIALLY DEFERRED,
    marc_record_type    config.marc_record_type NOT NULL,
    tag                 CHAR(3) NOT NULL,
    code                CHAR(1) NOT NULL,
    description         TEXT,
    repeatable          BOOLEAN,
    mandatory           BOOLEAN,
    hidden              BOOLEAN,
    value_ctype         TEXT
                        REFERENCES config.record_attr_definition (name)
                            DEFERRABLE INITIALLY DEFERRED,
    owner               INTEGER -- REFERENCES actor.org_unit (id)
                        -- if the owner is null, the data about the subfield is
                        -- assumed to come from the controlling MARC standard
);

COMMENT ON TABLE config.marc_subfield IS $$
This table stores the list of subfields recognized by this Evergreen
instance.  As with config.marc_field, of particular significance is the
owner column; if it's set to a null value, the subfield definition is
assumed to come from a national standards body; if it's set to a non-null
value, the subfield definition is an OU-level addition to or override
of the standard.
$$;

CREATE INDEX config_marc_subfield_tag_code_idx ON config.marc_subfield (tag, code);
CREATE UNIQUE INDEX config_standard_marc_subfields_are_unique
    ON config.marc_subfield(marc_format, marc_record_type, tag, code)
    WHERE owner IS NULL;
ALTER TABLE config.marc_subfield
    ADD CONSTRAINT config_standard_marc_subfields_are_fully_specified
    CHECK ((owner IS NOT NULL) OR
           (
                owner IS NULL AND
                repeatable IS NOT NULL AND
                mandatory IS NOT NULL AND
                hidden IS NOT NULL
           )
          );

CREATE TABLE config.copy_tag_type (
    code            TEXT NOT NULL PRIMARY KEY,
    label           TEXT NOT NULL,
    owner           INTEGER NOT NULL -- REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX config_copy_tag_type_owner_idx
    ON config.copy_tag_type (owner);

CREATE TABLE config.hold_type (
    id          SERIAL,
    hold_type   TEXT UNIQUE,
    description TEXT
);

INSERT INTO config.hold_type (hold_type,description) VALUES
    ('C','Copy Hold'),
    ('V','Volume Hold'),
    ('T','Title Hold'),
    ('M','Metarecord Hold'),
    ('R','Recall Hold'),
    ('F','Force Hold'),
    ('I','Issuance Hold'),
    ('P','Part Hold')
;

CREATE TABLE config.print_template (
    id           SERIAL PRIMARY KEY,
    name         TEXT NOT NULL, 
    label        TEXT NOT NULL, -- i18n
    owner        INT NOT NULL, -- REFERENCES actor.org_unit (id)
    active       BOOLEAN NOT NULL DEFAULT FALSE,
    locale       TEXT REFERENCES config.i18n_locale(code) 
                 ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    content_type TEXT NOT NULL DEFAULT 'text/html',
    template     TEXT NOT NULL,
    CONSTRAINT   name_once_per_lib UNIQUE (owner, name),
    CONSTRAINT   label_once_per_lib UNIQUE (owner, label)
);

CREATE TABLE config.carousel_type (
    id                          SERIAL PRIMARY KEY,
    name                        TEXT NOT NULL,
    automatic                   BOOLEAN NOT NULL DEFAULT TRUE,
    filter_by_age               BOOLEAN NOT NULL DEFAULT FALSE,
    filter_by_copy_owning_lib   BOOLEAN NOT NULL DEFAULT FALSE,
    filter_by_copy_location     BOOLEAN NOT NULL DEFAULT FALSE
);

INSERT INTO config.carousel_type
    (id, name,                               automatic, filter_by_age, filter_by_copy_owning_lib, filter_by_copy_location)
VALUES
    (1, 'Manual',                            FALSE,     FALSE,         FALSE,                     FALSE),
    (2, 'Newly Catalogued Items',            TRUE,      TRUE,          TRUE,                      TRUE),
    (3, 'Recently Returned Items',           TRUE,      TRUE,          TRUE,                      TRUE),
    (4, 'Top Circulated Items',              TRUE,      TRUE,          TRUE,                      FALSE),
    (5, 'Newest Items By Shelving Location', TRUE,      TRUE,          TRUE,                      FALSE)
;

SELECT SETVAL('config.carousel_type_id_seq'::TEXT, 100);

CREATE TABLE config.geolocation_service (
    id           SERIAL PRIMARY KEY,
    active       BOOLEAN,
    owner        INT NOT NULL, -- REFERENCES actor.org_unit (id)
    name         TEXT,
    service_code TEXT,
    api_key      TEXT
);

CREATE TABLE config.ui_staff_portal_page_entry_type (
    code        TEXT PRIMARY KEY,
    label       TEXT NOT NULL
);

CREATE TABLE config.ui_staff_portal_page_entry (
    id          SERIAL PRIMARY KEY,
    page_col    INTEGER NOT NULL,
    col_pos     INTEGER NOT NULL,
    entry_type  TEXT NOT NULL, -- REFERENCES config.ui_staff_portal_page_entry_type(code)
    label       TEXT,
    image_url   TEXT,
    target_url  TEXT,
    url_newtab  BOOLEAN,
    entry_text  TEXT,
    owner       INT NOT NULL -- REFERENCES actor.org_unit (id)
);

-- Add OpenAthens Integration
CREATE TABLE config.openathens_uid_field (
    id      SERIAL  PRIMARY KEY,
    name    TEXT    NOT NULL
);

INSERT INTO config.openathens_uid_field
    (id, name)
VALUES
    (1,'id'),
    (2,'usrname')
;

SELECT SETVAL('config.openathens_uid_field_id_seq'::TEXT, 100);

CREATE TABLE config.openathens_name_field (
    id      SERIAL  PRIMARY KEY,
    name    TEXT    NOT NULL
);

INSERT INTO config.openathens_name_field
    (id, name)
VALUES
    (1,'id'),
    (2,'usrname'),
    (3,'fullname')
;

SELECT SETVAL('config.openathens_name_field_id_seq'::TEXT, 100);

CREATE TABLE config.openathens_identity (
    id                          SERIAL  PRIMARY KEY,
    active                      BOOL    NOT NULL DEFAULT true,
    org_unit                    INT     NOT NULL, -- REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    api_key                     TEXT    NOT NULL,
    connection_id               TEXT    NOT NULL,
    connection_uri              TEXT    NOT NULL,
    auto_signon_enabled         BOOL    NOT NULL DEFAULT true,
    auto_signout_enabled        BOOL    NOT NULL DEFAULT false,
    unique_identifier           INT     NOT NULL REFERENCES config.openathens_uid_field (id) DEFAULT 1,
    display_name                INT     NOT NULL REFERENCES config.openathens_name_field (id) DEFAULT 1,
    release_prefix              BOOL    NOT NULL DEFAULT false,
    release_first_given_name    BOOL    NOT NULL DEFAULT false,
    release_second_given_name   BOOL    NOT NULL DEFAULT false,
    release_family_name         BOOL    NOT NULL DEFAULT false,
    release_suffix              BOOL    NOT NULL DEFAULT false,
    release_email               BOOL    NOT NULL DEFAULT false,
    release_home_ou             BOOL    NOT NULL DEFAULT false,
    release_barcode             BOOL    NOT NULL DEFAULT false
);

CREATE TABLE config.mfa_factor (
    name        TEXT    PRIMARY KEY,
    label       TEXT    NOT NULL,
    description TEXT    NOT NULL
);

CREATE TABLE config.patron_loader_header_map (
    id SERIAL,
    org_unit INTEGER NOT NULL, -- REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED;
    import_header TEXT NOT NULL,
    default_header TEXT NOT NULL
);

CREATE TABLE config.patron_loader_value_map (
    id SERIAL,
    org_unit INTEGER NOT NULL,  -- REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED;
    mapping_type TEXT NOT NULL,
    import_value TEXT NOT NULL,
    native_value TEXT NOT NULL
);

COMMIT;
