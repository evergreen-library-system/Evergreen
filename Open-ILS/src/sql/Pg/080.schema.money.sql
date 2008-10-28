/*
 * Copyright (C) 2004-2008  Georgia Public Library Service
 * Copyright (C) 2007-2008  Equinox Software, Inc.
 * Mike Rylander <miker@esilibrary.com> 
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
 *
 */

DROP SCHEMA money CASCADE;

BEGIN;

CREATE SCHEMA money;

CREATE TABLE money.collections_tracker (
	id		BIGSERIAL			PRIMARY KEY,
	usr		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED, -- actor.usr.id
	collector	INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	location	INT				NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	enter_time	TIMESTAMP WITH TIME ZONE
);
CREATE UNIQUE INDEX m_c_t_usr_collector_location_once_idx ON money.collections_tracker (usr, collector, location);

CREATE TABLE money.billable_xact (
	id          BIGSERIAL			PRIMARY KEY,
	usr         INT				NOT NULL, -- actor.usr.id
	xact_start  TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	xact_finish TIMESTAMP WITH TIME ZONE,
    unrecovered BOOL
);
CREATE INDEX m_b_x_open_xacts_idx ON money.billable_xact (usr);

CREATE TABLE money.grocery ( -- Catchall table for local billing
	billing_location	INT	NOT NULL, -- library creating transaction
	note			TEXT
) INHERITS (money.billable_xact);
ALTER TABLE money.grocery ADD PRIMARY KEY (id);
CREATE INDEX circ_open_date_idx ON "money".grocery (xact_start) WHERE xact_finish IS NULL;
CREATE INDEX m_g_usr_idx ON "money".grocery (usr);

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
CREATE INDEX m_b_time_idx ON money.billing (billing_ts);

CREATE TABLE money.payment (
	id		BIGSERIAL			PRIMARY KEY,
	xact		BIGINT				NOT NULL, -- money.billable_xact.id
	payment_ts	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	voided		BOOL				NOT NULL DEFAULT FALSE,
	amount		NUMERIC(6,2)			NOT NULL,
	note		TEXT
);
CREATE INDEX m_p_xact_idx ON money.payment (xact);
CREATE INDEX m_p_time_idx ON money.payment (payment_ts);

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

/* Replacing with the one below.
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
*/

CREATE OR REPLACE VIEW money.billable_xact_with_void_summary AS
	SELECT	xact.id AS id,
		xact.usr AS usr,
		xact.xact_start AS xact_start,
		xact.xact_finish AS xact_finish,
		SUM(credit.amount) AS total_paid,
		MAX(credit.payment_ts) AS last_payment_ts,
		LAST(credit.note) AS last_payment_note,
		LAST(credit.payment_type) AS last_payment_type,
		SUM(debit.amount) AS total_owed,
		MAX(debit.billing_ts) AS last_billing_ts,
		LAST(debit.note) AS last_billing_note,
		LAST(debit.billing_type) AS last_billing_type,
		COALESCE(SUM(debit.amount),0) - COALESCE(SUM(credit.amount),0) AS balance_owed,
		p.relname AS xact_type
	  FROM	money.billable_xact xact
	  	JOIN pg_class p ON (xact.tableoid = p.oid)
	  	LEFT JOIN money.billing debit ON (xact.id = debit.xact)
	  	LEFT JOIN money.payment_view credit ON (xact.id = credit.xact)
	  GROUP BY 1,2,3,4,14
	  ORDER BY MAX(debit.billing_ts), MAX(credit.payment_ts);

/* Replacing with the version below
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

CREATE OR REPLACE VIEW money.billable_xact_summary AS
	SELECT	xact.id AS id,
		xact.usr AS usr,
		xact.xact_start AS xact_start,
		xact.xact_finish AS xact_finish,
		SUM(credit.amount) AS total_paid,
		MAX(credit.payment_ts) AS last_payment_ts,
		LAST(credit.note) AS last_payment_note,
		LAST(credit.payment_type) AS last_payment_type,
		SUM(debit.amount) AS total_owed,
		MAX(debit.billing_ts) AS last_billing_ts,
		LAST(debit.note) AS last_billing_note,
		LAST(debit.billing_type) AS last_billing_type,
		COALESCE(SUM(debit.amount),0) - COALESCE(SUM(credit.amount),0) AS balance_owed,
		p.relname AS xact_type
	  FROM	money.billable_xact xact
	  	JOIN pg_class p ON (xact.tableoid = p.oid)
	  	LEFT JOIN money.billing debit ON (xact.id = debit.xact AND debit.voided IS FALSE)
	  	LEFT JOIN money.payment_view credit ON (xact.id = credit.xact AND credit.voided IS FALSE)
	  GROUP BY 1,2,3,4,14
	  ORDER BY MAX(debit.billing_ts), MAX(credit.payment_ts);
*/

