/*
 * Copyright (C) 2009  Georgia Public Library Service
 * Scott McKellar <scott@esilibrary.com>
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

DROP SCHEMA IF EXISTS acq CASCADE;

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

CREATE TABLE acq.claim_policy (
	id              SERIAL       PRIMARY KEY,
	org_unit        INT          NOT NULL REFERENCES actor.org_unit
	                             DEFERRABLE INITIALLY DEFERRED,
	name            TEXT         NOT NULL,
	description     TEXT         NOT NULL,
	CONSTRAINT name_once_per_org UNIQUE (org_unit, name)
);

CREATE TABLE acq.claim_event_type (
	id             SERIAL           PRIMARY KEY,
	org_unit       INT              NOT NULL REFERENCES actor.org_unit(id)
	                                         DEFERRABLE INITIALLY DEFERRED,
	code           TEXT             NOT NULL,
	description    TEXT             NOT NULL,
	library_initiated BOOL          NOT NULL DEFAULT FALSE,
	CONSTRAINT event_type_once_per_org UNIQUE ( org_unit, code )
);

CREATE TABLE acq.claim_policy_action (
	id              SERIAL       PRIMARY KEY,
	claim_policy    INT          NOT NULL REFERENCES acq.claim_policy
                                 ON DELETE CASCADE
	                             DEFERRABLE INITIALLY DEFERRED,
	action_interval INTERVAL     NOT NULL,
	action          INT          NOT NULL REFERENCES acq.claim_event_type
	                             DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT action_sequence UNIQUE (claim_policy, action_interval)
);

CREATE TABLE acq.provider (
    id                  SERIAL  PRIMARY KEY,
    name                TEXT    NOT NULL,
    owner               INT     NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
    currency_type       TEXT    NOT NULL REFERENCES acq.currency_type (code) DEFERRABLE INITIALLY DEFERRED,
    code                TEXT    NOT NULL,
    holding_tag         TEXT,
    san                 TEXT,
    edi_default         INT,          -- REFERENCES acq.edi_account (id) DEFERRABLE INITIALLY DEFERRED
	active              BOOL    NOT NULL DEFAULT TRUE,
	prepayment_required BOOL    NOT NULL DEFAULT FALSE,
    url                 TEXT,
    email               TEXT,
    phone               TEXT,
    fax_phone           TEXT,
	default_claim_policy INT    REFERENCES acq.claim_policy
	                            DEFERRABLE INITIALLY DEFERRED,
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
	post_code	TEXT	NOT NULL,
	fax_phone	TEXT
);

CREATE TABLE acq.provider_contact (
	id		SERIAL	PRIMARY KEY,
    provider    INT NOT NULL REFERENCES acq.provider (id) DEFERRABLE INITIALLY DEFERRED,
    name    TEXT NOT NULL,
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
	post_code		TEXT	NOT NULL,
	fax_phone		TEXT
);

CREATE TABLE acq.provider_note (
	id		SERIAL				PRIMARY KEY,
	provider    INT				NOT NULL REFERENCES acq.provider (id) DEFERRABLE INITIALLY DEFERRED,
	creator		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	editor		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	edit_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	value		TEXT			NOT NULL
);
CREATE INDEX acq_pro_note_pro_idx      ON acq.provider_note ( provider );
CREATE INDEX acq_pro_note_creator_idx  ON acq.provider_note ( creator );
CREATE INDEX acq_pro_note_editor_idx   ON acq.provider_note ( editor );


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
The acq.ordered_funding_source_credit view is a prioritized
ordering of funding source credits.  When ordered by the first
three columns, this view defines the order in which the various
credits are to be tapped for spending, subject to the allocations
in the acq.fund_allocation table.

The first column reflects the principle that we should spend
money with deadlines before spending money without deadlines.

The second column reflects the principle that we should spend the
oldest money first.  For money with deadlines, that means that we
spend first from the credit with the earliest deadline.  For
money without deadlines, we spend first from the credit with the
earliest effective date.

The third column is a tie breaker to ensure a consistent
ordering.
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
	active          BOOL    NOT NULL DEFAULT TRUE,
	balance_warning_percent INT,
	balance_stop_percent    INT,
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

CREATE TABLE acq.fund_allocation_percent
(
    id                   SERIAL            PRIMARY KEY,
    funding_source       INT               NOT NULL REFERENCES acq.funding_source
                                               DEFERRABLE INITIALLY DEFERRED,
    org                  INT               NOT NULL REFERENCES actor.org_unit
                                               DEFERRABLE INITIALLY DEFERRED,
    fund_code            TEXT,
    percent              NUMERIC           NOT NULL,
    allocator            INTEGER           NOT NULL REFERENCES actor.usr
                                               DEFERRABLE INITIALLY DEFERRED,
    note                 TEXT,
    create_time          TIMESTAMPTZ       NOT NULL DEFAULT now(),
    CONSTRAINT logical_key UNIQUE( funding_source, org, fund_code ),
    CONSTRAINT percentage_range CHECK( percent >= 0 AND percent <= 100 )
);

-- Trigger function to validate combination of org_unit and fund_code

CREATE OR REPLACE FUNCTION acq.fund_alloc_percent_val()
RETURNS TRIGGER AS $$
--
DECLARE
--
dummy int := 0;
--
BEGIN
    SELECT
        1
    INTO
        dummy
    FROM
        acq.fund
    WHERE
        org = NEW.org
        AND code = NEW.fund_code
        LIMIT 1;
    --
    IF dummy = 1 then
        RETURN NEW;
    ELSE
        RAISE EXCEPTION 'No fund exists for org % and code %', NEW.org, NEW.fund_code;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER acq_fund_alloc_percent_val_trig
    BEFORE INSERT OR UPDATE ON acq.fund_allocation_percent
    FOR EACH ROW EXECUTE PROCEDURE acq.fund_alloc_percent_val();

-- To do: trigger to verify that percentages don't add up to more than 100

CREATE OR REPLACE FUNCTION acq.fap_limit_100()
RETURNS TRIGGER AS $$
DECLARE
--
total_percent numeric;
--
BEGIN
    SELECT
        sum( percent )
    INTO
        total_percent
    FROM
        acq.fund_allocation_percent AS fap
    WHERE
        fap.funding_source = NEW.funding_source;
    --
    IF total_percent > 100 THEN
        RAISE EXCEPTION 'Total percentages exceed 100 for funding_source %',
            NEW.funding_source;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER acqfap_limit_100_trig
    AFTER INSERT OR UPDATE ON acq.fund_allocation_percent
    FOR EACH ROW EXECUTE PROCEDURE acq.fap_limit_100();

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

CREATE TABLE acq.cancel_reason (
        id            SERIAL            PRIMARY KEY,
        org_unit      INTEGER           NOT NULL REFERENCES actor.org_unit( id )
                                        DEFERRABLE INITIALLY DEFERRED,
        label         TEXT              NOT NULL,
        description   TEXT              NOT NULL,
		keep_debits   BOOL              NOT NULL DEFAULT FALSE,
        CONSTRAINT acq_cancel_reason_one_per_org_unit UNIQUE( org_unit, label )
);

-- Reserve ids 1-999 for stock reasons
-- Reserve ids 1000-1999 for EDI reasons
-- 2000+ are available for staff to create

SELECT SETVAL('acq.cancel_reason_id_seq'::TEXT, 2000);

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
	name			TEXT					NOT NULL,
	cancel_reason   INT                     REFERENCES acq.cancel_reason( id )
                                            DEFERRABLE INITIALLY DEFERRED,
	prepayment_required BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT valid_po_state CHECK (state IN ('new','pending','on-order','received','cancelled'))
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
	value		TEXT			NOT NULL,
	vendor_public BOOLEAN       NOT NULL DEFAULT FALSE
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
	eg_bib_id           BIGINT                      REFERENCES biblio.record_entry (id) DEFERRABLE INITIALLY DEFERRED,
	source_label        TEXT,
	state               TEXT                        NOT NULL DEFAULT 'new',
	cancel_reason       INT                         REFERENCES acq.cancel_reason( id )
                                                    DEFERRABLE INITIALLY DEFERRED,
	estimated_unit_price NUMERIC,
	claim_policy        INT                         REFERENCES acq.claim_policy
			                                        DEFERRABLE INITIALLY DEFERRED,
    queued_record       BIGINT                      REFERENCES vandelay.queued_bib_record (id)
                                                        ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT picklist_or_po CHECK (picklist IS NOT NULL OR purchase_order IS NOT NULL)
);
CREATE INDEX li_po_idx ON acq.lineitem (purchase_order);
CREATE INDEX li_pl_idx ON acq.lineitem (picklist);
CREATE INDEX li_creator_idx   ON acq.lineitem ( creator );
CREATE INDEX li_editor_idx    ON acq.lineitem ( editor );
CREATE INDEX li_selector_idx  ON acq.lineitem ( selector );

CREATE TABLE acq.lineitem_alert_text (
    id               SERIAL         PRIMARY KEY,
    code             TEXT           NOT NULL,
    description      TEXT,
	owning_lib       INT            NOT NULL
	                                REFERENCES actor.org_unit(id)
	                                DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT alert_one_code_per_org UNIQUE (code, owning_lib)
);

CREATE TABLE acq.lineitem_note (
	id		SERIAL				PRIMARY KEY,
	lineitem	INT				NOT NULL REFERENCES acq.lineitem (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	creator		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	editor		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	edit_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	value		TEXT			NOT NULL,
	alert_text	INT						 REFERENCES acq.lineitem_alert_text(id)
										 DEFERRABLE INITIALLY DEFERRED,
	vendor_public BOOLEAN       NOT NULL DEFAULT FALSE
);
CREATE INDEX li_note_li_idx ON acq.lineitem_note (lineitem);
CREATE INDEX li_note_creator_idx  ON acq.lineitem_note ( creator );
CREATE INDEX li_note_editor_idx   ON acq.lineitem_note ( editor );

CREATE TABLE acq.lineitem_detail (
    id          BIGSERIAL	PRIMARY KEY,
    lineitem    INT         NOT NULL REFERENCES acq.lineitem (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    fund        INT         REFERENCES acq.fund (id) DEFERRABLE INITIALLY DEFERRED,
    fund_debit  INT         REFERENCES acq.fund_debit (id) DEFERRABLE INITIALLY DEFERRED,
    eg_copy_id  BIGINT,     -- REFERENCES asset.copy (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED, -- XXX could be an serial.issuance
    barcode     TEXT,
    cn_label    TEXT,
    note        TEXT,
    collection_code TEXT,
    circ_modifier   TEXT    REFERENCES config.circ_modifier (code) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    owning_lib  INT         REFERENCES actor.org_unit (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    location    INT         REFERENCES asset.copy_location (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    recv_time   TIMESTAMP WITH TIME ZONE,
	receiver		INT	    REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	cancel_reason   INT     REFERENCES acq.cancel_reason( id ) DEFERRABLE INITIALLY DEFERRED
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
	lineitem	BIGINT		NOT NULL REFERENCES acq.lineitem (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
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
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath, remove ) VALUES ('upc', 'UPC', '//*[@tag="024" and @ind1="1"]/*[@code="a"]', $r$(?:-|\s.+$)$r$);
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

CREATE TABLE acq.distribution_formula_application (
    id BIGSERIAL PRIMARY KEY,
    creator INT NOT NULL REFERENCES actor.usr(id) DEFERRABLE INITIALLY DEFERRED,
    create_time TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    formula INT NOT NULL
        REFERENCES acq.distribution_formula(id) DEFERRABLE INITIALLY DEFERRED,
    lineitem INT NOT NULL
        REFERENCES acq.lineitem(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX acqdfa_df_idx
    ON acq.distribution_formula_application(formula);
CREATE INDEX acqdfa_li_idx
    ON acq.distribution_formula_application(lineitem);
CREATE INDEX acqdfa_creator_idx
    ON acq.distribution_formula_application(creator);

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
    dest_fund        INT            REFERENCES acq.fund( id )
                                    DEFERRABLE INITIALLY DEFERRED,
    dest_amount      NUMERIC,
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
Fund Transfer
Each row represents the transfer of money from a source fund
to a destination fund.  There should be corresponding entries
in acq.fund_allocation.  The purpose of acq.fund_transfer is
to record how much money moved from which fund to which other
fund.

The presence of two amount fields, rather than one, reflects
the possibility that the two funds are denominated in different
currencies.  If they use the same currency type, the two
amounts should be the same.
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

ALTER TABLE actor.org_unit ADD FOREIGN KEY
	(fiscal_calendar) REFERENCES acq.fiscal_calendar( id )
   	DEFERRABLE INITIALLY DEFERRED;

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
    in_dir      TEXT,   -- incoming messages dir (probably different than config.remote_account.path, the outgoing dir)
    vendcode    TEXT,
    vendacct    TEXT
) INHERITS (config.remote_account);

-- We need a UNIQUE constraint here also, to support the FK from acq.provider.edi_default
ALTER TABLE acq.edi_account ADD PRIMARY KEY (id);

CREATE TABLE acq.edi_message (
    id               SERIAL          PRIMARY KEY,
    account          INTEGER         REFERENCES acq.edi_account(id)
                                     DEFERRABLE INITIALLY DEFERRED,
    remote_file      TEXT,
    create_time      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    translate_time   TIMESTAMPTZ,
    process_time     TIMESTAMPTZ,
    error_time       TIMESTAMPTZ,
    status           TEXT            NOT NULL DEFAULT 'new'
                                     CONSTRAINT status_value CHECK
                                     ( status IN (
                                        'new',          -- needs to be translated
                                        'translated',   -- needs to be processed
                                        'trans_error',  -- error in translation step
                                        'processed',    -- needs to have remote_file deleted
                                        'proc_error',   -- error in processing step
                                        'delete_error', -- error in deletion
										'retry',        -- need to retry
                                        'complete'      -- done
                                     )),
    edi              TEXT,
    jedi             TEXT,
    error            TEXT,
    purchase_order   INT             REFERENCES acq.purchase_order
                                     DEFERRABLE INITIALLY DEFERRED,
	message_type     TEXT            NOT NULL CONSTRAINT valid_message_type CHECK
	                                 ( message_type IN (
									     'ORDERS',
									     'ORDRSP',
									     'INVOIC',
									     'OSTENQ',
									     'OSTRPT'
									 ))
);

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

-- Invoicing

CREATE TABLE acq.invoice_method (
    code    TEXT    PRIMARY KEY,
    name    TEXT    NOT NULL -- i18n-ize
);

CREATE TABLE acq.invoice_payment_method (
    code    TEXT    PRIMARY KEY,
    name    TEXT    NOT NULL -- i18n-ize
);

CREATE TABLE acq.invoice (
    id          SERIAL      PRIMARY KEY,
    receiver    INT         NOT NULL REFERENCES actor.org_unit (id),
    provider    INT         NOT NULL REFERENCES acq.provider (id),
    shipper     INT         NOT NULL REFERENCES acq.provider (id),
    recv_date   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    recv_method TEXT        NOT NULL REFERENCES acq.invoice_method (code) DEFAULT 'EDI',
    inv_type    TEXT,       -- A "type" field is desired, but no idea what goes here
    inv_ident   TEXT        NOT NULL, -- vendor-supplied invoice id/number
	payment_auth TEXT,
	payment_method TEXT     REFERENCES acq.invoice_payment_method (code)
	                        DEFERRABLE INITIALLY DEFERRED,
	note        TEXT,
    complete    BOOL        NOT NULL DEFAULT FALSE,
    CONSTRAINT  inv_ident_once_per_provider UNIQUE(provider, inv_ident)
);

CREATE TABLE acq.invoice_entry (
    id              SERIAL      PRIMARY KEY,
    invoice         INT         NOT NULL REFERENCES acq.invoice (id) ON DELETE CASCADE,
    purchase_order  INT         REFERENCES acq.purchase_order (id) ON UPDATE CASCADE ON DELETE SET NULL,
    lineitem        INT         REFERENCES acq.lineitem (id) ON UPDATE CASCADE ON DELETE SET NULL,
    inv_item_count  INT         NOT NULL, -- How many acqlids did they say they sent
    phys_item_count INT, -- and how many did staff count
    note            TEXT,
    billed_per_item BOOL,
    cost_billed     NUMERIC(8,2),
    actual_cost     NUMERIC(8,2),
	amount_paid     NUMERIC (8,2)
);

CREATE INDEX ie_inv_idx on acq.invoice_entry (invoice);
CREATE INDEX ie_po_idx on acq.invoice_entry (purchase_order);
CREATE INDEX ie_li_idx on acq.invoice_entry (lineitem);

CREATE TABLE acq.invoice_item_type (
    code    TEXT    PRIMARY KEY,
    name    TEXT    NOT NULL,  -- i18n-ize
	prorate BOOL    NOT NULL DEFAULT FALSE
);

CREATE TABLE acq.po_item (
	id              SERIAL      PRIMARY KEY,
	purchase_order  INT         REFERENCES acq.purchase_order (id)
	                            ON UPDATE CASCADE ON DELETE SET NULL
	                            DEFERRABLE INITIALLY DEFERRED,
	fund_debit      INT         REFERENCES acq.fund_debit (id)
	                            DEFERRABLE INITIALLY DEFERRED,
	inv_item_type   TEXT        NOT NULL
	                            REFERENCES acq.invoice_item_type (code)
	                            DEFERRABLE INITIALLY DEFERRED,
	title           TEXT,
	author          TEXT,
	note            TEXT,
	estimated_cost  NUMERIC(8,2),
	fund            INT         REFERENCES acq.fund (id)
	                            DEFERRABLE INITIALLY DEFERRED,
    target          BIGINT
);

CREATE INDEX poi_po_idx ON acq.po_item (purchase_order);

CREATE TABLE acq.invoice_item ( -- for invoice-only debits: taxes/fees/non-bib items/etc
    id              SERIAL      PRIMARY KEY,
    invoice         INT         NOT NULL REFERENCES acq.invoice (id) ON UPDATE CASCADE ON DELETE CASCADE,
    purchase_order  INT         REFERENCES acq.purchase_order (id) ON UPDATE CASCADE ON DELETE SET NULL,
    fund_debit      INT         REFERENCES acq.fund_debit (id),
    inv_item_type   TEXT        NOT NULL REFERENCES acq.invoice_item_type (code),
    title           TEXT,
    author          TEXT,
    note            TEXT,
    cost_billed     NUMERIC(8,2),
    actual_cost     NUMERIC(8,2),
	fund            INT         REFERENCES acq.fund (id)
	                            DEFERRABLE INITIALLY DEFERRED,
	amount_paid     NUMERIC (8,2),
	po_item         INT         REFERENCES acq.po_item (id)
	                            DEFERRABLE INITIALLY DEFERRED,
    target          BIGINT
);

CREATE INDEX ii_inv_idx on acq.invoice_item (invoice);
CREATE INDEX ii_po_idx on acq.invoice_item (purchase_order);
CREATE INDEX ii_poi_idx on acq.invoice_item (po_item);

-- Patron requests
CREATE TABLE acq.user_request_type (
    id      SERIAL  PRIMARY KEY,
    label   TEXT    NOT NULL UNIQUE -- i18n-ize
);

INSERT INTO acq.user_request_type (id,label) VALUES (1, oils_i18n_gettext('1', 'Books', 'aurt', 'label'));
INSERT INTO acq.user_request_type (id,label) VALUES (2, oils_i18n_gettext('2', 'Journal/Magazine & Newspaper Articles', 'aurt', 'label'));
INSERT INTO acq.user_request_type (id,label) VALUES (3, oils_i18n_gettext('3', 'Audiobooks', 'aurt', 'label'));
INSERT INTO acq.user_request_type (id,label) VALUES (4, oils_i18n_gettext('4', 'Music', 'aurt', 'label'));
INSERT INTO acq.user_request_type (id,label) VALUES (5, oils_i18n_gettext('5', 'DVDs', 'aurt', 'label'));

SELECT SETVAL('acq.user_request_type_id_seq'::TEXT, 6);

CREATE TABLE acq.user_request (
    id                  SERIAL  PRIMARY KEY,
    usr                 INT     NOT NULL REFERENCES actor.usr (id), -- requesting user
    hold                BOOL    NOT NULL DEFAULT TRUE,

    pickup_lib          INT     NOT NULL REFERENCES actor.org_unit (id), -- pickup lib
    holdable_formats    TEXT,           -- nullable, for use in hold creation
    phone_notify        TEXT,
    email_notify        BOOL    NOT NULL DEFAULT TRUE,
    lineitem            INT     REFERENCES acq.lineitem (id) ON DELETE CASCADE,
    eg_bib              BIGINT  REFERENCES biblio.record_entry (id) ON DELETE CASCADE,
    request_date        TIMESTAMPTZ NOT NULL DEFAULT NOW(), -- when they requested it
    need_before         TIMESTAMPTZ,    -- don't create holds after this
    max_fee             TEXT,
  
    request_type        INT     NOT NULL REFERENCES acq.user_request_type (id),
    isxn                TEXT,
    title               TEXT,
    volume              TEXT,
    author              TEXT,
    article_title       TEXT,
    article_pages       TEXT,
    publisher           TEXT,
    location            TEXT,
    pubdate             TEXT,
    mentioned           TEXT,
    other_info          TEXT,
	cancel_reason       INT    REFERENCES acq.cancel_reason( id )
	                           DEFERRABLE INITIALLY DEFERRED
);


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
	SELECT extract_marc_field('acq.lineitem', $1, $2, $3);
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

CREATE OR REPLACE FUNCTION public.ingest_acq_marc ( ) RETURNS TRIGGER AS $function$
DECLARE
	value		TEXT;
	atype		TEXT;
	prov		INT;
	pos 		INT;
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

            xpath_string := REGEXP_REPLACE(xpath_string,$re$//?text\(\)$$re$,'');

            IF (adef.code = 'title' OR adef.code = 'author') THEN
                -- title and author should not be split
                -- FIXME: once oils_xpath can grok XPATH 2.0 functions, we can use
                -- string-join in the xpath and remove this special case
    			SELECT extract_acq_marc_field(id, xpath_string, adef.remove) INTO value FROM acq.lineitem WHERE id = NEW.id;
    			IF (value IS NOT NULL AND value <> '') THEN
				    INSERT INTO acq.lineitem_attr (lineitem, definition, attr_type, attr_name, attr_value)
	     			    VALUES (NEW.id, adef.id, atype, adef.code, value);
                END IF;
            ELSE
                pos := 1;

                LOOP
    			    SELECT extract_acq_marc_field(id, xpath_string || '[' || pos || ']', adef.remove) INTO value FROM acq.lineitem WHERE id = NEW.id;

    			    IF (value IS NOT NULL AND value <> '') THEN
	    			    INSERT INTO acq.lineitem_attr (lineitem, definition, attr_type, attr_name, attr_value)
		    			    VALUES (NEW.id, adef.id, atype, adef.code, value);
                    ELSE
                        EXIT;
			        END IF;

                    pos := pos + 1;
                END LOOP;
            END IF;

		END IF;

	END LOOP;

	RETURN NULL;
END;
$function$ LANGUAGE PLPGSQL;

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

CREATE OR REPLACE FUNCTION acq.transfer_fund(
	old_fund   IN INT,
	old_amount IN NUMERIC,     -- in currency of old fund
	new_fund   IN INT,
	new_amount IN NUMERIC,     -- in currency of new fund
	user_id    IN INT,
	xfer_note  IN TEXT         -- to be recorded in acq.fund_transfer
	-- ,funding_source_in IN INT  -- if user wants to specify a funding source (see notes)
) RETURNS VOID AS $$
/* -------------------------------------------------------------------------------

Function to transfer money from one fund to another.

A transfer is represented as a pair of entries in acq.fund_allocation, with a
negative amount for the old (losing) fund and a positive amount for the new
(gaining) fund.  In some cases there may be more than one such pair of entries
in order to pull the money from different funding sources, or more specifically
from different funding source credits.  For each such pair there is also an
entry in acq.fund_transfer.

Since funding_source is a non-nullable column in acq.fund_allocation, we must
choose a funding source for the transferred money to come from.  This choice
must meet two constraints, so far as possible:

1. The amount transferred from a given funding source must not exceed the
amount allocated to the old fund by the funding source.  To that end we
compare the amount being transferred to the amount allocated.

2. We shouldn't transfer money that has already been spent or encumbered, as
defined by the funding attribution process.  We attribute expenses to the
oldest funding source credits first.  In order to avoid transferring that
attributed money, we reverse the priority, transferring from the newest funding
source credits first.  There can be no guarantee that this approach will
avoid overcommitting a fund, but no other approach can do any better.

In this context the age of a funding source credit is defined by the
deadline_date for credits with deadline_dates, and by the effective_date for
credits without deadline_dates, with the proviso that credits with deadline_dates
are all considered "older" than those without.

----------

In the signature for this function, there is one last parameter commented out,
named "funding_source_in".  Correspondingly, the WHERE clause for the query
driving the main loop has an OR clause commented out, which references the
funding_source_in parameter.

If these lines are uncommented, this function will allow the user optionally to
restrict a fund transfer to a specified funding source.  If the source
parameter is left NULL, then there will be no such restriction.

------------------------------------------------------------------------------- */ 
DECLARE
	same_currency      BOOLEAN;
	currency_ratio     NUMERIC;
	old_fund_currency  TEXT;
	old_remaining      NUMERIC;  -- in currency of old fund
	new_fund_currency  TEXT;
	new_fund_active    BOOLEAN;
	new_remaining      NUMERIC;  -- in currency of new fund
	curr_old_amt       NUMERIC;  -- in currency of old fund
	curr_new_amt       NUMERIC;  -- in currency of new fund
	source_addition    NUMERIC;  -- in currency of funding source
	source_deduction   NUMERIC;  -- in currency of funding source
	orig_allocated_amt NUMERIC;  -- in currency of funding source
	allocated_amt      NUMERIC;  -- in currency of fund
	source             RECORD;
