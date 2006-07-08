DROP SCHEMA money CASCADE;

BEGIN;

CREATE SCHEMA money;

CREATE TABLE money.collections_tracker (
	id		BIGSERIAL			PRIMARY KEY,
	usr		INT				NOT NULL REFERENCES actor.usr (id), -- actor.usr.id
	collector	INT				NOT NULL REFERENCES actor.usr (id),
	location	INT				NOT NULL REFERENCES actor.org_unit (id),
	enter_time	TIMESTAMP WITH TIME ZONE
);
CREATE UNIQUE INDEX m_c_t_usr_collector_location_once_idx ON money.collections_tracker (usr, collector, location);

CREATE TABLE money.billable_xact (
	id		BIGSERIAL			PRIMARY KEY,
	usr		INT				NOT NULL, -- actor.usr.id
	xact_start	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	xact_finish	TIMESTAMP WITH TIME ZONE
);
CREATE INDEX m_b_x_open_xacts_idx ON money.billable_xact (usr);

CREATE TABLE money.grocery ( -- Catchall table for local billing
	billing_location	INT	NOT NULL, -- library creating transaction
	note			TEXT
) INHERITS (money.billable_xact);

CREATE TABLE money.billing (
	id		BIGSERIAL			PRIMARY KEY,
	xact		BIGINT				NOT NULL, -- money.billable_xact.id
	billing_ts	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	voided		BOOL				NOT NULL DEFAULT FALSE,
	voider		INT,
	void_time	TIMESTAMP WITH TIME ZONE,
	amount		NUMERIC(6,2)			NOT NULL,
	billing_type	TEXT				NOT NULL,
	note		TEXT
);
CREATE INDEX m_b_xact_idx ON money.billing (xact);

CREATE TABLE money.payment (
	id		BIGSERIAL			PRIMARY KEY,
	xact		BIGINT				NOT NULL, -- money.billable_xact.id
	payment_ts	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	voided		BOOL				NOT NULL DEFAULT FALSE,
	amount		NUMERIC(6,2)			NOT NULL,
	note		TEXT
);
CREATE INDEX m_p_xact_idx ON money.payment (xact);

CREATE OR REPLACE VIEW money.payment_view AS
	SELECT	p.*,c.relname AS payment_type
	  FROM	money.payment p
	  	JOIN pg_class c ON (p.tableoid = c.oid);

CREATE OR REPLACE VIEW money.transaction_billing_type_summary AS
	SELECT	xact,
		billing_type AS last_billing_type,
		LAST(note) AS last_billing_note,
		MAX(billing_ts) AS last_billing_ts,
		SUM(COALESCE(amount,0)) AS total_owed
	  FROM	money.billing
	  WHERE	voided IS FALSE
	  GROUP BY xact,billing_type
	  ORDER BY MAX(billing_ts);

CREATE OR REPLACE VIEW money.transaction_billing_summary AS
	SELECT	xact,
		LAST(billing_type) AS last_billing_type,
		LAST(note) AS last_billing_note,
		MAX(billing_ts) AS last_billing_ts,
		SUM(COALESCE(amount,0)) AS total_owed
	  FROM	money.billing
	  WHERE	voided IS FALSE
	  GROUP BY xact
	  ORDER BY MAX(billing_ts);

CREATE OR REPLACE VIEW money.transaction_payment_summary AS
	SELECT	xact,
		LAST(payment_type) AS last_payment_type,
		LAST(note) AS last_payment_note,
		MAX(payment_ts) as last_payment_ts,
		SUM(COALESCE(amount,0)) AS total_paid
	  FROM	money.payment_view
	  WHERE	voided IS FALSE
	  GROUP BY xact
	  ORDER BY MAX(payment_ts);