CREATE OR REPLACE VIEW money.billable_xact_summary AS
	SELECT	xact.id,
		xact.usr,
		xact.xact_start,
		xact.xact_finish,
		credit.amount AS total_paid,
		credit.payment_ts AS last_payment_ts,
		credit.note AS last_payment_note,
		credit.payment_type AS last_payment_type,
		debit.amount AS total_owed,
		debit.billing_ts AS last_billing_ts,
		debit.note AS last_billing_note,
		debit.billing_type AS last_billing_type,
		COALESCE(debit.amount, 0::numeric) - COALESCE(credit.amount, 0::numeric) AS balance_owed,
		p.relname AS xact_type
	  FROM	money.billable_xact xact
		JOIN pg_class p ON xact.tableoid = p.oid
		LEFT JOIN (
			SELECT	billing.xact,
				sum(billing.amount) AS amount,
				max(billing.billing_ts) AS billing_ts,
				last(billing.note) AS note,
				last(billing.billing_type) AS billing_type
			  FROM	money.billing
			  WHERE	billing.voided IS FALSE
			  GROUP BY billing.xact
			) debit ON xact.id = debit.xact
		LEFT JOIN (
			SELECT	payment_view.xact,
				sum(payment_view.amount) AS amount,
				max(payment_view.payment_ts) AS payment_ts,
				last(payment_view.note) AS note,
				last(payment_view.payment_type) AS payment_type
			  FROM	money.payment_view
			  WHERE	payment_view.voided IS FALSE
			  GROUP BY payment_view.xact
			) credit ON xact.id = credit.xact
	  ORDER BY debit.billing_ts, credit.payment_ts;

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
ALTER TABLE money.bnm_payment ADD PRIMARY KEY (id);

CREATE TABLE money.forgive_payment () INHERITS (money.bnm_payment);
ALTER TABLE money.forgive_payment ADD PRIMARY KEY (id);
CREATE INDEX money_forgive_id_idx ON money.forgive_payment (id);
CREATE INDEX money_forgive_payment_xact_idx ON money.forgive_payment (xact);
CREATE INDEX money_forgive_payment_payment_ts_idx ON money.forgive_payment (payment_ts);
CREATE INDEX money_forgive_payment_accepting_usr_idx ON money.forgive_payment (accepting_usr);

CREATE TABLE money.work_payment () INHERITS (money.bnm_payment);
ALTER TABLE money.work_payment ADD PRIMARY KEY (id);
CREATE INDEX money_work_id_idx ON money.work_payment (id);
CREATE INDEX money_work_payment_xact_idx ON money.work_payment (xact);
CREATE INDEX money_work_payment_payment_ts_idx ON money.work_payment (payment_ts);
CREATE INDEX money_work_payment_accepting_usr_idx ON money.work_payment (accepting_usr);

CREATE TABLE money.credit_payment () INHERITS (money.bnm_payment);
ALTER TABLE money.credit_payment ADD PRIMARY KEY (id);
CREATE INDEX money_credit_id_idx ON money.credit_payment (id);
CREATE INDEX money_credit_payment_xact_idx ON money.credit_payment (xact);
CREATE INDEX money_credit_payment_payment_ts_idx ON money.credit_payment (payment_ts);
CREATE INDEX money_credit_payment_accepting_usr_idx ON money.credit_payment (accepting_usr);

