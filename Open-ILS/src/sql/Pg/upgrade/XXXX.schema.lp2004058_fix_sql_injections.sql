BEGIN;

CREATE OR REPLACE FUNCTION acq.create_acq_seq     ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$CREATE SEQUENCE acq.$$ || quote_ident(sch || $$_$$ || tbl || $$_pkey_seq$$);
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION acq.create_acq_history ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE TABLE acq.$$ || sch || $$_$$ || tbl || $$_history (
            audit_id	BIGINT				PRIMARY KEY,
            audit_time	TIMESTAMP WITH TIME ZONE	NOT NULL,
            audit_action	TEXT				NOT NULL,
            LIKE $$ || quote_ident(sch) || $$.$$ || quote_ident(tbl) || $$
        );
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION acq.create_acq_func    ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE OR REPLACE FUNCTION acq.audit_$$ || quote_ident(sch || $$_$$ || tbl || $$_func$$) || $$ ()
        RETURNS TRIGGER AS $func$
        BEGIN
            INSERT INTO acq.$$ || quote_ident(sch || $$_$$ || tbl || $$_history$$) || $$
                SELECT	nextval($$ || quote_literal($$acq.$$ || sch || $$_$$ || tbl || $$_pkey_seq$$) || $$),
                    now(),
                    SUBSTR(TG_OP,1,1),
                    OLD.*;
            RETURN NULL;
        END;
        $func$ LANGUAGE 'plpgsql';
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION acq.create_acq_update_trigger ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE TRIGGER audit_$$ || quote_ident(sch || $$_$$ || tbl || $$_update_trigger$$) || $$
            AFTER UPDATE OR DELETE ON $$ || quote_ident(sch) || $$.$$ || quote_ident(tbl) || $$ FOR EACH ROW
            EXECUTE PROCEDURE acq.audit_$$ || quote_ident(sch || $$_$$ || tbl || $$_func$$) || $$ ();
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION acq.create_acq_lifecycle     ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE OR REPLACE VIEW acq.$$ || quote_ident(sch || $$_$$ || tbl || $$_lifecycle$$) || $$ AS
            SELECT	-1, now() as audit_time, '-' as audit_action, *
              FROM	$$ || sch || $$.$$ || tbl || $$
                UNION ALL
            SELECT	*
              FROM	acq.$$ || quote_ident(sch || $$_$$ || tbl || $$_history$$) || $$;
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION auditor.create_auditor_seq     ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$CREATE SEQUENCE auditor.$$ || quote_ident(sch || $$_$$ || tbl || $$_pkey_seq$$);
    RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION auditor.create_auditor_history ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE TABLE auditor.$$ || quote_ident(sch || $$_$$ || tbl || $$_history$$) || $$ (
            audit_id	BIGINT				PRIMARY KEY,
            audit_time	TIMESTAMP WITH TIME ZONE	NOT NULL,
            audit_action	TEXT				NOT NULL,
            audit_user  INT,
            audit_ws    INT,
            LIKE $$ || quote_ident(sch) || $$.$$ || quote_ident(tbl) || $$
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
        CREATE OR REPLACE FUNCTION auditor.$$ || quote_ident($$audit_$$ || sch || $$_$$ || tbl || $$_func$$) || $$ ()
        RETURNS TRIGGER AS $func$
        BEGIN
            INSERT INTO auditor.$$ || quote_ident(sch || $$_$$ || tbl || $$_history$$) || $$ ( audit_id, audit_time, audit_action, audit_user, audit_ws, $$
            || array_to_string(column_list, ', ') || $$ )
                SELECT  nextval($$ || quote_literal($$auditor.$$ || sch || $$_$$ || tbl || $$_pkey_seq$$) || $$),
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

CREATE OR REPLACE FUNCTION auditor.create_auditor_update_trigger ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE TRIGGER $$ || quote_ident($$audit_$$ || sch || $$_$$ || tbl || $$_update_trigger$$) || $$
            AFTER UPDATE OR DELETE ON $$ || quote_ident(sch) || $$.$$ || quote_ident(tbl) || $$ FOR EACH ROW
            EXECUTE PROCEDURE auditor.$$ || quote_ident($$audit_$$ || sch || $$_$$ || tbl || $$_func$$) || $$ ();
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
        CREATE VIEW auditor.$$ || quote_ident(sch || $$_$$ || tbl || $$_lifecycle$$) || $$ AS
            SELECT -1 AS audit_id,
                   now() AS audit_time,
                   '-' AS audit_action,
                   -1 AS audit_user,
                   -1 AS audit_ws,
                   $$ || array_to_string(column_list, ', ') || $$
              FROM $$ || quote_ident(sch) || $$.$$ || quote_ident(tbl) || $$
                UNION ALL
            SELECT audit_id, audit_time, audit_action, audit_user, audit_ws,
            $$ || array_to_string(column_list, ', ') || $$
              FROM auditor.$$ || quote_ident(sch || $$_$$ || tbl || $$_history$$) || $$;
    $$;
    RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION asset.label_normalizer() RETURNS TRIGGER AS $func$
DECLARE
    sortkey        TEXT := '';
BEGIN
    sortkey := NEW.label_sortkey;

    IF NEW.label_class IS NULL THEN
            NEW.label_class := COALESCE(
            (   
                SELECT substring(value from E'\\d+')::integer
                FROM actor.org_unit_ancestor_setting('cat.default_classification_scheme', NEW.owning_lib)
            ), 1
        );
    END IF;

    EXECUTE FORMAT('SELECT %s(%L)', acnc.normalizer::REGPROC, NEW.label)
       FROM asset.call_number_class acnc
       WHERE acnc.id = NEW.label_class
       INTO sortkey;
    NEW.label_sortkey = sortkey;
    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

DROP FUNCTION IF EXISTS public.extract_marc_field(TEXT, BIGINT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.extract_marc_field(TEXT, BIGINT, TEXT);

CREATE OR REPLACE FUNCTION evergreen.extract_marc_field ( TEXT, BIGINT, TEXT, TEXT ) RETURNS TEXT AS $$
DECLARE
    query TEXT;
    output TEXT;
BEGIN
    query := FORMAT($q$
        SELECT  regexp_replace(
                    oils_xpath_string(
                        %L,
                        marc,
                        ' '
                    ),
                    %L,
                    '',
                    'g')
          FROM %s
          WHERE id = %L
    $q$, $3, $4, $1::REGCLASS, $2);

    EXECUTE query INTO output;

    -- RAISE NOTICE 'query: %, output; %', query, output;

    RETURN output;
END;
$$ LANGUAGE PLPGSQL IMMUTABLE;

CREATE OR REPLACE FUNCTION evergreen.extract_marc_field ( TEXT, BIGINT, TEXT ) RETURNS TEXT AS $$
    SELECT extract_marc_field($1,$2,$3,'');
$$ LANGUAGE SQL IMMUTABLE;

DROP FUNCTION IF EXISTS unapi.memoize(TEXT, BIGINT, TEXT, TEXT, TEXT[], TEXT, INT, HSTORE, HSTORE, BOOL);

CREATE OR REPLACE FUNCTION actor.usr_merge_rows( table_name TEXT, col_name TEXT, src_usr INT, dest_usr INT ) RETURNS VOID AS $$
DECLARE
    sel TEXT;
    upd TEXT;
    del TEXT;
    cur_row RECORD;
BEGIN
    sel := FORMAT('SELECT id::BIGINT FROM %s WHERE %I = $1', table_name::REGCLASS, col_name);
    upd := FORMAT('UPDATE %s SET %I = $1 WHERE id = $2', table_name::REGCLASS, col_name);
    del := FORMAT('DELETE FROM %s WHERE id = $1', table_name::REGCLASS);
    FOR cur_row IN EXECUTE sel USING src_usr LOOP
        BEGIN
            EXECUTE upd USING dest_usr, cur_row.id;
        EXCEPTION WHEN unique_violation THEN
            EXECUTE del USING cur_row.id;
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS evergreen.change_db_setting(TEXT, TEXT[]);

COMMIT;
