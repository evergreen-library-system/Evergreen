/*
 * Copyright (C) 2004-2008  Georgia Public Library Service
 * Copyright (C) 2007-2008  Equinox Software, Inc.
 * Mike Rylander <miker@esilibrary.com> 
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 */

DROP SCHEMA IF EXISTS auditor CASCADE;

BEGIN;

CREATE SCHEMA auditor;

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

