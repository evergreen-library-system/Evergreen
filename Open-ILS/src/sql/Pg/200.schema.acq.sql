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
    from_currency   TEXT    NOT NULL REFERENCES acq.currency_type (code),
    to_currency     TEXT    NOT NULL REFERENCES acq.currency_type (code),
    ratio           NUMERIC NOT NULL,
    CONSTRAINT exchange_rate_from_to_once UNIQUE (from_currency,to_currency)
);

INSERT INTO acq.exchange_rate (from_currency,to_currency,ratio) VALUES ('USD','CAN',1.2);
INSERT INTO acq.exchange_rate (from_currency,to_currency,ratio) VALUES ('USD','EUR',0.5);

CREATE TABLE acq.provider (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL,
	owner		INT	NOT NULL REFERENCES actor.org_unit (id),
	currency_type	TEXT	NOT NULL REFERENCES acq.currency_type (code),
	code		TEXT	UNIQUE,
	CONSTRAINT provider_name_once_per_owner UNIQUE (name,owner)
);

CREATE TABLE acq.funding_source (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL,
	owner		INT	NOT NULL REFERENCES actor.org_unit (id),
	currency_type	TEXT	NOT NULL REFERENCES acq.currency_type (code),
	code		TEXT	UNIQUE,
	CONSTRAINT funding_source_name_once_per_owner UNIQUE (name,owner)
);

CREATE TABLE acq.funding_source_credit (
	id	SERIAL	PRIMARY KEY,
	funding_source    INT     NOT NULL REFERENCES acq.funding_source (id),
	amount	NUMERIC	NOT NULL,
	note	TEXT
);

CREATE TABLE acq.fund (
    id              SERIAL  PRIMARY KEY,
    org             INT     NOT NULL REFERENCES actor.org_unit (id) ON UPDATE CASCADE ON DELETE CASCADE,
    name            TEXT    NOT NULL,
    year            INT     NOT NULL DEFAULT EXTRACT( YEAR FROM NOW() ),
    currency_type   TEXT    NOT NULL REFERENCES acq.currency_type (code),
    code            TEXT    UNIQUE,
    CONSTRAINT name_once_per_org_year UNIQUE (org,name,year)
);

CREATE TABLE acq.fund_debit (
	id			SERIAL	PRIMARY KEY,
	fund			INT     NOT NULL REFERENCES acq.fund (id),
	origin_amount		NUMERIC	NOT NULL,  -- pre-exchange-rate amount
	origin_currency_type	TEXT	NOT NULL REFERENCES acq.currency_type (code),
	amount			NUMERIC	NOT NULL,
	encumbrance		BOOL	NOT NULL DEFAULT TRUE,
	debit_type		TEXT	NOT NULL,
	xfer_destination	INT	REFERENCES acq.fund (id)
);

CREATE TABLE acq.fund_allocation (
    id          SERIAL  PRIMARY KEY,
    funding_source        INT     NOT NULL REFERENCES acq.funding_source (id) ON UPDATE CASCADE ON DELETE CASCADE,
    fund        INT     NOT NULL REFERENCES acq.fund (id) ON UPDATE CASCADE ON DELETE CASCADE,
    amount      NUMERIC,
    percent     NUMERIC CHECK (percent IS NULL OR percent BETWEEN 0.0 AND 100.0),
    allocator   INT NOT NULL REFERENCES actor.usr (id),
    note        TEXT,
    CONSTRAINT allocation_amount_or_percent CHECK ((percent IS NULL AND amount IS NOT NULL) OR (percent IS NOT NULL AND amount IS NULL))
);


CREATE TABLE acq.picklist (
	id		SERIAL				PRIMARY KEY,
	owner		INT				NOT NULL REFERENCES actor.usr (id),
	org_unit	INT				NOT NULL REFERENCES actor.org_unit (id),
	name		TEXT				NOT NULL,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	edit_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	CONSTRAINT name_once_per_owner UNIQUE (name,owner)
);

CREATE TABLE acq.purchase_order (
	id		SERIAL				PRIMARY KEY,
	owner		INT				NOT NULL REFERENCES actor.usr (id),
	ordering_agency		INT				NOT NULL REFERENCES actor.org_unit (id),
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	edit_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	provider	INT				NOT NULL REFERENCES acq.provider (id),
	state		TEXT				NOT NULL DEFAULT 'new'
);
CREATE INDEX po_owner_idx ON acq.purchase_order (owner);
CREATE INDEX po_provider_idx ON acq.purchase_order (provider);
CREATE INDEX po_state_idx ON acq.purchase_order (state);

CREATE TABLE acq.po_note (
	id		SERIAL				PRIMARY KEY,
	purchase_order	INT				NOT NULL REFERENCES acq.purchase_order (id),
	creator		INT				NOT NULL REFERENCES actor.usr (id),
	editor		INT				NOT NULL REFERENCES actor.usr (id),
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	edit_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	value		TEXT				NOT NULL
);
CREATE INDEX po_note_po_idx ON acq.po_note (purchase_order);

