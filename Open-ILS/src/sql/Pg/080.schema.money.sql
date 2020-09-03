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

DROP SCHEMA IF EXISTS money CASCADE;

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
CREATE INDEX m_c_t_collector_idx                          ON money.collections_tracker ( collector );

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
	billing_ts	TIMESTAMP WITH TIME ZONE	NOT NULL, -- DEPRECATED, legacy only
	voided		BOOL				NOT NULL DEFAULT FALSE,
	voider		INT,
	void_time	TIMESTAMP WITH TIME ZONE,
	amount		NUMERIC(6,2)			NOT NULL,
	billing_type	TEXT				NOT NULL,
	btype		INT				NOT NULL REFERENCES config.billing_type (id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
	note		TEXT,
	create_date	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	period_start	TIMESTAMP WITH TIME ZONE,
	period_end	TIMESTAMP WITH TIME ZONE
);
CREATE INDEX m_b_xact_idx ON money.billing (xact);
CREATE INDEX m_b_time_idx ON money.billing (billing_ts);
CREATE INDEX m_b_create_date_idx ON money.billing (create_date);
CREATE INDEX m_b_period_start_idx ON money.billing (period_start);
CREATE INDEX m_b_period_end_idx ON money.billing (period_end);
CREATE INDEX m_b_voider_idx ON money.billing (voider); -- helps user merge function speed
CREATE OR REPLACE FUNCTION money.maintain_billing_ts () RETURNS TRIGGER AS $$
BEGIN
	NEW.billing_ts := COALESCE(NEW.period_end, NEW.create_date);
	RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;
CREATE TRIGGER maintain_billing_ts_tgr BEFORE INSERT OR UPDATE ON money.billing FOR EACH ROW EXECUTE PROCEDURE money.maintain_billing_ts();

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

CREATE OR REPLACE RULE money_payment_view_update AS ON UPDATE TO money.payment_view DO INSTEAD 
    UPDATE money.payment SET xact = NEW.xact, payment_ts = NEW.payment_ts, voided = NEW.voided, amount = NEW.amount, note = NEW.note WHERE id = NEW.id;

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

CREATE OR REPLACE VIEW money.billable_xact_summary AS
	SELECT	xact.id,
		xact.usr,
		xact.xact_start,
		xact.xact_finish,
		COALESCE(credit.amount, 0.0::numeric) AS total_paid,
		credit.payment_ts AS last_payment_ts,
		credit.note AS last_payment_note,
		credit.payment_type AS last_payment_type,
		COALESCE(debit.amount, 0.0::numeric) AS total_owed,
		debit.billing_ts AS last_billing_ts,
		debit.note AS last_billing_note,
		debit.billing_type AS last_billing_type,
		COALESCE(debit.amount, 0.0::numeric) - COALESCE(credit.amount, 0.0::numeric) AS balance_owed,
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

CREATE TABLE money.materialized_billable_xact_summary AS
	SELECT * FROM money.billable_xact_summary WHERE 1=0;

-- TODO: Define money.materialized_billable_xact_summary w/ explicit columns and
-- remove the definition above for money.billable_xact_summary.
CREATE OR REPLACE VIEW money.billable_xact_summary AS 
    SELECT * FROM money.materialized_billable_xact_summary;

ALTER TABLE money.materialized_billable_xact_summary ADD PRIMARY KEY (id);

CREATE INDEX money_mat_summary_usr_idx ON money.materialized_billable_xact_summary (usr);
CREATE INDEX money_mat_summary_xact_start_idx ON money.materialized_billable_xact_summary (xact_start);

CREATE OR REPLACE VIEW money.transaction_billing_summary AS
    SELECT id as xact,
        last_billing_type,
        last_billing_note,
        last_billing_ts,
        total_owed
      FROM money.materialized_billable_xact_summary;

/* AFTER trigger only! */
CREATE OR REPLACE FUNCTION money.mat_summary_create () RETURNS TRIGGER AS $$
BEGIN
	INSERT INTO money.materialized_billable_xact_summary (id, usr, xact_start, xact_finish, total_paid, total_owed, balance_owed, xact_type)
		VALUES ( NEW.id, NEW.usr, NEW.xact_start, NEW.xact_finish, 0.0, 0.0, 0.0, TG_ARGV[0]);
	RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

/* BEFORE or AFTER trigger only! */
CREATE OR REPLACE FUNCTION money.mat_summary_update () RETURNS TRIGGER AS $$
BEGIN
	UPDATE	money.materialized_billable_xact_summary
	  SET	usr = NEW.usr,
		xact_start = NEW.xact_start,
		xact_finish = NEW.xact_finish
	  WHERE	id = NEW.id;
	RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

/* AFTER trigger only! */
CREATE OR REPLACE FUNCTION money.mat_summary_delete () RETURNS TRIGGER AS $$
BEGIN
	DELETE FROM money.materialized_billable_xact_summary WHERE id = OLD.id;
	RETURN OLD;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER mat_summary_create_tgr AFTER INSERT ON money.grocery FOR EACH ROW EXECUTE PROCEDURE money.mat_summary_create ('grocery');
CREATE TRIGGER mat_summary_change_tgr AFTER UPDATE ON money.grocery FOR EACH ROW EXECUTE PROCEDURE money.mat_summary_update ();
CREATE TRIGGER mat_summary_remove_tgr AFTER DELETE ON money.grocery FOR EACH ROW EXECUTE PROCEDURE money.mat_summary_delete ();



/* BEFORE or AFTER trigger */
CREATE OR REPLACE FUNCTION money.materialized_summary_billing_add () RETURNS TRIGGER AS $$
BEGIN
	IF NOT NEW.voided THEN
		UPDATE	money.materialized_billable_xact_summary
		  SET	total_owed = COALESCE(total_owed, 0.0::numeric) + NEW.amount,
			last_billing_ts = NEW.billing_ts,
			last_billing_note = NEW.note,
			last_billing_type = NEW.billing_type,
			balance_owed = balance_owed + NEW.amount
		  WHERE	id = NEW.xact;
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