BEGIN
	--
	-- Sanity checks
	--
	IF old_fund IS NULL THEN
		RAISE EXCEPTION 'acq.transfer_fund: old fund id is NULL';
	END IF;
	--
	IF old_amount IS NULL THEN
		RAISE EXCEPTION 'acq.transfer_fund: amount to transfer is NULL';
	END IF;
	--
	-- The new fund and its amount must be both NULL or both not NULL.
	--
	IF new_fund IS NOT NULL AND new_amount IS NULL THEN
		RAISE EXCEPTION 'acq.transfer_fund: amount to transfer to receiving fund is NULL';
	END IF;
	--
	IF new_fund IS NULL AND new_amount IS NOT NULL THEN
		RAISE EXCEPTION 'acq.transfer_fund: receiving fund is NULL, its amount is not NULL';
	END IF;
	--
	IF user_id IS NULL THEN
		RAISE EXCEPTION 'acq.transfer_fund: user id is NULL';
	END IF;
	--
	-- Initialize the amounts to be transferred, each denominated
	-- in the currency of its respective fund.  They will be
	-- reduced on each iteration of the loop.
	--
	old_remaining := old_amount;
	new_remaining := new_amount;
	--
	-- RAISE NOTICE 'Transferring % in fund % to % in fund %',
	--	old_amount, old_fund, new_amount, new_fund;
	--
	-- Get the currency types of the old and new funds.
	--
	SELECT
		currency_type
	INTO
		old_fund_currency
	FROM
		acq.fund
	WHERE
		id = old_fund;
	--
	IF old_fund_currency IS NULL THEN
		RAISE EXCEPTION 'acq.transfer_fund: old fund id % is not defined', old_fund;
	END IF;
	--
	IF new_fund IS NOT NULL THEN
		SELECT
			currency_type,
			active
		INTO
			new_fund_currency,
			new_fund_active
		FROM
			acq.fund
		WHERE
			id = new_fund;
		--
		IF new_fund_currency IS NULL THEN
			RAISE EXCEPTION 'acq.transfer_fund: new fund id % is not defined', new_fund;
		ELSIF NOT new_fund_active THEN
			--
			-- No point in putting money into a fund from whence you can't spend it
			--
			RAISE EXCEPTION 'acq.transfer_fund: new fund id % is inactive', new_fund;
		END IF;
		--
		IF new_amount = old_amount THEN
			same_currency := true;
			currency_ratio := 1;
		ELSE
			--
			-- We'll have to translate currency between funds.  We presume that
			-- the calling code has already applied an appropriate exchange rate,
			-- so we'll apply the same conversion to each sub-transfer.
			--
			same_currency := false;
			currency_ratio := new_amount / old_amount;
		END IF;
	END IF;
	--
	-- Identify the funding source(s) from which we want to transfer the money.
	-- The principle is that we want to transfer the newest money first, because
	-- we spend the oldest money first.  The priority for spending is defined
	-- by a sort of the view acq.ordered_funding_source_credit.
	--
	FOR source in
		SELECT
			ofsc.id,
			ofsc.funding_source,
			ofsc.amount,
			ofsc.amount * acq.exchange_ratio( fs.currency_type, old_fund_currency )
				AS converted_amt,
			fs.currency_type
		FROM
			acq.ordered_funding_source_credit AS ofsc,
			acq.funding_source fs
		WHERE
			ofsc.funding_source = fs.id
			and ofsc.funding_source IN
			(
				SELECT funding_source
				FROM acq.fund_allocation
				WHERE fund = old_fund
			)
			-- and
			-- (
			-- 	ofsc.funding_source = funding_source_in
			-- 	OR funding_source_in IS NULL
			-- )
		ORDER BY
			ofsc.sort_priority desc,
			ofsc.sort_date desc,
			ofsc.id desc
	LOOP
		--
		-- Determine how much money the old fund got from this funding source,
		-- denominated in the currency types of the source and of the fund.
		-- This result may reflect transfers from previous iterations.
		--
		SELECT
			COALESCE( sum( amount ), 0 ),
			COALESCE( sum( amount )
				* acq.exchange_ratio( source.currency_type, old_fund_currency ), 0 )
		INTO
			orig_allocated_amt,     -- in currency of the source
			allocated_amt           -- in currency of the old fund
		FROM
			acq.fund_allocation
		WHERE
			fund = old_fund
			and funding_source = source.funding_source;
		--	
		-- Determine how much to transfer from this credit, in the currency
		-- of the fund.   Begin with the amount remaining to be attributed:
		--
		curr_old_amt := old_remaining;
		--
		-- Can't attribute more than was allocated from the fund:
		--
		IF curr_old_amt > allocated_amt THEN
			curr_old_amt := allocated_amt;
		END IF;
		--
		-- Can't attribute more than the amount of the current credit:
		--
		IF curr_old_amt > source.converted_amt THEN
			curr_old_amt := source.converted_amt;
		END IF;
		--
		curr_old_amt := trunc( curr_old_amt, 2 );
		--
		old_remaining := old_remaining - curr_old_amt;
		--
		-- Determine the amount to be deducted, if any,
		-- from the old allocation.
		--
		IF old_remaining > 0 THEN
			--
			-- In this case we're using the whole allocation, so use that
			-- amount directly instead of applying a currency translation
			-- and thereby inviting round-off errors.
			--
			source_deduction := - orig_allocated_amt;
		ELSE 
			source_deduction := trunc(
				( - curr_old_amt ) *
					acq.exchange_ratio( old_fund_currency, source.currency_type ),
				2 );
		END IF;
		--
		IF source_deduction <> 0 THEN
			--
			-- Insert negative allocation for old fund in fund_allocation,
			-- converted into the currency of the funding source
			--
			INSERT INTO acq.fund_allocation (
				funding_source,
				fund,
				amount,
				allocator,
				note
			) VALUES (
				source.funding_source,
				old_fund,
				source_deduction,
				user_id,
				'Transfer to fund ' || new_fund
			);
		END IF;
		--
		IF new_fund IS NOT NULL THEN
			--
			-- Determine how much to add to the new fund, in
			-- its currency, and how much remains to be added:
			--
			IF same_currency THEN
				curr_new_amt := curr_old_amt;
			ELSE
				IF old_remaining = 0 THEN
					--
					-- This is the last iteration, so nothing should be left
					--
					curr_new_amt := new_remaining;
					new_remaining := 0;
				ELSE
					curr_new_amt := trunc( curr_old_amt * currency_ratio, 2 );
					new_remaining := new_remaining - curr_new_amt;
				END IF;
			END IF;
			--
			-- Determine how much to add, if any,
			-- to the new fund's allocation.
			--
			IF old_remaining > 0 THEN
				--
				-- In this case we're using the whole allocation, so use that amount
				-- amount directly instead of applying a currency translation and
				-- thereby inviting round-off errors.
				--
				source_addition := orig_allocated_amt;
			ELSIF source.currency_type = old_fund_currency THEN
				--
				-- In this case we don't need a round trip currency translation,
				-- thereby inviting round-off errors:
				--
				source_addition := curr_old_amt;
			ELSE 
				source_addition := trunc(
					curr_new_amt *
						acq.exchange_ratio( new_fund_currency, source.currency_type ),
					2 );
			END IF;
			--
			IF source_addition <> 0 THEN
				--
				-- Insert positive allocation for new fund in fund_allocation,
				-- converted to the currency of the founding source
				--
				INSERT INTO acq.fund_allocation (
					funding_source,
					fund,
					amount,
					allocator,
					note
				) VALUES (
					source.funding_source,
					new_fund,
					source_addition,
					user_id,
					'Transfer from fund ' || old_fund
				);
			END IF;
		END IF;
		--
		IF trunc( curr_old_amt, 2 ) <> 0
		OR trunc( curr_new_amt, 2 ) <> 0 THEN
			--
			-- Insert row in fund_transfer, using amounts in the currency of the funds
			--
			INSERT INTO acq.fund_transfer (
				src_fund,
				src_amount,
				dest_fund,
				dest_amount,
				transfer_user,
				note,
				funding_source_credit
			) VALUES (
				old_fund,
				trunc( curr_old_amt, 2 ),
				new_fund,
				trunc( curr_new_amt, 2 ),
				user_id,
				xfer_note,
				source.id
			);
		END IF;
		--
		if old_remaining <= 0 THEN
			EXIT;                   -- Nothing more to be transferred
		END IF;
	END LOOP;
