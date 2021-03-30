BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);


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


-- Now Populate the materialized table

BEGIN;

CREATE OR REPLACE FUNCTION tmp_populate_p_b_bt () RETURNS BOOL AS $$
DECLARE
    p   RECORD;
BEGIN
    FOR p IN
        SELECT  DISTINCT xact
          FROM  money.payment
    LOOP

        INSERT INTO money.materialized_payment_by_billing_type (
            xact, payment, billing, payment_ts, billing_ts,
            payment_type, billing_type, amount, billing_ou, payment_ou
        ) SELECT    xact, payment, billing, payment_ts, billing_ts,
                    payment_type, billing_type, amount, billing_ou, payment_ou
          FROM money.payment_by_billing_type( p.xact );

    END LOOP;

    RETURN TRUE;
END;
$$ LANGUAGE PLPGSQL;

SELECT tmp_populate_p_b_bt();

DROP FUNCTION tmp_populate_p_b_bt ();

COMMIT;
