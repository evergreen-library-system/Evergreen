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

DROP SCHEMA IF EXISTS asset CASCADE;

BEGIN;

CREATE SCHEMA asset;

CREATE TABLE asset.copy_location (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL,
	owning_lib	INT	NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	holdable	BOOL	NOT NULL DEFAULT TRUE,
	hold_verify	BOOL	NOT NULL DEFAULT FALSE,
	opac_visible	BOOL	NOT NULL DEFAULT TRUE,
	circulate	BOOL	NOT NULL DEFAULT TRUE,
	label_prefix	TEXT,
	label_suffix	TEXT,
	checkin_alert	BOOL	NOT NULL DEFAULT FALSE,
	deleted		BOOL	NOT NULL DEFAULT FALSE,
	url		TEXT
);
CREATE UNIQUE INDEX acl_name_once_per_lib ON asset.copy_location (name, owning_lib) WHERE deleted = FALSE OR deleted IS FALSE;

CREATE TABLE asset.copy_location_order
(
        id              SERIAL           PRIMARY KEY,
        location        INT              NOT NULL
                                             REFERENCES asset.copy_location
                                             ON DELETE CASCADE
                                             DEFERRABLE INITIALLY DEFERRED,
        org             INT              NOT NULL
                                             REFERENCES actor.org_unit
                                             ON DELETE CASCADE
                                             DEFERRABLE INITIALLY DEFERRED,
        position        INT              NOT NULL DEFAULT 0,
        CONSTRAINT acplo_once_per_org UNIQUE ( location, org )
);

CREATE TABLE asset.copy_location_group (
    id              SERIAL  PRIMARY KEY,
    name            TEXT    NOT NULL, -- i18n
    owner           INT     NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    pos             INT     NOT NULL DEFAULT 0,
    top             BOOL    NOT NULL DEFAULT FALSE,
    opac_visible    BOOL    NOT NULL DEFAULT TRUE,
    CONSTRAINT lgroup_once_per_owner UNIQUE (owner,name)
);