END;
$$ LANGUAGE plpgsql;

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
	curr_fund_source_bal RECORD;
	seqno                INT;     -- sequence num for credits applicable to a fund
	fund_credit          RECORD;  -- current row in temp t_fund_credit table
	fc                   RECORD;  -- used for loading t_fund_credit table
	sc                   RECORD;  -- used for loading t_fund_credit table
	--
	-- Used exclusively in the main loop:
	--
	deb                 RECORD;   -- current row from acq.fund_debit table
	curr_credit_bal     RECORD;   -- current row from temp t_credit table
	debit_balance       NUMERIC;  -- amount left to attribute for current debit
	conv_debit_balance  NUMERIC;  -- debit balance in currency of the fund
	attr_amount         NUMERIC;  -- amount being attributed, in currency of debit
	conv_attr_amount    NUMERIC;  -- amount being attributed, in currency of source
	conv_cred_balance   NUMERIC;  -- credit_balance in the currency of the fund
	conv_alloc_balance  NUMERIC;  -- allocated balance in the currency of the fund
	attrib_count        INT;      -- populates id of acq.debit_attribution
BEGIN
	--
	-- Load a temporary table.  For each combination of fund and funding source,
	-- load an entry with the total amount allocated to that fund by that source.
	-- This sum may reflect transfers as well as original allocations.  We will
	-- reduce this balance whenever we attribute debits to it.
	--
	CREATE TEMP TABLE t_fund_source_bal
	ON COMMIT DROP AS
		SELECT
			fund AS fund,
			funding_source AS source,
			sum( amount ) AS balance
		FROM
			acq.fund_allocation
		GROUP BY
			fund,
			funding_source
		HAVING
			sum( amount ) > 0;
	--
	CREATE INDEX t_fund_source_bal_idx
		ON t_fund_source_bal( fund, source );
	-------------------------------------------------------------------------------
	--
	-- Load another temporary table.  For each fund, load zero or more
	-- funding source credits from which that fund can get money.
	--
	CREATE TEMP TABLE t_fund_credit (
		fund        INT,
		seq         INT,
		credit      INT
	) ON COMMIT DROP;
	--
	FOR fc IN
		SELECT DISTINCT fund
		FROM acq.fund_allocation
		ORDER BY fund
	LOOP                  -- Loop over the funds
		seqno := 1;
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
			INSERT INTO t_fund_credit (
				fund,
				seq,
				credit
			) VALUES (
				fc.fund,
				seqno,
				sc.id
			);
			--RAISE NOTICE 'Fund % credit %', fc.fund, sc.id;
			seqno := seqno + 1;
		END LOOP;     -- Loop over credits for a given fund
	END LOOP;         -- Loop over funds
	--
	CREATE INDEX t_fund_credit_idx
		ON t_fund_credit( fund, seq );
	-------------------------------------------------------------------------------
	--
	-- Load yet another temporary table.  This one is a list of funding source
	-- credits, with their balances.  We shall reduce those balances as we
	-- attribute debits to them.
	--
	CREATE TEMP TABLE t_credit
	ON COMMIT DROP AS
        SELECT
            fsc.id AS credit,
            fsc.funding_source AS source,
            fsc.amount AS balance,
            fs.currency_type AS currency_type
        FROM
            acq.funding_source_credit AS fsc,
            acq.funding_source fs
        WHERE
            fsc.funding_source = fs.id
			AND fsc.amount > 0;
	--
	CREATE INDEX t_credit_idx
		ON t_credit( credit );
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
			fd.id
	LOOP
		--RAISE NOTICE 'Debit %, fund %', deb.id, deb.fund;
		--
		debit_balance := deb.amount;
		--
		-- Loop over the funding source credits that are eligible
		-- to pay for this debit
		--
		FOR fund_credit IN
			SELECT
				credit
			FROM
				t_fund_credit
			WHERE
				fund = deb.fund
			ORDER BY
				seq
		LOOP
			--RAISE NOTICE '   Examining credit %', fund_credit.credit;
			--
			-- Look up the balance for this credit.  If it's zero, then
			-- it's not useful, so treat it as if you didn't find it.
			-- (Actually there shouldn't be any zero balances in the table,
			-- but we check just to make sure.)
			--
			SELECT *
			INTO curr_credit_bal
			FROM t_credit
			WHERE
				credit = fund_credit.credit
				AND balance > 0;
			--
			IF curr_credit_bal IS NULL THEN
				--
				-- This credit is exhausted; try the next one.
				--
				CONTINUE;
			END IF;
			--
			--
			-- At this point we have an applicable credit with some money left.
			-- Now see if the relevant funding_source has any money left.
			--
			-- Look up the balance of the allocation for this combination of
			-- fund and source.  If you find such an entry, but it has a zero
			-- balance, then it's not useful, so treat it as unfound.
			-- (Actually there shouldn't be any zero balances in the table,
			-- but we check just to make sure.)
			--
			SELECT *
			INTO curr_fund_source_bal
			FROM t_fund_source_bal
			WHERE
				fund = deb.fund
				AND source = curr_credit_bal.source
				AND balance > 0;
			--
			IF curr_fund_source_bal IS NULL THEN
				--
				-- This fund/source doesn't exist or is already exhausted,
				-- so we can't use this credit.  Go on to the next one.
				--
				CONTINUE;
			END IF;
			--
			-- Convert the available balances to the currency of the fund
			--
			conv_alloc_balance := curr_fund_source_bal.balance * acq.exchange_ratio(
				curr_credit_bal.currency_type, deb.currency_type );
			conv_cred_balance := curr_credit_bal.balance * acq.exchange_ratio(
				curr_credit_bal.currency_type, deb.currency_type );
			--
			-- Determine how much we can attribute to this credit: the minimum
			-- of the debit amount, the fund/source balance, and the
			-- credit balance
			--
			--RAISE NOTICE '   deb bal %', debit_balance;
			--RAISE NOTICE '      source % balance %', curr_credit_bal.source, conv_alloc_balance;
			--RAISE NOTICE '      credit % balance %', curr_credit_bal.credit, conv_cred_balance;
			--
			conv_attr_amount := NULL;
			attr_amount := debit_balance;
			--
			IF attr_amount > conv_alloc_balance THEN
				attr_amount := conv_alloc_balance;
				conv_attr_amount := curr_fund_source_bal.balance;
			END IF;
			IF attr_amount > conv_cred_balance THEN
				attr_amount := conv_cred_balance;
				conv_attr_amount := curr_credit_bal.balance;
			END IF;
			--
			-- If we're attributing all of one of the balances, then that's how
			-- much we will deduct from the balances, and we already captured
			-- that amount above.  Otherwise we must convert the amount of the
			-- attribution from the currency of the fund back to the currency of
			-- the funding source.
			--
			IF conv_attr_amount IS NULL THEN
				conv_attr_amount := attr_amount * acq.exchange_ratio(
					deb.currency_type, curr_credit_bal.currency_type );
			END IF;
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
				curr_credit_bal.credit,
				conv_attr_amount
			);
			--
			-- Subtract the attributed amount from the various balances
			--
			debit_balance := debit_balance - attr_amount;
			curr_fund_source_bal.balance := curr_fund_source_bal.balance - conv_attr_amount;
			--
			IF curr_fund_source_bal.balance <= 0 THEN
				--
				-- This allocation is exhausted.  Delete it so
				-- that we don't waste time looking at it again.
				--
				DELETE FROM t_fund_source_bal
				WHERE
					fund = curr_fund_source_bal.fund
					AND source = curr_fund_source_bal.source;
			ELSE
				UPDATE t_fund_source_bal
				SET balance = balance - conv_attr_amount
				WHERE
					fund = curr_fund_source_bal.fund
					AND source = curr_fund_source_bal.source;
			END IF;
			--
			IF curr_credit_bal.balance <= 0 THEN
				--
				-- This funding source credit is exhausted.  Delete it
				-- so that we don't waste time looking at it again.
				--
				--DELETE FROM t_credit
				--WHERE
				--	credit = curr_credit_bal.credit;
				--
				DELETE FROM t_fund_credit
				WHERE
					credit = curr_credit_bal.credit;
			ELSE
				UPDATE t_credit
				SET balance = curr_credit_bal.balance
				WHERE
					credit = curr_credit_bal.credit;
			END IF;
			--
			-- Are we done with this debit yet?
			--
			IF debit_balance <= 0 THEN
				EXIT;       -- We've fully attributed this debit; stop looking at credits.
			END IF;
		END LOOP;       -- End loop over credits
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

