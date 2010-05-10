BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0256'); -- Scott McKellar

-- Create updatable view for bind variable expressions

CREATE OR REPLACE VIEW query.expr_xbind AS
    SELECT
		id,
		parenthesize,
		parent_expr,
		seq_no,
		bind_variable
    FROM
        query.expression
    WHERE
        type = 'xbind';

CREATE OR REPLACE RULE query_expr_xbind_insert_rule AS
    ON INSERT TO query.expr_xbind
    DO INSTEAD
    INSERT INTO query.expression (
		id,
		type,
		parenthesize,
		parent_expr,
		seq_no,
		bind_variable
    ) VALUES (
        COALESCE(NEW.id, NEXTVAL('query.expression_id_seq'::REGCLASS)),
        'xbind',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
		NEW.bind_variable
    );

CREATE OR REPLACE RULE query_expr_xbind_update_rule AS
    ON UPDATE TO query.expr_xbind
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
		bind_variable = NEW.bind_variable
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_xbind_delete_rule AS
    ON DELETE TO query.expr_xbind
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

COMMIT;
