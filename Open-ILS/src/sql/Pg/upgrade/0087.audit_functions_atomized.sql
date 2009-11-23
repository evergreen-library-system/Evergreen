/*
 * Copyright (C) 2009 Equinox Software, Inc.
 * Joe Atzberger
 *
 * Released under GNU General Public License version 2
 */

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0087'); -- atz

CREATE FUNCTION auditor.create_auditor_seq     ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE SEQUENCE auditor.$$ || sch || $$_$$ || tbl || $$_pkey_seq;
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE FUNCTION auditor.create_auditor_history ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE TABLE auditor.$$ || sch || $$_$$ || tbl || $$_history (
            audit_id	BIGINT				PRIMARY KEY,
            audit_time	TIMESTAMP WITH TIME ZONE	NOT NULL,
            audit_action	TEXT				NOT NULL,
            LIKE $$ || sch || $$.$$ || tbl || $$
        );
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE FUNCTION auditor.create_auditor_func    ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE FUNCTION auditor.audit_$$ || sch || $$_$$ || tbl || $$_func ()
        RETURNS TRIGGER AS $func$
        BEGIN
            INSERT INTO auditor.$$ || sch || $$_$$ || tbl || $$_history
                SELECT	nextval('auditor.$$ || sch || $$_$$ || tbl || $$_pkey_seq'),
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

CREATE FUNCTION auditor.create_auditor_update_trigger ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE TRIGGER audit_$$ || sch || $$_$$ || tbl || $$_update_trigger
            AFTER UPDATE OR DELETE ON $$ || sch || $$.$$ || tbl || $$ FOR EACH ROW
            EXECUTE PROCEDURE auditor.audit_$$ || sch || $$_$$ || tbl || $$_func ();
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE FUNCTION auditor.create_auditor_lifecycle     ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE VIEW auditor.$$ || sch || $$_$$ || tbl || $$_lifecycle AS
            SELECT	-1, now() as audit_time, '-' as audit_action, *
              FROM	$$ || sch || $$.$$ || tbl || $$
                UNION ALL
            SELECT	*
              FROM	auditor.$$ || sch || $$_$$ || tbl || $$_history;
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

DROP FUNCTION IF EXISTS auditor.create_auditor (TEXT, TEXT); -- Besides this line and the 0087 INSERT, the rest of this file is 900.audit-functions.sql

-- The main event

CREATE FUNCTION auditor.create_auditor ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    PERFORM auditor.create_auditor_seq(sch, tbl);
    PERFORM auditor.create_auditor_history(sch, tbl);
    PERFORM auditor.create_auditor_func(sch, tbl);
    PERFORM auditor.create_auditor_update_trigger(sch, tbl);
    PERFORM auditor.create_auditor_lifecycle(sch, tbl);
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

COMMIT;