CREATE TABLE asset.copy_location_group_map (
    id       SERIAL PRIMARY KEY,
    location    INT     NOT NULL REFERENCES asset.copy_location (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    lgroup      INT     NOT NULL REFERENCES asset.copy_location_group (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT  lgroup_once_per_group UNIQUE (lgroup,location)
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
	deleted		BOOL				NOT NULL DEFAULT FALSE,
	floating        INT,
	dummy_isbn      TEXT,
	status_changed_time TIMESTAMP WITH TIME ZONE,
	active_date TIMESTAMP WITH TIME ZONE,
	mint_condition      BOOL        NOT NULL DEFAULT TRUE,
    cost    NUMERIC(8,2)
);
CREATE UNIQUE INDEX copy_barcode_key ON asset.copy (barcode) WHERE deleted = FALSE OR deleted IS FALSE;
CREATE INDEX cp_cn_idx ON asset.copy (call_number);
CREATE INDEX cp_avail_cn_idx ON asset.copy (call_number);
CREATE INDEX cp_creator_idx  ON asset.copy ( creator );
CREATE INDEX cp_editor_idx   ON asset.copy ( editor );
CREATE INDEX cp_create_date  ON asset.copy (create_date);
CREATE INDEX cp_extant_by_circ_lib_idx ON asset.copy(circ_lib) WHERE deleted = FALSE OR deleted IS FALSE;
CREATE RULE protect_copy_delete AS ON DELETE TO asset.copy DO INSTEAD UPDATE asset.copy SET deleted = TRUE WHERE OLD.id = asset.copy.id RETURNING *;

CREATE TABLE asset.copy_part_map (
    id          SERIAL  PRIMARY KEY,
    target_copy BIGINT  NOT NULL, -- points o asset.copy
    part        INT     NOT NULL REFERENCES biblio.monograph_part (id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX copy_part_map_cp_part_idx ON asset.copy_part_map (target_copy, part);

CREATE TABLE asset.copy_inventory (
    id                          SERIAL                      PRIMARY KEY,
    inventory_workstation       INTEGER                     REFERENCES actor.workstation (id) DEFERRABLE INITIALLY DEFERRED,
    inventory_date              TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
    copy                        BIGINT                      NOT NULL
);
CREATE INDEX copy_inventory_copy_idx ON asset.copy_inventory (copy);
CREATE UNIQUE INDEX asset_copy_inventory_date_once_per_copy ON asset.copy_inventory (inventory_date, copy);

CREATE OR REPLACE FUNCTION asset.copy_may_float_to_inventory_workstation() RETURNS TRIGGER AS $func$
DECLARE
    copy asset.copy%ROWTYPE;
    workstation actor.workstation%ROWTYPE;
BEGIN
    SELECT * INTO copy FROM asset.copy WHERE id = NEW.copy;
    IF FOUND THEN
        SELECT * INTO workstation FROM actor.workstation WHERE id = NEW.inventory_workstation;
        IF FOUND THEN
           IF copy.floating IS NULL THEN
              IF copy.circ_lib <> workstation.owning_lib THEN
                 RAISE EXCEPTION 'Inventory workstation owning lib (%) does not match copy circ lib (%).',
                       workstation.owning_lib, copy.circ_lib;
              END IF;
           ELSE
              IF NOT evergreen.can_float(copy.floating, copy.circ_lib, workstation.owning_lib) THEN
                 RAISE EXCEPTION 'Copy (%) cannot float to inventory workstation owning lib (%).',
                       copy.id, workstation.owning_lib;
              END IF;
           END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL VOLATILE COST 50;

CREATE CONSTRAINT TRIGGER asset_copy_inventory_allowed_trig
        AFTER UPDATE OR INSERT ON asset.copy_inventory
        DEFERRABLE FOR EACH ROW EXECUTE PROCEDURE asset.copy_may_float_to_inventory_workstation();

CREATE VIEW asset.latest_inventory (id, inventory_workstation, inventory_date, copy) AS
SELECT DISTINCT ON (copy) id, inventory_workstation, inventory_date, copy
FROM asset.copy_inventory
ORDER BY copy, inventory_date DESC;

CREATE OR REPLACE FUNCTION asset.acp_status_changed()
RETURNS TRIGGER AS $$
BEGIN
	IF NEW.status <> OLD.status AND NOT (NEW.status = 0 AND OLD.status = 7) THEN
        NEW.status_changed_time := now();
        IF NEW.active_date IS NULL AND NEW.status IN (SELECT id FROM config.copy_status WHERE copy_active = true) THEN
            NEW.active_date := now();
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Need to check on initial create. Fast adds, manual edit of status at create, etc.
CREATE OR REPLACE FUNCTION asset.acp_created()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.active_date IS NULL AND NEW.status IN (SELECT id FROM config.copy_status WHERE copy_active = true) THEN
        NEW.active_date := now();
    END IF;
    IF NEW.status_changed_time IS NULL THEN
        NEW.status_changed_time := now();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER acp_status_changed_trig
    BEFORE UPDATE ON asset.copy
    FOR EACH ROW EXECUTE PROCEDURE asset.acp_status_changed();

CREATE TRIGGER acp_created_trig
    BEFORE INSERT ON asset.copy
    FOR EACH ROW EXECUTE PROCEDURE asset.acp_created();

CREATE OR REPLACE FUNCTION asset.acp_location_fixer()
RETURNS TRIGGER AS $$
DECLARE
    new_copy_location INT;
BEGIN
    IF (TG_OP = 'UPDATE') THEN
        IF NEW.location = OLD.location AND NEW.call_number = OLD.call_number AND NEW.circ_lib = OLD.circ_lib THEN
            RETURN NEW;
        END IF;
    END IF;
    SELECT INTO new_copy_location acpl.id FROM asset.copy_location acpl JOIN actor.org_unit_ancestors_distance((SELECT owning_lib FROM asset.call_number WHERE id = NEW.call_number)) aouad ON acpl.owning_lib = aouad.id WHERE deleted IS FALSE AND name = (SELECT name FROM asset.copy_location WHERE id = NEW.location) ORDER BY distance LIMIT 1;
    IF new_copy_location IS NULL THEN
        SELECT INTO new_copy_location acpl.id FROM asset.copy_location acpl JOIN actor.org_unit_ancestors_distance(NEW.circ_lib) aouad ON acpl.owning_lib = aouad.id WHERE deleted IS FALSE AND name = (SELECT name FROM asset.copy_location WHERE id = NEW.location) ORDER BY distance LIMIT 1;
    END IF;
    IF new_copy_location IS NOT NULL THEN
        NEW.location = new_copy_location;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER acp_location_fixer_trig
    BEFORE INSERT OR UPDATE OF location, call_number, circ_lib ON asset.copy
    FOR EACH ROW EXECUTE PROCEDURE asset.acp_location_fixer();

CREATE TABLE asset.stat_cat_sip_fields (
    field   CHAR(2) PRIMARY KEY,
    name    TEXT    NOT NULL,
    one_only BOOL    NOT NULL DEFAULT FALSE
);
COMMENT ON TABLE asset.stat_cat_sip_fields IS $$
Asset Statistical Category SIP Fields

Contains the list of valid SIP Field identifiers for
Statistical Categories.
$$;

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
	required	BOOL	NOT NULL DEFAULT FALSE,
    sip_field   CHAR(2) REFERENCES asset.stat_cat_sip_fields(field) ON UPDATE CASCADE ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    sip_format  TEXT,
    checkout_archive    BOOL NOT NULL DEFAULT FALSE,
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
CREATE INDEX scecm_owning_copy_idx ON asset.stat_cat_entry_copy_map(owning_copy);

CREATE FUNCTION asset.stat_cat_check() RETURNS trigger AS $func$
DECLARE
    sipfield asset.stat_cat_sip_fields%ROWTYPE;
    use_count INT;
BEGIN
    IF NEW.sip_field IS NOT NULL THEN
        SELECT INTO sipfield * FROM asset.stat_cat_sip_fields WHERE field = NEW.sip_field;
        IF sipfield.one_only THEN
            SELECT INTO use_count count(id) FROM asset.stat_cat WHERE sip_field = NEW.sip_field AND id != NEW.id;
            IF use_count > 0 THEN
                RAISE EXCEPTION 'Sip field cannot be used twice';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

CREATE TRIGGER asset_stat_cat_sip_update_trigger
    BEFORE INSERT OR UPDATE ON asset.stat_cat FOR EACH ROW
    EXECUTE PROCEDURE asset.stat_cat_check();

CREATE TABLE asset.copy_note (
	id		BIGSERIAL			PRIMARY KEY,
	owning_copy	BIGINT				NOT NULL,
	creator		BIGINT				NOT NULL,
	create_date	TIMESTAMP WITH TIME ZONE	DEFAULT NOW(),
	pub		BOOL				NOT NULL DEFAULT FALSE,
	title		TEXT				NOT NULL,
	value		TEXT				NOT NULL
);
CREATE INDEX asset_copy_note_creator_idx ON asset.copy_note ( creator );
CREATE INDEX asset_copy_note_owning_copy_idx ON asset.copy_note ( owning_copy );

CREATE TABLE asset.uri (
    id  SERIAL  PRIMARY KEY,
    href    TEXT    NOT NULL,
    label   TEXT,
    use_restriction TEXT,
    active  BOOL    NOT NULL DEFAULT TRUE
);

CREATE TABLE asset.call_number_class (
    id             bigserial     PRIMARY KEY,
    name           TEXT          NOT NULL,
    normalizer     TEXT          NOT NULL DEFAULT 'asset.normalize_generic',
    field          TEXT          NOT NULL DEFAULT '050ab,055ab,060ab,070ab,080ab,082ab,086ab,088ab,090,092,096,098,099'
);
COMMENT ON TABLE asset.call_number_class IS $$
Defines the call number normalization database functions in the "normalizer"
column and the tag/subfield combinations to use to lookup the call number in
the "field" column for a given classification scheme. Tag/subfield combinations
are delimited by commas.
$$;

CREATE OR REPLACE FUNCTION asset.label_normalizer() RETURNS TRIGGER AS $func$
DECLARE
    sortkey        TEXT := '';
BEGIN
    sortkey := NEW.label_sortkey;

    IF NEW.label_class IS NULL THEN
            NEW.label_class := COALESCE(
            (
                SELECT substring(value from E'\\d+')::integer
                FROM actor.org_unit_ancestor_setting('cat.default_classification_scheme', NEW.owning_lib)
            ), 1
        );
    END IF;

    EXECUTE 'SELECT ' || acnc.normalizer || '(' || 
       quote_literal( NEW.label ) || ')'
       FROM asset.call_number_class acnc
       WHERE acnc.id = NEW.label_class
       INTO sortkey;
    NEW.label_sortkey = sortkey;
    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.label_normalizer_generic(TEXT) RETURNS TEXT AS $func$
    # Created after looking at the Koha C4::ClassSortRoutine::Generic module,
    # thus could probably be considered a derived work, although nothing was
    # directly copied - but to err on the safe side of providing attribution:
    # Copyright (C) 2007 LibLime
    # Copyright (C) 2011 Equinox Software, Inc (Steve Callendar)
    # Licensed under the GPL v2 or later

    use strict;
    use warnings;

    # Converts the callnumber to uppercase
    # Strips spaces from start and end of the call number
    # Converts anything other than letters, digits, and periods into spaces
    # Collapses multiple spaces into a single underscore
    my $callnum = uc(shift);
    $callnum =~ s/^\s//g;
    $callnum =~ s/\s$//g;
    # NOTE: this previously used underscores, but this caused sorting issues
    # for the "before" half of page 0 on CN browse, sorting CNs containing a
    # decimal before "whole number" CNs
    $callnum =~ s/[^A-Z0-9_.]/ /g;
    $callnum =~ s/ {2,}/ /g;

    return $callnum;
$func$ LANGUAGE PLPERLU IMMUTABLE;

CREATE OR REPLACE FUNCTION asset.label_normalizer_dewey(TEXT) RETURNS TEXT AS $func$
    # Derived from the Koha C4::ClassSortRoutine::Dewey module
    # Copyright (C) 2007 LibLime
    # Licensed under the GPL v2 or later

    use strict;
    use warnings;

    my $init = uc(shift);
    $init =~ s/^\s+//;
    $init =~ s/\s+$//;
    $init =~ s!/!!g;
    $init =~ s/^([\p{IsAlpha}]+)/$1 /;
    my @tokens = split /\.|\s+/, $init;
    my $digit_group_count = 0;
    my $first_digit_group_idx;
    for (my $i = 0; $i <= $#tokens; $i++) {
        if ($tokens[$i] =~ /^\d+$/) {
            $digit_group_count++;
            if ($digit_group_count == 1) {
                $first_digit_group_idx = $i;
            }
            if (2 == $digit_group_count) {
                $tokens[$i] = sprintf("%-15.15s", $tokens[$i]);
                $tokens[$i] =~ tr/ /0/;
            }
        }
    }
    # Pad the first digit_group if there was only one
    if (1 == $digit_group_count) {
        $tokens[$first_digit_group_idx] .= '_000000000000000'
    }
    my $key = join("_", @tokens);
    $key =~ s/[^\p{IsAlnum}_]//g;

    return $key;

$func$ LANGUAGE PLPERLU IMMUTABLE;


CREATE OR REPLACE FUNCTION asset.label_normalizer_lc(TEXT) RETURNS TEXT AS $func$
    use strict;
    use warnings;

    # Library::CallNumber::LC is currently hosted at http://code.google.com/p/library-callnumber-lc/
    # The author hopes to upload it to CPAN some day, which would make our lives easier
    use Library::CallNumber::LC;

    my $callnum = Library::CallNumber::LC->new(shift);
    return $callnum->normalize();

$func$ LANGUAGE PLPERLU IMMUTABLE;

INSERT INTO asset.call_number_class (name, normalizer, field) VALUES 
    ('Generic', 'asset.label_normalizer_generic', '050ab,055ab,060ab,070ab,080ab,082ab,086ab,088ab,090,092,096,098,099'),
    ('Dewey (DDC)', 'asset.label_normalizer_dewey', '080ab,082ab,092abef'),
    ('Library of Congress (LC)', 'asset.label_normalizer_lc', '050ab,055ab,090abef')
;

CREATE OR REPLACE FUNCTION asset.normalize_affix_sortkey () RETURNS TRIGGER AS $$
BEGIN
    NEW.label_sortkey := REGEXP_REPLACE(
        evergreen.lpad_number_substrings(
            naco_normalize(NEW.label),
            '0',
            10
        ),
        E'\\s+',
        '',
        'g'
    );
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TABLE asset.call_number_prefix (
	id		        SERIAL   PRIMARY KEY,
	owning_lib	    INT			NOT NULL REFERENCES actor.org_unit (id),
	label		    TEXT		NOT NULL, -- i18n
	label_sortkey	TEXT
);
CREATE TRIGGER prefix_normalize_tgr BEFORE INSERT OR UPDATE ON asset.call_number_prefix FOR EACH ROW EXECUTE PROCEDURE asset.normalize_affix_sortkey();
CREATE UNIQUE INDEX asset_call_number_prefix_once_per_lib ON asset.call_number_prefix (label, owning_lib);
CREATE INDEX asset_call_number_prefix_sortkey_idx ON asset.call_number_prefix (label_sortkey);

CREATE TABLE asset.call_number_suffix (
	id		        SERIAL   PRIMARY KEY,
	owning_lib	    INT			NOT NULL REFERENCES actor.org_unit (id),
	label		    TEXT		NOT NULL, -- i18n
	label_sortkey	TEXT
);
CREATE TRIGGER suffix_normalize_tgr BEFORE INSERT OR UPDATE ON asset.call_number_suffix FOR EACH ROW EXECUTE PROCEDURE asset.normalize_affix_sortkey();
CREATE UNIQUE INDEX asset_call_number_suffix_once_per_lib ON asset.call_number_suffix (label, owning_lib);
CREATE INDEX asset_call_number_suffix_sortkey_idx ON asset.call_number_suffix (label_sortkey);

CREATE TABLE asset.call_number (
	id		bigserial PRIMARY KEY,
	creator		BIGINT				NOT NULL,
	create_date	TIMESTAMP WITH TIME ZONE	DEFAULT NOW(),
	editor		BIGINT				NOT NULL,
	edit_date	TIMESTAMP WITH TIME ZONE	DEFAULT NOW(),
	record		bigint				NOT NULL,
	owning_lib	INT				    NOT NULL,
	label		TEXT				NOT NULL,
	deleted		BOOL				NOT NULL DEFAULT FALSE,
	prefix  	INT				    NOT NULL DEFAULT -1 REFERENCES asset.call_number_prefix(id) DEFERRABLE INITIALLY DEFERRED,
	suffix  	INT				    NOT NULL DEFAULT -1 REFERENCES asset.call_number_suffix(id) DEFERRABLE INITIALLY DEFERRED,
	label_class	BIGINT				NOT NULL
							REFERENCES asset.call_number_class(id)
							DEFERRABLE INITIALLY DEFERRED,
	label_sortkey	TEXT
);
CREATE INDEX asset_call_number_record_idx ON asset.call_number (record);
CREATE INDEX asset_call_number_creator_idx ON asset.call_number (creator);
CREATE INDEX asset_call_number_editor_idx ON asset.call_number (editor);
CREATE INDEX asset_call_number_dewey_idx ON asset.call_number (public.call_number_dewey(label));
CREATE INDEX asset_call_number_upper_label_id_owning_lib_idx ON asset.call_number (oils_text_as_bytea(label),id,owning_lib);
CREATE INDEX asset_call_number_label_sortkey ON asset.call_number(oils_text_as_bytea(label_sortkey));
CREATE UNIQUE INDEX asset_call_number_label_once_per_lib ON asset.call_number (record, owning_lib, label, prefix, suffix) WHERE deleted = FALSE OR deleted IS FALSE;
CREATE INDEX asset_call_number_label_sortkey_browse ON asset.call_number(oils_text_as_bytea(label_sortkey), oils_text_as_bytea(label), id, owning_lib) WHERE deleted IS FALSE OR deleted = FALSE;
CREATE RULE protect_cn_delete AS ON DELETE TO asset.call_number DO INSTEAD UPDATE asset.call_number SET deleted = TRUE WHERE OLD.id = asset.call_number.id RETURNING *;
CREATE TRIGGER protect_acn_id_neg1
  BEFORE UPDATE ON asset.call_number
  FOR EACH ROW WHEN (OLD.id = -1)
  EXECUTE PROCEDURE evergreen.raise_protected_row_exception();

CREATE TRIGGER asset_label_sortkey_trigger
    BEFORE UPDATE OR INSERT ON asset.call_number
    FOR EACH ROW EXECUTE PROCEDURE asset.label_normalizer();

CREATE TABLE asset.uri_call_number_map (
    id          BIGSERIAL   PRIMARY KEY,
    uri         INT         NOT NULL REFERENCES asset.uri (id),
    call_number INT         NOT NULL REFERENCES asset.call_number (id),
    CONSTRAINT uri_cn_once UNIQUE (uri,call_number)
);
CREATE INDEX asset_uri_call_number_map_cn_idx ON asset.uri_call_number_map (call_number);

CREATE TABLE asset.call_number_note (
	id		BIGSERIAL			PRIMARY KEY,
	call_number	BIGINT				NOT NULL,
	creator		BIGINT				NOT NULL,
	create_date	TIMESTAMP WITH TIME ZONE	DEFAULT NOW(),
	pub		BOOL				NOT NULL DEFAULT FALSE,
	title		TEXT				NOT NULL,
	value		TEXT				NOT NULL
);
CREATE INDEX asset_call_number_note_creator_idx ON asset.call_number_note ( creator );

CREATE TABLE asset.copy_template (
	id             SERIAL   PRIMARY KEY,
	owning_lib     INT      NOT NULL
	                        REFERENCES actor.org_unit (id)
	                        DEFERRABLE INITIALLY DEFERRED,
	creator        BIGINT   NOT NULL
	                        REFERENCES actor.usr (id)
	                        DEFERRABLE INITIALLY DEFERRED,
	editor         BIGINT   NOT NULL
	                        REFERENCES actor.usr (id)
	                        DEFERRABLE INITIALLY DEFERRED,
	create_date    TIMESTAMP WITH TIME ZONE    DEFAULT NOW(),
	edit_date      TIMESTAMP WITH TIME ZONE    DEFAULT NOW(),
	name           TEXT     NOT NULL,
	-- columns above this point are attributes of the template itself
	-- columns after this point are attributes of the copy this template modifies/creates
	circ_lib       INT      REFERENCES actor.org_unit (id)
	                        DEFERRABLE INITIALLY DEFERRED,
	status         INT      REFERENCES config.copy_status (id)
	                        DEFERRABLE INITIALLY DEFERRED,
	location       INT      REFERENCES asset.copy_location (id)
	                        DEFERRABLE INITIALLY DEFERRED,
	loan_duration  INT      CONSTRAINT valid_loan_duration CHECK (
	                            loan_duration IS NULL OR loan_duration IN (1,2,3)),
	fine_level     INT      CONSTRAINT valid_fine_level CHECK (
	                            fine_level IS NULL OR fine_level IN (1,2,3)),
	age_protect    INT,
	circulate      BOOL,
	deposit        BOOL,
	ref            BOOL,
	holdable       BOOL,
	deposit_amount NUMERIC(6,2),
	price          NUMERIC(8,2),
	circ_modifier  TEXT,
	circ_as_type   TEXT,
	alert_message  TEXT,
	opac_visible   BOOL,
	floating       INT,
	mint_condition BOOL
);

CREATE TABLE asset.copy_vis_attr_cache (
    id              BIGSERIAL   PRIMARY KEY,
    record          BIGINT      NOT NULL, -- No FKEYs, managed by user triggers.
    target_copy     BIGINT      NOT NULL,
    vis_attr_vector INT[]
);
CREATE INDEX copy_vis_attr_cache_record_idx ON asset.copy_vis_attr_cache (record);
CREATE INDEX copy_vis_attr_cache_copy_idx ON asset.copy_vis_attr_cache (target_copy);

CREATE OR REPLACE FUNCTION asset.opac_ou_record_copy_count (org INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = rid;

    FOR ans IN SELECT u.id, t.depth FROM actor.org_unit_ancestors(org) AS u JOIN actor.org_unit_type t ON (u.ou_type = t.id) LOOP
        RETURN QUERY
        WITH org_list AS (SELECT ARRAY_AGG(id)::BIGINT[] AS orgs FROM actor.org_unit_descendants(ans.id) x),
             available_statuses AS (SELECT ARRAY_AGG(id) AS ids FROM config.copy_status WHERE is_available),
             mask AS (SELECT c_attrs FROM asset.patron_default_visibility_mask() x)
        SELECT  ans.depth,
                ans.id,
                COUNT( av.id ),
                SUM( (cp.status = ANY (available_statuses.ids))::INT ),
                COUNT( av.id ),
                trans
          FROM  mask,
                available_statuses,
                org_list,
                asset.copy_vis_attr_cache av
                JOIN asset.copy cp ON (cp.id = av.target_copy AND av.record = rid)
                JOIN asset.call_number cn ON (cp.call_number = cn.id AND not cn.deleted)
          WHERE cp.circ_lib = ANY (org_list.orgs) AND av.vis_attr_vector @@ mask.c_attrs::query_int
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.opac_lasso_record_copy_count (i_lasso INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = rid;

    FOR ans IN SELECT u.org_unit AS id FROM actor.org_lasso_map AS u WHERE lasso = i_lasso LOOP
        RETURN QUERY
        WITH org_list AS (SELECT ARRAY_AGG(id)::BIGINT[] AS orgs FROM actor.org_unit_descendants(ans.id) x),
             available_statuses AS (SELECT ARRAY_AGG(id) AS ids FROM config.copy_status WHERE is_available),
             mask AS (SELECT c_attrs FROM asset.patron_default_visibility_mask() x)
        SELECT  -1,
                ans.id,
                COUNT( av.id ),
                SUM( (cp.status = ANY (available_statuses.ids))::INT ),
                COUNT( av.id ),
                trans
          FROM  mask,
                org_list,
                available_statuses,
                asset.copy_vis_attr_cache av
                JOIN asset.copy cp ON (cp.id = av.target_copy AND av.record = rid)
          WHERE cp.circ_lib = ANY (org_list.orgs) AND av.vis_attr_vector @@ mask.c_attrs::query_int
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT -1, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;   
                
    RETURN;     
END;            
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.staff_ou_record_copy_count(org integer, rid bigint)
 RETURNS TABLE(depth integer, org_unit integer, visible bigint, available bigint, unshadow bigint, transcendant integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = rid;

    FOR ans IN SELECT u.id, t.depth FROM actor.org_unit_ancestors(org) AS u JOIN actor.org_unit_type t ON (u.ou_type = t.id) WHERE staff_catalog_visible LOOP
        RETURN QUERY
        WITH available_statuses AS (SELECT ARRAY_AGG(id) AS ids FROM config.copy_status WHERE is_available),
            cp AS(
                SELECT  cp.id,
                        (cp.status = ANY (available_statuses.ids))::INT as available,
                        (cl.opac_visible AND cp.opac_visible)::INT as opac_visible
                  FROM
                        available_statuses,
                        actor.org_unit_descendants(ans.id) d
                        JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
                        JOIN asset.copy_location cl ON (cp.location = cl.id AND NOT cl.deleted)
                        JOIN asset.call_number cn ON (cn.record = rid AND cn.id = cp.call_number AND NOT cn.deleted)
            ),
            peer AS (
                select  cp.id,
                        (cp.status = ANY  (available_statuses.ids))::INT as available,
                        (cl.opac_visible AND cp.opac_visible)::INT as opac_visible
                FROM
                        available_statuses,
                        actor.org_unit_descendants(ans.id) d
                        JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
                        JOIN asset.copy_location cl ON (cp.location = cl.id AND NOT cl.deleted)
                        JOIN biblio.peer_bib_copy_map bp ON (bp.peer_record = rid AND bp.target_copy = cp.id)
            )
        select ans.depth, ans.id, count(id), sum(x.available::int), sum(x.opac_visible::int), trans
        from ((select * from cp) union (select * from peer)) x
        group by 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;
    RETURN;
END;
$function$;

CREATE OR REPLACE FUNCTION asset.staff_lasso_record_copy_count (i_lasso INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = rid;

    FOR ans IN SELECT u.org_unit AS id FROM actor.org_lasso_map AS u WHERE lasso = i_lasso LOOP
        RETURN QUERY
        SELECT  -1,
                ans.id,
                COUNT( cp.id ),
                SUM( CASE WHEN cp.status IN (SELECT id FROM config.copy_status WHERE holdable AND is_available)
                   THEN 1 ELSE 0 END ),
                SUM( CASE WHEN cl.opac_visible AND cp.opac_visible THEN 1 ELSE 0 END),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
                JOIN asset.copy_location cl ON (cp.location = cl.id AND NOT cl.deleted)
                JOIN asset.call_number cn ON (cn.record = rid AND cn.id = cp.call_number AND NOT cn.deleted)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT -1, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.record_copy_count ( place INT, rid BIGINT, staff BOOL) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
BEGIN
    IF staff IS TRUE THEN
        IF place > 0 THEN
            RETURN QUERY SELECT * FROM asset.staff_ou_record_copy_count( place, rid );
        ELSE
            RETURN QUERY SELECT * FROM asset.staff_lasso_record_copy_count( -place, rid );
        END IF;
    ELSE
        IF place > 0 THEN
            RETURN QUERY SELECT * FROM asset.opac_ou_record_copy_count( place, rid );
        ELSE
            RETURN QUERY SELECT * FROM asset.opac_lasso_record_copy_count( -place, rid );
        END IF;
    END IF;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION asset.record_has_holdable_copy ( rid BIGINT, ou INT DEFAULT NULL) RETURNS BOOL AS $f$
BEGIN
    PERFORM 1
        FROM
            asset.copy acp
            JOIN asset.call_number acn ON acp.call_number = acn.id
            JOIN asset.copy_location acpl ON acp.location = acpl.id
            JOIN config.copy_status ccs ON acp.status = ccs.id
        WHERE
            acn.record = rid
            AND acp.holdable = true
            AND acpl.holdable = true
            AND ccs.holdable = true
            AND acp.deleted = false
            AND acpl.deleted = false
            AND acp.circ_lib IN (SELECT id FROM actor.org_unit_descendants(COALESCE($2,(SELECT id FROM evergreen.org_top()))))
        LIMIT 1;
    IF FOUND THEN
        RETURN true;
    END IF;
    RETURN FALSE;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.opac_ou_metarecord_copy_count (org INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) JOIN metabib.metarecord_source_map m ON (m.source = b.id) WHERE src.transcendant AND m.metarecord = rid;

    FOR ans IN SELECT u.id, t.depth FROM actor.org_unit_ancestors(org) AS u JOIN actor.org_unit_type t ON (u.ou_type = t.id) LOOP
        RETURN QUERY
        WITH org_list AS (SELECT ARRAY_AGG(id)::BIGINT[] AS orgs FROM actor.org_unit_descendants(ans.id) x),
             available_statuses AS (SELECT ARRAY_AGG(id) AS ids FROM config.copy_status WHERE is_available),
             mask AS (SELECT c_attrs FROM asset.patron_default_visibility_mask() x)
        SELECT  ans.depth,
                ans.id,
                COUNT( av.id ),
                SUM( (cp.status = ANY (available_statuses.ids))::INT ),
                COUNT( av.id ),
                trans
          FROM  mask,
                org_list,
                available_statuses,
                asset.copy_vis_attr_cache av
                JOIN asset.copy cp ON (cp.id = av.target_copy)
                JOIN metabib.metarecord_source_map m ON (m.metarecord = rid AND m.source = av.record)
          WHERE cp.circ_lib = ANY (org_list.orgs) AND av.vis_attr_vector @@ mask.c_attrs::query_int
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.opac_lasso_metarecord_copy_count (i_lasso INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) JOIN metabib.metarecord_source_map m ON (m.source = b.id) WHERE src.transcendant AND m.metarecord = rid;

    FOR ans IN SELECT u.org_unit AS id FROM actor.org_lasso_map AS u WHERE lasso = i_lasso LOOP
        RETURN QUERY
        WITH org_list AS (SELECT ARRAY_AGG(id)::BIGINT[] AS orgs FROM actor.org_unit_descendants(ans.id) x),
             available_statuses AS (SELECT ARRAY_AGG(id) AS ids FROM config.copy_status WHERE is_available),
             mask AS (SELECT c_attrs FROM asset.patron_default_visibility_mask() x)
        SELECT  -1,
                ans.id,
                COUNT( av.id ),
                SUM( (cp.status = ANY (available_statuses.ids))::INT ),
                COUNT( av.id ),
                trans
          FROM  mask,
                org_list,
                available_statuses,
                asset.copy_vis_attr_cache av
                JOIN asset.copy cp ON (cp.id = av.target_copy)
                JOIN metabib.metarecord_source_map m ON (m.metarecord = rid AND m.source = av.record)
          WHERE cp.circ_lib = ANY (org_list.orgs) AND av.vis_attr_vector @@ mask.c_attrs::query_int
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;   
                
    RETURN;     
END;            
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.staff_ou_metarecord_copy_count (org INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE         
    ans RECORD; 
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) JOIN metabib.metarecord_source_map m ON (m.source = b.id) WHERE src.transcendant AND m.metarecord = rid;

    FOR ans IN SELECT u.id, t.depth FROM actor.org_unit_ancestors(org) AS u JOIN actor.org_unit_type t ON (u.ou_type = t.id) LOOP
        RETURN QUERY
        SELECT  ans.depth,
                ans.id,
                COUNT( cp.id ),
                SUM( CASE WHEN cp.status IN (SELECT id FROM config.copy_status WHERE holdable AND is_available) THEN 1 ELSE 0 END ),
                COUNT( cp.id ),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
                JOIN asset.call_number cn ON (cn.id = cp.call_number AND NOT cn.deleted)
                JOIN metabib.metarecord_source_map m ON (m.metarecord = rid AND m.source = cn.record)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.staff_lasso_metarecord_copy_count (i_lasso INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) JOIN metabib.metarecord_source_map m ON (m.source = b.id) WHERE src.transcendant AND m.metarecord = rid;

    FOR ans IN SELECT u.org_unit AS id FROM actor.org_lasso_map AS u WHERE lasso = i_lasso LOOP
        RETURN QUERY
        SELECT  -1,
                ans.id,
                COUNT( cp.id ),
                SUM( CASE WHEN cp.status IN (SELECT id FROM config.copy_status WHERE holdable AND is_available) THEN 1 ELSE 0 END ),
                COUNT( cp.id ),
                trans
          FROM
                actor.org_unit_descendants(ans.id) d
                JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
                JOIN asset.call_number cn ON (cn.id = cp.call_number AND NOT cn.deleted)
                JOIN metabib.metarecord_source_map m ON (m.metarecord = rid AND m.source = cn.record)
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.metarecord_copy_count ( place INT, rid BIGINT, staff BOOL) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
BEGIN
    IF staff IS TRUE THEN
        IF place > 0 THEN
            RETURN QUERY SELECT * FROM asset.staff_ou_metarecord_copy_count( place, rid );
        ELSE
            RETURN QUERY SELECT * FROM asset.staff_lasso_metarecord_copy_count( -place, rid );
        END IF;
    ELSE
        IF place > 0 THEN
            RETURN QUERY SELECT * FROM asset.opac_ou_metarecord_copy_count( place, rid );
        ELSE
            RETURN QUERY SELECT * FROM asset.opac_lasso_metarecord_copy_count( -place, rid );
        END IF;
    END IF;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

-- If you want to know how many items are available in a particular library group,
-- you can't easily sum the results of, say, asset.staff_lasso_record_copy_count,
-- since library groups can theoretically include descendants of other org units
-- in the library group (for example, the group could include a system and a branch
-- within that same system), which means that certain items would be counted twice.
-- The following functions address that problem by providing deduplicated sums that
-- only count each item once.

CREATE OR REPLACE FUNCTION asset.staff_lasso_record_copy_count_sum(lasso_id INT, record_id BIGINT)
    RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT, library_group INT) AS $$
    BEGIN
    IF (lasso_id IS NULL) THEN RETURN; END IF;
    IF (record_id IS NULL) THEN RETURN; END IF;
    RETURN QUERY SELECT
        -1,
        -1,
        COUNT(cp.id),
        SUM( CASE WHEN cp.status IN (SELECT id FROM config.copy_status WHERE holdable AND is_available) THEN 1 ELSE 0 END ),
        SUM( CASE WHEN cl.opac_visible AND cp.opac_visible THEN 1 ELSE 0 END),
        0,
        lasso_id
    FROM ( SELECT DISTINCT descendants.id FROM actor.org_lasso_map aolmp JOIN LATERAL actor.org_unit_descendants(aolmp.org_unit) AS descendants ON TRUE WHERE aolmp.lasso = lasso_id) d
        JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
        JOIN asset.copy_location cl ON (cp.location = cl.id AND NOT cl.deleted)
        JOIN asset.call_number cn ON (cn.record = record_id AND cn.id = cp.call_number AND NOT cn.deleted);
    END;
$$ LANGUAGE PLPGSQL STABLE ROWS 1;

CREATE OR REPLACE FUNCTION asset.opac_lasso_record_copy_count_sum(lasso_id INT, record_id BIGINT)
    RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT, library_group INT) AS $$
    BEGIN
    RAISE 'NOT IMPLEMENTED';
    END;
$$ LANGUAGE PLPGSQL STABLE ROWS 1;

CREATE OR REPLACE FUNCTION asset.staff_lasso_metarecord_copy_count_sum(lasso_id INT, metarecord_id BIGINT)
    RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT, library_group INT) AS $$
    SELECT (
        -1,
        -1,
        SUM(sums.visible)::bigint,
        SUM(sums.available)::bigint,
        SUM(sums.unshadow)::bigint,
        MIN(sums.transcendant),
        lasso_id
    ) FROM metabib.metarecord_source_map mmsm
      JOIN LATERAL (SELECT visible, available, unshadow, transcendant FROM asset.staff_lasso_record_copy_count_sum(lasso_id, mmsm.source)) sums ON TRUE
      WHERE mmsm.metarecord = metarecord_id;
$$ LANGUAGE SQL STABLE ROWS 1;

CREATE OR REPLACE FUNCTION asset.opac_lasso_metarecord_copy_count_sum(lasso_id INT, metarecord_id BIGINT)
    RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT, library_group INT) AS $$
    SELECT (
        -1,
        -1,
        SUM(sums.visible)::bigint,
        SUM(sums.available)::bigint,
        SUM(sums.unshadow)::bigint,
        MIN(sums.transcendant),
        lasso_id
    ) FROM metabib.metarecord_source_map mmsm
      JOIN LATERAL (SELECT visible, available, unshadow, transcendant FROM asset.opac_lasso_record_copy_count_sum(lasso_id, mmsm.source)) sums ON TRUE
      WHERE mmsm.metarecord = metarecord_id;
$$ LANGUAGE SQL STABLE ROWS 1;

CREATE OR REPLACE FUNCTION asset.copy_org_ids(org_units INT[], depth INT, library_groups INT[])
RETURNS TABLE (id INT)
AS $$
DECLARE
    ancestor INT;
BEGIN
    RETURN QUERY SELECT org_unit FROM actor.org_lasso_map WHERE lasso = ANY(library_groups);
    FOR ancestor IN SELECT unnest(org_units)
    LOOP
        RETURN QUERY
        SELECT d.id
        FROM actor.org_unit_descendants(ancestor, depth) d;
    END LOOP;
    RETURN;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION asset.staff_copy_total(rec_id INT, org_units INT[], depth INT, library_groups INT[])
RETURNS INT AS $$
  SELECT COUNT(cp.id) total
  	FROM asset.copy cp
  	INNER JOIN asset.call_number cn ON (cn.id = cp.call_number AND NOT cn.deleted AND cn.record = rec_id)
  	INNER JOIN asset.copy_location cl ON (cp.location = cl.id AND NOT cl.deleted)
  	WHERE cp.circ_lib = ANY (SELECT asset.copy_org_ids(org_units, depth, library_groups))
  	AND NOT cp.deleted;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION asset.opac_copy_total(rec_id INT, org_units INT[], depth INT, library_groups INT[])
RETURNS INT AS $$
BEGIN
RAISE 'Not implemented';
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.metarecord_has_holdable_copy ( rid BIGINT, ou INT DEFAULT NULL) RETURNS BOOL AS $f$
BEGIN
    PERFORM 1
        FROM
            asset.copy acp
            JOIN asset.call_number acn ON acp.call_number = acn.id
            JOIN asset.copy_location acpl ON acp.location = acpl.id
            JOIN config.copy_status ccs ON acp.status = ccs.id
            JOIN metabib.metarecord_source_map mmsm ON acn.record = mmsm.source
        WHERE
            mmsm.metarecord = rid
            AND acp.holdable = true
            AND acpl.holdable = true
            AND ccs.holdable = true
            AND acp.deleted = false
            AND acpl.deleted = false
            AND acp.circ_lib IN (SELECT id FROM actor.org_unit_descendants(COALESCE($2,(SELECT id FROM evergreen.org_top()))))
        LIMIT 1;
    IF FOUND THEN
        RETURN true;
    END IF;
    RETURN FALSE;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.autogenerate_placeholder_barcode ( ) RETURNS TRIGGER AS $f$
BEGIN
	IF NEW.barcode LIKE '@@%' THEN
		NEW.barcode := '@@' || NEW.id;
	END IF;
	RETURN NEW;
END;
$f$ LANGUAGE PLPGSQL;

CREATE TRIGGER autogenerate_placeholder_barcode
	BEFORE INSERT OR UPDATE ON asset.copy
	FOR EACH ROW EXECUTE PROCEDURE asset.autogenerate_placeholder_barcode();

CREATE OR REPLACE FUNCTION evergreen.fake_fkey_tgr () RETURNS TRIGGER AS $F$
DECLARE
    copy_id BIGINT;
BEGIN
    EXECUTE 'SELECT ($1).' || quote_ident(TG_ARGV[0]) INTO copy_id USING NEW;
    IF copy_id IS NOT NULL THEN
        PERFORM * FROM asset.copy WHERE id = copy_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Key (%.%=%) does not exist in asset.copy', TG_TABLE_SCHEMA, TG_TABLE_NAME, copy_id;
        END IF;
    END IF;
    RETURN NULL;
END;
$F$ LANGUAGE PLPGSQL;

CREATE TABLE asset.copy_tag (
    id              SERIAL PRIMARY KEY,
    tag_type        TEXT REFERENCES config.copy_tag_type (code)
                    ON UPDATE CASCADE ON DELETE CASCADE,
    label           TEXT NOT NULL,
    value           TEXT NOT NULL,
    index_vector    tsvector NOT NULL,
    staff_note      TEXT,
    pub             BOOLEAN DEFAULT TRUE,
    owner           INTEGER NOT NULL REFERENCES actor.org_unit (id),
    url             TEXT
);

CREATE INDEX asset_copy_tag_label_idx
    ON asset.copy_tag (label);
CREATE INDEX asset_copy_tag_label_lower_idx
    ON asset.copy_tag (evergreen.lowercase(label));
CREATE INDEX asset_copy_tag_index_vector_idx
    ON asset.copy_tag
    USING GIN(index_vector);
CREATE INDEX asset_copy_tag_tag_type_idx
    ON asset.copy_tag (tag_type);
CREATE INDEX asset_copy_tag_owner_idx
    ON asset.copy_tag (owner);

CREATE OR REPLACE FUNCTION asset.set_copy_tag_value () RETURNS TRIGGER AS $$
BEGIN
    IF NEW.value IS NULL THEN
        NEW.value = NEW.label;        
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';

-- name of following trigger chosen to ensure it runs first
CREATE TRIGGER asset_copy_tag_do_value
    BEFORE INSERT OR UPDATE ON asset.copy_tag
    FOR EACH ROW EXECUTE PROCEDURE asset.set_copy_tag_value();
CREATE TRIGGER asset_copy_tag_fti_trigger
    BEFORE UPDATE OR INSERT ON asset.copy_tag
    FOR EACH ROW EXECUTE PROCEDURE oils_tsearch2('default');

CREATE TABLE asset.copy_tag_copy_map (
    id              BIGSERIAL PRIMARY KEY,
    copy            BIGINT,
    tag             INTEGER REFERENCES asset.copy_tag (id)
                    ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE INDEX asset_copy_tag_copy_map_copy_idx
    ON asset.copy_tag_copy_map (copy);
CREATE INDEX asset_copy_tag_copy_map_tag_idx
    ON asset.copy_tag_copy_map (tag);

CREATE OR REPLACE FUNCTION asset.copy_state (cid BIGINT) RETURNS TEXT AS $$
DECLARE
    last_circ_stop	TEXT;
    the_copy	    asset.copy%ROWTYPE;
BEGIN

    SELECT * INTO the_copy FROM asset.copy WHERE id = cid;
    IF NOT FOUND THEN RETURN NULL; END IF;

    IF the_copy.status = 3 THEN -- Lost
        RETURN 'LOST';
    ELSIF the_copy.status = 4 THEN -- Missing
        RETURN 'MISSING';
    ELSIF the_copy.status = 14 THEN -- Damaged
        RETURN 'DAMAGED';
    ELSIF the_copy.status = 17 THEN -- Lost and paid
        RETURN 'LOST_AND_PAID';
    END IF;

    SELECT stop_fines INTO last_circ_stop
      FROM  action.circulation
      WHERE target_copy = cid AND checkin_time IS NULL
      ORDER BY xact_start DESC LIMIT 1;

    IF FOUND THEN
        IF last_circ_stop IN (
            'CLAIMSNEVERCHECKEDOUT',
            'CLAIMSRETURNED',
            'LONGOVERDUE'
        ) THEN
            RETURN last_circ_stop;
        END IF;
    END IF;

    RETURN 'NORMAL';
END;
$$ LANGUAGE PLPGSQL;

CREATE TYPE config.copy_alert_type_state AS ENUM (
    'NORMAL',
    'LOST',
    'LOST_AND_PAID',
    'MISSING',
    'DAMAGED',
    'CLAIMSRETURNED',
    'LONGOVERDUE',
    'CLAIMSNEVERCHECKEDOUT'
);

CREATE TYPE config.copy_alert_type_event AS ENUM (
    'CHECKIN',
    'CHECKOUT'
);

CREATE TABLE config.copy_alert_type (
    id      serial  primary key, -- reserve 1-100 for system
    scope_org   int not null references actor.org_unit (id) on delete cascade,
    active      bool    not null default true,
    name        text    not null unique,
    state       config.copy_alert_type_state,
    event       config.copy_alert_type_event,
    in_renew    bool,
    invert_location bool    not null default false,
    at_circ     bool,
    at_owning   bool,
    next_status int[]
);
SELECT SETVAL('config.copy_alert_type_id_seq'::TEXT, 100);

CREATE TABLE actor.copy_alert_suppress (
    id          serial primary key,
    org         int not null references actor.org_unit (id) on delete cascade,
    alert_type  int not null references config.copy_alert_type (id) on delete cascade
);

CREATE TABLE asset.copy_alert (
    id      bigserial   primary key,
    alert_type  int     not null references config.copy_alert_type (id) on delete cascade,
    copy        bigint  not null,
    temp        bool    not null default false,
    create_time timestamptz not null default now(),
    create_staff    bigint  not null references actor.usr (id) on delete set null,
    note        text,
    ack_time    timestamptz,
    ack_staff   bigint references actor.usr (id) on delete set null
);

CREATE VIEW asset.active_copy_alert AS
    SELECT  *
      FROM  asset.copy_alert
      WHERE ack_time IS NULL;

CREATE TABLE asset.course_module_course (
    id              SERIAL PRIMARY KEY,
    name            TEXT NOT NULL,
    course_number   TEXT NOT NULL,
    section_number  TEXT,
    owning_lib      INT REFERENCES actor.org_unit (id),
    is_archived        BOOLEAN DEFAULT false
);

CREATE TABLE asset.course_module_role (
    id              SERIAL  PRIMARY KEY,
    name            TEXT    UNIQUE NOT NULL,
    is_public       BOOLEAN NOT NULL DEFAULT false
);

CREATE TABLE asset.course_module_course_users (
    id              SERIAL PRIMARY KEY,
    course          INT NOT NULL REFERENCES asset.course_module_course (id),
    usr             INT NOT NULL REFERENCES actor.usr (id),
    usr_role        INT REFERENCES asset.course_module_role (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE asset.course_module_course_materials (
    id              SERIAL PRIMARY KEY,
    course          INT NOT NULL REFERENCES asset.course_module_course (id),
    item            INT REFERENCES asset.copy (id),
    relationship    TEXT,
    record          INT REFERENCES biblio.record_entry (id),
    temporary_record       BOOLEAN,
    original_location      INT REFERENCES asset.copy_location,
    original_status        INT REFERENCES config.copy_status,
    original_circ_modifier TEXT, --REFERENCES config.circ_modifier
    original_callnumber    INT REFERENCES asset.call_number,
    original_circ_lib      INT REFERENCES actor.org_unit (id),
    unique (course, item, record)
);

CREATE TABLE asset.course_module_term (
    id              SERIAL  PRIMARY KEY,
    name            TEXT NOT NULL,
    owning_lib      INT REFERENCES actor.org_unit (id),
	start_date      TIMESTAMP WITH TIME ZONE,
	end_date        TIMESTAMP WITH TIME ZONE,
    CONSTRAINT cmt_once_per_owning_lib UNIQUE (owning_lib, name)
);

CREATE TABLE asset.course_module_term_course_map (
    id              BIGSERIAL  PRIMARY KEY,
    term            INT     NOT NULL REFERENCES asset.course_module_term (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    course          INT     NOT NULL REFERENCES asset.course_module_course (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TYPE asset.holdable_part_count AS (id INT, label TEXT, holdable_count BIGINT);
CREATE OR REPLACE FUNCTION asset.count_holdable_parts_on_record (record_id BIGINT, pickup_lib INT DEFAULT NULL) RETURNS SETOF asset.holdable_part_count AS $func$
DECLARE 
    hard_boundary                   INT;
    orgs_within_hard_boundary       INT[];
BEGIN

    SELECT value INTO hard_boundary 
    FROM actor.org_unit_ancestor_setting('circ.hold_boundary.hard', pickup_lib)
    LIMIT 1;

    IF hard_boundary IS NOT NULL THEN
        SELECT ARRAY_AGG(id) INTO orgs_within_hard_boundary
        FROM actor.org_unit_descendants(pickup_lib, hard_boundary);
    END IF;

    RETURN QUERY 
    SELECT 
        bmp.id, 
        bmp.label, 
        COUNT(DISTINCT acp.id) AS holdable_count
    FROM asset.copy_part_map acpm
        JOIN biblio.monograph_part bmp ON acpm.part = bmp.id
        JOIN asset.copy acp ON acpm.target_copy = acp.id
        JOIN asset.call_number acn ON acp.call_number = acn.id
        JOIN biblio.record_entry bre ON acn.record = bre.id
        JOIN config.copy_status ccs ON acp.status = ccs.id
        JOIN asset.copy_location acpl ON acp.location = acpl.id
    WHERE
        NOT bmp.deleted
        AND (NOT acp.deleted AND acp.holdable)
        AND bre.id = record_id
        AND ccs.holdable
        AND acpl.holdable
        -- Check the circ_lib, but only when given a pickup lib for our hold AND we have hard boundary restrictions
        AND CASE WHEN orgs_within_hard_boundary IS NOT NULL THEN 
                acp.circ_lib = ANY(orgs_within_hard_boundary)
            ELSE TRUE 
            END
    GROUP BY 1, 2
    ORDER BY bmp.label_sortkey ASC;
END;
$func$ LANGUAGE plpgsql;

COMMIT;

