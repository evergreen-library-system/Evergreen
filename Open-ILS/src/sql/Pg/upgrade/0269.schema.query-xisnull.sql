BEGIN;

-- Create new expression type for IS [NOT] NULL

INSERT INTO config.upgrade_log (version) VALUES ('0269'); -- Scott McKellar

ALTER TABLE query.expression
	DROP CONSTRAINT expression_type;

ALTER TABLE query.expression
	ADD CONSTRAINT expression_type CHECK
    ( type IN (
		'xbet',    -- between
		'xbind',   -- bind variable
		'xbool',   -- boolean
		'xcase',   -- case
		'xcast',   -- cast
		'xcol',    -- column
		'xex',     -- exists
		'xfld',    -- field
		'xfunc',   -- function
		'xin',     -- in
		'xisnull'  -- is null
		'xnull',   -- null
		'xnum',    -- number
		'xop',     -- operator
		'xstr',    -- string
		'xsubq'    -- subquery
	) );

-- Create updatable view for IS NULL expressions

CREATE OR REPLACE VIEW query.expr_xisnull AS
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
        type = 'xisnull';

CREATE OR REPLACE RULE query_expr_xisnull_insert_rule AS
    ON INSERT TO query.expr_xisnull
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
        'xisnull',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.left_operand,
		NEW.negate
    );

CREATE OR REPLACE RULE query_expr_xisnull_update_rule AS
    ON UPDATE TO query.expr_xisnull
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

CREATE OR REPLACE RULE query_expr_xisnull_delete_rule AS
    ON DELETE TO query.expr_xisnull
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

COMMIT;
