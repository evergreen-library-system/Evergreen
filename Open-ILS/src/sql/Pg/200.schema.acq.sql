DROP SCHEMA acq CASCADE;

BEGIN;

CREATE SCHEMA acq;


-- Tables


CREATE TABLE acq.currency_type (
	code	TEXT PRIMARY KEY,
	label	TEXT
);

-- Use the ISO 4217 abbreviations for currency codes
INSERT INTO acq.currency_type (code, label) VALUES ('USD','US Dollars');
INSERT INTO acq.currency_type (code, label) VALUES ('CAN','Canadian Dollars');
INSERT INTO acq.currency_type (code, label) VALUES ('EUR','Euros');

CREATE TABLE acq.exchange_rate (
    id              SERIAL  PRIMARY KEY,
    from_currency   TEXT    NOT NULL REFERENCES acq.currency_type (code) DEFERRABLE INITIALLY DEFERRED,
    to_currency     TEXT    NOT NULL REFERENCES acq.currency_type (code) DEFERRABLE INITIALLY DEFERRED,
    ratio           NUMERIC NOT NULL,
    CONSTRAINT exchange_rate_from_to_once UNIQUE (from_currency,to_currency)
);

INSERT INTO acq.exchange_rate (from_currency,to_currency,ratio) VALUES ('USD','CAN',1.2);
INSERT INTO acq.exchange_rate (from_currency,to_currency,ratio) VALUES ('USD','EUR',0.5);

CREATE TABLE acq.provider (
    id                  SERIAL  PRIMARY KEY,
    name                TEXT    NOT NULL,
    owner               INT     NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
    currency_type       TEXT    NOT NULL REFERENCES acq.currency_type (code) DEFERRABLE INITIALLY DEFERRED,
    code                TEXT    NOT NULL,
    holding_tag         TEXT,
    san                 TEXT,
    edi_default         INT,          -- REFERENCES acq.edi_account (id) DEFERRABLE INITIALLY DEFERRED
    CONSTRAINT provider_name_once_per_owner UNIQUE (name,owner),
	CONSTRAINT code_once_per_owner UNIQUE (code, owner)
);

CREATE TABLE acq.provider_holding_subfield_map (
    id          SERIAL  PRIMARY KEY,
    provider    INT     NOT NULL REFERENCES acq.provider (id) DEFERRABLE INITIALLY DEFERRED,
    name        TEXT    NOT NULL, -- barcode, price, etc
    subfield    TEXT    NOT NULL,
    CONSTRAINT name_once_per_provider UNIQUE (provider,name)
);

CREATE TABLE acq.provider_address (
	id		SERIAL	PRIMARY KEY,
	valid		BOOL	NOT NULL DEFAULT TRUE,
	address_type	TEXT,
    provider    INT     NOT NULL REFERENCES acq.provider (id) DEFERRABLE INITIALLY DEFERRED,
	street1		TEXT	NOT NULL,
	street2		TEXT,
	city		TEXT	NOT NULL,
	county		TEXT,
	state		TEXT	NOT NULL,
	country		TEXT	NOT NULL,
	post_code	TEXT	NOT NULL
);

CREATE TABLE acq.provider_contact (
	id		SERIAL	PRIMARY KEY,
    provider    INT NOT NULL REFERENCES acq.provider (id) DEFERRABLE INITIALLY DEFERRED,
    name    TEXT NULL NULL,
    role    TEXT, -- free-form.. e.g. "our sales guy"
    email   TEXT,
    phone   TEXT
);

CREATE TABLE acq.provider_contact_address (
	id			SERIAL	PRIMARY KEY,
	valid			BOOL	NOT NULL DEFAULT TRUE,
	address_type	TEXT,
	contact    		INT	    NOT NULL REFERENCES acq.provider_contact (id) DEFERRABLE INITIALLY DEFERRED,
	street1			TEXT	NOT NULL,
	street2			TEXT,
	city			TEXT	NOT NULL,
	county			TEXT,
	state			TEXT	NOT NULL,
	country			TEXT	NOT NULL,
	post_code		TEXT	NOT NULL
);


CREATE TABLE acq.funding_source (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL,
	owner		INT	NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	currency_type	TEXT	NOT NULL REFERENCES acq.currency_type (code) DEFERRABLE INITIALLY DEFERRED,
	code		TEXT	UNIQUE,
	CONSTRAINT funding_source_name_once_per_owner UNIQUE (name,owner)
);

CREATE TABLE acq.funding_source_credit (
	id	SERIAL	   PRIMARY KEY,
	funding_source INT      NOT NULL REFERENCES acq.funding_source (id) DEFERRABLE INITIALLY DEFERRED,
	amount	       NUMERIC	NOT NULL,
	note  	       TEXT,
	deadline_date  TIMESTAMPTZ,
	effective_date TIMESTAMPTZ NOT NULL default now()
);

CREATE VIEW acq.ordered_funding_source_credit AS
    SELECT
        CASE WHEN deadline_date IS NULL THEN
            2
        ELSE
            1
        END AS sort_priority,
        CASE WHEN deadline_date IS NULL THEN
            effective_date
        ELSE
            deadline_date
        END AS sort_date,
        id,
        funding_source,
        amount,
        note
    FROM
        acq.funding_source_credit;

COMMENT ON VIEW acq.ordered_funding_source_credit IS $$
/*
 * Copyright (C) 2009  Georgia Public Library Service
 * Scott McKellar <scott@gmail.com>
 *
 * The acq.ordered_funding_source_credit view is a prioritized
 * ordering of funding source credits.  When ordered by the first
 * three columns, this view defines the order in which the various
 * credits are to be tapped for spending, subject to the allocations
 * in the acq.fund_allocation table.
 *
 * The first column reflects the principle that we should spend
 * money with deadlines before spending money without deadlines.
 *
 * The second column reflects the principle that we should spend the
 * oldest money first.  For money with deadlines, that means that we
 * spend first from the credit with the earliest deadline.  For
 * money without deadlines, we spend first from the credit with the
 * earliest effective date.
 *
 * The third column is a tie breaker to ensure a consistent
 * ordering.
 *
 * ****
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
 */
$$;