CREATE TABLE money.goods_payment () INHERITS (money.bnm_payment);
ALTER TABLE money.goods_payment ADD PRIMARY KEY (id);
CREATE INDEX money_goods_id_idx ON money.goods_payment (id);
CREATE INDEX money_goods_payment_xact_idx ON money.goods_payment (xact);
CREATE INDEX money_goods_payment_payment_ts_idx ON money.goods_payment (payment_ts);
CREATE INDEX money_goods_payment_accepting_usr_idx ON money.goods_payment (accepting_usr);

CREATE TABLE money.bnm_desk_payment (
	cash_drawer	INT	REFERENCES actor.workstation (id) DEFERRABLE INITIALLY DEFERRED
) INHERITS (money.bnm_payment);
ALTER TABLE money.bnm_desk_payment ADD PRIMARY KEY (id);

CREATE OR REPLACE VIEW money.desk_payment_view AS
	SELECT	p.*,c.relname AS payment_type
	  FROM	money.bnm_desk_payment p
	  	JOIN pg_class c ON (p.tableoid = c.oid);

CREATE OR REPLACE VIEW money.bnm_payment_view AS
	SELECT	p.*,c.relname AS payment_type
	  FROM	money.bnm_payment p
	  	JOIN pg_class c ON (p.tableoid = c.oid);

CREATE TABLE money.cash_payment () INHERITS (money.bnm_desk_payment);
ALTER TABLE money.cash_payment ADD PRIMARY KEY (id);
CREATE INDEX money_cash_id_idx ON money.cash_payment (id);
CREATE INDEX money_cash_payment_xact_idx ON money.cash_payment (xact);
CREATE INDEX money_cash_payment_ts_idx ON money.cash_payment (payment_ts);
CREATE INDEX money_cash_payment_accepting_usr_idx ON money.cash_payment (accepting_usr);
CREATE INDEX money_cash_payment_cash_drawer_idx ON money.cash_payment (cash_drawer);

CREATE TABLE money.check_payment (
	check_number	TEXT	NOT NULL
) INHERITS (money.bnm_desk_payment);
ALTER TABLE money.check_payment ADD PRIMARY KEY (id);
CREATE INDEX money_check_payment_xact_idx ON money.check_payment (xact);
CREATE INDEX money_check_id_idx ON money.check_payment (id);
CREATE INDEX money_check_payment_ts_idx ON money.check_payment (payment_ts);
CREATE INDEX money_check_payment_accepting_usr_idx ON money.check_payment (accepting_usr);
CREATE INDEX money_check_payment_cash_drawer_idx ON money.check_payment (cash_drawer);

CREATE TABLE money.credit_card_payment (
	cc_type		TEXT,
	cc_number	TEXT,
	expire_month	INT,
	expire_year	INT,
	approval_code	TEXT
) INHERITS (money.bnm_desk_payment);
ALTER TABLE money.credit_card_payment ADD PRIMARY KEY (id);
CREATE INDEX money_credit_card_payment_xact_idx ON money.credit_card_payment (xact);
CREATE INDEX money_credit_card_id_idx ON money.credit_card_payment (id);
CREATE INDEX money_credit_card_payment_ts_idx ON money.credit_card_payment (payment_ts);
CREATE INDEX money_credit_card_payment_accepting_usr_idx ON money.credit_card_payment (accepting_usr);
CREATE INDEX money_credit_card_payment_cash_drawer_idx ON money.credit_card_payment (cash_drawer);

CREATE OR REPLACE VIEW money.non_drawer_payment_view AS
	SELECT	p.*, c.relname AS payment_type
	  FROM	money.bnm_payment p         
			JOIN pg_class c ON p.tableoid = c.oid
	  WHERE	c.relname NOT IN ('cash_payment','check_payment','credit_card_payment');

CREATE OR REPLACE VIEW money.cashdrawer_payment_view AS
	SELECT	ou.id AS org_unit,
		ws.id AS cashdrawer,
		t.payment_type AS payment_type,
		p.payment_ts AS payment_ts,
		p.amount AS amount,
		p.voided AS voided,
		p.note AS note
	  FROM	actor.org_unit ou
		JOIN actor.workstation ws ON (ou.id = ws.owning_lib)
		LEFT JOIN money.bnm_desk_payment p ON (ws.id = p.cash_drawer)
		LEFT JOIN money.payment_view t ON (p.id = t.id);


COMMIT;

