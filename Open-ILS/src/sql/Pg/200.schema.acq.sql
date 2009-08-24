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
    code                TEXT    UNIQUE,
    holding_tag         TEXT,
    CONSTRAINT provider_name_once_per_owner UNIQUE (name,owner)
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
	id	SERIAL	PRIMARY KEY,
	funding_source    INT     NOT NULL REFERENCES acq.funding_source (id) DEFERRABLE INITIALLY DEFERRED,
	amount	NUMERIC	NOT NULL,
	note	TEXT
);

CREATE TABLE acq.fund (
    id              SERIAL  PRIMARY KEY,
    org             INT     NOT NULL REFERENCES actor.org_unit (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    name            TEXT    NOT NULL,
    year            INT     NOT NULL DEFAULT EXTRACT( YEAR FROM NOW() ),
    currency_type   TEXT    NOT NULL REFERENCES acq.currency_type (code) DEFERRABLE INITIALLY DEFERRED,
    code            TEXT,
    CONSTRAINT name_once_per_org_year UNIQUE (org,name,year),
    CONSTRAINT code_once_per_org_year UNIQUE (org, code, year)
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
    amount      NUMERIC,
    percent     NUMERIC CHECK (percent IS NULL OR percent BETWEEN 0.0 AND 100.0),
    allocator   INT NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    note        TEXT,
	create_time TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT allocation_amount_or_percent CHECK ((percent IS NULL AND amount IS NOT NULL) OR (percent IS NOT NULL AND amount IS NULL))
);


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

-- Functions

CREATE TYPE acq.flat_lineitem_holding_subfield AS (lineitem int, holding int, subfield text, data text);
CREATE OR REPLACE FUNCTION acq.extract_holding_attr_table (lineitem int, tag text) RETURNS SETOF acq.flat_lineitem_holding_subfield AS $$
DECLARE
    counter INT;
    lida    acq.flat_lineitem_holding_subfield%ROWTYPE;
BEGIN

    SELECT  COUNT(*) INTO counter
      FROM  xpath_table(
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
                          FROM  xpath_table(
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

CREATE OR REPLACE VIEW acq.funding_source_credit_total AS
    SELECT  funding_source,
            SUM(amount) AS amount
      FROM  acq.funding_source_credit
      GROUP BY 1;

CREATE OR REPLACE VIEW acq.funding_source_allocation_total AS
    SELECT  funding_source,
            SUM(amount)::NUMERIC(100,2) AS amount
      FROM (
            SELECT  funding_source,
                    SUM(a.amount)::NUMERIC(100,2) AS amount
              FROM  acq.fund_allocation a
              WHERE a.percent IS NULL
              GROUP BY 1
                            UNION ALL
            SELECT  funding_source,
                    SUM( (SELECT SUM(amount) FROM acq.funding_source_credit c WHERE c.funding_source = a.funding_source) * (a.percent/100.0) )::NUMERIC(100,2) AS amount
              FROM  acq.fund_allocation a
              WHERE a.amount IS NULL
              GROUP BY 1
        ) x
      GROUP BY 1;

CREATE OR REPLACE VIEW acq.funding_source_balance AS
    SELECT  COALESCE(c.funding_source, a.funding_source) AS funding_source,
            SUM(COALESCE(c.amount,0.0) - COALESCE(a.amount,0.0))::NUMERIC(100,2) AS amount
      FROM  acq.funding_source_credit_total c
            FULL JOIN acq.funding_source_allocation_total a USING (funding_source)
      GROUP BY 1;

CREATE OR REPLACE VIEW acq.fund_allocation_total AS
    SELECT  fund,
            SUM(amount)::NUMERIC(100,2) AS amount
      FROM (
            SELECT  fund,
                    SUM(a.amount * acq.exchange_ratio(s.currency_type, f.currency_type))::NUMERIC(100,2) AS amount
              FROM  acq.fund_allocation a
                    JOIN acq.fund f ON (a.fund = f.id)
                    JOIN acq.funding_source s ON (a.funding_source = s.id)
              WHERE a.percent IS NULL
              GROUP BY 1
                            UNION ALL
            SELECT  fund,
                    SUM( (SELECT SUM(amount) FROM acq.funding_source_credit c WHERE c.funding_source = a.funding_source) * acq.exchange_ratio(s.currency_type, f.currency_type) * (a.percent/100.0) )::NUMERIC(100,2) AS amount
              FROM  acq.fund_allocation a
                    JOIN acq.fund f ON (a.fund = f.id)
                    JOIN acq.funding_source s ON (a.funding_source = s.id)
              WHERE a.amount IS NULL
              GROUP BY 1
        ) x
      GROUP BY 1;

CREATE OR REPLACE VIEW acq.fund_debit_total AS
    SELECT  id AS fund,
            encumbrance,
            SUM(amount) AS amount
      FROM  acq.fund_debit 
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