CREATE TABLE acq.fund (
    id              SERIAL  PRIMARY KEY,
    org             INT     NOT NULL REFERENCES actor.org_unit (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    name            TEXT    NOT NULL,
    year            INT     NOT NULL DEFAULT EXTRACT( YEAR FROM NOW() ),
    currency_type   TEXT    NOT NULL REFERENCES acq.currency_type (code) DEFERRABLE INITIALLY DEFERRED,
    code            TEXT,
	rollover        BOOL    NOT NULL DEFAULT FALSE,
	propagate       BOOL    NOT NULL DEFAULT TRUE,
    CONSTRAINT name_once_per_org_year UNIQUE (org,name,year),
    CONSTRAINT code_once_per_org_year UNIQUE (org, code, year),
	CONSTRAINT acq_fund_rollover_implies_propagate CHECK ( propagate OR NOT rollover )
);

CREATE TABLE acq.fund_debit (
	id			SERIAL	PRIMARY KEY,
	fund			INT     NOT NULL REFERENCES acq.fund (id) DEFERRABLE INITIALLY DEFERRED,
	origin_amount		NUMERIC	NOT NULL,  -- pre-exchange-rate amount
	origin_currency_type	TEXT	NOT NULL REFERENCES acq.currency_type (code) DEFERRABLE INITIALLY DEFERRED,
	amount			NUMERIC	NOT NULL,
	encumbrance		BOOL	NOT NULL DEFAULT TRUE,
	debit_type		TEXT	NOT NULL,
	xfer_destination	INT	REFERENCES acq.fund (id) DEFERRABLE INITIALLY DEFERRED,
	create_time     TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE acq.fund_allocation (
    id          SERIAL  PRIMARY KEY,
    funding_source        INT     NOT NULL REFERENCES acq.funding_source (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    fund        INT     NOT NULL REFERENCES acq.fund (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    amount      NUMERIC NOT NULL,
    allocator   INT NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    note        TEXT,
	create_time TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);
CREATE INDEX fund_alloc_allocator_idx ON acq.fund_allocation ( allocator );

CREATE TABLE acq.picklist (
	id		SERIAL				PRIMARY KEY,
	owner		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	creator         INT                             NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	editor          INT                             NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	org_unit	INT				NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	name		TEXT				NOT NULL,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	edit_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	CONSTRAINT name_once_per_owner UNIQUE (name,owner)
);
CREATE INDEX acq_picklist_owner_idx   ON acq.picklist ( owner );
CREATE INDEX acq_picklist_creator_idx ON acq.picklist ( creator );
CREATE INDEX acq_picklist_editor_idx  ON acq.picklist ( editor );

CREATE TABLE acq.purchase_order (
	id		SERIAL				PRIMARY KEY,
	owner		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	creator         INT                             NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	editor          INT                             NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	ordering_agency INT				NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	edit_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	provider	INT				NOT NULL REFERENCES acq.provider (id) DEFERRABLE INITIALLY DEFERRED,
	state			TEXT					NOT NULL DEFAULT 'new',
	order_date		TIMESTAMP WITH TIME ZONE,
	name			TEXT					NOT NULL
);
CREATE INDEX po_owner_idx ON acq.purchase_order (owner);
CREATE INDEX po_provider_idx ON acq.purchase_order (provider);
CREATE INDEX po_state_idx ON acq.purchase_order (state);
CREATE INDEX po_creator_idx  ON acq.purchase_order ( creator );
CREATE INDEX po_editor_idx   ON acq.purchase_order ( editor );
CREATE INDEX acq_po_org_name_order_date_idx ON acq.purchase_order( ordering_agency, name, order_date );

-- The name should default to the id, as text.  We can't reference a column
-- in a DEFAULT clause, so we use a trigger:

CREATE OR REPLACE FUNCTION acq.purchase_order_name_default () RETURNS TRIGGER 
AS $$
BEGIN
	IF NEW.name IS NULL THEN
		NEW.name := NEW.id::TEXT;
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER po_name_default_trg
  BEFORE INSERT OR UPDATE ON acq.purchase_order
  FOR EACH ROW EXECUTE PROCEDURE acq.purchase_order_name_default ();

-- The order name should be unique for a given ordering agency on a given order date
-- (truncated to midnight), but only where the order_date is not NULL.  Conceptually
-- this rule requires a check constraint with a subquery.  However you can't have a
-- subquery in a CHECK constraint, so we fake it with a trigger.

CREATE OR REPLACE FUNCTION acq.po_org_name_date_unique () RETURNS TRIGGER 
AS $$
DECLARE
	collision INT;
BEGIN
	--
	-- If order_date is not null, then make sure we don't have a collision
	-- on order_date (truncated to day), org, and name
	--
	IF NEW.order_date IS NULL THEN
		RETURN NEW;
	END IF;
	--
	-- In the WHERE clause, we compare the order_dates without regard to time of day.
	-- We use a pair of inequalities instead of comparing truncated dates so that the
	-- query can do an indexed range scan.
	--
	SELECT 1 INTO collision
	FROM acq.purchase_order
	WHERE
		ordering_agency = NEW.ordering_agency
		AND name = NEW.name
		AND order_date >= date_trunc( 'day', NEW.order_date )
		AND order_date <  date_trunc( 'day', NEW.order_date ) + '1 day'::INTERVAL
		AND id <> NEW.id;
	--
	IF collision IS NULL THEN
		-- okay, no collision
		RETURN NEW;
	ELSE
		-- collision; nip it in the bud
		RAISE EXCEPTION 'Colliding purchase orders: ordering_agency %, date %, name ''%''',
			NEW.ordering_agency, NEW.order_date, NEW.name;
	END IF;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER po_org_name_date_unique_trg
  BEFORE INSERT OR UPDATE ON acq.purchase_order
  FOR EACH ROW EXECUTE PROCEDURE acq.po_org_name_date_unique ();

CREATE TABLE acq.po_note (
	id		SERIAL				PRIMARY KEY,
	purchase_order	INT				NOT NULL REFERENCES acq.purchase_order (id) DEFERRABLE INITIALLY DEFERRED,
	creator		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	editor		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	edit_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	value		TEXT				NOT NULL
);
CREATE INDEX po_note_po_idx ON acq.po_note (purchase_order);
CREATE INDEX acq_po_note_creator_idx  ON acq.po_note ( creator );
CREATE INDEX acq_po_note_editor_idx   ON acq.po_note ( editor );

CREATE TABLE acq.lineitem (
	id                  BIGSERIAL                   PRIMARY KEY,
	creator             INT                         NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	editor              INT                         NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	selector            INT                         NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	provider            INT                         REFERENCES acq.provider (id) DEFERRABLE INITIALLY DEFERRED,
	purchase_order      INT                         REFERENCES acq.purchase_order (id) DEFERRABLE INITIALLY DEFERRED,
	picklist            INT                         REFERENCES acq.picklist (id) DEFERRABLE INITIALLY DEFERRED,
	expected_recv_time  TIMESTAMP WITH TIME ZONE,
	create_time         TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
	edit_time           TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
	marc                TEXT                        NOT NULL,
	eg_bib_id           INT                         REFERENCES biblio.record_entry (id) DEFERRABLE INITIALLY DEFERRED,
	source_label        TEXT,
	item_count          INT                         NOT NULL DEFAULT 0,
	state               TEXT                        NOT NULL DEFAULT 'new',
    CONSTRAINT picklist_or_po CHECK (picklist IS NOT NULL OR purchase_order IS NOT NULL)
);
CREATE INDEX li_po_idx ON acq.lineitem (purchase_order);
CREATE INDEX li_pl_idx ON acq.lineitem (picklist);
CREATE INDEX li_creator_idx   ON acq.lineitem ( creator );
CREATE INDEX li_editor_idx    ON acq.lineitem ( editor );
CREATE INDEX li_selector_idx  ON acq.lineitem ( selector );

CREATE TABLE acq.lineitem_note (
	id		SERIAL				PRIMARY KEY,
	lineitem	INT				NOT NULL REFERENCES acq.lineitem (id) DEFERRABLE INITIALLY DEFERRED,
	creator		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	editor		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	edit_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	value		TEXT				NOT NULL
);
CREATE INDEX li_note_li_idx ON acq.lineitem_note (lineitem);
CREATE INDEX li_note_creator_idx  ON acq.lineitem_note ( creator );
CREATE INDEX li_note_editor_idx   ON acq.lineitem_note ( editor );

CREATE TABLE acq.lineitem_detail (
    id          BIGSERIAL	PRIMARY KEY,
    lineitem    INT         NOT NULL REFERENCES acq.lineitem (id) DEFERRABLE INITIALLY DEFERRED,
    fund        INT         REFERENCES acq.fund (id) DEFERRABLE INITIALLY DEFERRED,
    fund_debit  INT         REFERENCES acq.fund_debit (id) DEFERRABLE INITIALLY DEFERRED,
    eg_copy_id  BIGINT      REFERENCES asset.copy (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    barcode     TEXT,
    cn_label    TEXT,
    note        TEXT,
    collection_code TEXT,
    circ_modifier   TEXT    REFERENCES config.circ_modifier (code) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    owning_lib  INT         REFERENCES actor.org_unit (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    location    INT         REFERENCES asset.copy_location (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    recv_time   TIMESTAMP WITH TIME ZONE
);

CREATE INDEX li_detail_li_idx ON acq.lineitem_detail (lineitem);

CREATE TABLE acq.lineitem_attr_definition (
	id		BIGSERIAL	PRIMARY KEY,
	code		TEXT		NOT NULL,
	description	TEXT		NOT NULL,
	remove		TEXT		NOT NULL DEFAULT '',
	ident		BOOL		NOT NULL DEFAULT FALSE
);

CREATE TABLE acq.lineitem_marc_attr_definition (
	id		BIGINT	PRIMARY KEY DEFAULT NEXTVAL('acq.lineitem_attr_definition_id_seq'),
	xpath		TEXT		NOT NULL
) INHERITS (acq.lineitem_attr_definition);

CREATE TABLE acq.lineitem_provider_attr_definition (
	id		BIGINT	PRIMARY KEY DEFAULT NEXTVAL('acq.lineitem_attr_definition_id_seq'),
	xpath		TEXT		NOT NULL,
	provider	INT	NOT NULL REFERENCES acq.provider (id) DEFERRABLE INITIALLY DEFERRED
) INHERITS (acq.lineitem_attr_definition);

CREATE TABLE acq.lineitem_generated_attr_definition (
	id		BIGINT	PRIMARY KEY DEFAULT NEXTVAL('acq.lineitem_attr_definition_id_seq'),
	xpath		TEXT		NOT NULL
) INHERITS (acq.lineitem_attr_definition);

CREATE TABLE acq.lineitem_usr_attr_definition (
	id		BIGINT	PRIMARY KEY DEFAULT NEXTVAL('acq.lineitem_attr_definition_id_seq'),
	usr		INT	NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED
) INHERITS (acq.lineitem_attr_definition);
CREATE INDEX li_usr_attr_def_usr_idx  ON acq.lineitem_usr_attr_definition ( usr );

CREATE TABLE acq.lineitem_local_attr_definition (
	id		BIGINT	PRIMARY KEY DEFAULT NEXTVAL('acq.lineitem_attr_definition_id_seq')
) INHERITS (acq.lineitem_attr_definition);

CREATE TABLE acq.lineitem_attr (
	id		BIGSERIAL	PRIMARY KEY,
	definition	BIGINT		NOT NULL,
	lineitem	BIGINT		NOT NULL REFERENCES acq.lineitem (id) DEFERRABLE INITIALLY DEFERRED,
	attr_type	TEXT		NOT NULL,
	attr_name	TEXT		NOT NULL,
	attr_value	TEXT		NOT NULL
);

CREATE INDEX li_attr_li_idx ON acq.lineitem_attr (lineitem);
CREATE INDEX li_attr_value_idx ON acq.lineitem_attr (attr_value);
CREATE INDEX li_attr_definition_idx ON acq.lineitem_attr (definition);


-- Seed data


INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath ) VALUES ('title','Title of work','//*[@tag="245"]/*[contains("abcmnopr",@code)]');
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath ) VALUES ('author','Author of work','//*[@tag="100" or @tag="110" or @tag="113"]/*[contains("ad",@code)]');
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath ) VALUES ('language','Language of work','//*[@tag="240"]/*[@code="l"][1]');
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath ) VALUES ('pagination','Pagination','//*[@tag="300"]/*[@code="a"][1]');
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath, remove ) VALUES ('isbn','ISBN','//*[@tag="020"]/*[@code="a"]', $r$(?:-|\s.+$)$r$);
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath, remove ) VALUES ('issn','ISSN','//*[@tag="022"]/*[@code="a"]', $r$(?:-|\s.+$)$r$);
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath ) VALUES ('price','Price','//*[@tag="020" or @tag="022"]/*[@code="c"][1]');
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath ) VALUES ('identifier','Identifier','//*[@tag="001"]');
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath ) VALUES ('publisher','Publisher','//*[@tag="260"]/*[@code="b"][1]');
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath ) VALUES ('pubdate','Publication Date','//*[@tag="260"]/*[@code="c"][1]');
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath ) VALUES ('edition','Edition','//*[@tag="250"]/*[@code="a"][1]');

