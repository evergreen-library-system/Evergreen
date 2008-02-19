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
	CONSTRAINT provider_name_once_per_owner UNIQUE (name,owner)
);

CREATE TABLE acq.funding_source (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL,
	owner		INT	NOT NULL REFERENCES actor.org_unit (id),
	currency_type	TEXT	NOT NULL REFERENCES acq.currency_type (code),
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
    CONSTRAINT name_once_per_org_year UNIQUE (org,name,year)
);

CREATE TABLE acq.fund_debit (
	id			SERIAL	PRIMARY KEY,
	fund			INT     NOT NULL REFERENCES acq.fund (id),
	origin_amount		NUMERIC	NOT NULL,  -- pre-exchange-rate amount
	origin_currency_type	TEXT	NOT NULL REFERENCES acq.currency_type (code),
	amount			NUMERIC	NOT NULL,
	encumberance		BOOL	NOT NULL DEFAULT TRUE,
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
	name		TEXT				NOT NULL,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	edit_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	CONSTRAINT name_once_per_owner UNIQUE (name,owner)
);

CREATE TABLE acq.purchase_order (
	id		SERIAL				PRIMARY KEY,
	owner		INT				NOT NULL REFERENCES actor.usr (id),
	default_fund	INT				REFERENCES acq.fund (id),
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	edit_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	provider	INT				NOT NULL REFERENCES acq.provider (id),
	state		TEXT				NOT NULL DEFAULT 'new',
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

CREATE TABLE acq.picklist_entry (
	id		BIGSERIAL			PRIMARY KEY,
	picklist	INT				NOT NULL REFERENCES acq.picklist (id) ON DELETE CASCADE,
	provider	INT				REFERENCES acq.provider (id),
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	edit_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	marc		TEXT				NOT NULL,
	eg_bib_id	INT				REFERENCES biblio.record_entry (id),
	source_label	TEXT,
	po_lineitem	INT				REFERENCES acq.po_lineitem (id)
);

CREATE TABLE acq.po_lineitem (
	id			BIGSERIAL			PRIMARY KEY,
	purchase_order		INT				NOT NULL REFERENCES acq.purchase_order (id),
	fund			INT				REFERENCES acq.fund (id),
	expected_recv_time	TIMESTAMP WITH TIME ZONE,
	create_time		TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	edit_time		TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	marc			TEXT				NOT NULL,
	eg_bib_id		INT				REFERENCES biblio.record_entry (id),
	list_price		NUMERIC,
	item_count		INT				NOT NULL DEFAULT 0
);
CREATE INDEX po_li_po_idx ON acq.po_lineitem (purchase_order);

CREATE TABLE acq.po_li_note (
	id		SERIAL				PRIMARY KEY,
	po_lineitem	INT				NOT NULL REFERENCES acq.po_lineitem (id),
	creator		INT				NOT NULL REFERENCES actor.usr (id),
	editor		INT				NOT NULL REFERENCES actor.usr (id),
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	edit_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	value		TEXT				NOT NULL
);
CREATE INDEX po_li_note_li_idx ON acq.po_li_note (po_lineitem);

CREATE TABLE acq.po_li_detail (
	id		BIGSERIAL			PRIMARY KEY,
	po_lineitem	INT				NOT NULL REFERENCES acq.po_lineitem (id),
	fund_debit	INT				REFERENCES acq.fund_debit (id),
	eg_copy_id	BIGINT				REFERENCES asset.copy (id),
	barcode		TEXT,
	cn_label	TEXT,
	recv_time	TIMESTAMP WITH TIME ZONE
);

CREATE INDEX po_li_detail_li_idx ON acq.po_li_detail (po_lineitem);

CREATE TABLE acq.picklist_entry_attr (
	id		BIGSERIAL	PRIMARY KEY,
	picklist_entry	BIGINT		NOT NULL REFERENCES acq.picklist_entry (id) ON DELETE CASCADE,
	attr_type	TEXT		NOT NULL,
	attr_name	TEXT		NOT NULL,
	attr_value	TEXT		NOT NULL
);

CREATE TABLE acq.po_li_attr (
	id		BIGSERIAL	PRIMARY KEY,
	po_lineitem	BIGINT		NOT NULL REFERENCES acq.po_lineitem (id),
	attr_type	TEXT		NOT NULL,
	attr_name	TEXT		NOT NULL,
	attr_value	TEXT		NOT NULL
);

CREATE INDEX po_li_attr_li_idx ON acq.po_li_attr (po_lineitem);

CREATE TABLE acq.picklist_attr_definition (
	id		BIGSERIAL	PRIMARY KEY,
	code		TEXT		NOT NULL,
	description	TEXT		NOT NULL,
	xpath		TEXT		NOT NULL
);

CREATE TABLE acq.picklist_marc_attr_definition (
	id		BIGINT	PRIMARY KEY DEFAULT NEXTVAL('acq.picklist_attr_definition_id_seq')
) INHERITS (acq.picklist_attr_definition);

CREATE TABLE acq.picklist_provider_attr_definition (
	id		BIGINT	PRIMARY KEY DEFAULT NEXTVAL('acq.picklist_attr_definition_id_seq'),
	provider	INT	NOT NULL REFERENCES acq.provider (id)
) INHERITS (acq.picklist_attr_definition);

CREATE TABLE acq.picklist_generated_attr_definition (
	id		BIGINT	PRIMARY KEY DEFAULT NEXTVAL('acq.picklist_attr_definition_id_seq')
) INHERITS (acq.picklist_attr_definition);

CREATE TABLE acq.picklist_usr_attr_definition (
	id		BIGINT	PRIMARY KEY DEFAULT NEXTVAL('acq.picklist_attr_definition_id_seq'),
	usr		INT	NOT NULL REFERENCES actor.usr (id)
) INHERITS (acq.picklist_attr_definition);


-- Seed data


INSERT INTO acq.picklist_marc_attr_definition ( code, description, xpath ) VALUES ('title','Title of work','//*[@tag="245"]/*[contains("abcmnopr",@code)]');
INSERT INTO acq.picklist_marc_attr_definition ( code, description, xpath ) VALUES ('author','Author of work','//*[@tag="100" or @tag="110" or @tag="113"]/*[contains("ad",@code)]');
INSERT INTO acq.picklist_marc_attr_definition ( code, description, xpath ) VALUES ('language','Lanuage of work','//*[@tag="240"]/*[@code="l"][1]');
INSERT INTO acq.picklist_marc_attr_definition ( code, description, xpath ) VALUES ('pagination','Pagination','//*[@tag="300"]/*[@code="a"][1]');
INSERT INTO acq.picklist_marc_attr_definition ( code, description, xpath ) VALUES ('isbn','ISBN','//*[@tag="020"]/*[@code="a"]');
INSERT INTO acq.picklist_marc_attr_definition ( code, description, xpath ) VALUES ('issn','ISSN','//*[@tag="022"]/*[@code="a"]');
INSERT INTO acq.picklist_marc_attr_definition ( code, description, xpath ) VALUES ('price','Price','//*[@tag="020" or @tag="022"]/*[@code="c"][1]');
INSERT INTO acq.picklist_marc_attr_definition ( code, description, xpath ) VALUES ('identifier','Identifier','//*[@tag="001"]');
INSERT INTO acq.picklist_marc_attr_definition ( code, description, xpath ) VALUES ('publisher','Publisher','//*[@tag="260"]/*[@code="b"][1]');
INSERT INTO acq.picklist_marc_attr_definition ( code, description, xpath ) VALUES ('pubdate','Publication Date','//*[@tag="260"]/*[@code="c"][1]');
INSERT INTO acq.picklist_marc_attr_definition ( code, description, xpath ) VALUES ('edition','Edition','//*[@tag="250"]/*[@code="a"][1]');


-- Functions


CREATE OR REPLACE FUNCTION public.extract_marc_field ( TEXT, BIGINT, TEXT ) RETURNS TEXT AS $$
	SELECT array_to_string( array_accum( output ),' ' ) FROM xpath_table('id', 'marc', $1, $3, 'id='||$2)x(id INT, output TEXT);
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION public.extract_acq_marc_field ( BIGINT, TEXT ) RETURNS TEXT AS $$
	SELECT public.extract_marc_field('acq.picklist_entry', $1, $2);
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION public.extract_bib_marc_field ( BIGINT, TEXT ) RETURNS TEXT AS $$
	SELECT public.extract_marc_field('biblio.record_entry', $1, $2);
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION public.extract_authority_marc_field ( BIGINT, TEXT ) RETURNS TEXT AS $$
	SELECT public.extract_marc_field('authority.record_entry', $1, $2);
$$ LANGUAGE SQL;

-- For example:
-- INSERT INTO acq.picklist_provider_attr_definition ( provider, code, description, xpath ) VALUES (1,'price','Price','//*[@tag="020" or @tag="022"]/*[@code="a"][1]');

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
	value	TEXT;
	atype	TEXT;
	prov	INT;
	adef	RECORD;
BEGIN
	FOR adef IN SELECT *,tableoid FROM acq.picklist_attr_definition LOOP

		SELECT relname::TEXT INTO atype FROM pg_class WHERE oid = adef.tableoid;
		IF (atype = 'picklist_provider_attr_definition') THEN
			SELECT provider INTO prov FROM acq.picklist_provider_attr_definition WHERE id = adef.id;
			CONTINUE WHEN NEW.provider IS NULL OR prov <> NEW.provider;
		END IF;

		SELECT extract_acq_marc_field(id, adef.xpath) INTO value FROM acq.picklist_entry WHERE id = NEW.id;
		IF (value IS NOT NULL AND value <> '') THEN
			INSERT INTO acq.picklist_entry_attr (picklist_entry, attr_type, attr_name, attr_value) VALUES (NEW.id, atype, adef.code, value);
		END IF;
	END LOOP;

	RETURN NULL;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION public.cleanup_acq_marc ( ) RETURNS TRIGGER AS $$
BEGIN
	DELETE FROM acq.picklist_entry_attr WHERE picklist_entry = OLD.id;
	IF TG_OP = 'UPDATE' THEN
		RETURN NEW;
	ELSE
		RETURN OLD;
	END IF;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER cleanup_picklist_entry_trigger
	BEFORE UPDATE OR DELETE ON acq.picklist_entry 
	FOR EACH ROW EXECUTE PROCEDURE public.cleanup_acq_marc();

CREATE TRIGGER ingest_picklist_entry_trigger
	AFTER INSERT OR UPDATE ON acq.picklist_entry 
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
            encumberance,
            SUM(amount) AS amount
      FROM  acq.fund_debit 
      GROUP BY 1,2;

CREATE OR REPLACE VIEW acq.fund_encumberance_total AS
    SELECT  fund,
            SUM(amount) AS amount
      FROM  acq.fund_debit_total
      WHERE encumberance IS TRUE
      GROUP BY 1;

CREATE OR REPLACE VIEW acq.fund_spent_total AS
    SELECT  fund,
            SUM(amount) AS amount
      FROM  acq.fund_debit_total
      WHERE encumberance IS FALSE
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




