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
	note		TEXT,
	void		BOOL				NOT NULL DEFALUT FALSE
);
CREATE INDEX m_b_xact_idx ON money.billing (xact);

CREATE TABLE money.payment (
	id		BIGSERIAL			PRIMARY KEY,
	xact		BIGINT				NOT NULL, -- money.billable_xact.id
	amount		NUMERIC(6,2)			NOT NULL,
	payment_ts	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	note		TEXT,
	void		BOOL				NOT NULL DEFALUT FALSE
);
CREATE INDEX m_p_xact_idx ON money.payment (xact);

CREATE OR REPLACE VIEW money.billable_xact_summary AS
	SELECT	xact.id AS id,
		xact.usr AS usr,
		xact.xact_start AS xact_start,
		xact.xact_finish AS xact_finish,
		SUM(COALESCE(credit.amount,0)) AS total_paid,
		MAX(credit.payment_ts) AS last_payment_ts,
		SUM(COALESCE(debit.amount,0)) AS total_owed,
		MAX(debit.billing_ts) AS last_billing_ts,
		SUM(COALESCE(debit.amount,0) - COALESCE(credit.amount,0)) AS balance_owed
	  FROM	money.billable_xact xact
	  	LEFT JOIN money.billing debit ON (xact.id = debit.xact AND debit.void IS FALSE)
		LEFT JOIN money.payment credit ON (xact.id = credit.xact AND credit.void IS FALSE)
	  WHERE	xact.xact_finish IS NULL
	GROUP BY 1,2,3,4;

CREATE OR REPLACE VIEW money.usr_summary AS
	SELECT	usr,
		SUM(total_paid) AS total_paid,
		SUM(total_owed) AS total_owed, 
		SUM(balance_owed) AS balance_owed
	  FROM money.billable_xact_summary
	  GROUP BY 1;

CREATE TABLE money.bnm_payment (
	amount_collected	NUMERIC(6,2)	NOT NULL,
	accepting_usr		INT		NOT NULL
) INHERITS (money.payment);

CREATE TABLE money.forgive_payment () INHERITS (money.bnm_payment);
CREATE INDEX money_forgive_payment_xact_idx ON money.forgive_payment (xact);
CREATE INDEX money_forgive_payment_accepting_usr_idx ON money.forgive_payment (accepting_usr);

CREATE TABLE money.work_payment () INHERITS (money.bnm_payment);
CREATE INDEX money_work_payment_xact_idx ON money.work_payment (xact);
CREATE INDEX money_work_payment_accepting_usr_idx ON money.work_payment (accepting_usr);

CREATE TABLE money.credit_payment () INHERITS (money.bnm_payment);
CREATE INDEX money_credit_payment_xact_idx ON money.credit_payment (xact);
CREATE INDEX money_credit_payment_accepting_usr_idx ON money.credit_payment (accepting_usr);

CREATE TABLE money.bnm_desk_payment (
	cash_drawer	TEXT	NOT NULL
) INHERITS (money.bnm_payment);

CREATE TABLE money.cash_payment () INHERITS (money.bnm_desk_payment);
CREATE INDEX money_cash_payment_xact_idx ON money.cash_payment (xact);
CREATE INDEX money_cash_payment_accepting_usr_idx ON money.cash_payment (accepting_usr);

CREATE TABLE money.check_payment (
	check_number	TEXT	NOT NULL
) INHERITS (money.bnm_desk_payment);
CREATE INDEX money_check_payment_xact_idx ON money.check_payment (xact);
CREATE INDEX money_check_payment_accepting_usr_idx ON money.check_payment (accepting_usr);

CREATE TABLE money.credit_card_payment (
	cc_type		TEXT	NOT NULL,
	cc_number	TEXT	NOT NULL,
	expire_month	INT	NOT NULL,
	expire_year	INT	NOT NULL,
	approval_code	TEXT	NOT NULL
) INHERITS (money.bnm_desk_payment);
CREATE INDEX money_credit_card_payment_xact_idx ON money.credit_card_payment (xact);
CREATE INDEX money_credit_card_payment_accepting_usr_idx ON money.credit_card_payment (accepting_usr);


COMMIT;