CREATE OR REPLACE FUNCTION acq.propagate_funds_by_org_tree(
	old_year INTEGER,
	user_id INTEGER,
	org_unit_id INTEGER,
    include_desc BOOL DEFAULT TRUE
) RETURNS VOID AS $$
DECLARE
--
new_id      INT;
old_fund    RECORD;
org_found   BOOLEAN;
--
BEGIN
	--
	-- Sanity checks
	--
	IF old_year IS NULL THEN
		RAISE EXCEPTION 'Input year argument is NULL';
	ELSIF old_year NOT BETWEEN 2008 and 2200 THEN
		RAISE EXCEPTION 'Input year is out of range';
	END IF;
	--
	IF user_id IS NULL THEN
		RAISE EXCEPTION 'Input user id argument is NULL';
	END IF;
	--
	IF org_unit_id IS NULL THEN
		RAISE EXCEPTION 'Org unit id argument is NULL';
	ELSE
		SELECT TRUE INTO org_found
		FROM actor.org_unit
		WHERE id = org_unit_id;
		--
		IF org_found IS NULL THEN
			RAISE EXCEPTION 'Org unit id is invalid';
		END IF;
	END IF;
	--
	-- Loop over the applicable funds
	--
	FOR old_fund in SELECT * FROM acq.fund
	WHERE
		year = old_year
		AND propagate
		AND ( ( include_desc AND org IN ( SELECT id FROM actor.org_unit_descendants( org_unit_id ) ) )
                OR (NOT include_desc AND org = org_unit_id ) )
    
	LOOP
		BEGIN
			INSERT INTO acq.fund (
				org,
				name,
				year,
				currency_type,
				code,
				rollover,
				propagate,
				balance_warning_percent,
				balance_stop_percent
			) VALUES (
				old_fund.org,
				old_fund.name,
				old_year + 1,
				old_fund.currency_type,
				old_fund.code,
				old_fund.rollover,
				true,
				old_fund.balance_warning_percent,
				old_fund.balance_stop_percent
			)
			RETURNING id INTO new_id;
		EXCEPTION
			WHEN unique_violation THEN
				--RAISE NOTICE 'Fund % already propagated', old_fund.id;
				CONTINUE;
		END;
		--RAISE NOTICE 'Propagating fund % to fund %',
		--	old_fund.code, new_id;
	END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION acq.propagate_funds_by_org_unit( old_year INTEGER, user_id INTEGER, org_unit_id INTEGER ) RETURNS VOID AS $$
    SELECT acq.propagate_funds_by_org_tree( $1, $2, $3, FALSE );
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION acq.rollover_funds_by_org_tree(
	old_year INTEGER,
	user_id INTEGER,
	org_unit_id INTEGER,
    encumb_only BOOL DEFAULT FALSE,
    include_desc BOOL DEFAULT TRUE
) RETURNS VOID AS $$
DECLARE
--
new_fund    INT;
new_year    INT := old_year + 1;
org_found   BOOL;
perm_ous    BOOL;
xfer_amount NUMERIC := 0;
roll_fund   RECORD;
deb         RECORD;
detail      RECORD;
--
BEGIN
	--
	-- Sanity checks
	--
	IF old_year IS NULL THEN
		RAISE EXCEPTION 'Input year argument is NULL';
    ELSIF old_year NOT BETWEEN 2008 and 2200 THEN
        RAISE EXCEPTION 'Input year is out of range';
	END IF;
	--
	IF user_id IS NULL THEN
		RAISE EXCEPTION 'Input user id argument is NULL';
	END IF;
	--
	IF org_unit_id IS NULL THEN
		RAISE EXCEPTION 'Org unit id argument is NULL';
	ELSE
		--
		-- Validate the org unit
		--
		SELECT TRUE
		INTO org_found
		FROM actor.org_unit
		WHERE id = org_unit_id;
		--
		IF org_found IS NULL THEN
			RAISE EXCEPTION 'Org unit id % is invalid', org_unit_id;
		ELSIF encumb_only THEN
			SELECT INTO perm_ous value::BOOL FROM
			actor.org_unit_ancestor_setting(
				'acq.fund.allow_rollover_without_money', org_unit_id
			);
			IF NOT FOUND OR NOT perm_ous THEN
				RAISE EXCEPTION 'Encumbrance-only rollover not permitted at org %', org_unit_id;
			END IF;
		END IF;
	END IF;
	--
	-- Loop over the propagable funds to identify the details
	-- from the old fund plus the id of the new one, if it exists.
	--
	FOR roll_fund in
	SELECT
	    oldf.id AS old_fund,
	    oldf.org,
	    oldf.name,
	    oldf.currency_type,
	    oldf.code,
		oldf.rollover,
	    newf.id AS new_fund_id
	FROM
    	acq.fund AS oldf
    	LEFT JOIN acq.fund AS newf
        	ON ( oldf.code = newf.code )
	WHERE
 		    oldf.year = old_year
		AND oldf.propagate
        AND newf.year = new_year
		AND ( ( include_desc AND oldf.org IN ( SELECT id FROM actor.org_unit_descendants( org_unit_id ) ) )
                OR (NOT include_desc AND oldf.org = org_unit_id ) )
	LOOP
		--RAISE NOTICE 'Processing fund %', roll_fund.old_fund;
		--
		IF roll_fund.new_fund_id IS NULL THEN
			--
			-- The old fund hasn't been propagated yet.  Propagate it now.
			--
			INSERT INTO acq.fund (
				org,
				name,
				year,
				currency_type,
				code,
				rollover,
				propagate,
				balance_warning_percent,
				balance_stop_percent
			) VALUES (
				roll_fund.org,
				roll_fund.name,
				new_year,
				roll_fund.currency_type,
				roll_fund.code,
				true,
				true,
				roll_fund.balance_warning_percent,
				roll_fund.balance_stop_percent
			)
			RETURNING id INTO new_fund;
		ELSE
			new_fund = roll_fund.new_fund_id;
		END IF;
		--
		-- Determine the amount to transfer
		--
		SELECT amount
		INTO xfer_amount
		FROM acq.fund_spent_balance
		WHERE fund = roll_fund.old_fund;
		--
		IF xfer_amount <> 0 THEN
			IF NOT encumb_only AND roll_fund.rollover THEN
				--
				-- Transfer balance from old fund to new
				--
				--RAISE NOTICE 'Transferring % from fund % to %', xfer_amount, roll_fund.old_fund, new_fund;
				--
				PERFORM acq.transfer_fund(
					roll_fund.old_fund,
					xfer_amount,
					new_fund,
					xfer_amount,
					user_id,
					'Rollover'
				);
			ELSE
				--
				-- Transfer balance from old fund to the void
				--
				-- RAISE NOTICE 'Transferring % from fund % to the void', xfer_amount, roll_fund.old_fund;
				--
				PERFORM acq.transfer_fund(
					roll_fund.old_fund,
					xfer_amount,
					NULL,
					NULL,
					user_id,
					'Rollover into the void'
				);
			END IF;
		END IF;
		--
		IF roll_fund.rollover THEN
			--
			-- Move any lineitems from the old fund to the new one
			-- where the associated debit is an encumbrance.
			--
			-- Any other tables tying expenditure details to funds should
			-- receive similar treatment.  At this writing there are none.
			--
			UPDATE acq.lineitem_detail
			SET fund = new_fund
			WHERE
    			fund = roll_fund.old_fund -- this condition may be redundant
    			AND fund_debit in
    			(
        			SELECT id
        			FROM acq.fund_debit
        			WHERE
            			fund = roll_fund.old_fund
            			AND encumbrance
    			);
			--
			-- Move encumbrance debits from the old fund to the new fund
			--
			UPDATE acq.fund_debit
			SET fund = new_fund
			wHERE
				fund = roll_fund.old_fund
				AND encumbrance;
		END IF;
		--
		-- Mark old fund as inactive, now that we've closed it
		--
		UPDATE acq.fund
		SET active = FALSE
		WHERE id = roll_fund.old_fund;
	END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION acq.rollover_funds_by_org_unit( old_year INTEGER, user_id INTEGER, org_unit_id INTEGER, encumb_only BOOL DEFAULT FALSE ) RETURNS VOID AS $$
    SELECT acq.rollover_funds_by_org_tree( $1, $2, $3, $4, FALSE );
