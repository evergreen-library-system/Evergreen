/*
 * Copyright (C) 2004-2008  Georgia Public Library Service
 * Copyright (C) 2007-2008  Equinox Software, Inc.
 * Scott McKellar <scott@esilibrary.com> 
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

BEGIN;

CREATE OR REPLACE FUNCTION acq.create_acq_seq     ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE SEQUENCE acq.$$ || sch || $$_$$ || tbl || $$_pkey_seq;
    $$;
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
            LIKE $$ || sch || $$.$$ || tbl || $$
        );
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION acq.create_acq_func    ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE OR REPLACE FUNCTION acq.audit_$$ || sch || $$_$$ || tbl || $$_func ()
        RETURNS TRIGGER AS $func$
        BEGIN
            INSERT INTO acq.$$ || sch || $$_$$ || tbl || $$_history
                SELECT	nextval('acq.$$ || sch || $$_$$ || tbl || $$_pkey_seq'),
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
        CREATE TRIGGER audit_$$ || sch || $$_$$ || tbl || $$_update_trigger
            AFTER UPDATE OR DELETE ON $$ || sch || $$.$$ || tbl || $$ FOR EACH ROW
            EXECUTE PROCEDURE acq.audit_$$ || sch || $$_$$ || tbl || $$_func ();
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION acq.create_acq_lifecycle     ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    EXECUTE $$
        CREATE OR REPLACE VIEW acq.$$ || sch || $$_$$ || tbl || $$_lifecycle AS
            SELECT	-1, now() as audit_time, '-' as audit_action, *
              FROM	$$ || sch || $$.$$ || tbl || $$
                UNION ALL
            SELECT	*
              FROM	acq.$$ || sch || $$_$$ || tbl || $$_history;
    $$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';


-- The main event

CREATE OR REPLACE FUNCTION acq.create_acq_auditor ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
    PERFORM acq.create_acq_seq(sch, tbl);
    PERFORM acq.create_acq_history(sch, tbl);
    PERFORM acq.create_acq_func(sch, tbl);
    PERFORM acq.create_acq_update_trigger(sch, tbl);
    PERFORM acq.create_acq_lifecycle(sch, tbl);
    RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

SELECT acq.create_acq_auditor ( 'acq', 'purchase_order' );
CREATE INDEX acq_po_hist_id_idx            ON acq.acq_purchase_order_history( id );

SELECT acq.create_acq_auditor ( 'acq', 'lineitem' );
CREATE INDEX acq_lineitem_hist_id_idx            ON acq.acq_lineitem_history( id );
CREATE INDEX acq_lineitem_history_queued_record_idx  ON acq.acq_lineitem_history (queued_record);

COMMIT;
