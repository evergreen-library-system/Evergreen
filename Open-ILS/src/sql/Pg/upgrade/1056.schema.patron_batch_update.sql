BEGIN;

INSERT INTO config.upgrade_log (version, applied_to) VALUES ('1056', :eg_version); -- miker/gmcharlt

INSERT INTO permission.perm_list (id,code,description) VALUES (592,'CONTAINER_BATCH_UPDATE','Allow batch update via buckets');

INSERT INTO container.user_bucket_type (code,label) SELECT code,label FROM container.copy_bucket_type where code = 'staff_client';

CREATE TABLE action.fieldset_group (
    id              SERIAL  PRIMARY KEY,
    name            TEXT        NOT NULL,
    create_time     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    complete_time   TIMESTAMPTZ,
    container       INT,        -- Points to a container of some type ...
    container_type  TEXT,       -- One of 'biblio_record_entry', 'user', 'call_number', 'copy'
    can_rollback    BOOL        DEFAULT TRUE,
    rollback_group  INT         REFERENCES action.fieldset_group (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    rollback_time   TIMESTAMPTZ,
    creator         INT         NOT NULL REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    owning_lib      INT         NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

ALTER TABLE action.fieldset ADD COLUMN fieldset_group INT REFERENCES action.fieldset_group (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE action.fieldset ADD COLUMN error_msg TEXT;
ALTER TABLE container.biblio_record_entry_bucket ADD COLUMN owning_lib INT REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE container.user_bucket ADD COLUMN owning_lib INT REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE container.call_number_bucket ADD COLUMN owning_lib INT REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE container.copy_bucket ADD COLUMN owning_lib INT REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

UPDATE query.stored_query SET id = id + 1000 WHERE id < 1000;
UPDATE query.from_relation SET id = id + 1000 WHERE id < 1000;
UPDATE query.expression SET id = id + 1000 WHERE id < 1000;

SELECT SETVAL('query.stored_query_id_seq', 1, FALSE);
SELECT SETVAL('query.from_relation_id_seq', 1, FALSE);
SELECT SETVAL('query.expression_id_seq', 1, FALSE);

INSERT INTO query.bind_variable (name,type,description,label)
    SELECT  'bucket','number','ID of the bucket to pull items from','Bucket ID'
      WHERE NOT EXISTS (SELECT 1 FROM query.bind_variable WHERE name = 'bucket');

-- Assumes completely empty 'query' schema
INSERT INTO query.stored_query (type, use_distinct) VALUES ('SELECT', TRUE); -- 1

INSERT INTO query.from_relation (type, table_name, class_name, table_alias) VALUES ('RELATION', 'container.user_bucket_item', 'cubi', 'cubi'); -- 1
UPDATE query.stored_query SET from_clause = 1;

INSERT INTO query.expr_xcol (table_alias, column_name) VALUES ('cubi', 'target_user'); -- 1
INSERT INTO query.select_item (stored_query,seq_no,expression) VALUES (1,1,1);

INSERT INTO query.expr_xcol (table_alias, column_name) VALUES ('cubi', 'bucket'); -- 2
INSERT INTO query.expr_xbind (bind_variable) VALUES ('bucket'); -- 3

INSERT INTO query.expr_xop (left_operand, operator, right_operand) VALUES (2, '=', 3); -- 4
UPDATE query.stored_query SET where_clause = 4;

SELECT SETVAL('query.stored_query_id_seq', 1000, TRUE) FROM query.stored_query;
SELECT SETVAL('query.from_relation_id_seq', 1000, TRUE) FROM query.from_relation;
SELECT SETVAL('query.expression_id_seq', 10000, TRUE) FROM query.expression;

CREATE OR REPLACE FUNCTION action.apply_fieldset(
    fieldset_id IN INT,        -- id from action.fieldset
    table_name  IN TEXT,       -- table to be updated
    pkey_name   IN TEXT,       -- name of primary key column in that table
    query       IN TEXT        -- query constructed by qstore (for query-based
                               --    fieldsets only; otherwise null
)
RETURNS TEXT AS $$
DECLARE
    statement TEXT;
    where_clause TEXT;
    fs_status TEXT;
    fs_pkey_value TEXT;
    fs_query TEXT;
    sep CHAR;
    status_code TEXT;
    msg TEXT;
    fs_id INT;
    fsg_id INT;
    update_count INT;
    cv RECORD;
    fs_obj action.fieldset%ROWTYPE;
    fs_group action.fieldset_group%ROWTYPE;
    rb_row RECORD;
BEGIN
    -- Sanity checks
    IF fieldset_id IS NULL THEN
        RETURN 'Fieldset ID parameter is NULL';
    END IF;
    IF table_name IS NULL THEN
        RETURN 'Table name parameter is NULL';
    END IF;
    IF pkey_name IS NULL THEN
        RETURN 'Primary key name parameter is NULL';
    END IF;

    SELECT
        status,
        quote_literal( pkey_value )
    INTO
        fs_status,
        fs_pkey_value
    FROM
        action.fieldset
    WHERE
        id = fieldset_id;

    --
    -- Build the WHERE clause.  This differs according to whether it's a
    -- single-row fieldset or a query-based fieldset.
    --
    IF query IS NULL        AND fs_pkey_value IS NULL THEN
        RETURN 'Incomplete fieldset: neither a primary key nor a query available';
    ELSIF query IS NOT NULL AND fs_pkey_value IS NULL THEN
        fs_query := rtrim( query, ';' );
        where_clause := 'WHERE ' || pkey_name || ' IN ( '
                     || fs_query || ' )';
    ELSIF query IS NULL     AND fs_pkey_value IS NOT NULL THEN
        where_clause := 'WHERE ' || pkey_name || ' = ';
        IF pkey_name = 'id' THEN
            where_clause := where_clause || fs_pkey_value;
        ELSIF pkey_name = 'code' THEN
            where_clause := where_clause || quote_literal(fs_pkey_value);
        ELSE
            RETURN 'Only know how to handle "id" and "code" pkeys currently, received ' || pkey_name;
        END IF;
    ELSE  -- both are not null
        RETURN 'Ambiguous fieldset: both a primary key and a query provided';
    END IF;

    IF fs_status IS NULL THEN
        RETURN 'No fieldset found for id = ' || fieldset_id;
    ELSIF fs_status = 'APPLIED' THEN
        RETURN 'Fieldset ' || fieldset_id || ' has already been applied';
    END IF;

    SELECT * INTO fs_obj FROM action.fieldset WHERE id = fieldset_id;
    SELECT * INTO fs_group FROM action.fieldset_group WHERE id = fs_obj.fieldset_group;

    IF fs_group.can_rollback THEN
        -- This is part of a non-rollback group.  We need to record the current values for future rollback.

        INSERT INTO action.fieldset_group (can_rollback, name, creator, owning_lib, container, container_type)
            VALUES (FALSE, 'ROLLBACK: '|| fs_group.name, fs_group.creator, fs_group.owning_lib, fs_group.container, fs_group.container_type);

        fsg_id := CURRVAL('action.fieldset_group_id_seq');

        FOR rb_row IN EXECUTE 'SELECT * FROM ' || table_name || ' ' || where_clause LOOP
            IF pkey_name = 'id' THEN
                fs_pkey_value := rb_row.id;
            ELSIF pkey_name = 'code' THEN
                fs_pkey_value := rb_row.code;
            ELSE
                RETURN 'Only know how to handle "id" and "code" pkeys currently, received ' || pkey_name;
            END IF;
            INSERT INTO action.fieldset (fieldset_group,owner,owning_lib,status,classname,name,pkey_value)
                VALUES (fsg_id, fs_obj.owner, fs_obj.owning_lib, 'PENDING', fs_obj.classname, fs_obj.name || ' ROLLBACK FOR ' || fs_pkey_value, fs_pkey_value);

            fs_id := CURRVAL('action.fieldset_id_seq');
            sep := '';
            FOR cv IN
                SELECT  DISTINCT col
                FROM    action.fieldset_col_val
                WHERE   fieldset = fieldset_id
            LOOP
                EXECUTE 'INSERT INTO action.fieldset_col_val (fieldset, col, val) ' || 
                    'SELECT '|| fs_id || ', '||quote_literal(cv.col)||', '||cv.col||' FROM '||table_name||' WHERE '||pkey_name||' = '||fs_pkey_value;
            END LOOP;
        END LOOP;
    END IF;

    statement := 'UPDATE ' || table_name || ' SET';

    sep := '';
    FOR cv IN
        SELECT  col,
                val
        FROM    action.fieldset_col_val
        WHERE   fieldset = fieldset_id
    LOOP
        statement := statement || sep || ' ' || cv.col
                     || ' = ' || coalesce( quote_literal( cv.val ), 'NULL' );
        sep := ',';
    END LOOP;

    IF sep = '' THEN
        RETURN 'Fieldset ' || fieldset_id || ' has no column values defined';
    END IF;
    statement := statement || ' ' || where_clause;

    --
    -- Execute the update
    --
    BEGIN
        EXECUTE statement;
        GET DIAGNOSTICS update_count = ROW_COUNT;

        IF update_count = 0 THEN
            RAISE data_exception;
        END IF;

        IF fsg_id IS NOT NULL THEN
            UPDATE action.fieldset_group SET rollback_group = fsg_id WHERE id = fs_group.id;
        END IF;

        IF fs_group.id IS NOT NULL THEN
            UPDATE action.fieldset_group SET complete_time = now() WHERE id = fs_group.id;
        END IF;

        UPDATE action.fieldset SET status = 'APPLIED', applied_time = now() WHERE id = fieldset_id;

    EXCEPTION WHEN data_exception THEN
        msg := 'No eligible rows found for fieldset ' || fieldset_id;
        UPDATE action.fieldset SET status = 'ERROR', applied_time = now() WHERE id = fieldset_id;
        RETURN msg;

    END;

    RETURN msg;

EXCEPTION WHEN OTHERS THEN
    msg := 'Unable to apply fieldset ' || fieldset_id || ': ' || sqlerrm;
    UPDATE action.fieldset SET status = 'ERROR', applied_time = now() WHERE id = fieldset_id;
    RETURN msg;

END;
$$ LANGUAGE plpgsql;

COMMIT;