$$ LANGUAGE SQL;

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
            sum(COALESCE(fund_debit.amount, 0::numeric)) AS amount
    FROM acq.fund fund
        LEFT JOIN acq.fund_debit fund_debit ON fund.id = fund_debit.fund
    GROUP BY fund.id;

CREATE OR REPLACE VIEW acq.fund_encumbrance_total AS
    SELECT 
        fund.id AS fund, 
        sum(COALESCE(fund_debit.amount, 0::numeric)) AS amount 
    FROM acq.fund fund
        LEFT JOIN acq.fund_debit fund_debit ON fund.id = fund_debit.fund 
    WHERE fund_debit.encumbrance GROUP BY fund.id;

CREATE OR REPLACE VIEW acq.fund_spent_total AS
    SELECT  fund.id AS fund, 
            sum(COALESCE(fund_debit.amount, 0::numeric)) AS amount 
    FROM acq.fund fund
        LEFT JOIN acq.fund_debit fund_debit ON fund.id = fund_debit.fund 
    WHERE NOT fund_debit.encumbrance 
    GROUP BY fund.id;

CREATE OR REPLACE VIEW acq.fund_combined_balance AS
    SELECT  c.fund, 
            c.amount - COALESCE(d.amount, 0.0) AS amount
    FROM acq.fund_allocation_total c
    LEFT JOIN acq.fund_debit_total d USING (fund);

