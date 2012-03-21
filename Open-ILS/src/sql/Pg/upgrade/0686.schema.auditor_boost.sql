-- Evergreen DB patch 0686.schema.auditor_boost.sql
--
-- FIXME: insert description of change, if needed
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0686', :eg_version);

-- FIXME: add/check SQL statements to perform the upgrade
-- These three functions are for capturing, getting, and clearing user and workstation information

-- Set the User AND workstation in one call. Tis faster. And less calls.
-- First argument is user, second is workstation
CREATE OR REPLACE FUNCTION auditor.set_audit_info(INT, INT) RETURNS VOID AS $$
    $_SHARED{"eg_audit_user"} = $_[0];
    $_SHARED{"eg_audit_ws"} = $_[1];
$$ LANGUAGE plperl;

-- Get the User AND workstation in one call. Less calls, useful for joins ;)
CREATE OR REPLACE FUNCTION auditor.get_audit_info() RETURNS TABLE (eg_user INT, eg_ws INT) AS $$
    return [{eg_user => $_SHARED{"eg_audit_user"}, eg_ws => $_SHARED{"eg_audit_ws"}}];
$$ LANGUAGE plperl;

-- Clear the audit info, for whatever reason
CREATE OR REPLACE FUNCTION auditor.clear_audit_info() RETURNS VOID AS $$
    delete($_SHARED{"eg_audit_user"});
    delete($_SHARED{"eg_audit_ws"});
$$ LANGUAGE plperl;

CREATE OR REPLACE FUNCTION auditor.create_auditor_history ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE TABLE auditor.$$ || sch || $$_$$ || tbl || $$_history (
            audit_id	BIGINT				PRIMARY KEY,
            audit_time	TIMESTAMP WITH TIME ZONE	NOT NULL,
            audit_action	TEXT				NOT NULL,
            audit_user  INT,
            audit_ws    INT,
            LIKE $$ || sch || $$.$$ || tbl || $$
        );
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION auditor.create_auditor_func    ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
DECLARE
    column_list TEXT[];
BEGIN
    SELECT INTO column_list array_agg(a.attname)
        FROM pg_catalog.pg_attribute a
            JOIN pg_catalog.pg_class c ON a.attrelid = c.oid
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        WHERE relkind = 'r' AND n.nspname = sch AND c.relname = tbl AND a.attnum > 0 AND NOT a.attisdropped;

    EXECUTE $$
        CREATE OR REPLACE FUNCTION auditor.audit_$$ || sch || $$_$$ || tbl || $$_func ()
        RETURNS TRIGGER AS $func$
        BEGIN
            INSERT INTO auditor.$$ || sch || $$_$$ || tbl || $$_history ( audit_id, audit_time, audit_action, audit_user, audit_ws, $$
            || array_to_string(column_list, ', ') || $$ )
                SELECT  nextval('auditor.$$ || sch || $$_$$ || tbl || $$_pkey_seq'),
                    now(),
                    SUBSTR(TG_OP,1,1),
                    eg_user,
                    eg_ws,
                    OLD.$$ || array_to_string(column_list, ', OLD.') || $$
                FROM auditor.get_audit_info();
            RETURN NULL;
        END;
        $func$ LANGUAGE 'plpgsql';
    $$;
    RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION auditor.create_auditor_lifecycle     ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
DECLARE
    column_list TEXT[];
BEGIN
    SELECT INTO column_list array_agg(a.attname)
        FROM pg_catalog.pg_attribute a
            JOIN pg_catalog.pg_class c ON a.attrelid = c.oid
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        WHERE relkind = 'r' AND n.nspname = sch AND c.relname = tbl AND a.attnum > 0 AND NOT a.attisdropped;

    EXECUTE $$
        CREATE VIEW auditor.$$ || sch || $$_$$ || tbl || $$_lifecycle AS
            SELECT -1 AS audit_id,
                   now() AS audit_time,
                   '-' AS audit_action,
                   -1 AS audit_user,
                   -1 AS audit_ws,
                   $$ || array_to_string(column_list, ', ') || $$
              FROM $$ || sch || $$.$$ || tbl || $$
                UNION ALL
            SELECT audit_id, audit_time, audit_action, audit_user, audit_ws,
            $$ || array_to_string(column_list, ', ') || $$
              FROM auditor.$$ || sch || $$_$$ || tbl || $$_history;
    $$;
    RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

-- Corrects all column discrepencies between audit table and core table:
-- Adds missing columns
-- Removes leftover columns
-- Updates types
-- Also, ensures all core auditor columns exist.
CREATE OR REPLACE FUNCTION auditor.fix_columns() RETURNS VOID AS $BODY$
DECLARE
    current_table TEXT = ''; -- Storage for post-loop main table name
    current_audit_table TEXT = ''; -- Storage for post-loop audit table name
    query TEXT = ''; -- Storage for built query
    cr RECORD; -- column record object
    alter_t BOOL = false; -- Has the alter table command been appended yet
    auditor_cores TEXT[] = ARRAY[]::TEXT[]; -- Core auditor function list (filled inside of loop)
    core_column TEXT; -- The current core column we are adding