CREATE OR REPLACE VIEW money.transaction_billing_with_void_summary AS
	SELECT	xact,
		LAST(billing_type) AS last_billing_type,
		LAST(note) AS last_billing_note,
		MAX(billing_ts) AS last_billing_ts,
		SUM(CASE WHEN voided THEN 0 ELSE COALESCE(amount,0) END) AS total_owed
	  FROM	money.billing
	  GROUP BY xact
	  ORDER BY MAX(billing_ts);

CREATE OR REPLACE VIEW money.transaction_payment_with_void_summary AS
	SELECT	xact,
		LAST(payment_type) AS last_payment_type,
		LAST(note) AS last_payment_note,
		MAX(payment_ts) as last_payment_ts,
		SUM(CASE WHEN voided THEN 0 ELSE COALESCE(amount,0) END) AS total_paid
	  FROM	money.payment_view
	  GROUP BY xact
	  ORDER BY MAX(payment_ts);

CREATE OR REPLACE VIEW money.open_transaction_billing_type_summary AS
	SELECT	xact,
		billing_type AS last_billing_type,
		LAST(note) AS last_billing_note,
		MAX(billing_ts) AS last_billing_ts,
		SUM(COALESCE(amount,0)) AS total_owed
	  FROM	money.billing
	  WHERE	voided IS FALSE
	  GROUP BY xact,billing_type
	  ORDER BY MAX(billing_ts);

CREATE OR REPLACE VIEW money.open_transaction_billing_summary AS
	SELECT	xact,
		LAST(billing_type) AS last_billing_type,
		LAST(note) AS last_billing_note,
		MAX(billing_ts) AS last_billing_ts,
		SUM(COALESCE(amount,0)) AS total_owed
	  FROM	money.billing
	  WHERE	voided IS FALSE
	  GROUP BY xact
	  ORDER BY MAX(billing_ts);

CREATE OR REPLACE VIEW money.open_transaction_payment_summary AS
	SELECT	xact,
		LAST(payment_type) AS last_payment_type,
		LAST(note) AS last_payment_note,
		MAX(payment_ts) as last_payment_ts,
		SUM(COALESCE(amount,0)) AS total_paid
	  FROM	money.payment_view
	  WHERE	voided IS FALSE
	  GROUP BY xact
	  ORDER BY MAX(payment_ts);

CREATE OR REPLACE VIEW money.billable_xact_with_void_summary AS
	SELECT	xact.id AS id,
		xact.usr AS usr,
		xact.xact_start AS xact_start,
		xact.xact_finish AS xact_finish,
		credit.total_paid,
		credit.last_payment_ts,
		credit.last_payment_note,
		credit.last_payment_type,
		debit.total_owed,
		debit.last_billing_ts,
		debit.last_billing_note,
		debit.last_billing_type,
		COALESCE(debit.total_owed,0) - COALESCE(credit.total_paid,0) AS balance_owed,
		p.relname AS xact_type
	  FROM	money.billable_xact xact
	  	JOIN pg_class p ON (xact.tableoid = p.oid)
	  	LEFT JOIN money.transaction_billing_with_void_summary debit ON (xact.id = debit.xact)
	  	LEFT JOIN money.transaction_payment_with_void_summary credit ON (xact.id = credit.xact);

CREATE OR REPLACE VIEW money.billable_xact_summary AS
	SELECT	xact.id AS id,
		xact.usr AS usr,
		xact.xact_start AS xact_start,
		xact.xact_finish AS xact_finish,
		credit.total_paid,
		credit.last_payment_ts,
		credit.last_payment_note,
		credit.last_payment_type,
		debit.total_owed,
		debit.last_billing_ts,
		debit.last_billing_note,
		debit.last_billing_type,
		COALESCE(debit.total_owed,0) - COALESCE(credit.total_paid,0) AS balance_owed,
		p.relname AS xact_type
	  FROM	money.billable_xact xact
	  	JOIN pg_class p ON (xact.tableoid = p.oid)
	  	LEFT JOIN money.transaction_billing_summary debit ON (xact.id = debit.xact)
	  	LEFT JOIN money.transaction_payment_summary credit ON (xact.id = credit.xact);

