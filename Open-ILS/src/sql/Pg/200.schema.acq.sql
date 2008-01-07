DROP SCHEMA acq CASCADE;

BEGIN;

CREATE SCHEMA acq;

CREATE TABLE acq.currency_type (
	code	TEXT PRIMARY KEY,
	label	TEXT
);

-- Use the ISO 4217 abbreviations for currency codes
INSERT INTO acq.currency_type (code, label) VALUES ('USD','US Dollars');
INSERT INTO acq.currency_type (code, label) VALUES ('CAD','Canadian Dollars');
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

CREATE TABLE acq.provider_share_map (
	id		SERIAL	PRIMARY KEY,
	provider	INT	NOT NULL REFERENCES acq.provider (id),
	org		INT	NOT NULL REFERENCES actor.org_unit (id),
	CONSTRAINT provider_share_once_per_owner UNIQUE (provider,org)
);

CREATE TABLE acq.fund (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL,
	owner		INT	NOT NULL REFERENCES actor.org_unit (id),
	currency_type	TEXT	NOT NULL REFERENCES acq.currency_type (code),
	CONSTRAINT fund_name_once_per_owner UNIQUE (name,owner)
);

CREATE TABLE acq.fund_share_map (
	id		SERIAL	PRIMARY KEY,
	fund		INT	NOT NULL REFERENCES acq.fund (id),
	org		INT	NOT NULL REFERENCES actor.org_unit (id),
	CONSTRAINT fund_share_once_per_owner UNIQUE (fund,org)
);

CREATE TABLE acq.fund_credit (
	id	SERIAL	PRIMARY KEY,
	fund    INT     NOT NULL REFERENCES acq.fund (id),
	amount	NUMERIC	NOT NULL,
	note	TEXT
);

CREATE TABLE acq.fund_debit (
	id			SERIAL	PRIMARY KEY,
	fund			INT     NOT NULL REFERENCES acq.fund (id),
	origin_amount		NUMERIC	NOT NULL,  -- pre-exchange-rate amount
	origin_currency_type	TEXT	NOT NULL REFERENCES acq.currency_type (code),
	amount			NUMERIC	NOT NULL,
	encumberance		BOOL	NOT NULL DEFAULT TRUE
);

CREATE TABLE acq.picklist (
	id		SERIAL				PRIMARY KEY,
	owner		INT				NOT NULL REFERENCES actor.usr (id),
	name		TEXT				NOT NULL,
	create_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	CONSTRAINT name_once_per_owner UNIQUE (name,owner)
);

CREATE TABLE acq.picklist_entry (
	id		SERIAL	PRIMARY KEY,
	picklist	INT	NOT NULL REFERENCES acq.picklist (id),
	marc		TEXT	NOT NULL,
	marc_title	TEXT,
	marc_author	TEXT,
	marc_lanuage	TEXT,
	marc_pagination	TEXT,
	marc_isbn	TEXT,
	marc_issn	TEXT,
	marc_identifier	TEXT,
	marc_publisher	TEXT,
	marc_pubdate	TEXT,
	marc_edition	TEXT,
	marc_price	TEXT,
	marc_currency	TEXT	REFERENCES acq.currency_type (code),
	eg_bib_id	INT,
	source_label	TEXT,
	vendor_price	TEXT,
	vendor_currency	TEXT	REFERENCES acq.currency_type (code),
	vendor_avail	INT,
	vendor_po	TEXT,
	vendor_identifier	TEXT
);

CREATE TABLE acq.budget (
    id      SERIAL  PRIMARY KEY,
    org     INT     NOT NULL REFERENCES actor.org_unit (id) ON UPDATE CASCADE ON DELETE CASCADE,
    name    TEXT    NOT NULL,
    year    INT     NOT NULL DEFAULT EXTRACT( YEAR FROM NOW() ),
    CONSTRAINT name_once_per_org_year UNIQUE (org,name,year)
);

CREATE TABLE acq.budget_allocation (
    id          SERIAL  PRIMARY KEY,
    fund        INT     NOT NULL REFERENCES acq.fund (id) ON UPDATE CASCADE ON DELETE CASCADE,
    budget      INT     NOT NULL REFERENCES acq.budget (id) ON UPDATE CASCADE ON DELETE CASCADE,
    amount      NUMERIC,
    percent     NUMERIC CHECK (percent IS NULL OR percent BETWEEN 0.0 AND 100.0),
    allocator   INT NOT NULL REFERENCES actor.usr (id),
    note        TEXT,
    CONSTRAINT allocation_amount_or_percent CHECK ((percent IS NULL AND amount IS NOT NULL) OR (percent IS NOT NULL AND amount IS NULL))
);

COMMIT;