/* AFTER trigger only! */
CREATE OR REPLACE FUNCTION money.materialized_summary_billing_update () RETURNS TRIGGER AS $$
DECLARE
	old_billing	money.billing%ROWTYPE;
	old_voided	money.billing%ROWTYPE;
BEGIN

	SELECT * INTO old_billing FROM money.billing WHERE xact = NEW.xact AND NOT voided ORDER BY billing_ts DESC LIMIT 1;
	SELECT * INTO old_voided FROM money.billing WHERE xact = NEW.xact ORDER BY billing_ts DESC LIMIT 1;

	IF NEW.voided AND NOT OLD.voided THEN
		IF OLD.id = old_voided.id THEN
			UPDATE	money.materialized_billable_xact_summary
			  SET	last_billing_ts = old_billing.billing_ts,
				last_billing_note = old_billing.note,
				last_billing_type = old_billing.billing_type
			  WHERE	id = OLD.xact;
		END IF;

		UPDATE	money.materialized_billable_xact_summary
		  SET	total_owed = total_owed - NEW.amount,
			balance_owed = balance_owed - NEW.amount
		  WHERE	id = NEW.xact;

	ELSIF NOT NEW.voided AND OLD.voided THEN

		IF OLD.id = old_billing.id THEN
			UPDATE	money.materialized_billable_xact_summary
			  SET	last_billing_ts = old_billing.billing_ts,
				last_billing_note = old_billing.note,
				last_billing_type = old_billing.billing_type
			  WHERE	id = OLD.xact;
		END IF;

		UPDATE	money.materialized_billable_xact_summary
		  SET	total_owed = total_owed + NEW.amount,
			balance_owed = balance_owed + NEW.amount
		  WHERE	id = NEW.xact;

	ELSE
		UPDATE	money.materialized_billable_xact_summary
		  SET	total_owed = total_owed - (OLD.amount - NEW.amount),
			balance_owed = balance_owed - (OLD.amount - NEW.amount)
		  WHERE	id = NEW.xact;
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

/* BEFORE trigger only! */
CREATE OR REPLACE FUNCTION money.materialized_summary_billing_del () RETURNS TRIGGER AS $$
DECLARE
	prev_billing	money.billing%ROWTYPE;
	old_billing	money.billing%ROWTYPE;
BEGIN
	SELECT * INTO prev_billing FROM money.billing WHERE xact = OLD.xact AND NOT voided ORDER BY billing_ts DESC LIMIT 1 OFFSET 1;
	SELECT * INTO old_billing FROM money.billing WHERE xact = OLD.xact AND NOT voided ORDER BY billing_ts DESC LIMIT 1;

	IF OLD.id = old_billing.id THEN
		UPDATE	money.materialized_billable_xact_summary
		  SET	last_billing_ts = prev_billing.billing_ts,
			last_billing_note = prev_billing.note,
			last_billing_type = prev_billing.billing_type
		  WHERE	id = OLD.xact;
	END IF;

	IF NOT OLD.voided THEN
		UPDATE	money.materialized_billable_xact_summary
		  SET	total_owed = total_owed - OLD.amount,
			balance_owed = balance_owed - OLD.amount
		  WHERE	id = OLD.xact;
	END IF;

	RETURN OLD;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.billing FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_billing_add ();
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.billing FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_billing_update ();
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.billing FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_billing_del ();


/* BEFORE or AFTER trigger */
CREATE OR REPLACE FUNCTION money.materialized_summary_payment_add () RETURNS TRIGGER AS $$
BEGIN
	IF NOT NEW.voided THEN
		UPDATE	money.materialized_billable_xact_summary
		  SET	total_paid = COALESCE(total_paid, 0.0::numeric) + NEW.amount,
			last_payment_ts = NEW.payment_ts,
			last_payment_note = NEW.note,
			last_payment_type = TG_ARGV[0],
			balance_owed = balance_owed - NEW.amount
		  WHERE	id = NEW.xact;
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

/* AFTER trigger only! */
CREATE OR REPLACE FUNCTION money.materialized_summary_payment_update () RETURNS TRIGGER AS $$
DECLARE
	old_payment	money.payment_view%ROWTYPE;
	old_voided	money.payment_view%ROWTYPE;
BEGIN

	SELECT * INTO old_payment FROM money.payment_view WHERE xact = NEW.xact AND NOT voided ORDER BY payment_ts DESC LIMIT 1;
	SELECT * INTO old_voided FROM money.payment_view WHERE xact = NEW.xact ORDER BY payment_ts DESC LIMIT 1;

	IF NEW.voided AND NOT OLD.voided THEN
		IF OLD.id = old_voided.id THEN
			UPDATE	money.materialized_billable_xact_summary
			  SET	last_payment_ts = old_payment.payment_ts,
				last_payment_note = old_payment.note,
				last_payment_type = old_payment.payment_type
			  WHERE	id = OLD.xact;
		END IF;

		UPDATE	money.materialized_billable_xact_summary
		  SET	total_paid = total_paid - NEW.amount,
			balance_owed = balance_owed + NEW.amount
		  WHERE	id = NEW.xact;

	ELSIF NOT NEW.voided AND OLD.voided THEN

		IF OLD.id = old_payment.id THEN
			UPDATE	money.materialized_billable_xact_summary
			  SET	last_payment_ts = old_payment.payment_ts,
				last_payment_note = old_payment.note,
				last_payment_type = old_payment.payment_type
			  WHERE	id = OLD.xact;
		END IF;

		UPDATE	money.materialized_billable_xact_summary
		  SET	total_paid = total_paid + NEW.amount,
			balance_owed = balance_owed - NEW.amount
		  WHERE	id = NEW.xact;

	ELSE
		UPDATE	money.materialized_billable_xact_summary
		  SET	total_paid = total_paid - (OLD.amount - NEW.amount),
			balance_owed = balance_owed + (OLD.amount - NEW.amount)
		  WHERE	id = NEW.xact;
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