CREATE OR REPLACE VIEW acq.fund_spent_balance AS
    SELECT  c.fund,
            c.amount - COALESCE(d.amount,0.0) AS amount
      FROM  acq.fund_allocation_total c
            LEFT JOIN acq.fund_spent_total d USING (fund);

-- For each fund: the total allocation from all sources, in the
-- currency of the fund (or 0 if there are no allocations)

CREATE VIEW acq.all_fund_allocation_total AS
SELECT
    f.id AS fund,
    COALESCE( SUM( a.amount * acq.exchange_ratio(
        s.currency_type, f.currency_type))::numeric(100,2), 0 )
    AS amount
FROM
    acq.fund f
        LEFT JOIN acq.fund_allocation a
            ON a.fund = f.id
        LEFT JOIN acq.funding_source s
            ON a.funding_source = s.id
GROUP BY
    f.id;

-- For every fund: the total encumbrances (or 0 if none),
-- in the currency of the fund.

CREATE VIEW acq.all_fund_encumbrance_total AS
SELECT
	f.id AS fund,
	COALESCE( encumb.amount, 0 ) AS amount
FROM
	acq.fund AS f
		LEFT JOIN (
			SELECT
				fund,
				sum( amount ) AS amount
			FROM
				acq.fund_debit
			WHERE
				encumbrance
			GROUP BY fund
		) AS encumb
			ON f.id = encumb.fund;

