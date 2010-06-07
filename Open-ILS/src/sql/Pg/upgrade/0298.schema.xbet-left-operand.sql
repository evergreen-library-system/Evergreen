BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0298'); -- Scott McKellar

-- Create updatable view for BETWEEN expressions

DROP VIEW query.expr_xbet CASCADE;

CREATE OR REPLACE VIEW query.expr_xbet AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		negate
    FROM
        query.expression
    WHERE
        type = 'xbet';

CREATE OR REPLACE RULE query_expr_xbet_insert_rule AS
    ON INSERT TO query.expr_xbet
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xbet',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.left_operand,
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xbet_update_rule AS
    ON UPDATE TO query.expr_xbet
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		left_operand = NEW.left_operand,
		negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xbet_delete_rule AS
    ON DELETE TO query.expr_xbet
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

COMMIT;
