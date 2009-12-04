BEGIN;

-- Create updatable view for BETWEEN expressions

INSERT INTO config.upgrade_log (version) VALUES ('0107'); -- Scott McKellar

CREATE OR REPLACE VIEW query.expr_xbet AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no
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
		seq_no
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xbet',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1)
    );

CREATE OR REPLACE RULE query_expr_xbet_update_rule AS
    ON UPDATE TO query.expr_xbet
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xbet_delete_rule AS
    ON DELETE TO query.expr_xbet
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for boolean expressions

CREATE OR REPLACE VIEW query.expr_xbool AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		literal
    FROM
        query.expression
    WHERE
        type = 'xbool';

CREATE OR REPLACE RULE query_expr_xbool_insert_rule AS
    ON INSERT TO query.expr_xbool
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		literal
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xbool',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
        NEW.literal
    );

CREATE OR REPLACE RULE query_expr_xbool_update_rule AS
    ON UPDATE TO query.expr_xbool
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
        literal = NEW.literal
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xbool_delete_rule AS
    ON DELETE TO query.expr_xbool
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for CASE expressions

CREATE OR REPLACE VIEW query.expr_xcase AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no
    FROM
        query.expression
    WHERE
        type = 'xcase';

CREATE OR REPLACE RULE query_expr_xcase_insert_rule AS
    ON INSERT TO query.expr_xcase
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xcase',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1)
    );

CREATE OR REPLACE RULE query_expr_xcase_update_rule AS
    ON UPDATE TO query.expr_xcase
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xcase_delete_rule AS
    ON DELETE TO query.expr_xcase
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for cast expressions

CREATE OR REPLACE VIEW query.expr_xcast AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		cast_type
    FROM
        query.expression
    WHERE
        type = 'xcast';

CREATE OR REPLACE RULE query_expr_xcast_insert_rule AS
    ON INSERT TO query.expr_xcast
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		cast_type
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xcast',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.left_operand,
		NEW.cast_type
    );

CREATE OR REPLACE RULE query_expr_xcast_update_rule AS
    ON UPDATE TO query.expr_xcast
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		left_operand = NEW.left_operand,
		cast_type = NEW.cast_type
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xcast_delete_rule AS
    ON DELETE TO query.expr_xcast
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for column expressions

CREATE OR REPLACE VIEW query.expr_xcol AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		table_alias,
		column_name
    FROM
        query.expression
    WHERE
        type = 'xcol';

CREATE OR REPLACE RULE query_expr_xcol_insert_rule AS
    ON INSERT TO query.expr_xcol
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		table_alias,
		column_name
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xcol',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.table_alias,
		NEW.column_name
    );

CREATE OR REPLACE RULE query_expr_xcol_update_rule AS
    ON UPDATE TO query.expr_xcol
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		table_alias = NEW.table_alias,
		column_name = NEW.column_name
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xcol_delete_rule AS
    ON DELETE TO query.expr_xcol
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for EXISTS expressions

CREATE OR REPLACE VIEW query.expr_xex AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		subquery
    FROM
        query.expression
    WHERE
        type = 'xex';

CREATE OR REPLACE RULE query_expr_xex_insert_rule AS
    ON INSERT TO query.expr_xex
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		subquery
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xex',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.subquery
    );

CREATE OR REPLACE RULE query_expr_xex_update_rule AS
    ON UPDATE TO query.expr_xex
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		subquery = NEW.subquery
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xex_delete_rule AS
    ON DELETE TO query.expr_xex
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for field expressions

CREATE OR REPLACE VIEW query.expr_xfld AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		column_name,
		left_operand
    FROM
        query.expression
    WHERE
        type = 'xfld';

CREATE OR REPLACE RULE query_expr_xfld_insert_rule AS
    ON INSERT TO query.expr_xfld
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		column_name,
		left_operand
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xfld',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.column_name,
		NEW.left_operand
    );

CREATE OR REPLACE RULE query_expr_xfld_update_rule AS
    ON UPDATE TO query.expr_xfld
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		column_name = NEW.column_name,
		left_operand = NEW.left_operand
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xfld_delete_rule AS
    ON DELETE TO query.expr_xfld
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for function call expressions

CREATE OR REPLACE VIEW query.expr_xfunc AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		function_id
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
		function_id
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xfunc',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.function_id
    );

CREATE OR REPLACE RULE query_expr_xfunc_update_rule AS
    ON UPDATE TO query.expr_xfunc
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		function_id = NEW.function_id
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xfunc_delete_rule AS
    ON DELETE TO query.expr_xfunc
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for IN expressions