-- For every fund: the total spent (or 0 if none),
-- in the currency of the fund.

CREATE VIEW acq.all_fund_spent_total AS
SELECT
    f.id AS fund,
    COALESCE( spent.amount, 0 ) AS amount
FROM
    acq.fund AS f
        LEFT JOIN (
            SELECT
                fund,
                sum( amount ) AS amount
            FROM
                acq.fund_debit
            WHERE
                NOT encumbrance
            GROUP BY fund
        ) AS spent
            ON f.id = spent.fund;

-- For each fund: the amount not yet spent, in the currency
-- of the fund.  May include encumbrances.

CREATE VIEW acq.all_fund_spent_balance AS
SELECT
	c.fund,
	c.amount - d.amount AS amount
FROM acq.all_fund_allocation_total c
    LEFT JOIN acq.all_fund_spent_total d USING (fund);

-- For each fund: the amount neither spent nor encumbered,
-- in the currency of the fund

CREATE VIEW acq.all_fund_combined_balance AS
SELECT
     a.fund,
     a.amount - COALESCE( c.amount, 0 ) AS amount
FROM
     acq.all_fund_allocation_total a
        LEFT OUTER JOIN (
            SELECT
                fund,
                SUM( amount ) AS amount
            FROM
                acq.fund_debit
            GROUP BY
                fund
        ) AS c USING ( fund );