CREATE TABLE acq.lineitem (
	id                  BIGSERIAL                   PRIMARY KEY,
	selector            INT                         NOT NULL REFERENCES actor.org_unit (id),
	provider            INT                         REFERENCES acq.provider (id),
	purchase_order      INT                         REFERENCES acq.purchase_order (id),
	picklist            INT                         REFERENCES acq.picklist (id),
	expected_recv_time  TIMESTAMP WITH TIME ZONE,
	create_time         TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
	edit_time           TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
	marc                TEXT                        NOT NULL,
	eg_bib_id           INT                         REFERENCES biblio.record_entry (id),
	source_label        TEXT,
	item_count          INT                         NOT NULL DEFAULT 0,
	state               TEXT                        NOT NULL DEFAULT 'new',
    CONSTRAINT picklist_or_po CHECK (picklist IS NOT NULL OR purchase_order IS NOT NULL)
);
CREATE INDEX li_po_idx ON acq.lineitem (purchase_order);
CREATE INDEX li_pl_idx ON acq.lineitem (picklist);

CREATE TABLE acq.lineitem_note (
	id		SERIAL				PRIMARY KEY,
	lineitem	INT				NOT NULL REFERENCES acq.lineitem (id),
	creator		INT				NOT NULL REFERENCES actor.usr (id),
	editor		INT				NOT NULL REFERENCES actor.usr (id),
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	edit_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	value		TEXT				NOT NULL
);
CREATE INDEX li_note_li_idx ON acq.lineitem_note (lineitem);

CREATE TABLE acq.lineitem_detail (
	id		BIGSERIAL			PRIMARY KEY,
	lineitem	INT				NOT NULL REFERENCES acq.lineitem (id),
	fund		INT				REFERENCES acq.fund (id),
	fund_debit	INT				REFERENCES acq.fund_debit (id),
	eg_copy_id	BIGINT			REFERENCES asset.copy (id) ON DELETE SET NULL,
	barcode		TEXT,
	cn_label	TEXT,
    owning_lib  INT             REFERENCES actor.org_unit (id) ON DELETE SET NULL,
    location    INT             REFERENCES asset.copy_location (id) ON DELETE SET NULL,
	recv_time	TIMESTAMP WITH TIME ZONE
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
	provider	INT	NOT NULL REFERENCES acq.provider (id)
) INHERITS (acq.lineitem_attr_definition);

CREATE TABLE acq.lineitem_generated_attr_definition (
	id		BIGINT	PRIMARY KEY DEFAULT NEXTVAL('acq.lineitem_attr_definition_id_seq'),
	xpath		TEXT		NOT NULL
) INHERITS (acq.lineitem_attr_definition);

CREATE TABLE acq.lineitem_usr_attr_definition (
	id		BIGINT	PRIMARY KEY DEFAULT NEXTVAL('acq.lineitem_attr_definition_id_seq'),
	usr		INT	NOT NULL REFERENCES actor.usr (id)
) INHERITS (acq.lineitem_attr_definition);

CREATE TABLE acq.lineitem_local_attr_definition (
	id		BIGINT	PRIMARY KEY DEFAULT NEXTVAL('acq.lineitem_attr_definition_id_seq')
) INHERITS (acq.lineitem_attr_definition);

CREATE TABLE acq.lineitem_attr (
	id		BIGSERIAL	PRIMARY KEY,
	definition	BIGINT		NOT NULL,
	lineitem	BIGINT		NOT NULL REFERENCES acq.lineitem (id),
	attr_type	TEXT		NOT NULL,
	attr_name	TEXT		NOT NULL,
	attr_value	TEXT		NOT NULL
);

CREATE INDEX li_attr_li_idx ON acq.lineitem_attr (lineitem);


-- Seed data


INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath ) VALUES ('title','Title of work','//*[@tag="245"]/*[contains("abcmnopr",@code)]');
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath ) VALUES ('author','Author of work','//*[@tag="100" or @tag="110" or @tag="113"]/*[contains("ad",@code)]');
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath ) VALUES ('language','Lanuage of work','//*[@tag="240"]/*[@code="l"][1]');
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath ) VALUES ('pagination','Pagination','//*[@tag="300"]/*[@code="a"][1]');
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath, remove ) VALUES ('isbn','ISBN','//*[@tag="020"]/*[@code="a"]', $r$(?:-|\s.+$)$r$);
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath, remove ) VALUES ('issn','ISSN','//*[@tag="022"]/*[@code="a"]', $r$(?:-|\s.+$)$r$);
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath ) VALUES ('price','Price','//*[@tag="020" or @tag="022"]/*[@code="c"][1]');
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath ) VALUES ('identifier','Identifier','//*[@tag="001"]');
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath ) VALUES ('publisher','Publisher','//*[@tag="260"]/*[@code="b"][1]');
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath ) VALUES ('pubdate','Publication Date','//*[@tag="260"]/*[@code="c"][1]');
INSERT INTO acq.lineitem_marc_attr_definition ( code, description, xpath ) VALUES ('edition','Edition','//*[@tag="250"]/*[@code="a"][1]');


-- Functions


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