CREATE OR REPLACE VIEW query.expr_xin AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		subquery
    FROM
        query.expression
    WHERE
        type = 'xin';

CREATE OR REPLACE RULE query_expr_xin_insert_rule AS
    ON INSERT TO query.expr_xin
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		subquery
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xin',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.subquery
    );

CREATE OR REPLACE RULE query_expr_xin_update_rule AS
    ON UPDATE TO query.expr_xin
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		subquery = NEW.subquery
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xin_delete_rule AS
    ON DELETE TO query.expr_xin
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for NOT BETWEEN expressions

CREATE OR REPLACE VIEW query.expr_xnbet AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no
    FROM
        query.expression
    WHERE
        type = 'xnbet';

CREATE OR REPLACE RULE query_expr_xnbet_insert_rule AS
    ON INSERT TO query.expr_xnbet
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xnbet',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1)
    );

CREATE OR REPLACE RULE query_expr_xnbet_update_rule AS
    ON UPDATE TO query.expr_xnbet
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xnbet_delete_rule AS
    ON DELETE TO query.expr_xnbet
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for NOT EXISTS expressions

CREATE OR REPLACE VIEW query.expr_xnex AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		subquery
    FROM
        query.expression
    WHERE
        type = 'xnex';

CREATE OR REPLACE RULE query_expr_xnex_insert_rule AS
    ON INSERT TO query.expr_xnex
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		subquery
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xnex',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.subquery
    );

CREATE OR REPLACE RULE query_expr_xnex_update_rule AS
    ON UPDATE TO query.expr_xnex
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		subquery = NEW.subquery
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xnex_delete_rule AS
    ON DELETE TO query.expr_xnex
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for NOT IN expressions

CREATE OR REPLACE VIEW query.expr_xnin AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		subquery
    FROM
        query.expression
    WHERE
        type = 'xnin';

CREATE OR REPLACE RULE query_expr_xnin_insert_rule AS
    ON INSERT TO query.expr_xnin
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		subquery
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xnin',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.subquery
    );

CREATE OR REPLACE RULE query_expr_xnin_update_rule AS
    ON UPDATE TO query.expr_xnin
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		subquery = NEW.subquery
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xnin_delete_rule AS
    ON DELETE TO query.expr_xnin
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for NULL expressions

CREATE OR REPLACE VIEW query.expr_xnull AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no
    FROM
        query.expression
    WHERE
        type = 'xnull';

CREATE OR REPLACE RULE query_expr_xnull_insert_rule AS
    ON INSERT TO query.expr_xnull
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xnull',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1)
    );

CREATE OR REPLACE RULE query_expr_xnull_update_rule AS
    ON UPDATE TO query.expr_xnull
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xnull_delete_rule AS
    ON DELETE TO query.expr_xnull
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for numeric literal expressions

CREATE OR REPLACE VIEW query.expr_xnum AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		literal
    FROM
        query.expression
    WHERE
        type = 'xnum';

CREATE OR REPLACE RULE query_expr_xnum_insert_rule AS
    ON INSERT TO query.expr_xnum
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		literal
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xnum',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
        NEW.literal
    );

CREATE OR REPLACE RULE query_expr_xnum_update_rule AS
    ON UPDATE TO query.expr_xnum
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
        literal = NEW.literal
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xnum_delete_rule AS
    ON DELETE TO query.expr_xnum
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for operator expressions

CREATE OR REPLACE VIEW query.expr_xop AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		operator,
		right_operand
    FROM
        query.expression
    WHERE
        type = 'xop';

CREATE OR REPLACE RULE query_expr_xop_insert_rule AS
    ON INSERT TO query.expr_xop
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		operator,
		right_operand
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xop',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.left_operand,
		NEW.operator,
		NEW.right_operand
    );

CREATE OR REPLACE RULE query_expr_xop_update_rule AS
    ON UPDATE TO query.expr_xop
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		left_operand = NEW.left_operand,
		operator = NEW.operator,
		right_operand = NEW.right_operand
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xop_delete_rule AS
    ON DELETE TO query.expr_xop
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

-- Create updatable view for subquery expressions

CREATE OR REPLACE VIEW query.expr_xsubq AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		subquery
    FROM
        query.expression
    WHERE
        type = 'xsubq';

CREATE OR REPLACE RULE query_expr_xsubq_insert_rule AS
    ON INSERT TO query.expr_xsubq
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		subquery
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xsubq',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.subquery
    );

CREATE OR REPLACE RULE query_expr_xsubq_update_rule AS
    ON UPDATE TO query.expr_xsubq
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		subquery = NEW.subquery
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xsubq_delete_rule AS
    ON DELETE TO query.expr_xsubq
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

COMMIT;