CREATE TABLE acq.claim_type (
	id             SERIAL           PRIMARY KEY,
	org_unit       INT              NOT NULL REFERENCES actor.org_unit(id)
	                                         DEFERRABLE INITIALLY DEFERRED,
	code           TEXT             NOT NULL,
	description    TEXT             NOT NULL,
	CONSTRAINT claim_type_once_per_org UNIQUE ( org_unit, code )
);

CREATE TABLE acq.claim (
	id             SERIAL           PRIMARY KEY,
	type           INT              NOT NULL REFERENCES acq.claim_type
	                                         DEFERRABLE INITIALLY DEFERRED,
	lineitem_detail BIGINT          NOT NULL REFERENCES acq.lineitem_detail
	                                         DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX claim_lid_idx ON acq.claim( lineitem_detail );

CREATE TABLE acq.claim_event (
	id             BIGSERIAL        PRIMARY KEY,
	type           INT              NOT NULL REFERENCES acq.claim_event_type
	                                         DEFERRABLE INITIALLY DEFERRED,
	claim          SERIAL           NOT NULL REFERENCES acq.claim
	                                         DEFERRABLE INITIALLY DEFERRED,
	event_date     TIMESTAMPTZ      NOT NULL DEFAULT now(),
	creator        INT              NOT NULL REFERENCES actor.usr
	                                         DEFERRABLE INITIALLY DEFERRED,
	note           TEXT
);

CREATE INDEX claim_event_claim_date_idx ON acq.claim_event( claim, event_date );

-- And the serials version of claiming
CREATE TABLE acq.serial_claim (
    id     SERIAL           PRIMARY KEY,
    type   INT              NOT NULL REFERENCES acq.claim_type
                                     DEFERRABLE INITIALLY DEFERRED,
    item    BIGINT          NOT NULL REFERENCES serial.item
                                     DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX serial_claim_lid_idx ON acq.serial_claim( item );

CREATE TABLE acq.serial_claim_event (
    id             BIGSERIAL        PRIMARY KEY,
    type           INT              NOT NULL REFERENCES acq.claim_event_type
                                             DEFERRABLE INITIALLY DEFERRED,
    claim          SERIAL           NOT NULL REFERENCES acq.serial_claim
                                             DEFERRABLE INITIALLY DEFERRED,
    event_date     TIMESTAMPTZ      NOT NULL DEFAULT now(),
    creator        INT              NOT NULL REFERENCES actor.usr
                                             DEFERRABLE INITIALLY DEFERRED,
    note           TEXT
);

CREATE INDEX serial_claim_event_claim_date_idx ON acq.serial_claim_event( claim, event_date );

COMMIT;