CREATE OR REPLACE VIEW money.open_billable_xact_summary AS
	SELECT	xact.id AS id,
		xact.usr AS usr,
		xact.xact_start AS xact_start,
		xact.xact_finish AS xact_finish,
		credit.total_paid,
		credit.last_payment_ts,
		credit.last_payment_note,
		credit.last_payment_type,
		debit.total_owed,
		debit.last_billing_ts,
		debit.last_billing_note,
		debit.last_billing_type,
		COALESCE(debit.total_owed,0) - COALESCE(credit.total_paid,0) AS balance_owed,
		p.relname AS xact_type
	  FROM	money.billable_xact xact
	  	JOIN pg_class p ON (xact.tableoid = p.oid)
	  	LEFT JOIN money.transaction_billing_summary debit ON (xact.id = debit.xact)
	  	LEFT JOIN money.transaction_payment_summary credit ON (xact.id = credit.xact)
	  WHERE	xact.xact_finish IS NULL;

CREATE OR REPLACE VIEW money.open_usr_summary AS
	SELECT	usr,
		SUM(total_paid) AS total_paid,
		SUM(total_owed) AS total_owed, 
		SUM(balance_owed) AS balance_owed
	  FROM money.open_billable_xact_summary
	  GROUP BY 1;

CREATE OR REPLACE VIEW money.open_usr_circulation_summary AS
	SELECT	usr,
		SUM(total_paid) AS total_paid,
		SUM(total_owed) AS total_owed, 
		SUM(balance_owed) AS balance_owed
	  FROM	money.open_billable_xact_summary
	  WHERE	xact_type = 'circulation'
	  GROUP BY 1;

CREATE OR REPLACE VIEW money.usr_summary AS
	SELECT	usr,
		SUM(total_paid) AS total_paid,
		SUM(total_owed) AS total_owed, 
		SUM(balance_owed) AS balance_owed
	  FROM money.billable_xact_summary
	  GROUP BY 1;

CREATE OR REPLACE VIEW money.usr_circulation_summary AS
	SELECT	usr,
		SUM(total_paid) AS total_paid,
		SUM(total_owed) AS total_owed, 
		SUM(balance_owed) AS balance_owed
	  FROM	money.billable_xact_summary
	  WHERE	xact_type = 'circulation'
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
	cash_drawer	INT	REFERENCES actor.workstation (id)
) INHERITS (money.bnm_payment);

CREATE TABLE money.cash_payment () INHERITS (money.bnm_desk_payment);
CREATE INDEX money_cash_payment_xact_idx ON money.cash_payment (xact);
CREATE INDEX money_cash_payment_accepting_usr_idx ON money.cash_payment (accepting_usr);
CREATE INDEX money_cash_payment_cash_drawer_idx ON money.cash_payment (cash_drawer);

CREATE TABLE money.check_payment (
	check_number	TEXT	NOT NULL
) INHERITS (money.bnm_desk_payment);
CREATE INDEX money_check_payment_xact_idx ON money.check_payment (xact);
CREATE INDEX money_check_payment_accepting_usr_idx ON money.check_payment (accepting_usr);
CREATE INDEX money_check_payment_cash_drawer_idx ON money.check_payment (cash_drawer);

CREATE TABLE money.credit_card_payment (
	cc_type		TEXT	NOT NULL,
	cc_number	TEXT	NOT NULL,
	expire_month	INT	NOT NULL,
	expire_year	INT	NOT NULL,
	approval_code	TEXT	NOT NULL
) INHERITS (money.bnm_desk_payment);
CREATE INDEX money_credit_card_payment_xact_idx ON money.credit_card_payment (xact);
CREATE INDEX money_credit_card_payment_accepting_usr_idx ON money.credit_card_payment (accepting_usr);
CREATE INDEX money_credit_card_payment_cash_drawer_idx ON money.credit_card_payment (cash_drawer);


COMMIT;

