BEGIN;

-- Create new expression type 'xser' for serial expressions,
-- i.e. series of expressions separated by operators

INSERT INTO config.upgrade_log (version) VALUES ('0280'); -- Scott McKellar

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
         'xisnull', -- is null
         'xnull',   -- null
         'xnum',    -- number
         'xop',     -- operator
         'xser',    -- series
         'xstr',    -- string
         'xsubq'    -- subquery
    ) );

-- Create updatable view for series expressions

CREATE OR REPLACE VIEW query.expr_xser AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		operator,
		negate
    FROM
        query.expression
    WHERE
        type = 'xser';

CREATE OR REPLACE RULE query_expr_xser_insert_rule AS
    ON INSERT TO query.expr_xser
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		operator,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xser',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.operator,
		NEW.negate
    );

CREATE OR REPLACE RULE query_expr_xser_update_rule AS
    ON UPDATE TO query.expr_xser
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		operator = NEW.operator,
		negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xser_delete_rule AS
    ON DELETE TO query.expr_xser
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

COMMIT;
