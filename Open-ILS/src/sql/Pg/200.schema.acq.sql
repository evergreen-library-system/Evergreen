DROP SCHEMA acq CASCADE;

BEGIN;

CREATE SCHEMA acq;

CREATE TABLE acq.currency_type (
	code	TEXT PRIMARY KEY,
	label	TEXT
);

-- Use the ISO 4217 abbreviations for currency codes
INSERT INTO acq.currency_type (code, label) VALUES ('USD','US Dollars');
INSERT INTO acq.currency_type (code, label) VALUES ('CAN','Canadian Dollars');
INSERT INTO acq.currency_type (code, label) VALUES ('EUR','Euros');

CREATE TABLE acq.exchange_rate (
	id		SERIAL	PRIMARY KEY,
	from_currency	TEXT	NOT NULL REFERENCES acq.currency_type (code),
	to_currency	TEXT	NOT NULL REFERENCES acq.currency_type (code),
	ratio		NUMERIC	NOT NULL,
	CONSTRAINT exchange_rate_from_to_once UNIQUE (from_currency,to_currency)
);

INSERT INTO acq.exchange_rate (from_currency,to_currency,ratio) VALUES ('USD','CAD',1.2);
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

CREATE TABLE acq.picklist (
	id		SERIAL				PRIMARY KEY,
	owner		INT				NOT NULL REFERENCES actor.usr (id),
	name		TEXT				NOT NULL,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	edit_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	CONSTRAINT name_once_per_owner UNIQUE (name,owner)
);

CREATE TABLE acq.picklist_entry (
	id		BIGSERIAL			PRIMARY KEY,
	picklist	INT				NOT NULL REFERENCES acq.picklist (id) ON DELETE CASCADE,
	provider	INT				REFERENCES acq.provider (id),
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	edit_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	marc		TEXT				NOT NULL,
	eg_bib_id	INT,
	source_label	TEXT
);

CREATE TABLE acq.picklist_entry_attr (
	id		BIGSERIAL	PRIMARY KEY,
	picklist_entry	BIGINT		NOT NULL REFERENCES acq.picklist_entry (id) ON DELETE CASCADE,
	attr_type	TEXT		NOT NULL,
	attr_name	TEXT		NOT NULL,
	attr_value	TEXT		NOT NULL
);

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

CREATE TABLE acq.fund (
    id      SERIAL  PRIMARY KEY,
    org     INT     NOT NULL REFERENCES actor.org_unit (id) ON UPDATE CASCADE ON DELETE CASCADE,
    name    TEXT    NOT NULL,
    year    INT     NOT NULL DEFAULT EXTRACT( YEAR FROM NOW() ),
    CONSTRAINT name_once_per_org_year UNIQUE (org,name,year)
);

CREATE TABLE acq.fund_debit (
	id			SERIAL	PRIMARY KEY,
	fund			INT     NOT NULL REFERENCES acq.fund (id),
	origin_amount		NUMERIC	NOT NULL,  -- pre-exchange-rate amount
	origin_currency_type	TEXT	NOT NULL REFERENCES acq.currency_type (code),
	amount			NUMERIC	NOT NULL,
	encumberance		BOOL	NOT NULL DEFAULT TRUE
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

COMMIT;




