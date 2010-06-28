-- Instead of representing a subfield as a distinct expression type in its
-- own right, express it as a variant of the xfunc type -- i.e. a function
-- call with a column name.  In consequence:

-- 1. Eliminate the query.expr_xfld view;

-- 2. Expand the query.expr_xfunc view to include column_name;

-- 3. Eliminate 'xfld' as a valid value for expression.type.

-- Theoretically, the latter change could create a problem if you already
-- have xfld rows in your expression table.  You would have to delete them,
-- and represent the corresponding expressions by other means.  In practice
-- this is exceedingly unlikely, since subfields were never even
-- supported until earlier today.

-- We start by dropping two views; the first for good, and the second so that
-- we can replace it.  We drop them outside the transaction so that the
-- script won't fail if the views don't exist yet.

DROP VIEW query.expr_xfld;

DROP VIEW query.expr_xfunc;

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0322'); -- Scott McKellar

-- Eliminate 'xfld' as an expression type

ALTER TABLE query.expression
	DROP CONSTRAINT expression_type;

ALTER TABLE query.expression
	ADD CONSTRAINT expression_type CHECK ( type in (
        'xbet',    -- between
        'xbind',   -- bind variable
        'xbool',   -- boolean
        'xcase',   -- case
        'xcast',   -- cast
        'xcol',    -- column
        'xex',     -- exists
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

-- Create updatable view for function call expressions

CREATE OR REPLACE VIEW query.expr_xfunc AS
    SELECT
        id,
        parenthesize,
        parent_expr,
        seq_no,
        column_name,
        function_id,
        negate
    FROM
        query.expression
    WHERE
        type = 'xfunc';

CREATE OR REPLACE RULE query_expr_xfunc_insert_rule AS
    ON INSERT TO query.expr_xfunc
    DO INSTEAD
    INSERT INTO query.expression (
        id,
        type,
        parenthesize,
        parent_expr,
        seq_no,
        column_name,
        function_id,
        negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xfunc',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
        NEW.column_name,
        NEW.function_id,
        COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xfunc_update_rule AS
    ON UPDATE TO query.expr_xfunc
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
        column_name = NEW.column_name,
        function_id = NEW.function_id,
        negate = NEW.negate
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xfunc_delete_rule AS
    ON DELETE TO query.expr_xfunc
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

COMMIT;