/* BEFORE trigger only! */
CREATE OR REPLACE FUNCTION money.materialized_summary_payment_del () RETURNS TRIGGER AS $$
DECLARE
	prev_payment	money.payment_view%ROWTYPE;
	old_payment	money.payment_view%ROWTYPE;
BEGIN
	SELECT * INTO prev_payment FROM money.payment_view WHERE xact = OLD.xact AND NOT voided ORDER BY payment_ts DESC LIMIT 1 OFFSET 1;
	SELECT * INTO old_payment FROM money.payment_view WHERE xact = OLD.xact AND NOT voided ORDER BY payment_ts DESC LIMIT 1;

	IF OLD.id = old_payment.id THEN
		UPDATE	money.materialized_billable_xact_summary
		  SET	last_payment_ts = prev_payment.payment_ts,
			last_payment_note = prev_payment.note,
			last_payment_type = prev_payment.payment_type
		  WHERE	id = OLD.xact;
	END IF;

	IF NOT OLD.voided THEN
		UPDATE	money.materialized_billable_xact_summary
		  SET	total_paid = total_paid - OLD.amount,
			balance_owed = balance_owed + OLD.amount
		  WHERE	id = OLD.xact;
	END IF;

	RETURN OLD;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE VIEW money.usr_summary AS
    SELECT 
        usr, 
        sum(total_paid) AS total_paid, 
        sum(total_owed) AS total_owed, 
        sum(balance_owed) AS balance_owed
    FROM money.materialized_billable_xact_summary
    GROUP BY usr;