INSERT INTO acq.lineitem_local_attr_definition ( code, description ) VALUES ('estimated_price', 'Estimated Price');


CREATE TABLE acq.distribution_formula (
	id		SERIAL PRIMARY KEY,
	owner	INT NOT NULL
			REFERENCES actor.org_unit(id) DEFERRABLE INITIALLY DEFERRED,
	name	TEXT NOT NULL,
	skip_count 	INT NOT NULL DEFAULT 0,
	CONSTRAINT acqdf_name_once_per_owner UNIQUE (name, owner)
);

CREATE TABLE acq.distribution_formula_entry (
	id			SERIAL PRIMARY KEY,
	formula		INTEGER NOT NULL REFERENCES acq.distribution_formula(id)
				ON DELETE CASCADE
				DEFERRABLE INITIALLY DEFERRED,
	position	INTEGER NOT NULL,
	item_count	INTEGER NOT NULL,
	owning_lib	INTEGER REFERENCES actor.org_unit(id)
				DEFERRABLE INITIALLY DEFERRED,
	location	INTEGER REFERENCES asset.copy_location(id),
	CONSTRAINT acqdfe_lib_once_per_formula UNIQUE( formula, position ),
	CONSTRAINT acqdfe_must_be_somewhere
				CHECK( owning_lib IS NOT NULL OR location IS NOT NULL ) 
);

