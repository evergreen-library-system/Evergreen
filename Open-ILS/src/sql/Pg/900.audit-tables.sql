DROP SCHEMA auditor CASCADE;

BEGIN;

CREATE SCHEMA auditor;

CREATE FUNCTION auditor.create_auditor ( sch TEXT, tbl TEXT ) RETURNS BOOL AS $creator$
BEGIN
	EXECUTE $$
			CREATE TABLE auditor.$$ || sch || $$_$$ || tbl || $$_history (
				audit_time	TIMESTAMP WITH TIME ZONE	NOT NULL,
				audit_action	CHAR(1)				NOT NULL,
				LIKE $$ || sch || $$.$$ || tbl || $$
			);
	$$;

	EXECUTE $$
			CREATE FUNCTION auditor.audit_$$ || sch || $$_$$ || tbl || $$_func ()
			RETURNS TRIGGER AS $func$
			BEGIN
				INSERT INTO auditor.$$ || sch || $$_$$ || tbl || $$_history
					SELECT now(), SUBSTR(TG_OP,1,1), OLD.*;
				RETURN NULL;
			END;
			$func$ LANGUAGE 'plpgsql';
	$$;

	EXECUTE $$
			CREATE TRIGGER audit_$$ || sch || $$_$$ || tbl || $$_update_trigger
				AFTER UPDATE OR DELETE ON $$ || sch || $$.$$ || tbl || $$ FOR EACH ROW
				EXECUTE PROCEDURE auditor.audit_$$ || sch || $$_$$ || tbl || $$_func ();
	$$;
	RETURN TRUE;
END;
$creator$ LANGUAGE 'plpgsql';

SELECT auditor.create_auditor ( 'actor', 'usr' );
SELECT auditor.create_auditor ( 'biblio', 'record_entry' );
SELECT auditor.create_auditor ( 'asset', 'copy' );

COMMIT;

