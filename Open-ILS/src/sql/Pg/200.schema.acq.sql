DROP SCHEMA acq CASCADE;

BEGIN;

CREATE SCHEMA acq;

CREATE TABLE acq.currency_type (
	code	TEXT PRIMARY KEY,
	label	TEXT
);

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

INSERT INTO acq.exchange_rate (from_currency,to_currency,ratio) VALUES ('USD','CAN',1.2);
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
	amount	NUMERIC	NOT NULL,
	note	TEXT
);

CREATE TABLE acq.fund_debit (
	id			SERIAL	PRIMARY KEY,
	origin_amount		NUMERIC	NOT NULL,  -- pre-exchange-rate amount
	origin_currency_type	TEXT	NOT NULL REFERENCES acq.currency_type (code),
	amount			NUMERIC	NOT NULL,
	encumberance		BOOL	NOT NULL DEFAULT TRUE
);

COMMIT;