BEGIN
    FOR cr IN
        WITH audit_tables AS ( -- Basic grab of auditor tables. Anything in the auditor namespace, basically. With oids.
            SELECT c.oid AS audit_oid, c.relname AS audit_table
            FROM pg_catalog.pg_class c
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            WHERE relkind='r' AND nspname = 'auditor'
        ),
        table_set AS ( -- Union of auditor tables with their "main" tables. With oids.
            SELECT a.audit_oid, a.audit_table, c.oid AS main_oid, n.nspname as main_namespace, c.relname as main_table
            FROM pg_catalog.pg_class c
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            JOIN audit_tables a ON a.audit_table = n.nspname || '_' || c.relname || '_history'
            WHERE relkind = 'r'
        ),
        column_lists AS ( -- All columns associated with the auditor or main table, grouped by the main table's oid.
            SELECT DISTINCT ON (main_oid, attname) t.main_oid, a.attname
            FROM table_set t
            JOIN pg_catalog.pg_attribute a ON a.attrelid IN (t.main_oid, t.audit_oid)
            WHERE attnum > 0 AND NOT attisdropped
        ),
        column_defs AS ( -- The motherload, every audit table and main table plus column names and defs.
            SELECT audit_table,
                   main_namespace,
                   main_table,
                   a.attname AS main_column, -- These two will be null for columns that have since been deleted, or for auditor core columns
                   pg_catalog.format_type(a.atttypid, a.atttypmod) AS main_column_def,
                   b.attname AS audit_column, -- These two will be null for columns that have since been added
                   pg_catalog.format_type(b.atttypid, b.atttypmod) AS audit_column_def
            FROM table_set t
            JOIN column_lists c USING (main_oid)
            LEFT JOIN pg_catalog.pg_attribute a ON a.attname = c.attname AND a.attrelid = t.main_oid AND a.attnum > 0 AND NOT a.attisdropped
            LEFT JOIN pg_catalog.pg_attribute b ON b.attname = c.attname AND b.attrelid = t.audit_oid AND b.attnum > 0 AND NOT b.attisdropped
        )
        -- Nice sorted output from the above
        SELECT * FROM column_defs WHERE main_column_def IS DISTINCT FROM audit_column_def ORDER BY main_namespace, main_table, main_column, audit_column
    LOOP
        IF current_table <> (cr.main_namespace || '.' || cr.main_table) THEN -- New table?
            FOR core_column IN SELECT DISTINCT unnest(auditor_cores) LOOP -- Update missing core auditor columns
                IF NOT alter_t THEN -- Add ALTER TABLE if we haven't already
                    query:=query || $$ALTER TABLE auditor.$$ || current_audit_table;
                    alter_t:=TRUE;
                ELSE
                    query:=query || $$,$$;
                END IF;
                -- Bit of a sneaky bit here. Create audit_id as a bigserial so it gets automatic values and doesn't complain about nulls when becoming a PRIMARY KEY.
                query:=query || $$ ADD COLUMN $$ || CASE WHEN core_column = 'audit_id bigint' THEN $$audit_id bigserial PRIMARY KEY$$ ELSE core_column END;
            END LOOP;
            IF alter_t THEN -- Open alter table = needs a semicolon
                query:=query || $$; $$;
                alter_t:=FALSE;
                IF 'audit_id bigint' = ANY(auditor_cores) THEN -- We added a primary key...
                    -- Fun! Drop the default on audit_id, drop the auto-created sequence, create a new one, and set the current value
                    -- For added fun, we have to execute in chunks due to the parser checking setval/currval arguments at parse time.
                    EXECUTE query;
                    EXECUTE $$ALTER TABLE auditor.$$ || current_audit_table || $$ ALTER COLUMN audit_id DROP DEFAULT; $$ ||
                        $$CREATE SEQUENCE auditor.$$ || current_audit_table || $$_pkey_seq;$$;
                    EXECUTE $$SELECT setval('auditor.$$ || current_audit_table || $$_pkey_seq', currval('auditor.$$ || current_audit_table || $$_audit_id_seq')); $$ ||
                        $$DROP SEQUENCE auditor.$$ || current_audit_table || $$_audit_id_seq;$$;
                    query:='';
                END IF;
            END IF;
            -- New table means we reset the list of needed auditor core columns
            auditor_cores = ARRAY['audit_id bigint', 'audit_time timestamp with time zone', 'audit_action text', 'audit_user integer', 'audit_ws integer'];
            -- And store some values for use later, because we can't rely on cr in all places.
            current_table:=cr.main_namespace || '.' || cr.main_table;
            current_audit_table:=cr.audit_table;
        END IF;
        IF cr.main_column IS NULL AND cr.audit_column LIKE 'audit_%' THEN -- Core auditor column?
            -- Remove core from list of cores
            SELECT INTO auditor_cores array_agg(core) FROM unnest(auditor_cores) AS core WHERE core != (cr.audit_column || ' ' || cr.audit_column_def);
        ELSIF cr.main_column IS NULL THEN -- Main column doesn't exist, and it isn't an auditor column. Needs dropping from the auditor.
            IF NOT alter_t THEN
                query:=query || $$ALTER TABLE auditor.$$ || current_audit_table;
                alter_t:=TRUE;
            ELSE
                query:=query || $$,$$;
            END IF;
            query:=query || $$ DROP COLUMN $$ || cr.audit_column;
        ELSIF cr.audit_column IS NULL AND cr.main_column IS NOT NULL THEN -- New column auditor doesn't have. Add it.
            IF NOT alter_t THEN
                query:=query || $$ALTER TABLE auditor.$$ || current_audit_table;
                alter_t:=TRUE;
            ELSE
                query:=query || $$,$$;
            END IF;
            query:=query || $$ ADD COLUMN $$ || cr.main_column || $$ $$ || cr.main_column_def;
        ELSIF cr.main_column IS NOT NULL AND cr.audit_column IS NOT NULL THEN -- Both sides have this column, but types differ. Fix that.
            IF NOT alter_t THEN
                query:=query || $$ALTER TABLE auditor.$$ || current_audit_table;
                alter_t:=TRUE;
            ELSE
                query:=query || $$,$$;
            END IF;
            query:=query || $$ ALTER COLUMN $$ || cr.audit_column || $$ TYPE $$ || cr.main_column_def;
        END IF;
    END LOOP;
    FOR core_column IN SELECT DISTINCT unnest(auditor_cores) LOOP -- Repeat this outside of the loop to catch the last table
        IF NOT alter_t THEN
            query:=query || $$ALTER TABLE auditor.$$ || current_audit_table;
            alter_t:=TRUE;
        ELSE
            query:=query || $$,$$;
        END IF;
        -- Bit of a sneaky bit here. Create audit_id as a bigserial so it gets automatic values and doesn't complain about nulls when becoming a PRIMARY KEY.
        query:=query || $$ ADD COLUMN $$ || CASE WHEN core_column = 'audit_id bigint' THEN $$audit_id bigserial PRIMARY KEY$$ ELSE core_column END;
    END LOOP;
    IF alter_t THEN -- Open alter table = needs a semicolon
        query:=query || $$;$$;
        IF 'audit_id bigint' = ANY(auditor_cores) THEN -- We added a primary key...
            -- Fun! Drop the default on audit_id, drop the auto-created sequence, create a new one, and set the current value
            -- For added fun, we have to execute in chunks due to the parser checking setval/currval arguments at parse time.
            EXECUTE query;
            EXECUTE $$ALTER TABLE auditor.$$ || current_audit_table || $$ ALTER COLUMN audit_id DROP DEFAULT; $$ ||
                $$CREATE SEQUENCE auditor.$$ || current_audit_table || $$_pkey_seq;$$;
            EXECUTE $$SELECT setval('auditor.$$ || current_audit_table || $$_pkey_seq', currval('auditor.$$ || current_audit_table || $$_audit_id_seq')); $$ ||
                $$DROP SEQUENCE auditor.$$ || current_audit_table || $$_audit_id_seq;$$;
            query:='';
        END IF;
    END IF;
    EXECUTE query;
