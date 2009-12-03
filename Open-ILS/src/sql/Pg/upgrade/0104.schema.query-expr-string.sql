BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0104'); -- Scott McKellar

-- Create updatable view

CREATE OR REPLACE VIEW query.expr_string AS
    SELECT
        id,
        parenthesize,
        parent_expr,
        seq_no,
        literal
    FROM
        query.expression
    WHERE
        type = 'xstr';

CREATE OR REPLACE RULE query_expr_string_insert_rule AS
    ON INSERT TO query.expr_string
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
        'xstr',
        COALESCE(NEW.parenthesize, FALSE),
        NEW.parent_expr,
        COALESCE(NEW.seq_no, 1),
        NEW.literal
    );

CREATE OR REPLACE RULE query_expr_string_update_rule AS
    ON UPDATE TO query.expr_string
    DO INSTEAD
    UPDATE query.expression SET
        id = NEW.id,
        parenthesize = NEW.parenthesize,
        parent_expr = NEW.parent_expr,
        seq_no = NEW.seq_no,
        literal = NEW.literal
    WHERE
        id = OLD.id;

CREATE OR REPLACE RULE query_expr_string_delete_rule AS
    ON DELETE TO query.expr_string
    DO INSTEAD
    DELETE FROM query.expression WHERE id = OLD.id;

COMMIT;