CREATE OR REPLACE VIEW money.usr_circulation_summary AS
	SELECT	usr,
		SUM(total_paid) AS total_paid,
		SUM(total_owed) AS total_owed, 
		SUM(balance_owed) AS balance_owed
	  FROM	money.billable_xact_summary
	  WHERE	xact_type = 'circulation'
	  GROUP BY 1;

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('payment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('payment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('payment');

CREATE TABLE money.bnm_payment (
	amount_collected	NUMERIC(6,2)	NOT NULL,
	accepting_usr		INT		NOT NULL
) INHERITS (money.payment);
ALTER TABLE money.bnm_payment ADD PRIMARY KEY (id);

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.bnm_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('bnm_payment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.bnm_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('bnm_payment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.bnm_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('bnm_payment');


CREATE TABLE money.forgive_payment () INHERITS (money.bnm_payment);
ALTER TABLE money.forgive_payment ADD PRIMARY KEY (id);
CREATE INDEX money_forgive_id_idx ON money.forgive_payment (id);
CREATE INDEX money_forgive_payment_xact_idx ON money.forgive_payment (xact);
CREATE INDEX money_forgive_payment_payment_ts_idx ON money.forgive_payment (payment_ts);
CREATE INDEX money_forgive_payment_accepting_usr_idx ON money.forgive_payment (accepting_usr);

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.forgive_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('forgive_payment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.forgive_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('forgive_payment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.forgive_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('forgive_payment');

CREATE TABLE money.account_adjustment (
    billing BIGINT REFERENCES money.billing (id) ON DELETE SET NULL
) INHERITS (money.bnm_payment);
ALTER TABLE money.account_adjustment ADD PRIMARY KEY (id);
CREATE INDEX money_adjustment_id_idx ON money.account_adjustment (id);
CREATE INDEX money_account_adjustment_xact_idx ON money.account_adjustment (xact);
CREATE INDEX money_account_adjustment_bill_idx ON money.account_adjustment (billing);
CREATE INDEX money_account_adjustment_payment_ts_idx ON money.account_adjustment (payment_ts);
CREATE INDEX money_account_adjustment_accepting_usr_idx ON money.account_adjustment (accepting_usr);

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.account_adjustment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('account_adjustment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.account_adjustment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('account_adjustment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.account_adjustment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('account_adjustment');


CREATE TABLE money.work_payment () INHERITS (money.bnm_payment);
ALTER TABLE money.work_payment ADD PRIMARY KEY (id);
CREATE INDEX money_work_id_idx ON money.work_payment (id);
CREATE INDEX money_work_payment_xact_idx ON money.work_payment (xact);
CREATE INDEX money_work_payment_payment_ts_idx ON money.work_payment (payment_ts);
CREATE INDEX money_work_payment_accepting_usr_idx ON money.work_payment (accepting_usr);

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.work_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('work_payment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.work_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('work_payment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.work_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('work_payment');


CREATE TABLE money.credit_payment () INHERITS (money.bnm_payment);
ALTER TABLE money.credit_payment ADD PRIMARY KEY (id);
CREATE INDEX money_credit_id_idx ON money.credit_payment (id);
CREATE INDEX money_credit_payment_xact_idx ON money.credit_payment (xact);
CREATE INDEX money_credit_payment_payment_ts_idx ON money.credit_payment (payment_ts);
CREATE INDEX money_credit_payment_accepting_usr_idx ON money.credit_payment (accepting_usr);

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.credit_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('credit_payment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.credit_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('credit_payment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.credit_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('credit_payment');


CREATE TABLE money.goods_payment () INHERITS (money.bnm_payment);
ALTER TABLE money.goods_payment ADD PRIMARY KEY (id);
CREATE INDEX money_goods_id_idx ON money.goods_payment (id);
CREATE INDEX money_goods_payment_xact_idx ON money.goods_payment (xact);
CREATE INDEX money_goods_payment_payment_ts_idx ON money.goods_payment (payment_ts);
CREATE INDEX money_goods_payment_accepting_usr_idx ON money.goods_payment (accepting_usr);

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.goods_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('goods_payment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.goods_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('goods_payment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.goods_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('goods_payment');


CREATE TABLE money.bnm_desk_payment (
	cash_drawer	INT	REFERENCES actor.workstation (id) DEFERRABLE INITIALLY DEFERRED
) INHERITS (money.bnm_payment);
ALTER TABLE money.bnm_desk_payment ADD PRIMARY KEY (id);

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.bnm_desk_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('bnm_desk_payment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.bnm_desk_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('bnm_desk_payment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.bnm_desk_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('bnm_desk_payment');


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

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.cash_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('cash_payment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.cash_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('cash_payment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.cash_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('cash_payment');


CREATE TABLE money.check_payment (
	check_number	TEXT	NOT NULL
) INHERITS (money.bnm_desk_payment);
ALTER TABLE money.check_payment ADD PRIMARY KEY (id);
CREATE INDEX money_check_payment_xact_idx ON money.check_payment (xact);
CREATE INDEX money_check_id_idx ON money.check_payment (id);
CREATE INDEX money_check_payment_ts_idx ON money.check_payment (payment_ts);
CREATE INDEX money_check_payment_accepting_usr_idx ON money.check_payment (accepting_usr);
CREATE INDEX money_check_payment_cash_drawer_idx ON money.check_payment (cash_drawer);

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.check_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('check_payment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.check_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('check_payment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.check_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('check_payment');


CREATE TABLE money.credit_card_payment (
    cc_number     TEXT,
    cc_processor TEXT,
    cc_order_number TEXT,
	approval_code	TEXT
) INHERITS (money.bnm_desk_payment);
ALTER TABLE money.credit_card_payment ADD PRIMARY KEY (id);
CREATE INDEX money_credit_card_payment_xact_idx ON money.credit_card_payment (xact);
CREATE INDEX money_credit_card_id_idx ON money.credit_card_payment (id);
CREATE INDEX money_credit_card_payment_ts_idx ON money.credit_card_payment (payment_ts);
CREATE INDEX money_credit_card_payment_accepting_usr_idx ON money.credit_card_payment (accepting_usr);
CREATE INDEX money_credit_card_payment_cash_drawer_idx ON money.credit_card_payment (cash_drawer);

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.credit_card_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('credit_card_payment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.credit_card_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('credit_card_payment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.credit_card_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('credit_card_payment');


CREATE TABLE money.debit_card_payment () INHERITS (money.bnm_desk_payment);
ALTER TABLE money.debit_card_payment ADD PRIMARY KEY (id);
CREATE INDEX money_debit_card_payment_xact_idx ON money.debit_card_payment (xact);
CREATE INDEX money_debit_card_id_idx ON money.debit_card_payment (id);
CREATE INDEX money_debit_card_payment_ts_idx ON money.debit_card_payment (payment_ts);
CREATE INDEX money_debit_card_payment_accepting_usr_idx ON money.debit_card_payment (accepting_usr);
CREATE INDEX money_debit_card_payment_cash_drawer_idx ON money.debit_card_payment (cash_drawer);

CREATE TRIGGER mat_summary_add_tgr AFTER INSERT ON money.debit_card_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_add ('debit_card_payment');
CREATE TRIGGER mat_summary_upd_tgr AFTER UPDATE ON money.debit_card_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_update ('debit_card_payment');
CREATE TRIGGER mat_summary_del_tgr BEFORE DELETE ON money.debit_card_payment FOR EACH ROW EXECUTE PROCEDURE money.materialized_summary_payment_del ('debit_card_payment');


CREATE OR REPLACE VIEW money.non_drawer_payment_view AS
	SELECT	p.*, c.relname AS payment_type
	  FROM	money.bnm_payment p         
			JOIN pg_class c ON p.tableoid = c.oid
	  WHERE	c.relname NOT IN ('cash_payment','check_payment','credit_card_payment','debit_card_payment');

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

-- serves as the basis for the aged payments data.
CREATE OR REPLACE VIEW money.payment_view_for_aging AS
    SELECT p.*,
        bnm.accepting_usr,
        bnmd.cash_drawer,
        maa.billing
    FROM money.payment_view p
    LEFT JOIN money.bnm_payment bnm ON bnm.id = p.id
    LEFT JOIN money.bnm_desk_payment bnmd ON bnmd.id = p.id
    LEFT JOIN money.account_adjustment maa ON maa.id = p.id;

-- Create 'aged' clones of billing and payment_view tables
CREATE TABLE money.aged_payment (LIKE money.payment INCLUDING INDEXES);
ALTER TABLE money.aged_payment 
    ADD COLUMN payment_type TEXT NOT NULL,
    ADD COLUMN accepting_usr INTEGER,
    ADD COLUMN cash_drawer INTEGER,
    ADD COLUMN billing BIGINT;

CREATE INDEX aged_payment_accepting_usr_idx ON money.aged_payment(accepting_usr);
CREATE INDEX aged_payment_cash_drawer_idx ON money.aged_payment(cash_drawer);
CREATE INDEX aged_payment_billing_idx ON money.aged_payment(billing);

CREATE TABLE money.aged_billing (LIKE money.billing INCLUDING INDEXES);

CREATE OR REPLACE VIEW money.all_payments AS
    SELECT * FROM money.payment_view_for_aging
    UNION ALL
    SELECT * FROM money.aged_payment;

CREATE OR REPLACE VIEW money.all_billings AS
    SELECT * FROM money.billing
    UNION ALL
    SELECT * FROM money.aged_billing;

CREATE OR REPLACE FUNCTION money.age_billings_and_payments() RETURNS INTEGER AS $FUNC$
-- Age billings and payments linked to transactions which were 
-- completed at least 'older_than' time ago.
DECLARE
    xact_id BIGINT;
    counter INTEGER DEFAULT 0;
    keep_age INTERVAL;
BEGIN

    SELECT value::INTERVAL INTO keep_age FROM config.global_flag 
        WHERE name = 'history.money.retention_age' AND enabled;

    -- Confirm interval-based aging is enabled.
    IF keep_age IS NULL THEN RETURN counter; END IF;

    -- Start with non-circulation transactions
    FOR xact_id IN SELECT DISTINCT(xact.id) FROM money.billable_xact xact
        -- confirm there is something to age
        JOIN money.billing mb ON mb.xact = xact.id
        -- Avoid aging money linked to non-aged circulations.
        LEFT JOIN action.circulation circ ON circ.id = xact.id
        WHERE circ.id IS NULL AND AGE(NOW(), xact.xact_finish) > keep_age LOOP

        PERFORM money.age_billings_and_payments_for_xact(xact_id);
        counter := counter + 1;
    END LOOP;

    -- Then handle aged circulation money.
    FOR xact_id IN SELECT DISTINCT(xact.id) FROM action.aged_circulation xact
        -- confirm there is something to age
        JOIN money.billing mb ON mb.xact = xact.id
        WHERE AGE(NOW(), xact.xact_finish) > keep_age LOOP

        PERFORM money.age_billings_and_payments_for_xact(xact_id);
        counter := counter + 1;
    END LOOP;

    RETURN counter;
END;
$FUNC$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION money.age_billings_and_payments_for_xact
    (xact_id BIGINT) RETURNS VOID AS $FUNC$

    INSERT INTO money.aged_billing
        SELECT * FROM money.billing WHERE xact = $1;

    INSERT INTO money.aged_payment 
        SELECT * FROM money.payment_view_for_aging WHERE xact = xact_id;

    DELETE FROM money.payment WHERE xact = $1;
    DELETE FROM money.billing WHERE xact = $1;

$FUNC$ LANGUAGE SQL;

CREATE TABLE money.materialized_payment_by_billing_type (
    id              BIGSERIAL       PRIMARY KEY,
    xact            BIGINT          NOT NULL,
    payment         BIGINT          NOT NULL,
    billing         BIGINT          NOT NULL,
    payment_ts      TIMESTAMPTZ     NOT NULL,
    billing_ts      TIMESTAMPTZ     NOT NULL,
    amount          NUMERIC(8,2)    NOT NULL,
    payment_type    TEXT,
    billing_type    TEXT,
    payment_ou      INT,
    billing_ou      INT,
    CONSTRAINT x_p_b_once UNIQUE (xact,payment,billing)
);

CREATE INDEX p_by_b_payment_ts_idx
    ON money.materialized_payment_by_billing_type (payment_ts);



CREATE OR REPLACE FUNCTION money.payment_by_billing_type (
    p_xact BIGINT
) RETURNS SETOF money.materialized_payment_by_billing_type AS $$
DECLARE
    current_result      money.materialized_payment_by_billing_type%ROWTYPE;
    current_payment     money.payment_view%ROWTYPE;
    current_billing     money.billing%ROWTYPE;
    payment_remainder   NUMERIC(8,2) := 0.0;
    billing_remainder   NUMERIC(8,2) := 0.0;
    payment_offset      INT := 0;
    billing_offset      INT := 0;
    billing_ou          INT := 0;
    payment_ou          INT := 0;
    fast_forward        BOOLEAN := FALSE;
    maintain_billing_remainder    BOOLEAN := FALSE;
    billing_loop        INT := -1;
    billing_row_count    INT := 0;
    current_billing_id    BIGINT := 0;
    billing_id_used     BIGINT ARRAY;
    billing_l        INT := 0;
    continuing_payment    BOOLEAN := FALSE;
    continuing_payment_last_row    BOOLEAN := FALSE;
BEGIN

    /*  We take a transaction id and fetch its payments in chronological order.
     *  We apply the payment amount, or a portion thereof, to each billing on
     *  the transaction, also in chronological order, until we run out of money
     *  from that payment.  For each billing we encounter while we have money
     *  left from a payment we emmit a row of output containing the information
     *  about the billing and payment, and the amount of the current payment that
     *  was applied to the current billing.
     */

    -- First we'll go get the xact location.  That will be the fallback location.

    SELECT billing_location INTO billing_ou FROM money.grocery WHERE id = p_xact;
    IF NOT FOUND THEN
        SELECT circ_lib INTO billing_ou FROM action.circulation WHERE id = p_xact;
    END IF;

    SELECT count(id) INTO billing_row_count FROM money.billing WHERE xact = p_xact;

    -- Loop through the positive payments
    FOR current_payment IN
        SELECT  *
          FROM  money.payment_view
          WHERE xact = p_xact
                AND NOT voided
                AND amount > 0.0
          ORDER BY payment_ts
    LOOP

    payment_remainder = current_payment.amount;
        -- With every new payment row, we need to fast forward
        -- the billing lines up to the last paid billing row
        fast_forward := TRUE;

        SELECT  ws.owning_lib INTO payment_ou
            FROM  money.bnm_desk_payment p
                JOIN actor.workstation ws ON (p.cash_drawer = ws.id)
            WHERE p.id = current_payment.id;
        -- If we don't do this then OPAC CC payments have no payment_ou
        IF NOT FOUND THEN
            SELECT home_ou INTO payment_ou FROM actor.usr WHERE id = (SELECT accepting_usr FROM money.bnm_payment WHERE id = current_payment.id);
        END IF;

        -- Were we looking at a billing from a previous step in the loop?
        IF billing_remainder > 0.0 THEN
            current_result.xact = p_xact;
            current_result.payment = current_payment.id;
            current_result.billing = current_billing.id;
            current_result.payment_ts = current_payment.payment_ts;
            current_result.billing_ts = current_billing.billing_ts;
            current_result.payment_type = current_payment.payment_type;
            current_result.billing_type = current_billing.billing_type;
            current_result.payment_ou = payment_ou;
            current_result.billing_ou = billing_ou;

            IF billing_remainder >= payment_remainder THEN
                current_result.amount = payment_remainder;
                billing_remainder = billing_remainder - payment_remainder;
                payment_remainder = 0.0;
                payment_offset = payment_offset + 1;
                -- If it is equal then we need to close up the billing line and move to the next
                -- This prevents 0 amounts applied to billing lines
                IF billing_remainder = payment_remainder THEN
                    billing_remainder = 0.0;
                    billing_offset = billing_offset + 1;
                    billing_id_used = array_append( billing_id_used, current_billing_id );
                ELSE
                    maintain_billing_remainder := TRUE;
                END IF;

            ELSE
                current_result.amount = billing_remainder;
                payment_remainder = payment_remainder - billing_remainder;
                billing_remainder = 0.0;
                billing_offset = billing_offset + 1;
                billing_id_used = array_append( billing_id_used, current_billing_id );
                continuing_payment := TRUE;
                maintain_billing_remainder := FALSE;
            END IF;

            RETURN NEXT current_result;
            -- Done paying the billing rows when we run out of rows to pay (out of bounds)
            EXIT WHEN array_length(billing_id_used, 1) = billing_row_count;
        END IF;

        CONTINUE WHEN payment_remainder = 0.0;

        -- next billing, please
        billing_loop := -1;

        FOR current_billing IN
            SELECT  *
              FROM  money.billing
              WHERE xact = p_xact
               -- Gotta put the voided billing rows at the bottom (last)
              ORDER BY voided,billing_ts
        LOOP
            billing_loop = billing_loop + 1;

            -- Skip billing rows that we have already paid
            IF billing_id_used @> ARRAY[current_billing.id]    THEN CONTINUE;
            END IF;

            IF maintain_billing_remainder THEN
                CONTINUE WHEN current_billing.id <> current_billing_id;
                -- Account adjustment - we expect to pay billing rows that are identical amounts
                ELSE IF current_payment.payment_type = 'account_adjustment' THEN
                    -- Go ahead and allow the row through when it's the last row and we still haven't found one with equal payment amount
                    CONTINUE WHEN ( ( current_billing.amount <> current_payment.amount ) AND ( billing_loop + 1 <> billing_row_count ) );
                END IF;
            END IF;

            -- Keep the old remainder if we were in the middle of a billing row
            IF NOT maintain_billing_remainder THEN
                billing_remainder = current_billing.amount;
            END IF;

            maintain_billing_remainder := FALSE;
            fast_forward := FALSE;
            current_billing_id := current_billing.id;
            continuing_payment := FALSE;

            current_result.xact = p_xact;
            current_result.payment = current_payment.id;
            current_result.billing = current_billing.id;
            current_result.payment_ts = current_payment.payment_ts;
            current_result.billing_ts = current_billing.billing_ts;
            current_result.payment_type = current_payment.payment_type;
            current_result.billing_type = current_billing.billing_type;
            current_result.payment_ou = payment_ou;
            current_result.billing_ou = billing_ou;

            IF billing_remainder >= payment_remainder THEN
                current_result.amount = payment_remainder;
                billing_remainder = billing_remainder - payment_remainder;
                payment_remainder = 0.0;
                -- If it is equal then we need to close up the billing line and move to the next
                -- This prevents 0 amounts applied to billing lines
                IF billing_remainder = payment_remainder THEN
                    billing_remainder = 0.0;
                    billing_offset = billing_offset + 1;
                    billing_id_used = array_append( billing_id_used, current_billing_id );
                END IF;
            ELSE
                current_result.amount = billing_remainder;
                payment_remainder = payment_remainder - billing_remainder;
                continuing_payment := TRUE;
                IF billing_loop + 1 = billing_row_count THEN
                -- We have a situation where we are on the last billing row and we are in the middle of a payment row
                -- We need to start back at the beginning of the billing rows and pay
                    continuing_payment_last_row := TRUE;
                END IF;
                billing_remainder = 0.0;
                billing_offset = billing_offset + 1;
                billing_id_used = array_append( billing_id_used, current_billing_id );
            END IF;

            RETURN NEXT current_result;
            IF continuing_payment_last_row THEN
                -- This should only occur when the account_adjustment's do not line up exactly with the billing
                -- So we are going to pay some other type of billing row with this odd account_adjustment
                -- And we need to stay in the current_payment row while doing so
                billing_loop := -1;
                FOR current_billing IN
                    SELECT  *
                      FROM  money.billing
                      WHERE xact = p_xact
                      ORDER BY voided,billing_ts
                LOOP
                    billing_loop = billing_loop + 1;
                    -- Skip billing rows that we have already paid
                    IF billing_id_used @> ARRAY[current_billing.id]    THEN CONTINUE; END IF;

                    billing_remainder = current_billing.amount;
                    current_billing_id := current_billing.id;
                    continuing_payment := FALSE;

                    current_result.xact = p_xact;
                    current_result.payment = current_payment.id;
                    current_result.billing = current_billing.id;
                    current_result.payment_ts = current_payment.payment_ts;
                    current_result.billing_ts = current_billing.billing_ts;
                    current_result.payment_type = current_payment.payment_type;
                    current_result.billing_type = current_billing.billing_type;
                    current_result.payment_ou = payment_ou;
                    current_result.billing_ou = billing_ou;

                    IF billing_remainder >= payment_remainder THEN
                        current_result.amount = payment_remainder;
                        billing_remainder = billing_remainder - payment_remainder;
                        payment_remainder = 0.0;
                        -- If it is equal then we need to close up the billing line and move to the next
                        -- This prevents 0 amounts applied to billing lines
                        IF billing_remainder = payment_remainder THEN
                            billing_remainder = 0.0;
                            billing_offset = billing_offset + 1;
                            billing_id_used = array_append( billing_id_used, current_billing_id );
                        END IF;
                    ELSE
                        current_result.amount = billing_remainder;
                        payment_remainder = payment_remainder - billing_remainder;
                        billing_remainder = 0.0;
                        billing_offset = billing_offset + 1;
                        billing_id_used = array_append( billing_id_used, current_billing_id );
                    END IF;

                    RETURN NEXT current_result;
                    EXIT WHEN payment_remainder = 0.0;
                END LOOP;

            END IF;
            EXIT WHEN payment_remainder = 0.0;
        END LOOP;

        payment_offset = payment_offset + 1;
        -- Done paying the billing rows when we run out of rows to pay (out of bounds)
        EXIT WHEN array_length(billing_id_used, 1) = billing_row_count;

    END LOOP;

    payment_remainder   := 0.0;
    billing_remainder   := 0.0;
    payment_offset      := 0;
    billing_offset      := 0;
    billing_row_count   := 0;
    billing_loop        := -1;

    -- figure out how many voided billing rows there are
    SELECT count(id) INTO billing_row_count FROM money.billing WHERE xact = p_xact AND voided;

    -- Loop through the negative payments, these are refunds on voided billings
    FOR current_payment IN
        SELECT  *
          FROM  money.payment_view
          WHERE xact = p_xact
                AND NOT voided
                AND amount < 0.0
          ORDER BY payment_ts
    LOOP

        SELECT  ws.owning_lib INTO payment_ou
            FROM  money.bnm_desk_payment p
                JOIN actor.workstation ws ON (p.cash_drawer = ws.id)
            WHERE p.id = current_payment.id;

        IF NOT FOUND THEN
            SELECT home_ou INTO payment_ou FROM actor.usr WHERE id = (SELECT accepting_usr FROM money.bnm_payment WHERE id = current_payment.id);
        END IF;

        payment_remainder = -current_payment.amount; -- invert
        -- With every new payment row, we need to fast forward
        -- the billing lines up to the last paid billing row
        fast_forward := TRUE;

        -- Were we looking at a billing from a previous step in the loop?
        IF billing_remainder > 0.0 THEN

            current_result.xact = p_xact;
            current_result.payment = current_payment.id;
            current_result.billing = current_billing.id;
            current_result.payment_ts = current_payment.payment_ts;
            current_result.billing_ts = current_billing.billing_ts;
            current_result.payment_type = 'REFUND';
            current_result.billing_type = current_billing.billing_type;
            current_result.payment_ou = payment_ou;
            current_result.billing_ou = billing_ou;

            IF billing_remainder >= payment_remainder THEN
                current_result.amount = payment_remainder;
                billing_remainder = billing_remainder - payment_remainder;
                payment_remainder = 0.0;
                payment_offset = payment_offset + 1;
                -- If it is equal then we need to close up the billing line and move to the next
                -- This prevents 0 amounts applied to billing lines
                IF billing_remainder = payment_remainder THEN
                    billing_remainder = 0.0;
                    billing_offset = billing_offset + 1;
                ELSE
                    maintain_billing_remainder := TRUE;
                END IF;
            ELSE
                current_result.amount = billing_remainder;
                payment_remainder = payment_remainder - billing_remainder;
                billing_remainder = 0.0;
                billing_offset = billing_offset + 1;
            END IF;

            current_result.amount = -current_result.amount;
            RETURN NEXT current_result;
            -- Done paying the billing rows when we run out of rows to pay (out of bounds)
            EXIT WHEN billing_offset = billing_row_count + 1;
        END IF;

        CONTINUE WHEN payment_remainder = 0.0;

        -- next billing, please
        billing_loop := -1;
        FOR current_billing IN
            SELECT  *
              FROM  money.billing
              WHERE xact = p_xact
                    AND voided
              ORDER BY billing_ts
        LOOP
            billing_loop = billing_loop + 1; -- first iteration billing_loop=0, it starts at -1
            -- Fast forward through the rows until we get to the billing row
            -- where we left off
            IF fast_forward THEN
                CONTINUE WHEN billing_loop <> billing_offset;
            END IF;

            -- Keep the old remainder if we were in the middle of a billing row
            IF NOT maintain_billing_remainder THEN
                billing_remainder = current_billing.amount;
            END IF;

            maintain_billing_remainder := FALSE;
            fast_forward := FALSE;

            current_result.xact = p_xact;
            current_result.payment = current_payment.id;
            current_result.billing = current_billing.id;
            current_result.payment_ts = current_payment.payment_ts;
            current_result.billing_ts = current_billing.billing_ts;
            current_result.payment_type = 'REFUND';
            current_result.billing_type = current_billing.billing_type;
            current_result.payment_ou = payment_ou;
            current_result.billing_ou = billing_ou;

            IF billing_remainder >= payment_remainder THEN
                current_result.amount = payment_remainder;
                billing_remainder = billing_remainder - payment_remainder;
                payment_remainder = 0.0;
                -- If it is equal then we need to close up the billing line and move to the next
                -- This prevents 0 amounts applied to billing lines
                IF billing_remainder = payment_remainder THEN
                    billing_remainder = 0.0;
                    billing_offset = billing_offset + 1;
                END IF;
            ELSE
                current_result.amount = billing_remainder;
                payment_remainder = payment_remainder - billing_remainder;
                billing_remainder = 0.0;
                billing_offset = billing_offset + 1;
            END IF;

            current_result.amount = -current_result.amount;
            RETURN NEXT current_result;

            EXIT WHEN payment_remainder = 0.0;

        END LOOP;

        payment_offset = payment_offset + 1;
        -- Done paying the billing rows when we run out of rows to pay (out of bounds)
        EXIT WHEN billing_offset = billing_row_count + 1;

    END LOOP;

END;

$$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION money.payment_by_billing_type (
    range_start TIMESTAMPTZ,
    range_end TIMESTAMPTZ,
    location INT
) RETURNS SETOF money.materialized_payment_by_billing_type AS $$

DECLARE
    current_transaction RECORD;
    current_result      money.materialized_payment_by_billing_type%ROWTYPE;
BEGIN

    -- first, we find transactions at specified locations involving
    -- positve, unvoided payments within the specified range
    FOR current_transaction IN
        SELECT  DISTINCT x.id
          FROM  action.circulation x
                JOIN money.payment p ON (x.id = p.xact)
                JOIN actor.org_unit_descendants(location) d
                    ON (d.id = x.circ_lib)
          WHERE p.payment_ts BETWEEN range_start AND range_end
                AND NOT p.voided
                AND p.amount > 0.0
            UNION ALL
        SELECT  DISTINCT x.id
          FROM  money.grocery x
                JOIN money.payment p ON (x.id = p.xact)
                JOIN actor.org_unit_descendants(location) d
                    ON (d.id = x.billing_location)
          WHERE p.payment_ts BETWEEN range_start AND range_end
                AND NOT p.voided
                AND p.amount > 0.0
    LOOP

        -- then, we send each transaction to the payment-by-billing-type
        -- calculator, and return rows for payments we're interested in
        FOR current_result IN
            SELECT * FROM money.payment_by_billing_type( current_transaction.id )
        LOOP
            IF current_result.payment_ts BETWEEN range_start AND range_end THEN
                RETURN NEXT current_result;
            END IF;
        END LOOP;

    END LOOP;

END;

$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION money.payment_by_billing_type_trigger ()
RETURNS TRIGGER AS $$

BEGIN

    IF TG_OP = 'INSERT' THEN
        DELETE FROM money.materialized_payment_by_billing_type
            WHERE xact = NEW.xact;

        INSERT INTO money.materialized_payment_by_billing_type (
            xact, payment, billing, payment_ts, billing_ts,
            payment_type, billing_type, amount, billing_ou, payment_ou
        ) SELECT    xact, payment, billing, payment_ts, billing_ts,
                    payment_type, billing_type, amount, billing_ou, payment_ou
          FROM  money.payment_by_billing_type( NEW.xact );

    ELSIF TG_OP = 'UPDATE' THEN
        DELETE FROM money.materialized_payment_by_billing_type
            WHERE xact IN (OLD.xact,NEW.xact);

        INSERT INTO money.materialized_payment_by_billing_type (
            xact, payment, billing, payment_ts, billing_ts,
            payment_type, billing_type, amount, billing_ou, payment_ou
        ) SELECT    xact, payment, billing, payment_ts, billing_ts,
                    payment_type, billing_type, amount, billing_ou, payment_ou
          FROM money.payment_by_billing_type( NEW.xact );

        IF NEW.xact <> OLD.xact THEN
            INSERT INTO money.materialized_payment_by_billing_type (
                xact, payment, billing, payment_ts, billing_ts,
                payment_type, billing_type, amount, billing_ou, payment_ou
            ) SELECT    xact, payment, billing, payment_ts, billing_ts,
                        payment_type, billing_type, amount, billing_ou, payment_ou
              FROM money.payment_by_billing_type( OLD.xact );
        END IF;

    ELSE
        DELETE FROM money.materialized_payment_by_billing_type
            WHERE xact = OLD.xact;

        INSERT INTO money.materialized_payment_by_billing_type (
            xact, payment, billing, payment_ts, billing_ts,
            payment_type, billing_type, amount, billing_ou, payment_ou
        ) SELECT    xact, payment, billing, payment_ts, billing_ts,
                    payment_type, billing_type, amount, billing_ou, payment_ou
          FROM money.payment_by_billing_type( OLD.xact );

        RETURN OLD;
    END IF;

    RETURN NEW;

END;

$$ LANGUAGE PLPGSQL;


CREATE TRIGGER calculate_payment_by_btype_tgr
    AFTER INSERT OR UPDATE OR DELETE ON money.billing
    FOR EACH ROW EXECUTE PROCEDURE money.payment_by_billing_type_trigger();

CREATE TRIGGER calculate_payment_by_btype_tgr
    AFTER INSERT OR UPDATE OR DELETE ON money.payment
    FOR EACH ROW EXECUTE PROCEDURE money.payment_by_billing_type_trigger();

CREATE TRIGGER calculate_payment_by_btype_tgr
    AFTER INSERT OR UPDATE OR DELETE ON money.bnm_payment
    FOR EACH ROW EXECUTE PROCEDURE money.payment_by_billing_type_trigger();

CREATE TRIGGER calculate_payment_by_btype_tgr
    AFTER INSERT OR UPDATE OR DELETE ON money.forgive_payment
    FOR EACH ROW EXECUTE PROCEDURE money.payment_by_billing_type_trigger();

CREATE TRIGGER calculate_payment_by_btype_tgr
    AFTER INSERT OR UPDATE OR DELETE ON money.work_payment
    FOR EACH ROW EXECUTE PROCEDURE money.payment_by_billing_type_trigger();

CREATE TRIGGER calculate_payment_by_btype_tgr
    AFTER INSERT OR UPDATE OR DELETE ON money.credit_payment
    FOR EACH ROW EXECUTE PROCEDURE money.payment_by_billing_type_trigger();

CREATE TRIGGER calculate_payment_by_btype_tgr
    AFTER INSERT OR UPDATE OR DELETE ON money.goods_payment
    FOR EACH ROW EXECUTE PROCEDURE money.payment_by_billing_type_trigger();

CREATE TRIGGER calculate_payment_by_btype_tgr
    AFTER INSERT OR UPDATE OR DELETE ON money.bnm_desk_payment
    FOR EACH ROW EXECUTE PROCEDURE money.payment_by_billing_type_trigger();

CREATE TRIGGER calculate_payment_by_btype_tgr
    AFTER INSERT OR UPDATE OR DELETE ON money.cash_payment
    FOR EACH ROW EXECUTE PROCEDURE money.payment_by_billing_type_trigger();

CREATE TRIGGER calculate_payment_by_btype_tgr
    AFTER INSERT OR UPDATE OR DELETE ON money.check_payment
    FOR EACH ROW EXECUTE PROCEDURE money.payment_by_billing_type_trigger();

CREATE TRIGGER calculate_payment_by_btype_tgr
    AFTER INSERT OR UPDATE OR DELETE ON money.credit_card_payment
    FOR EACH ROW EXECUTE PROCEDURE money.payment_by_billing_type_trigger();


COMMIT;