END;
$BODY$ LANGUAGE plpgsql;

-- Update it all routine
CREATE OR REPLACE FUNCTION auditor.update_auditors() RETURNS boolean AS $BODY$
DECLARE
    auditor_name TEXT;
    table_schema TEXT;
    table_name TEXT;
BEGIN
    -- Drop Lifecycle view(s) before potential column changes
    FOR auditor_name IN
        SELECT c.relname
            FROM pg_catalog.pg_class c
                JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            WHERE relkind = 'v' AND n.nspname = 'auditor' LOOP
        EXECUTE $$ DROP VIEW auditor.$$ || auditor_name || $$;$$;
    END LOOP;
    -- Fix all column discrepencies
    PERFORM auditor.fix_columns();
    -- Re-create trigger functions and lifecycle views
    FOR table_schema, table_name IN
        WITH audit_tables AS (
            SELECT c.oid AS audit_oid, c.relname AS audit_table
            FROM pg_catalog.pg_class c
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            WHERE relkind='r' AND nspname = 'auditor'
        ),
        table_set AS (
            SELECT a.audit_oid, a.audit_table, c.oid AS main_oid, n.nspname as main_namespace, c.relname as main_table
            FROM pg_catalog.pg_class c
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            JOIN audit_tables a ON a.audit_table = n.nspname || '_' || c.relname || '_history'
            WHERE relkind = 'r'
        )
        SELECT main_namespace, main_table FROM table_set LOOP
        
        PERFORM auditor.create_auditor_func(table_schema, table_name);
        PERFORM auditor.create_auditor_lifecycle(table_schema, table_name);
    END LOOP;
    RETURN TRUE;
END;
$BODY$ LANGUAGE plpgsql;

-- Go ahead and update them all now
SELECT auditor.update_auditors();


COMMIT;
