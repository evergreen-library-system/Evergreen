BEGIN;

-- For various updatable views based on query.expression:
-- add COALESCE to the insert rule so that we don't always
-- have to specify a value for the "negate" column.

INSERT INTO config.upgrade_log (version) VALUES ('0286'); -- Scott McKellar

CREATE OR REPLACE RULE query_expr_xbet_insert_rule AS
    ON INSERT TO query.expr_xbet
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xbet',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xbool_insert_rule AS
    ON INSERT TO query.expr_xbool
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		literal,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xbool',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
        NEW.literal,
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xcase_insert_rule AS
    ON INSERT TO query.expr_xcase
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xcase',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		COALESCE(NEW.negate, false)
    );

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
		cast_type,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xcast',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.left_operand,
		NEW.cast_type,
		COALESCE(NEW.negate, false)
    );

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
		column_name,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xcol',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.table_alias,
		NEW.column_name,
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xex_insert_rule AS
    ON INSERT TO query.expr_xex
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		subquery,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xex',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.subquery,
		COALESCE(NEW.negate, false)
    );

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
		left_operand,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xfld',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.column_name,
		NEW.left_operand,
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xfunc_insert_rule AS
    ON INSERT TO query.expr_xfunc
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		function_id,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xfunc',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.function_id,
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xin_insert_rule AS
    ON INSERT TO query.expr_xin
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		left_operand,
		subquery,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xin',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.left_operand,
		NEW.subquery,
		COALESCE(NEW.negate, false)
    );

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
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xnull_insert_rule AS
    ON INSERT TO query.expr_xnull
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xnull',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		COALESCE(NEW.negate, false)
    );

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
		right_operand,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xop',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.left_operand,
		NEW.operator,
		NEW.right_operand,
		COALESCE(NEW.negate, false)
    );

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
		COALESCE(NEW.negate, false)
    );

CREATE OR REPLACE RULE query_expr_xsubq_insert_rule AS
    ON INSERT TO query.expr_xsubq
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		subquery,
		negate
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xsubq',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.subquery,
		COALESCE(NEW.negate, false)
    );

COMMIT;
