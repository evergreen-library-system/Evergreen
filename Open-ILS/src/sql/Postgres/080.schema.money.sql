DROP SCHEMA money CASCADE;

BEGIN;

CREATE SCHEMA money;

CREATE TABLE money.billable_xact (
	id		BIGSERIAL			PRIMARY KEY,
	usr		INT				NOT NULL, -- actor.usr.id
	xact_start	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	xact_finish	TIMESTAMP WITH TIME ZONE
);
CREATE INDEX m_b_x_open_xacts_idx ON money.billable_xact (usr) WHERE xact_finish IS NULL;

CREATE TABLE money.billing (
	id		BIGSERIAL			PRIMARY KEY,
	xact		BIGINT				NOT NULL, -- money.billable_xact.id
	amount		NUMERIC(6,2)			NOT NULL,
	billing_ts	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	note		TEXT
);
CREATE INDEX m_b_xact_idx ON money.billing (xact);

CREATE TABLE money.payment (
	id		BIGSERIAL			PRIMARY KEY,
	xact		BIGINT				NOT NULL, -- money.billable_xact.id
	amount		NUMERIC(6,2)			NOT NULL,
	payment_ts	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	note		TEXT
);
CREATE INDEX m_p_xact_idx ON money.payment (xact);

CREATE VIEW money.usr_billable_summary_total AS
	SELECT	xact.usr AS usr,
		SUM(COALESCE(credit.amount,0)) AS payed, SUM(COALESCE(debit.amount,0)) AS owed
	  FROM	money.billable_xact xact
	  	JOIN money.billing debit ON (xact.id = debit.xact)
		JOIN money.payment credit ON (xact.id = credit.xact)
	  WHERE	xact.xact_finish IS NULL
	GROUP BY 1;

CREATE VIEW money.usr_billable_summary_xact AS
	SELECT	xact.id AS transaction,
		xact.usr AS usr,
		SUM(COALESCE(credit.amount,0)) AS payed, SUM(COALESCE(debit.amount,0)) AS owed
	  FROM	money.billable_xact xact
	  	JOIN money.billing debit ON (xact.id = debit.xact)
		JOIN money.payment credit ON (xact.id = credit.xact)
	  WHERE	xact.xact_finish IS NULL
	GROUP BY 1,2;



CREATE TABLE money.bnm_payment (
	amount_collected	NUMERIC(6,2)	NOT NULL,
	accepting_usr		INT		NOT NULL
) INHERITS (money.payment);

CREATE TABLE money.forgive_payment () INHERITS (money.bnm_payment);
CREATE TABLE money.work_payment () INHERITS (money.bnm_payment);
CREATE TABLE money.credit_payment () INHERITS (money.bnm_payment);

CREATE TABLE money.bnm_desk_payment (
	cash_drawer	TEXT	NOT NULL
) INHERITS (money.bnm_payment);

CREATE TABLE money.cash_payment () INHERITS (money.bnm_desk_payment);

CREATE TABLE money.check_payment (
	check_number	TEXT	NOT NULL
) INHERITS (money.bnm_desk_payment);

CREATE TABLE money.credit_card_payment (
	cc_type		TEXT	NOT NULL,
	cc_number	TEXT	NOT NULL,
	expire_month	INT	NOT NULL,
	expire_year	INT	NOT NULL,
	approval_code	TEXT	NOT NULL
) INHERITS (money.bnm_desk_payment);


COMMIT;