CREATE TABLE acq.fund_tag (
	id		SERIAL PRIMARY KEY,
	owner	INT NOT NULL
			REFERENCES actor.org_unit(id) DEFERRABLE INITIALLY DEFERRED,
	name	TEXT NOT NULL,
	CONSTRAINT acqft_tag_once_per_owner UNIQUE (name, owner)
);

CREATE TABLE acq.fund_tag_map (
	id			SERIAL PRIMARY KEY,
	fund   		INTEGER NOT NULL REFERENCES acq.fund(id)
				DEFERRABLE INITIALLY DEFERRED,
	tag         INTEGER REFERENCES acq.fund_tag(id)
				ON DELETE CASCADE
				DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT acqftm_fund_once_per_tag UNIQUE( fund, tag )
);

CREATE TABLE acq.fund_transfer (
    id               SERIAL         PRIMARY KEY,
    src_fund         INT            NOT NULL REFERENCES acq.fund( id )
                                    DEFERRABLE INITIALLY DEFERRED,
    src_amount       NUMERIC        NOT NULL,
    dest_fund        INT            NOT NULL REFERENCES acq.fund( id )
                                    DEFERRABLE INITIALLY DEFERRED,
    dest_amount      NUMERIC        NOT NULL,
    transfer_time    TIMESTAMPTZ    NOT NULL DEFAULT now(),
    transfer_user    INT            NOT NULL REFERENCES actor.usr( id )
                                    DEFERRABLE INITIALLY DEFERRED,
    note             TEXT,
	funding_source_credit INT       NOT NULL REFERENCES acq.funding_source_credit( id )
                                    DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX acqftr_usr_idx
ON acq.fund_transfer( transfer_user );

COMMENT ON TABLE acq.fund_transfer IS $$
/*
 * Copyright (C) 2009  Georgia Public Library Service
 * Scott McKellar <scott@esilibrary.com>
 *
 * Fund Transfer
 *
 * Each row represents the transfer of money from a source fund
 * to a destination fund.  There should be corresponding entries
 * in acq.fund_allocation.  The purpose of acq.fund_transfer is
 * to record how much money moved from which fund to which other
 * fund.
 *
 * The presence of two amount fields, rather than one, reflects
 * the possibility that the two funds are denominated in different
 * currencies.  If they use the same currency type, the two
 * amounts should be the same.
 *
 * ****
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
 */
$$;

CREATE TABLE acq.fiscal_calendar (
	id              SERIAL         PRIMARY KEY,
	name            TEXT           NOT NULL
);

-- Create a default calendar (though we don't specify its contents). 
-- Create a foreign key in actor.org_unit, initially pointing to
-- the default calendar.

INSERT INTO acq.fiscal_calendar (
    name
) VALUES (

    'Default'
);

ALTER TABLE actor.org_unit
ADD COLUMN fiscal_calendar INT NOT NULL
    REFERENCES acq.fiscal_calendar( id )
    DEFERRABLE INITIALLY DEFERRED
    DEFAULT 1;

CREATE TABLE acq.fiscal_year (
	id              SERIAL         PRIMARY KEY,
	calendar        INT            NOT NULL
	                               REFERENCES acq.fiscal_calendar
	                               ON DELETE CASCADE
	                               DEFERRABLE INITIALLY DEFERRED,
	year            INT            NOT NULL,
	year_begin      TIMESTAMPTZ    NOT NULL,
	year_end        TIMESTAMPTZ    NOT NULL,
	CONSTRAINT acq_fy_logical_key  UNIQUE ( calendar, year ),
    CONSTRAINT acq_fy_physical_key UNIQUE ( calendar, year_begin )
);

CREATE TABLE acq.edi_account (      -- similar tables can extend remote_account for other parts of EG
    provider    INT     NOT NULL REFERENCES acq.provider          (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    in_dir      TEXT    -- incoming messages dir (probably different than config.remote_account.path, the outgoing dir)
) INHERITS (config.remote_account);

-- We need a UNIQUE constraint here also, to support the FK from acq.provider.edi_default
ALTER TABLE acq.edi_account ADD CONSTRAINT acq_edi_account_id_unique UNIQUE (id);

-- Note below that the primary key is NOT a SERIAL type.  We will periodically truncate and rebuild
-- the table, assigning ids programmatically instead of using a sequence.
CREATE TABLE acq.debit_attribution (
    id                     INT         NOT NULL PRIMARY KEY,
    fund_debit             INT         NOT NULL
                                       REFERENCES acq.fund_debit
                                       DEFERRABLE INITIALLY DEFERRED,
    debit_amount           NUMERIC     NOT NULL,
    funding_source_credit  INT         REFERENCES acq.funding_source_credit
                                       DEFERRABLE INITIALLY DEFERRED,
    credit_amount          NUMERIC
);

CREATE INDEX acq_attribution_debit_idx
    ON acq.debit_attribution( fund_debit );

CREATE INDEX acq_attribution_credit_idx
    ON acq.debit_attribution( funding_source_credit );

-- Functions

CREATE TYPE acq.flat_lineitem_holding_subfield AS (lineitem int, holding int, subfield text, data text);
CREATE OR REPLACE FUNCTION acq.extract_holding_attr_table (lineitem int, tag text) RETURNS SETOF acq.flat_lineitem_holding_subfield AS $$
DECLARE
    counter INT;
    lida    acq.flat_lineitem_holding_subfield%ROWTYPE;
BEGIN

    SELECT  COUNT(*) INTO counter
      FROM  oils_xpath_table(
                'id',
                'marc',
                'acq.lineitem',
                '//*[@tag="' || tag || '"]',
                'id=' || lineitem
            ) as t(i int,c text);

    FOR i IN 1 .. counter LOOP
        FOR lida IN
            SELECT  * 
              FROM  (   SELECT  id,i,t,v
                          FROM  oils_xpath_table(
                                    'id',
                                    'marc',
                                    'acq.lineitem',
                                    '//*[@tag="' || tag || '"][position()=' || i || ']/*/@code|' ||
                                        '//*[@tag="' || tag || '"][position()=' || i || ']/*[@code]',
                                    'id=' || lineitem
                                ) as t(id int,t text,v text)
                    )x
        LOOP
            RETURN NEXT lida;
        END LOOP;
    END LOOP;

    RETURN;
END;
$$ LANGUAGE PLPGSQL;

CREATE TYPE acq.flat_lineitem_detail AS (lineitem int, holding int, attr text, data text);
CREATE OR REPLACE FUNCTION acq.extract_provider_holding_data ( lineitem_i int ) RETURNS SETOF acq.flat_lineitem_detail AS $$
DECLARE
    prov_i  INT;
    tag_t   TEXT;
    lida    acq.flat_lineitem_detail%ROWTYPE;
BEGIN
    SELECT provider INTO prov_i FROM acq.lineitem WHERE id = lineitem_i;
    IF NOT FOUND THEN RETURN; END IF;

    SELECT holding_tag INTO tag_t FROM acq.provider WHERE id = prov_i;
    IF NOT FOUND OR tag_t IS NULL THEN RETURN; END IF;

    FOR lida IN
        SELECT  lineitem_i,
                h.holding,
                a.name,
                h.data
          FROM  acq.extract_holding_attr_table( lineitem_i, tag_t ) h
                JOIN acq.provider_holding_subfield_map a USING (subfield)
          WHERE a.provider = prov_i
    LOOP
        RETURN NEXT lida;
    END LOOP;

    RETURN;
END;
$$ LANGUAGE PLPGSQL;

-- select * from acq.extract_provider_holding_data(699);

CREATE OR REPLACE FUNCTION public.extract_acq_marc_field ( BIGINT, TEXT, TEXT) RETURNS TEXT AS $$
	SELECT public.extract_marc_field('acq.lineitem', $1, $2, $3);
$$ LANGUAGE SQL;

/*
CREATE OR REPLACE FUNCTION public.extract_bib_marc_field ( BIGINT, TEXT ) RETURNS TEXT AS $$
	SELECT public.extract_marc_field('biblio.record_entry', $1, $2);
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION public.extract_authority_marc_field ( BIGINT, TEXT ) RETURNS TEXT AS $$
	SELECT public.extract_marc_field('authority.record_entry', $1, $2);
$$ LANGUAGE SQL;
*/
-- For example:
-- INSERT INTO acq.lineitem_provider_attr_definition ( provider, code, description, xpath ) VALUES (1,'price','Price','//*[@tag="020" or @tag="022"]/*[@code="a"][1]');

/*
Suggested vendor fields:
	vendor_price
	vendor_currency
	vendor_avail
	vendor_po
	vendor_identifier
*/

CREATE OR REPLACE FUNCTION public.ingest_acq_marc ( ) RETURNS TRIGGER AS $$
DECLARE
	value		TEXT;
	atype		TEXT;
	prov		INT;
	adef		RECORD;
	xpath_string	TEXT;
BEGIN
	FOR adef IN SELECT *,tableoid FROM acq.lineitem_attr_definition LOOP

		SELECT relname::TEXT INTO atype FROM pg_class WHERE oid = adef.tableoid;

		IF (atype NOT IN ('lineitem_usr_attr_definition','lineitem_local_attr_definition')) THEN
			IF (atype = 'lineitem_provider_attr_definition') THEN
				SELECT provider INTO prov FROM acq.lineitem_provider_attr_definition WHERE id = adef.id;
				CONTINUE WHEN NEW.provider IS NULL OR prov <> NEW.provider;
			END IF;
			
			IF (atype = 'lineitem_provider_attr_definition') THEN
				SELECT xpath INTO xpath_string FROM acq.lineitem_provider_attr_definition WHERE id = adef.id;
			ELSIF (atype = 'lineitem_marc_attr_definition') THEN
				SELECT xpath INTO xpath_string FROM acq.lineitem_marc_attr_definition WHERE id = adef.id;
			ELSIF (atype = 'lineitem_generated_attr_definition') THEN
				SELECT xpath INTO xpath_string FROM acq.lineitem_generated_attr_definition WHERE id = adef.id;
			END IF;

			SELECT extract_acq_marc_field(id, xpath_string, adef.remove) INTO value FROM acq.lineitem WHERE id = NEW.id;

			IF (value IS NOT NULL AND value <> '') THEN
				INSERT INTO acq.lineitem_attr (lineitem, definition, attr_type, attr_name, attr_value)
					VALUES (NEW.id, adef.id, atype, adef.code, value);
			END IF;

		END IF;

	END LOOP;

	RETURN NULL;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION public.cleanup_acq_marc ( ) RETURNS TRIGGER AS $$
BEGIN
	IF TG_OP = 'UPDATE' THEN
		DELETE FROM acq.lineitem_attr
	    		WHERE lineitem = OLD.id AND attr_type IN ('lineitem_provider_attr_definition', 'lineitem_marc_attr_definition','lineitem_generated_attr_definition');
		RETURN NEW;
	ELSE
		DELETE FROM acq.lineitem_attr WHERE lineitem = OLD.id;
		RETURN OLD;
	END IF;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER cleanup_lineitem_trigger
	BEFORE UPDATE OR DELETE ON acq.lineitem
	FOR EACH ROW EXECUTE PROCEDURE public.cleanup_acq_marc();

CREATE TRIGGER ingest_lineitem_trigger
	AFTER INSERT OR UPDATE ON acq.lineitem
	FOR EACH ROW EXECUTE PROCEDURE public.ingest_acq_marc();

CREATE OR REPLACE FUNCTION acq.exchange_ratio ( from_ex TEXT, to_ex TEXT ) RETURNS NUMERIC AS $$
DECLARE
    rat NUMERIC;
BEGIN
    IF from_ex = to_ex THEN
        RETURN 1.0;
    END IF;

    SELECT ratio INTO rat FROM acq.exchange_rate WHERE from_currency = from_ex AND to_currency = to_ex;

    IF FOUND THEN
        RETURN rat;
    ELSE
        SELECT ratio INTO rat FROM acq.exchange_rate WHERE from_currency = to_ex AND to_currency = from_ex;
        IF FOUND THEN
            RETURN 1.0/rat;
        END IF;
    END IF;

    RETURN NULL;

END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION acq.exchange_ratio ( TEXT, TEXT, NUMERIC ) RETURNS NUMERIC AS $$
    SELECT $3 * acq.exchange_ratio($1, $2);
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION acq.find_bad_fy()
/*
	Examine the acq.fiscal_year table, comparing successive years.
	Report any inconsistencies, i.e. years that overlap, have gaps
    between them, or are out of sequence.
*/
RETURNS SETOF RECORD AS $$
DECLARE
	first_row  BOOLEAN;
	curr_year  RECORD;
	prev_year  RECORD;
	return_rec RECORD;
BEGIN
	first_row := true;
	FOR curr_year in
		SELECT
			id,
			calendar,
			year,
			year_begin,
			year_end
		FROM
			acq.fiscal_year
		ORDER BY
			calendar,
			year_begin
	LOOP
		--
		IF first_row THEN
			first_row := FALSE;
		ELSIF curr_year.calendar    = prev_year.calendar THEN
			IF curr_year.year_begin > prev_year.year_end THEN
				-- This ugly kludge works around the fact that older
				-- versions of PostgreSQL don't support RETURN QUERY SELECT
				FOR return_rec IN SELECT
					prev_year.id,
					prev_year.year,
					'Gap between fiscal years'::TEXT
				LOOP
					RETURN NEXT return_rec;
				END LOOP;
			ELSIF curr_year.year_begin < prev_year.year_end THEN
				FOR return_rec IN SELECT
					prev_year.id,
					prev_year.year,
					'Overlapping fiscal years'::TEXT
				LOOP
					RETURN NEXT return_rec;
				END LOOP;
			ELSIF curr_year.year < prev_year.year THEN
				FOR return_rec IN SELECT
					prev_year.id,
					prev_year.year,
					'Fiscal years out of order'::TEXT
				LOOP
					RETURN NEXT return_rec;
				END LOOP;
			END IF;
		END IF;
		--
		prev_year := curr_year;
	END LOOP;
	--
	RETURN;
END;
$$ LANGUAGE plpgsql;

-- The following three types are intended for internal use
-- by the acq.attribute_debits() function.

-- For a combination of fund and funding_source: How much that source
-- allocated to that fund, and how much is left.
CREATE TYPE acq.fund_source_balance AS
(
    fund       INT,        -- fund id
    source     INT,        -- funding source id
    amount     NUMERIC,    -- original total allocation
    balance    NUMERIC     -- what's left
);

-- For a fund: a list of funding_source_credits to which
-- the fund's debits can be attributed.
CREATE TYPE acq.fund_credits AS
(
    fund       INT,        -- fund id
    credit_count INT,      -- number of entries in the following array
    credit     INT []      -- funding source credits from which a fund may draw
);

-- For a funding source credit: the funding source, the currency type
-- of the funding source, and the current balance.
CREATE TYPE acq.funding_source_credit_balance AS
(
    credit_id       INT,        -- if for funding source credit
    funding_source  INT,        -- id of funding source
    currency_type   TEXT,       -- currency type of funding source
    amount          NUMERIC,    -- original amount of credit
    balance         NUMERIC     -- how much is left
);

CREATE OR REPLACE FUNCTION acq.attribute_debits() RETURNS VOID AS $$
/*
	Function to attribute expenditures and encumbrances to funding source credits,
	and thereby to funding sources.

	Read the debits in chonological order, attributing each one to one or
	more funding source credits.  Constraints:

	1. Don't attribute more to a credit than the amount of the credit.

	2. For a given fund, don't attribute more to a funding source than the
	source has allocated to that fund.

	3. Attribute debits to credits with deadlines before attributing them to
	credits without deadlines.  Otherwise attribute to the earliest credits
	first, based on the deadline date when present, or on the effective date
	when there is no deadline.  Use funding_source_credit.id as a tie-breaker.
	This ordering is defined by an ORDER BY clause on the view
	acq.ordered_funding_source_credit.

	Start by truncating the table acq.debit_attribution.  Then insert a row
	into that table for each attribution.  If a debit cannot be fully
	attributed, insert a row for the unattributable balance, with the 
	funding_source_credit and credit_amount columns NULL.
*/
DECLARE
	curr_fund_src_bal   acq.fund_source_balance;
	fund_source_balance acq.fund_source_balance [];
	curr_fund_cr_list   acq.fund_credits;
	fund_credit_list    acq.fund_credits [];
	curr_cr_bal         acq.funding_source_credit_balance;
	cr_bal              acq.funding_source_credit_balance[];
	crl_max             INT;     -- Number of entries in fund_credits[]
	fcr_max             INT;     -- Number of entries in a credit list
	fsa_max             INT;     -- Number of entries in fund_source_balance[]
	fscr_max            INT;     -- Number of entries in cr_bal[]
	fsa                 RECORD;
	fc                  RECORD;
	sc                  RECORD;
	cr                  RECORD;
	--
	-- Used exclusively in the main loop:
	--
	deb                 RECORD;
	debit_balance       NUMERIC;  -- amount left to attribute for current debit
	conv_debit_balance  NUMERIC;  -- debit balance in currency of the fund
	attr_amount         NUMERIC;  -- amount being attributed, in currency of debit
	conv_attr_amount    NUMERIC;  -- amount being attributed, in currency of source
	conv_cred_balance   NUMERIC;  -- credit_balance in the currency of the fund
	conv_alloc_balance  NUMERIC;  -- allocated balance in the currency of the fund
	fund_found          BOOL; 
	credit_found        BOOL;
	alloc_found         BOOL;
	curr_cred_x         INT;   -- index of current credit in cr_bal[]
	curr_fund_src_x     INT;   -- index of current credit in fund_source_balance[]
	attrib_count        INT;   -- populates id of acq.debit_attribution
BEGIN
	--
	-- Load an array.  For each combination of fund and funding source, load an
	-- entry with the total amount allocated to that fund by that source.  This
	-- sum may reflect transfers as well as original allocations.  The balance
	-- is initially equal to the original amount.
	--
	fsa_max := 0;
	FOR fsa IN
		SELECT
			fund AS fund,
			funding_source AS source,
			sum( amount ) AS amount
		FROM
			acq.fund_allocation
		GROUP BY
			fund,
			funding_source
		HAVING
			sum( amount ) <> 0
		ORDER BY
			fund,
			funding_source
	LOOP
		IF fsa.amount > 0 THEN
			--
			-- Add this fund/source combination to the list
			--
			curr_fund_src_bal.fund    := fsa.fund;
			curr_fund_src_bal.source  := fsa.source;
			curr_fund_src_bal.amount  := fsa.amount;
			curr_fund_src_bal.balance := fsa.amount;
			--
			fsa_max := fsa_max + 1;
			fund_source_balance[ fsa_max ] := curr_fund_src_bal;
		END IF;
		--
	END LOOP;
	-------------------------------------------------------------------------------
	--
	-- Load another array.  For each fund, load a list of funding
	-- source credits from which that fund can get money.
	--
	crl_max := 0;
	FOR fc IN
		SELECT DISTINCT fund
		FROM acq.fund_allocation
		ORDER BY fund
	LOOP                  -- Loop over the funds
		--
		-- Initialize the array entry
		--
		curr_fund_cr_list.fund := fc.fund;
		fcr_max := 0;
		curr_fund_cr_list.credit := NULL;
		--
		-- Make a list of the funding source credits
		-- applicable to this fund
		--
		FOR sc IN
			SELECT
				ofsc.id
			FROM
				acq.ordered_funding_source_credit AS ofsc
			WHERE
				ofsc.funding_source IN
				(
					SELECT funding_source
					FROM acq.fund_allocation
					WHERE fund = fc.fund
				)
    		ORDER BY
    		    ofsc.sort_priority,
    		    ofsc.sort_date,
    		    ofsc.id
		LOOP                        -- Add each credit to the list
			fcr_max := fcr_max + 1;
			curr_fund_cr_list.credit[ fcr_max ] := sc.id;
			--
		END LOOP;
		--
		-- If there are any credits applicable to this fund,
		-- add the credit list to the list of credit lists.
		--
		IF fcr_max > 0 THEN
			curr_fund_cr_list.credit_count := fcr_max;
			crl_max := crl_max + 1;
			fund_credit_list[ crl_max ] := curr_fund_cr_list;
		END IF;
		--
	END LOOP;
	-------------------------------------------------------------------------------
	--
	-- Load yet another array.  This one is a list of funding source credits, with
	-- their balances.
	--
	fscr_max := 0;
    FOR cr in
        SELECT
            ofsc.id,
            ofsc.funding_source,
            ofsc.amount,
            fs.currency_type
        FROM
            acq.ordered_funding_source_credit AS ofsc,
            acq.funding_source fs
        WHERE
            ofsc.funding_source = fs.id
       ORDER BY
            ofsc.sort_priority,
            ofsc.sort_date,
            ofsc.id
	LOOP
		--
		curr_cr_bal.credit_id      := cr.id;
		curr_cr_bal.funding_source := cr.funding_source;
		curr_cr_bal.amount         := cr.amount;
		curr_cr_bal.balance        := cr.amount;
		curr_cr_bal.currency_type  := cr.currency_type;
		--
		fscr_max := fscr_max + 1;
		cr_bal[ fscr_max ] := curr_cr_bal;
	END LOOP;
	--
	-------------------------------------------------------------------------------
	--
	-- Now that we have loaded the lookup tables: loop through the debits,
	-- attributing each one to one or more funding source credits.
	-- 
	truncate table acq.debit_attribution;
	--
	attrib_count := 0;
	FOR deb in
		SELECT
			fd.id,
			fd.fund,
			fd.amount,
			f.currency_type,
			fd.encumbrance
		FROM
			acq.fund_debit fd,
			acq.fund f
		WHERE
			fd.fund = f.id
		ORDER BY
			id
	LOOP
		debit_balance := deb.amount;
		--
		-- Find the list of credits applicable to this fund
		--
		fund_found := false;
		FOR i in 1 .. crl_max LOOP
			IF fund_credit_list[ i ].fund = deb.fund THEN
				curr_fund_cr_list := fund_credit_list[ i ];
				fund_found := true;
				exit;
			END IF;
		END LOOP;
		--
		-- If we didn't find an entry for this fund, then there are no applicable
		-- funding sources for this fund, and the debit is hence unattributable.
		--
		-- If we did find an entry for this fund, then we have a list of funding source
		-- credits that we can apply to it.  Go through that list and attribute the
		-- debit accordingly.
		--
		IF fund_found THEN
			--
			-- For each applicable credit
			--
			FOR i in 1 .. curr_fund_cr_list.credit_count LOOP
				--
				-- Find the entry in the credit list for this credit.  If you find it but
				-- it has a zero balance, it's not useful, so treat it as if you didn't
				-- find it.
				--
				credit_found := false;
				FOR j in 1 .. fscr_max LOOP
					IF cr_bal[ j ].credit_id = curr_fund_cr_list.credit[i] THEN
						curr_cr_bal  := cr_bal[ j ];
						IF curr_cr_bal.balance <> 0 THEN
							curr_cred_x  := j;
							credit_found := true;
						END IF;
						EXIT;
					END IF;
				END LOOP;
				--
				IF NOT credit_found THEN
					--
					-- This credit is not usable; try the next one.
					--
					CONTINUE;
				END IF;
				--
				-- At this point we have an applicable credit with some money left.
				-- Now see if the relevant funding_source has any money left.
				--
				-- Search the fund/source list for an entry with this combination
				-- of fund and source.  If you find such an entry, but it has a zero
				-- balance, then it's not useful, so treat it as unfound.
				--
				alloc_found := false;
				FOR j in 1 .. fsa_max LOOP
					IF fund_source_balance[ j ].fund = deb.fund
					AND fund_source_balance[ j ].source = curr_cr_bal.funding_source THEN
						curr_fund_src_bal := fund_source_balance[ j ];
						IF curr_fund_src_bal.balance <> 0 THEN
							curr_fund_src_x := j;
							alloc_found := true;
						END IF;
						EXIT;
					END IF;
				END LOOP;
				--
				IF NOT alloc_found THEN
					--
					-- This fund/source doesn't exist is already exhausted,
					-- so we can't use this credit.  Go on to the next on.
					--
					CONTINUE;
				END IF;
				--
				-- Convert the available balances to the currency of the fund
				--
				conv_alloc_balance := curr_fund_src_bal.balance * acq.exchange_ratio(
					curr_cr_bal.currency_type, deb.currency_type );
				conv_cred_balance := curr_cr_bal.balance * acq.exchange_ratio(
					curr_cr_bal.currency_type, deb.currency_type );
				--
				-- Determine how much we can attribute to this credit: the minimum
				-- of the debit amount, the fund/source balance, and the
				-- credit balance
				--
				attr_amount := debit_balance;
				IF attr_amount > conv_alloc_balance THEN
					attr_amount := conv_alloc_balance;
				END IF;
				IF attr_amount > conv_cred_balance THEN
					attr_amount := conv_cred_balance;
				END IF;
				--
				-- Convert the amount of the attribution to the
				-- currency of the funding source.
				--
				conv_attr_amount := attr_amount * acq.exchange_ratio(
					deb.currency_type, curr_cr_bal.currency_type );
				--
				-- Insert a row to record the attribution
				--
				attrib_count := attrib_count + 1;
				INSERT INTO acq.debit_attribution (
					id,
					fund_debit,
					debit_amount,
					funding_source_credit,
					credit_amount
				) VALUES (
					attrib_count,
					deb.id,
					attr_amount,
					curr_cr_bal.credit_id,
					conv_attr_amount
				);
				--
				-- Subtract the attributed amount from the various balances
				--
				debit_balance := debit_balance - attr_amount;
				--
				curr_fund_src_bal.balance := curr_fund_src_bal.balance - conv_attr_amount;
				fund_source_balance[ curr_fund_src_x ] := curr_fund_src_bal;
				IF curr_fund_src_bal.balance <= 0 THEN
					--
					-- This allocation is exhausted.  Take it out of the list
					-- so that we don't waste time looking at it again.
					--
					FOR i IN curr_fund_src_x .. fsa_max - 1 LOOP
						fund_source_balance[ i ] := fund_source_balance[ i + 1 ];
					END LOOP;
					fund_source_balance[ fsa_max ] := NULL;
					fsa_max := fsa_max - 1;
				END IF;
				--
				curr_cr_bal.balance   := curr_cr_bal.balance - conv_attr_amount;
				cr_bal[ curr_cred_x ] := curr_cr_bal;
				IF curr_cr_bal.balance <= 0 THEN
					--
					-- This funding source credit is exhausted.  Take it out of
					-- the list so that we don't waste time looking at it again.
					--
					FOR i IN curr_cred_x .. fscr_max - 1 LOOP
						cr_bal[ i ] := cr_bal[ i + 1 ];
					END LOOP;
					cr_bal[ fscr_max ] := NULL;
					fscr_max := fscr_max - 1;
				END IF;
				--
				-- Are we done with this debit yet?
				--
				IF debit_balance <= 0 THEN
					EXIT;       -- We've fully attributed this debit; stop looking at credits.
				END IF;
			END LOOP;           -- End of loop over applicable credits
		END IF;
		--
		IF debit_balance <> 0 THEN
			--
			-- We weren't able to attribute this debit, or at least not
			-- all of it.  Insert a row for the unattributed balance.
			--
			attrib_count := attrib_count + 1;
			INSERT INTO acq.debit_attribution (
				id,
				fund_debit,
				debit_amount,
				funding_source_credit,
				credit_amount
			) VALUES (
				attrib_count,
				deb.id,
				debit_balance,
				NULL,
				NULL
			);
		END IF;
	END LOOP;   -- End of loop over debits
END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE VIEW acq.funding_source_credit_total AS
    SELECT  funding_source,
            SUM(amount) AS amount
      FROM  acq.funding_source_credit
      GROUP BY 1;

CREATE OR REPLACE VIEW acq.funding_source_allocation_total AS
    SELECT  funding_source,
            SUM(a.amount)::NUMERIC(100,2) AS amount
    FROM  acq.fund_allocation a
    GROUP BY 1;

CREATE OR REPLACE VIEW acq.funding_source_balance AS
    SELECT  COALESCE(c.funding_source, a.funding_source) AS funding_source,
            SUM(COALESCE(c.amount,0.0) - COALESCE(a.amount,0.0))::NUMERIC(100,2) AS amount
      FROM  acq.funding_source_credit_total c
            FULL JOIN acq.funding_source_allocation_total a USING (funding_source)
      GROUP BY 1;

CREATE OR REPLACE VIEW acq.fund_allocation_total AS
    SELECT  fund,
            SUM(a.amount * acq.exchange_ratio(s.currency_type, f.currency_type))::NUMERIC(100,2) AS amount
    FROM acq.fund_allocation a
         JOIN acq.fund f ON (a.fund = f.id)
         JOIN acq.funding_source s ON (a.funding_source = s.id)
    GROUP BY 1;

CREATE OR REPLACE VIEW acq.fund_debit_total AS
    SELECT  fund.id AS fund,
            fund_debit.encumbrance AS encumbrance,
			SUM( COALESCE( fund_debit.amount, 0 ) ) AS amount
      FROM acq.fund AS fund
            LEFT JOIN acq.fund_debit AS fund_debit
                ON ( fund.id = fund_debit.fund )
      GROUP BY 1,2;

CREATE OR REPLACE VIEW acq.fund_encumbrance_total AS
    SELECT  fund,
            SUM(amount) AS amount
      FROM  acq.fund_debit_total
      WHERE encumbrance IS TRUE
      GROUP BY 1;

CREATE OR REPLACE VIEW acq.fund_spent_total AS
    SELECT  fund,
            SUM(amount) AS amount
      FROM  acq.fund_debit_total
      WHERE encumbrance IS FALSE
      GROUP BY 1;

CREATE OR REPLACE VIEW acq.fund_combined_balance AS
    SELECT  c.fund,
            c.amount - COALESCE(d.amount,0.0) AS amount
      FROM  acq.fund_allocation_total c
            LEFT JOIN acq.fund_debit_total d USING (fund);

CREATE OR REPLACE VIEW acq.fund_spent_balance AS
    SELECT  c.fund,
            c.amount - COALESCE(d.amount,0.0) AS amount
      FROM  acq.fund_allocation_total c
            LEFT JOIN acq.fund_spent_total d USING (fund);

COMMIT;




